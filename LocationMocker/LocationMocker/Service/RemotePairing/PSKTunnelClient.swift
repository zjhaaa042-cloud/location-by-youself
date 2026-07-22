import Foundation
import OpenSSL

/// M2 隧道客户端：TLS1.2-PSK 连接设备 listener → CDTunnel 握手 → 包转发。
/// OpenSSL 提供 PSK 密码套件（Network.framework 不支持），PSK 即 pair-verify 的
/// X25519 共享密钥（encryptionKey）。
final class PSKTunnelClient {

    enum TunnelError: Error, CustomStringConvertible {
        case socketFailed(String)
        case tlsFailed(String)
        case handshakeFailed(String)

        var description: String {
            switch self {
            case .socketFailed(let s): return "socket 错误：\(s)"
            case .tlsFailed(let s): return "TLS 错误：\(s)"
            case .handshakeFailed(let s): return "CDTunnel 握手错误：\(s)"
            }
        }
    }

    struct TunnelParameters {
        let serverAddress: String
        let serverRSDPort: UInt16
        let clientAddress: String
        let mtu: Int
    }

    /// 用户态 PSK（每次 pair-verify 会话随机生成，仅内存使用）。
    private static var currentPSK = Data()

    private var ssl: OpaquePointer?
    private var ctx: OpaquePointer?
    private var sock: Int32 = -1

    /// 连接并完成 CDTunnel 握手，返回隧道参数。
    func connect(host: String, port: UInt16, psk: Data) throws -> TunnelParameters {
        Self.currentPSK = psk
        sock = try openTCPSocket(host: host, port: port)
        do {
            try startTLS()
        } catch {
            closeAll()
            throw error
        }
        do {
            return try performCDTunnelHandshake()
        } catch {
            closeAll()
            throw error
        }
    }

    func close() {
        closeAll()
    }

    // MARK: - TCP

    private func openTCPSocket(host: String, port: UInt16) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &result) == 0, let info = result else {
            throw TunnelError.socketFailed("getaddrinfo 失败")
        }
        defer { freeaddrinfo(result) }

        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { throw TunnelError.socketFailed("socket() errno=\(errno)") }
        // 禁止 write 触发 SIGPIPE（对端关闭时静默杀进程，无崩溃报告）
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        if Darwin.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) != 0 {
            let e = errno
            Darwin.close(fd)
            throw TunnelError.socketFailed("connect \(host):\(port) errno=\(e)")
        }
        return fd
    }

    // MARK: - TLS-PSK

    private func startTLS() throws {
        guard let method = TLS_client_method() else {
            throw TunnelError.tlsFailed("TLS_client_method 不可用")
        }
        guard let context = SSL_CTX_new(method) else {
            throw TunnelError.tlsFailed("SSL_CTX_new 失败")
        }
        ctx = context
        // SSL_CTX_set_min/max_proto_version 是宏（Swift 不可见），用底层 ctrl：
        // SSL_CTRL_SET_MIN_PROTO_VERSION=123, SSL_CTRL_SET_MAX_PROTO_VERSION=124
        SSL_CTX_ctrl(context, 123, Int(TLS1_2_VERSION), nil)
        SSL_CTX_ctrl(context, 124, Int(TLS1_2_VERSION), nil)
        guard SSL_CTX_set_cipher_list(context, "PSK") == 1 else {
            throw TunnelError.tlsFailed("无可用 PSK 密码套件")
        }
        SSL_CTX_set_psk_client_callback(context) { _, _, identity, maxIdentityLen, pskOut, maxPskLen -> UInt32 in
            // 静态 PSK：identity 可为空；PSK 拷贝原始字节
            let key = PSKTunnelClient.currentPSK
            guard key.count <= maxPskLen else { return 0 }
            if let identity = identity, maxIdentityLen > 1 {
                identity[0] = 0  // identity 置空字符串
            }
            key.withUnsafeBytes { src in
                if let base = src.baseAddress {
                    memcpy(pskOut, base, key.count)
                }
            }
            return UInt32(key.count)
        }

        guard let sslPtr = SSL_new(context) else {
            throw TunnelError.tlsFailed("SSL_new 失败")
        }
        ssl = sslPtr
        SSL_set_fd(sslPtr, sock)
        guard SSL_connect(sslPtr) == 1 else {
            let err = ERR_get_error()
            var buf = [CChar](repeating: 0, count: 256)
            ERR_error_string_n(err, &buf, buf.count)
            throw TunnelError.tlsFailed("PSK 握手失败：\(String(cString: buf))")
        }
    }

    // MARK: - CDTunnel 握手

    private func performCDTunnelHandshake() throws -> TunnelParameters {
        let request: [String: Any] = ["type": "clientHandshakeRequest", "mtu": 16000]
        try sendCDPacket(request)
        guard let response = try receiveCDPacket() else {
            throw TunnelError.handshakeFailed("无响应")
        }
        guard let serverAddress = response["serverAddress"] as? String,
              let rsdPort = response["serverRSDPort"] as? Int,
              let clientParams = response["clientParameters"] as? [String: Any],
              let clientAddress = clientParams["address"] as? String,
              let mtu = clientParams["mtu"] as? Int else {
            throw TunnelError.handshakeFailed("响应字段缺失：\(response)")
        }
        return TunnelParameters(serverAddress: serverAddress,
                                serverRSDPort: UInt16(rsdPort),
                                clientAddress: clientAddress,
                                mtu: mtu)
    }

    /// CDTunnel 帧：magic "CDTunnel"（8 字节）+ u16 BE 长度 + JSON body。
    private func sendCDPacket(_ json: [String: Any]) throws {
        let body = try JSONSerialization.data(withJSONObject: json)
        var frame = Data("CDTunnel".utf8)
        var len = UInt16(body.count).bigEndian
        frame.append(Data(bytes: &len, count: 2))
        frame.append(body)
        try tlsWrite(frame)
    }

    private func receiveCDPacket() throws -> [String: Any]? {
        let header = try tlsRead(exactly: 10)
        guard header.prefix(8) == Data("CDTunnel".utf8) else {
            throw TunnelError.handshakeFailed("magic 不匹配")
        }
        let len = Int(header[8]) << 8 | Int(header[9])
        let body = try tlsRead(exactly: len)
        return try JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    // MARK: - TLS 读写

    private func tlsWrite(_ data: Data) throws {
        guard let ssl = ssl else { throw TunnelError.tlsFailed("未连接") }
        try data.withUnsafeBytes { src in
            guard let base = src.baseAddress else { return }
            var written = 0
            while written < data.count {
                let n = SSL_write(ssl, base.advanced(by: written), Int32(data.count - written))
                guard n > 0 else { throw TunnelError.tlsFailed("SSL_write 失败") }
                written += Int(n)
            }
        }
    }

    private func tlsRead(exactly count: Int) throws -> Data {
        guard let ssl = ssl else { throw TunnelError.tlsFailed("未连接") }
        var out = Data(count: count)
        var read = 0
        try out.withUnsafeMutableBytes { dst in
            guard let base = dst.baseAddress else { return }
            while read < count {
                let n = SSL_read(ssl, base.advanced(by: read), Int32(count - read))
                guard n > 0 else { throw TunnelError.tlsFailed("SSL_read 失败（对端关闭？）") }
                read += Int(n)
            }
        }
        return out
    }

    // MARK: - 隧道包读写（CDTunnel 握手完成后使用）

    private var packetBuffer: [UInt8] = []

    /// 进入隧道模式：设置 socket 读超时（供超时轮询），此后 TLS 通道裸传 IPv6 包。
    func enterTunnelMode() {
        var tv = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// 写入一个裸 IPv6 包。
    func writeTunnelPacket(_ data: Data) throws {
        try tlsWrite(data)
    }

    /// 读取一个完整 IPv6 包（按 IPv6 payload length 切分）；deadline 前无包返回 nil。
    func readTunnelPacket(until deadline: Date) throws -> Data? {
        while true {
            if let pkt = drainPacket() { return Data(pkt) }
            if Date() > deadline { return nil }
            let chunk = try tlsReadSome(max: 65536)
            if chunk.isEmpty { continue }  // SO_RCVTIMEO 超时切片
            packetBuffer.append(contentsOf: chunk)
        }
    }

    /// 注意：底层缓冲必须是 [UInt8]（Data 切片 startIndex 非零时下标访问会运行时 trap）。
    private func drainPacket() -> [UInt8]? {
        guard packetBuffer.count >= 40, packetBuffer[0] >> 4 == 6 else { return nil }
        let plen = Int(packetBuffer[4]) << 8 | Int(packetBuffer[5])
        let total = 40 + plen
        guard packetBuffer.count >= total else { return nil }
        let pkt = Array(packetBuffer[0..<total])
        packetBuffer.removeFirst(total)
        return pkt
    }

    /// 非精确读：返回 SSL 流当前可读字节；socket 读超时返回空 Data。
    private func tlsReadSome(max: Int) throws -> Data {
        guard let ssl = ssl else { throw TunnelError.tlsFailed("未连接") }
        var buf = [UInt8](repeating: 0, count: max)
        let n = SSL_read(ssl, &buf, Int32(max))
        if n > 0 { return Data(buf[0..<Int(n)]) }
        let err = SSL_get_error(ssl, n)
        if err == SSL_ERROR_ZERO_RETURN { throw TunnelError.tlsFailed("对端关闭 TLS") }
        if err == SSL_ERROR_SYSCALL && errno != 0 && errno != EAGAIN {
            throw TunnelError.tlsFailed("SSL_read errno=\(errno)")
        }
        return Data()  // EAGAIN / WANT_READ（SO_RCVTIMEO 超时）
    }

    private func closeAll() {
        if let ssl = ssl {
            SSL_shutdown(ssl)
            SSL_free(ssl)
            self.ssl = nil
        }
        if let ctx = ctx {
            SSL_CTX_free(ctx)
            self.ctx = nil
        }
        if sock >= 0 {
            Darwin.close(sock)
            sock = -1
        }
    }
}
