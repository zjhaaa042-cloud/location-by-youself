package com.example.locationmocker.domain.route

import com.example.locationmocker.domain.model.RoutePoint
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

object RouteMath {
    private const val EARTH_RADIUS_METERS = 6_371_000.0

    fun speedKmhToMetersPerSecond(speedKmh: Float): Float = speedKmh / 3.6f

    fun distanceMeters(a: RoutePoint, b: RoutePoint): Double {
        val dLat = (b.lat - a.lat).toRadians()
        val dLon = (b.lon - a.lon).toRadians()
        val lat1 = a.lat.toRadians()
        val lat2 = b.lat.toRadians()
        val haversine = sin(dLat / 2).pow(2) + cos(lat1) * cos(lat2) * sin(dLon / 2).pow(2)
        return 2 * EARTH_RADIUS_METERS * atan2(sqrt(haversine), sqrt(1 - haversine))
    }

    fun bearingDegrees(a: RoutePoint, b: RoutePoint): Float {
        if (a == b) return 0f
        val lat1 = a.lat.toRadians()
        val lat2 = b.lat.toRadians()
        val dLon = (b.lon - a.lon).toRadians()
        val y = sin(dLon) * cos(lat2)
        val x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return ((atan2(y, x).toDegrees() + 360.0) % 360.0).toFloat()
    }

    fun interpolate(a: RoutePoint, b: RoutePoint, fraction: Double): RoutePoint {
        val clamped = fraction.coerceIn(0.0, 1.0)
        val altitude = when {
            a.altitude != null && b.altitude != null -> a.altitude + (b.altitude - a.altitude) * clamped
            else -> a.altitude ?: b.altitude
        }
        return RoutePoint(
            lat = a.lat + (b.lat - a.lat) * clamped,
            lon = a.lon + (b.lon - a.lon) * clamped,
            altitude = altitude,
        )
    }

    internal fun Double.toRadians(): Double = this / 180.0 * PI
    private fun Double.toDegrees(): Double = this / PI * 180.0
}
