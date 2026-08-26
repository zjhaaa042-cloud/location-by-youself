import SwiftUI
import MapKit

struct ContentView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVPNInstalled = true
    @State private var signatureDaysRemaining: Int?

    var body: some View {
        ZStack {
            MapView()
                .ignoresSafeArea()

            VStack {
                // Top status bar（VStack 默认尊重安全区，小屏机型也不会顶到状态栏）
                statusBar
                    .padding(.top, 8)
                    .padding(.horizontal)

                // Address search
                SearchBarView()
                    .padding(.horizontal)

                // LocalDevVPN 未安装时引导跳转 App Store（注入依赖其回环隧道）
                if !isVPNInstalled {
                    vpnInstallBanner
                        .padding(.horizontal)
                }

                // 免费签名 7 天到期：剩余 ≤2 天时醒目提醒重装
                if let days = signatureDaysRemaining, days <= 2 {
                    signatureExpiryBanner(days: days)
                        .padding(.horizontal)
                }

                // 地图操作按钮：放在布局流里（搜索栏下方），而不是悬浮 overlay，
                // 保证任何屏幕尺寸都不会与状态栏/搜索栏/引导条互相遮挡
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        mapTypeMenu
                        locateButton
                    }
                }
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
        .onAppear {
            isVPNInstalled = LocalDevVPNGuide.isInstalled
            signatureDaysRemaining = SignatureExpiry.daysRemaining
        }
        .onChange(of: scenePhase) { _, phase in
            // 从 App Store 装完回到 App 时刷新，引导条自动消失
            if phase == .active { isVPNInstalled = LocalDevVPNGuide.isInstalled }
        }
    }

    /// 签名到期提醒横幅：免费 Personal Team 描述文件 7 天到期，需连电脑重装
    private func signatureExpiryBanner(days: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark.fill")
                .font(.system(size: 20))
                .foregroundColor(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(days <= 0 ? "签名今天到期" : "签名 \(days) 天后到期")
                    .font(.system(size: 13, weight: .semibold))
                Text("到期后 App 将无法打开，请尽快连接电脑重新安装一次")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// LocalDevVPN 未安装引导条：一键跳转 App Store 安装页
    private var vpnInstallBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 20))
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("未安装 LocalDevVPN")
                    .font(.system(size: 13, weight: .semibold))
                Text("系统定位注入依赖它提供回环隧道")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("去安装") {
                LocalDevVPNGuide.openAppStore()
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.orange.opacity(0.15))
            .foregroundColor(.orange)
            .clipShape(Capsule())
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// 地图样式切换（标准 / 卫星）
    private var mapTypeMenu: some View {
        Menu {
            Button("标准地图") { viewModel.mapIsSatellite = false }
            Button("卫星地图") { viewModel.mapIsSatellite = true }
        } label: {
            Image(systemName: "map.fill")
                .font(.title3)
                .frame(width: 22, height: 22)
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }

    /// 定位按钮：按下把地图镜头移动到当前（系统）位置
    private var locateButton: some View {
        Button {
            viewModel.locateToCurrentPosition()
        } label: {
            Group {
                if viewModel.isLocating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "location.fill")
                        .font(.title3)
                }
            }
            .frame(width: 22, height: 22)
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
        }
        .disabled(viewModel.isLocating)
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
