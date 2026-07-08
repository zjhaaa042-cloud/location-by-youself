package com.example.locationmocker.domain.track

import com.example.locationmocker.domain.model.PlaybackMode
import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.route.RouteMath
import kotlin.random.Random
import org.junit.Assert.assertTrue
import org.junit.Test

class NaturalRunCursorTest {
    @Test
    fun next_keepsSpeedInNaturalRunningRange() {
        val route = TrackRoutePlanner().buildCounterClockwiseRoute(RoutePoint(31.2304, 121.4737))
        val cursor = NaturalRunCursor(route, PlaybackMode.Loop, baseSpeedKmh = 8.5f, random = Random(7))

        repeat(120) {
            val sample = requireNotNull(cursor.next())
            val speedKmh = sample.speedMetersPerSecond * 3.6f
            assertTrue(speedKmh in 6f..12f)
        }
    }

    @Test
    fun next_appliesSmallTrackDrift() {
        val route = TrackRoutePlanner().buildCounterClockwiseRoute(RoutePoint(31.2304, 121.4737))
        val cursor = NaturalRunCursor(route, PlaybackMode.Loop, baseSpeedKmh = 8.5f, random = Random(11))

        val projection = TrackRoutePlanner.LocalProjection(route.first())
        val driftDistances = (0 until 60).map {
            val sample = requireNotNull(cursor.next())
            val nearestRoutePoint = route.minBy { point ->
                val projected = projection.project(point)
                val sampleProjected = projection.project(sample.point)
                val dx = projected.x - sampleProjected.x
                val dy = projected.y - sampleProjected.y
                dx * dx + dy * dy
            }
            RouteMath.distanceMeters(nearestRoutePoint, sample.point)
        }

        assertTrue(driftDistances.max() <= 4.0)
        assertTrue(driftDistances.any { it >= 0.5 })
    }
}
