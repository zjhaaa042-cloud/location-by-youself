import Foundation

/// 读取打包进 App 的 embedded.mobileprovision，解析签名到期时间。
///
/// 免费 Personal Team 的描述文件 7 天到期，到期后 App 无法启动。
/// 模拟器构建没有内嵌描述文件，返回 nil。
enum SignatureExpiry {
    /// 描述文件到期日；解析失败返回 nil
    static var expirationDate: Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let plistData = extractPlist(from: data),
              let dict = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return nil }
        return dict["ExpirationDate"] as? Date
    }

    /// 距离到期的整天数；0 = 今天到期
    static var daysRemaining: Int? {
        guard let expiry = expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
    }

    /// mobileprovision 是 PKCS#7 签名包裹的 plist；截取 <?xml ... </plist> 部分解析
    static func extractPlist(from data: Data) -> Data? {
        guard let startRange = data.range(of: Data("<?xml".utf8)),
              let endRange = data.range(of: Data("</plist>".utf8),
                                        in: startRange.lowerBound..<data.count)
        else { return nil }
        return data[startRange.lowerBound..<endRange.upperBound]
    }
}
