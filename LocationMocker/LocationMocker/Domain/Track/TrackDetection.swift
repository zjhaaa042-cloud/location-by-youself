import Foundation

struct TrackCandidate {
    let name: String
    let center: RoutePoint
    let typeDescription: String
    /// MapKit POI 类别原始值（MKPointOfInterestCategory.rawValue），用于类别加分/过滤
    let category: String
    let distanceMeters: Double

    init(name: String, center: RoutePoint, typeDescription: String = "", category: String = "", distanceMeters: Double = 0) {
        self.name = name
        self.center = center
        self.typeDescription = typeDescription
        self.category = category
        self.distanceMeters = distanceMeters
    }
}

/// 带评分的候选（评分器输出，按分数降序交给 UI 选择）
struct ScoredTrackCandidate {
    let candidate: TrackCandidate
    let score: Int

    var name: String { candidate.name.isEmpty ? "附近操场" : candidate.name }
    var center: RoutePoint { candidate.center }
    var distanceMeters: Double { candidate.distanceMeters }

    /// 可信度标签：高 / 中（供候选列表展示）
    var confidenceLabel: String { score >= 80 ? "高" : "中" }
}

enum TrackDetectionResult {
    /// 排序后的候选列表（分数降序，最多 8 个）；调用方在多个候选时让用户选择
    case candidates([ScoredTrackCandidate])
    case notFound(reason: String)
}

enum TrackCandidateScorer {
    // 「田径」做泛匹配（如"市田径中心"），是「田径场」「田径馆」的子串，不改变原有匹配行为
    private static let strongKeywords = ["操场", "田径场", "田径馆", "田径", "运动场", "跑道", "track and field", "track"]
    private static let weakKeywords = ["体育场", "体育中心", "运动中心", "足球场", "体育馆", "奥体", "stadium", "sports", "field", "arena"]

    /// 加分类别（rawValue 片段，小写比较）：体育场/公园/学校更可能有跑道
    private static let boostedCategories: [(token: String, bonus: Int)] = [
        ("mkpoicategorystadium", 15),
        ("mkpoicategorypark", 8),
        ("mkpoicategoryschool", 8),
        ("mkpoicategoryuniversity", 8)
    ]

    /// 明显无关类别直接 0 分过滤（餐饮、商店、医院等不可能有跑道）
    private static let rejectedCategoryTokens = [
        "mkpoicategoryrestaurant", "mkpoicategorycafe", "mkpoicategorybakery",
        "mkpoicategorystore", "mkpoicategoryfoodmarket", "mkpoicategorygasstation",
        "mkpoicategoryhospital", "mkpoicategorypharmacy", "mkpoicategorybank",
        "mkpoicategoryatm", "mkpoicategoryhotel", "mkpoicategorylaundry",
        "mkpoicategorynightlife", "mkpoicategorywinery", "mkpoicategorybrewery",
        "mkpoicategorybeauty", "mkpoicategoryanimalservices", "mkpoicategorycarshop"
    ]

    /// 评分阈值：低于此分数的候选直接丢弃（2026-07-19 由 55 放宽到 45，
    /// 让「XX 运动场 / XX 田径场」类名称在 300–400m 距离也能进入候选列表）
    static let acceptanceThreshold = 45
    /// 邻近去重半径：相距小于此值的候选视为同一物理地点
    static let dedupRadiusMeters: Double = 150
    /// 候选列表最大返回数量
    static let maxCandidates = 8

    /// 评分 + 邻近去重 + 排序，返回候选列表（降序，最多 8 个）
    static func rankedCandidates(origin: RoutePoint, candidates: [TrackCandidate]) -> TrackDetectionResult {
        let merged = deduplicate(origin: origin, candidates: candidates)
        let scored = merged
            .map { ScoredTrackCandidate(candidate: $0, score: score(origin: origin, candidate: $0)) }
            .filter { $0.score >= acceptanceThreshold }
            .sorted { $0.score > $1.score }
        guard !scored.isEmpty else {
            return .notFound(reason: "附近未识别到操场")
        }
        return .candidates(Array(scored.prefix(maxCandidates)))
    }

    /// 邻近去重/聚合：多个搜索结果指向同一物理地点（<150m）时合并，
    /// 保留评分最高者的坐标和名字，避免同一操场出现多次干扰选择
    static func deduplicate(origin: RoutePoint, candidates: [TrackCandidate]) -> [TrackCandidate] {
        let sorted = candidates.sorted {
            score(origin: origin, candidate: $0) > score(origin: origin, candidate: $1)
        }
        var kept: [TrackCandidate] = []
        for candidate in sorted {
            let isDuplicate = kept.contains {
                RouteMath.distanceMeters($0.center, candidate.center) < dedupRadiusMeters
            }
            if !isDuplicate { kept.append(candidate) }
        }
        return kept
    }

    static func score(origin: RoutePoint, candidate: TrackCandidate) -> Int {
        let text = "\(candidate.name) \(candidate.typeDescription) \(candidate.category)".lowercased()

        // 明显无关类别直接 0 分过滤
        if rejectedCategoryTokens.contains(where: text.contains) { return 0 }

        let nameText = candidate.name.lowercased()
        let keywordScore: Int
        if strongKeywords.contains(where: text.contains) {
            // 名称本身含强关键词（如就叫"XX 操场/田径场"）额外加分
            keywordScore = 70 + (strongKeywords.contains(where: nameText.contains) ? 10 : 0)
        } else if weakKeywords.contains(where: text.contains) {
            // 纯弱关键词降权，需类别或近距离支撑才能过阈值（基础分 35 → 40，配合阈值放宽）
            keywordScore = 40
        } else {
            return 0
        }

        // POI 类别加分（取最高一档）
        let categoryBonus = boostedCategories.first(where: { text.contains($0.token) })?.bonus ?? 0

        let distance = candidate.distanceMeters > 0
            ? candidate.distanceMeters
            : RouteMath.distanceMeters(origin, candidate.center)
        // 平滑线性衰减：0m → 25 分，500m → 0 分；超过 500m 强惩罚
        let distanceScore = distance > 500 ? -30.0 : 25.0 * (1.0 - distance / 500.0)

        let total = Double(keywordScore + categoryBonus) + distanceScore
        return min(max(Int(total.rounded()), 0), 100)
    }
}
