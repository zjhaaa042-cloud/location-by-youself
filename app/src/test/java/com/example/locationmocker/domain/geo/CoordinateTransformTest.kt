package com.example.locationmocker.domain.geo

import com.example.locationmocker.domain.model.RoutePoint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CoordinateTransformTest {
    @Test
    fun gcj02ToWgs84_reversesForwardTransformInChina() {
        val wgs84 = RoutePoint(lat = 31.2304, lon = 121.4737)

        val gcj02 = CoordinateTransform.wgs84ToGcj02(wgs84)
        val convertedBack = CoordinateTransform.gcj02ToWgs84(gcj02)

        assertEquals(wgs84.lat, convertedBack.lat, 0.000001)
        assertEquals(wgs84.lon, convertedBack.lon, 0.000001)
    }

    @Test
    fun gcj02ToWgs84_keepsOutsideChinaCoordinatesUnchanged() {
        val newYork = RoutePoint(lat = 40.7128, lon = -74.0060)

        val converted = CoordinateTransform.gcj02ToWgs84(newYork)

        assertEquals(newYork, converted)
    }

    @Test
    fun wgs84ToGcj02_offsetsChinaCoordinates() {
        val shanghai = RoutePoint(lat = 31.2304, lon = 121.4737)

        val converted = CoordinateTransform.wgs84ToGcj02(shanghai)

        assertTrue(kotlin.math.abs(converted.lat - shanghai.lat) > 0.001)
        assertTrue(kotlin.math.abs(converted.lon - shanghai.lon) > 0.001)
    }
}
