import XCTest
@testable import LocationMocker

/// TrackShapeEstimator 色值识别单测：全部用合成像素缓冲区（纯数据，不依赖 UIImage/MapKit）
final class TrackShapeEstimatorTests: XCTestCase {

    private let width = 512
    private let height = 512
    /// 米/像素：与 220m 跨度 ÷ 512px（scale 1）接近的量级
    private let mpp = 0.43

    // MARK: - 合成缓冲工具

    /// 合成 RGBA8 缓冲：白底 + 满足 fill 的像素涂绿（模拟内场草坪浅绿色）
    private func makeBuffer(fill: (Int, Int) -> Bool) -> [UInt8] {
        var buf = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            for col in 0..<width where fill(col, row) {
                let o = (row * width + col) * 4
                buf[o] = 60       // R
                buf[o + 1] = 180  // G（满足 g > r+10 && g > b+10 && g > 100）
                buf[o + 2] = 60   // B
                buf[o + 3] = 255  // A
            }
        }
        return buf
    }

    /// 实心旋转椭圆判定：thetaDeg 为地图坐标方向角（0° = 长轴东西向，正值向北偏转）。
    /// 换算到图像坐标（y 向下 = 南）：长轴方向 (cosθ, -sinθ)，短轴方向 (sinθ, cosθ)。
    private func ellipse(cx: Double, cy: Double, a: Double, b: Double, thetaDeg: Double) -> (Int, Int) -> Bool {
        let t = thetaDeg * .pi / 180
        let c = cos(t), s = sin(t)
        return { col, row in
            let dx = Double(col) - cx
            let dy = Double(row) - cy
            let along = dx * c - dy * s   // 投影到长轴
            let perp = dx * s + dy * c    // 投影到短轴
            return (along * along) / (a * a) + (perp * perp) / (b * b) <= 1
        }
    }

    private func estimate(_ buf: [UInt8]) -> TrackShapeEstimate? {
        buf.withUnsafeBufferPointer {
            TrackShapeEstimator.estimate(
                pixels: $0,
                width: width,
                height: height,
                bytesPerRow: width * 4,
                mppX: mpp,
                mppY: mpp
            )
        }
    }

    // MARK: - 用例

    /// 旋转 30° 的绿色实心椭圆（半轴 100×46 px）：方向、周长档位、居中偏移
    func testEstimate_rotatedEllipse30Degrees() {
        let buf = makeBuffer(fill: ellipse(cx: 256, cy: 256, a: 100, b: 46, thetaDeg: 30))

        let result = estimate(buf)

        guard let r = result else { return XCTFail("绿色椭圆应被识别") }
        XCTAssertEqual(r.rotationDegrees, 30, accuracy: 3, "PCA 主轴应恢复椭圆方向角")
        // 长轴 ≈ 200px×0.43 ≈ 86m，短轴 ≈ 39.6m → scale ≈ 0.544 → 周长 ≈ 217m → 吸附 200m 档
        XCTAssertEqual(r.perimeterMeters, 200, accuracy: 0.001, "周长应吸附到最近档位 200m")
        XCTAssertEqual(r.centerOffsetEastMeters, 0, accuracy: 0.5, "椭圆居中时东向偏移应 ≈0")
        XCTAssertEqual(r.centerOffsetNorthMeters, 0, accuracy: 0.5, "椭圆居中时北向偏移应 ≈0")
        // 掩码像素数 ≈ 椭圆面积 π×100×46 ≈ 14451（离散化误差 5% 内）
        XCTAssertEqual(Double(r.maskPixelCount), .pi * 100 * 46, accuracy: .pi * 100 * 46 * 0.05)
    }

    /// 椭圆中心故意偏离图像中心 (东 40px, 北 40px)：中心偏移方向与数值正确
    func testEstimate_offsetEllipseReportsCenterOffset() {
        let buf = makeBuffer(fill: ellipse(cx: 296, cy: 216, a: 100, b: 46, thetaDeg: 15))

        let result = estimate(buf)

        guard let r = result else { return XCTFail("绿色椭圆应被识别") }
        let expected = 40 * mpp // 40px × 0.43 = 17.2m
        XCTAssertEqual(r.centerOffsetEastMeters, expected, accuracy: expected * 0.1,
                       "质心偏东 40px → 东向偏移 +17.2m（±10%）")
        XCTAssertEqual(r.centerOffsetNorthMeters, expected, accuracy: expected * 0.1,
                       "质心偏北 40px（图像 y 减小）→ 北向偏移 +17.2m（±10%）")
    }

    /// 全白缓冲：无任何绿色 → nil（调用方走默认回退）
    func testEstimate_allWhiteReturnsNil() {
        let buf = makeBuffer { _, _ in false }
        XCTAssertNil(estimate(buf))
    }

    /// 只有碎绿块（< 总像素 0.3%）：视为噪声丢弃 → nil
    func testEstimate_tinyBlobReturnsNil() {
        // 半径 10px 的圆 ≈ 314px < 512×512×0.3% ≈ 786px
        let buf = makeBuffer(fill: ellipse(cx: 256, cy: 256, a: 10, b: 10, thetaDeg: 0))
        XCTAssertNil(estimate(buf))
    }

    /// 远处角落有更大的绿块时，仍应选中离图像中心最近的操场大小绿块
    func testEstimate_prefersComponentNearestToCenter() {
        let far = ellipse(cx: 70, cy: 70, a: 110, b: 70, thetaDeg: 70)   // 角落大块（面积更大）
        let near = ellipse(cx: 256, cy: 256, a: 100, b: 46, thetaDeg: 0) // 近中心操场块
        let buf = makeBuffer { col, row in far(col, row) || near(col, row) }

        let result = estimate(buf)

        guard let r = result else { return XCTFail("应识别到绿块") }
        // 若误选角落大块：方向会 ≈70°、质心偏移巨大；选近中心块则方向 ≈0°、偏移 ≈0
        XCTAssertEqual(r.rotationDegrees, 0, accuracy: 3, "应选中近中心的块（方向 0° 而非 70°）")
        XCTAssertEqual(r.centerOffsetEastMeters, 0, accuracy: 1)
        XCTAssertEqual(r.centerOffsetNorthMeters, 0, accuracy: 1)
    }

    /// 横躺椭圆（长轴东西向）：方向角归一化为 0°，且在 [0, 180) 内
    func testEstimate_horizontalEllipseRotationZero() {
        let buf = makeBuffer(fill: ellipse(cx: 256, cy: 256, a: 100, b: 46, thetaDeg: 0))

        guard let r = estimate(buf) else { return XCTFail("绿色椭圆应被识别") }
        XCTAssertEqual(r.rotationDegrees, 0, accuracy: 3)
        XCTAssertGreaterThanOrEqual(r.rotationDegrees, 0)
        XCTAssertLessThan(r.rotationDegrees, 180)
    }

    /// 竖直椭圆（长轴南北向）：方向角 90°（归一化到 [0, 180)，不出现 -90°/270°）
    func testEstimate_verticalEllipseRotation90() {
        let buf = makeBuffer(fill: ellipse(cx: 256, cy: 256, a: 100, b: 46, thetaDeg: 90))

        guard let r = estimate(buf) else { return XCTFail("绿色椭圆应被识别") }
        XCTAssertEqual(r.rotationDegrees, 90, accuracy: 3)
        XCTAssertGreaterThanOrEqual(r.rotationDegrees, 0)
        XCTAssertLessThan(r.rotationDegrees, 180)
    }
}
