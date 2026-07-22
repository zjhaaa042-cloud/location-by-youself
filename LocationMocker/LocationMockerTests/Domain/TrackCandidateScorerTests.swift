import XCTest
@testable import LocationMocker

final class TrackCandidateScorerTests: XCTestCase {
    // 以北京奥体中心附近一点作为用户地图中心
    private let origin = RoutePoint(lat: 39.98, lon: 116.39)

    private func scoredList(_ result: TrackDetectionResult) -> [ScoredTrackCandidate] {
        guard case .candidates(let list) = result else { return [] }
        return list
    }

    /// 检测成功时，跑道中心必须来自候选 POI，而不是用户的地图中心
    /// （回归：曾错误返回 origin，导致跑道生成在地图中心而非体育场）
    func testRanked_successReturnsCandidateCenter() {
        let stadium = RoutePoint(lat: 39.9805, lon: 116.3905)
        let candidate = TrackCandidate(name: "国家奥林匹克体育中心田径场", center: stadium)

        let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: [candidate])

        let list = scoredList(result)
        XCTAssertEqual(list.count, 1, "附近有关键词匹配的候选，应检测成功")
        XCTAssertEqual(list[0].center.lat, stadium.lat, accuracy: 1e-9)
        XCTAssertEqual(list[0].center.lon, stadium.lon, accuracy: 1e-9)
    }

    /// 强关键词候选在 500m 内应被接受
    /// （回归：距离评分曾只奖励 ≤250m，与 500m 搜索半径不匹配，搜得到却被丢弃）
    func testRanked_strongKeywordWithin500mAccepted() {
        // 距 origin 约 400m（0.0036° 纬度 ≈ 400m）
        let far = RoutePoint(lat: 39.9836, lon: 116.39)
        let candidate = TrackCandidate(name: "某大学田径场", center: far)

        let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: [candidate])

        guard case .candidates = result else {
            return XCTFail("400m 内的田径场应被接受")
        }
    }

    /// 超过 500m 的强关键词候选受强惩罚（距离分 -30）：
    /// 阈值放宽到 45 后仍可入列（80-30=50 分），但被压到列表底部，
    /// 由用户结合距离标签自行判断（旧阈值 55 时会被直接拒绝）
    func testRanked_strongKeywordBeyond500mAcceptedButPenalized() {
        // 距 origin 约 1.1km（0.01° 纬度 ≈ 1113m）
        let tooFar = RoutePoint(lat: 39.99, lon: 116.39)
        let candidate = TrackCandidate(name: "田径场", center: tooFar)

        let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: [candidate])

        let list = scoredList(result)
        XCTAssertEqual(list.count, 1, "阈值放宽后强关键词远距候选可入列，供用户选择")
        XCTAssertLessThanOrEqual(list[0].score, 55, ">500m 强惩罚后应低分垫底")
    }

    /// 英文名称 / MKMapItem 分类应被识别
    /// （回归：关键词曾仅中文且大小写敏感，英文区 POI 得 0 分被丢弃）
    func testRanked_englishStadiumAccepted() {
        let stadium = RoutePoint(lat: 39.9805, lon: 116.3905)
        let candidate = TrackCandidate(
            name: "Olympic Stadium",
            center: stadium,
            typeDescription: "MKPOICategoryStadium",
            category: "MKPOICategoryStadium"
        )

        let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: [candidate])

        guard case .candidates = result else {
            return XCTFail("英文体育场 POI 应被识别")
        }
    }

    /// 与跑道无关的 POI 不应被误判
    func testRanked_unrelatedPOINotFound() {
        let cafe = TrackCandidate(name: "星巴克咖啡", center: RoutePoint(lat: 39.9801, lon: 116.3901))

        let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: [cafe])

        guard case .notFound = result else {
            return XCTFail("无关 POI 不应被识别为操场")
        }
    }

    // MARK: - 问题 1 新增：准确率改进

    /// 明显无关类别（餐厅等）即使名字含强关键词也应 0 分过滤
    func testRanked_irrelevantCategoryFiltered() {
        let restaurant = TrackCandidate(
            name: "操场主题餐厅",
            center: RoutePoint(lat: 39.9805, lon: 116.3905),
            category: "MKPOICategoryRestaurant"
        )

        let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: [restaurant])

        guard case .notFound = result else {
            return XCTFail("餐厅类别应被过滤，即使名字含「操场」")
        }
    }

    /// 体育场类别加分：弱关键词 + 体育场类别应过阈值
    func testRanked_stadiumCategoryBoostsWeakKeyword() {
        let center = RoutePoint(lat: 39.982, lon: 116.39) // 约 222m
        let candidate = TrackCandidate(
            name: "某体育中心",
            center: center,
            category: "MKPOICategoryStadium"
        )

        let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: [candidate])

        guard case .candidates = result else {
            return XCTFail("弱关键词 + 体育场类别应被接受")
        }
    }

    /// 纯弱关键词降权：无类别支撑、距离较远（>400m）时仍过不了 45 阈值
    /// （基础分 40 后，纯弱关键词的可接受距离上限约为 400m：40+25×(1-d/500) < 45 ⟺ d > 400）
    func testRanked_bareWeakKeywordDowngraded() {
        let center = RoutePoint(lat: 39.98405, lon: 116.39) // 约 450m
        let candidate = TrackCandidate(name: "某体育中心", center: center)

        let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: [candidate])

        guard case .notFound = result else {
            return XCTFail("纯弱关键词在 450m 外应被拒绝（降权）")
        }
    }

    /// 名称含强关键词的候选应比纯弱关键词候选得分更高
    func testScore_strongNameBeatsWeakName() {
        let center = RoutePoint(lat: 39.981, lon: 116.39) // 约 111m
        let strong = TrackCandidate(name: "市民田径场", center: center)
        let weak = TrackCandidate(name: "市民体育中心", center: center)

        let strongScore = TrackCandidateScorer.score(origin: origin, candidate: strong)
        let weakScore = TrackCandidateScorer.score(origin: origin, candidate: weak)

        XCTAssertGreaterThan(strongScore, weakScore)
    }

    /// 邻近去重：相距 <150m 的多个搜索结果合并为一个候选，保留评分最高者
    func testRanked_nearbyDuplicatesMerged() {
        // 两者相距约 40m，指向同一物理操场
        let better = TrackCandidate(
            name: "朝阳体育场田径场",
            center: RoutePoint(lat: 39.981, lon: 116.39) // 约 111m
        )
        let worse = TrackCandidate(
            name: "田径场",
            center: RoutePoint(lat: 39.9813, lon: 116.3902) // 约 160m
        )

        let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: [worse, better])

        let list = scoredList(result)
        XCTAssertEqual(list.count, 1, "同一物理地点的重复结果应合并")
        XCTAssertEqual(list[0].name, "朝阳体育场田径场", "应保留评分最高者的名字")
    }

    /// 相距 >150m 的两个候选不应被合并
    func testRanked_distinctPlacesNotMerged() {
        let a = TrackCandidate(name: "大学田径场", center: RoutePoint(lat: 39.981, lon: 116.39))
        let b = TrackCandidate(name: "中学操场", center: RoutePoint(lat: 39.983, lon: 116.39)) // 相距约 222m

        let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: [a, b])

        XCTAssertEqual(scoredList(result).count, 2)
    }

    /// 候选列表按分数降序，且最多保留 maxCandidates（8）个
    func testRanked_sortedDescendingAndCappedAtMax() {
        // 8 个方向各放一个 300m 处的强关键词候选（相邻约 230m，不会触发去重）
        let deltaLat = 0.001905   // ≈212m
        let deltaLon = 0.002487   // ≈212m（39.98°N）
        var offsets: [(Double, Double)] = [
            (0.002695, 0), (-0.002695, 0), (0, 0.003517), (0, -0.003517),
            (deltaLat, deltaLon), (deltaLat, -deltaLon), (-deltaLat, deltaLon), (-deltaLat, -deltaLon)
        ]
        // 再加 4 个 ~460m 处的强关键词候选（与 300m 候选相距 >150m，不去重），
        // 总数 12 > 上限 8，验证截断
        offsets += [(0.0042, 0), (-0.0042, 0), (0, 0.0054), (0, -0.0054)]
        let candidates = offsets.enumerated().map { i, o in
            TrackCandidate(name: "田径场\(i)", center: RoutePoint(lat: origin.lat + o.0, lon: origin.lon + o.1))
        }

        let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: candidates)

        let list = scoredList(result)
        XCTAssertEqual(list.count, TrackCandidateScorer.maxCandidates, "候选最多保留 8 个")
        for i in 0..<(list.count - 1) {
            XCTAssertGreaterThanOrEqual(list[i].score, list[i + 1].score, "候选应按分数降序")
        }
    }

    /// 不同距离的候选按分数降序（近的在前）
    func testRanked_nearerCandidateRanksFirst() {
        let near = TrackCandidate(name: "近处田径场", center: RoutePoint(lat: 39.9809, lon: 116.39))  // ≈100m
        let mid = TrackCandidate(name: "中距田径场", center: RoutePoint(lat: 39.98225, lon: 116.39)) // ≈250m
        let far = TrackCandidate(name: "远处田径场", center: RoutePoint(lat: 39.9836, lon: 116.39))  // ≈400m

        let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: [far, mid, near])

        let names = scoredList(result).map(\.name)
        XCTAssertEqual(names, ["近处田径场", "中距田径场", "远处田径场"])
    }

    // MARK: - 2026-07-19 阈值放宽（55→45 / 弱关键词 35→40 / +田径泛匹配 / 上限 5→8）

    /// 「XX 运动场」（强关键词）在 ~350m 处应能进入候选列表（用户反馈此前进不了候选）
    func testRanked_sportsFieldNameAt350mAccepted() {
        let center = RoutePoint(lat: 39.98315, lon: 116.39) // ≈350m
        let candidate = TrackCandidate(name: "长风公园运动场", center: center)

        let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: [candidate])

        guard case .candidates = result else {
            return XCTFail("350m 处的「运动场」应能进入候选列表")
        }
    }

    /// 「XX 体育场」（纯弱关键词、无类别）在 ~150m 处应过 45 阈值
    /// （旧阈值 55 + 旧基础分 35 时仅得 53 分被拒）
    func testRanked_weakKeywordStadiumAt150mAccepted() {
        let center = RoutePoint(lat: 39.98135, lon: 116.39) // ≈150m
        let candidate = TrackCandidate(name: "长风体育场", center: center)

        let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: [candidate])

        guard case .candidates = result else {
            return XCTFail("150m 处的「体育场」（弱关键词）应过阈值")
        }
    }

    /// 「田径」泛匹配：名称不含「田径场」但含「田径」（如"市田径中心"）也应被识别
    func testRanked_trackKeywordLooseMatchAccepted() {
        let center = RoutePoint(lat: 39.9805, lon: 116.3905) // ≈70m
        let candidate = TrackCandidate(name: "市田径中心", center: center)

        let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: [candidate])

        guard case .candidates = result else {
            return XCTFail("「市田径中心」应被「田径」泛匹配识别")
        }
    }
}
