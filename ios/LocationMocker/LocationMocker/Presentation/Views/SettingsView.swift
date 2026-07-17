import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("模拟参数") {
                    HStack {
                        Text("速度 (km/h)")
                        Spacer()
                        TextField("速度", value: $viewModel.speedKmh, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Picker("播放模式", selection: $viewModel.playbackMode) {
                        Text("单次").tag(PlaybackMode.once)
                        Text("循环").tag(PlaybackMode.loop)
                        Text("往返").tag(PlaybackMode.pingPong)
                    }

                    Picker("路线模式", selection: $viewModel.routeProfile) {
                        Text("手动匀速").tag(RouteProfile.manual)
                        Text("自然跑步").tag(RouteProfile.trackRunning)
                    }
                }

                Section("跑道设置") {
                    Picker("跑道朝向", selection: $viewModel.trackOrientation) {
                        Text("竖直").tag(TrackOrientation.vertical)
                        Text("水平").tag(TrackOrientation.horizontal)
                    }

                    if !viewModel.trackName.isEmpty {
                        HStack {
                            Text("当前跑道")
                            Spacer()
                            Text(viewModel.trackName)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("越狱插件") {
                    if viewModel.isJailbroken {
                        Toggle("全局位置注入", isOn: $viewModel.isTweakMode)
                        Text("启用后，模拟位置将注入到系统 CoreLocation 服务，所有 App 都会收到模拟定位")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.orange)
                            Text("设备未越狱，全局注入不可用")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("坐标系统") {
                    HStack {
                        Text("坐标系")
                        Spacer()
                        Text("WGS-84 / GCJ-02 自动转换")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0 (iOS)")
                            .foregroundColor(.secondary)
                    }
                    Text("iOS 位置模拟开发工具\n普通模式: 地图可视化 + GPX 导出\n越狱模式: 全局 CoreLocation 注入")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        viewModel.saveSettings()
                        dismiss()
                    }
                }
            }
        }
    }
}
