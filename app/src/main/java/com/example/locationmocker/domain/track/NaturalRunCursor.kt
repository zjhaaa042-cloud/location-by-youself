package com.example.locationmocker.domain.track

import com.example.locationmocker.domain.model.PlaybackMode
import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.model.RouteSample
import com.example.locationmocker.domain.route.RouteMath
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.sin
import kotlin.random.Random

class NaturalRunCursor(
    route: List<RoutePoint>,
    private val mode: PlaybackMode,
    private val baseSpeedKmh: Float = 8.5f,
    private val updateIntervalMs: Long = 1_000L,
    private val random: Random = Random(System.currentTimeMillis()),
) {
    private val points = closeRoute(route)
    private val cumulativeMeters = buildCumulativeMeters(points)
    private val totalMeters = cumulativeMeters.lastOrNull() ?: 0.0
    private var traveledMeters = 0.0
    private var direction = 1
    private var completed = false
    private var lastLap = -1
    private var lapSpeedOffsetKmh = 0.0
    private var lapLaneBiasMeters = 0.0
    private var lapDriftAmplitudeMeters = 1.5
    private var lapPhase = 0.0
    @Volatile
    private var currentBaseSpeedKmh = baseSpeedKmh.coerceIn(6f, 12f)
    private var smoothedSpeedMetersPerSecond = (baseSpeedKmh / 3.6).toDouble()

    fun updateBaseSpeedKmh(speedKmh: Float) {
        currentBaseSpeedKmh = speedKmh.coerceIn(6f, 12f)
    }

    fun next(): RouteSample? {
        if (points.size < 2 || totalMeters <= 0.0 || completed) return null

        val lap = floor(traveledMeters / totalMeters).toInt()
        if (lap != lastLap) {
            lastLap = lap
            lapSpeedOffsetKmh = random.nextDouble(-0.45, 0.45)
            lapLaneBiasMeters = random.nextDouble(-0.9, 0.9)
            lapDriftAmplitudeMeters = random.nextDouble(1.0, 2.4)
            lapPhase = random.nextDouble(0.0, 2.0 * PI)
        }

        val currentDistance = normalizeDistance(traveledMeters)
        val progress = currentDistance / totalMeters
        val basePoint = interpolateAt(currentDistance)
        val nextDistance = normalizeDistance(currentDistance + direction * 2.0)
        val nextBasePoint = interpolateAt(nextDistance)
        val driftedPoint = applySmoothDrift(basePoint, nextBasePoint, progress)
        val lookAheadDistance = normalizeDistance(nextDistance + direction * 2.0)
        val nextProgress = lookAheadDistance / totalMeters
        val nextDriftedPoint = applySmoothDrift(nextBasePoint, interpolateAt(lookAheadDistance), nextProgress)
        val speed = smoothedSpeedMetersPerSecond(progress)
        val bearing = RouteMath.bearingDegrees(driftedPoint, nextDriftedPoint)

        advance(speed)
        return RouteSample(driftedPoint, speed, bearing)
    }

    private fun advance(speedMetersPerSecond: Float) {
        val stepMeters = speedMetersPerSecond * (updateIntervalMs / 1_000f)
        when (mode) {
            PlaybackMode.Once -> {
                traveledMeters += stepMeters
                if (traveledMeters >= totalMeters) completed = true
            }

            PlaybackMode.Loop -> {
                traveledMeters += stepMeters
            }

            PlaybackMode.PingPong -> {
                traveledMeters += stepMeters * direction
                when {
                    traveledMeters >= totalMeters -> {
                        traveledMeters = totalMeters
                        direction = -1
                    }

                    traveledMeters <= 0.0 -> {
                        traveledMeters = 0.0
                        direction = 1
                    }
                }
            }
        }
    }

    private fun smoothedSpeedMetersPerSecond(progress: Double): Float {
        val wave = sin(progress * 2.0 * PI * 3.0 + lapPhase) * 0.35 +
            sin(progress * 2.0 * PI * 7.0 + lapPhase * 0.7) * 0.15
        val speedKmh = (currentBaseSpeedKmh + lapSpeedOffsetKmh + wave).coerceIn(6.0, 12.0)
        val target = speedKmh / 3.6
        val alpha = (updateIntervalMs / 1_500.0).coerceIn(0.08, 0.28)
        smoothedSpeedMetersPerSecond += (target - smoothedSpeedMetersPerSecond) * alpha
        return smoothedSpeedMetersPerSecond.toFloat()
    }

    private fun applySmoothDrift(point: RoutePoint, nextPoint: RoutePoint, progress: Double): RoutePoint {
        val projection = TrackRoutePlanner.LocalProjection(point)
        val next = projection.project(nextPoint)
        val length = kotlin.math.sqrt(next.x * next.x + next.y * next.y).takeIf { it > 0.01 } ?: 1.0
        val normalX = -next.y / length
        val normalY = next.x / length
        val drift = (
            lapLaneBiasMeters +
                lapDriftAmplitudeMeters * sin(progress * 2.0 * PI * 2.0 + lapPhase) +
                0.45 * sin(progress * 2.0 * PI * 7.0 + lapPhase * 0.6)
            ).coerceIn(-3.0, 3.0)
        return projection.unproject(
            TrackRoutePlanner.ProjectedPoint(
                x = normalX * drift * direction,
                y = normalY * drift * direction,
            ),
        )
    }

    private fun interpolateAt(distanceMeters: Double): RoutePoint {
        val distance = distanceMeters.coerceIn(0.0, totalMeters)
        val segmentIndex = cumulativeMeters
            .indexOfLast { it <= distance }
            .coerceIn(0, cumulativeMeters.lastIndex - 1)
        val startDistance = cumulativeMeters[segmentIndex]
        val endDistance = cumulativeMeters[segmentIndex + 1]
        val fraction = if (endDistance == startDistance) {
            0.0
        } else {
            (distance - startDistance) / (endDistance - startDistance)
        }
        return RouteMath.interpolate(points[segmentIndex], points[segmentIndex + 1], fraction)
    }

    private fun normalizeDistance(distanceMeters: Double): Double {
        if (mode == PlaybackMode.PingPong) return distanceMeters.coerceIn(0.0, totalMeters)
        val remainder = distanceMeters % totalMeters
        return if (remainder < 0.0) remainder + totalMeters else remainder
    }

    private fun closeRoute(route: List<RoutePoint>): List<RoutePoint> {
        if (route.size < 2) return route
        return if (RouteMath.distanceMeters(route.first(), route.last()) <= 0.5) {
            route
        } else {
            route + route.first()
        }
    }

    private fun buildCumulativeMeters(points: List<RoutePoint>): List<Double> {
        if (points.isEmpty()) return emptyList()
        val result = mutableListOf(0.0)
        points.zipWithNext().forEach { (a, b) ->
            result += result.last() + RouteMath.distanceMeters(a, b)
        }
        return result
    }
}
