package com.example.locationmocker.domain.route

import com.example.locationmocker.domain.model.RoutePoint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RouteMathTest {
    @Test
    fun speedKmhToMetersPerSecond_convertsExpectedValue() {
        assertEquals(10f, RouteMath.speedKmhToMetersPerSecond(36f), 0.001f)
    }

    @Test
    fun interpolate_returnsMiddlePoint() {
        val start = RoutePoint(10.0, 20.0)
        val end = RoutePoint(12.0, 24.0)

        val middle = RouteMath.interpolate(start, end, 0.5)

        assertEquals(11.0, middle.lat, 0.000001)
        assertEquals(22.0, middle.lon, 0.000001)
    }

    @Test
    fun distanceMeters_forNearbyPointsIsPositive() {
        val start = RoutePoint(31.2304, 121.4737)
        val end = RoutePoint(31.2314, 121.4737)

        assertTrue(RouteMath.distanceMeters(start, end) > 100)
    }
}
