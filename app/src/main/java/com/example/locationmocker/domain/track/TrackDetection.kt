package com.example.locationmocker.domain.track

import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.route.RouteMath

data class TrackCandidate(
    val name: String,
    val center: RoutePoint,
    val typeDescription: String = "",
    val distanceMeters: Double = 0.0,
)

sealed interface TrackDetectionResult {
    data class Success(
        val name: String,
        val center: RoutePoint,
        val confidence: Int,
        val sourceBounds: List<RoutePoint> = emptyList(),
    ) : TrackDetectionResult

    data class NotFound(val reason: String) : TrackDetectionResult
}

object TrackCandidateScorer {
    private val strongKeywords = listOf(
        "\u64cd\u573a",
        "\u7530\u5f84\u573a",
        "\u8fd0\u52a8\u573a",
        "\u8dd1\u9053",
    )
    private val weakKeywords = listOf(
        "\u4f53\u80b2\u573a",
        "\u4f53\u80b2\u4e2d\u5fc3",
        "\u8fd0\u52a8\u4e2d\u5fc3",
        "\u8db3\u7403\u573a",
    )

    fun bestCandidate(origin: RoutePoint, candidates: List<TrackCandidate>): TrackDetectionResult {
        val scored = candidates.mapNotNull { candidate ->
            val score = score(origin, candidate)
            if (score >= 55) candidate to score else null
        }.maxByOrNull { it.second }

        return if (scored == null) {
            TrackDetectionResult.NotFound("\u9644\u8fd1\u672a\u8bc6\u522b\u5230\u64cd\u573a")
        } else {
            val candidate = scored.first
            TrackDetectionResult.Success(
                name = candidate.name.ifBlank { "\u9644\u8fd1\u64cd\u573a" },
                center = origin,
                confidence = scored.second,
            )
        }
    }

    fun score(origin: RoutePoint, candidate: TrackCandidate): Int {
        val text = "${candidate.name} ${candidate.typeDescription}"
        val keywordScore = when {
            strongKeywords.any { text.contains(it) } -> 70
            weakKeywords.any { text.contains(it) } -> 45
            else -> 0
        }
        if (keywordScore == 0) return 0

        val distance = candidate.distanceMeters.takeIf { it > 0.0 }
            ?: RouteMath.distanceMeters(origin, candidate.center)
        val distanceScore = when {
            distance <= 80.0 -> 25
            distance <= 150.0 -> 18
            distance <= 250.0 -> 10
            else -> -20
        }
        return (keywordScore + distanceScore).coerceIn(0, 100)
    }

}
