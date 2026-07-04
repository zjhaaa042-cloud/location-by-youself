package com.example.locationmocker.domain.route

import com.example.locationmocker.domain.model.PlaybackMode
import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.model.RouteSample
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PlaybackCursorTest {
    private val samples = listOf(
        sample(0.0),
        sample(1.0),
        sample(2.0),
    )

    @Test
    fun once_returnsSamplesThenCompletes() {
        val cursor = PlaybackCursor(samples, PlaybackMode.Once)

        assertEquals(0.0, cursor.next()?.point?.lat)
        assertEquals(1.0, cursor.next()?.point?.lat)
        assertEquals(2.0, cursor.next()?.point?.lat)
        assertNull(cursor.next())
    }

    @Test
    fun once_singleSampleCompletesAfterFirstValue() {
        val cursor = PlaybackCursor(listOf(sample(4.0)), PlaybackMode.Once)

        assertEquals(4.0, cursor.next()?.point?.lat)
        assertNull(cursor.next())
    }

    @Test
    fun loop_wrapsToBeginning() {
        val cursor = PlaybackCursor(samples, PlaybackMode.Loop)

        val latitudes = List(5) { cursor.next()?.point?.lat }

        assertEquals(listOf(0.0, 1.0, 2.0, 0.0, 1.0), latitudes)
    }

    @Test
    fun pingPong_reversesAtEnds() {
        val cursor = PlaybackCursor(samples, PlaybackMode.PingPong)

        val latitudes = List(7) { cursor.next()?.point?.lat }

        assertEquals(listOf(0.0, 1.0, 2.0, 1.0, 0.0, 1.0, 2.0), latitudes)
    }

    private fun sample(lat: Double): RouteSample =
        RouteSample(RoutePoint(lat, 0.0), speedMetersPerSecond = 1f, bearingDegrees = 0f)
}
