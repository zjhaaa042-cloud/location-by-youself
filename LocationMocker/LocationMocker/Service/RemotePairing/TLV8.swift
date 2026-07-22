import Foundation

/// HAP TLV8 编解码。单个条目值超过 255 字节时拆分为多个连续同类型条目；
/// 解码时连续同类型条目合并为一个值。
enum TLV8 {

    enum ItemType: UInt8 {
        case method = 0x00
        case identifier = 0x01
        case salt = 0x02
        case publicKey = 0x03
        case proof = 0x04
        case encryptedData = 0x05
        case state = 0x06
        case error = 0x07
        case signature = 0x0A
        case info = 0x11
    }

    struct Item {
        let type: UInt8
        let value: Data
    }

    /// 编码为 TLV8 字节流；值 > 255 字节自动拆分。
    static func encode(_ items: [Item]) -> Data {
        var out = Data()
        for item in items {
            var value = item.value
            if value.isEmpty {
                out.append(item.type)
                out.append(0)
                continue
            }
            while !value.isEmpty {
                let chunk = value.prefix(255)
                out.append(item.type)
                out.append(UInt8(chunk.count))
                out.append(contentsOf: chunk)
                value = value.dropFirst(chunk.count)
            }
        }
        return out
    }

    /// 解码 TLV8 字节流；连续同类型条目合并，保持首次出现顺序。
    static func decode(_ data: Data) throws -> [Item] {
        var items: [Item] = []
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            guard offset + 2 <= bytes.count else {
                throw TLV8Error.truncated
            }
            let type = bytes[offset]
            let length = Int(bytes[offset + 1])
            offset += 2
            guard offset + length <= bytes.count else {
                throw TLV8Error.truncated
            }
            let value = Data(bytes[offset..<(offset + length)])
            offset += length

            if let last = items.last, last.type == type {
                var merged = last.value
                merged.append(value)
                items[items.count - 1] = Item(type: type, value: merged)
            } else {
                items.append(Item(type: type, value: value))
            }
        }
        return items
    }

    /// 便捷：按类型查找第一个匹配项。
    static func first(_ type: ItemType, in items: [Item]) -> Data? {
        items.first(where: { $0.type == type.rawValue })?.value
    }

    enum TLV8Error: Error {
        case truncated
    }
}
