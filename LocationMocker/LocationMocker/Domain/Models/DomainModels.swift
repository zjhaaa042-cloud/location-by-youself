import Foundation

// MARK: - RoutePoint

struct RoutePoint: Codable, Equatable, Hashable {
    let lat: Double
    let lon: Double
    let altitude: Double?

    init(lat: Double, lon: Double, altitude: Double? = nil) {
        self.lat = lat
        self.lon = lon
        self.altitude = altitude
    }
}

// MARK: - RouteSample

struct RouteSample: Codable, Equatable {
    let point: RoutePoint
    let speedMetersPerSecond: Float
    let bearingDegrees: Float
}

// MARK: - PlaybackMode

enum PlaybackMode: String, Codable, CaseIterable {
    case once = "Once"
    case loop = "Loop"
    case pingPong = "PingPong"
}

// MARK: - RouteProfile

enum RouteProfile: String, Codable, CaseIterable {
    case manual = "Manual"
    case trackRunning = "TrackRunning"
}

// MARK: - SimulationConfig

struct SimulationConfig: Codable {
    let points: [RoutePoint]
    let speedKmh: Float
    let mode: PlaybackMode
    let updateIntervalMs: Int
    let routeProfile: RouteProfile

    init(
        points: [RoutePoint],
        speedKmh: Float,
        mode: PlaybackMode,
        updateIntervalMs: Int = 1000,
        routeProfile: RouteProfile = .manual
    ) {
        self.points = points
        self.speedKmh = speedKmh
        self.mode = mode
        self.updateIntervalMs = updateIntervalMs
        self.routeProfile = routeProfile
    }
}

// MARK: - SimulationState

enum SimulationState: Equatable {
    case idle
    case ready
    case running
    case paused
    case error(String)
}

// MARK: - SimulationProgress

struct SimulationProgress: Equatable {
    let point: RoutePoint
    let speedMetersPerSecond: Float
    let bearingDegrees: Float
    let isRoute: Bool
    var paused: Bool = false
    var errorMessage: String? = nil
}
