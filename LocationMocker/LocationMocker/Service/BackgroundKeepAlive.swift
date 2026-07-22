import Foundation
import CoreLocation
import AVFoundation

/// 静音 WAV 数据生成器（纯逻辑，可单测）
///
/// 后台保活的"双保险"之一：循环播放一段静音音频，让系统把 App 当作
/// 正在播放音乐的进程而不挂起。这里用代码生成极小的 PCM16 单声道 WAV，
/// 避免在 bundle 里携带资源文件。
enum SilentAudioGenerator {

    /// 生成一段静音 WAV 数据（44 字节标准头 + 16bit PCM 全零采样）
    /// - Parameters:
    ///   - durationSeconds: 时长（秒），默认 1s，循环播放听不出接缝
    ///   - sampleRate: 采样率，默认 8000Hz（电话级，足够小，文件仅 ~16KB/s）
    static func makeWAVData(durationSeconds: Double = 1.0, sampleRate: Int = 8000) -> Data {
        let frameCount = max(1, Int(durationSeconds * Double(sampleRate)))
        let dataSize = UInt32(frameCount * 2) // 16bit 单声道 = 每帧 2 字节
        let byteRate = UInt32(sampleRate * 2)

        var data = Data()
        data.reserveCapacity(44 + Int(dataSize))

        // RIFF 头
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.appendLittleEndian(UInt32(36) + dataSize)      // 文件总长 - 8
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt 子块：PCM / 单声道 / 16bit
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        data.appendLittleEndian(UInt32(16))                // fmt 块大小
        data.appendLittleEndian(UInt16(1))                 // PCM 格式
        data.appendLittleEndian(UInt16(1))                 // 单声道
        data.appendLittleEndian(UInt32(sampleRate))        // 采样率
        data.appendLittleEndian(byteRate)                  // 字节率
        data.appendLittleEndian(UInt16(2))                 // 块对齐 = 声道数 × 位深/8
        data.appendLittleEndian(UInt16(16))                // 位深

        // data 子块：全零采样（静音）
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.appendLittleEndian(dataSize)
        data.append(Data(count: Int(dataSize)))

        return data
    }
}

private extension Data {
    /// 按小端序追加定长整数（WAV 为 RIFF 小端格式）
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        // 显式用 Swift 全局函数，避免解析到 Data 的实例方法
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}

/// 后台保活：模拟运行期间防止 App 进后台/锁屏后被系统挂起
///
/// 双保险策略（侧载分发，无审核顾虑）：
/// 1. **CoreLocation 后台定位**：声明了 `UIBackgroundModes=[location]` 后必须
///    实际启动定位更新才生效。用 3km 低精度 + 不自动暂停，功耗极低，
///    回调内容不使用（位置数据来自模拟游标，不是真实 GPS）。
/// 2. **静音音频**：`AVAudioSession` 配 `.playback` 分类并循环播放静音 WAV。
///    音量设 0.01 而不是 0，避免被系统当作无声输出优化掉。
///
/// 电话等音频中断时监听 `interruptionNotification`，中断结束后若仍处于
/// 保活状态则自动重新激活会话并恢复播放。
final class BackgroundKeepAlive: NSObject {

    /// 保活是否激活（只读，start/stop 幂等）
    private(set) var isActive = false

    private let locationManager = CLLocationManager()
    private var audioPlayer: AVAudioPlayer?
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        // 低功耗配置：目的只是让 iOS 不挂起进程，不关心定位精度
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = kCLDistanceFilterNone
        observeAudioInterruption()
    }

    deinit {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// 开启保活（幂等）：后台定位 + 静音音频同时启用
    func start() {
        guard !isActive else { return }
        isActive = true

        // 请求 WhenInUse 权限（Info.plist 已有描述字符串）；
        // allowsBackgroundLocationUpdates=true 时 WhenInUse 授权即可后台定位
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()

        activateAudioSession()
        startSilentAudio()
    }

    /// 关闭保活（幂等）：停止定位与静音播放，并让出音频会话
    func stop() {
        guard isActive else { return }
        isActive = false

        locationManager.stopUpdatingLocation()
        audioPlayer?.stop()
        audioPlayer = nil
        // notifyOthersOnDeactivation：让被压制的其他音频（如音乐 App）恢复
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 私有

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // .playback 分类：即使静音开关打开/锁屏也允许播放，且支持后台音频
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    private func startSilentAudio() {
        guard audioPlayer == nil else {
            audioPlayer?.play()
            return
        }
        let wav = SilentAudioGenerator.makeWAVData()
        guard let player = try? AVAudioPlayer(data: wav) else { return }
        player.numberOfLoops = -1 // 无限循环
        player.volume = 0.01      // 极小音量而非 0，避免系统无声优化
        player.prepareToPlay()
        player.play()
        audioPlayer = player
    }

    /// 电话/Siri 等打断音频会话后自动恢复：中断结束且仍在保活则重新激活并播放
    private func observeAudioInterruption() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self, self.isActive,
                  let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: typeValue) == .ended
            else { return }
            self.activateAudioSession()
            self.audioPlayer?.play()
        }
    }
}
