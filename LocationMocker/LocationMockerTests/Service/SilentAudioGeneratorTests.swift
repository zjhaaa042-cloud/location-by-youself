import XCTest
@testable import LocationMocker

/// 静音 WAV 生成器（BackgroundKeepAlive 的纯逻辑部分）合法性校验
final class SilentAudioGeneratorTests: XCTestCase {

    /// WAV 文件结构合法：RIFF/WAVE 头 + fmt/data 子块 + 尺寸字段自洽
    func testMakeWAVData_validHeaderStructure() {
        let sampleRate = 8000
        let duration = 1.0
        let data = SilentAudioGenerator.makeWAVData(durationSeconds: duration, sampleRate: sampleRate)

        let frameCount = Int(duration * Double(sampleRate))
        let pcmBytes = frameCount * 2 // 16bit 单声道
        XCTAssertEqual(data.count, 44 + pcmBytes, "总长 = 44 字节头 + PCM 数据")

        // RIFF / WAVE 魔数
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: data[12..<16], as: UTF8.self), "fmt ")
        XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")

        // RIFF 总块大小 = 文件长 - 8
        XCTAssertEqual(data.littleEndianUInt32(at: 4), UInt32(data.count - 8))
        // PCM 格式 = 1，单声道 = 1，位深 = 16
        XCTAssertEqual(data.littleEndianUInt16(at: 20), 1)
        XCTAssertEqual(data.littleEndianUInt16(at: 22), 1)
        XCTAssertEqual(data.littleEndianUInt16(at: 34), 16)
        // 采样率与 data 子块大小
        XCTAssertEqual(data.littleEndianUInt32(at: 24), UInt32(sampleRate))
        XCTAssertEqual(data.littleEndianUInt32(at: 40), UInt32(pcmBytes))
    }

    /// PCM 段全零（静音），且时长缩放正确
    func testMakeWAVData_silentSamplesAndDurationScaling() {
        let data = SilentAudioGenerator.makeWAVData(durationSeconds: 2.0, sampleRate: 8000)
        XCTAssertEqual(data.count, 44 + 2 * 8000 * 2)
        XCTAssertTrue(data[44...].allSatisfy { $0 == 0 }, "PCM 采样必须全零（静音）")
    }
}

private extension Data {
    /// 读取小端 UInt32（WAV 为 RIFF 小端格式）
    func littleEndianUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }

    /// 读取小端 UInt16
    func littleEndianUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }
}
