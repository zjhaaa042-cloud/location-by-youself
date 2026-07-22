import Foundation

/// 地图图像色值识别结果：跑道方向 / 周长档位 / 精确中心偏移
struct TrackShapeEstimate: Equatable {
    /// 跑道方向角（直接交给 TrackRoutePlanner 的 rotationDegrees：
    /// 0° = 直道东西向，已归一化到 [0, 180)，因为椭圆无方向性）
    let rotationDegrees: Double
    /// 周长（米），已按估计缩放吸附到最近档位（200 / 300 / 400）
    let perimeterMeters: Double
    /// 跑道中心相对快照中心的东向偏移（米，向东为正）
    let centerOffsetEastMeters: Double
    /// 跑道中心相对快照中心的北向偏移（米，向北为正）
    let centerOffsetNorthMeters: Double
    /// 参与识别的绿色掩码像素数（诊断/调试用）
    let maskPixelCount: Int
}

/// 从标准样式地图快照中用色值识别操场跑道形状（纯逻辑，不依赖 UIKit/MapKit，可单测）
///
/// 原理：Apple 标准地图样式下，操场内场草坪渲染为浅绿色，与红色塑胶跑道、
/// 灰色道路/建筑差异明显。用绿色掩码 + 4 连通域分析找出操场绿块，
/// 再对块内像素做 PCA 主轴分析，得到跑道方向与尺寸。
///
/// 坐标系约定：
/// - 图像坐标：x 向右 = 地图东，y 向下 = 地图南（快照正北朝上）；
/// - 米/像素（mppX/mppY）由调用方用快照 region span ÷ 图像尺寸算出；
/// - 输出角度遵循 TrackRoutePlanner 约定（0° = 直道沿东西方向）；
/// - 中心偏移东/北为正（米制），可直接交给 TrackRoutePlanner.translated。
enum TrackShapeEstimator {

    // MARK: - 可调常量

    /// 连通域最小占比：像素数低于总像素 0.3% 的碎块丢弃（绿化带、小草坪等噪声）
    static let minComponentRatio = 0.003
    /// 标准 400m 场几何全幅（外缘）：长轴 = 直道 + 两端弯半径，短轴 = 两弯直径
    static let standardFullMajorMeters = TrackRoutePlanner.standardStraightMeters + 2 * TrackRoutePlanner.standardRadiusMeters // 157.39m
    static let standardFullMinorMeters = 2 * TrackRoutePlanner.standardRadiusMeters // 73m
    /// 尺寸缩放系数的合理范围：防止误识别时给出离谱周长
    static let scaleRange: ClosedRange<Double> = 0.35...1.3
    /// 周长吸附档位（与微调面板预设一致）
    static let perimeterSnaps: [Double] = [200, 300, 400]

    /// 从 RGBA8 像素缓冲区估计跑道形状
    /// - Parameters:
    ///   - pixels: RGBA8 像素数据（每像素 4 字节，R/G/B/A 顺序）
    ///   - width / height: 图像像素尺寸
    ///   - bytesPerRow: 每行字节数（≥ width × 4）
    ///   - mppX / mppY: 米/像素（x 向东，y 向南）
    /// - Returns: 识别结果；没有任何有效绿块时返回 nil（调用方走默认回退）
    static func estimate(
        pixels: UnsafeBufferPointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        mppX: Double,
        mppY: Double
    ) -> TrackShapeEstimate? {
        guard width > 0, height > 0, bytesPerRow >= width * 4,
              pixels.count >= bytesPerRow * (height - 1) + width * 4,
              mppX > 0, mppY > 0 else { return nil }

        let totalPixels = width * height

        // MARK: 1. 绿色掩码
        // Apple 标准地图的内场草坪为浅绿色：G 通道明显高于 R/B 且亮度不太低
        var mask = [Bool](repeating: false, count: totalPixels)
        for row in 0..<height {
            let rowBase = row * bytesPerRow
            for col in 0..<width {
                let o = rowBase + col * 4
                let r = Int(pixels[o]), g = Int(pixels[o + 1]), b = Int(pixels[o + 2])
                mask[row * width + col] = (g > r + 10) && (g > b + 10) && (g > 100)
            }
        }

        // MARK: 2. 4 连通域标记（迭代 BFS，避免递归爆栈）
        // 同时累计每个块的一阶/二阶矩（质心 + 协方差用）
        var labels = [Int32](repeating: 0, count: totalPixels)
        var compCount = [Int]()
        var compSumX = [Double]()
        var compSumY = [Double]()
        var compSumXX = [Double]()
        var compSumYY = [Double]()
        var compSumXY = [Double]()

        var queue = [Int]()
        queue.reserveCapacity(4096)

        for start in 0..<totalPixels where mask[start] && labels[start] == 0 {
            let label = Int32(compCount.count + 1)
            var count = 0
            var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0
            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            labels[start] = label
            var head = 0
            while head < queue.count {
                let cur = queue[head]
                head += 1
                let cr = cur / width
                let cc = cur - cr * width
                count += 1
                let x = Double(cc), y = Double(cr)
                sx += x; sy += y
                sxx += x * x; syy += y * y; sxy += x * y
                // 4 连通邻居（上下左右）
                if cc > 0 {
                    let n = cur - 1
                    if mask[n] && labels[n] == 0 { labels[n] = label; queue.append(n) }
                }
                if cc < width - 1 {
                    let n = cur + 1
                    if mask[n] && labels[n] == 0 { labels[n] = label; queue.append(n) }
                }
                if cr > 0 {
                    let n = cur - width
                    if mask[n] && labels[n] == 0 { labels[n] = label; queue.append(n) }
                }
                if cr < height - 1 {
                    let n = cur + width
                    if mask[n] && labels[n] == 0 { labels[n] = label; queue.append(n) }
                }
            }
            compCount.append(count)
            compSumX.append(sx); compSumY.append(sy)
            compSumXX.append(sxx); compSumYY.append(syy); compSumXY.append(sxy)
        }

        // 丢弃碎块后，选质心离图像中心最近的块
        // （操场通常就在准星附近；远处更大的公园绿地不应抢中）
        let minCount = max(1, Int((Double(totalPixels) * minComponentRatio).rounded(.down)))
        let imageCenterX = Double(width) / 2
        let imageCenterY = Double(height) / 2
        var best: Int?
        var bestDistSq = Double.greatestFiniteMagnitude
        for i in 0..<compCount.count where compCount[i] >= minCount {
            let n = Double(compCount[i])
            let mx = compSumX[i] / n
            let my = compSumY[i] / n
            let dx = mx - imageCenterX
            let dy = my - imageCenterY
            let distSq = dx * dx + dy * dy
            if distSq < bestDistSq {
                bestDistSq = distSq
                best = i
            }
        }
        guard let chosen = best else { return nil } // 无有效绿块 → 回退

        let n = Double(compCount[chosen])
        let meanX = compSumX[chosen] / n
        let meanY = compSumY[chosen] / n

        // MARK: 3. PCA 主轴（2×2 协方差的主特征向量）
        let cxx = compSumXX[chosen] / n - meanX * meanX
        let cyy = compSumYY[chosen] / n - meanY * meanY
        let cxy = compSumXY[chosen] / n - meanX * meanY
        // 对称 2×2 矩阵主特征向量的闭式解（atan2 形式，自动处理 cxx/cyy 大小关系）
        let theta = 0.5 * atan2(2 * cxy, cxx - cyy)
        let vx = cos(theta)
        let vy = sin(theta)
        // 图像 y 向下=南：地图坐标中的主轴方向为 (vx, -vy)，
        // TrackRoutePlanner 的 0° = 直道东西向，故 rotation = 主轴与正东的夹角
        var rotation = atan2(-vy, vx) * 180 / .pi
        rotation = rotation.truncatingRemainder(dividingBy: 180)
        if rotation < 0 { rotation += 180 } // 椭圆无方向性，归一化到 [0, 180)

        // MARK: 4. 尺寸估计：块内像素投影到主轴/副轴（地图米制），取投影范围长度
        // 主轴地图方向 u = (vx, -vy)，副轴方向 w = (vy, vx)（u 逆时针转 90°）
        var minMajor = Double.greatestFiniteMagnitude
        var maxMajor = -Double.greatestFiniteMagnitude
        var minMinor = Double.greatestFiniteMagnitude
        var maxMinor = -Double.greatestFiniteMagnitude
        let chosenLabel = Int32(chosen + 1)
        for idx in 0..<totalPixels where labels[idx] == chosenLabel {
            let cr = idx / width
            let cc = idx - cr * width
            // 相对质心的米制坐标（投影范围与基准无关，用质心数值更稳）
            let east = (Double(cc) - meanX) * mppX
            let north = -(Double(cr) - meanY) * mppY
            let pMajor = east * vx + north * (-vy)
            let pMinor = east * vy + north * vx
            minMajor = min(minMajor, pMajor); maxMajor = max(maxMajor, pMajor)
            minMinor = min(minMinor, pMinor); maxMinor = max(maxMinor, pMinor)
        }
        let lengthMajor = maxMajor - minMajor
        let lengthMinor = maxMinor - minMinor

        // 与标准 400m 场全幅（157.39 × 73m）比较，长短轴各算一个缩放取平均
        let rawScale = ((lengthMajor / standardFullMajorMeters) + (lengthMinor / standardFullMinorMeters)) / 2
        let scale = min(max(rawScale, scaleRange.lowerBound), scaleRange.upperBound)
        let rawPerimeter = scale * TrackRoutePlanner.standardPerimeterMeters
        // 吸附到最近档位（200 / 300 / 400），与微调面板预设保持一致
        let perimeter = perimeterSnaps.min(by: {
            abs($0 - rawPerimeter) < abs($1 - rawPerimeter)
        }) ?? 400

        // MARK: 5. 中心修正：块质心相对图像中心的像素偏移 → 米制偏移
        let centerOffsetEast = (meanX - imageCenterX) * mppX
        let centerOffsetNorth = -(meanY - imageCenterY) * mppY

        return TrackShapeEstimate(
            rotationDegrees: rotation,
            perimeterMeters: perimeter,
            centerOffsetEastMeters: centerOffsetEast,
            centerOffsetNorthMeters: centerOffsetNorth,
            maskPixelCount: compCount[chosen]
        )
    }
}
