import Foundation
import MapKit

final class TrackDetector {

    struct NearbyPOI {
        let name: String
        let coordinate: CLLocationCoordinate2D
        let typeDescription: String
    }

    /// MKLocalSearch 的自然语言查询不支持 OR 布尔语法，
    /// 因此按关键词分别搜索后合并去重（中英文覆盖，兼容模拟器英文区 POI 数据）
    private let searchKeywords = ["操场", "田径场", "体育场", "运动场", "跑道", "stadium", "sports field"]

    /// 搜索范围（米），与 TrackCandidateScorer 的距离评分档匹配
    private let searchRadiusMeters: Double = 1500

    func findNearbyTracks(
        around coordinate: CLLocationCoordinate2D,
        completion: @escaping (TrackDetectionResult) -> Void
    ) {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: searchRadiusMeters,
            longitudinalMeters: searchRadiusMeters
        )

        let group = DispatchGroup()
        let lock = NSLock()
        var collected: [MKMapItem] = []
        var lastError: Error?
        var searches: [MKLocalSearch] = []
        searches.reserveCapacity(searchKeywords.count)

        for keyword in searchKeywords {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = keyword
            request.region = region
            request.resultTypes = .pointOfInterest

            let search = MKLocalSearch(request: request)
            searches.append(search)
            group.enter()
            search.start { response, error in
                lock.lock()
                if let items = response?.mapItems {
                    collected.append(contentsOf: items)
                }
                if let error {
                    lastError = error
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            // 持有搜索对象直到全部回调完成
            withExtendedLifetime(searches) {}

            let origin = RoutePoint(lat: coordinate.latitude, lon: coordinate.longitude)
            var seen = Set<String>()
            let candidates = collected.compactMap { item -> TrackCandidate? in
                let coord = item.placemark.coordinate
                let key = "\(item.name ?? "")|\(String(format: "%.4f", coord.latitude))|\(String(format: "%.4f", coord.longitude))"
                guard seen.insert(key).inserted else { return nil }
                return TrackCandidate(
                    name: item.name ?? "",
                    center: RoutePoint(lat: coord.latitude, lon: coord.longitude),
                    typeDescription: item.pointOfInterestCategory?.rawValue ?? "",
                    category: item.pointOfInterestCategory?.rawValue ?? "",
                    distanceMeters: coord.distance(from: coordinate)
                )
            }

            let result = TrackCandidateScorer.rankedCandidates(origin: origin, candidates: candidates)
            switch result {
            case .candidates:
                completion(result)
            case .notFound(let reason):
                if candidates.isEmpty {
                    if lastError != nil {
                        // 区分「搜索服务失败」与「附近真的没有」，避免静默误导
                        completion(.notFound(reason: "地图搜索服务暂不可用，请检查网络后重试"))
                    } else {
                        completion(.notFound(reason: "附近未找到操场或运动场"))
                    }
                } else {
                    completion(.notFound(reason: reason))
                }
            }
        }
    }
}

private extension CLLocationCoordinate2D {
    func distance(from other: CLLocationCoordinate2D) -> Double {
        let a = CLLocation(latitude: latitude, longitude: longitude)
        let b = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return a.distance(from: b)
    }
}
