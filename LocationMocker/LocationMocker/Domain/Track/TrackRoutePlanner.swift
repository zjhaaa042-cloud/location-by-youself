import Foundation

struct TrackRoutePlanner {

    // MARK: - 标准跑道几何常量（400m 标准场：两条直道 + 两个半圆弯）

    static let standardStraightMeters = 84.39
    static let standardRadiusMeters = 36.5

    /// 标准 400m 场的实际几何周长（两直道 + 两整圆弯）
    static var standardPerimeterMeters: Double {
        2 * standardStraightMeters + 2 * .pi * standardRadiusMeters
    }

    struct LocalProjection {
        let origin: RoutePoint
        private let metersPerDegreeLat = 111_320.0
        private let metersPerDegreeLon: Double

        init(origin: RoutePoint) {
            self.origin = origin
            self.metersPerDegreeLon = 111_320.0 * cos(origin.lat * .pi / 180.0)
        }

        func project(_ point: RoutePoint) -> ProjectedPoint {
            ProjectedPoint(
                x: (point.lon - origin.lon) * metersPerDegreeLon,
                y: (point.lat - origin.lat) * metersPerDegreeLat
            )
        }

        func unproject(_ point: ProjectedPoint) -> RoutePoint {
            RoutePoint(
                lat: origin.lat + point.y / metersPerDegreeLat,
                lon: origin.lon + point.x / metersPerDegreeLon
            )
        }
    }

    struct ProjectedPoint {
        let x: Double
        let y: Double
    }

    /// 弧长参数化采样点距（米）：约每 5m 一个点，全程点距均匀
    static let defaultSampleSpacingMeters = 5.0

    /// 生成标准跑道（两条直道 + 两个半圆弯）
    ///
    /// 弧长参数化采样：把体育场曲线按周长均匀采样（点距约 5m，采样数取偶），
    /// 消除直道/弯道拼接处的点距差；返回数组**显式闭环**（最后一点 == 第一点）。
    /// - Parameters:
    ///   - center: 跑道中心，支持平移到任意位置（POI 坐标或地图中心均可）
    ///   - perimeterMeters: 目标周长，按标准 400m 场几何等比缩放（直道/弯道比例保持不变）
    ///   - rotationDegrees: 绕中心整体旋转角度（0° 时直道沿东西方向）
    ///   - startOffsetMeters: 回放起点沿跑道的弧长偏移（0m = 第 1 直道起点，
    ///     顺跑动方向沿跑道量），采样点整体旋转后仍保持闭环
    ///   - clockwise: 跑动方向。`true`（默认）= 北向上视角顺时针（第 1 直道
    ///     西向东 → 右弯下行），与历史行为完全一致；`false` = 同一物理起点
    ///     沿跑道反向行进（采样相位取反 `s = offset − i·step`），
    ///     startOffsetMeters 语义不变、末点仍 = 首点闭环
    func generateOvalTrack(
        center: RoutePoint,
        perimeterMeters: Double = TrackRoutePlanner.standardPerimeterMeters,
        rotationDegrees: Double = 0,
        startOffsetMeters: Double = 0,
        clockwise: Bool = true
    ) -> [RoutePoint] {
        let projection = LocalProjection(origin: center)
        let scale = perimeterMeters / TrackRoutePlanner.standardPerimeterMeters
        let straightLen = TrackRoutePlanner.standardStraightMeters * scale
        let radius = TrackRoutePlanner.standardRadiusMeters * scale
        let curveLen = Double.pi * radius
        let total = 2 * straightLen + 2 * curveLen
        let theta = rotationDegrees * .pi / 180
        let cosT = cos(theta)
        let sinT = sin(theta)

        /// 按弧长取曲线上的点（本地米制坐标，未旋转）：
        /// s ∈ [0, total)，0m 位于第 1 直道起点（左上端），沿跑动方向前进
        func pointOnCurve(at rawS: Double) -> ProjectedPoint {
            var s = rawS.truncatingRemainder(dividingBy: total)
            if s < 0 { s += total }
            let halfStraight = straightLen / 2
            switch s {
            case ..<straightLen:
                // 第 1 直道（从左到右）
                return ProjectedPoint(x: -halfStraight + s, y: radius)
            case ..<(straightLen + curveLen):
                // 右半圆弯（π/2 → -π/2）
                let angle = Double.pi / 2 - (s - straightLen) / radius
                return ProjectedPoint(x: halfStraight + radius * cos(angle), y: radius * sin(angle))
            case ..<(2 * straightLen + curveLen):
                // 第 2 直道（从右到左）
                let d = s - straightLen - curveLen
                return ProjectedPoint(x: halfStraight - d, y: -radius)
            default:
                // 左半圆弯（-π/2 → -3π/2）
                let angle = -Double.pi / 2 - (s - 2 * straightLen - curveLen) / radius
                return ProjectedPoint(x: -halfStraight + radius * cos(angle), y: radius * sin(angle))
            }
        }

        // 均匀采样：采样数取偶（保证对蹠点成对、质心居中），点距 ≈ 5m
        let sampleCount = max(16, 2 * Int((total / TrackRoutePlanner.defaultSampleSpacingMeters / 2).rounded()))
        let step = total / Double(sampleCount)
        let offset = startOffsetMeters.truncatingRemainder(dividingBy: total)
        // 行进方向：+1 顺曲线弧长方向（北向上视角顺时针，历史行为）；
        // -1 相位取反（s = offset − i·step），同一物理起点反向行进
        let direction: Double = clockwise ? 1 : -1

        var points = [RoutePoint]()
        points.reserveCapacity(sampleCount + 1)
        for i in 0..<sampleCount {
            let p = pointOnCurve(at: offset + direction * Double(i) * step)
            // 绕中心旋转后再投影回经纬度
            let rx = p.x * cosT - p.y * sinT
            let ry = p.x * sinT + p.y * cosT
            points.append(projection.unproject(ProjectedPoint(x: rx, y: ry)))
        }
        // 显式闭环：追加起点副本，MapPolyline 画出来闭合、回放 loop 无缝
        if let first = points.first {
            points.append(first)
        }
        return points
    }

    /// 将某点向正北/正东平移指定米数（用于跑道位置微调）
    static func translated(_ point: RoutePoint, northMeters: Double, eastMeters: Double) -> RoutePoint {
        LocalProjection(origin: point).unproject(ProjectedPoint(x: eastMeters, y: northMeters))
    }
}
