package com.example.locationmocker.domain.model

data class SimulationConfig(
    val points: List<RoutePoint>,
    val speedKmh: Float,
    val mode: PlaybackMode,
    val updateIntervalMs: Long = 1_000L,
    val routeProfile: RouteProfile = RouteProfile.Manual,
)
