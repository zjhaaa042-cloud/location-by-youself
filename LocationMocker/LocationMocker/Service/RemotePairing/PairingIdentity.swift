import CryptoKit
import Foundation

/// 远程配对身份：Ed25519 密钥对 + identifier，持久化于 Application Support。
/// 与 StikDebug 的 rp_pairing_file.plist 同构：{identifier, public_key, private_key}。
/// 注意：任务附带的 pairing_record.mobiledevicepairing 是 lockdown RSA 记录，
/// 与 RPPairing pair-verify 所需的 Ed25519 记录格式不同，无法复用。
struct PairingIdentity {
    let identifier: String
    let privateKey: Curve25519.Signing.PrivateKey

    var publicKeyData: Data { privateKey.publicKey.rawRepresentation }

    // MARK: - 持久化

    private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("rp_pairing_file.plist")
    }

    /// 读取身份。优先级：① bundle 内一次性桌面引导生成的 rp_pairing_file.plist
    ///（设备已注册该身份，pair-verify 直接通过）；② 沙盒已持久化身份；③ 新建身份。
    static func loadOrCreate() throws -> PairingIdentity {
        if let bundled = loadBundled() {
            return bundled
        }
        let url = storeURL
        if let data = try? Data(contentsOf: url),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let identifier = dict["identifier"] as? String,
           let priv = dict["private_key"] as? Data,
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: priv) {
            return PairingIdentity(identifier: identifier, privateKey: key)
        }

        let key = Curve25519.Signing.PrivateKey()
        let identifier = UUID().uuidString
        let identity = PairingIdentity(identifier: identifier, privateKey: key)
        try identity.save(to: url)
        return identity
    }

    /// bundle 内随包的 Ed25519 远程配对记录（一次性桌面引导产物，仅调试用）。
    private static func loadBundled() -> PairingIdentity? {
        guard let url = Bundle.main.url(forResource: "rp_pairing_file", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let identifier = dict["identifier"] as? String,
              let priv = dict["private_key"] as? Data,
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: priv) else {
            return nil
        }
        return PairingIdentity(identifier: identifier, privateKey: key)
    }

    private func save(to url: URL) throws {
        let dict: [String: Any] = [
            "identifier": identifier,
            "public_key": publicKeyData,
            "private_key": privateKey.rawRepresentation,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        // 0600：仅属主可读写
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: - 调试用 lockdown 记录检测

    /// 检测 bundle 内附带的 lockdown 配对记录（格式与 RPPairing 不兼容，仅作诊断展示）。
    static func inspectBundledLockdownRecord() -> String {
        guard let url = Bundle.main.url(forResource: "pairing_record", withExtension: "mobiledevicepairing"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return "未找到随包配对记录"
        }
        var parts: [String] = ["检测到随包 pairing_record.mobiledevicepairing（lockdown RSA 格式）"]
        if let hostID = dict["HostID"] as? String {
            parts.append("HostID: \(hostID)")
        }
        if Bundle.main.url(forResource: "rp_pairing_file", withExtension: "plist") != nil {
            parts.append("已载入随包 Ed25519 rp_pairing_file（桌面引导产物，pair-verify 应直接通过）")
        } else if dict["HostCertificate"] != nil {
            parts.append("含 HostCertificate/私钥，但 RPPairing 需要 Ed25519 身份，无法用于本次握手")
        }
        return parts.joined(separator: "；")
    }
}
