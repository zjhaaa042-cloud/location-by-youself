import SwiftUI

/// Milestone 1 诊断界面：纯手机端独立注入
/// （NE 回环隧道 + RPPairing 握手 / pair-verify / SRP 配对）。
struct DiagnosticView: View {
    @StateObject private var manager = RemoteInjectionManager()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                statusCard
                logList
            }
            .padding(16)
            .navigationTitle("独立注入诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                // 无接触真机验证：启动参数或环境变量触发自动开始诊断
                if ProcessInfo.processInfo.arguments.contains("-autoDiagnostic")
                    || ProcessInfo.processInfo.environment["AUTO_DIAGNOSTIC"] == "1" {
                    manager.startDiagnostic()
                } else if ProcessInfo.processInfo.arguments.contains("-verifyLocation") {
                    manager.runLocationVerificationOnly()
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("M2 · 纯手机端定位注入")
                        .font(.headline)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Picker("回环来源", selection: $manager.loopbackMode) {
                ForEach(RemoteInjectionManager.LoopbackMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(manager.phase.isRunning)

            if manager.loopbackMode == .directLoopback {
                Text("请先在 LocalDevVPN 中开启回环隧道，再开始诊断。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    manager.startDiagnostic()
                } label: {
                    Label("开始诊断", systemImage: "stethoscope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.phase.isRunning)

                if manager.m2LocationInjected {
                    Button(role: .destructive) {
                        manager.clearInjectedLocation()
                    } label: {
                        Label("清除定位", systemImage: "location.slash")
                    }
                    .buttonStyle(.bordered)
                }

                if manager.phase.isRunning {
                    ProgressView()
                }
            }
        }
        .cardStyle()
    }

    private var logList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("运行日志")
                .font(.headline)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(manager.logs) { line in
                            Text("\(line.time)  \(line.text)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .background(AppTheme.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onChange(of: manager.logs.count) { _, _ in
                    if let last = manager.logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var statusIcon: String {
        switch manager.phase {
        case .idle: return "circle.dashed"
        case .installingTunnel, .startingTunnel, .handshaking: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        switch manager.phase {
        case .idle: return .secondary
        case .installingTunnel, .startingTunnel, .handshaking: return AppTheme.accent
        case .succeeded: return AppTheme.success
        case .failed: return AppTheme.danger
        }
    }

    private var statusText: String {
        switch manager.phase {
        case .idle: return "尚未运行。请在真机上执行；模拟器不支持 NE 隧道。"
        case .installingTunnel: return "正在安装/启用回环隧道配置…"
        case .startingTunnel: return "正在启动隧道扩展…"
        case .handshaking: return "正在与 remotepairingd 握手…"
        case .succeeded(let summary): return summary
        case .failed(let reason): return reason
        }
    }
}
