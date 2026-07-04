package com.example.locationmocker.domain.route

import com.example.locationmocker.domain.model.PlaybackMode
import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.model.SimulationConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RoutePlannerTest {
    private val planner = RoutePlanner()

    @Test
    fun buildSamples_emptyRouteReturnsEmptyList() {
        val samples = planner.buildSamples(
            SimulationConfig(emptyList(), 5f, PlaybackMode.Once),
        )

        assertTrue(samples.isEmpty())
    }

    @Test
    fun buildSamples_singlePointReturnsStationarySample() {
        val point = RoutePoint(31.2304, 121.4737)

        val samples = planner.buildSamples(
            SimulationConfig(listOf(point), 5f, PlaybackMode.Once),
        )

        assertEquals(1, samples.size)
        assertEquals(0f, samples.first().speedMetersPerSecond, 0.001f)
    }

    @Test
    fun buildSamples_twoPointsIncludesStartAndEnd() {
        val start = RoutePoint(31.2304, 121.4737)
        val end = RoutePoint(31.2404, 121.4837)

        val samples = planner.buildSamples(
            SimulationConfig(listOf(start, end), 36f, PlaybackMode.Once),
        )

        assertTrue(samples.size > 2)
        assertEquals(start.lat, samples.first().point.lat, 0.000001)
        assertEquals(end.lon, samples.last().point.lon, 0.000001)
    }
}
