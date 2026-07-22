import Foundation

/// 最小化无符号大整数实现，专为 SRP-6a（3072 位模幂）设计。
/// 内部以小端 UInt64 limbs 存储，不含前导零（零值 limbs 为空数组）。
/// 部署目标 iOS 17，UInt128 不可用，128 位中间运算以 (hi, lo) 手写实现。
struct BigUInt: Equatable {
    private(set) var limbs: [UInt64]  // 小端：limbs[0] 为最低位

    // MARK: - 128 位中间结果（hi:lo）

    private struct U128 {
        var hi: UInt64
        var lo: UInt64
    }

    /// 64×64→128 全乘法（Hacker's Delight mulhu/mullu）。
    private static func mul64(_ a: UInt64, _ b: UInt64) -> U128 {
        let aLo = a & 0xFFFF_FFFF
        let aHi = a >> 32
        let bLo = b & 0xFFFF_FFFF
        let bHi = b >> 32

        let ll = aLo &* bLo
        let lh = aLo &* bHi
        let hl = aHi &* bLo
        let hh = aHi &* bHi

        // cross = lh + hl + (ll >> 32)，跟踪两次溢出进位（各代表 2^64 → hi 的位 32）
        let (cross1, c1) = lh.addingReportingOverflow(hl)
        let (cross, c2) = cross1.addingReportingOverflow(ll >> 32)
        var hi = hh &+ (cross >> 32)
        if c1 { hi &+= 1 << 32 }
        if c2 { hi &+= 1 << 32 }
        let lo = (ll & 0xFFFF_FFFF) | (cross << 32)
        return U128(hi: hi, lo: lo)
    }

    /// 128 + 64 → 128。
    private static func add64(_ x: U128, _ y: UInt64) -> U128 {
        let (lo, carry) = x.lo.addingReportingOverflow(y)
        return U128(hi: x.hi &+ (carry ? 1 : 0), lo: lo)
    }

    private static func cmp(_ a: U128, _ b: U128) -> ComparisonResult {
        if a.hi != b.hi { return a.hi < b.hi ? .orderedAscending : .orderedDescending }
        if a.lo != b.lo { return a.lo < b.lo ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }

    /// (hi:lo) / d → (商, 余数)，要求 hi < d（商才能装进 64 位）。
    /// 逐位二进制长除，64 轮。
    private static func divmod128by64(_ hi: UInt64, _ lo: UInt64, by d: UInt64) -> (q: UInt64, r: UInt64) {
        precondition(d != 0 && hi < d, "divmod128by64 前置条件不满足")
        var rem = hi
        var quotient: UInt64 = 0
        // d 的补数：2^64 - d（用于处理 rem<<1 溢出的情况）
        let dComplement = ~d &+ 1
        for i in stride(from: 63, through: 0, by: -1) {
            let bit = (lo >> UInt64(i)) & 1
            let overflow = rem >> 63  // rem < d ≤ 2^64−1；若最高位为 1 则 rem<<1 溢出
            rem = (rem << 1) | bit
            // 真实被除值 R = rem_stored + overflow·2^64，恒有 R < 2d（因旧 rem < d）
            if overflow == 1 {
                // R − d = rem_stored + (2^64 − d)，结果 < d 可表示
                rem = rem &+ dComplement
                quotient |= (1 << UInt64(i))
            } else if rem >= d {
                rem = rem - d
                quotient |= (1 << UInt64(i))
            }
        }
        return (quotient, rem)
    }

    // MARK: - 构造

    static let zero = BigUInt(limbs: [])
    static let one = BigUInt(1)

    init(_ value: UInt64) {
        limbs = value == 0 ? [] : [value]
    }

    private init(limbs: [UInt64]) {
        self.limbs = limbs
        normalize()
    }

    /// 由大端字节构造。
    init(bigEndian bytes: [UInt8]) {
        var result: [UInt64] = []
        result.reserveCapacity((bytes.count + 7) / 8)
        var i = bytes.count
        while i > 0 {
            var limb: UInt64 = 0
            let start = max(0, i - 8)
            for j in start..<i {
                limb = (limb << 8) | UInt64(bytes[j])
            }
            result.append(limb)
            i = start
        }
        self.init(limbs: result)
    }

    init(bigEndian data: Data) {
        self.init(bigEndian: [UInt8](data))
    }

    /// 由大端 hex 字符串构造。
    init?(hex: String) {
        var chars = Array(hex)
        if chars.count % 2 != 0 { chars.insert("0", at: 0) }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let hi = UInt8(String(chars[i]), radix: 16),
                  let lo = UInt8(String(chars[i + 1]), radix: 16) else { return nil }
            bytes.append((hi << 4) | lo)
            i += 2
        }
        self.init(bigEndian: bytes)
    }

    private mutating func normalize() {
        while let last = limbs.last, last == 0 { limbs.removeLast() }
    }

    // MARK: - 导出

    /// 导出大端字节；可左补零到固定长度。
    func toBigEndianBytes(paddedTo length: Int? = nil) -> [UInt8] {
        var bytes: [UInt8] = []
        for limb in limbs.reversed() {
            var chunk: [UInt8] = []
            var v = limb
            for _ in 0..<8 {
                chunk.insert(UInt8(v & 0xFF), at: 0)
                v >>= 8
            }
            if bytes.isEmpty {
                while chunk.count > 1 && chunk.first == 0 { chunk.removeFirst() }
            }
            bytes.append(contentsOf: chunk)
        }
        if let length = length, bytes.count < length {
            bytes = [UInt8](repeating: 0, count: length - bytes.count) + bytes
        }
        return bytes
    }

    func toBigEndianData(paddedTo length: Int? = nil) -> Data {
        Data(toBigEndianBytes(paddedTo: length))
    }

    // MARK: - 基本属性

    var isZero: Bool { limbs.isEmpty }

    var bitCount: Int {
        guard let top = limbs.last else { return 0 }
        return (limbs.count - 1) * 64 + (64 - top.leadingZeroBitCount)
    }

    func bit(_ index: Int) -> Bool {
        let limbIndex = index / 64
        guard limbIndex < limbs.count else { return false }
        return (limbs[limbIndex] >> UInt64(index % 64)) & 1 == 1
    }

    // MARK: - 比较

    static func < (lhs: BigUInt, rhs: BigUInt) -> Bool {
        if lhs.limbs.count != rhs.limbs.count { return lhs.limbs.count < rhs.limbs.count }
        for i in stride(from: lhs.limbs.count - 1, through: 0, by: -1) {
            if lhs.limbs[i] != rhs.limbs[i] { return lhs.limbs[i] < rhs.limbs[i] }
        }
        return false
    }

    static func <= (lhs: BigUInt, rhs: BigUInt) -> Bool { lhs < rhs || lhs == rhs }
    static func > (lhs: BigUInt, rhs: BigUInt) -> Bool { !(lhs <= rhs) }
    static func >= (lhs: BigUInt, rhs: BigUInt) -> Bool { !(lhs < rhs) }

    // MARK: - 加减

    static func + (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        let count = max(lhs.limbs.count, rhs.limbs.count)
        var result = [UInt64](repeating: 0, count: count)
        var carry: UInt64 = 0
        for i in 0..<count {
            let a = i < lhs.limbs.count ? lhs.limbs[i] : 0
            let b = i < rhs.limbs.count ? rhs.limbs[i] : 0
            let (s1, o1) = a.addingReportingOverflow(b)
            let (s2, o2) = s1.addingReportingOverflow(carry)
            result[i] = s2
            carry = (o1 ? 1 : 0) | (o2 ? 1 : 0)
        }
        if carry != 0 { result.append(carry) }
        return BigUInt(limbs: result)
    }

    /// 要求 lhs >= rhs，否则触发断言（数学上不会产生负值）。
    static func - (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        precondition(lhs >= rhs, "BigUInt 减法结果为负")
        var result = lhs.limbs
        var borrow: UInt64 = 0
        for i in 0..<result.count {
            let b = i < rhs.limbs.count ? rhs.limbs[i] : 0
            let (d1, o1) = result[i].subtractingReportingOverflow(b)
            let (d2, o2) = d1.subtractingReportingOverflow(borrow)
            result[i] = d2
            borrow = (o1 ? 1 : 0) | (o2 ? 1 : 0)
        }
        return BigUInt(limbs: result)
    }

    // MARK: - 移位

    func shiftedLeft(_ bits: Int) -> BigUInt {
        guard !isZero else { return self }
        let limbShift = bits / 64
        let bitShift = bits % 64
        var result = [UInt64](repeating: 0, count: limbs.count + limbShift + 1)
        for i in 0..<limbs.count {
            result[i + limbShift] |= limbs[i] << UInt64(bitShift)
            if bitShift > 0 {
                result[i + limbShift + 1] |= limbs[i] >> UInt64(64 - bitShift)
            }
        }
        return BigUInt(limbs: result)
    }

    func shiftedRight(_ bits: Int) -> BigUInt {
        let limbShift = bits / 64
        let bitShift = bits % 64
        guard limbShift < limbs.count else { return .zero }
        var result = [UInt64](repeating: 0, count: limbs.count - limbShift)
        for i in 0..<result.count {
            result[i] = limbs[i + limbShift] >> UInt64(bitShift)
            if bitShift > 0, i + limbShift + 1 < limbs.count {
                result[i] |= limbs[i + limbShift + 1] << UInt64(64 - bitShift)
            }
        }
        return BigUInt(limbs: result)
    }

    // MARK: - 乘法

    static func * (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        guard !lhs.isZero, !rhs.isZero else { return .zero }
        var result = [UInt64](repeating: 0, count: lhs.limbs.count + rhs.limbs.count)
        for i in 0..<lhs.limbs.count {
            var carry: UInt64 = 0
            for j in 0..<rhs.limbs.count {
                let product = mul64(lhs.limbs[i], rhs.limbs[j])
                let withCarry = add64(product, carry)
                let total = add64(withCarry, result[i + j])
                result[i + j] = total.lo
                carry = total.hi
            }
            var k = i + rhs.limbs.count
            while carry != 0 {
                let (sum, overflow) = result[k].addingReportingOverflow(carry)
                result[k] = sum
                carry = overflow ? 1 : 0
                k += 1
            }
        }
        return BigUInt(limbs: result)
    }

    // MARK: - 除法（Knuth Algorithm D）

    /// 返回 (商, 余数)。
    func quotientAndRemainder(dividingBy divisor: BigUInt) -> (BigUInt, BigUInt) {
        precondition(!divisor.isZero, "除以零")
        if self < divisor { return (.zero, self) }
        if divisor.limbs.count == 1 {
            return divmodByLimb(divisor.limbs[0])
        }

        let n = divisor.limbs.count
        let m = limbs.count - n

        // 归一化：使除数最高 limb 的最高位为 1
        let shift = divisor.limbs[n - 1].leadingZeroBitCount
        let vn = divisor.shiftedLeft(shift).limbs  // 恰好 n 个 limb
        var un = shiftedLeft(shift).limbs
        un.append(0)  // 附加高位，共 m+n+1 个 limb
        while un.count < m + n + 1 { un.append(0) }

        var quotient = [UInt64](repeating: 0, count: m + 1)

        for j in stride(from: m, through: 0, by: -1) {
            // qhat = (un[j+n]·b + un[j+n−1]) / vn[n−1]，可能等于 b（需截断为 b−1）
            var qhat: UInt64
            var rhatHi: UInt64  // rhat 以 (hi:lo) 表示：初始 rhat < vn[n−1]，加 vn[n−1] 后可能 ≥ b
            var rhatLo: UInt64
            if un[j + n] == vn[n - 1] {
                qhat = UInt64.max  // 即 b−1
                let (r, carry) = un[j + n - 1].addingReportingOverflow(vn[n - 1])
                rhatLo = r
                rhatHi = carry ? 1 : 0
            } else {
                let (q, r) = BigUInt.divmod128by64(un[j + n], un[j + n - 1], by: vn[n - 1])
                qhat = q
                rhatLo = r
                rhatHi = 0
            }

            // 修正：while qhat·vn[n−2] > (rhat·b + un[j+n−2])
            while rhatHi == 0 {
                let lhs = BigUInt.mul64(qhat, vn[n - 2])
                let rhs = U128(hi: rhatLo, lo: un[j + n - 2])  // rhat·b + un[j+n−2]，rhatHi==0 时 rhat=rhatLo
                if BigUInt.cmp(lhs, rhs) != .orderedDescending { break }
                qhat &-= 1
                let (r, carry) = rhatLo.addingReportingOverflow(vn[n - 1])
                rhatLo = r
                rhatHi = carry ? 1 : 0
            }

            // 乘并减：un[j...j+n] −= qhat · vn
            var mulCarry: UInt64 = 0
            var borrow: UInt64 = 0
            for i in 0..<n {
                let p = BigUInt.mul64(qhat, vn[i])
                let pSum = BigUInt.add64(p, mulCarry)
                mulCarry = pSum.hi
                let (d1, o1) = un[i + j].subtractingReportingOverflow(pSum.lo)
                let (d2, o2) = d1.subtractingReportingOverflow(borrow)
                un[i + j] = d2
                borrow = (o1 ? 1 : 0) | (o2 ? 1 : 0)
            }
            let (d3, o3) = un[j + n].subtractingReportingOverflow(mulCarry)
            let (d4, o4) = d3.subtractingReportingOverflow(borrow)
            un[j + n] = d4

            if o3 || o4 {
                // 减过头了：qhat −= 1，并加回除数
                qhat &-= 1
                var carry: UInt64 = 0
                for i in 0..<n {
                    let (s1, p1) = un[i + j].addingReportingOverflow(vn[i])
                    let (s2, p2) = s1.addingReportingOverflow(carry)
                    un[i + j] = s2
                    carry = (p1 ? 1 : 0) | (p2 ? 1 : 0)
                }
                un[j + n] = un[j + n] &+ carry
            }

            quotient[j] = qhat
        }

        let remainder = BigUInt(limbs: Array(un[0..<n])).shiftedRight(shift)
        return (BigUInt(limbs: quotient), remainder)
    }

    private func divmodByLimb(_ d: UInt64) -> (BigUInt, BigUInt) {
        var quotient = [UInt64](repeating: 0, count: limbs.count)
        var rem: UInt64 = 0
        for i in stride(from: limbs.count - 1, through: 0, by: -1) {
            let (q, r) = BigUInt.divmod128by64(rem, limbs[i], by: d)
            quotient[i] = q
            rem = r
        }
        return (BigUInt(limbs: quotient), BigUInt(rem))
    }

    static func / (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        lhs.quotientAndRemainder(dividingBy: rhs).0
    }

    static func % (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        lhs.quotientAndRemainder(dividingBy: rhs).1
    }

    // MARK: - 模幂（平方乘方）

    static func modPow(base: BigUInt, exponent: BigUInt, modulus: BigUInt) -> BigUInt {
        precondition(!modulus.isZero, "模数为零")
        if modulus == .one { return .zero }
        var result = BigUInt.one
        var b = base % modulus
        let bits = exponent.bitCount
        for i in 0..<bits {
            if exponent.bit(i) {
                result = (result * b) % modulus
            }
            if i < bits - 1 {
                b = (b * b) % modulus
            }
        }
        return result
    }
}
