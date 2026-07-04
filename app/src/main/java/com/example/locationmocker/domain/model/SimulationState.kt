package com.example.locationmocker.domain.model

sealed interface SimulationState {
    data object Idle : SimulationState
    data object Ready : SimulationState
    data object Running : SimulationState
    data object Paused : SimulationState
    data class Error(val message: String) : SimulationState
}
