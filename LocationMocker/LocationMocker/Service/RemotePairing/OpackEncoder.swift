import Foundation

/// 最小 OPACK 编码器，仅覆盖配对 device_info 所需类型：
/// string / data / bool / int / dict（有序）。格式对照 idevice remote_pairing/opack.rs。
enum OpackEncoder {

    enum Value {
        case string(String)
        case data(Data)
        case bool(Bool)
        case int(UInt64)
        case dict([(String, Value)])  // 保持插入序，与 idevice（IndexMap）一致
    }

    static func encode(_ value: Value) -> Data {
        var buf = Data()
        encodeInner(value, into: &buf)
        return buf
    }

    private static func encodeInner(_ value: Value, into buf: inout Data) {
        switch value {
        case .dict(let pairs):
            let count = pairs.count
            if count < 15 {
                buf.append(UInt8(0xE0 + count))
            } else {
                buf.append(0xEF)
            }
            for (key, val) in pairs {
                encodeInner(.string(key), into: &buf)
                encodeInner(val, into: &buf)
            }
            if count > 14 {
                buf.append(0x03)  // 终止符
            }

        case .bool(let b):
            buf.append(b ? 0x01 : 0x02)

        case .int(let v):
            if v <= UInt64(UInt8.max) {
                let u8 = UInt8(v)
                if u8 > 0x27 {
                    buf.append(0x30)
                    buf.append(u8)
                } else {
                    buf.append(u8 + 8)
                }
            } else if v <= UInt64(UInt32.max) {
                buf.append(0x32)
                var le = UInt32(v).littleEndian
                withUnsafeBytes(of: &le) { buf.append(contentsOf: $0) }
            } else {
                buf.append(0x33)
                var le = v.littleEndian
                withUnsafeBytes(of: &le) { buf.append(contentsOf: $0) }
            }

        case .string(let s):
            let bytes = [UInt8](s.utf8)
            let len = bytes.count
            if len > 0x20 {
                if len <= 0xFF {
                    buf.append(0x61)
                    buf.append(UInt8(len))
                } else if len <= 0xFFFF {
                    buf.append(0x62)
                    var le = UInt16(len).littleEndian
                    withUnsafeBytes(of: &le) { buf.append(contentsOf: $0) }
                } else {
                    buf.append(0x63)
                    var le = UInt32(len).littleEndian
                    withUnsafeBytes(of: &le) { buf.append(contentsOf: $0) }
                }
            } else {
                buf.append(UInt8(0x40 + len))
            }
            buf.append(contentsOf: bytes)

        case .data(let data):
            let len = data.count
            if len > 0x20 {
                if len <= 0xFF {
                    buf.append(0x91)
                    buf.append(UInt8(len))
                } else if len <= 0xFFFF {
                    buf.append(0x92)
                    var le = UInt16(len).littleEndian
                    withUnsafeBytes(of: &le) { buf.append(contentsOf: $0) }
                } else {
                    buf.append(0x93)
                    var le = UInt32(len).littleEndian
                    withUnsafeBytes(of: &le) { buf.append(contentsOf: $0) }
                }
            } else {
                buf.append(UInt8(0x70 + len))
            }
            buf.append(data)
        }
    }
}
