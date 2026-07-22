import Foundation
import Combine
import CoreLocation

@MainActor
final class SimulationEngine: ObservableObject {
    @Published var state: SimulationState = .idle
    @Published var progress: SimulationProgress?

    private var config: SimulationConfig?
    private var manualCursor: PlaybackCursor?
    private var naturalCursor: NaturalRunCursor?
    private var timer: Timer?
    private var paused = false

    /// 后台保活（后台定位 + 静音音频）：模拟运行期间防止进程被系统挂起
    private let keepAlive = BackgroundKeepAlive()

    var currentPoint: RoutePoint? { progress?.point }

    /// 后台保活是否激活（供 UI 显示保活状态指示）
    var isKeepAliveActive: Bool { keepAlive.isActive }

    func startFixed(point: RoutePoint) {
        stop()
        state = .running
        keepAlive.start()
        paused = false
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.paused else { return }
                self.progress = SimulationProgress(
                    point: point,
                    speedMetersPerSecond: 0,
                    bearingDegrees: 0,
                    isRoute: false
                )
            }
        }
    }

    func startRoute(config: SimulationConfig) {
        stop()
        self.config = config
        paused = false

        if config.routeProfile == .trackRunning {
            naturalCursor = NaturalRunCursor(
                route: config.points,
                mode: config.mode,
                baseSpeedKmh: config.speedKmh,
                updateIntervalMs: config.updateIntervalMs
            )
            manualCursor = nil
        } else {
            let samples = RoutePlanner().buildSamples(config: config)
            manualCursor = PlaybackCursor(samples: samples, mode: config.mode)
            naturalCursor = nil
        }

        state = .running
        keepAlive.start()
        let interval = Double(config.updateIntervalMs) / 1000.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func pause() {
        paused = true
        state = .paused
    }

    func resume() {
        paused = false
        state = .running
    }

    func updateSpeed(_ speedKmh: Float) {
        naturalCursor?.updateBaseSpeedKmh(speedKmh)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        manualCursor = nil
        naturalCursor = nil
        paused = false
        config = nil
        progress = nil
        state = .idle
        keepAlive.stop()
    }

    private func tick() {
        guard !paused else { return }
        let sample = naturalCursor?.next() ?? manualCursor?.next()
        guard let sample else {
            stop()
            return
        }
        progress = SimulationProgress(
            point: sample.point,
            speedMetersPerSecond: sample.speedMetersPerSecond,
            bearingDegrees: sample.bearingDegrees,
            isRoute: true
        )
    }
}
