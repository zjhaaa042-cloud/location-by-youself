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
