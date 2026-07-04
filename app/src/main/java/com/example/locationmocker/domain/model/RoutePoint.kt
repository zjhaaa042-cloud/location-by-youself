package com.example.locationmocker.domain.model

data class RoutePoint(
    val lat: Double,
    val lon: Double,
    val altitude: Double? = null,
)
