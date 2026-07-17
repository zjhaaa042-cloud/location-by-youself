import SwiftUI

struct SavedRoutesView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var savedGPXFiles: [String] = []

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.markers.isEmpty && savedGPXFiles.isEmpty {
                    ContentUnavailableView(
                        "没有保存的路线",
                        systemImage: "map",
                        description: Text("在地图上点击放置标记点来创建路线")
                    )
                } else {
                    List {
                        if !viewModel.markers.isEmpty {
                            Section("当前路线") {
                                ForEach(Array(viewModel.markers.enumerated()), id: \.offset) { index, point in
                                    HStack {
                                        Text("点 \(index + 1)")
                                            .font(.subheadline)
                                        Spacer()
                                        Text(String(format: "%.6f, %.6f", point.lat, point.lon))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .onDelete { indexSet in
                                    viewModel.markers.remove(atOffsets: indexSet)
                                    viewModel.routePolyline.remove(atOffsets: indexSet)
                                }
                            }
                        }

                        if !savedGPXFiles.isEmpty {
                            Section("已导出的 GPX 文件") {
                                ForEach(savedGPXFiles, id: \.self) { file in
                                    HStack {
                                        Image(systemName: "doc.text.fill")
                                            .foregroundColor(.green)
                                        Text(file)
                                            .font(.subheadline)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("保存的路线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                loadGPXFiles()
            }
        }
    }

    private func loadGPXFiles() {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return }
        savedGPXFiles = (try? FileManager.default.contentsOfDirectory(atPath: docs.path))?
            .filter { $0.hasSuffix(".gpx") } ?? []
    }
}
