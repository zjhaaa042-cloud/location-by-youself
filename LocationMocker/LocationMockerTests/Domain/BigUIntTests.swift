import XCTest
@testable import LocationMocker

/// BigUInt 正确性验证：基础运算 + 3072 位模幂测试向量（由 refs/gen_srp_vectors.py 生成）。
final class BigUIntTests: XCTestCase {

    func testZeroOneRoundTrip() {
        XCTAssertTrue(BigUInt(0).isZero)
        XCTAssertEqual(BigUInt(0).toBigEndianBytes(), [])
        XCTAssertEqual(BigUInt(1).toBigEndianBytes(), [1])
        XCTAssertEqual(BigUInt(bigEndian: [0x00, 0x00, 0x01, 0x00]), BigUInt(256))
    }

    func testHexInit() {
        XCTAssertEqual(BigUInt(hex: "FF"), BigUInt(255))
        XCTAssertEqual(BigUInt(hex: "0100"), BigUInt(256))
        XCTAssertEqual(BigUInt(hex: "deadbeef"), BigUInt(0xDEADBEEF))
        XCTAssertNil(BigUInt(hex: "zz"))
    }

    func testAddSubMulSmall() {
        let a = BigUInt(0xFFFFFFFFFFFFFFFF)
        let b = BigUInt(1)
        XCTAssertEqual((a + b).toBigEndianBytes(), [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual((a + b - a), b)
        let c = BigUInt(0xFFFFFFFF)
        XCTAssertEqual((c * c).toBigEndianBytes(), [0xFF, 0xFF, 0xFF, 0xFE, 0x00, 0x00, 0x00, 0x01])
    }

    func testDivisionRandomConsistency() {
        // 多组伪随机数验证 a = q*b + r
        var state: UInt64 = 0x123456789ABCDEF
        func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 11
        }
        for _ in 0..<50 {
            let aBytes = (0..<24).map { _ in UInt8(truncatingIfNeeded: next()) }
            let bBytes = (0..<9).map { _ in UInt8(truncatingIfNeeded: next()) }
            let a = BigUInt(bigEndian: aBytes)
            let b = BigUInt(bigEndian: bBytes)
            guard !b.isZero else { continue }
            let (q, r) = a.quotientAndRemainder(dividingBy: b)
            XCTAssertEqual(q * b + r, a)
            XCTAssertTrue(r < b)
        }
    }

    func testModPowVector() {
        // refs/gen_srp_vectors.py 生成的 3072 位向量
        let base = BigUInt(hex: "DEADBEEF1234567890ABCDEF")!
        let exp = BigUInt(hex: "FEDCBA9876543210")!
        let n = BigUInt(hex: SRPClient.modulusHex)!
        let expected =
            "24EAB4B14751BC820BDF0B4F36E7C581306F9BBBEDC10FACF5E52184F32DDA29B3BAE63821F5ECA9CB3F01D133B5B3EC53077EE0165C25D7688174C7DCB39BF9146A43D7C122BCCEF44DF28C22623ABE1D0C66E1EE3E571E57237383D198F1C9644282ABFDEF9E4A5B9D6863D4EF8AA425D28FCFF33E399BCB235937DEFC3152A675C1B02161F91900F28F4344A290E588044655E26FEA2E1FE92E54BBE94DE8F64867FF0284C3EFDF0660001BFBA63FC70EFF200A086570DADE6D0CF4AB4526F882B8AB91D92460FD3D3B5F30B468DA1118E11131F2D8464878F74C3A339C22306D518C8F40552BD3F01F6C086EECDA2B81F945E3227C85B4BBEE3C3DA92C40131F1A0EE59F00DB5C2FCCA9D5D9F218B4E3E578F3B9B5A8B59CC088055244F54D26AD389310E451F8B08C31710DE1EE6C47FA97AF2601DE92C564FA3B48EE1401D4AC84D2DA582CEB28470DF0C2FEBA989D3412602BED7AFD6DDFFD047399488A3B77C98803A3A605309887B19A3EBF820D7A8A010892CD589A93572B696023"
        let result = BigUInt.modPow(base: base, exponent: exp, modulus: n)
        XCTAssertEqual(hexString(result), expected)
    }

    func testModPowSmall() {
        // 3^7 mod 11 = 2187 mod 11 = 9
        XCTAssertEqual(BigUInt.modPow(base: BigUInt(3), exponent: BigUInt(7), modulus: BigUInt(11)), BigUInt(9))
    }

    private func hexString(_ v: BigUInt) -> String {
        v.toBigEndianBytes().map { String(format: "%02X", $0) }.joined()
    }
}
