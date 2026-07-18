import Foundation

struct TrackRoutePlanner {

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

    /// Generate a standard 400m oval track centered at the given point.
    func generateOvalTrack(center: RoutePoint, orientation: TrackOrientation) -> [RoutePoint] {
        let projection = LocalProjection(origin: center)
        let straightLen: Double = 84.39  // meters
        let radius: Double = 36.5         // meters
        let segments = 24
        var points = [RoutePoint]()

        // Top straight (left to right, lane 1)
        let halfStraight = straightLen / 2
        for s in 0...segments / 2 {
            let frac = Double(s) / Double(segments / 2)
            let x = -halfStraight + straightLen * frac
            let y = radius
            let (mappedX, mappedY) = orientation == .vertical ? (x, y) : (y, x)
            points.append(projection.unproject(ProjectedPoint(x: mappedX, y: mappedY)))
        }

        // Right curve
        for s in 1..<segments / 2 {
            let angle = .pi / 2 - Double(s) / Double(segments / 2) * .pi
            let x = halfStraight + radius * cos(angle)
            let y = radius * sin(angle)
            let (mappedX, mappedY) = orientation == .vertical ? (x, y) : (y, x)
            points.append(projection.unproject(ProjectedPoint(x: mappedX, y: mappedY)))
        }

        // Bottom straight (right to left)
        for s in 0...segments / 2 {
            let frac = Double(s) / Double(segments / 2)
            let x = halfStraight - straightLen * frac
            let y = -radius
            let (mappedX, mappedY) = orientation == .vertical ? (x, y) : (y, x)
            points.append(projection.unproject(ProjectedPoint(x: mappedX, y: mappedY)))
        }

        // Left curve
        for s in 1..<segments / 2 {
            let angle = -.pi / 2 - Double(s) / Double(segments / 2) * .pi
            let x = -halfStraight + radius * cos(angle)
            let y = radius * sin(angle)
            let (mappedX, mappedY) = orientation == .vertical ? (x, y) : (y, x)
            points.append(projection.unproject(ProjectedPoint(x: mappedX, y: mappedY)))
        }

        return points
    }
}
