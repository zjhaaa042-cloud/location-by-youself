import Foundation
import Network
import NetworkExtension
import CoreLocation

/// Milestone 1「纯手机端独立注入」编排器：
/// 安装/启动 NE 回环隧道 → 经隧道连接本机 remotepairingd（10.7.0.1:49152）→
/// 完成 RPPairing 握手与 pair-verify / SRP 配对。
@MainActor
final class RemoteInjectionManager: ObservableObject {

    enum Phase: Equatable {
        case idle
        case installingTunnel
        case startingTunnel
        case handshaking
        case succeeded(String)
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .installingTunnel, .startingTunnel, .handshaking: return true
            default: return false
            }
        }
    }

    struct LogLine: Identifiable {
        let id = UUID()
        let time: String
        let text: String
    }

    /// 回环来源模式。
    enum LoopbackMode: String, CaseIterable {
        /// 经第三方回环 VPN（LocalDevVPN/StosVPN）直连 10.7.0.1，免费签名可用。
        case directLoopback = "直连回环（LocalDevVPN）"
        /// 自建 NE 隧道扩展（需付费开发者账号的 Network Extensions 签名）。
        case selfTunnel = "自建隧道（需付费账号）"
    }

    @Published var loopbackMode: LoopbackMode = .directLoopback
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var logs: [LogLine] = []

    /// 持有中的握手客户端（保持 RPPairing 控制连接，防止设备销毁 listener）。
    private var activeClient: RPPairingClient?
    /// M2：持有隧道与 DTX 连接（定位注入期间保持存活）。
    private var activeTunnel: PSKTunnelClient?
    /// 连续坐标写入泵：串行发送、只保留最新坐标，避免 250ms 跑道 tick 堵塞 UI
    /// 或在链路抖动时堆积过期坐标。
    private var locationUpdatePump: DTXLocationUpdatePump?
    /// M2：定位注入是否成功（驱动"清除模拟定位"按钮）。
    @Published private(set) var m2LocationInjected = false
    /// M2 终验：经 CoreLocation 读回系统级坐标的一次性验证器。
    private let locationVerifier = LocationVerifier()

    private let tunnelBundleID = "com.zhangjiahui.locationmocker.tunnel"
    private let rppHost = "10.7.0.1"
    private let rppPort: UInt16 = 49152
    private let rsdProbePort: UInt16 = 58783

    // MARK: - 入口

    func startDiagnostic() {
        guard !phase.isRunning else { return }
        Task {
            do {
                try await startInjection(latitude: 39.9042, longitude: 116.4074,
                                         verboseProtocol: true)
            } catch {
                // startInjection 已记录并发布失败状态。
            }
        }
    }

    /// 主功能入口：建立 M2 会话并注入首个坐标。返回时 LocationSimulation 通道
    /// 已可复用，后续路线 tick 直接调用 updateLocation。
    func startInjection(latitude: Double, longitude: Double,
                        verboseProtocol: Bool = false) async throws {
        if let pump = locationUpdatePump, m2LocationInjected {
            pump.submit(latitude: latitude, longitude: longitude)
            return
        }
        guard !phase.isRunning else {
            throw NSError(domain: "RemoteInjection", code: 20,
                          userInfo: [NSLocalizedDescriptionKey: "注入链路正在连接，请稍候"])
        }

        // 全局忽略 SIGPIPE：任何遗留裸 socket 写入对端已关连接时不杀进程
        signal(SIGPIPE, SIG_IGN)
        logs = []
        resetLogFile()
        log("开始 M2 独立注入（模式：\(loopbackMode.rawValue)）")
        log(PairingIdentity.inspectBundledLockdownRecord())

        do {
            switch loopbackMode {
            case .directLoopback:
                try await runHandshake(targetLat: latitude, targetLon: longitude,
                                       verboseProtocol: verboseProtocol)
            case .selfTunnel:
                #if targetEnvironment(simulator)
                log("模拟器不支持 NetworkExtension 回环隧道")
                throw NSError(domain: "RemoteInjection", code: 21,
                              userInfo: [NSLocalizedDescriptionKey: "模拟器环境不支持"])
                #else
                phase = .installingTunnel
                log("提示：自建隧道需要 Network Extensions 签名（付费开发者账号）")
                try await ensureTunnelRunning()
                try await runHandshake(targetLat: latitude, targetLon: longitude,
                                       verboseProtocol: verboseProtocol)
                #endif
            }
        } catch {
            locationUpdatePump = nil
            m2LocationInjected = false
            activeTunnel?.close()
            activeTunnel = nil
            activeClient = nil
            log("失败：\(String(describing: error))")
            phase = .failed(String(describing: error))
            throw error
        }
    }

    /// 路线/跑道游标推送。写入在专用串行队列执行，调用方不会被 DTX 回复等待阻塞。
    func updateLocation(latitude: Double, longitude: Double) {
        locationUpdatePump?.submit(latitude: latitude, longitude: longitude)
    }

    func stop() {
        Task {
            let managers = try? await NETunnelProviderManager.loadAllFromPreferences()
            managers?.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == tunnelBundleID
            }?.connection.stopVPNTunnel()
            log("已请求停止隧道")
        }
    }

    // MARK: - 隧道

    private func ensureTunnelRunning() async throws {
        log("查找/创建隧道配置（\(tunnelBundleID)）")
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == tunnelBundleID
        } ?? NETunnelProviderManager()

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleID
        proto.serverAddress = "127.0.0.1"  // 占位，回环隧道不连外网
        manager.protocolConfiguration = proto
        manager.localizedDescription = "LocationMocker 回环隧道"
        manager.isEnabled = true
        try await manager.saveToPreferences()
        // 保存后重新加载，避免使用过期对象
        try await manager.loadFromPreferences()
        log("隧道配置已保存并启用")

        if manager.connection.status == .connected {
            log("隧道已在运行")
        } else {
            phase = .startingTunnel
            log("启动隧道扩展…")
            do {
                try manager.connection.startVPNTunnel()
            } catch {
                throw NSError(domain: "RemoteInjection", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "启动隧道失败：\(error.localizedDescription)"])
            }
            // 等待 connected（最长 10 秒）
            let deadline = Date().addingTimeInterval(10)
            while manager.connection.status != .connected {
                if Date() > deadline {
                    throw NSError(domain: "RemoteInjection", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "等待隧道连接超时（状态 \(manager.connection.status.rawValue)）"])
                }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            log("隧道已连接")
        }
    }

    // MARK: - 握手

    private func runHandshake(targetLat: Double, targetLon: Double,
                              verboseProtocol: Bool) async throws {
        phase = .handshaking
        let client = RPPairingClient()
        activeClient = client  // 保持控制连接，listener 才不会被设备销毁
        client.onProgress = { [weak self] step, message in
            Task { @MainActor in
                self?.log("[\(step.rawValue)] \(message)")
            }
        }

        // 后台线程跑客户端，避免阻塞 MainActor
        let (host, port) = (rppHost, rppPort)
        let summary = try await Task.detached {
            try await client.run(host: host, port: port)
        }.value
        log(summary)

        // M2 第一步：createTcpListener（设备开 TLS-PSK 端口）
        let listenerPort = try await Task.detached {
            try await client.createTcpListener()
        }.value

        // M2 第二步：TLS1.2-PSK 连接 + CDTunnel 握手
        guard let psk = await client.encryptionKey else {
            throw NSError(domain: "M2", code: 9,
                          userInfo: [NSLocalizedDescriptionKey: "配对成功但未生成 TLS-PSK 密钥"])
        }
        let tunnel = PSKTunnelClient()
        do {
            let params = try await Task.detached {
                try tunnel.connect(host: "10.7.0.1", port: listenerPort, psk: psk)
            }.value
            log("M2 隧道握手成功：server=\(params.serverAddress):\(params.serverRSDPort)，client=\(params.clientAddress)，mtu=\(params.mtu)")

            // M2 第三~五步：userspace TCP → RSD/RemoteXPC → DTX LocationSimulation
            try await runM2Injection(tunnel: tunnel, params: params,
                                     targetLat: targetLat, targetLon: targetLon,
                                     verboseProtocol: verboseProtocol)
        } catch {
            log("M2 失败：\(String(describing: error))")
            tunnel.close()
            throw error
        }

        // 附带实验：探测 RSD 直连端口（M2 线索，纯信息记录）
        if verboseProtocol { await probeRSDPort() }

        phase = .succeeded(summary)
    }

    // MARK: - M2 注入链（userspace TCP → RSD/RemoteXPC → DTX LocationSimulation）

    /// 防猝死的直写日志（不经过 MainActor 跳转，进程被杀也能落盘到最后位置）。
    private static let rawLogLock = NSLock()
    nonisolated private func rawLog(_ text: String) {
        Self.rawLogLock.lock()
        defer { Self.rawLogLock.unlock() }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let stamped = "\(formatter.string(from: Date()))  [raw] \(text)\n"
        guard let data = stamped.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: Self.logFileURL) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? stamped.write(to: Self.logFileURL, atomically: false, encoding: .utf8)
        }
    }

    /// 在 CDTunnel 之上完成：TCP#1 → RSD 取 peer_info → TCP#2 → dtservicehub →
    /// DTX 握手 → 开 LocationSimulation 通道 → 注入目标坐标。
    /// 注意：RSD 与 DTX 两条 TCP 分时复用同一隧道（取完 peer_info 即关 RSD 连接）。
    private func runM2Injection(tunnel: PSKTunnelClient,
                                params: PSKTunnelClient.TunnelParameters,
                                targetLat: Double,
                                targetLon: Double,
                                verboseProtocol: Bool) async throws {
        // 心跳：证明进程/任务存活，猝死后能看到最后心跳时间
        let heartbeat = Heartbeat { [weak self] in self?.rawLog("…M2 心跳") }
        heartbeat.start()
        do {
            try await Task.detached { [weak self] in
                let raw: (String) -> Void = { msg in self?.rawLog(msg) }
                let log: (String) -> Void = { msg in
                    self?.rawLog(msg)
                    Task { @MainActor in self?.log(msg) }
                }
                raw("detached 任务已进入")
                tunnel.enterTunnelMode()
                raw("enterTunnelMode 完成")
                let pipeRead: (Date) throws -> Data? = { deadline in
                    try tunnel.readTunnelPacket(until: deadline)
                }
                let pipeWrite: (Data) throws -> Void = { pkt in
                    try tunnel.writeTunnelPacket(pkt)
                }

                // --- TCP#1：RSD（RemoteXPC） ---
                log("M2-3 userspace TCP → RSD :\(params.serverRSDPort)…")
                let tcpRSD = UserspaceTCP(readPacket: pipeRead, writePacket: pipeWrite,
                                          clientIPv6: params.clientAddress,
                                          serverIPv6: params.serverAddress, log: log)
                raw("UserspaceTCP 实例已建，开始 connect")
                try tcpRSD.connect(port: params.serverRSDPort)
                log("M2-3 TCP#1 已建立，开始 RemoteXPC 握手…")
                let xpc = RemoteXPCClient(tcp: tcpRSD, log: log)
                try xpc.performHandshake()
                raw("HTTP/2 握手完成")
                let peerInfo = try xpc.exchangeDeviceHandshake()
                raw("peer_info 收到，顶层键：\(peerInfo.keys.sorted())")
                if let json = try? JSONSerialization.data(withJSONObject: peerInfo),
                   let text = String(data: json, encoding: .utf8) {
                    raw("peer_info 内容（截断 800）：\(String(text.prefix(800)))")
                }
                guard let services = peerInfo["Services"] as? [String: Any] else {
                    throw NSError(domain: "M2", code: 10,
                                  userInfo: [NSLocalizedDescriptionKey: "peer_info 无 Services 字段"])
                }
                log("M2-3 peer_info 到手：\(services.count) 个服务")
                for name in services.keys.sorted() where name.contains("instruments") {
                    log("  instruments 服务: \(name)")
                }
                tcpRSD.close()

                guard let dt = services["com.apple.instruments.dtservicehub"] as? [String: Any],
                      let portAny = dt["Port"] else {
                    throw NSError(domain: "M2", code: 11,
                                  userInfo: [NSLocalizedDescriptionKey: "peer_info 无 dtservicehub 端口"])
                }
                let dtxPort: UInt16
                switch portAny {
                case let s as String: dtxPort = UInt16(s) ?? 0
                case let n as UInt64: dtxPort = UInt16(n)
                case let n as Int64: dtxPort = UInt16(n)
                case let n as Int: dtxPort = UInt16(n)
                default: dtxPort = 0
                }
                guard dtxPort != 0 else {
                    throw NSError(domain: "M2", code: 12,
                                  userInfo: [NSLocalizedDescriptionKey: "dtservicehub 端口解析失败：\(portAny)"])
                }
                log("M2-4 dtservicehub 端口=\(dtxPort)，建 TCP#2…")

                // --- TCP#2：DTX（LocationSimulation） ---
                let tcpDTX = UserspaceTCP(readPacket: pipeRead, writePacket: pipeWrite,
                                          clientIPv6: params.clientAddress,
                                          serverIPv6: params.serverAddress, log: log)
                try tcpDTX.connect(port: dtxPort)
                log("M2-4 TCP#2 已建立，开始 DTX 握手…")
                // 诊断时完整展示线协议；产品路线运行时关闭逐包日志，避免 4Hz
                // 注入让 UI 日志和磁盘文件无限增长。
                let dtx = DTXClient(tcp: tcpDTX, log: verboseProtocol ? log : { _ in })
                try dtx.handshake()
                raw("DTX 能力握手完成")
                try dtx.openLocationChannel()
                raw("LocationSimulation 通道已开")

                // --- 注入坐标 ---
                log("M2-5 注入坐标 \(targetLat), \(targetLon)…")
                try dtx.setLocation(latitude: targetLat, longitude: targetLon)
                log("🎉 M2 定位注入成功：\(targetLat), \(targetLon)")
                await MainActor.run {
                    self?.activeTunnel = tunnel
                    self?.locationUpdatePump = DTXLocationUpdatePump(
                        dtx: dtx,
                        onError: { [weak self] error in
                            Task { @MainActor in
                                self?.log("连续定位注入失败：\(String(describing: error))")
                                self?.m2LocationInjected = false
                                self?.locationUpdatePump = nil
                                self?.activeTunnel?.close()
                                self?.activeTunnel = nil
                                self?.activeClient = nil
                                self?.phase = .failed(String(describing: error))
                            }
                        }
                    )
                    self?.m2LocationInjected = true
                    // 终验：经 CoreLocation 读回系统级坐标，证明注入对全系统生效
                    self?.locationVerifier.verify(expectedLatitude: targetLat,
                                                  expectedLongitude: targetLon) { [weak self] result in
                        Task { @MainActor in
                            self?.log(result)
                        }
                    }
                }
            }.value
        } catch {
            rawLog("detached 任务抛错：\(String(describing: error))")
            heartbeat.stop()
            throw error
        }
        heartbeat.stop()
        rawLog("detached 任务正常结束")
    }

    /// 简单心跳器（防猝死取证）。
    private final class Heartbeat: @unchecked Sendable {
        private let tick: () -> Void
        private var stopped = false
        private let lock = NSLock()
        init(tick: @escaping () -> Void) { self.tick = tick }
        func start() {
            Thread.detachNewThread { [weak self] in
                while true {
                    Thread.sleep(forTimeInterval: 2)
                    guard let self = self else { return }
                    self.lock.lock()
                    let s = self.stopped
                    self.lock.unlock()
                    if s { return }
                    self.tick()
                }
            }
        }
        func stop() {
            lock.lock()
            stopped = true
            lock.unlock()
        }
    }

    /// 只读验证模式：不做任何注入，仅经 CoreLocation 读回当前系统坐标。
    func runLocationVerificationOnly() {
        signal(SIGPIPE, SIG_IGN)
        logs = []
        resetLogFile()
        log("只读验证：经 CoreLocation 读取当前系统坐标…")
        locationVerifier.verify { [weak self] result in
            Task { @MainActor in self?.log("只读验证结果：\(result)") }
        }
    }

    /// 清除模拟定位并断开 M2 链路。
    func clearInjectedLocation() {
        guard let pump = locationUpdatePump else { return }
        locationUpdatePump = nil
        m2LocationInjected = false
        log("清除模拟定位：停止接收新坐标并发送 stopLocationSimulation…")
        pump.stop { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.log("stop 已送达，保持隧道 3 秒让设备完成处理…")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.activeTunnel?.close()
                self.activeTunnel = nil
                self.activeClient = nil
                self.phase = .idle
                self.log("模拟定位已清除，M2 隧道已关闭")
            }
        }
    }

    /// 等待清除完成，供主界面的停止流程和测试调用。
    func clearInjectedLocationAndWait() async {
        guard let pump = locationUpdatePump else { return }
        locationUpdatePump = nil
        m2LocationInjected = false
        log("清除模拟定位：发送 stopLocationSimulation…")
        await withCheckedContinuation { continuation in
            pump.stop { continuation.resume() }
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        activeTunnel?.close()
        activeTunnel = nil
        activeClient = nil
        phase = .idle
        log("模拟定位已清除，M2 隧道已关闭")
    }

    /// 探测 10.7.0.1:58783（remotepairingd 的 RSD 直连端口，M2 候选路径）。
    private func probeRSDPort() async {
        log("探测 RSD 直连端口 \(rppHost):\(rsdProbePort)…")
        let host = rppHost
        let port = rsdProbePort
        let reachable = await Task.detached { () -> Bool in
            let conn = NWConnection(host: NWEndpoint.Host(host),
                                    port: NWEndpoint.Port(rawValue: port)!,
                                    using: .tcp)
            defer { conn.cancel() }
            return await withCheckedContinuation { cont in
                final class Box { var resumed = false; let lock = NSLock() }
                let box = Box()
                conn.stateUpdateHandler = { state in
                    let hit: Bool?
                    switch state {
                    case .ready: hit = true
                    case .failed, .waiting, .cancelled: hit = false
                    default: hit = nil
                    }
                    if let hit = hit {
                        box.lock.lock()
                        if !box.resumed {
                            box.resumed = true
                            box.lock.unlock()
                            cont.resume(returning: hit)
                        } else {
                            box.lock.unlock()
                        }
                    }
                }
                conn.start(queue: .global())
            }
        }.value
        log(reachable ? "RSD 端口可达（M2 或可无 TLS-PSK）" : "RSD 端口不可达，M2 需走 pair-verify 后的 TCP 隧道")
    }

    // MARK: - 日志

    /// 沙盒日志文件（供 devicectl copy 拉回做无接触验证）。
    nonisolated private static var logFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("diag-m1.log")
    }

    private func resetLogFile() {
        try? "".write(to: Self.logFileURL, atomically: true, encoding: .utf8)
    }

    private func log(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let stamped = "\(formatter.string(from: Date()))  \(text)"
        logs.append(LogLine(time: formatter.string(from: Date()), text: text))
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
        NSLog("[LocationMocker][M1] %@", text)  // 供统一日志抓取
        if let handle = try? FileHandle(forWritingTo: Self.logFileURL) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: Data((stamped + "\n").utf8))
            try? handle.close()
        } else {
            try? (stamped + "\n").write(to: Self.logFileURL, atomically: false, encoding: .utf8)
        }
    }
}

/// DTX 连续坐标发送器。
///
/// DTXClient/UserspaceTCP 都是有状态协议对象，不能从多个 Timer tick 并发访问。
/// 此发送器把所有写入放到一条串行队列；链路短暂变慢时覆盖 pending 坐标，
/// 让恢复后发送“当前位置”而不是追赶已经过时的整段轨迹。
private final class DTXLocationUpdatePump: @unchecked Sendable {
    private let dtx: DTXClient
    private let onError: (Error) -> Void
    private let queue = DispatchQueue(label: "com.zhangjiahui.locationmocker.dtx-location")
    private let lock = NSLock()
    private var pending: (latitude: Double, longitude: Double)?
    private var drainScheduled = false
    private var stopping = false

    init(dtx: DTXClient, onError: @escaping (Error) -> Void) {
        self.dtx = dtx
        self.onError = onError
    }

    func submit(latitude: Double, longitude: Double) {
        lock.lock()
        guard !stopping else {
            lock.unlock()
            return
        }
        pending = (latitude, longitude)
        if drainScheduled {
            lock.unlock()
            return
        }
        drainScheduled = true
        lock.unlock()

        queue.async { [weak self] in self?.drain() }
    }

    private func drain() {
        while true {
            lock.lock()
            guard !stopping, let coordinate = pending else {
                pending = nil
                drainScheduled = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()

            do {
                try dtx.setLocation(latitude: coordinate.latitude,
                                    longitude: coordinate.longitude,
                                    timeout: 3)
            } catch {
                lock.lock()
                stopping = true
                pending = nil
                drainScheduled = false
                lock.unlock()
                onError(error)
                return
            }
        }
    }

    func stop(completion: @escaping @Sendable () -> Void) {
        lock.lock()
        stopping = true
        pending = nil
        lock.unlock()
        queue.async { [dtx] in
            dtx.stopLocation()
            completion()
        }
    }
}

/// M2 终验：注入完成后经 CLLocationManager 读回系统级坐标。
/// 读回的若是注入坐标，证明 LocationSimulation 对全系统 CoreLocation 生效。
final class LocationVerifier: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((String) -> Void)?
    private var done = false
    private var expectedCoordinate: CLLocationCoordinate2D?
    private var lastObservedLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func verify(expectedLatitude: Double? = nil,
                expectedLongitude: Double? = nil,
                completion: @escaping (String) -> Void) {
        self.completion = completion
        done = false
        lastObservedLocation = nil
        if let expectedLatitude, let expectedLongitude {
            expectedCoordinate = CLLocationCoordinate2D(latitude: expectedLatitude,
                                                        longitude: expectedLongitude)
        } else {
            expectedCoordinate = nil
        }
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            requestVerificationLocation()
        default:
            completion("定位验证失败：无定位权限（\(status.rawValue)）")
        }
        // 超时兜底
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self = self, !self.done else { return }
            self.done = true
            self.manager.stopUpdatingLocation()
            if let loc = self.lastObservedLocation, let expected = self.expectedCoordinate {
                let distance = loc.distance(from: CLLocation(latitude: expected.latitude,
                                                             longitude: expected.longitude))
                self.completion?(String(format: "定位验证超时：最后读回 %.6f, %.6f，距本轮目标 %.0fm",
                                        loc.coordinate.latitude, loc.coordinate.longitude, distance))
            } else {
                self.completion?("定位验证超时：8 秒内未收到坐标回调")
            }
        }
    }

    private func requestVerificationLocation() {
        if expectedCoordinate == nil {
            manager.requestLocation()
        } else {
            // requestLocation 可能只回一条上一轮模拟的缓存坐标；持续监听到本轮目标
            // 真正传播到 locationd，或由 8 秒超时收尾。
            manager.startUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways, !done {
            requestVerificationLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !done, let loc = locations.last else { return }
        lastObservedLocation = loc
        if let expected = expectedCoordinate {
            let distance = loc.distance(from: CLLocation(latitude: expected.latitude,
                                                         longitude: expected.longitude))
            // 忽略上一轮缓存定位，直至本轮模拟坐标在 100m 内生效。
            guard distance <= 100 else { return }
        }
        done = true
        manager.stopUpdatingLocation()
        let age = Date().timeIntervalSince(loc.timestamp)
        completion?(String(format: "✅ 终验：CoreLocation 读回坐标 %.4f, %.4f（精度 %.0fm，时间戳 %.1f 秒前）",
                           loc.coordinate.latitude, loc.coordinate.longitude,
                           loc.horizontalAccuracy, age))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !done else { return }
        done = true
        manager.stopUpdatingLocation()
        completion?("定位验证失败：\(error.localizedDescription)")
    }
}
