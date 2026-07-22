import CryptoKit
import Foundation
import Network
#if os(iOS)
import UIKit
#endif

/// RPPairing 协议客户端：通过 NE 回环隧道与本机 remotepairingd 完成
/// handshake → pair-verify →（必要时）SRP 手动配对 → 重连再 verify 的全流程。
/// 协议格式对照 pymobiledevice3 remote/tunnel_service.py 与 idevice remote_pairing/。
final class RPPairingClient: @unchecked Sendable {

    enum Step: String {
        case connecting = "建立 TCP 连接"
        case handshake = "RPPairing 握手"
        case pairVerify = "Pair-Verify 验证"
        case manualPairing = "SRP 手动配对"
        case reconnecting = "配对后重连"
        case derivingKeys = "派生会话密钥"
        case createListener = "创建隧道监听"
        case verified = "验证通过"
    }

    enum RPPairingError: Error, CustomStringConvertible {
        case connectFailed(String)
        case frameIO(String)
        case badResponse(String)
        case pairVerifyRejected
        case pairingRejectedByUser(String)
        case serverProofMismatch
        case tlvMissing(String)

        var description: String {
            switch self {
            case .connectFailed(let s): return "连接失败：\(s)"
            case .frameIO(let s): return "帧读写错误：\(s)"
            case .badResponse(let s): return "响应格式异常：\(s)"
            case .pairVerifyRejected: return "设备拒绝 pair-verify（身份未知）"
            case .pairingRejectedByUser(let s): return "配对被拒绝：\(s)"
            case .serverProofMismatch: return "SRP 设备证明 M2 校验失败"
            case .tlvMissing(let s): return "TLV 缺少字段：\(s)"
            }
        }
    }

    /// 进度回调（主线程派发由调用方保证）。
    var onProgress: ((Step, String) -> Void)?

    private let wireProtocolVersion = 19
    private var sequenceNumber = 0
    private var connection: NWConnection?
    private var identity: PairingIdentity?

    /// 会话产物（供诊断展示与后续 M2 使用）。
    private(set) var peerDeviceInfo: [String: Any]?
    private(set) var encryptionKey: Data?       // pair-verify/SRP 共享主密钥材料（TLS-PSK 的 PSK）
    private(set) var clientMainKey: Data?       // ClientEncrypt-main
    private(set) var serverMainKey: Data?       // ServerEncrypt-main
    private var encryptedSeq: UInt64 = 0

    // MARK: - M2：createTcpListener

    /// pair-verify 通过后，让设备在本机开一个 TLS-PSK 监听端口，返回端口号。
    /// PSK 即 encryptionKey（X25519 原始共享密钥）。
    func createTcpListener() async throws -> UInt16 {
        guard let key = encryptionKey else { throw RPPairingError.badResponse("无加密密钥") }
        let pid = UInt32(ProcessInfo.processInfo.processIdentifier)
        let request: [String: Any] = [
            "request": ["_0": ["createListener": [
                "key": key.base64EncodedString(),
                "peerConnectionsInfo": [["owningPID": pid, "owningProcessName": "CoreDeviceService"]],
                "transportProtocolType": "tcp",
            ]]],
        ]
        report(.createListener, "请求设备创建 TCP listener（TLS-PSK）")
        let response = try await sendReceiveEncrypted(request)
        guard let listener = response["createListener"] as? [String: Any],
              let port = listener["port"] as? Int, port > 0, port <= 65535 else {
            throw RPPairingError.badResponse("createListener 响应异常：\(response.keys.joined(separator: ","))")
        }
        report(.createListener, "设备已开端口 \(port)")
        return UInt16(port)
    }

    /// streamEncrypted 请求/响应（nonce = LE(u64 seq) + 4×0x00，请求响应共用）。
    private func sendReceiveEncrypted(_ request: [String: Any]) async throws -> [String: Any] {
        guard let clientKey = clientMainKey, let serverKey = serverMainKey else {
            throw RPPairingError.badResponse("主会话密钥未派生")
        }
        var nonce = Data(count: 12)
        withUnsafeBytes(of: encryptedSeq.littleEndian) { nonce.replaceSubrange(0..<8, with: $0) }

        let plaintext = try JSONSerialization.data(withJSONObject: request)
        let sealed = try ChaChaPoly.seal(plaintext,
                                         using: SymmetricKey(data: clientKey),
                                         nonce: ChaChaPoly.Nonce(data: nonce))
        try sendFrame([
            "message": ["streamEncrypted": ["_0": (sealed.ciphertext + sealed.tag).base64EncodedString()]],
            "originatedBy": "host",
            "sequenceNumber": sequenceNumber,
        ])
        sequenceNumber += 1

        let respFrame = try await receiveFrame()
        guard let message = respFrame["message"] as? [String: Any],
              let enc = message["streamEncrypted"] as? [String: Any],
              let b64 = enc["_0"] as? String,
              let encData = Data(base64Encoded: b64), encData.count > 16 else {
            throw RPPairingError.badResponse("加密响应缺失")
        }
        let box = try ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: nonce),
                                           ciphertext: encData.dropLast(16),
                                           tag: encData.suffix(16))
        let plain = try ChaChaPoly.open(box, using: SymmetricKey(data: serverKey))
        encryptedSeq += 1

        guard let json = try JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let body = response["_1"] as? [String: Any] else {
            throw RPPairingError.badResponse("加密响应 JSON 结构异常")
        }
        if let err = body["errorExtended"] as? [String: Any],
           let info = (err["_0"] as? [String: Any])?["userInfo"] as? [String: Any],
           let desc = info["NSLocalizedDescription"] as? String {
            throw RPPairingError.badResponse("设备拒绝：\(desc)")
        }
        return body
    }

    // MARK: - 入口

    /// 完整流程：连接 → 握手 → pair-verify →（失败则 SRP 配对并重连 verify）。
    /// 返回可读的结果摘要。
    @discardableResult
    func run(host: String, port: UInt16) async throws -> String {
        sequenceNumber = 0
        let id = try PairingIdentity.loadOrCreate()
        identity = id

        try await connectAndVerify(host: host, port: port, allowPairing: true)

        let model = peerDeviceInfo?["model"] as? String ?? "未知型号"
        let identifier = peerDeviceInfo?["identifier"] as? String ?? "未知标识"
        return "握手完成：\(model)（\(identifier)），pair-verify 通过，主会话密钥已派生"
    }

    private func connectAndVerify(host: String, port: UInt16, allowPairing: Bool) async throws {
        try await openConnection(host: host, port: port)
        try await performHandshake()
        if try await performPairVerify() {
            try deriveMainKeys()
            report(.verified, "pair-verify 通过")
            return
        }
        guard allowPairing else { throw RPPairingError.pairVerifyRejected }

        // pair-verify 失败后设备会断开连接（iOS 26 行为）。
        // 重建连接并以 attemptPairVerify=false 直接发起 SRP 配对——
        // 避免设备把会话锁定在"仅验证"模式。
        report(.reconnecting, "pair-verify 被拒，重建连接直接发起 SRP 配对")
        closeConnection()
        sequenceNumber = 0
        try await openConnection(host: host, port: port)
        try await performHandshake(attemptPairVerify: false)
        try await performManualPairing()

        // 配对成功后设备会主动断开，必须重连再 verify
        report(.reconnecting, "配对完成，设备断开连接，重新连接并再次验证")
        closeConnection()
        sequenceNumber = 0
        try await openConnection(host: host, port: port)
        try await performHandshake()
        guard try await performPairVerify() else {
            throw RPPairingError.pairVerifyRejected
        }
        try deriveMainKeys()
        report(.verified, "配对后 pair-verify 通过")
    }

    // MARK: - 连接与帧层

    private func openConnection(host: String, port: UInt16) async throws {
        report(.connecting, "连接 \(host):\(port)")
        let conn = NWConnection(host: NWEndpoint.Host(host),
                                port: NWEndpoint.Port(rawValue: port)!,
                                using: .tcp)
        connection = conn
        let box = StateBox()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            box.onReady = {
                conn.stateUpdateHandler = nil
                cont.resume()
            }
            box.onFailure = { error in
                conn.stateUpdateHandler = nil
                cont.resume(throwing: error)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    box.succeed()
                case .failed(let err), .waiting(let err):
                    box.fail(RPPairingError.connectFailed(err.localizedDescription))
                case .cancelled:
                    box.fail(RPPairingError.connectFailed("连接被取消"))
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    private func closeConnection() {
        connection?.cancel()
        connection = nil
    }

    /// 保证成功/失败回调只触发一次。
    private final class StateBox {
        private let lock = NSLock()
        private var finished = false
        var onReady: (() -> Void)?
        var onFailure: ((Error) -> Void)?

        func succeed() { fire { $0.onReady?() } }
        func fail(_ error: Error) { fire { $0.onFailure?(error) } }

        private func fire(_ action: (StateBox) -> Void) {
            lock.lock()
            if finished {
                lock.unlock()
                return
            }
            finished = true
            lock.unlock()
            action(self)
        }
    }

    /// 发送一帧：magic "RPPairing" + u16 BE 长度 + JSON body。
    private func sendFrame(_ json: [String: Any]) throws {
        guard let conn = connection else { throw RPPairingError.frameIO("无连接") }
        let body = try JSONSerialization.data(withJSONObject: json, options: [])
        var frame = Data("RPPairing".utf8)
        var len = UInt16(body.count).bigEndian
        frame.append(Data(bytes: &len, count: 2))
        frame.append(body)
        conn.send(content: frame, completion: .idempotent)
    }

    /// 接收一帧并解析 JSON。
    private func receiveFrame() async throws -> [String: Any] {
        guard let conn = connection else { throw RPPairingError.frameIO("无连接") }
        let header = try await receiveExact(conn, length: 11)
        guard header.prefix(9) == Data("RPPairing".utf8) else {
            throw RPPairingError.badResponse("帧 magic 不匹配")
        }
        let len = Int(header[9]) << 8 | Int(header[10])
        let body = try await receiveExact(conn, length: len)
        guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw RPPairingError.badResponse("JSON 解析失败")
        }
        return json
    }

    private func receiveExact(_ conn: NWConnection, length: Int) async throws -> Data {
        var buffer = Data()
        while buffer.count < length {
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                conn.receive(minimumIncompleteLength: 1, maximumLength: length - buffer.count) { data, _, isComplete, error in
                    if let error = error {
                        cont.resume(throwing: RPPairingError.frameIO(error.localizedDescription))
                    } else if let data = data, !data.isEmpty {
                        cont.resume(returning: data)
                    } else if isComplete {
                        cont.resume(throwing: RPPairingError.frameIO("连接被对端关闭"))
                    } else {
                        cont.resume(throwing: RPPairingError.frameIO("空读"))
                    }
                }
            }
            buffer.append(chunk)
        }
        return buffer
    }

    // MARK: - 信封层

    private func sendPlain(_ payload: [String: Any]) throws {
        try sendFrame([
            "message": ["plain": ["_0": payload]],
            "originatedBy": "host",
            "sequenceNumber": sequenceNumber,
        ])
        sequenceNumber += 1
    }

    private func receivePlain() async throws -> [String: Any] {
        let frame = try await receiveFrame()
        guard let message = frame["message"] as? [String: Any],
              let plain = message["plain"] as? [String: Any],
              let payload = plain["_0"] as? [String: Any] else {
            throw RPPairingError.badResponse("缺少 message.plain._0")
        }
        return payload
    }

    /// 发送 pairingData 事件。
    private func sendPairingData(_ tlv: Data, kind: String, startNewSession: Bool, sendingHost: String? = nil) throws {
        var inner: [String: Any] = [
            "data": tlv.base64EncodedString(),
            "kind": kind,
            "startNewSession": startNewSession,
        ]
        if let sendingHost = sendingHost {
            inner["sendingHost"] = sendingHost
        }
        try sendPlain(["event": ["_0": ["pairingData": ["_0": inner]]]])
    }

    /// 接收 pairingData 事件（处理 awaitingUserConsent / 拒绝）。
    private func receivePairingData() async throws -> Data {
        let payload = try await receivePlain()
        guard let event = payload["event"] as? [String: Any],
              let eventBody = event["_0"] as? [String: Any] else {
            throw RPPairingError.badResponse("缺少 event._0")
        }
        if let pairingData = eventBody["pairingData"] as? [String: Any],
           let dataDict = pairingData["_0"] as? [String: Any],
           let dataB64 = dataDict["data"] as? String,
           let data = Data(base64Encoded: dataB64) {
            return data
        }
        if eventBody["awaitingUserConsent"] != nil {
            // 设备正在等待用户确认 Trust 对话框，继续等下一帧
            return try await receivePairingData()
        }
        if let rejected = eventBody["pairingRejectedWithError"] as? [String: Any] {
            let wrapped = rejected["wrappedError"] as? [String: Any]
            let userInfo = wrapped?["userInfo"] as? [String: Any]
            let reason = userInfo?["NSLocalizedDescription"] as? String ?? "用户拒绝"
            throw RPPairingError.pairingRejectedByUser(reason)
        }
        throw RPPairingError.badResponse("未知事件：\(eventBody.keys.joined(separator: ","))")
    }

    // MARK: - 握手

    private func performHandshake(attemptPairVerify: Bool = true) async throws {
        report(.handshake, "发送 handshake（wireProtocolVersion=\(wireProtocolVersion), attemptPairVerify=\(attemptPairVerify)）")
        try sendPlain([
            "request": ["_0": ["handshake": ["_0": [
                "hostOptions": ["attemptPairVerify": attemptPairVerify],
                "wireProtocolVersion": wireProtocolVersion,
            ]]]],
        ])
        let payload = try await receivePlain()
        guard let response = payload["response"] as? [String: Any],
              let respBody = response["_1"] as? [String: Any],
              let handshake = respBody["handshake"] as? [String: Any],
              let handshakeBody = handshake["_0"] as? [String: Any] else {
            throw RPPairingError.badResponse("handshake 响应缺失，实际顶层键：\(payload.keys.joined(separator: ","))")
        }
        peerDeviceInfo = handshakeBody["peerDeviceInfo"] as? [String: Any]
        if let jsonData = try? JSONSerialization.data(withJSONObject: handshakeBody),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            report(.handshake, "handshake 完整响应：\(jsonStr)")
        }
    }

    // MARK: - Pair-Verify

    /// 返回 true 表示验证通过。
    private func performPairVerify() async throws -> Bool {
        guard let identity = identity else { throw RPPairingError.badResponse("无身份") }
        report(.pairVerify, "发起 pair-verify（identifier=\(identity.identifier.prefix(8))…）")

        // M1/M2：发送我方 X25519 公钥
        let x25519 = Curve25519.KeyAgreement.PrivateKey()
        var tlv = TLV8.encode([
            .init(type: TLV8.ItemType.state.rawValue, value: Data([0x01])),
            .init(type: TLV8.ItemType.publicKey.rawValue, value: x25519.publicKey.rawRepresentation),
        ])
        try sendPairingData(tlv, kind: "verifyManualPairing", startNewSession: true)

        let responseTLV = try TLV8.decode(await receivePairingData())
        if let errorCode = TLV8.first(.error, in: responseTLV)?.first {
            report(.pairVerify, "设备返回错误 \(errorCode)，身份未知，转入配对流程")
            return false
        }
        guard let peerKeyData = TLV8.first(.publicKey, in: responseTLV),
              let peerKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerKeyData) else {
            throw RPPairingError.tlvMissing("PublicKey")
        }

        // 共享密钥与派生
        let sharedSecret = try x25519.sharedSecretFromKeyAgreement(with: peerKey)
        let shared = sharedSecret.withUnsafeBytes { Data($0) }
        encryptionKey = shared
        let verifyKey = Self.hkdf(ikm: shared,
                                  salt: Data("Pair-Verify-Encrypt-Salt".utf8),
                                  info: Data("Pair-Verify-Encrypt-Info".utf8))

        // M3：签名（我方X25519公钥 ‖ identifier ‖ 设备公钥），加密后发送
        var signBuf = Data()
        signBuf.append(x25519.publicKey.rawRepresentation)
        signBuf.append(Data(identity.identifier.utf8))
        signBuf.append(peerKeyData)
        let signature = try identity.privateKey.signature(for: signBuf)

        let innerTLV = TLV8.encode([
            .init(type: TLV8.ItemType.identifier.rawValue, value: Data(identity.identifier.utf8)),
            .init(type: TLV8.ItemType.signature.rawValue, value: signature),
        ])
        // 协议仅发送 ciphertext+tag（nonce 为固定常量，不随帧传输）
        let sealedMsg03 = try ChaChaPoly.seal(
            innerTLV,
            using: SymmetricKey(data: verifyKey),
            nonce: ChaChaPoly.Nonce(data: Data([0, 0, 0, 0]) + Data("PV-Msg03".utf8)))
        let encrypted = sealedMsg03.ciphertext + sealedMsg03.tag
        tlv = TLV8.encode([
            .init(type: TLV8.ItemType.state.rawValue, value: Data([0x03])),
            .init(type: TLV8.ItemType.encryptedData.rawValue, value: encrypted),
        ])
        try sendPairingData(tlv, kind: "verifyManualPairing", startNewSession: false)

        let finalTLV = try TLV8.decode(await receivePairingData())
        if let errorCode = TLV8.first(.error, in: finalTLV)?.first {
            report(.pairVerify, "签名验证被拒（错误 \(errorCode)），转入配对流程")
            return false
        }
        return true
    }

    // MARK: - SRP 手动配对

    private func performManualPairing() async throws {
        guard let identity = identity else { throw RPPairingError.badResponse("无身份") }
        report(.manualPairing, "发起 SRP 配对，请在设备上确认“信任”对话框")

        // 第一步：Method+State → 设备弹 Trust 框 → 回 Salt+B
        var tlv = TLV8.encode([
            .init(type: TLV8.ItemType.method.rawValue, value: Data([0x00])),
            .init(type: TLV8.ItemType.state.rawValue, value: Data([0x01])),
        ])
        try sendPairingData(tlv, kind: "setupManualPairing",
                            startNewSession: true, sendingHost: Self.hostName)
        let consentTLV = try TLV8.decode(await receivePairingData())
        if let errorCode = TLV8.first(.error, in: consentTLV)?.first {
            throw RPPairingError.pairingRejectedByUser("设备错误码 \(errorCode)")
        }
        guard let salt = TLV8.first(.salt, in: consentTLV),
              let serverPublic = TLV8.first(.publicKey, in: consentTLV) else {
            throw RPPairingError.tlvMissing("Salt/PublicKey")
        }
        report(.manualPairing, "收到设备盐与公钥，计算 SRP 证明")

        // 第二步：SRP 计算 → 发 A+M1 → 校验 M2
        var srp = SRPClient(salt: salt, pin: "000000")
        try srp.processChallenge(serverPublicKey: serverPublic)
        guard let proof = srp.clientProof else { throw RPPairingError.badResponse("SRP 证明缺失") }
        tlv = TLV8.encode([
            .init(type: TLV8.ItemType.state.rawValue, value: Data([0x03])),
            .init(type: TLV8.ItemType.publicKey.rawValue, value: srp.clientPublicKey),
            .init(type: TLV8.ItemType.proof.rawValue, value: proof),
        ])
        try sendPairingData(tlv, kind: "setupManualPairing",
                            startNewSession: false, sendingHost: Self.hostName)
        let proofTLV = try TLV8.decode(await receivePairingData())
        guard let serverProof = TLV8.first(.proof, in: proofTLV) else {
            throw RPPairingError.tlvMissing("Proof(M2)")
        }
        guard srp.verifyServerProof(serverProof) else {
            throw RPPairingError.serverProofMismatch
        }
        guard let sessionKey = srp.sessionKey else { throw RPPairingError.badResponse("SRP 会话密钥缺失") }
        encryptionKey = sessionKey
        report(.manualPairing, "SRP 证明通过，向设备注册身份")

        // 第三步：注册身份（加密 TLV）
        let setupKey = Self.hkdf(ikm: sessionKey,
                                 salt: Data("Pair-Setup-Encrypt-Salt".utf8),
                                 info: Data("Pair-Setup-Encrypt-Info".utf8))
        let signKey = Self.hkdf(ikm: sessionKey,
                                salt: Data("Pair-Setup-Controller-Sign-Salt".utf8),
                                info: Data("Pair-Setup-Controller-Sign-Info".utf8))
        var signBuf2 = Data()
        signBuf2.append(signKey)
        signBuf2.append(Data(identity.identifier.utf8))
        signBuf2.append(identity.publicKeyData)
        let signature2 = try identity.privateKey.signature(for: signBuf2)

        let deviceInfo = OpackEncoder.encode(.dict([
            ("altIRK", .data(Data([0xE9, 0xE8, 0x2D, 0xC0, 0x6A, 0x49, 0x79, 0x6B,
                                   0x56, 0x6F, 0x54, 0x00, 0x19, 0xB1, 0xC7, 0x7B]))),
            ("btAddr", .string("11:22:33:44:55:66")),
            ("mac", .data(Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66]))),
            ("remotepairing_serial_number", .string("AAAAAAAAAAAA")),
            ("accountID", .string(identity.identifier)),
            ("model", .string("computer-model")),
            ("name", .string(Self.hostName)),
        ]))

        let innerTLV = TLV8.encode([
            .init(type: TLV8.ItemType.identifier.rawValue, value: Data(identity.identifier.utf8)),
            .init(type: TLV8.ItemType.publicKey.rawValue, value: identity.publicKeyData),
            .init(type: TLV8.ItemType.signature.rawValue, value: signature2),
            .init(type: TLV8.ItemType.info.rawValue, value: deviceInfo),
        ])
        // 协议仅发送 ciphertext+tag（nonce 为固定常量）
        let sealedMsg05 = try ChaChaPoly.seal(
            innerTLV,
            using: SymmetricKey(data: setupKey),
            nonce: ChaChaPoly.Nonce(data: Data([0, 0, 0, 0]) + Data("PS-Msg05".utf8)))
        let encrypted = sealedMsg05.ciphertext + sealedMsg05.tag
        tlv = TLV8.encode([
            .init(type: TLV8.ItemType.encryptedData.rawValue, value: encrypted),
            .init(type: TLV8.ItemType.state.rawValue, value: Data([0x05])),
        ])
        try sendPairingData(tlv, kind: "setupManualPairing",
                            startNewSession: false, sendingHost: Self.hostName)

        // PS-Msg06：解密确认（内容不重要，能解开即成功）。
        // 设备回包为 ciphertext+tag，nonce 固定为 "\0\0\0\0PS-Msg06"。
        let finalTLV = try TLV8.decode(await receivePairingData())
        guard let encryptedReply = TLV8.first(.encryptedData, in: finalTLV),
              encryptedReply.count > 16 else {
            throw RPPairingError.tlvMissing("EncryptedData(PS-Msg06)")
        }
        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: ChaChaPoly.Nonce(data: Data([0, 0, 0, 0]) + Data("PS-Msg06".utf8)),
            ciphertext: encryptedReply.dropLast(16),
            tag: encryptedReply.suffix(16)
        )
        _ = try ChaChaPoly.open(sealedBox, using: SymmetricKey(data: setupKey))
        report(.manualPairing, "身份已注册到设备")
    }

    // MARK: - 主密钥派生

    private func deriveMainKeys() throws {
        guard let key = encryptionKey else { throw RPPairingError.badResponse("无加密密钥") }
        report(.derivingKeys, "派生 ClientEncrypt-main / ServerEncrypt-main")
        clientMainKey = Self.hkdf(ikm: key, salt: Data(), info: Data("ClientEncrypt-main".utf8))
        serverMainKey = Self.hkdf(ikm: key, salt: Data(), info: Data("ServerEncrypt-main".utf8))
    }

    // MARK: - 工具

    static func hkdf(ikm: Data, salt: Data, info: Data) -> Data {
        let key = HKDF<SHA512>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm),
                                         salt: salt,
                                         info: info,
                                         outputByteCount: 32)
        return key.withUnsafeBytes { Data($0) }
    }

    private static var hostName: String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().name ?? "LocationMocker"
        #endif
    }

    private func report(_ step: Step, _ message: String) {
        onProgress?(step, message)
    }
}
