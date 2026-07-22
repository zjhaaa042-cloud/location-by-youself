import SwiftUI

/// 跑道候选选择列表：自动检测到多个候选操场时弹出，用户选定后进入微调
struct TrackCandidatePickerView: View {
    @EnvironmentObject var viewModel: MainViewModel

    var body: some View {
        VStack(spacing: 12) {
            // 标题行
            HStack {
                Text("选择操场")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("找到 \(viewModel.trackCandidates.count) 个候选")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 候选列表：名称 + 距离 + 可信度
            VStack(spacing: 8) {
                ForEach(Array(viewModel.trackCandidates.enumerated()), id: \.offset) { _, scored in
                    Button {
                        viewModel.selectTrackCandidate(scored)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "figure.run")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.green)
                                .frame(width: 28, height: 28)
                                .background(Color.green.opacity(0.12))
                                .clipShape(Circle())

                            Text(scored.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Spacer()

                            Text("约 \(Int(scored.distanceMeters))m")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)

                            Text(scored.confidenceLabel)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(scored.score >= 80 ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                .foregroundColor(scored.score >= 80 ? .green : .orange)
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            // 取消
            Button("取消") {
                viewModel.dismissTrackCandidates()
            }
            .font(.system(size: 14, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.12))
            .foregroundColor(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
