import XCTest
@testable import LocationMocker

/// 签名到期解析（SignatureExpiry）的 plist 抽取逻辑校验
final class SignatureExpiryTests: XCTestCase {

    private func makeWrappedMobileprovision(expiration: String = "2026-09-01T00:00:00Z") -> Data {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
            <key>AppIDName</key><string>LocationMocker</string>
            <key>ExpirationDate</key><date>\(expiration)</date>
        </dict>
        </plist>
        """
        var data = Data([0x30, 0x82, 0x13, 0x37]) // 模拟 PKCS#7 头
        data.append(plist.data(using: .utf8)!)
        data.append(Data([0x00, 0xFF, 0x42]))     // 模拟尾部签名数据
        return data
    }

    /// 能从 CMS 包裹的描述文件中截出合法 plist 并解析出到期时间
    func testExtractPlist_fromCMSWrappedData() throws {
        let extracted = SignatureExpiry.extractPlist(from: makeWrappedMobileprovision())
        XCTAssertNotNil(extracted)
        let dict = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: XCTUnwrap(extracted), format: nil) as? [String: Any]
        )
        let expiry = try XCTUnwrap(dict["ExpirationDate"] as? Date)
        XCTAssertEqual(expiry.timeIntervalSince1970,
                       Date(timeIntervalSince1970: 1788220800).timeIntervalSince1970,
                       accuracy: 1) // 2026-09-01T00:00:00Z
    }

    /// 前后都有二进制垃圾数据时仍能准确定位 plist 边界
    func testExtractPlist_ignoresLeadingAndTrailingBytes() throws {
        var data = Data(repeating: 0xAB, count: 64)
        data.append(makeWrappedMobileprovision())
        data.append(Data(repeating: 0xCD, count: 64))
        let extracted = try XCTUnwrap(SignatureExpiry.extractPlist(from: data))
        let dict = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: extracted, format: nil) as? [String: Any]
        )
        XCTAssertEqual(dict["AppIDName"] as? String, "LocationMocker")
    }

    /// 非描述文件数据返回 nil 而不是崩溃
    func testExtractPlist_noPlistReturnsNil() {
        XCTAssertNil(SignatureExpiry.extractPlist(from: Data([0x01, 0x02, 0x03])))
        XCTAssertNil(SignatureExpiry.extractPlist(from: Data("<?xml only".utf8)))
        XCTAssertNil(SignatureExpiry.extractPlist(from: Data()))
    }
}
