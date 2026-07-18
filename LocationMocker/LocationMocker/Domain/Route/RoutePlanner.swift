import Foundation

final class RoutePlanner {

    func buildSamples(config: SimulationConfig) -> [RouteSample] {
        let points = config.points
        guard !points.isEmpty else { return [] }
        if points.count == 1 {
            return [RouteSample(point: points[0], speedMetersPerSecond: 0, bearingDegrees: 0)]
        }

        let smoothPolyline = buildSmoothPolyline(points)
        let stepMeters = Double(RouteMath.speedKmhToMetersPerSecond(config.speedKmh)) *
            (Double(config.updateIntervalMs) / 1000.0)
        let sampled = sampleByDistance(smoothPolyline, stepMeters: max(1.0, stepMeters))

        return sampled.enumerated().map { index, point in
            let next = sampled.indices.contains(index + 1) ? sampled[index + 1] : (index > 0 ? sampled[index - 1] : point)
            return RouteSample(
                point: point,
                speedMetersPerSecond: RouteMath.speedKmhToMetersPerSecond(config.speedKmh),
                bearingDegrees: RouteMath.bearingDegrees(point, next)
            )
        }
    }

    func buildSmoothPolyline(_ points: [RoutePoint]) -> [RoutePoint] {
        guard points.count > 2 else { return densifyLinear(points) }

        let projection = LocalProjection(origin: points[0])
        let projected = points.map(projection.project)
        var result = [RoutePoint]()

        for i in 0..<(projected.count - 1) {
            let p0 = projected.indices.contains(i - 1) ? projected[i - 1] : projected[i]
            let p1 = projected[i]
            let p2 = projected[i + 1]
            let p3 = projected.indices.contains(i + 2) ? projected[i + 2] : projected[i + 1]
            let distance = p1.distanceTo(p2)
            let samples = max(8, Int((distance / 20.0).rounded()))

            for s in 0..<samples {
                let t = Double(s) / Double(samples)
                let x = catmullRom(p0.x, p1.x, p2.x, p3.x, t: t)
                let y = catmullRom(p0.y, p1.y, p2.y, p3.y, t: t)
                result.append(projection.unproject(ProjectedPoint(x: x, y: y)))
            }
        }
        result.append(points.last!)
        return removeNearDuplicates(result)
    }

    private func densifyLinear(_ points: [RoutePoint]) -> [RoutePoint] {
        guard points.count > 1 else { return points }
        var result = [RoutePoint]()
        for i in 0..<(points.count - 1) {
            let start = points[i], end = points[i + 1]
            let distance = RouteMath.distanceMeters(start, end)
            let samples = max(1, Int((distance / 20.0).rounded()))
            for s in 0..<samples {
                result.append(RouteMath.interpolate(start, end, fraction: Double(s) / Double(samples)))
            }
        }
        result.append(points.last!)
        return removeNearDuplicates(result)
    }

    private func sampleByDistance(_ polyline: [RoutePoint], stepMeters: Double) -> [RoutePoint] {
        guard polyline.count > 1 else { return polyline }
        var result = [polyline[0]]
        var segmentStartIndex = 0
        var targetDistance = stepMeters

        var cumulative = [0.0]
        for i in 0..<(polyline.count - 1) {
            cumulative.append(cumulative.last! + RouteMath.distanceMeters(polyline[i], polyline[i + 1]))
        }
        let totalDistance = cumulative.last!

        while targetDistance < totalDistance {
            while segmentStartIndex < cumulative.count - 2 &&
                    cumulative[segmentStartIndex + 1] < targetDistance {
                segmentStartIndex += 1
            }
            let segStart = cumulative[segmentStartIndex]
            let segEnd = cumulative[segmentStartIndex + 1]
            let fraction = segEnd == segStart ? 0.0 : (targetDistance - segStart) / (segEnd - segStart)
            result.append(RouteMath.interpolate(
                polyline[segmentStartIndex],
                polyline[segmentStartIndex + 1],
                fraction: fraction
            ))
            targetDistance += stepMeters
        }
        if RouteMath.distanceMeters(result.last!, polyline.last!) > 0.5 {
            result.append(polyline.last!)
        }
        return result
    }

    private func removeNearDuplicates(_ points: [RoutePoint]) -> [RoutePoint] {
        var result = [RoutePoint]()
        for point in points {
            if let last = result.last, RouteMath.distanceMeters(last, point) < 0.25 { continue }
            result.append(point)
        }
        return result
    }

    private func catmullRom(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, t: Double) -> Double {
        let t2 = t * t, t3 = t2 * t
        return 0.5 * (
            (2 * p1) +
            (-p0 + p2) * t +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
            (-p0 + 3 * p1 - 3 * p2 + p3) * t3
        )
    }
}

// MARK: - Local projection helpers

private struct ProjectedPoint {
    let x: Double
    let y: Double

    func distanceTo(_ other: ProjectedPoint) -> Double {
        sqrt(pow(x - other.x, 2) + pow(y - other.y, 2))
    }
}

private struct LocalProjection {
    private let origin: RoutePoint
    private let metersPerDegreeLat: Double
    private let metersPerDegreeLon: Double

    init(origin: RoutePoint) {
        self.origin = origin
        self.metersPerDegreeLat = 111_320.0
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
