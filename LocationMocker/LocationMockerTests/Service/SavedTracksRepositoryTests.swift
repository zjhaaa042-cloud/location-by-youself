import XCTest
@testable import LocationMocker

/// 跑道收藏库（SavedTracksRepository）持久化行为校验
final class SavedTracksRepositoryTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SavedTracksRepositoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeTrack(name: String = "测试操场") -> SavedTrack {
        SavedTrack(
            name: name,
            center: RoutePoint(lat: 39.9042, lon: 116.4074),
            perimeterMeters: 400,
            rotationDegrees: 15.5,
            startOffsetMeters: 120,
            clockwise: false
        )
    }

    /// 写入后重新建库能完整读回（字段级往返一致）
    func testAddAndPersist_roundTrip() {
        let repo = SavedTracksRepository(directory: tempDir)
        let track = makeTrack()
        repo.add(track)

        let reloaded = SavedTracksRepository(directory: tempDir)
        XCTAssertEqual(reloaded.tracks.count, 1)
        let loaded = reloaded.tracks[0]
        XCTAssertEqual(loaded.id, track.id)
        XCTAssertEqual(loaded.name, track.name)
        XCTAssertEqual(loaded.center, track.center)
        XCTAssertEqual(loaded.perimeterMeters, track.perimeterMeters)
        XCTAssertEqual(loaded.rotationDegrees, track.rotationDegrees)
        XCTAssertEqual(loaded.startOffsetMeters, track.startOffsetMeters)
        XCTAssertEqual(loaded.clockwise, track.clockwise)
        XCTAssertEqual(loaded.createdAt.timeIntervalSinceReferenceDate,
                       track.createdAt.timeIntervalSinceReferenceDate, accuracy: 0.001)
    }

    /// 同名跑道覆盖而不是追加（同一操场微调多次只留最新一版）
    func testAdd_sameNameReplacesInPlace() {
        let repo = SavedTracksRepository(directory: tempDir)
        repo.add(makeTrack())
        var newer = makeTrack()
        newer.perimeterMeters = 200
        newer.rotationDegrees = 90
        repo.add(newer)

        XCTAssertEqual(repo.tracks.count, 1)
        XCTAssertEqual(repo.tracks[0].perimeterMeters, 200)
        XCTAssertEqual(repo.tracks[0].rotationDegrees, 90)
    }

    /// 不同名跑道各自保留
    func testAdd_differentNamesAppends() {
        let repo = SavedTracksRepository(directory: tempDir)
        repo.add(makeTrack(name: "操场 A"))
        repo.add(makeTrack(name: "操场 B"))
        XCTAssertEqual(repo.tracks.map(\.name), ["操场 A", "操场 B"])
    }

    /// 删除后同样落盘
    func testDelete_persists() {
        let repo = SavedTracksRepository(directory: tempDir)
        repo.add(makeTrack(name: "操场 A"))
        repo.add(makeTrack(name: "操场 B"))
        repo.delete(atOffsets: IndexSet(integer: 0))

        XCTAssertEqual(repo.tracks.map(\.name), ["操场 B"])
        let reloaded = SavedTracksRepository(directory: tempDir)
        XCTAssertEqual(reloaded.tracks.map(\.name), ["操场 B"])
    }

    /// 存档文件损坏时回退为空库而不是崩溃
    func testLoad_corruptedFileFallsBackToEmpty() throws {
        try "not json".write(to: tempDir.appendingPathComponent("saved_tracks.json"),
                             atomically: true, encoding: .utf8)
        let repo = SavedTracksRepository(directory: tempDir)
        XCTAssertTrue(repo.tracks.isEmpty)
    }
}
