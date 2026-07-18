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

                Spacer()

                // Bottom control panel
                ControlPanelView()
                    .padding(.horizontal)
                    .padding(.bottom, 24)
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

    @ViewBuilder
    private var statusBar: some View {
        HStack {
            statusChip
            if viewModel.isJailbroken && viewModel.isTweakMode {
                tweakChip
            }
            Spacer()
            markerCountChip
        }
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
