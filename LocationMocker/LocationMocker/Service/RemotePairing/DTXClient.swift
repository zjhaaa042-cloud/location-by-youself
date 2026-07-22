import Foundation

/// M2 DTX 协议客户端：在 userspace TCP 之上与 com.apple.instruments.dtservicehub
/// 通信——能力握手 → 开 LocationSimulation 通道 → simulateLocation / stopLocationSimulation。
/// 线格式与 pymobiledevice3 dtx/ 逐字节对齐（金样单测保证）。
final class DTXClient {

    enum DTXError: Error, CustomStringConvertible {
        case timeout(String)
        case protocolError(String)
        case deviceError(String)

        var description: String {
            switch self {
            case .timeout(let s): return "DTX 超时：\(s)"
            case .protocolError(let s): return "DTX 协议错误：\(s)"
            case .deviceError(let s): return "DTX 设备错误：\(s)"
            }
        }
    }

    struct Incoming {
        var type: UInt8         // 0=OK 1=DATA 2=DISPATCH 3=OBJECT 4=ERROR
        var identifier: UInt32
        var conversation: UInt32
        var channel: Int32
        var flags: UInt32
        var aux: Data
        var payload: Data
    }

    private let tcp: UserspaceTCP
    private let log: (String) -> Void
    /// DTX 的消息标识必须在同一连接内单调递增。诊断版只发过一次坐标，
    /// 因而一直写死为 3；路线/跑道连续注入时必须逐包递增。
    private var nextMessageIdentifier: UInt32 = 3

    init(tcp: UserspaceTCP, log: @escaping (String) -> Void) {
        self.tcp = tcp
        self.log = log
    }

    // MARK: - 协议步骤

    /// 发送客户端能力，等服务端能力 dispatch（channel 0, type=DISPATCH）。
    func handshake(timeout: TimeInterval = 8) throws {
        try tcp.send(Data(DTXStaticBytes.dtxNotifyCaps))
        log("DTX 客户端能力已发送（_notifyOfPublishedCapabilities:）")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let msg = try readMessage(deadline: deadline)
            log("DTX 收包：type=\(msg.type) id=\(msg.identifier).\(msg.conversation) ch=\(msg.channel) aux=\(msg.aux.count)B payload=\(msg.payload.count)B")
            if msg.channel == 0 && msg.type == 2 {
                if msg.flags & 1 != 0 { try sendOKReply(for: msg) }
                log("DTX 能力握手完成")
                return
            }
        }
        throw DTXError.timeout("等待服务端能力通知")
    }

    /// 打开 com.apple.instruments.server.services.LocationSimulation 通道（code 1）。
    func openLocationChannel(timeout: TimeInterval = 8) throws {
        try tcp.send(Data(DTXStaticBytes.dtxRequestChannel))
        log("DTX 请求打开 LocationSimulation 通道…")
        let reply = try awaitReply(identifier: 2, timeout: timeout)
        if reply.type == 4 {
            throw DTXError.deviceError("开通道被拒：\(payloadSummary(reply.payload))")
        }
        log("DTX 通道 1 已打开（回复 type=\(reply.type)）")
    }

    /// 注入坐标（simulateLocationWithLatitude:longitude:）。
    func setLocation(latitude: Double, longitude: Double, timeout: TimeInterval = 8) throws {
        let identifier = nextMessageIdentifier
        nextMessageIdentifier &+= 1
        let msg = Self.buildSimulateMessage(msgId: identifier, channel: 1,
                                            latitude: latitude, longitude: longitude)
        try tcp.send(msg)
        log("DTX 已发送 simulateLocation(\(latitude), \(longitude))")
        let reply = try awaitReply(identifier: identifier, timeout: timeout)
        if reply.type == 4 {
            throw DTXError.deviceError("模拟定位被拒：\(payloadSummary(reply.payload))")
        }
        log("DTX 模拟定位已确认（回复 type=\(reply.type)）")
    }

    /// 清除模拟定位（stopLocationSimulation，无回复）。
    func stopLocation() {
        let identifier = nextMessageIdentifier
        nextMessageIdentifier &+= 1
        try? tcp.send(Self.buildStopMessage(msgId: identifier))
        log("DTX 已发送 stopLocationSimulation")
    }

    // MARK: - 消息构建（运行时动态部分）

    /// 构建 simulateLocation 消息：fragment 头 + payload 头 + aux（两个归档 double）+ selector 负载。
    static func buildSimulateMessage(msgId: UInt32, channel: Int32,
                                     latitude: Double, longitude: Double) -> Data {
        let lat = archivedDouble(latitude)
        let lon = archivedDouble(longitude)
        let aux = buildAux([pbuf(lat), pbuf(lon)])
        let payload = Data(DTXStaticBytes.selSimulatePayload)
        return assembleMessage(msgId: msgId, channel: channel, msgType: 2,
                               aux: aux, payload: payload, expectsReply: true)
    }

    /// stopLocationSimulation 的归档负载固定，仅替换 fragment header 内的消息标识。
    static func buildStopMessage(msgId: UInt32) -> Data {
        var message = Data(DTXStaticBytes.dtxStop)
        var littleEndian = msgId.littleEndian
        let bytes = withUnsafeBytes(of: &littleEndian) { Data($0) }
        message.replaceSubrange(16..<20, with: bytes)
        return message
    }

    /// 归档 double：146 字节 NSKeyedArchive 模板，大端 double 在固定偏移。
    static func archivedDouble(_ value: Double) -> Data {
        var d = Data(DTXStaticBytes.doubleTemplate)
        var be = value.bitPattern.bigEndian
        let bytes = withUnsafeBytes(of: &be) { Data($0) }
        d.replaceSubrange(DTXStaticBytes.doubleValueOffset..<DTXStaticBytes.doubleValueOffset + 8,
                          with: bytes)
        return d
    }

    /// PBuf：type=2 + u32 长度 + 字节
    private static func pbuf(_ bytes: Data) -> Data {
        var out = Data()
        RemoteXPCClient.appendLE32(&out, 2)
        RemoteXPCClient.appendLE32(&out, UInt32(bytes.count))
        out.append(bytes)
        return out
    }

    /// aux = PrimitiveDictionary { PNULL: args }：
    /// u32 magic 0x1F0 + u32 0 + u64 bodyLen + [key(u32 10) + value]…
    static func buildAux(_ args: [Data]) -> Data {
        var body = Data()
        for arg in args {
            RemoteXPCClient.appendLE32(&body, 10)  // PNULL key
            body.append(arg)
        }
        var out = Data()
        RemoteXPCClient.appendLE32(&out, 0x1F0)
        RemoteXPCClient.appendLE32(&out, 0)
        RemoteXPCClient.appendLE64(&out, UInt64(body.count))
        out.append(body)
        return out
    }

    /// 单分片 DTX 消息：32 字节 fragment 头 + 16 字节 payload 头 + aux + payload。
    static func assembleMessage(msgId: UInt32, channel: Int32, msgType: UInt8,
                                aux: Data, payload: Data, expectsReply: Bool,
                                conversation: UInt32 = 0) -> Data {
        var body = Data()
        body.append(msgType)
        body.append(contentsOf: [0, 0, 0])
        RemoteXPCClient.appendLE32(&body, UInt32(aux.count))
        RemoteXPCClient.appendLE32(&body, UInt32(aux.count + payload.count))
        RemoteXPCClient.appendLE32(&body, 0)
        body.append(aux)
        body.append(payload)

        var out = Data()
        RemoteXPCClient.appendLE32(&out, 0x1F3D_5B79)  // magic
        RemoteXPCClient.appendLE32(&out, 32)           // header size
        RemoteXPCClient.appendLE32(&out, 1 << 16)      // index=0(u16) + count=1(u16)，小端连续写
        RemoteXPCClient.appendLE32(&out, UInt32(body.count))
        RemoteXPCClient.appendLE32(&out, msgId)
        RemoteXPCClient.appendLE32(&out, conversation)
        // wire channel：conversation 为奇数（回复）时取负
        let wireChannel = conversation % 2 == 0 ? channel : -channel
        RemoteXPCClient.appendLE32(&out, UInt32(bitPattern: wireChannel))
        RemoteXPCClient.appendLE32(&out, expectsReply ? 1 : 0)
        out.append(body)
        return out
    }

    // MARK: - 消息读取

    private func awaitReply(identifier: UInt32, timeout: TimeInterval) throws -> Incoming {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let msg = try readMessage(deadline: deadline)
            log("DTX 收包：type=\(msg.type) id=\(msg.identifier).\(msg.conversation) ch=\(msg.channel)")
            if msg.identifier == identifier && msg.conversation == 1 {
                return msg
            }
            // 服务端主动 dispatch 且要求回复 → 回 OK
            if msg.type == 2 && msg.flags & 1 != 0 {
                try sendOKReply(for: msg)
            }
        }
        throw DTXError.timeout("等待 id=\(identifier) 回复")
    }

    private func readMessage(deadline: Date) throws -> Incoming {
        let remain = { max(0.1, deadline.timeIntervalSinceNow) }
        var header = try tcp.readExact(32, timeout: remain())
        guard RemoteXPCClient.readLE32(header, 0) == 0x1F3D_5B79 else {
            throw DTXError.protocolError("fragment magic 不匹配")
        }
        let headerSize = Int(RemoteXPCClient.readLE32(header, 4))
        let index = Int(header[8]) | Int(header[9]) << 8
        let count = Int(header[10]) | Int(header[11]) << 8
        let dataSize = Int(RemoteXPCClient.readLE32(header, 12))
        let identifier = RemoteXPCClient.readLE32(header, 16)
        let conversation = RemoteXPCClient.readLE32(header, 20)
        let channel = Int32(bitPattern: RemoteXPCClient.readLE32(header, 24))
        let flags = RemoteXPCClient.readLE32(header, 28)
        if headerSize > 32 {
            _ = try tcp.readExact(headerSize - 32, timeout: remain())
        }

        var body = Data()
        if index == 0 && count > 1 {
            // 多分片：首片无 body，dataSize 为总大小
            var remaining = dataSize
            while remaining > 0 {
                let h = try tcp.readExact(32, timeout: remain())
                let fragSize = Int(RemoteXPCClient.readLE32(h, 12))
                let fragHeaderSize = Int(RemoteXPCClient.readLE32(h, 4))
                if fragHeaderSize > 32 {
                    _ = try tcp.readExact(fragHeaderSize - 32, timeout: remain())
                }
                body.append(try tcp.readExact(fragSize, timeout: remain()))
                remaining -= fragSize
            }
        } else {
            body = try tcp.readExact(dataSize, timeout: remain())
        }

        guard body.count >= 16 else {
            throw DTXError.protocolError("消息体过短 \(body.count)")
        }
        let msgType = body[0]
        let auxSize = Int(RemoteXPCClient.readLE32(body, 4))
        guard body.count >= 16 + auxSize else {
            throw DTXError.protocolError("aux 越界")
        }
        return Incoming(type: msgType,
                        identifier: identifier,
                        conversation: conversation,
                        channel: channel,
                        flags: flags,
                        aux: body.subdata(in: 16..<16 + auxSize),
                        payload: body.subdata(in: 16 + auxSize..<body.count))
    }

    /// 对服务端 EXPECTS_REPLY 的 dispatch 回 OK（type=0，无 body）。
    private func sendOKReply(for msg: Incoming) throws {
        let reply = Self.assembleMessage(msgId: msg.identifier, channel: msg.channel,
                                         msgType: 0, aux: Data(), payload: Data(),
                                         expectsReply: false,
                                         conversation: msg.conversation + 1)
        try tcp.send(reply)
    }

    private func payloadSummary(_ payload: Data) -> String {
        // ERROR payload 是归档 NSError；提取可打印片段辅助诊断
        let printable = payload.compactMap { b -> Character? in
            (32..<127).contains(b) ? Character(UnicodeScalar(b)) : nil
        }
        return printable.count > 200 ? String(printable.prefix(200)) + "…" : String(printable)
    }
}
