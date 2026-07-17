import Foundation

struct SegmentedTrack {
    let name: String
    let center: RoutePoint
    let segments: [[RoutePoint]]

    var allPoints: [RoutePoint] { segments.flatMap { $0 } }

    init(name: String, center: RoutePoint, segments: [[RoutePoint]]) {
        self.name = name
        self.center = center
        self.segments = segments
    }
}
