import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject var viewModel: MainViewModel

    @State private var showSettings = false
    @State private var showSaved = false
    @State private var showDiagnostic = false
    @State private var speedSlider: Float = 8.5

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.isInjectionConnecting || viewModel.isInjectionStopping {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(viewModel.isInjectionConnecting ? "正在建立手机独立注入链路…" : "正在清除系统定位…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Main action buttons
            mainActions

            // Speed slider (visible during running)
            if viewModel.simulationState == .running || viewModel.simulationState == .paused {
                speedControl
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Bottom toolbar
            bottomToolbar
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .animation(.easeInOut(duration: 0.3), value: viewModel.simulationState)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showSaved) {
            SavedRoutesView()
        }
        .sheet(isPresented: $showDiagnostic) {
            DiagnosticView()
        }
        .onAppear {
            // 无接触真机验证：devicectl launch 带 -autoDiagnostic 时自动打开诊断
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-autoDiagnostic") || args.contains("-verifyLocation")
                || ProcessInfo.processInfo.environment["AUTO_DIAGNOSTIC"] == "1" {
                showDiagnostic = true
            }
        }
    }

    @ViewBuilder
    private var mainActions: some View {
        HStack(spacing: 12) {
            // Start route
            actionButton(
                title: "路线模拟",
                icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                color: .blue
            ) {
                viewModel.startRouteSimulation()
            }
            .disabled(viewModel.markers.count < 2 || viewModel.simulationControlsLocked)

            // Start fixed point
            actionButton(
                title: "固定点",
                icon: "mappin.circle.fill",
                color: .orange
            ) {
                viewModel.startFixedSimulation()
            }
            .disabled(viewModel.markers.isEmpty || viewModel.simulationControlsLocked)

            // Track running: manual aiming (primary) or POI-assisted detection
            Menu {
                Button {
                    viewModel.beginTrackAiming()
                } label: {
                    Label("对准地图中心生成跑道", systemImage: "plus.viewfinder")
                }
                Button {
                    viewModel.detectNearbyTrack()
                } label: {
                    Label("自动搜索附近操场跑道", systemImage: "location.magnifyingglass")
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.title3)
                    Text("跑道")
                        .font(.system(size: 10))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.green.opacity(0.12))
                .foregroundColor(.green)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.simulationControlsLocked)

            // Pause / Resume
            if viewModel.simulationState == .running {
                actionButton(title: "暂停", icon: "pause.circle.fill", color: .orange) {
                    viewModel.pauseSimulation()
                }
            } else if viewModel.simulationState == .paused {
                actionButton(title: "继续", icon: "play.circle.fill", color: .green) {
                    viewModel.resumeSimulation()
                }
            }

            // Stop
            if viewModel.simulationState == .running || viewModel.simulationState == .paused {
                actionButton(title: "停止", icon: "stop.circle.fill", color: .red) {
                    viewModel.stopSimulation()
                }
            }
        }
    }

    private var speedControl: some View {
        VStack(spacing: 8) {
            HStack {
                Text("速度")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.1f km/h", viewModel.speedKmh))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            Slider(value: Binding(
                get: { viewModel.speedKmh },
                set: { viewModel.updateSpeed($0) }
            ), in: 6...12, step: 0.1) {
                Text("速度")
            }
            .tint(.blue)
        }
        .padding(.vertical, 4)
    }

    private var bottomToolbar: some View {
        HStack(spacing: 24) {
            toolbarButton(icon: "gearshape.fill", label: "设置") {
                showSettings = true
            }
            toolbarButton(icon: "folder.fill", label: "保存") {
                showSaved = true
            }
            toolbarButton(icon: "arrow.uturn.backward", label: "撤销") {
                viewModel.undoLastMarker()
            }
            .disabled(viewModel.markers.isEmpty)
            toolbarButton(icon: "trash.fill", label: "清空") {
                viewModel.clearMarkers()
            }
            .disabled(viewModel.markers.isEmpty)
            toolbarButton(icon: "square.and.arrow.up.fill", label: "GPX") {
                viewModel.exportGPX()
            }
            toolbarButton(icon: "stethoscope", label: "诊断") {
                showDiagnostic = true
            }
        }
    }

    private func actionButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func toolbarButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 10))
            }
        }
        .foregroundColor(.secondary)
    }
}
