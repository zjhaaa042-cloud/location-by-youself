import XCTest
@testable import LocationMocker

final class PlaybackCursorTests: XCTestCase {
    func testTrackConfigurationAlwaysLoops() {
        for mode in PlaybackMode.allCases {
            let config = SimulationConfig(points: [], speedKmh: 10, mode: mode, routeProfile: .trackRunning)
            XCTAssertEqual(config.mode, .loop)
            let cursor = PlaybackCursor(samples: makeSamples(count: 3), mode: config.mode)
            for _ in 0..<30 { XCTAssertNotNil(cursor.next()) }
            let track = [RoutePoint(lat: 31, lon: 121), RoutePoint(lat: 31.00001, lon: 121)]
            let natural = NaturalRunCursor(route: track, mode: config.mode)
            for _ in 0..<100 { XCTAssertNotNil(natural.next()) }
            let manual = SimulationConfig(points: [], speedKmh: 10, mode: mode)
            XCTAssertEqual(manual.mode, mode)
        }
    }

    private func makeSamples(count: Int) -> [RouteSample] {
        (0..<count).map { i in
            RouteSample(
                point: RoutePoint(lat: Double(i), lon: 0),
                speedMetersPerSecond: 5,
                bearingDegrees: 90
            )
        }
    }

    func testEmptyCursor_returnsNil() {
        let cursor = PlaybackCursor(samples: [], mode: .once)
        XCTAssertNil(cursor.next())
    }

    func testSingleSample_once() {
        let cursor = PlaybackCursor(samples: makeSamples(count: 1), mode: .once)
        XCTAssertNotNil(cursor.next())
        XCTAssertNil(cursor.next(), "Once mode should complete after single sample")
    }

    func testOnce_mode() {
        let cursor = PlaybackCursor(samples: makeSamples(count: 3), mode: .once)
        XCTAssertNotNil(cursor.next())
        XCTAssertNotNil(cursor.next())
        XCTAssertNotNil(cursor.next())
        XCTAssertNil(cursor.next())
    }

    func testLoop_mode() {
        let cursor = PlaybackCursor(samples: makeSamples(count: 3), mode: .loop)
        for _ in 0..<10 {
            XCTAssertNotNil(cursor.next())
        }
    }

    func testPingPong_mode() {
        let cursor = PlaybackCursor(samples: makeSamples(count: 3), mode: .pingPong)
        // Should go: 0, 1, 2, 1, 0, 1, 2, ...
        let first = cursor.next()
        let second = cursor.next()
        let third = cursor.next()
        let fourth = cursor.next()
        let fifth = cursor.next()

        XCTAssertEqual(first?.point.lat, 0)
        XCTAssertEqual(second?.point.lat, 1)
        XCTAssertEqual(third?.point.lat, 2)
        XCTAssertEqual(fourth?.point.lat, 1)
        XCTAssertEqual(fifth?.point.lat, 0)
    }

    func testReset() {
        let cursor = PlaybackCursor(samples: makeSamples(count: 3), mode: .once)
        _ = cursor.next()
        _ = cursor.next()
        cursor.reset()
        XCTAssertEqual(cursor.next()?.point.lat, 0, "After reset, should start from beginning")
    }
}
