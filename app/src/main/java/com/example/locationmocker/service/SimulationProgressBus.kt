package com.example.locationmocker.service

import com.example.locationmocker.domain.model.RoutePoint
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class SimulationProgress(
    val point: RoutePoint,
    val speedMetersPerSecond: Float,
    val bearingDegrees: Float,
    val isRoute: Boolean,
    val paused: Boolean = false,
    val errorMessage: String? = null,
)

object SimulationProgressBus {
    private val _progress = MutableStateFlow<SimulationProgress?>(null)
    val progress: StateFlow<SimulationProgress?> = _progress.asStateFlow()

    fun update(progress: SimulationProgress) {
        _progress.value = progress
    }

    fun setPaused(paused: Boolean) {
        _progress.value = _progress.value?.copy(paused = paused)
    }

    fun clear() {
        _progress.value = null
    }

    fun fail(message: String) {
        val fallbackPoint = _progress.value?.point ?: RoutePoint(0.0, 0.0)
        _progress.value = SimulationProgress(
            point = fallbackPoint,
            speedMetersPerSecond = 0f,
            bearingDegrees = 0f,
            isRoute = false,
            errorMessage = message,
        )
    }
}
