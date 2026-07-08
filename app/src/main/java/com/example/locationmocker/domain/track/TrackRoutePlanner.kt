package com.example.locationmocker.domain.track

import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.route.RouteMath
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.roundToInt

class TrackRoutePlanner {
    fun buildCounterClockwiseRoute(
        center: RoutePoint,
        sourceBounds: List<RoutePoint> = emptyList(),
        orientation: TrackOrientation = TrackOrientation.Vertical,
        sampleCount: Int = 360,
        rotationDegrees: Double? = null,
        outerWidthMeters: Double? = null,
        outerHeightMeters: Double? = null,
    ): List<RoutePoint> {
        if (sourceBounds.size >= 6) {
            return normalizeClosedRoute(sourceBounds)
        }

        return if (outerWidthMeters != null && outerHeightMeters != null) {
            buildFitted400MeterTrack(center, orientation, sampleCount, outerWidthMeters, outerHeightMeters, rotationDegrees)
        } else {
            buildStandard400MeterTrack(center, orientation, sampleCount, rotationDegrees)
        }
    }

    private fun buildStandard400MeterTrack(
        center: RoutePoint,
        orientation: TrackOrientation,
        sampleCount: Int,
        rotationDegrees: Double? = null,
    ): List<RoutePoint> {
        val projection = LocalProjection(center)
        val points = buildOrientedStadium(sampleCount, orientation, rotationDegrees)
        val route = points.map(projection::unproject)
        return route + route.first()
    }

    private fun buildFitted400MeterTrack(
        center: RoutePoint,
        orientation: TrackOrientation,
        sampleCount: Int,
        outerWidthMeters: Double,
        outerHeightMeters: Double,
        rotationDegrees: Double? = null,
    ): List<RoutePoint> {
        val shortOuter = minOf(outerWidthMeters, outerHeightMeters)
        val longOuter = maxOf(outerWidthMeters, outerHeightMeters)
        if (shortOuter !in 70.0..140.0 || longOuter !in 130.0..230.0) {
            return buildStandard400MeterTrack(center, orientation, sampleCount, rotationDegrees)
        }

        var centerlineShort = (shortOuter - TRACK_SURFACE_INSET_METERS * 2.0).coerceIn(62.0, 88.0)
        var centerlineLong = (longOuter - TRACK_SURFACE_INSET_METERS * 2.0).coerceIn(145.0, 180.0)
        if (centerlineLong <= centerlineShort + 55.0) {
            centerlineLong = centerlineShort + STRAIGHT_LENGTH_METERS
        }

        val perimeter = 2.0 * (centerlineLong - centerlineShort) + PI * centerlineShort
        val scale = (TRACK_LENGTH_METERS / perimeter).coerceIn(0.88, 1.12)
        centerlineShort *= scale
        centerlineLong *= scale

        val projection = LocalProjection(center)
        val points = buildOrientedStadium(sampleCount, orientation, rotationDegrees, centerlineLong, centerlineShort)
        val route = points.map(projection::unproject)
        return route + route.first()
    }

    private fun buildOrientedStadium(
        sampleCount: Int,
        orientation: TrackOrientation,
        rotationDegrees: Double?,
        centerlineLongMeters: Double = STRAIGHT_LENGTH_METERS + LANE_ONE_RADIUS_METERS * 2.0,
        centerlineShortMeters: Double = LANE_ONE_RADIUS_METERS * 2.0,
    ): List<ProjectedPoint> {
        val base = buildHorizontalStadium(sampleCount, centerlineLongMeters, centerlineShortMeters)
        val angleDegrees = rotationDegrees ?: when (orientation) {
            TrackOrientation.Horizontal -> 0.0
            TrackOrientation.Vertical -> 90.0
        }
        return rotatePoints(base, angleDegrees)
    }

    private fun rotatePoints(points: List<ProjectedPoint>, angleDegrees: Double): List<ProjectedPoint> {
        val radians = angleDegrees * PI / 180.0
        val cosAngle = cos(radians)
        val sinAngle = sin(radians)
        return points.map { point ->
            ProjectedPoint(
                x = point.x * cosAngle - point.y * sinAngle,
                y = point.x * sinAngle + point.y * cosAngle,
            )
        }
    }

    private fun buildHorizontalStadium(
        sampleCount: Int,
        centerlineLongMeters: Double = STRAIGHT_LENGTH_METERS + LANE_ONE_RADIUS_METERS * 2.0,
        centerlineShortMeters: Double = LANE_ONE_RADIUS_METERS * 2.0,
    ): List<ProjectedPoint> {
        val samples = max(120, sampleCount)
        val radiusMeters = centerlineShortMeters / 2.0
        val straightLengthMeters = centerlineLongMeters - centerlineShortMeters
        val trackLengthMeters = straightLengthMeters * 2.0 + 2.0 * PI * radiusMeters
        val straightSamples = (samples * straightLengthMeters / trackLengthMeters).roundToInt().coerceAtLeast(24)
        val curveSamples = ((samples - straightSamples * 2) / 2).coerceAtLeast(36)
        val halfStraight = straightLengthMeters / 2.0
        val result = mutableListOf<ProjectedPoint>()

        for (i in 0 until straightSamples) {
            val t = i.toDouble() / straightSamples
            result += ProjectedPoint(
                x = -halfStraight + straightLengthMeters * t,
                y = -radiusMeters,
            )
        }
        for (i in 0 until curveSamples) {
            val t = i.toDouble() / curveSamples
            val theta = -PI / 2.0 + PI * t
            result += ProjectedPoint(
                x = halfStraight + radiusMeters * cos(theta),
                y = radiusMeters * sin(theta),
            )
        }
        for (i in 0 until straightSamples) {
            val t = i.toDouble() / straightSamples
            result += ProjectedPoint(
                x = halfStraight - straightLengthMeters * t,
                y = radiusMeters,
            )
        }
        for (i in 0 until curveSamples) {
            val t = i.toDouble() / curveSamples
            val theta = PI / 2.0 + PI * t
            result += ProjectedPoint(
                x = -halfStraight + radiusMeters * cos(theta),
                y = radiusMeters * sin(theta),
            )
        }
        return result
    }

    private fun buildVerticalStadium(
        sampleCount: Int,
        centerlineLongMeters: Double = STRAIGHT_LENGTH_METERS + LANE_ONE_RADIUS_METERS * 2.0,
        centerlineShortMeters: Double = LANE_ONE_RADIUS_METERS * 2.0,
    ): List<ProjectedPoint> {
        return buildHorizontalStadium(sampleCount, centerlineLongMeters, centerlineShortMeters).map { point ->
            ProjectedPoint(
                x = -point.y,
                y = point.x,
            )
        }
    }

    private fun normalizeClosedRoute(points: List<RoutePoint>): List<RoutePoint> {
        val closed = if (RouteMath.distanceMeters(points.first(), points.last()) <= 1.0) {
            points
        } else {
            points + points.first()
        }
        return if (signedArea(closed) >= 0.0) closed else closed.reversed()
    }

    private fun signedArea(points: List<RoutePoint>): Double {
        val projection = LocalProjection(points.first())
        val projected = points.map(projection::project)
        return projected.zipWithNext().sumOf { (a, b) -> a.x * b.y - b.x * a.y } / 2.0
    }

    data class ProjectedPoint(val x: Double, val y: Double)

    class LocalProjection(private val origin: RoutePoint) {
        private val metersPerDegreeLat = 111_320.0
        private val metersPerDegreeLon = 111_320.0 * cos(origin.lat * PI / 180.0)

        fun project(point: RoutePoint): ProjectedPoint = ProjectedPoint(
            x = (point.lon - origin.lon) * metersPerDegreeLon,
            y = (point.lat - origin.lat) * metersPerDegreeLat,
        )

        fun unproject(point: ProjectedPoint): RoutePoint = RoutePoint(
            lat = origin.lat + point.y / metersPerDegreeLat,
            lon = origin.lon + point.x / metersPerDegreeLon,
        )
    }

    private companion object {
        const val LANE_ONE_RADIUS_METERS = 36.5
        const val STRAIGHT_LENGTH_METERS = 84.39
        const val TRACK_LENGTH_METERS = STRAIGHT_LENGTH_METERS * 2.0 + 2.0 * PI * LANE_ONE_RADIUS_METERS
        const val TRACK_SURFACE_INSET_METERS = 9.0
    }
}
