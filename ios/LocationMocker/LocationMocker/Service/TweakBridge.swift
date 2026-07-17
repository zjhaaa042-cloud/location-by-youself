import Foundation
import CoreLocation

/// 与越狱插件通信的桥接层
/// 将模拟配置写入共享 plist 文件，并通过 Darwin Notification 通知 tweak 更新
enum TweakBridge {

    // MARK: - 共享文件路径

    /// 获取 tweak 读取的共享配置文件路径
    static var configPath: String {
        // rootless jailbreak 优先
        let rootless = "/var/jb/var/mobile/Documents/location_mock_config.plist"
        if FileManager.default.fileExists(atPath: "/var/jb") {
            return rootless
        }
        // rootful 回退
        return "/var/mobile/Documents/location_mock_config.plist"
    }

    // MARK: - 写入配置

    /// 写入固定点模拟配置
    static func writeFixedPoint(lat: Double, lon: Double, altitude: Double = 0) {
        let config: [String: Any] = [
            "enabled": true,
            "latitude": lat,
            "longitude": lon,
            "altitude": altitude,
            "speed": 0,
            "course": 0,
            "horizontalAccuracy": 5.0,
            "verticalAccuracy": 10.0,
            "timestamp": Date().timeIntervalSince1970,
            "mode": "fixed",
            "routePoints": [],
            "routeIndex": 0,
            "updateInterval": 1.0,
        ]
        saveAndNotify(config)
    }

    /// 写入路线模拟配置
    static func writeRoute(
        points: [RoutePoint],
        speedMs: Float,
        bearing: Float,
        mode: String,
        interval: Double = 1.0
    ) {
        let routePoints: [[String: Any]] = points.map { pt in
            ["lat": pt.lat, "lon": pt.lon, "alt": pt.altitude ?? 0]
        }
        let config: [String: Any] = [
            "enabled": true,
            "latitude": points.first?.lat ?? 0,
            "longitude": points.first?.lon ?? 0,
            "altitude": points.first?.altitude ?? 0,
            "speed": speedMs,
            "course": bearing,
            "horizontalAccuracy": 5.0,
            "verticalAccuracy": 10.0,
            "timestamp": Date().timeIntervalSince1970,
            "mode": "route",
            "routePoints": routePoints,
            "routeIndex": 0,
            "updateInterval": interval,
            "playbackMode": mode,
        ]
        saveAndNotify(config)
    }

    /// 停止模拟
    static func stopMocking() {
        let config: [String: Any] = [
            "enabled": false,
            "mode": "fixed",
            "routePoints": [],
            "routeIndex": 0,
        ]
        saveAndNotify(config)
    }

    // MARK: - 检查环境

    /// 检测当前设备是否已越狱
    static var isJailbroken: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let paths = [
            "/var/jb",
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/usr/libexec/substituted",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/usr/lib/libsubstitute.dylib",
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        // 尝试写入越狱目录
        let testPath = "/var/jb/var/mobile/Documents/.jb_test"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            return false
        }
        #endif
    }

    // MARK: - Private

    private static func saveAndNotify(_ config: [String: Any]) {
        // 确保目录存在
        let dir = (configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir,
                                                  withIntermediateDirectories: true)

        // 写入 plist
        (config as NSDictionary).write(toFile: configPath, atomically: true)

        // 通过 Darwin Notification 通知 tweak
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName("com.example.locationmocker.configChanged" as CFString),
            nil, nil, true
        )
    }
}
