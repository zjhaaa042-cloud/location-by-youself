import Foundation

/// 跑道收藏库：持久化到 Documents/saved_tracks.json。
/// 文件本身是可读 JSON，可直接从“文件”App 导出分享。
final class SavedTracksRepository: ObservableObject {
    @Published private(set) var tracks: [SavedTrack] = []

    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        fileURL = dir.appendingPathComponent("saved_tracks.json")
        load()
    }

    /// 保存跑道；同名跑道直接覆盖（同一操场微调多次只留最新一版）
    func add(_ track: SavedTrack) {
        if let index = tracks.firstIndex(where: { $0.name == track.name }) {
            tracks[index] = track
        } else {
            tracks.append(track)
        }
        persist()
    }

    func delete(atOffsets offsets: IndexSet) {
        tracks.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        guard let data = try? encoder.encode(tracks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? decoder.decode([SavedTrack].self, from: data)
        else { return }
        tracks = saved
    }
}
