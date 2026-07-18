import Foundation

enum CoordinateTransform {
    private static let semiMajorAxis = 6_378_245.0
    private static let eccentricitySquared = 0.006693421622965943
    private static let inverseSearchDelta = 0.01
    private static let inverseTolerance = 0.0000001

    static func wgs84ToGcj02(_ point: RoutePoint) -> RoutePoint {
        guard !point.isOutsideChina else { return point }

        let dLat = transformLat(point.lon - 105, point.lat - 35)
        let dLon = transformLon(point.lon - 105, point.lat - 35)
        let radLat = point.lat / 180 * .pi
        var magic = sin(radLat)
        magic = 1 - eccentricitySquared * magic * magic
        let sqrtMagic = sqrt(magic)

        return RoutePoint(
            lat: point.lat + (dLat * 180) / ((semiMajorAxis * (1 - eccentricitySquared)) / (magic * sqrtMagic) * .pi),
            lon: point.lon + (dLon * 180) / (semiMajorAxis / sqrtMagic * cos(radLat) * .pi),
            altitude: point.altitude
        )
    }

    static func gcj02ToWgs84(_ point: RoutePoint) -> RoutePoint {
        guard !point.isOutsideChina else { return point }

        var minLat = point.lat - inverseSearchDelta
        var maxLat = point.lat + inverseSearchDelta
        var minLon = point.lon - inverseSearchDelta
        var maxLon = point.lon + inverseSearchDelta
        var candidate = point

        for _ in 0..<30 {
            candidate = RoutePoint(
                lat: (minLat + maxLat) / 2,
                lon: (minLon + maxLon) / 2
            )
            let transformed = wgs84ToGcj02(candidate)
            let latError = transformed.lat - point.lat
            let lonError = transformed.lon - point.lon

            if abs(latError) < inverseTolerance && abs(lonError) < inverseTolerance {
                return RoutePoint(lat: candidate.lat, lon: candidate.lon, altitude: point.altitude)
            }
            if latError > 0 { maxLat = candidate.lat } else { minLat = candidate.lat }
            if lonError > 0 { maxLon = candidate.lon } else { minLon = candidate.lon }
        }
        return RoutePoint(lat: candidate.lat, lon: candidate.lon, altitude: point.altitude)
    }

    private static func transformLat(_ x: Double, _ y: Double) -> Double {
        var result = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        result += (20 * sin(y * .pi) + 40 * sin(y / 3 * .pi)) * 2 / 3
        result += (160 * sin(y / 12 * .pi) + 320 * sin(y * .pi / 30)) * 2 / 3
        return result
    }

    private static func transformLon(_ x: Double, _ y: Double) -> Double {
        var result = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        result += (20 * sin(x * .pi) + 40 * sin(x / 3 * .pi)) * 2 / 3
        result += (150 * sin(x / 12 * .pi) + 300 * sin(x / 30 * .pi)) * 2 / 3
        return result
    }
}

private extension RoutePoint {
    var isOutsideChina: Bool {
        lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271
    }
}
