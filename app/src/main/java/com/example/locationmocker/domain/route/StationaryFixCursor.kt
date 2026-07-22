package com.example.locationmocker.domain.route

import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.model.RouteSample
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * Produces fresh, sub-meter fixes around a fixed target.
 *
 * Some fused-location consumers de-duplicate a stream whose coordinates, speed and bearing are
 * all identical. Keeping each fix distinct prevents a real cached fix from winning while the
 * reported position remains inside the normal horizontal-accuracy radius of the selected point.
 */
class StationaryFixCursor(
    private val target: RoutePoint,
) {
    private var index = 0

    fun next(): RouteSample {
        val angle = 2.0 * PI * index / SAMPLE_COUNT
        val nextAngle = 2.0 * PI * ((index + 1) % SAMPLE_COUNT) / SAMPLE_COUNT
        val point = target.offsetMeters(
            northMeters = STABILITY_RADIUS_METERS * sin(angle),
            eastMeters = STABILITY_RADIUS_METERS * cos(angle),
        )
        val nextPoint = target.offsetMeters(
            northMeters = STABILITY_RADIUS_METERS * sin(nextAngle),
            eastMeters = STABILITY_RADIUS_METERS * cos(nextAngle),
        )
        index = (index + 1) % SAMPLE_COUNT
        return RouteSample(
            point = point,
            speedMetersPerSecond = STATIONARY_SPEED_METERS_PER_SECOND,
            bearingDegrees = RouteMath.bearingDegrees(point, nextPoint),
        )
    }

    private fun RoutePoint.offsetMeters(northMeters: Double, eastMeters: Double): RoutePoint {
        val metersPerDegreeLongitude = (
            METERS_PER_DEGREE * cos(lat * PI / 180.0)
            ).coerceAtLeast(MIN_METERS_PER_DEGREE_LONGITUDE)
        return copy(
            lat = lat + northMeters / METERS_PER_DEGREE,
            lon = lon + eastMeters / metersPerDegreeLongitude,
        )
    }

    private companion object {
        private const val SAMPLE_COUNT = 8
        private const val STABILITY_RADIUS_METERS = 0.75
        private const val STATIONARY_SPEED_METERS_PER_SECOND = 0.1f
        private const val METERS_PER_DEGREE = 111_320.0
        private const val MIN_METERS_PER_DEGREE_LONGITUDE = 1.0
    }
}
