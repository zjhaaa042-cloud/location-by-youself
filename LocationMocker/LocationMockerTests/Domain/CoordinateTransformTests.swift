import XCTest
@testable import LocationMocker

final class CoordinateTransformTests: XCTestCase {

    func testWgs84ToGcj02_outsideChina_unchanged() {
        let point = RoutePoint(lat: 48.8566, lon: 2.3522) // Paris
        let result = CoordinateTransform.wgs84ToGcj02(point)
        XCTAssertEqual(result.lat, point.lat, accuracy: 0.0001)
        XCTAssertEqual(result.lon, point.lon, accuracy: 0.0001)
    }

    func testWgs84ToGcj02_insideChina_offset() {
        let point = RoutePoint(lat: 39.9042, lon: 116.4074) // Beijing
        let result = CoordinateTransform.wgs84ToGcj02(point)
        // GCJ-02 should be offset from WGS-84
        XCTAssertNotEqual(result.lat, point.lat, accuracy: 0.00001,
                          "Inside China, coordinates should be offset")
        XCTAssertNotEqual(result.lon, point.lon, accuracy: 0.00001,
                          "Inside China, coordinates should be offset")
    }

    func testGcj02ToWgs84_roundtrip() {
        let original = RoutePoint(lat: 39.9042, lon: 116.4074)
        let gcj = CoordinateTransform.wgs84ToGcj02(original)
        let back = CoordinateTransform.gcj02ToWgs84(gcj)
        XCTAssertEqual(back.lat, original.lat, accuracy: 0.0001)
        XCTAssertEqual(back.lon, original.lon, accuracy: 0.0001)
    }
}
