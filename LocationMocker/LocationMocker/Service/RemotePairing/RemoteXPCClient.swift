import Foundation

/// M2 RemoteXPC 客户端：在 userspace TCP 之上完成 HTTP/2 + XpcWrapper 握手，
/// 与 RSD（fd19:c693:e533::1:51313）交换 peer_info。
/// 线格式与 pymobiledevice3 remotexpc.py / xpc_message.py 逐字节对齐（金样单测保证）。
final class RemoteXPCClient {

    enum XPCError: Error, CustomStringConvertible {
        case timeout(String)
        case protocolError(String)
        case closed

        var description: String {
            switch self {
            case .timeout(let s): return "XPC 超时：\(s)"
            case .protocolError(let s): return "XPC 协议错误：\(s)"
            case .closed: return "XPC 连接关闭"
            }
        }
    }

    // MARK: - XPC 对象模型

    indirect enum XPCObject {
        case dict([(String, XPCObject)])
        case array([XPCObject])
        case string(String)
        case uint64(UInt64)
        case int64(Int64)
        case bool(Bool)
        case double(Double)
        case uuid(UUID)
        case data(Data)
        case null

        /// 转为 Swift 原生结构（dict → [String: Any]）
        func toNative() -> Any {
            switch self {
            case .dict(let entries):
                var out: [String: Any] = [:]
                for (k, v) in entries { out[k] = v.toNative() }
                return out
            case .array(let items): return items.map { $0.toNative() }
            case .string(let s): return s
            case .uint64(let v): return v
            case .int64(let v): return v
            case .bool(let v): return v
            case .double(let v): return v
            case .uuid(let v): return v.uuidString
            case .data(let v): return v
            case .null: return NSNull()
            }
            }
    }

    // MARK: - 成员

    private let tcp: UserspaceTCP
    private let log: (String) -> Void
    private var wrapperBuffer: [UInt8] = []  // 跨 DATA 帧的 wrapper 重组（数组避免 Data 切片下标陷阱）

    init(tcp: UserspaceTCP, log: @escaping (String) -> Void) {
        self.tcp = tcp
        self.log = log
    }

    // MARK: - HTTP/2 + RSD 握手

    /// 发送静态握手帧序列（与 pymobiledevice3 _do_handshake 一致），
    /// 等服务端 SETTINGS 后回 ACK。
    func performHandshake(timeout: TimeInterval = 8) throws {
        try tcp.send(Data(DTXStaticBytes.rsdHandshakeBlob))
        log("RemoteXPC preface 已发送（195 字节）")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let frame = try readFrame(deadline: deadline)
            if frame.type == 4 && frame.flags & 1 == 0 {  // SETTINGS（非 ACK）
                try tcp.send(Data(DTXStaticBytes.settingsAck))
                log("收到服务端 SETTINGS，已回 ACK")
                return
            }
            log("握手期间跳过帧 type=\(frame.type) stream=\(frame.streamId)")
        }
        throw XPCError.timeout("等待服务端 SETTINGS")
    }

    /// 发送设备 Handshake 消息并接收 peer_info。
    func exchangeDeviceHandshake(timeout: TimeInterval = 8) throws -> [String: Any] {
        let request = XPCObject.dict([
            ("MessageType", .string("Handshake")),
            ("MessagingProtocolVersion", .uint64(7)),
            ("UUID", .uuid(UUID())),
            ("Properties", .dict([
                ("RemoteXPCVersionFlags", .uint64(0x0100000000000006)),
                ("SensitivePropertiesVisible", .bool(true)),
            ])),
            ("Services", .dict([])),
        ])
        let wrapper = Self.encodeWrapper(request, messageId: 1, wantingReply: false)
        try tcp.send(Self.dataFrame(streamId: 1, payload: wrapper))
        log("设备 Handshake 已发送，等待 peer_info…")

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let obj = try receiveWrapper(deadline: deadline) {
                guard case .dict = obj else { continue }
                let native = obj.toNative()
                guard let dict = native as? [String: Any] else { continue }
                return dict
            }
        }
        throw XPCError.timeout("等待 peer_info")
    }

    // MARK: - HTTP/2 帧层

    private struct H2Frame {
        var type: UInt8
        var flags: UInt8
        var streamId: UInt32
        var payload: Data
    }

    private func readFrame(deadline: Date) throws -> H2Frame {
        let header = try tcp.readExact(9, timeout: max(0.1, deadline.timeIntervalSinceNow))
        let length = Int(header[0]) << 16 | Int(header[1]) << 8 | Int(header[2])
        let type = header[3]
        let flags = header[4]
        let streamId = UInt32(header[5] & 0x7F) << 24 | UInt32(header[6]) << 16
            | UInt32(header[7]) << 8 | UInt32(header[8])
        let payload = length > 0
            ? try tcp.readExact(length, timeout: max(0.1, deadline.timeIntervalSinceNow))
            : Data()
        return H2Frame(type: type, flags: flags, streamId: streamId, payload: payload)
    }

    static func dataFrame(streamId: UInt32, payload: Data) -> Data {
        var f = Data()
        f.append(UInt8((payload.count >> 16) & 0xFF))
        f.append(UInt8((payload.count >> 8) & 0xFF))
        f.append(UInt8(payload.count & 0xFF))
        f.append(0)  // DATA
        f.append(0)  // flags
        f.append(UInt8((streamId >> 24) & 0x7F))
        f.append(UInt8((streamId >> 16) & 0xFF))
        f.append(UInt8((streamId >> 8) & 0xFF))
        f.append(UInt8(streamId & 0xFF))
        f.append(payload)
        return f
    }

    /// 从 DATA 帧流中重组并解析一个带 payload 的 XPC wrapper。
    /// payload 为空（握手包）的 wrapper 会被跳过。
    private func receiveWrapper(deadline: Date) throws -> XPCObject? {
        while Date() < deadline {
            // 先尝试从缓冲解析
            if wrapperBuffer.count >= 16 {
                let payloadLen = Int(Self.readLE64(wrapperBuffer, 8))
                let totalLen = 24 + payloadLen  // 头(8) + L(8) + msgId(8) + payload
                if wrapperBuffer.count >= totalLen {
                    let wrapper = Data(wrapperBuffer[0..<totalLen])
                    wrapperBuffer.removeFirst(totalLen)
                    if let obj = Self.decodeWrapper(wrapper) {
                        // 与 pymobiledevice3 receive_response 一致：跳过空 dict（entries=None）
                        if case .dict(let entries) = obj, entries.isEmpty { continue }
                        return obj
                    }
                    continue  // 空 payload wrapper，继续
                }
            }
            let frame = try readFrame(deadline: deadline)
            switch frame.type {
            case 0:  // DATA
                wrapperBuffer.append(contentsOf: frame.payload)
            case 7:
                throw XPCError.protocolError("收到 GOAWAY")
            case 3:
                throw XPCError.protocolError("收到 RST_STREAM")
            default:
                continue  // SETTINGS/WINDOW_UPDATE/HEADERS 等跳过
            }
        }
        throw XPCError.timeout("receiveWrapper")
    }

    // MARK: - XpcWrapper 编解码

    /// flags = ALWAYS_SET | DATA_PRESENT (| WANTING_REPLY)
    static func encodeWrapper(_ obj: XPCObject, messageId: UInt64, wantingReply: Bool) -> Data {
        let payload = encodePayload(obj)
        var flags: UInt32 = 0x0000_0001 | 0x0000_0100
        if wantingReply { flags |= 0x0001_0000 }
        var out = Data()
        appendLE32(&out, 0x29B0_0B92)
        appendLE32(&out, flags)
        appendLE64(&out, UInt64(payload.count))  // L = payload 字节数（msgId/长度字段均不计）
        appendLE64(&out, messageId)
        out.append(payload)
        return out
    }

    private static func encodePayload(_ obj: XPCObject) -> Data {
        var out = Data()
        appendLE32(&out, 0x4213_3742)
        appendLE32(&out, 5)
        out.append(encodeObject(obj))
        return out
    }

    static func encodeObject(_ obj: XPCObject) -> Data {
        var out = Data()
        switch obj {
        case .dict(let entries):
            appendLE32(&out, 0x0000_F000)
            var body = Data()
            appendLE32(&body, UInt32(entries.count))
            for (key, value) in entries {
                let keyBytes = Array(key.utf8) + [0]
                body.append(contentsOf: keyBytes)
                body.append(contentsOf: repeatElement(0, count: pad4(keyBytes.count)))
                body.append(encodeObject(value))
            }
            appendLE32(&out, UInt32(body.count))
            out.append(body)
        case .array(let items):
            appendLE32(&out, 0x0000_E000)
            var body = Data()
            appendLE32(&body, UInt32(items.count))
            for item in items { body.append(encodeObject(item)) }
            appendLE32(&out, UInt32(body.count))
            out.append(body)
        case .string(let s):
            appendLE32(&out, 0x0000_9000)
            let bytes = Array(s.utf8) + [0]
            appendLE32(&out, UInt32(bytes.count))
            out.append(contentsOf: bytes)
            out.append(contentsOf: repeatElement(0, count: pad4(bytes.count)))
        case .uint64(let v):
            appendLE32(&out, 0x0000_4000)
            appendLE64(&out, v)
        case .int64(let v):
            appendLE32(&out, 0x0000_3000)
            appendLE64(&out, UInt64(bitPattern: v))
        case .bool(let v):
            appendLE32(&out, 0x0000_2000)
            appendLE32(&out, v ? 1 : 0)
        case .double(let v):
            appendLE32(&out, 0x0000_5000)
            appendLE64(&out, v.bitPattern)
        case .uuid(let v):
            appendLE32(&out, 0x0000_A000)
            let u = v.uuid
            out.append(contentsOf: [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
                                    u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15])
        case .data(let d):
            appendLE32(&out, 0x0000_8000)
            appendLE32(&out, UInt32(d.count))
            out.append(d)
            out.append(contentsOf: repeatElement(0, count: pad4(4 + d.count) ))
        case .null:
            appendLE32(&out, 0x0000_1000)
        }
        return out
    }

    /// 解码完整 wrapper；payload 缺失返回 nil。
    /// 布局：magic(4) + flags(4) + length(8) + msgId(8) + payloadMagic(4) + version(4) + object
    static func decodeWrapper(_ data: Data) -> XPCObject? {
        guard data.count >= 24 else { return nil }
        let length = Int(readLE64(data, 8))
        guard length > 0 else { return nil }  // 无 payload 的握手 wrapper（L=0）
        var off = 24  // 跳过 magic/flags/length/msgId
        guard data.count >= off + 8 else { return nil }
        guard readLE32(data, off) == 0x4213_3742 else { return nil }
        off += 8  // payload magic + version
        return decodeObject(data, &off)
    }

    static func decodeObject(_ data: Data, _ off: inout Int) -> XPCObject? {
        guard data.count >= off + 4 else { return nil }
        let type = readLE32(data, off)
        off += 4
        switch type {
        case 0xF000:  // dict
            guard data.count >= off + 8 else { return nil }
            let total = Int(readLE32(data, off))
            let count = Int(readLE32(data, off + 4))
            let bodyStart = off
            off += 8
            var entries: [(String, XPCObject)] = []
            for _ in 0..<count {
                // key：cstring + 4 对齐
                var keyBytes: [UInt8] = []
                while off < data.count, data[off] != 0 {
                    keyBytes.append(data[off])
                    off += 1
                }
                off += 1  // NUL
                off += pad4(keyBytes.count + 1)
                guard let value = decodeObject(data, &off) else { return nil }
                entries.append((String(decoding: keyBytes, as: UTF8.self), value))
            }
            off = max(off, bodyStart + 4 + total)  // 防御：按 total 对齐
            return .dict(entries)
        case 0xE000:  // array
            guard data.count >= off + 8 else { return nil }
            let total = Int(readLE32(data, off))
            let count = Int(readLE32(data, off + 4))
            let bodyStart = off
            off += 8
            var items: [XPCObject] = []
            for _ in 0..<count {
                guard let item = decodeObject(data, &off) else { return nil }
                items.append(item)
            }
            off = max(off, bodyStart + 4 + total)
            return .array(items)
        case 0x9000:  // string
            guard data.count >= off + 4 else { return nil }
            let len = Int(readLE32(data, off))
            off += 4
            guard data.count >= off + len else { return nil }
            let bytes = data[off..<off + len]
            off += len + pad4(len)
            return .string(String(decoding: bytes.dropLast(), as: UTF8.self))
        case 0x4000:
            guard data.count >= off + 8 else { return nil }
            defer { off += 8 }
            return .uint64(readLE64(data, off))
        case 0x3000:
            guard data.count >= off + 8 else { return nil }
            defer { off += 8 }
            return .int64(Int64(bitPattern: readLE64(data, off)))
        case 0x5000:
            guard data.count >= off + 8 else { return nil }
            defer { off += 8 }
            return .double(Double(bitPattern: readLE64(data, off)))
        case 0x2000:
            guard data.count >= off + 4 else { return nil }
            defer { off += 4 }
            return .bool(readLE32(data, off) != 0)
        case 0xA000:
            guard data.count >= off + 16 else { return nil }
            defer { off += 16 }
            let b = [UInt8](data[off..<off + 16])
            return .uuid(UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                                     b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])))
        case 0x8000:  // data
            guard data.count >= off + 4 else { return nil }
            let len = Int(readLE32(data, off))
            off += 4
            guard data.count >= off + len else { return nil }
            let d = Data(data[off..<off + len])
            off += len + pad4(4 + len)
            return .data(d)
        case 0x1000:
            return .null
        default:
            return nil
        }
    }

    // MARK: - 字节工具

    private static func pad4(_ n: Int) -> Int { (4 - (n % 4)) % 4 }

    static func appendLE32(_ d: inout Data, _ v: UInt32) {
        d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF))
        d.append(UInt8((v >> 16) & 0xFF)); d.append(UInt8((v >> 24) & 0xFF))
    }

    static func appendLE64(_ d: inout Data, _ v: UInt64) {
        for i in 0..<8 { d.append(UInt8((v >> UInt64(i * 8)) & 0xFF)) }
    }

    static func readLE32(_ d: Data, _ off: Int) -> UInt32 {
        UInt32(d[off]) | UInt32(d[off + 1]) << 8 | UInt32(d[off + 2]) << 16 | UInt32(d[off + 3]) << 24
    }

    static func readLE64(_ d: Data, _ off: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(d[off + i]) << UInt64(i * 8) }
        return v
    }

    static func readLE32(_ d: [UInt8], _ off: Int) -> UInt32 {
        UInt32(d[off]) | UInt32(d[off + 1]) << 8 | UInt32(d[off + 2]) << 16 | UInt32(d[off + 3]) << 24
    }

    static func readLE64(_ d: [UInt8], _ off: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(d[off + i]) << UInt64(i * 8) }
        return v
    }

    private func readLE64(_ d: Data, _ off: Int) -> UInt64 { Self.readLE64(d, off) }
}
