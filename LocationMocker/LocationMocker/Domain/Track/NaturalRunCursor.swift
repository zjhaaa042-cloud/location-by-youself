import Foundation

final class NaturalRunCursor {
    private let points: [RoutePoint]
    private let mode: PlaybackMode
    private let updateIntervalMs: Int
    private let cumulativeMeters: [Double]
    private let totalMeters: Double

    private var traveledMeters = 0.0
    private var direction = 1
    private var completed = false
    private var lastLap = -1
    private var lapSpeedOffsetKmh = 0.0
    private var lapLaneBiasMeters = 0.0
    private var lapDriftAmplitudeMeters = 1.5
    private var lapPhase = 0.0
    private var currentBaseSpeedKmh: Double
    private var smoothedSpeedMps = 0.0

    init(route: [RoutePoint], mode: PlaybackMode, baseSpeedKmh: Float = 8.5, updateIntervalMs: Int = 1000) {
        self.points = Self.closeRoute(route)
        self.mode = mode
        self.currentBaseSpeedKmh = Double(min(max(baseSpeedKmh, 6), 12))
        self.updateIntervalMs = updateIntervalMs

        var cum = [0.0]
        for i in 0..<(self.points.count - 1) {
            cum.append(cum.last! + RouteMath.distanceMeters(self.points[i], self.points[i + 1]))
        }
        self.cumulativeMeters = cum
        self.totalMeters = cum.last ?? 0
        self.smoothedSpeedMps = currentBaseSpeedKmh / 3.6
    }

    func updateBaseSpeedKmh(_ speedKmh: Float) {
        currentBaseSpeedKmh = Double(min(max(speedKmh, 6), 12))
    }

    func next() -> RouteSample? {
        guard points.count >= 2, totalMeters > 0, !completed else { return nil }

        let lap = Int(floor(traveledMeters / totalMeters))
        if lap != lastLap {
            lastLap = lap
            lapSpeedOffsetKmh = Double.random(in: -0.45...0.45)
            lapLaneBiasMeters = Double.random(in: -0.9...0.9)
            lapDriftAmplitudeMeters = Double.random(in: 1.0...2.4)
            lapPhase = Double.random(in: 0...(2 * .pi))
        }

        let currentDist = normalizeDistance(traveledMeters)
        let progress = currentDist / totalMeters
        let basePoint = interpolateAt(currentDist)
        let nextDist = normalizeDistance(currentDist + Double(direction) * 2)
        let nextBasePoint = interpolateAt(nextDist)
        let drifted = applySmoothDrift(basePoint, next: nextBasePoint, progress: progress)

        let lookAhead = normalizeDistance(nextDist + Double(direction) * 2)
        let lookProgress = lookAhead / totalMeters
        let lookDrifted = applySmoothDrift(nextBasePoint, next: interpolateAt(lookAhead), progress: lookProgress)

        let speed = smoothedSpeed(progress)
        let bearing = RouteMath.bearingDegrees(drifted, lookDrifted)

        advance(speed)
        return RouteSample(point: drifted, speedMetersPerSecond: speed, bearingDegrees: bearing)
    }

    func reset() {
        traveledMeters = 0
        direction = 1
        completed = false
        lastLap = -1
        smoothedSpeedMps = currentBaseSpeedKmh / 3.6
    }

    private func advance(_ speedMps: Float) {
        let step = Double(speedMps) * (Double(updateIntervalMs) / 1000)
        switch mode {
        case .once:
            traveledMeters += step
            if traveledMeters >= totalMeters { completed = true }
        case .loop:
            traveledMeters += step
        case .pingPong:
            traveledMeters += step * Double(direction)
            if traveledMeters >= totalMeters { traveledMeters = totalMeters; direction = -1 }
            else if traveledMeters <= 0 { traveledMeters = 0; direction = 1 }
        }
    }

    private func smoothedSpeed(_ progress: Double) -> Float {
        let wave = sin(progress * 2 * .pi * 3 + lapPhase) * 0.35 +
            sin(progress * 2 * .pi * 7 + lapPhase * 0.7) * 0.15
        let speedKmh = min(max(currentBaseSpeedKmh + lapSpeedOffsetKmh + wave, 6), 12)
        let target = speedKmh / 3.6
        let alpha = min(max(Double(updateIntervalMs) / 1500.0, 0.08), 0.28)
        smoothedSpeedMps += (target - smoothedSpeedMps) * alpha
        return Float(smoothedSpeedMps)
    }

    private func applySmoothDrift(_ point: RoutePoint, next: RoutePoint, progress: Double) -> RoutePoint {
        let proj = TrackRoutePlanner.LocalProjection(origin: point)
        let np = proj.project(next)
        let length = sqrt(np.x * np.x + np.y * np.y)
        let len = length > 0.01 ? length : 1.0
        let nx = -np.y / len
        let ny = np.x / len

        let drift = min(max(
            lapLaneBiasMeters +
            lapDriftAmplitudeMeters * sin(progress * 2 * .pi * 2 + lapPhase) +
            0.45 * sin(progress * 2 * .pi * 7 + lapPhase * 0.6),
            -3), 3)
        return proj.unproject(TrackRoutePlanner.ProjectedPoint(
            x: nx * drift * Double(direction),
            y: ny * drift * Double(direction)
        ))
    }

    private func interpolateAt(_ distanceMeters: Double) -> RoutePoint {
        let d = min(max(distanceMeters, 0), totalMeters)
        let idx = cumulativeMeters.lastIndex(where: { $0 <= d }) ?? 0
        let segIdx = min(idx, cumulativeMeters.count - 2)
        let start = cumulativeMeters[segIdx]
        let end = cumulativeMeters[segIdx + 1]
        let frac = end == start ? 0 : (d - start) / (end - start)
        return RouteMath.interpolate(points[segIdx], points[segIdx + 1], fraction: frac)
    }

    private func normalizeDistance(_ d: Double) -> Double {
        if mode == .pingPong { return min(max(d, 0), totalMeters) }
        let rem = d.truncatingRemainder(dividingBy: totalMeters)
        return rem < 0 ? rem + totalMeters : rem
    }

    private static func closeRoute(_ route: [RoutePoint]) -> [RoutePoint] {
        guard route.count >= 2 else { return route }
        if RouteMath.distanceMeters(route.first!, route.last!) <= 0.5 { return route }
        return route + [route.first!]
    }
}
