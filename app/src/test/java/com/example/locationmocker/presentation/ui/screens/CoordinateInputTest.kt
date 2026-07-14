package com.example.locationmocker.presentation.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class CoordinateInputTest {
    @Test
    fun parsesCommaSeparatedCoordinate() {
        val result = parseCoordinateInput("39.9042, 116.4074")

        assertNull(result.error)
        assertNotNull(result.point)
        assertEquals(39.9042, result.point!!.lat, 0.000001)
        assertEquals(116.4074, result.point!!.lon, 0.000001)
    }

    @Test
    fun parsesChineseCommaAndWhitespace() {
        val result = parseCoordinateInput(" 31.2304， 121.4737 ")

        assertNull(result.error)
        assertEquals(31.2304, result.point!!.lat, 0.000001)
        assertEquals(121.4737, result.point!!.lon, 0.000001)
    }

    @Test
    fun rejectsOutOfRangeCoordinate() {
        val result = parseCoordinateInput("91, 181")

        assertNull(result.point)
        assertNotNull(result.error)
    }
}
