import SwiftUI
import MapKit
import Combine

@MainActor
final class MainViewModel: ObservableObject {
    // MARK: - Published state

    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @Published var markers: [RoutePoint] = []
    @Published var routePolyline: [RoutePoint] = []
    @Published var currentLocation: RoutePoint?
    @Published var simulationState: SimulationState = .idle
    @Published var alertMessage: String?
    @Published var showGPXShare = false
    @Published var gpxFileURL: URL?

    // MARK: - Settings

    @Published var speedKmh: Float = 5
    @Published var playbackMode: PlaybackMode = .once
    @Published var routeProfile: RouteProfile = .manual
    @Published var trackName: String = ""
    @Published var trackOrientation: TrackOrientation = .vertical
    @Published var naturalRunEnabled: Bool = true

    // MARK: - Dependencies

    let engine = SimulationEngine()
    let settingsRepo = SettingsRepository()
    let trackDetector = TrackDetector()
    let routePlanner = RoutePlanner()

    private var cancellables = Set<AnyCancellable>()

    init() {
        isJailbroken = TweakBridge.isJailbroken
        isTweakMode = isJailbroken // 越狱设备默认启用 tweak 模式
        loadSettings()
        bindEngine()
    }

    private func bindEngine() {
        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.simulationState = state
            }
            .store(in: &cancellables)

        engine.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let p = progress else { return }
                self?.currentLocation = p.point
                self?.mapRegion.center = CLLocationCoordinate2D(
                    latitude: p.point.lat,
                    longitude: p.point.lon
                )
            }
            .store(in: &cancellables)
    }

    // MARK: - Map interactions

    func addMarker(at coordinate: CLLocationCoordinate2D) {
        let point = RoutePoint(lat: coordinate.latitude, lon: coordinate.longitude)
        markers.append(point)
        routePolyline.append(point)
    }

    func clearMarkers() {
        markers.removeAll()
        routePolyline.removeAll()
        currentLocation = nil
    }

    func undoLastMarker() {
        guard !markers.isEmpty else { return }
        markers.removeLast()
        routePolyline.removeLast()
    }

    // MARK: - Simulation control

    @Published var isTweakMode = false
    @Published var isJailbroken = false

    func startFixedSimulation() {
        guard let point = markers.last else {
            alertMessage = "请先在地图上放置一个标记点"
            return
        }
        engine.startFixed(point: point)
        if isTweakMode {
            TweakBridge.writeFixedPoint(lat: point.lat, lon: point.lon, altitude: point.altitude ?? 0)
        }
    }

    func startRouteSimulation() {
        guard markers.count >= 2 else {
            alertMessage = "请至少放置两个标记点来创建路线"
            return
        }
        let config = SimulationConfig(
            points: markers,
            speedKmh: speedKmh,
            mode: playbackMode,
            updateIntervalMs: 1000,
            routeProfile: routeProfile
        )
        engine.startRoute(config: config)
        if isTweakMode {
            TweakBridge.writeRoute(
                points: markers,
                speedMs: RouteMath.speedKmhToMetersPerSecond(speedKmh),
                bearing: 0,
                mode: playbackMode.rawValue
            )
        }
    }

    func startTrackSimulation() {
        guard !trackName.isEmpty, let center = settingsRepo.settings.trackCenter else {
            alertMessage = "请先检测跑道"
            return
        }
        let trackPoints = TrackRoutePlanner().generateOvalTrack(
            center: center,
            orientation: trackOrientation
        )
        routePolyline = trackPoints
        markers = trackPoints
        let config = SimulationConfig(
            points: trackPoints,
            speedKmh: speedKmh,
            mode: playbackMode,
            updateIntervalMs: 250,
            routeProfile: .trackRunning
        )
        engine.startRoute(config: config)
    }

    func pauseSimulation() { engine.pause() }
    func resumeSimulation() { engine.resume() }
    func stopSimulation() {
        engine.stop()
        if isTweakMode {
            TweakBridge.stopMocking()
        }
    }

    func updateSpeed(_ speed: Float) {
        speedKmh = speed
        engine.updateSpeed(speed)
    }

    // MARK: - Track detection

    func detectNearbyTrack() {
        let center = mapRegion.center
        trackDetector.findNearbyTracks(around: center) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let name, let centerPt, _, _):
                    self?.trackName = name
                    self?.settingsRepo.saveTrack(name: name, center: centerPt)
                    self?.mapRegion.center = CLLocationCoordinate2D(
                        latitude: centerPt.lat,
                        longitude: centerPt.lon
                    )
                case .notFound(let reason):
                    self?.alertMessage = reason
                }
            }
        }
    }

    // MARK: - GPX export

    func exportGPX() {
        let points: [RoutePoint]
        let name: String

        if !routePolyline.isEmpty {
            points = routePolyline
            name = trackName.isEmpty ? "路线" : trackName
        } else if let last = markers.last {
            points = [last]
            name = "固定点"
        } else {
            alertMessage = "没有可导出的位置数据"
            return
        }

        let gpxContent: String
        if points.count == 1 {
            gpxContent = GPXExporter.generateWaypointGPX(name: name, point: points[0])
        } else {
            gpxContent = GPXExporter.generateGPX(name: name, points: points, speedMs: speedKmh / 3.6)
        }

        let safeName = name.replacingOccurrences(of: " ", with: "_")
        gpxFileURL = GPXExporter.saveGPX(gpxContent, fileName: safeName)
        showGPXShare = gpxFileURL != nil
    }

    // MARK: - Settings persistence

    func saveSettings() {
        settingsRepo.saveSpeed(speedKmh)
        settingsRepo.savePlaybackMode(playbackMode)
        settingsRepo.savePoints(markers)
        settingsRepo.saveTrackOrientation(trackOrientation)
    }

    private func loadSettings() {
        let s = settingsRepo.settings
        speedKmh = s.speedKmh
        playbackMode = s.playbackMode
        markers = s.points
        routePolyline = s.points
        trackName = s.trackName
        trackOrientation = s.trackOrientation
        naturalRunEnabled = s.naturalRunEnabled
        if let center = s.trackCenter {
            mapRegion.center = CLLocationCoordinate2D(
                latitude: center.lat,
                longitude: center.lon
            )
        }
    }
}
