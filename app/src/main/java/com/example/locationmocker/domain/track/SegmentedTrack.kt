package com.example.locationmocker.domain.track

import com.example.locationmocker.domain.model.RoutePoint

data class SegmentedTrack(
    val center: RoutePoint,
    val orientation: TrackOrientation,
    val confidence: Int,
    val rotationDegrees: Double? = null,
    val outerWidthMeters: Double? = null,
    val outerHeightMeters: Double? = null,
)
