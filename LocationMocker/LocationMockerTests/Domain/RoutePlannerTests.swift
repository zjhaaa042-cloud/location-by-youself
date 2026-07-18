import XCTest
@testable import LocationMocker

final class RoutePlannerTests: XCTestCase {

    func testBuildSamples_emptyPoints() {
        let config = SimulationConfig(points: [], speedKmh: 5, mode: .once)
        let samples = RoutePlanner().buildSamples(config: config)
        XCTAssertTrue(samples.isEmpty)
    }

    func testBuildSamples_singlePoint() {
        let point = RoutePoint(lat: 39.9, lon: 116.4)
        let config = SimulationConfig(points: [point], speedKmh: 5, mode: .once)
        let samples = RoutePlanner().buildSamples(config: config)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].point, point)
        XCTAssertEqual(samples[0].speedMetersPerSecond, 0)
    }

    func testBuildSmoothPolyline_twoPoints() {
        let a = RoutePoint(lat: 0, lon: 0)
        let b = RoutePoint(lat: 0.01, lon: 0.01)
        let result = RoutePlanner().buildSmoothPolyline([a, b])
        XCTAssertGreaterThan(result.count, 1)
        XCTAssertEqual(result.first!, a)
        XCTAssertEqual(result.last!, b)
    }

    func testBuildSmoothPolyline_multiplePoints() {
        let points = [
            RoutePoint(lat: 0, lon: 0),
            RoutePoint(lat: 0.01, lon: 0),
            RoutePoint(lat: 0.01, lon: 0.01),
            RoutePoint(lat: 0, lon: 0.01),
        ]
        let result = RoutePlanner().buildSmoothPolyline(points)
        XCTAssertGreaterThan(result.count, points.count, "Smoothing should add intermediate points")
    }

    func testBuildSamples_producesValidBearings() {
        let points = [
            RoutePoint(lat: 39.9, lon: 116.4),
            RoutePoint(lat: 39.91, lon: 116.41),
        ]
        let config = SimulationConfig(points: points, speedKmh: 30, mode: .once)
        let samples = RoutePlanner().buildSamples(config: config)
        for sample in samples {
            XCTAssertGreaterThanOrEqual(sample.bearingDegrees, 0)
            XCTAssertLessThan(sample.bearingDegrees, 360)
            XCTAssertGreaterThan(sample.speedMetersPerSecond, 0)
        }
    }
}
