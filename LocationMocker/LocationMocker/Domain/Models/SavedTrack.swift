import Foundation

/// 一条已保存的跑道。跑道是参数化生成的（标准两直道 + 两半圆），
/// 只需保存生成参数即可随时用 `TrackRoutePlanner.generateOvalTrack` 精确重建，
/// 不需要存储整条折线。
struct SavedTrack: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var center: RoutePoint
    var perimeterMeters: Double
    var rotationDegrees: Double
    /// 回放起点沿跑道的弧长偏移（米）
    var startOffsetMeters: Double
    /// true = 顺时针跑动
    var clockwise: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        center: RoutePoint,
        perimeterMeters: Double,
        rotationDegrees: Double,
        startOffsetMeters: Double,
        clockwise: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.center = center
        self.perimeterMeters = perimeterMeters
        self.rotationDegrees = rotationDegrees
        self.startOffsetMeters = startOffsetMeters
        self.clockwise = clockwise
        self.createdAt = createdAt
    }
}
