import Foundation
import MapKit

final class TrackDetector {

    struct NearbyPOI {
        let name: String
        let coordinate: CLLocationCoordinate2D
        let typeDescription: String
    }

    func findNearbyTracks(
        around coordinate: CLLocationCoordinate2D,
        completion: @escaping (TrackDetectionResult) -> Void
    ) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "操场 OR 田径场 OR 跑道 OR 运动场"
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )

        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let items = response?.mapItems, !items.isEmpty else {
                completion(.notFound(reason: "附近未找到操场或运动场"))
                return
            }

            let origin = RoutePoint(lat: coordinate.latitude, lon: coordinate.longitude)
            let candidates = items.map { item in
                TrackCandidate(
                    name: item.name ?? "",
                    center: RoutePoint(
                        lat: item.placemark.coordinate.latitude,
                        lon: item.placemark.coordinate.longitude
                    ),
                    typeDescription: item.placemark.pointOfInterestCategory?.rawValue ?? "",
                    distanceMeters: item.placemark.coordinate.distance(from: coordinate)
                )
            }
            let result = TrackCandidateScorer.bestCandidate(origin: origin, candidates: candidates)

            DispatchQueue.main.async {
                completion(result)
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
