import XCTest
@testable import LocationMocker

/// M2 线格式金样测试：Swift 编码器输出必须与 pymobiledevice3 逐字节一致。
/// 金样由 tools/gen_m2_golden.py 生成（DTXGoldenVectors.swift）。
final class M2WireFormatTests: XCTestCase {

    /// RemoteXPC 设备 Handshake wrapper：固定 UUID + msg_id=1 + flags=0x101。
    func testDeviceHandshakeMatchesGolden() throws {
        let request = RemoteXPCClient.XPCObject.dict([
            ("MessageType", .string("Handshake")),
            ("MessagingProtocolVersion", .uint64(7)),
            ("UUID", .uuid(UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")!)),
            ("Properties", .dict([
                ("RemoteXPCVersionFlags", .uint64(0x0100000000000006)),
                ("SensitivePropertiesVisible", .bool(true)),
            ])),
            ("Services", .dict([])),
        ])
        let encoded = RemoteXPCClient.encodeWrapper(request, messageId: 1, wantingReply: false)
        let golden = DTXGoldenVectors.deviceHandshake
        if [UInt8](encoded) != golden {
            let a = [UInt8](encoded), b = golden
            var idx = 0
            while idx < min(a.count, b.count), a[idx] == b[idx] { idx += 1 }
            let lo = max(0, idx - 8), hiA = min(a.count, idx + 16), hiB = min(b.count, idx + 16)
            XCTFail("""
            设备 Handshake 分叉于偏移 \(idx)（本端 \(a.count)B / 金样 \(b.count)B）
            本端[\(lo)..<\(hiA)]: \(a[lo..<hiA].map { String(format: "%02x", $0) }.joined())
            金样[\(lo)..<\(hiB)]: \(b[lo..<hiB].map { String(format: "%02x", $0) }.joined())
            """)
        }
    }

    /// simulateLocation 消息：北京 39.9042,116.4074 / msg_id=3 / channel=1。
    func testSimulateMessageMatchesGolden() throws {
        let msg = DTXClient.buildSimulateMessage(msgId: 3, channel: 1,
                                                 latitude: 39.9042, longitude: 116.4074)
        XCTAssertEqual([UInt8](msg), DTXGoldenVectors.dtxSimulateBeijing,
                       "simulateLocation 消息与 pymobiledevice3 不一致")
    }

    /// 连续注入后 stop 的消息 ID 必须跟随增长，且 ID=4 时仍与金样逐字节一致。
    func testStopMessageUsesDynamicIdentifier() throws {
        XCTAssertEqual([UInt8](DTXClient.buildStopMessage(msgId: 4)),
                       DTXGoldenVectors.dtxStop)
        let later = DTXClient.buildStopMessage(msgId: 19)
        XCTAssertEqual(RemoteXPCClient.readLE32(later, 16), 19)
        XCTAssertEqual(later[0..<16], Data(DTXGoldenVectors.dtxStop)[0..<16])
        XCTAssertEqual(later[20...], Data(DTXGoldenVectors.dtxStop)[20...])
    }

    /// double 归档：1.0 应与模板完全一致；其他值仅 8 字节大端位不同。
    func testArchivedDouble() throws {
        let one = DTXClient.archivedDouble(1.0)
        XCTAssertEqual([UInt8](one), DTXGoldenVectors.doubleTemplate)
        let lat = DTXClient.archivedDouble(39.9042)
        XCTAssertEqual(lat.count, one.count)
        XCTAssertEqual(lat[77], 0x23)  // real marker
        var be = 39.9042.bitPattern.bigEndian
        let expected = withUnsafeBytes(of: &be) { Data($0) }
        XCTAssertEqual(lat[78..<86], expected)
    }

    /// wrapper 解码往返：解码金样 deviceHandshake 应还原关键字段。
    func testDecodeWrapperGolden() throws {
        let data = Data(DTXGoldenVectors.deviceHandshake)
        guard let obj = RemoteXPCClient.decodeWrapper(data),
              case .dict(let entries) = obj else {
            XCTFail("金样 wrapper 解码失败")
            return
        }
        let dict = Dictionary(uniqueKeysWithValues: entries)
        guard case .string(let msgType)? = dict["MessageType"] else {
            XCTFail("MessageType 缺失")
            return
        }
        XCTAssertEqual(msgType, "Handshake")
        guard case .uint64(let ver)? = dict["MessagingProtocolVersion"] else {
            XCTFail("MessagingProtocolVersion 缺失")
            return
        }
        XCTAssertEqual(ver, 7)
    }

    /// TCP 校验和：RFC 1071 经典向量。
    func testInternetChecksum() throws {
        // 00 01 f2 03 f4 f5 f6 f7 → 和为 0xddf2，校验和取反 0x220d（RFC1071 例）
        let sum = UserspaceTCP.internetChecksum(Data([0x00, 0x01, 0xf2, 0x03, 0xf4, 0xf5, 0xf6, 0xf7]))
        XCTAssertEqual(sum, 0x220d)
    }

    /// IPv6 文本解析：压缩形式。
    func testIPv6Parse() throws {
        let bytes = UserspaceTCP.parseIPv6("fd19:c693:e533::1")
        XCTAssertEqual(bytes.count, 16)
        XCTAssertEqual(bytes[0], 0xfd)
        XCTAssertEqual(bytes[1], 0x19)
        XCTAssertEqual(bytes[15], 0x01)
        let bytes2 = UserspaceTCP.parseIPv6("fd19:c693:e533::2")
        XCTAssertEqual(bytes2[15], 0x02)
    }
}
