package com.example.locationmocker.domain.geo

import com.example.locationmocker.domain.model.RoutePoint
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

object CoordinateTransform {
    private const val SEMI_MAJOR_AXIS = 6_378_245.0
    private const val ECCENTRICITY_SQUARED = 0.006693421622965943
    private const val INVERSE_SEARCH_DELTA = 0.01
    private const val INVERSE_TOLERANCE = 0.0000001

    fun wgs84ToGcj02(point: RoutePoint): RoutePoint {
        if (point.isOutsideChina()) return point

        val deltaLat = transformLat(point.lon - 105.0, point.lat - 35.0)
        val deltaLon = transformLon(point.lon - 105.0, point.lat - 35.0)
        val radLat = point.lat / 180.0 * PI
        var magic = sin(radLat)
        magic = 1 - ECCENTRICITY_SQUARED * magic * magic
        val sqrtMagic = sqrt(magic)
        val adjustedLat = point.lat + (deltaLat * 180.0) /
            ((SEMI_MAJOR_AXIS * (1 - ECCENTRICITY_SQUARED)) / (magic * sqrtMagic) * PI)
        val adjustedLon = point.lon + (deltaLon * 180.0) /
            (SEMI_MAJOR_AXIS / sqrtMagic * cos(radLat) * PI)

        return point.copy(lat = adjustedLat, lon = adjustedLon)
    }

    fun gcj02ToWgs84(point: RoutePoint): RoutePoint {
        if (point.isOutsideChina()) return point

        var minLat = point.lat - INVERSE_SEARCH_DELTA
        var maxLat = point.lat + INVERSE_SEARCH_DELTA
        var minLon = point.lon - INVERSE_SEARCH_DELTA
        var maxLon = point.lon + INVERSE_SEARCH_DELTA
        var candidate = point

        repeat(30) {
            candidate = point.copy(
                lat = (minLat + maxLat) / 2.0,
                lon = (minLon + maxLon) / 2.0,
            )
            val transformed = wgs84ToGcj02(candidate)
            val latError = transformed.lat - point.lat
            val lonError = transformed.lon - point.lon
            if (abs(latError) < INVERSE_TOLERANCE && abs(lonError) < INVERSE_TOLERANCE) {
                return candidate
            }
            if (latError > 0) {
                maxLat = candidate.lat
            } else {
                minLat = candidate.lat
            }
            if (lonError > 0) {
                maxLon = candidate.lon
            } else {
                minLon = candidate.lon
            }
        }

        return candidate
    }

    private fun RoutePoint.isOutsideChina(): Boolean {
        return lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271
    }

    private fun transformLat(x: Double, y: Double): Double {
        var result = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y +
            0.2 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * PI) + 20.0 * sin(2.0 * x * PI)) * 2.0 / 3.0
        result += (20.0 * sin(y * PI) + 40.0 * sin(y / 3.0 * PI)) * 2.0 / 3.0
        result += (160.0 * sin(y / 12.0 * PI) + 320.0 * sin(y * PI / 30.0)) * 2.0 / 3.0
        return result
    }

    private fun transformLon(x: Double, y: Double): Double {
        var result = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y +
            0.1 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * PI) + 20.0 * sin(2.0 * x * PI)) * 2.0 / 3.0
        result += (20.0 * sin(x * PI) + 40.0 * sin(x / 3.0 * PI)) * 2.0 / 3.0
        result += (150.0 * sin(x / 12.0 * PI) + 300.0 * sin(x / 30.0 * PI)) * 2.0 / 3.0
        return result
    }
}
