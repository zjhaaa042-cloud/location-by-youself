import Foundation

enum RouteMath {
    private static let earthRadiusMeters: Double = 6_371_000.0

    static func speedKmhToMetersPerSecond(_ speedKmh: Float) -> Float {
        speedKmh / 3.6
    }

    static func distanceMeters(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        let dLat = (b.lat - a.lat).toRadians
        let dLon = (b.lon - a.lon).toRadians
        let lat1 = a.lat.toRadians
        let lat2 = b.lat.toRadians
        let haversine = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2)
        return 2 * earthRadiusMeters * atan2(sqrt(haversine), sqrt(1 - haversine))
    }

    static func bearingDegrees(_ a: RoutePoint, _ b: RoutePoint) -> Float {
        guard a != b else { return 0 }
        let lat1 = a.lat.toRadians
        let lat2 = b.lat.toRadians
        let dLon = (b.lon - a.lon).toRadians
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return Float((atan2(y, x).toDegrees + 360).truncatingRemainder(dividingBy: 360))
    }

    static func interpolate(_ a: RoutePoint, _ b: RoutePoint, fraction: Double) -> RoutePoint {
        let clamped = min(max(fraction, 0), 1)
        let alt: Double?
        if let altA = a.altitude, let altB = b.altitude {
            alt = altA + (altB - altA) * clamped
        } else {
            alt = a.altitude ?? b.altitude
        }
        return RoutePoint(
            lat: a.lat + (b.lat - a.lat) * clamped,
            lon: a.lon + (b.lon - a.lon) * clamped,
            altitude: alt
        )
    }
}

extension Double {
    var toRadians: Double { self / 180 * .pi }
    var toDegrees: Double { self / .pi * 180 }
}
