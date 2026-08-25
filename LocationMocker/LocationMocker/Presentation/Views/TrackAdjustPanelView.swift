import SwiftUI

/// 跑道微调面板：生成后、开始模拟前调整位置 / 旋转 / 周长，地图预览实时更新
struct TrackAdjustPanelView: View {
    @EnvironmentObject var viewModel: MainViewModel

    private let nudgeStepMeters: Double = 10

    var body: some View {
        VStack(spacing: 12) {
            // 标题行
            HStack {
                Text("微调跑道")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if !viewModel.trackName.isEmpty {
                    Text(viewModel.trackName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                // 保存到跑道收藏库（同名覆盖），之后可随时载入或导出 GPX 分享
                Button {
                    viewModel.saveCurrentTrackToLibrary()
                } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(8)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // 周长预设
            HStack {
                Text("周长")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("周长", selection: Binding(
                    get: { viewModel.trackPerimeterMeters },
                    set: { viewModel.setTrackPerimeter($0) }
                )) {
                    Text("200m").tag(200.0)
                    Text("300m").tag(300.0)
                    Text("400m").tag(400.0)
                }
                .pickerStyle(.segmented)
            }

            // 跑动方向：顺时针 / 逆时针（同一物理起点反向行进）
            HStack {
                Text("方向")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("方向", selection: Binding(
                    get: { viewModel.trackClockwise },
                    set: { viewModel.setTrackClockwise($0) }
                )) {
                    Text("顺时针").tag(true)
                    Text("逆时针").tag(false)
                }
                .pickerStyle(.segmented)
            }

            // 起点调节：回放从跑道上指定弧长位置开始
            HStack {
                Text("起点")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(value: Binding(
                    get: { viewModel.trackStartOffsetMeters },
                    set: { viewModel.setTrackStartOffset($0) }
                ), in: 0...viewModel.trackPerimeterMeters, step: 5) {
                    Text("起点")
                }
                .tint(.green)
                Text("起点：\(Int(viewModel.trackStartOffsetMeters)) m")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(width: 76, alignment: .trailing)
            }

            HStack {
                // 位置微调（方向键，每步 10m）
                VStack(spacing: 6) {
                    nudgeButton(icon: "arrow.up") {
                        viewModel.nudgeTrack(northMeters: nudgeStepMeters, eastMeters: 0)
                    }
                    HStack(spacing: 6) {
                        nudgeButton(icon: "arrow.left") {
                            viewModel.nudgeTrack(northMeters: 0, eastMeters: -nudgeStepMeters)
                        }
                        Text("10m/步")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 40)
                        nudgeButton(icon: "arrow.right") {
                            viewModel.nudgeTrack(northMeters: 0, eastMeters: nudgeStepMeters)
                        }
                    }
                    nudgeButton(icon: "arrow.down") {
                        viewModel.nudgeTrack(northMeters: -nudgeStepMeters, eastMeters: 0)
                    }
                }

                Spacer()

                // 旋转微调
                VStack(spacing: 6) {
                    Text("旋转 \(Int(viewModel.trackRotationDegrees))°")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    HStack(spacing: 6) {
                        rotateButton("-10°") { viewModel.rotateTrack(byDegrees: -10) }
                        rotateButton("-1°") { viewModel.rotateTrack(byDegrees: -1) }
                    }
                    HStack(spacing: 6) {
                        rotateButton("+1°") { viewModel.rotateTrack(byDegrees: 1) }
                        rotateButton("+10°") { viewModel.rotateTrack(byDegrees: 10) }
                    }
                }
            }

            // 确认 / 取消
            HStack(spacing: 12) {
                Button("取消") {
                    viewModel.cancelTrackSetup()
                }
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.12))
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    viewModel.confirmTrackAndStart()
                } label: {
                    Label("确认并开始", systemImage: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func nudgeButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.12))
                .foregroundColor(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func rotateButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                .foregroundColor(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
