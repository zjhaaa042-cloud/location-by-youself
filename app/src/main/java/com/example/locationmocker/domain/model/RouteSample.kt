package com.example.locationmocker.domain.model

data class RouteSample(
    val point: RoutePoint,
    val speedMetersPerSecond: Float,
    val bearingDegrees: Float,
)
