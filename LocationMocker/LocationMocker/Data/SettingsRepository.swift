import Foundation
import Combine

struct SavedSettings: Codable, Equatable {
    var speedKmh: Float = 5
    var playbackMode: PlaybackMode = .once
    var points: [RoutePoint] = []
    var trackName: String = ""
    var trackCenter: RoutePoint? = nil
    var naturalRunEnabled: Bool = true
    var trackOrientation: TrackOrientation = .vertical
    var trackClockwise: Bool = true

    /// 容错解码：旧版本存档缺少后加的字段（如 trackClockwise）时回退默认值，
    /// 而不是整个解码失败丢掉全部已存设置
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speedKmh = try c.decodeIfPresent(Float.self, forKey: .speedKmh) ?? 5
        playbackMode = try c.decodeIfPresent(PlaybackMode.self, forKey: .playbackMode) ?? .once
        points = try c.decodeIfPresent([RoutePoint].self, forKey: .points) ?? []
        trackName = try c.decodeIfPresent(String.self, forKey: .trackName) ?? ""
        trackCenter = try c.decodeIfPresent(RoutePoint.self, forKey: .trackCenter)
        naturalRunEnabled = try c.decodeIfPresent(Bool.self, forKey: .naturalRunEnabled) ?? true
        trackOrientation = try c.decodeIfPresent(TrackOrientation.self, forKey: .trackOrientation) ?? .vertical
        trackClockwise = try c.decodeIfPresent(Bool.self, forKey: .trackClockwise) ?? true
    }

    init() {}
}

final class SettingsRepository: ObservableObject {
    @Published var settings = SavedSettings()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() { load() }

    func saveSpeed(_ speedKmh: Float) {
        settings.speedKmh = min(max(speedKmh, 5), 120)
        persist()
    }

    func savePlaybackMode(_ mode: PlaybackMode) {
        settings.playbackMode = mode
        persist()
    }

    func savePoints(_ points: [RoutePoint]) {
        settings.points = points
        persist()
    }

    func saveTrack(name: String, center: RoutePoint, naturalRunEnabled: Bool = true) {
        settings.trackName = name
        settings.trackCenter = center
        settings.naturalRunEnabled = naturalRunEnabled
        persist()
    }

    func saveTrackOrientation(_ orientation: TrackOrientation) {
        settings.trackOrientation = orientation
        persist()
    }

    func saveTrackClockwise(_ clockwise: Bool) {
        settings.trackClockwise = clockwise
        persist()
    }

    private func persist() {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: "saved_settings")
    }

    private func load() {
        guard let data = defaults.data(forKey: "saved_settings"),
              let saved = try? decoder.decode(SavedSettings.self, from: data)
        else { return }
        settings = saved
    }
}
