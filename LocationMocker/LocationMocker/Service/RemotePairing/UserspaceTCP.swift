import Foundation

/// M2 用户态 TCP 栈（单连接客户端）：在 CDTunnel 裸 IPv6 包管道上实现
/// SYN/SYN-ACK/ACK 建连、stop-and-wait 可靠发送、按序接收 + 累积 ACK、FIN/RST 处理。
/// 仅供诊断链路使用：小包、按序假设 + 乱序缓存，无拥塞控制。
final class UserspaceTCP {

    enum TCPError: Error, CustomStringConvertible {
        case timeout(String)
        case reset
        case closed
        case badPacket(String)

        var description: String {
            switch self {
            case .timeout(let s): return "TCP 超时：\(s)"
            case .reset: return "TCP 收到 RST"
            case .closed: return "TCP 连接已关闭"
            case .badPacket(let s): return "TCP 包异常：\(s)"
            }
        }
    }

    private struct Flag {
        static let fin: UInt8 = 0x01
        static let syn: UInt8 = 0x02
        static let rst: UInt8 = 0x04
        static let psh: UInt8 = 0x08
        static let ack: UInt8 = 0x10
    }

    /// 包管道
    private let readPacket: (Date) throws -> Data?   // 参数为截止时间；超时返回 nil
    private let writePacket: (Data) throws -> Void
    private let log: (String) -> Void

    private let srcIP: [UInt8]  // 16 字节
    private let dstIP: [UInt8]

    private var srcPort: UInt16 = 0
    private var dstPort: UInt16 = 0
    private var sndNxt: UInt32 = 0
    private var sndUna: UInt32 = 0
    private var rcvNxt: UInt32 = 0
    private(set) var established = false
    private var remoteClosed = false
    private var gotRST = false

    private var rxBuffer: [UInt8] = []
    private var oooSegments: [UInt32: Data] = [:]

    private let mss = 1400

    init(readPacket: @escaping (Date) throws -> Data?,
         writePacket: @escaping (Data) throws -> Void,
         clientIPv6: String, serverIPv6: String,
         log: @escaping (String) -> Void) {
        self.readPacket = readPacket
        self.writePacket = writePacket
        self.srcIP = Self.parseIPv6(clientIPv6)
        self.dstIP = Self.parseIPv6(serverIPv6)
        self.log = log
    }

    // MARK: - 对外 API

    func connect(port: UInt16, timeout: TimeInterval = 8) throws {
        srcPort = UInt16.random(in: 49152...60999)
        dstPort = port
        let isn = UInt32.random(in: 0...UInt32.max)
        sndNxt = isn &+ 1
        sndUna = isn &+ 1
        // MSS 选项：02 04 05 B4（1400）
        let syn = buildSegment(flags: Flag.syn, seq: isn, ack: 0,
                               payload: Data(), options: [0x02, 0x04, 0x05, 0xB4])
        try writePacket(syn)
        log("TCP SYN → :\(port)（sport \(srcPort)）")

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if gotRST { throw TCPError.reset }
            guard let pkt = try readPacket(deadline) else { continue }
            guard let seg = parseSegment(pkt) else { continue }
            if seg.dstPort != srcPort { continue }
            if seg.flags & Flag.rst != 0 { throw TCPError.reset }
            if seg.flags & (Flag.syn | Flag.ack) == (Flag.syn | Flag.ack), seg.ack == sndNxt {
                rcvNxt = seg.seq &+ 1
                sndUna = seg.ack
                try sendACK()
                established = true
                log("TCP 已建立 → :\(port)")
                return
            }
        }
        throw TCPError.timeout("SYN-ACK 未到达（:\(port)）")
    }

    /// 可靠发送（stop-and-wait，按 MSS 分块）
    func send(_ data: Data) throws {
        guard established else { throw TCPError.closed }
        var offset = 0
        while offset < data.count {
            let end = min(offset + mss, data.count)
            let chunk = data[offset..<end]
            let segSeq = sndNxt
            let target = segSeq &+ UInt32(chunk.count)
            sndNxt = target  // 立即推进：否则 pump 中 ack<=sndNxt 校验会拒绝本次数据的 ACK
            let seg = buildSegment(flags: Flag.psh | Flag.ack, seq: segSeq, ack: rcvNxt,
                                   payload: Data(chunk), options: [])
            var attempts = 0
            while true {
                try writePacket(seg)
                let ackDeadline = Date().addingTimeInterval(1.0)
                while Date() < ackDeadline && sndUna != target {
                    try pump(ackDeadline)
                }
                if sndUna == target { break }
                attempts += 1
                if attempts > 6 { throw TCPError.timeout("ACK 未到达（已重传 \(attempts) 次）") }
            }
            offset = end
        }
    }

    /// 读取应用数据（至少 1 字节；超时抛错；对端关闭返回空 Data）
    func receive(timeout: TimeInterval) throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if !rxBuffer.isEmpty {
                let out = Data(rxBuffer)
                rxBuffer = []
                return out
            }
            if remoteClosed { return Data() }
            if gotRST { throw TCPError.reset }
            if Date() > deadline { throw TCPError.timeout("receive \(String(format: "%.1f", timeout))s 无数据") }
            try pump(deadline)
        }
    }

    /// 精确读取 n 字节（供协议层帧解析）
    func readExact(_ n: Int, timeout: TimeInterval) throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        while rxBuffer.count < n {
            if remoteClosed { throw TCPError.closed }
            if gotRST { throw TCPError.reset }
            if Date() > deadline { throw TCPError.timeout("readExact(\(n)) 仅有 \(rxBuffer.count) 字节") }
            try pump(deadline)
        }
        let out = Data(rxBuffer[0..<n])
        rxBuffer.removeFirst(n)
        return out
    }

    func close() {
        guard established else { return }
        let fin = buildSegment(flags: Flag.fin | Flag.ack, seq: sndNxt, ack: rcvNxt,
                               payload: Data(), options: [])
        try? writePacket(fin)
        established = false
    }

    // MARK: - 收包处理

    private func pump(_ deadline: Date) throws {
        guard let pkt = try readPacket(deadline) else { return }
        guard let seg = parseSegment(pkt) else { return }
        guard seg.dstPort == srcPort else { return }
        if seg.flags & Flag.rst != 0 {
            gotRST = true
            return
        }
        if seg.flags & Flag.ack != 0, seg.ack > sndUna, seg.ack <= sndNxt {
            sndUna = seg.ack
        }
        guard established else { return }
        if !seg.payload.isEmpty {
            if seg.seq == rcvNxt {
                rxBuffer.append(contentsOf: seg.payload)
                rcvNxt = rcvNxt &+ UInt32(seg.payload.count)
                // 尝试消化乱序缓存
                while let next = oooSegments.removeValue(forKey: rcvNxt) {
                    rxBuffer.append(contentsOf: next)
                    rcvNxt = rcvNxt &+ UInt32(next.count)
                }
            } else if seqLess(seg.seq, rcvNxt) {
                // 重叠/重发：只取未收到的后缀
                let already = rcvNxt &- seg.seq
                if already < UInt32(seg.payload.count) {
                    let suffix = seg.payload.dropFirst(Int(already))
                    rxBuffer.append(contentsOf: suffix)
                    rcvNxt = rcvNxt &+ UInt32(suffix.count)
                }
            } else {
                oooSegments[seg.seq] = seg.payload
            }
            try sendACK()
        }
        if seg.flags & Flag.fin != 0 {
            let finSeq = seg.seq &+ UInt32(seg.payload.count)
            if finSeq == rcvNxt {
                rcvNxt = rcvNxt &+ 1
                try sendACK()
                remoteClosed = true
            }
        }
    }

    private func sendACK() throws {
        let ack = buildSegment(flags: Flag.ack, seq: sndNxt, ack: rcvNxt, payload: Data(), options: [])
        try writePacket(ack)
    }

    private func seqLess(_ a: UInt32, _ b: UInt32) -> Bool {
        (a &- b) & 0x8000_0000 != 0
    }

    // MARK: - 包编解码

    private struct Segment {
        var srcPort: UInt16
        var dstPort: UInt16
        var seq: UInt32
        var ack: UInt32
        var flags: UInt8
        var payload: Data
    }

    /// 解析 IPv6 + TCP；非 TCP 包返回 nil（ICMPv6 等仅记录）。
    private func parseSegment(_ pkt: Data) -> Segment? {
        guard pkt.count >= 40, pkt[0] >> 4 == 6 else { return nil }
        let nextHeader = pkt[6]
        guard nextHeader == 6 else {
            log("忽略非 TCP 包：nh=\(nextHeader) len=\(pkt.count)")
            return nil
        }
        let tcp = pkt.subdata(in: 40..<pkt.count)
        guard tcp.count >= 20 else { return nil }
        let dataOffset = Int(tcp[12] >> 4) * 4
        guard tcp.count >= dataOffset else { return nil }
        return Segment(
            srcPort: UInt16(tcp[0]) << 8 | UInt16(tcp[1]),
            dstPort: UInt16(tcp[2]) << 8 | UInt16(tcp[3]),
            seq: readBE32(tcp, 4),
            ack: readBE32(tcp, 8),
            flags: tcp[13],
            payload: tcp.subdata(in: dataOffset..<tcp.count)
        )
    }

    private func buildSegment(flags: UInt8, seq: UInt32, ack: UInt32, payload: Data, options: [UInt8]) -> Data {
        var opt = options
        while opt.count % 4 != 0 { opt.append(1) }  // NOP 填充到 4 字节
        let dataOffset = (20 + opt.count) / 4

        var tcp = Data()
        appendBE16(&tcp, srcPort)
        appendBE16(&tcp, dstPort)
        appendBE32(&tcp, seq)
        appendBE32(&tcp, ack)
        tcp.append(UInt8(dataOffset << 4))
        tcp.append(flags)
        appendBE16(&tcp, 65535)  // window
        appendBE16(&tcp, 0)      // checksum 占位
        appendBE16(&tcp, 0)      // urgent
        tcp.append(contentsOf: opt)
        tcp.append(payload)

        // 校验和：伪头 + TCP
        var sumData = Data()
        sumData.append(contentsOf: srcIP)
        sumData.append(contentsOf: dstIP)
        appendBE32(&sumData, UInt32(tcp.count))
        sumData.append(contentsOf: [0, 0, 0, 6])
        sumData.append(tcp)
        let cksum = Self.internetChecksum(sumData)
        tcp[16] = UInt8(cksum >> 8)
        tcp[17] = UInt8(cksum & 0xFF)

        var ip = Data()
        ip.append(contentsOf: [0x60, 0x00, 0x00, 0x00])
        appendBE16(&ip, UInt16(tcp.count))
        ip.append(6)    // next header = TCP
        ip.append(64)   // hop limit
        ip.append(contentsOf: srcIP)
        ip.append(contentsOf: dstIP)
        ip.append(tcp)
        return ip
    }

    static func internetChecksum(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        let bytes = [UInt8](data)
        while i + 1 < bytes.count {
            sum &+= UInt32(UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1]))
            i += 2
        }
        if i < bytes.count {
            sum &+= UInt32(UInt16(bytes[i]) << 8)
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) &+ (sum >> 16)
        }
        return ~UInt16(sum & 0xFFFF)
    }

    /// 简易 IPv6 文本解析（支持 "::" 压缩）
    static func parseIPv6(_ s: String) -> [UInt8] {
        let halves = s.components(separatedBy: "::")
        var groups: [UInt16] = []
        let left = halves[0].isEmpty ? [] : halves[0].components(separatedBy: ":")
        for g in left { groups.append(UInt16(g, radix: 16) ?? 0) }
        var right: [UInt16] = []
        if halves.count > 1, !halves[1].isEmpty {
            for g in halves[1].components(separatedBy: ":") { right.append(UInt16(g, radix: 16) ?? 0) }
        }
        let zeros = 8 - groups.count - right.count
        groups.append(contentsOf: repeatElement(0, count: max(zeros, 0)))
        groups.append(contentsOf: right)
        var out: [UInt8] = []
        for g in groups.prefix(8) { out.append(UInt8(g >> 8)); out.append(UInt8(g & 0xFF)) }
        return out
    }

    // MARK: - 字节工具

    private func readBE32(_ d: Data, _ off: Int) -> UInt32 {
        UInt32(d[off]) << 24 | UInt32(d[off + 1]) << 16 | UInt32(d[off + 2]) << 8 | UInt32(d[off + 3])
    }

    private func appendBE16(_ d: inout Data, _ v: UInt16) {
        d.append(UInt8(v >> 8)); d.append(UInt8(v & 0xFF))
    }

    private func appendBE32(_ d: inout Data, _ v: UInt32) {
        d.append(UInt8(v >> 24)); d.append(UInt8((v >> 16) & 0xFF))
        d.append(UInt8((v >> 8) & 0xFF)); d.append(UInt8(v & 0xFF))
    }
}
