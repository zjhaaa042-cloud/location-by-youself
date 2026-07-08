package com.example.locationmocker.domain.track

import com.example.locationmocker.domain.model.RoutePoint
import org.junit.Assert.assertTrue
import org.junit.Test

class TrackCandidateScorerTest {
    @Test
    fun bestCandidate_prefersStrongKeywordNearbyCandidate() {
        val origin = RoutePoint(31.2304, 121.4737)
        val result = TrackCandidateScorer.bestCandidate(
            origin,
            listOf(
                TrackCandidate("\u5496\u5561\u5e97", RoutePoint(31.2305, 121.4738), "\u9910\u996e", 20.0),
                TrackCandidate("\u7b2c\u4e00\u4e2d\u5b66\u64cd\u573a", RoutePoint(31.2306, 121.4739), "\u8fd0\u52a8\u573a", 30.0),
            ),
        )

        assertTrue(result is TrackDetectionResult.Success)
        assertTrue((result as TrackDetectionResult.Success).confidence >= 80)
        assertTrue(result.center == origin)
    }

    @Test
    fun bestCandidate_returnsNotFoundWithoutTrackKeywords() {
        val origin = RoutePoint(31.2304, 121.4737)
        val result = TrackCandidateScorer.bestCandidate(
            origin,
            listOf(
                TrackCandidate("\u6559\u5b66\u697c", RoutePoint(31.2305, 121.4738), "\u79d1\u6559\u6587\u5316", 20.0),
            ),
        )

        assertTrue(result is TrackDetectionResult.NotFound)
    }
}
