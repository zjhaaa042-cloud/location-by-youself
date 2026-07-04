package com.example.locationmocker.domain.route

import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.model.RouteSample
import com.example.locationmocker.domain.model.SimulationConfig
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.roundToInt

class RoutePlanner {
    fun buildSamples(config: SimulationConfig): List<RouteSample> {
        val points = config.points
        if (points.isEmpty()) return emptyList()
        if (points.size == 1) {
            return listOf(
                RouteSample(
                    point = points.first(),
                    speedMetersPerSecond = 0f,
                    bearingDegrees = 0f,
                ),
            )
        }

        val smoothPolyline = buildSmoothPolyline(points)
        val stepMeters = RouteMath.speedKmhToMetersPerSecond(config.speedKmh) *
            (config.updateIntervalMs / 1_000f)
        val sampledPoints = sampleByDistance(smoothPolyline, max(1.0, stepMeters.toDouble()))
        return sampledPoints.mapIndexed { index, point ->
            val next = sampledPoints.getOrNull(index + 1) ?: sampledPoints.getOrNull(index - 1) ?: point
            RouteSample(
                point = point,
                speedMetersPerSecond = RouteMath.speedKmhToMetersPerSecond(config.speedKmh),
                bearingDegrees = RouteMath.bearingDegrees(point, next),
            )
        }
    }

    fun buildSmoothPolyline(points: List<RoutePoint>): List<RoutePoint> {
        if (points.size <= 2) return densifyLinear(points)

        val projection = LocalProjection(points.first())
        val projected = points.map(projection::project)
        val result = mutableListOf<RoutePoint>()

        for (i in 0 until projected.lastIndex) {
            val p0 = projected.getOrElse(i - 1) { projected[i] }
            val p1 = projected[i]
            val p2 = projected[i + 1]
            val p3 = projected.getOrElse(i + 2) { projected[i + 1] }
            val distance = p1.distanceTo(p2)
            val samples = max(8, (distance / 20.0).roundToInt())

            for (s in 0 until samples) {
                val t = s.toDouble() / samples
                val x = catmullRom(p0.x, p1.x, p2.x, p3.x, t)
                val y = catmullRom(p0.y, p1.y, p2.y, p3.y, t)
                result += projection.unproject(ProjectedPoint(x, y))
            }
        }

        result += points.last()
        return removeNearDuplicates(result)
    }

    private fun densifyLinear(points: List<RoutePoint>): List<RoutePoint> {
        if (points.size <= 1) return points
        val result = mutableListOf<RoutePoint>()
        points.zipWithNext().forEach { (start, end) ->
            val distance = RouteMath.distanceMeters(start, end)
            val samples = max(1, (distance / 20.0).roundToInt())
            for (i in 0 until samples) {
                result += RouteMath.interpolate(start, end, i.toDouble() / samples)
            }
        }
        result += points.last()
        return removeNearDuplicates(result)
    }

    private fun sampleByDistance(polyline: List<RoutePoint>, stepMeters: Double): List<RoutePoint> {
        if (polyline.size <= 1) return polyline

        val result = mutableListOf(polyline.first())
        var segmentStartIndex = 0
        var segmentStartDistance = 0.0
        var targetDistance = stepMeters
        val cumulative = mutableListOf(0.0)

        polyline.zipWithNext().forEach { (a, b) ->
            cumulative += cumulative.last() + RouteMath.distanceMeters(a, b)
        }
        val totalDistance = cumulative.last()

        while (targetDistance < totalDistance) {
            while (
                segmentStartIndex < cumulative.lastIndex - 1 &&
                cumulative[segmentStartIndex + 1] < targetDistance
            ) {
                segmentStartIndex++
                segmentStartDistance = cumulative[segmentStartIndex]
            }

            val nextDistance = cumulative[segmentStartIndex + 1]
            val fraction = if (nextDistance == segmentStartDistance) {
                0.0
            } else {
                (targetDistance - segmentStartDistance) / (nextDistance - segmentStartDistance)
            }
            result += RouteMath.interpolate(
                polyline[segmentStartIndex],
                polyline[segmentStartIndex + 1],
                fraction,
            )
            targetDistance += stepMeters
        }

        if (RouteMath.distanceMeters(result.last(), polyline.last()) > 0.5) {
            result += polyline.last()
        }
        return result
    }

    private fun removeNearDuplicates(points: List<RoutePoint>): List<RoutePoint> {
        val result = mutableListOf<RoutePoint>()
        points.forEach { point ->
            if (result.lastOrNull()?.let { RouteMath.distanceMeters(it, point) < 0.25 } != true) {
                result += point
            }
        }
        return result
    }

    private fun catmullRom(p0: Double, p1: Double, p2: Double, p3: Double, t: Double): Double {
        val t2 = t * t
        val t3 = t2 * t
        return 0.5 * (
            (2 * p1) +
                (-p0 + p2) * t +
                (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                (-p0 + 3 * p1 - 3 * p2 + p3) * t3
            )
    }

    private data class ProjectedPoint(val x: Double, val y: Double) {
        fun distanceTo(other: ProjectedPoint): Double {
            val dx = x - other.x
            val dy = y - other.y
            return kotlin.math.sqrt(dx * dx + dy * dy)
        }
    }

    private class LocalProjection(private val origin: RoutePoint) {
        private val metersPerDegreeLat = 111_320.0
        private val metersPerDegreeLon = 111_320.0 * cos(origin.lat * Math.PI / 180.0)

        fun project(point: RoutePoint): ProjectedPoint = ProjectedPoint(
            x = (point.lon - origin.lon) * metersPerDegreeLon,
            y = (point.lat - origin.lat) * metersPerDegreeLat,
        )

        fun unproject(point: ProjectedPoint): RoutePoint = RoutePoint(
            lat = origin.lat + point.y / metersPerDegreeLat,
            lon = origin.lon + point.x / metersPerDegreeLon,
        )
    }
}
