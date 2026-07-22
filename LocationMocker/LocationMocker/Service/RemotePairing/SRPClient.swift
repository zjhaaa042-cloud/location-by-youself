import CryptoKit
import Foundation

/// SRP-6a 客户端（HAP Pair-Setup 变体）：
/// N = RFC 3526 3072 位群，g = 5，H = SHA-512，用户名 "Pair-Setup"。
struct SRPClient {

    /// RFC 3526 3072-bit MODP 群素数（大端 hex）。
    static let modulusHex =
        "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA6"
        + "3B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245"
        + "E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F2411"
        + "7C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F"
        + "83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08"
        + "CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9"
        + "DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AAAC42DAD33170D"
        + "04507A33A85521ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7"
        + "ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6BF12FFA06D98A0864D8760273"
        + "3EC86A64521F2B18177B200CBBE117577A615D6C770988C0BAD946E208E24FA074E5AB31"
        + "43DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF"

    static let N = BigUInt(hex: modulusHex)!
    static let g = BigUInt(5)
    static let groupByteCount = 384  // 3072 / 8

    private let username = "Pair-Setup"
    private let pin: String
    private let salt: Data
    private let a: BigUInt          // 客户端私钥
    let clientPublicKey: Data       // A = g^a mod N（384 字节大端）

    private(set) var sessionKey: Data?   // K
    private(set) var clientProof: Data?  // M1

    /// - Parameters:
    ///   - salt: 设备下发的 16 字节盐
    ///   - pin: 配对码，模拟 macOS 时使用 "000000"
    ///   - secret: 客户端私钥 a；nil 时随机生成 32 字节。测试时可注入固定值。
    init(salt: Data, pin: String, secret: Data? = nil) {
        self.salt = salt
        self.pin = pin
        let secretBytes = secret ?? Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        a = BigUInt(bigEndian: secretBytes)
        let publicValue = BigUInt.modPow(base: SRPClient.g, exponent: a, modulus: SRPClient.N)
        clientPublicKey = publicValue.toBigEndianData(paddedTo: SRPClient.groupByteCount)
    }

    /// 处理设备公钥 B，计算会话密钥 K 与客户端证明 M1。
    /// B 不合法（B mod N == 0）时抛出错误。
    mutating func processChallenge(serverPublicKey B: Data) throws {
        let nBytes = SRPClient.N.toBigEndianData(paddedTo: SRPClient.groupByteCount)

        let bInt = BigUInt(bigEndian: B)
        guard bInt % SRPClient.N != .zero else {
            throw SRPError.invalidServerPublicKey
        }

        // k = H(N ‖ pad384(g))
        let k = Self.hashInt(nBytes, SRPClient.g.toBigEndianData(paddedTo: SRPClient.groupByteCount))

        // x = H(salt ‖ H(user ":" pin))
        let innerHash = Self.hash(Data("\(username):\(pin)".utf8))
        let x = Self.hashInt(salt, innerHash)

        // u = H(pad384(A) ‖ pad384(B))
        let paddedA = BigUInt(bigEndian: clientPublicKey).toBigEndianData(paddedTo: SRPClient.groupByteCount)
        let paddedB = bInt.toBigEndianData(paddedTo: SRPClient.groupByteCount)
        let u = Self.hashInt(paddedA, paddedB)
        guard u != .zero else { throw SRPError.invalidScrambling }

        // S = (B − k·g^x mod N)^(a + u·x) mod N
        let gx = BigUInt.modPow(base: SRPClient.g, exponent: x, modulus: SRPClient.N)
        let kgx = (k * gx) % SRPClient.N
        var base = bInt
        if base < kgx {
            base = base + SRPClient.N
        }
        base = base - kgx
        let exponent = (a + (u * x)) % SRPClient.N
        let s = BigUInt.modPow(base: base, exponent: exponent, modulus: SRPClient.N)

        // K = H(S)（S 不补齐）
        let key = Self.hash(s.toBigEndianData())
        sessionKey = key

        // M1 = H( (H(N) ⊕ H(g)) ‖ H(user) ‖ salt ‖ A ‖ B ‖ K )，A/B 不补齐
        let hN = Self.hash(SRPClient.N.toBigEndianData())
        let hG = Self.hash(SRPClient.g.toBigEndianData())
        var xorHash = Data(count: hN.count)
        for i in 0..<hN.count { xorHash[i] = hN[i] ^ hG[i] }
        let hUser = Self.hash(Data(username.utf8))
        let aBytes = BigUInt(bigEndian: clientPublicKey).toBigEndianData()
        let bBytes = bInt.toBigEndianData()
        var m1Input = Data()
        m1Input.append(xorHash)
        m1Input.append(hUser)
        m1Input.append(salt)
        m1Input.append(aBytes)
        m1Input.append(bBytes)
        m1Input.append(key)
        clientProof = Self.hash(m1Input)
    }

    /// 校验设备证明 M2 = H(A ‖ M1 ‖ K)。
    func verifyServerProof(_ m2: Data) -> Bool {
        guard let key = sessionKey, let proof = clientProof else { return false }
        var input = Data()
        input.append(BigUInt(bigEndian: clientPublicKey).toBigEndianData())
        input.append(proof)
        input.append(key)
        return Self.hash(input) == m2
    }

    // MARK: - 工具

    private static func hash(_ data: Data) -> Data {
        Data(SHA512.hash(data: data))
    }

    private static func hashInt(_ parts: Data...) -> BigUInt {
        var joined = Data()
        for p in parts { joined.append(p) }
        return BigUInt(bigEndian: hash(joined))
    }

    enum SRPError: Error {
        case invalidServerPublicKey
        case invalidScrambling
    }
}
