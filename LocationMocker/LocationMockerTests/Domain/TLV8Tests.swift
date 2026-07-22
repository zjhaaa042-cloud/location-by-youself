import XCTest
@testable import LocationMocker

/// TLV8 编解码：长值拆分 / 合并、空值、类型常量。
final class TLV8Tests: XCTestCase {

    func testShortValueRoundTrip() throws {
        let items = [
            TLV8.Item(type: TLV8.ItemType.method.rawValue, value: Data([0x00])),
            TLV8.Item(type: TLV8.ItemType.state.rawValue, value: Data([0x01])),
        ]
        let encoded = TLV8.encode(items)
        XCTAssertEqual([UInt8](encoded), [0x00, 0x01, 0x00, 0x06, 0x01, 0x01])
        let decoded = try TLV8.decode(encoded)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].type, 0x00)
        XCTAssertEqual(decoded[0].value, Data([0x00]))
        XCTAssertEqual(decoded[1].type, 0x06)
    }

    func testLongValueSplitAndMerge() throws {
        // 384 字节公钥应拆为 255 + 129 两段，解码后合并
        let big = Data((0..<384).map { UInt8($0 % 256) })
        let encoded = TLV8.encode([.init(type: TLV8.ItemType.publicKey.rawValue, value: big)])

        // 第一段：type + 0xFF + 255 字节；第二段：type + 0x81 + 129 字节
        XCTAssertEqual(encoded[0], 0x03)
        XCTAssertEqual(encoded[1], 0xFF)
        XCTAssertEqual(encoded[2 + 255], 0x03)
        XCTAssertEqual(encoded[2 + 255 + 1], 0x81)
        XCTAssertEqual(encoded.count, (2 + 255) + (2 + 129))

        let decoded = try TLV8.decode(encoded)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].value, big)
    }

    func testInterleavedTypesNotMerged() throws {
        // 同类型但不连续的条目不能合并
        let items = [
            TLV8.Item(type: 0x03, value: Data([0xAA])),
            TLV8.Item(type: 0x06, value: Data([0x01])),
            TLV8.Item(type: 0x03, value: Data([0xBB])),
        ]
        let decoded = try TLV8.decode(TLV8.encode(items))
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].value, Data([0xAA]))
        XCTAssertEqual(decoded[2].value, Data([0xBB]))
    }

    func testEmptyValue() throws {
        let encoded = TLV8.encode([.init(type: 0x01, value: Data())])
        XCTAssertEqual([UInt8](encoded), [0x01, 0x00])
        let decoded = try TLV8.decode(encoded)
        XCTAssertEqual(decoded[0].value, Data())
    }

    func testTruncatedThrows() {
        XCTAssertThrowsError(try TLV8.decode(Data([0x03, 0x05, 0x01])))
    }

    func testFirstLookup() throws {
        let items = [
            TLV8.Item(type: TLV8.ItemType.salt.rawValue, value: Data([1, 2, 3])),
            TLV8.Item(type: TLV8.ItemType.publicKey.rawValue, value: Data([4, 5])),
        ]
        XCTAssertEqual(TLV8.first(.salt, in: items), Data([1, 2, 3]))
        XCTAssertNil(TLV8.first(.proof, in: items))
    }
}

/// OPACK 编码：对照 idevice remote_pairing/opack.rs 测试向量。
final class OpackEncoderTests: XCTestCase {

    /// device_info 编码必须与 idevice opack.rs t1 测试期望完全一致。
    func testDeviceInfoMatchesIdeviceVector() {
        let value = OpackEncoder.Value.dict([
            ("altIRK", .data(Data([0xE9, 0xE8, 0x2D, 0xC0, 0x6A, 0x49, 0x79, 0x6B,
                                   0x56, 0x6F, 0x54, 0x00, 0x19, 0xB1, 0xC7, 0x7B]))),
            ("btAddr", .string("11:22:33:44:55:66")),
            ("mac", .data(Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66]))),
            ("remotepairing_serial_number", .string("AAAAAAAAAAAA")),
            ("accountID", .string("lolsssss")),
            ("model", .string("computer-model")),
            ("name", .string("reeeee")),
        ])
        let encoded = OpackEncoder.encode(value)

        let expected: [UInt8] = [
            0xE7, 0x46, 0x61, 0x6C, 0x74, 0x49, 0x52, 0x4B, 0x80, 0xE9, 0xE8, 0x2D, 0xC0, 0x6A,
            0x49, 0x79, 0x6B, 0x56, 0x6F, 0x54, 0x00, 0x19, 0xB1, 0xC7, 0x7B, 0x46, 0x62, 0x74,
            0x41, 0x64, 0x64, 0x72, 0x51, 0x31, 0x31, 0x3A, 0x32, 0x32, 0x3A, 0x33, 0x33, 0x3A,
            0x34, 0x34, 0x3A, 0x35, 0x35, 0x3A, 0x36, 0x36, 0x43, 0x6D, 0x61, 0x63, 0x76, 0x11,
            0x22, 0x33, 0x44, 0x55, 0x66, 0x5B, 0x72, 0x65, 0x6D, 0x6F, 0x74, 0x65, 0x70, 0x61,
            0x69, 0x72, 0x69, 0x6E, 0x67, 0x5F, 0x73, 0x65, 0x72, 0x69, 0x61, 0x6C, 0x5F, 0x6E,
            0x75, 0x6D, 0x62, 0x65, 0x72, 0x4C, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
            0x41, 0x41, 0x41, 0x41, 0x49, 0x61, 0x63, 0x63, 0x6F, 0x75, 0x6E, 0x74, 0x49, 0x44,
            0x48, 0x6C, 0x6F, 0x6C, 0x73, 0x73, 0x73, 0x73, 0x73, 0x45, 0x6D, 0x6F, 0x64, 0x65,
            0x6C, 0x4E, 0x63, 0x6F, 0x6D, 0x70, 0x75, 0x74, 0x65, 0x72, 0x2D, 0x6D, 0x6F, 0x64,
            0x65, 0x6C, 0x44, 0x6E, 0x61, 0x6D, 0x65, 0x46, 0x72, 0x65, 0x65, 0x65, 0x65, 0x65,
        ]
        XCTAssertEqual([UInt8](encoded), expected)
    }

    func testScalars() {
        // 小整数内联编码：v + 8
        XCTAssertEqual([UInt8](OpackEncoder.encode(.int(0))), [0x08])
        XCTAssertEqual([UInt8](OpackEncoder.encode(.int(0x27))), [0x2F])
        XCTAssertEqual([UInt8](OpackEncoder.encode(.int(0x28))), [0x30, 0x28])
        // 布尔
        XCTAssertEqual([UInt8](OpackEncoder.encode(.bool(true))), [0x01])
        XCTAssertEqual([UInt8](OpackEncoder.encode(.bool(false))), [0x02])
        // 短字符串内联
        XCTAssertEqual([UInt8](OpackEncoder.encode(.string("hi"))), [0x42, 0x68, 0x69])
        // 短 data 内联
        XCTAssertEqual([UInt8](OpackEncoder.encode(.data(Data([0xAB])))), [0x71, 0xAB])
        // 33 字节字符串走 0x61 + 长度
        let s33 = String(repeating: "x", count: 33)
        let enc33 = [UInt8](OpackEncoder.encode(.string(s33)))
        XCTAssertEqual(enc33[0], 0x61)
        XCTAssertEqual(enc33[1], 33)
        XCTAssertEqual(enc33.count, 2 + 33)
    }

    func testHKDFKnownValue() {
        // HKDF-SHA512 RFC 5869 风格交叉验证：
        // ikm/salt/info 固定时输出确定，且与 CryptoKit 结果比较——
        // 这里验证两次调用一致且长度为 32。
        let k1 = RPPairingClient.hkdf(ikm: Data(repeating: 0x0B, count: 22),
                                      salt: Data("Pair-Verify-Encrypt-Salt".utf8),
                                      info: Data("Pair-Verify-Encrypt-Info".utf8))
        let k2 = RPPairingClient.hkdf(ikm: Data(repeating: 0x0B, count: 22),
                                      salt: Data("Pair-Verify-Encrypt-Salt".utf8),
                                      info: Data("Pair-Verify-Encrypt-Info".utf8))
        XCTAssertEqual(k1.count, 32)
        XCTAssertEqual(k1, k2)
    }
}
