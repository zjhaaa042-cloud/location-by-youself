import XCTest
@testable import LocationMocker

final class TrackRoutePlannerGeometryTests: XCTestCase {
    // 浙大城市学院附近（用户反馈偏移问题的实际地点）
    private let center = RoutePoint(lat: 30.2700, lon: 120.1500)
    private let planner = TrackRoutePlanner()

    /// 闭环周长（含首尾闭合段）
    private func perimeter(of points: [RoutePoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for i in 0..<(points.count - 1) {
            total += RouteMath.distanceMeters(points[i], points[i + 1])
        }
        total += RouteMath.distanceMeters(points.last!, points.first!)
        return total
    }

    /// 投影到本地米制坐标后的 x/y 跨度
    private func projectedExtents(of points: [RoutePoint], origin: RoutePoint) -> (x: Double, y: Double) {
        let proj = TrackRoutePlanner.LocalProjection(origin: origin)
        let ps = points.map { proj.project($0) }
        let xs = ps.map(\.x)
        let ys = ps.map(\.y)
        return (xs.max()! - xs.min()!, ys.max()! - ys.min()!)
    }

    /// 周长按请求值生成（48 点离散化以弦逼近弧，周长会略小于连续几何值，允许 1.5m 误差）
    func testGenerate_requestedPerimeter400m() {
        let points = planner.generateOvalTrack(center: center, perimeterMeters: 400)
        XCTAssertEqual(perimeter(of: points), 400, accuracy: 1.5)
    }

    /// 周长缩放到 200m：总长正确且尺寸约为 400m 场的一半（保持标准几何比例）
    func testGenerate_scaledPerimeter200m() {
        let small = planner.generateOvalTrack(center: center, perimeterMeters: 200)
        let big = planner.generateOvalTrack(center: center, perimeterMeters: 400)
        XCTAssertEqual(perimeter(of: small), 200, accuracy: 1.0)
        let eS = projectedExtents(of: small, origin: center)
        let eB = projectedExtents(of: big, origin: center)
        XCTAssertEqual(eS.x, eB.x / 2, accuracy: 1.0)
        XCTAssertEqual(eS.y, eB.y / 2, accuracy: 1.0)
    }

    /// 跑道质心必须落在请求的中心点上（平移正确性）
    /// （显式闭环后数组末点是首点副本，平均时剔除重复点）
    func testGenerate_centroidMatchesCenter() {
        var points = planner.generateOvalTrack(center: center, perimeterMeters: 400, rotationDegrees: 25)
        if points.first == points.last { points.removeLast() }
        let avgLat = points.map(\.lat).reduce(0, +) / Double(points.count)
        let avgLon = points.map(\.lon).reduce(0, +) / Double(points.count)
        XCTAssertEqual(avgLat, center.lat, accuracy: 1e-6)
        XCTAssertEqual(avgLon, center.lon, accuracy: 1e-6)
    }

    /// 旋转不改变跑道周长（纯刚体变换）
    func testGenerate_rotationPreservesPerimeter() {
        let base = perimeter(of: planner.generateOvalTrack(center: center, perimeterMeters: 400, rotationDegrees: 0))
        let rotated = perimeter(of: planner.generateOvalTrack(center: center, perimeterMeters: 400, rotationDegrees: 37))
        XCTAssertEqual(base, rotated, accuracy: 0.05)
    }

    /// 旋转 90° 后 x/y 跨度互换
    func testGenerate_rotation90SwapsExtents() {
        let p0 = planner.generateOvalTrack(center: center, perimeterMeters: 400, rotationDegrees: 0)
        let p90 = planner.generateOvalTrack(center: center, perimeterMeters: 400, rotationDegrees: 90)
        let e0 = projectedExtents(of: p0, origin: center)
        let e90 = projectedExtents(of: p90, origin: center)
        XCTAssertEqual(e0.x, e90.y, accuracy: 0.5)
        XCTAssertEqual(e0.y, e90.x, accuracy: 0.5)
    }

    /// 微调平移：向正北 10m
    func testTranslated_northTenMeters() {
        let moved = TrackRoutePlanner.translated(center, northMeters: 10, eastMeters: 0)
        XCTAssertEqual(RouteMath.distanceMeters(center, moved), 10, accuracy: 0.05)
        XCTAssertEqual(Double(RouteMath.bearingDegrees(center, moved)), 0, accuracy: 1)
    }

    /// 微调平移：向正东 10m
    func testTranslated_eastTenMeters() {
        let moved = TrackRoutePlanner.translated(center, northMeters: 0, eastMeters: 10)
        XCTAssertEqual(RouteMath.distanceMeters(center, moved), 10, accuracy: 0.05)
        XCTAssertEqual(Double(RouteMath.bearingDegrees(center, moved)), 90, accuracy: 1)
    }

    // MARK: - 问题 2 新增：闭环 / 均匀点距 / 起点偏移

    /// 显式闭环：最后一点与第一点坐标完全相同
    func testGenerate_explicitlyClosed() {
        let points = planner.generateOvalTrack(center: center, perimeterMeters: 400)
        XCTAssertGreaterThanOrEqual(points.count, 3)
        XCTAssertEqual(points.first, points.last, "最后一点必须等于第一点（显式闭环）")
    }

    /// 相邻点距全数组均匀（含回绕段，误差容忍 ±5%）
    func testGenerate_uniformPointSpacing() {
        let points = planner.generateOvalTrack(center: center, perimeterMeters: 400)
        let core = Array(points.dropLast()) // 去掉闭合副本点
        var gaps: [Double] = []
        for i in 0..<core.count {
            gaps.append(RouteMath.distanceMeters(core[i], core[(i + 1) % core.count]))
        }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        XCTAssertEqual(mean, 5, accuracy: 0.5, "平均点距应约等于 5m 采样间隔")
        for (i, g) in gaps.enumerated() {
            XCTAssertEqual(g, mean, accuracy: mean * 0.05, "第 \(i) 段点距不均匀：\(g)m，均值 \(mean)m")
        }
    }

    /// 总周长（含首尾闭合段）≈ 目标周长（±2%）
    func testGenerate_totalPerimeterWithinTwoPercent() {
        let points = planner.generateOvalTrack(center: center, perimeterMeters: 400)
        var total = 0.0
        for i in 0..<(points.count - 1) {
            total += RouteMath.distanceMeters(points[i], points[i + 1])
        }
        XCTAssertEqual(total, 400, accuracy: 400 * 0.02)
    }

    /// startOffset 旋转后：起点坐标沿跑道弧长偏移 ≈ 指定米数，且仍闭环
    func testGenerate_startOffsetRotatesStart() {
        let base = planner.generateOvalTrack(center: center, perimeterMeters: 400, startOffsetMeters: 0)
        let shifted = planner.generateOvalTrack(center: center, perimeterMeters: 400, startOffsetMeters: 100)

        // 偏移后仍显式闭环
        XCTAssertEqual(shifted.first, shifted.last)

        // 偏移后的起点应落在基准跑道弧长 100m 处的采样点上（100m / 5m = 第 20 个采样点）
        XCTAssertEqual(RouteMath.distanceMeters(shifted[0], base[20]), 0, accuracy: 0.01)

        // 沿基准跑道从 base[0] 到 base[20] 的弧长 ≈ 100m（±1%）
        var arc = 0.0
        for i in 0..<20 {
            arc += RouteMath.distanceMeters(base[i], base[i + 1])
        }
        XCTAssertEqual(arc, 100, accuracy: 1.0)
    }

    /// startOffset 不改变周长与点距（纯相位旋转）
    func testGenerate_startOffsetPreservesGeometry() {
        let base = perimeter(of: planner.generateOvalTrack(center: center, perimeterMeters: 400, startOffsetMeters: 0))
        let shifted = perimeter(of: planner.generateOvalTrack(center: center, perimeterMeters: 400, startOffsetMeters: 137))
        XCTAssertEqual(base, shifted, accuracy: 0.5)
    }

    // MARK: - 顺时针 / 逆时针跑动方向

    /// 投影到本地米制坐标后的有向面积（鞋带公式，x 向东 / y 向北）：
    /// 符号表示遍历方向，北向上视角顺时针为负、逆时针为正
    private func signedArea(of points: [RoutePoint], origin: RoutePoint) -> Double {
        let proj = TrackRoutePlanner.LocalProjection(origin: origin)
        var ps = points.map { proj.project($0) }
        if ps.first?.x == ps.last?.x, ps.first?.y == ps.last?.y { ps.removeLast() }
        var sum = 0.0
        for i in 0..<ps.count {
            let a = ps[i]
            let b = ps[(i + 1) % ps.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    /// 逆时针 = 同一闭合曲线的反向遍历：有向面积符号相反、绝对值一致，
    /// 且两种方向的采样点集合相同（每个点都能在对方找到 1cm 内的对应点）
    func testGenerate_counterclockwiseReversesTraversal() {
        let cw = planner.generateOvalTrack(center: center, perimeterMeters: 400, clockwise: true)
        let ccw = planner.generateOvalTrack(center: center, perimeterMeters: 400, clockwise: false)
        XCTAssertEqual(cw.count, ccw.count)

        let areaCW = signedArea(of: cw, origin: center)
        let areaCCW = signedArea(of: ccw, origin: center)
        XCTAssertLessThan(areaCW, 0, "北向上视角顺时针的有向面积应为负")
        XCTAssertGreaterThan(areaCCW, 0, "北向上视角逆时针的有向面积应为正")
        XCTAssertEqual(areaCW, -areaCCW, accuracy: abs(areaCW) * 0.001, "两种方向围成的面积绝对值应一致")

        // 采样点集合相同（顺序相反）：每个顺时针点都能在逆时针结果中找到 1cm 内对应点
        for p in cw {
            let matched = ccw.contains { RouteMath.distanceMeters($0, p) < 0.01 }
            XCTAssertTrue(matched, "逆时针结果中找不到与顺时针点 (\(p.lat), \(p.lon)) 对应的采样点")
        }
    }

    /// startOffset 相同时两种方向的首点（物理起点）坐标完全相同
    func testGenerate_sameStartPointBothDirections() {
        for offset in [0.0, 137.0] {
            let cw = planner.generateOvalTrack(center: center, perimeterMeters: 400, startOffsetMeters: offset, clockwise: true)
            let ccw = planner.generateOvalTrack(center: center, perimeterMeters: 400, startOffsetMeters: offset, clockwise: false)
            XCTAssertEqual(RouteMath.distanceMeters(cw[0], ccw[0]), 0, accuracy: 0.001,
                           "startOffset=\(offset) 时两种方向的起点应相同")
        }
    }

    /// 逆时针仍显式闭环、点距均匀、周长不变
    func testGenerate_counterclockwiseClosedUniformPerimeter() {
        let ccw = planner.generateOvalTrack(center: center, perimeterMeters: 400, clockwise: false)
        XCTAssertEqual(ccw.first, ccw.last, "逆时针也必须显式闭环")

        let core = Array(ccw.dropLast())
        var gaps: [Double] = []
        for i in 0..<core.count {
            gaps.append(RouteMath.distanceMeters(core[i], core[(i + 1) % core.count]))
        }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        XCTAssertEqual(mean, 5, accuracy: 0.5, "逆时针平均点距应约等于 5m 采样间隔")
        for (i, g) in gaps.enumerated() {
            XCTAssertEqual(g, mean, accuracy: mean * 0.05, "逆时针第 \(i) 段点距不均匀：\(g)m")
        }

        let cw = planner.generateOvalTrack(center: center, perimeterMeters: 400, clockwise: true)
        XCTAssertEqual(perimeter(of: ccw), perimeter(of: cw), accuracy: 0.05, "方向反转不应改变周长")
    }

    /// 向后兼容：不传 clockwise 参数的结果与显式顺时针完全一致
    func testGenerate_defaultMatchesClockwise() {
        let legacy = planner.generateOvalTrack(center: center, perimeterMeters: 400)
        let explicitCW = planner.generateOvalTrack(center: center, perimeterMeters: 400, clockwise: true)
        XCTAssertEqual(legacy, explicitCW, "默认参数必须与顺时针结果逐点一致（向后兼容）")
    }
}
