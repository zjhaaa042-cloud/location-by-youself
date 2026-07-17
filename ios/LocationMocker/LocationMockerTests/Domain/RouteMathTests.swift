import XCTest
@testable import LocationMocker

final class RouteMathTests: XCTestCase {

    func testSpeedConversion() {
        XCTAssertEqual(RouteMath.speedKmhToMetersPerSecond(3.6), 1.0, accuracy: 0.01)
        XCTAssertEqual(RouteMath.speedKmhToMetersPerSecond(36), 10.0, accuracy: 0.01)
    }

    func testDistanceMeters_samePoint() {
        let a = RoutePoint(lat: 39.9, lon: 116.4)
        let b = RoutePoint(lat: 39.9, lon: 116.4)
        XCTAssertEqual(RouteMath.distanceMeters(a, b), 0, accuracy: 0.01)
    }

    func testDistanceMeters_knownDistance() {
        // One degree of latitude ≈ 111,320 meters
        let a = RoutePoint(lat: 0, lon: 0)
        let b = RoutePoint(lat: 1, lon: 0)
        let dist = RouteMath.distanceMeters(a, b)
        XCTAssertEqual(dist, 111_320, accuracy: 500)
    }

    func testBearing_north() {
        let a = RoutePoint(lat: 0, lon: 0)
        let b = RoutePoint(lat: 1, lon: 0)
        let bearing = RouteMath.bearingDegrees(a, b)
        XCTAssertEqual(bearing, 0, accuracy: 0.5)
    }

    func testBearing_east() {
        let a = RoutePoint(lat: 0, lon: 0)
        let b = RoutePoint(lat: 0, lon: 1)
        let bearing = RouteMath.bearingDegrees(a, b)
        XCTAssertEqual(bearing, 90, accuracy: 0.5)
    }

    func testInterpolate_midpoint() {
        let a = RoutePoint(lat: 0, lon: 0, altitude: 10)
        let b = RoutePoint(lat: 1, lon: 2, altitude: 20)
        let mid = RouteMath.interpolate(a, b, fraction: 0.5)
        XCTAssertEqual(mid.lat, 0.5, accuracy: 0.001)
        XCTAssertEqual(mid.lon, 1.0, accuracy: 0.001)
        XCTAssertEqual(mid.altitude!, 15, accuracy: 0.01)
    }
}
