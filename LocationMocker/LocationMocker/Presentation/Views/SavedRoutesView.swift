import SwiftUI

struct SavedRoutesView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var savedGPXFiles: [String] = []
    @State private var trackShareURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.markers.isEmpty && savedGPXFiles.isEmpty
                    && viewModel.savedTracksRepo.tracks.isEmpty {
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

                        if !viewModel.savedTracksRepo.tracks.isEmpty {
                            Section("已保存的跑道") {
                                ForEach(viewModel.savedTracksRepo.tracks) { track in
                                    HStack {
                                        Image(systemName: "figure.run")
                                            .foregroundColor(.orange)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(track.name)
                                                .font(.subheadline)
                                            Text("\(Int(track.perimeterMeters))m · \(String(format: "%.5f, %.5f", track.center.lat, track.center.lon))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Button {
                                            shareTrack(track)
                                        } label: {
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.subheadline)
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.loadSavedTrack(track)
                                        dismiss()
                                    }
                                }
                                .onDelete { indexSet in
                                    viewModel.savedTracksRepo.delete(atOffsets: indexSet)
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
            .sheet(isPresented: Binding(
                get: { trackShareURL != nil },
                set: { if !$0 { trackShareURL = nil } }
            )) {
                if let url = trackShareURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private func shareTrack(_ track: SavedTrack) {
        trackShareURL = viewModel.exportTrackGPX(track)
        if trackShareURL == nil {
            viewModel.alertMessage = "跑道「\(track.name)」导出失败"
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
