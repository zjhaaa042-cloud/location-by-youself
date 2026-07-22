import SwiftUI
import MapKit

/// 地址搜索栏 + 实时补全结果列表
/// 选中结果后复用 MainViewModel 现有的地图点选数据流
struct SearchBarView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @StateObject private var completer = SearchCompleter()
    @FocusState private var isFocused: Bool

    private let maxVisibleResults = 8

    var body: some View {
        VStack(spacing: 8) {
            searchField

            if !completer.query.isEmpty {
                resultList
            }
        }
        .onAppear {
            completer.bias(to: viewModel.mapRegion)
        }
        .onChange(of: isFocused) { _, focused in
            // 开始搜索时让建议偏向当前地图可见区域
            if focused {
                completer.bias(to: viewModel.mapRegion)
            }
        }
    }

    // MARK: - 搜索框

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundColor(.secondary)

            TextField("搜索地址或地点", text: $completer.query)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit {
                    // 回车直接选中第一条建议
                    if let first = completer.results.first {
                        select(first)
                    }
                }

            if !completer.query.isEmpty {
                Button {
                    completer.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 结果列表

    @ViewBuilder
    private var resultList: some View {
        if completer.results.isEmpty {
            Text("未找到相关地点")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(completer.results.prefix(maxVisibleResults).enumerated()), id: \.offset) { index, completion in
                        Button {
                            select(completion)
                        } label: {
                            resultRow(completion)
                        }

                        if index < min(completer.results.count, maxVisibleResults) - 1 {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func resultRow(_ completion: MKLocalSearchCompletion) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(completion.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
            if !completion.subtitle.isEmpty {
                Text(completion.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - 选中结果

    private func select(_ completion: MKLocalSearchCompletion) {
        isFocused = false   // 收起键盘
        completer.clear()   // 收起结果列表
        completer.resolve(completion) { coordinate in
            guard let coordinate else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                viewModel.locateSearchedPlace(at: coordinate)
            }
        }
    }
}
