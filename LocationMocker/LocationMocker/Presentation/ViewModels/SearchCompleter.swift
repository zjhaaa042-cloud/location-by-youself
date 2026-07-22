import Foundation
import MapKit
import Combine

/// 地址搜索补全器
/// 封装 MKLocalSearchCompleter，提供实时补全建议，并将选中的建议解析为地图坐标
@MainActor
final class SearchCompleter: NSObject, ObservableObject {

    /// 当前搜索关键字，修改后自动触发实时补全
    @Published var query: String = "" {
        didSet {
            completer.queryFragment = query
            if query.isEmpty {
                results = []
            }
        }
    }

    /// 实时补全结果
    @Published private(set) var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()
    private var activeSearch: MKLocalSearch?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// 让建议结果偏向指定地图区域（附近地点排序靠前）
    func bias(to region: MKCoordinateRegion) {
        completer.region = region
    }

    /// 清空搜索状态（同时收起结果列表）
    func clear() {
        query = ""
        results = []
    }

    /// 解析补全结果为地图坐标
    func resolve(_ completion: MKLocalSearchCompletion,
                 handler: @escaping (CLLocationCoordinate2D?) -> Void) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        activeSearch = search
        search.start { response, error in
            let coordinate = (error == nil) ? response?.mapItems.first?.placemark.coordinate : nil
            DispatchQueue.main.async {
                handler(coordinate)
            }
        }
    }
}

extension SearchCompleter: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.results = completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.results = []
        }
    }
}
