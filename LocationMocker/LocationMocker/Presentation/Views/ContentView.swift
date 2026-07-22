import SwiftUI
import MapKit

struct ContentView: View {
    @EnvironmentObject var viewModel: MainViewModel

    var body: some View {
        ZStack {
            MapView()
                .ignoresSafeArea()

            VStack {
                // Top status bar
                statusBar
                    .padding(.top, 48)
                    .padding(.horizontal)

                // Address search
                SearchBarView()
                    .padding(.horizontal)

                Spacer()

                // Track candidate picker (multiple POI candidates)
                if !viewModel.trackCandidates.isEmpty {
                    TrackCandidatePickerView()
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                // Track aiming hint
                if viewModel.trackSetupMode == .aiming {
                    aimingBar
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                // Bottom: adjust panel while fine-tuning, otherwise control panel
                Group {
                    if viewModel.trackSetupMode == .adjusting {
                        TrackAdjustPanelView()
                    } else {
                        ControlPanelView()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }

            // Crosshair for manual track aiming (hidden once track is generated)
            if viewModel.trackSetupMode == .aiming {
                Image(systemName: "plus.viewfinder")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.orange)
                    .shadow(color: .white.opacity(0.8), radius: 1)
                    .allowsHitTesting(false)
            }
        }
        .alert("提示", isPresented: Binding(
            get: { viewModel.alertMessage != nil },
            set: { if !$0 { viewModel.alertMessage = nil } }
        )) {
            Button("确定") { viewModel.alertMessage = nil }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .sheet(isPresented: $viewModel.showGPXShare) {
            if let url = viewModel.gpxFileURL {
                ShareSheet(items: [url])
            }
        }
    }

    /// 对准模式提示条：引导用户平移地图对准操场，确认后生成跑道
    private var aimingBar: some View {
        VStack(spacing: 8) {
            Text("平移地图，将准星对准操场中心后点确认（可双指缩放地图）")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                Button("取消") {
                    viewModel.cancelTrackSetup()
                }
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.12))
                .foregroundColor(.primary)
                .clipShape(Capsule())

                Button {
                    viewModel.generateTrackAtMapCenter()
                } label: {
                    if viewModel.isAnalyzingTrackShape {
                        // 快照 + 色值分析中：显示进度并禁用，防止重复点击
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在识别跑道…")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                    } else {
                        Label("在此生成跑道", systemImage: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
                .disabled(viewModel.isAnalyzingTrackShape)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var statusBar: some View {
        HStack {
            statusChip
            if viewModel.isKeepAliveActive {
                keepAliveChip
            }
            if viewModel.isInjectionConnecting {
                injectionChip(text: "连接注入", color: .blue, icon: "link")
            } else if viewModel.isInjectionStopping {
                injectionChip(text: "清除中", color: .orange, icon: "location.slash")
            } else if viewModel.isRemoteInjectionActive {
                injectionChip(text: "系统注入", color: .purple, icon: "location.fill")
            }
            if viewModel.isJailbroken && viewModel.isTweakMode {
                tweakChip
            }
            Spacer()
            markerCountChip
        }
    }

    private func injectionChip(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .clipShape(Capsule())
    }

    /// 后台保活指示：模拟运行中显示，提示锁屏/切后台后模拟仍会继续
    private var keepAliveChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 10))
            Text("后台保活")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.15))
        .foregroundColor(.green)
        .clipShape(Capsule())
    }

    private var tweakChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 10))
            Text("全局注入")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.purple.opacity(0.15))
        .foregroundColor(.purple)
        .clipShape(Capsule())
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var markerCountChip: some View {
        Text("标记点: \(viewModel.markers.count)")
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch viewModel.simulationState {
        case .idle:     return .gray
        case .ready:    return .blue
        case .running:  return .green
        case .paused:   return .orange
        case .error:    return .red
        }
    }

    private var statusText: String {
        switch viewModel.simulationState {
        case .idle:     return "空闲"
        case .ready:    return "就绪"
        case .running:  return "运行中"
        case .paused:   return "已暂停"
        case .error(let msg): return "错误: \(msg)"
        }
    }
}
