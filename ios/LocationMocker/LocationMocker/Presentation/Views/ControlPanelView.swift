import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject var viewModel: MainViewModel

    @State private var showSettings = false
    @State private var showSaved = false
    @State private var speedSlider: Float = 8.5

    var body: some View {
        VStack(spacing: 12) {
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
            .disabled(viewModel.markers.count < 2)

            // Start fixed point
            actionButton(
                title: "固定点",
                icon: "mappin.circle.fill",
                color: .orange
            ) {
                viewModel.startFixedSimulation()
            }
            .disabled(viewModel.markers.isEmpty)

            // Track running
            actionButton(
                title: "跑道",
                icon: "figure.run.circle.fill",
                color: .green
            ) {
                viewModel.detectNearbyTrack()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    viewModel.startTrackSimulation()
                }
            }

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
