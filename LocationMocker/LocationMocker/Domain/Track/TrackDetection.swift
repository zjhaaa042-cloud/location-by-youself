import Foundation

struct TrackCandidate {
    let name: String
    let center: RoutePoint
    let typeDescription: String
    let distanceMeters: Double

    init(name: String, center: RoutePoint, typeDescription: String = "", distanceMeters: Double = 0) {
        self.name = name
        self.center = center
        self.typeDescription = typeDescription
        self.distanceMeters = distanceMeters
    }
}

enum TrackDetectionResult {
    case success(name: String, center: RoutePoint, confidence: Int, sourceBounds: [RoutePoint])
    case notFound(reason: String)
}

enum TrackCandidateScorer {
    private static let strongKeywords = ["操场", "田径场", "运动场", "跑道"]
    private static let weakKeywords = ["体育场", "体育中心", "运动中心", "足球场"]

    static func bestCandidate(origin: RoutePoint, candidates: [TrackCandidate]) -> TrackDetectionResult {
        let scored = candidates.compactMap { candidate -> (TrackCandidate, Int)? in
            let s = score(origin: origin, candidate: candidate)
            return s >= 55 ? (candidate, s) : nil
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }) else {
            return .notFound(reason: "附近未识别到操场")
        }
        let name = best.0.name.isEmpty ? "附近操场" : best.0.name
        return .success(name: name, center: origin, confidence: best.1, sourceBounds: [])
    }

    static func score(origin: RoutePoint, candidate: TrackCandidate) -> Int {
        let text = "\(candidate.name) \(candidate.typeDescription)"
        let keywordScore: Int
        if strongKeywords.contains(where: text.contains) {
            keywordScore = 70
        } else if weakKeywords.contains(where: text.contains) {
            keywordScore = 45
        } else {
            return 0
        }
        let distance = candidate.distanceMeters > 0
            ? candidate.distanceMeters
            : RouteMath.distanceMeters(origin, candidate.center)
        let distanceScore: Int
        if distance <= 80 { distanceScore = 25 }
        else if distance <= 150 { distanceScore = 18 }
        else if distance <= 250 { distanceScore = 10 }
        else { distanceScore = -20 }
        return min(max(keywordScore + distanceScore, 0), 100)
    }
}
