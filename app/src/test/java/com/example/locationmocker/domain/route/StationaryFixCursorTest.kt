package com.example.locationmocker.domain.route

import com.example.locationmocker.domain.model.RoutePoint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StationaryFixCursorTest {
    private val target = RoutePoint(lat = 31.2304, lon = 121.4737, altitude = 12.0)

    @Test
    fun next_keepsEveryFixWithinOneMeterOfTarget() {
        val cursor = StationaryFixCursor(target)

        repeat(16) {
            val sample = cursor.next()

            assertTrue(RouteMath.distanceMeters(target, sample.point) < 1.0)
            assertEquals(target.altitude, sample.point.altitude)
        }
    }

    @Test
    fun next_doesNotRepeatConsecutiveCoordinates() {
        val cursor = StationaryFixCursor(target)
        var previous = cursor.next().point

        repeat(15) {
            val current = cursor.next().point

            assertNotEquals(previous, current)
            previous = current
        }
    }

    @Test
    fun next_marksFixAsNearlyStationaryButFresh() {
        val sample = StationaryFixCursor(target).next()

        assertTrue(sample.speedMetersPerSecond > 0f)
        assertTrue(sample.speedMetersPerSecond < 0.5f)
    }
}
