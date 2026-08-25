import SwiftUI
import MapKit
import Combine

/// 跑道设置流程状态
enum TrackSetupMode {
    case off        // 无跑道操作
    case aiming     // 手动模式：平移地图用准星对准操场中心
    case adjusting  // 微调中：跑道预览已生成，可调整位置/旋转/周长
}

@MainActor
final class MainViewModel: ObservableObject {
    // MARK: - Published state

    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    /// 地图样式：false = 标准，true = 卫星（按钮状态提升到这里，按钮才能放进布局流）
    @Published var mapIsSatellite = false
    @Published var markers: [RoutePoint] = []
    @Published var routePolyline: [RoutePoint] = []
    @Published var currentLocation: RoutePoint?
    @Published var simulationState: SimulationState = .idle
    @Published var alertMessage: String?
    @Published var showGPXShare = false
    @Published var gpxFileURL: URL?
    @Published private(set) var isInjectionConnecting = false
    @Published private(set) var isInjectionStopping = false

    // MARK: - Track setup (aiming / adjusting)

    @Published var trackSetupMode: TrackSetupMode = .off
    @Published var trackPreview: [RoutePoint] = []
    @Published var trackRotationDegrees: Double = 0
    @Published var trackPerimeterMeters: Double = 400
    /// 回放起点沿跑道的弧长偏移（米），0 = 第 1 直道起点
    @Published var trackStartOffsetMeters: Double = 0
    /// 跑动方向：true = 顺时针（北向上视角），false = 逆时针
    @Published var trackClockwise: Bool = true
    /// 自动检测到的候选操场列表（>1 个时由用户选择）
    @Published var trackCandidates: [ScoredTrackCandidate] = []
    /// 正在分析地图快照识别跑道形状（色值分析进行中，用于瞄准条按钮 loading 态）
    @Published var isAnalyzingTrackShape = false
    private var trackWorkingCenter: RoutePoint?

    /// 跑道回放起点坐标（用于地图起点标记）
    var trackStartPoint: RoutePoint? { trackPreview.first }

    // MARK: - Settings

    @Published var speedKmh: Float = 5
    @Published var playbackMode: PlaybackMode = .once
    @Published var routeProfile: RouteProfile = .manual
    @Published var trackName: String = ""
    @Published var trackOrientation: TrackOrientation = .vertical
    @Published var naturalRunEnabled: Bool = true

    // MARK: - Dependencies

    let engine = SimulationEngine()
    let injectionManager = RemoteInjectionManager()
    let settingsRepo = SettingsRepository()
    let trackDetector = TrackDetector()
    let routePlanner = RoutePlanner()
    let savedTracksRepo = SavedTracksRepository()

    private var cancellables = Set<AnyCancellable>()
    private var previousSimulationState: SimulationState = .idle

    init() {
        isJailbroken = TweakBridge.isJailbroken
        isTweakMode = isJailbroken // 越狱设备默认启用 tweak 模式
        loadSettings()
        bindEngine()
        bindInjectionManager()
    }

    private func bindEngine() {
        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                let previous = self.previousSimulationState
                self.previousSimulationState = state
                self.simulationState = state
                // once 路线自然结束时也必须显式 clear，不能把末点粘在系统里。
                if state == .idle,
                   previous == .running || previous == .paused {
                    self.clearRemoteInjectionIfNeeded()
                }
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
                // 中国区 MapKit 的交互/搜索坐标按 GCJ-02 显示；DTX LocationSimulation
                // 接收的是 CoreLocation/WGS-84。只在系统注入边界转换，UI 路线仍保持
                // MapKit 坐标，否则标记、折线和跑道预览会反向偏移。
                let systemPoint = CoordinateTransform.gcj02ToWgs84(p.point)
                self?.injectionManager.updateLocation(latitude: systemPoint.lat,
                                                      longitude: systemPoint.lon)
            }
            .store(in: &cancellables)
    }

    private func bindInjectionManager() {
        // RemoteInjectionManager 是嵌套 ObservableObject；转发变化让状态 chip/UI 能刷新。
        injectionManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // 跑道收藏库同样是嵌套 ObservableObject，转发变化刷新列表 UI
        savedTracksRepo.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        injectionManager.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self, case .failed(let reason) = phase else { return }
                if self.simulationState == .running || self.simulationState == .paused {
                    self.engine.stop()
                }
                self.alertMessage = "系统定位注入失败：\(reason)\n请确认 LocalDevVPN 已连接后重试。"
            }
            .store(in: &cancellables)
    }

    // MARK: - Map interactions

    @Published var isLocating = false
    private let locationLocator = CurrentLocationLocator()

    /// 「定位到当前位置」：一次性读取系统定位并把地图镜头移过去。
    /// 注入激活期间读到的是模拟坐标（与系统状态一致）。
    func locateToCurrentPosition() {
        guard !isLocating else { return }
        isLocating = true
        locationLocator.request { [weak self] coordinate in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLocating = false
                if let coordinate {
                    self.mapRegion = MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                    )
                } else {
                    self.alertMessage = "无法获取当前位置。请确认定位服务已开启，并允许本 App 使用定位（设置 → 隐私与安全性 → 定位服务）。"
                }
            }
        }
    }

    func addMarker(at coordinate: CLLocationCoordinate2D) {
        let point = RoutePoint(lat: coordinate.latitude, lon: coordinate.longitude)
        markers.append(point)
        routePolyline.append(point)
    }

    /// 搜索选点：将地图镜头移动到目标坐标，并复用与地图点选完全相同的选点数据流
    func locateSearchedPlace(at coordinate: CLLocationCoordinate2D) {
        mapRegion = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        addMarker(at: coordinate)
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

    /// 后台保活是否激活（顶部状态区"保活中"指示图标）
    var isKeepAliveActive: Bool { engine.isKeepAliveActive }

    var isRemoteInjectionActive: Bool { injectionManager.m2LocationInjected }

    var simulationControlsLocked: Bool {
        isInjectionConnecting || isInjectionStopping
            || simulationState == .running || simulationState == .paused
    }

    func startFixedSimulation() {
        guard let point = markers.last else {
            alertMessage = "请先在地图上放置一个标记点"
            return
        }
        guard !simulationControlsLocked else { return }
        startRemoteInjection(at: point) { [weak self] in
            guard let self else { return }
            self.engine.startFixed(point: point)
            if self.isTweakMode {
                TweakBridge.writeFixedPoint(lat: point.lat, lon: point.lon,
                                            altitude: point.altitude ?? 0)
            }
        }
    }

    func startRouteSimulation() {
        guard markers.count >= 2 else {
            alertMessage = "请至少放置两个标记点来创建路线"
            return
        }
        guard !simulationControlsLocked else { return }
        let config = SimulationConfig(
            points: markers,
            speedKmh: speedKmh,
            mode: playbackMode,
            updateIntervalMs: 1000,
            routeProfile: routeProfile
        )
        startRemoteInjection(at: markers[0]) { [weak self] in
            guard let self else { return }
            self.engine.startRoute(config: config)
            if self.isTweakMode {
                TweakBridge.writeRoute(
                    points: self.markers,
                    speedMs: RouteMath.speedKmhToMetersPerSecond(self.speedKmh),
                    bearing: 0,
                    mode: self.playbackMode.rawValue
                )
            }
        }
    }

    func pauseSimulation() { engine.pause() }
    func resumeSimulation() { engine.resume() }
    func stopSimulation() {
        // 先暂停游标，保留后台保活，等 stopLocationSimulation 送达并保持隧道
        // 3 秒后再彻底停止；避免用户点停止后立刻锁屏造成 clear 时序被挂起。
        if simulationState == .running {
            engine.pause()
        }
        if injectionManager.m2LocationInjected {
            clearRemoteInjectionIfNeeded(stopEngineAfterClear: true)
        } else {
            engine.stop()
        }
        if isTweakMode {
            TweakBridge.stopMocking()
        }
    }

    private func startRemoteInjection(at point: RoutePoint,
                                      onReady: @escaping @MainActor () -> Void) {
        isInjectionConnecting = true
        Task { @MainActor in
            defer { self.isInjectionConnecting = false }
            do {
                let systemPoint = CoordinateTransform.gcj02ToWgs84(point)
                try await self.injectionManager.startInjection(latitude: systemPoint.lat,
                                                               longitude: systemPoint.lon)
                onReady()
            } catch {
                self.alertMessage = "无法启动系统定位注入：\(String(describing: error))\n请先打开并连接 LocalDevVPN。"
            }
        }
    }

    private func clearRemoteInjectionIfNeeded(stopEngineAfterClear: Bool = false) {
        guard injectionManager.m2LocationInjected, !isInjectionStopping else { return }
        isInjectionStopping = true
        Task { @MainActor in
            await injectionManager.clearInjectedLocationAndWait()
            if stopEngineAfterClear {
                engine.stop()
            }
            isInjectionStopping = false
        }
    }

    func updateSpeed(_ speed: Float) {
        speedKmh = speed
        engine.updateSpeed(speed)
    }

    // MARK: - Track setup (manual aiming / POI-assisted / fine-tuning)

    /// 手动模式第一步：进入准星对准状态（不依赖 POI 搜索）
    func beginTrackAiming() {
        if simulationState == .running || simulationState == .paused {
            stopSimulation()
        }
        trackSetupMode = .aiming
    }

    /// 对准完成：先截取地图中心附近快照，用色值识别跑道方向/周长/精确中心，
    /// 然后进入微调状态。识别失败（快照失败、无绿块等）完全回退到默认行为
    /// （方向按 trackOrientation 设置、周长 400、中心=地图中心），不阻塞流程。
    func generateTrackAtMapCenter() {
        let center = RoutePoint(lat: mapRegion.center.latitude, lon: mapRegion.center.longitude)
        isAnalyzingTrackShape = true
        analyzeTrackShape(around: center, spanMeters: 220) { [weak self] estimate in
            guard let self else { return }
            self.isAnalyzingTrackShape = false
            // 分析期间用户已取消对准：只收尾，不再进入微调
            guard self.trackSetupMode == .aiming else { return }
            if let estimate {
                // 用绿块质心偏移修正跑道中心（用户瞄准的可能偏了几十米）
                let adjusted = TrackRoutePlanner.translated(
                    center,
                    northMeters: estimate.centerOffsetNorthMeters,
                    eastMeters: estimate.centerOffsetEastMeters
                )
                self.beginTrackAdjust(
                    center: adjusted,
                    name: "自定义跑道",
                    moveMapToCenter: false,
                    rotationOverride: estimate.rotationDegrees,
                    perimeterOverride: estimate.perimeterMeters
                )
            } else {
                self.beginTrackAdjust(center: center, name: "自定义跑道", moveMapToCenter: false)
            }
        }
    }

    /// POI 自动检测（辅助手段）：唯一候选直接进微调；多个候选发布列表由用户选择
    func detectNearbyTrack() {
        let center = mapRegion.center
        trackDetector.findNearbyTracks(around: center) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .candidates(let list):
                    if list.count == 1, let only = list.first {
                        self.beginTrackAdjust(center: only.center, name: only.name, moveMapToCenter: true)
                        // 色值精修：修正 POI 坐标偏移（实测可达 200–400m），失败保持现状
                        self.refineTrackShapeFromSnapshot(around: only.center)
                    } else {
                        self.trackCandidates = list
                    }
                case .notFound(let reason):
                    self.alertMessage = reason
                }
            }
        }
    }

    /// 用户从候选列表中选定操场，进入微调
    func selectTrackCandidate(_ scored: ScoredTrackCandidate) {
        trackCandidates = []
        beginTrackAdjust(center: scored.center, name: scored.name, moveMapToCenter: true)
        // 色值精修：修正 POI 坐标偏移（实测可达 200–400m），失败保持现状
        refineTrackShapeFromSnapshot(around: scored.center)
    }

    /// 取消候选选择
    func dismissTrackCandidates() {
        trackCandidates = []
    }

    /// 位置微调：向正北/正东移动指定米数
    func nudgeTrack(northMeters: Double, eastMeters: Double) {
        guard let center = trackWorkingCenter else { return }
        trackWorkingCenter = TrackRoutePlanner.translated(center, northMeters: northMeters, eastMeters: eastMeters)
        regenerateTrackPreview()
    }

    /// 旋转微调：绕中心整体旋转
    func rotateTrack(byDegrees delta: Double) {
        trackRotationDegrees = (trackRotationDegrees + delta).truncatingRemainder(dividingBy: 360)
        regenerateTrackPreview()
    }

    /// 尺寸微调：按周长预设等比缩放（保持两直道 + 两半圆的标准比例）
    func setTrackPerimeter(_ meters: Double) {
        trackPerimeterMeters = meters
        // 起点偏移不能超出新周长
        trackStartOffsetMeters = min(trackStartOffsetMeters, meters)
        regenerateTrackPreview()
    }

    /// 起点微调：回放起点沿跑道的弧长偏移（米）
    func setTrackStartOffset(_ meters: Double) {
        trackStartOffsetMeters = min(max(meters, 0), trackPerimeterMeters)
        regenerateTrackPreview()
    }

    /// 方向微调：顺时针 / 逆时针跑动（同一物理起点反向行进），并持久化偏好
    func setTrackClockwise(_ clockwise: Bool) {
        trackClockwise = clockwise
        settingsRepo.saveTrackClockwise(clockwise)
        regenerateTrackPreview()
    }

    /// 确认微调结果并开始模拟
    func confirmTrackAndStart() {
        guard let center = trackWorkingCenter, trackPreview.count >= 2 else { return }
        guard !simulationControlsLocked else { return }
        settingsRepo.saveTrack(name: trackName, center: center)
        let points = trackPreview
        let config = SimulationConfig(
            points: points,
            speedKmh: speedKmh,
            mode: playbackMode,
            updateIntervalMs: 250,
            routeProfile: .trackRunning
        )
        startRemoteInjection(at: points[0]) { [weak self] in
            self?.trackSetupMode = .off
            self?.engine.startRoute(config: config)
        }
    }

    /// 取消对准/微调，清除预览
    func cancelTrackSetup() {
        trackSetupMode = .off
        trackPreview = []
        trackWorkingCenter = nil
        // 防御性复位：快照回调到达时会再次置 false（幂等，不会卡状态）
        isAnalyzingTrackShape = false
    }

    private func beginTrackAdjust(
        center: RoutePoint,
        name: String,
        moveMapToCenter: Bool,
        rotationOverride: Double? = nil,
        perimeterOverride: Double? = nil
    ) {
        if simulationState == .running || simulationState == .paused {
            stopSimulation()
        }
        trackName = name
        trackWorkingCenter = center
        // 色值识别成功时覆盖方向/周长；nil = 现有默认（方向按设置、周长 400）
        trackRotationDegrees = rotationOverride ?? ((trackOrientation == .vertical) ? 0 : 90)
        trackPerimeterMeters = perimeterOverride ?? 400
        trackStartOffsetMeters = 0
        regenerateTrackPreview()
        if moveMapToCenter {
            mapRegion.center = CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon)
        }
        trackSetupMode = .adjusting
    }

    // MARK: - 地图图像色值识别（快照 → RGBA8 位图 → TrackShapeEstimator）

    /// POI 路径的色值精修：以候选坐标为中心截 400m 跨度快照做色值分析，
    /// 成功后覆盖中心/方向/周长（修正 POI 坐标 200–400m 的偏移）；
    /// 失败或期间用户已退出微调则保持现状。
    private func refineTrackShapeFromSnapshot(around center: RoutePoint) {
        isAnalyzingTrackShape = true
        analyzeTrackShape(around: center, spanMeters: 400) { [weak self] estimate in
            guard let self else { return }
            self.isAnalyzingTrackShape = false
            // 仅在仍处于微调状态时应用精修结果（用户可能已取消或已开始模拟）
            guard let estimate, self.trackSetupMode == .adjusting else { return }
            let adjusted = TrackRoutePlanner.translated(
                center,
                northMeters: estimate.centerOffsetNorthMeters,
                eastMeters: estimate.centerOffsetEastMeters
            )
            self.trackWorkingCenter = adjusted
            self.trackRotationDegrees = estimate.rotationDegrees
            self.trackPerimeterMeters = estimate.perimeterMeters
            self.trackStartOffsetMeters = 0
            self.regenerateTrackPreview()
        }
    }

    /// 共用 helper：地图快照 → RGBA8 位图 → 色值估计。
    /// - Parameters:
    ///   - center: 快照中心（地图中心路径 = 准星位置，POI 路径 = 候选坐标）
    ///   - spanMeters: 快照覆盖跨度（米）。地图中心路径用 220m（覆盖 400m 场全幅
    ///     157×73m + 余量）；POI 路径用 400m（容纳 POI 坐标偏移，绿块可能偏离
    ///     快照中心一二百米，同时避免把隔壁公园整个框进来）
    ///   - completion: 主线程回调；快照失败/无绿块时返回 nil（调用方走回退）
    private func analyzeTrackShape(
        around center: RoutePoint,
        spanMeters: Double,
        completion: @escaping (TrackShapeEstimate?) -> Void
    ) {
        let coordinate = CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon)
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: spanMeters,
            longitudinalMeters: spanMeters
        )
        options.size = CGSize(width: 512, height: 512)
        options.scale = 2 // Retina 分辨率（实际位图 1024×1024），绿块边缘更锐利
        // 强制标准样式 + 浅色外观 + 排除全部 POI 标注，保证绿色色值规则稳定——
        // 即使用户当前看的是卫星图/深色模式，也用标准样式快照，
        // 几何位置一致，不影响识别结果的正确性
        let config = MKStandardMapConfiguration()
        config.pointOfInterestFilter = .excludingAll
        config.elevationStyle = .flat // 关闭 3D 地形，避免阴影干扰色值
        options.preferredConfiguration = config
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        options.showsBuildings = false

        Task {
            // async 版 start：Task 挂起期间系统持有请求，无需手动 retain snapshotter
            guard let snapshot = try? await MKMapSnapshotter(options: options).start() else {
                completion(nil) // 快照失败：回退，绝不卡在分析状态
                return
            }
            let image = snapshot.image
            // 米/像素标定：MKMapSnapshot 只有 point(for:)（坐标→图像点），
            // 在中心东/北各 100m 取参照坐标映射到图像点（points）量距离，
            // 再乘 image.scale 换算到位图像素——不假设快照严格等于请求 region
            let referenceMeters = 100.0
            let metersPerDegreeLat = 111_320.0
            let metersPerDegreeLon = 111_320.0 * cos(center.lat * .pi / 180)
            let pCenter = snapshot.point(for: coordinate)
            let pEast = snapshot.point(for: CLLocationCoordinate2D(
                latitude: center.lat,
                longitude: center.lon + referenceMeters / metersPerDegreeLon
            ))
            let pNorth = snapshot.point(for: CLLocationCoordinate2D(
                latitude: center.lat + referenceMeters / metersPerDegreeLat,
                longitude: center.lon
            ))
            let eastPoints = hypot(pEast.x - pCenter.x, pEast.y - pCenter.y)
            let northPoints = hypot(pNorth.x - pCenter.x, pNorth.y - pCenter.y)
            guard eastPoints > 0, northPoints > 0, image.scale > 0 else {
                completion(nil) // 标定失败：回退
                return
            }
            let mppX = referenceMeters / (eastPoints * image.scale)   // x 向东
            let mppY = referenceMeters / (northPoints * image.scale)  // y 向南
            // 位图绘制 + 连通域 + PCA 较耗时（百万级像素），放后台线程避免阻塞 UI
            let estimate = await Task.detached(priority: .userInitiated) {
                Self.estimateShape(in: image, mppX: mppX, mppY: mppY)
            }.value
            completion(estimate)
        }
    }

    /// 后台线程执行：UIImage → RGBA8 位图 → TrackShapeEstimator（纯函数）
    /// - Parameters:
    ///   - mppX / mppY: 米/像素（x 向东，y 向南），由快照 point(for:) 标定
    private nonisolated static func estimateShape(
        in image: UIImage,
        mppX: Double,
        mppY: Double
    ) -> TrackShapeEstimate? {
        guard let (pixels, width, height) = rgba8Bitmap(from: image) else { return nil }
        return pixels.withUnsafeBufferPointer {
            TrackShapeEstimator.estimate(
                pixels: $0,
                width: width,
                height: height,
                bytesPerRow: width * 4,
                mppX: mppX,
                mppY: mppY
            )
        }
    }

    /// 把 UIImage 绘制成 RGBA8 像素缓冲（供 TrackShapeEstimator 逐像素分析）
    private nonisolated static func rgba8Bitmap(from image: UIImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (pixels, width, height)
    }

    private func regenerateTrackPreview() {
        guard let center = trackWorkingCenter else {
            trackPreview = []
            return
        }
        trackPreview = TrackRoutePlanner().generateOvalTrack(
            center: center,
            perimeterMeters: trackPerimeterMeters,
            rotationDegrees: trackRotationDegrees,
            startOffsetMeters: trackStartOffsetMeters,
            clockwise: trackClockwise
        )
    }

    // MARK: - 跑道收藏（保存 / 载入 / 分享）

    /// 把当前微调中的跑道参数存入收藏库（同名覆盖）
    func saveCurrentTrackToLibrary() {
        guard trackSetupMode == .adjusting, let center = trackWorkingCenter else { return }
        let name = trackName.isEmpty ? "未命名跑道" : trackName
        savedTracksRepo.add(SavedTrack(
            name: name,
            center: center,
            perimeterMeters: trackPerimeterMeters,
            rotationDegrees: trackRotationDegrees,
            startOffsetMeters: trackStartOffsetMeters,
            clockwise: trackClockwise
        ))
        alertMessage = "已保存跑道「\(name)」，可在「保存的路线」中载入或分享。"
    }

    /// 载入收藏的跑道：恢复全部生成参数并进入微调状态，地图移到跑道中心
    func loadSavedTrack(_ track: SavedTrack) {
        if simulationState == .running || simulationState == .paused {
            stopSimulation()
        }
        trackName = track.name
        trackWorkingCenter = track.center
        trackRotationDegrees = track.rotationDegrees
        trackPerimeterMeters = track.perimeterMeters
        trackStartOffsetMeters = min(track.startOffsetMeters, track.perimeterMeters)
        trackClockwise = track.clockwise
        regenerateTrackPreview()
        mapRegion.center = CLLocationCoordinate2D(latitude: track.center.lat, longitude: track.center.lon)
        trackSetupMode = .adjusting
    }

    /// 按收藏参数重建跑道折线并导出 GPX，返回文件 URL（用于系统分享面板）
    func exportTrackGPX(_ track: SavedTrack) -> URL? {
        let points = TrackRoutePlanner().generateOvalTrack(
            center: track.center,
            perimeterMeters: track.perimeterMeters,
            rotationDegrees: track.rotationDegrees,
            startOffsetMeters: track.startOffsetMeters,
            clockwise: track.clockwise
        )
        guard points.count >= 2 else { return nil }
        let gpx = GPXExporter.generateGPX(name: track.name, points: points, speedMs: speedKmh / 3.6)
        let safeName = track.name.replacingOccurrences(of: " ", with: "_")
        return GPXExporter.saveGPX(gpx, fileName: safeName)
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
        settingsRepo.saveTrackClockwise(trackClockwise)
    }

    private func loadSettings() {
        let s = settingsRepo.settings
        speedKmh = s.speedKmh
        playbackMode = s.playbackMode
        markers = s.points
        routePolyline = s.points
        trackName = s.trackName
        trackOrientation = s.trackOrientation
        trackClockwise = s.trackClockwise
        naturalRunEnabled = s.naturalRunEnabled
        if let center = s.trackCenter {
            mapRegion.center = CLLocationCoordinate2D(
                latitude: center.lat,
                longitude: center.lon
            )
        }
    }
}
