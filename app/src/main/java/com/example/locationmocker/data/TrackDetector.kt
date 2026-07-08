package com.example.locationmocker.data

import android.content.Context
import com.amap.api.services.core.AMapException
import com.amap.api.services.core.LatLonPoint
import com.amap.api.services.core.PoiItem
import com.amap.api.services.poisearch.PoiResult
import com.amap.api.services.poisearch.PoiSearch
import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.route.RouteMath
import com.example.locationmocker.domain.track.TrackCandidate
import com.example.locationmocker.domain.track.TrackCandidateScorer
import com.example.locationmocker.domain.track.TrackDetectionResult
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

class TrackDetector(private val context: Context) {
    private val keywords = listOf(
        "\u64cd\u573a",
        "\u8fd0\u52a8\u573a",
        "\u7530\u5f84\u573a",
        "\u8dd1\u9053",
        "\u4f53\u80b2\u573a",
    )

    suspend fun detectAround(origin: RoutePoint): TrackDetectionResult {
        val candidates = keywords.flatMap { keyword ->
            searchKeyword(origin, keyword)
        }.distinctBy { "${it.name}-${"%.6f".format(it.center.lat)}-${"%.6f".format(it.center.lon)}" }

        return TrackCandidateScorer.bestCandidate(origin, candidates)
    }

    private suspend fun searchKeyword(origin: RoutePoint, keyword: String): List<TrackCandidate> =
        suspendCancellableCoroutine { continuation ->
            val query = PoiSearch.Query(keyword, "", "").apply {
                pageSize = 12
                pageNum = 0
            }
            val search = PoiSearch(context, query).apply {
                bound = PoiSearch.SearchBound(
                    LatLonPoint(origin.lat, origin.lon),
                    SEARCH_RADIUS_METERS,
                )
            }
            search.setOnPoiSearchListener(object : PoiSearch.OnPoiSearchListener {
                override fun onPoiSearched(result: PoiResult?, code: Int) {
                    if (!continuation.isActive) return
                    val candidates = if (code == AMapException.CODE_AMAP_SUCCESS) {
                        result?.pois.orEmpty().mapNotNull { it.toTrackCandidate(origin) }
                    } else {
                        emptyList()
                    }
                    continuation.resume(candidates)
                }

                override fun onPoiItemSearched(item: PoiItem?, code: Int) = Unit
            })
            continuation.invokeOnCancellation {
                search.setOnPoiSearchListener(null)
            }
            search.searchPOIAsyn()
        }

    private fun PoiItem.toTrackCandidate(origin: RoutePoint): TrackCandidate? {
        val point = latLonPoint ?: return null
        val center = RoutePoint(lat = point.latitude, lon = point.longitude)
        val distance = distance.takeIf { it > 0 }?.toDouble()
            ?: RouteMath.distanceMeters(origin, center)
        return TrackCandidate(
            name = title.orEmpty(),
            center = center,
            typeDescription = typeDes.orEmpty(),
            distanceMeters = distance,
        )
    }

    private companion object {
        const val SEARCH_RADIUS_METERS = 250
    }
}
