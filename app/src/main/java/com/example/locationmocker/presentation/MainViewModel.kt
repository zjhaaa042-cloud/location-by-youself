package com.example.locationmocker.presentation

import android.Manifest
import android.app.Application
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.example.locationmocker.data.SettingsRepository
import com.example.locationmocker.domain.model.PlaybackMode
import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.model.SimulationConfig
import com.example.locationmocker.domain.model.SimulationState
import com.example.locationmocker.domain.route.RouteMath
import com.example.locationmocker.service.MockLocationService
import com.example.locationmocker.service.SimulationProgressBus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class EditMode {
    Fixed,
    Route,
}

data class Readiness(
    val hasLocationPermission: Boolean = false,
    val hasNotificationPermission: Boolean = true,
    val locationEnabled: Boolean = false,
    val mockAppSelected: Boolean = false,
) {
    val ready: Boolean
        get() = hasLocationPermission && locationEnabled && mockAppSelected

    fun missingItems(): List<String> = buildList {
        if (!hasLocationPermission) add("定位权限")
        if (!locationEnabled) add("系统定位开关")
        if (!mockAppSelected) add("模拟位置应用")
        if (!hasNotificationPermission) add("通知权限")
    }
}

data class MainUiState(
    val points: List<RoutePoint> = emptyList(),
    val editMode: EditMode = EditMode.Fixed,
    val speedKmh: Float = 5f,
    val playbackMode: PlaybackMode = PlaybackMode.Once,
    val simulationState: SimulationState = SimulationState.Idle,
    val readiness: Readiness = Readiness(),
    val devicePoint: RoutePoint? = null,
    val currentPoint: RoutePoint? = null,
    val traveledPoints: List<RoutePoint> = emptyList(),
) {
    val selectedPoint: RoutePoint?
        get() = points.lastOrNull()
}

class MainViewModel(
    application: Application,
    private val settingsRepository: SettingsRepository,
) : AndroidViewModel(application) {
    private val _uiState = MutableStateFlow(MainUiState())
    val uiState: StateFlow<MainUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            settingsRepository.settings.collect { saved ->
                _uiState.update {
                    it.copy(
                        speedKmh = saved.speedKmh,
                        playbackMode = saved.playbackMode,
                        points = saved.points,
                        simulationState = it.simulationState.preserveActiveOrReady(saved.points),
                    )
                }
            }
        }
        viewModelScope.launch {
            SimulationProgressBus.progress.collect { progress ->
                _uiState.update { state ->
                    if (progress == null) {
                        state.copy(
                            currentPoint = null,
                            traveledPoints = emptyList(),
                            simulationState = if (state.points.isEmpty()) {
                                SimulationState.Idle
                            } else {
                                SimulationState.Ready
                            },
                        )
                    } else if (progress.errorMessage != null) {
                        state.copy(
                            simulationState = SimulationState.Error(progress.errorMessage),
                        )
                    } else {
                        val nextTrail = if (progress.isRoute) {
                            state.traveledPoints.appendIfMoved(progress.point)
                        } else {
                            emptyList()
                        }
                        state.copy(
                            currentPoint = progress.point,
                            traveledPoints = nextTrail,
                            simulationState = if (progress.paused) {
                                SimulationState.Paused
                            } else {
                                SimulationState.Running
                            },
                        )
                    }
                }
            }
        }
        refreshReadiness()
    }

    fun refreshReadiness() {
        val context = getApplication<Application>()
        _uiState.update { it.copy(readiness = context.readiness()) }
    }

    fun onDeviceLocationChanged(lat: Double, lon: Double) {
        _uiState.update {
            it.copy(devicePoint = RoutePoint(lat = lat, lon = lon))
        }
    }

    fun setEditMode(mode: EditMode) {
        _uiState.update { it.copy(editMode = mode) }
    }

    fun onMapTapped(lat: Double, lon: Double) {
        val newPoint = RoutePoint(lat = lat, lon = lon)
        val updatedPoints = when (_uiState.value.editMode) {
            EditMode.Fixed -> listOf(newPoint)
            EditMode.Route -> _uiState.value.points + newPoint
        }
        _uiState.update {
            it.copy(
                points = updatedPoints,
                simulationState = SimulationState.Ready,
            )
        }
        viewModelScope.launch { settingsRepository.savePoints(updatedPoints) }
    }

    fun undoLastPoint() {
        val updated = _uiState.value.points.dropLast(1)
        _uiState.update {
            it.copy(
                points = updated,
                simulationState = if (updated.isEmpty()) SimulationState.Idle else SimulationState.Ready,
            )
        }
        viewModelScope.launch { settingsRepository.savePoints(updated) }
    }

    fun clearPoints() {
        _uiState.update {
            it.copy(points = emptyList(), simulationState = SimulationState.Idle)
        }
        viewModelScope.launch { settingsRepository.savePoints(emptyList()) }
    }

    fun setSpeed(speedKmh: Float) {
        val clamped = speedKmh.coerceIn(5f, 120f)
        _uiState.update { it.copy(speedKmh = clamped) }
        viewModelScope.launch { settingsRepository.saveSpeed(clamped) }
    }

    fun setPlaybackMode(mode: PlaybackMode) {
        _uiState.update { it.copy(playbackMode = mode) }
        viewModelScope.launch { settingsRepository.savePlaybackMode(mode) }
    }

    fun play() {
        refreshReadiness()
        val state = _uiState.value
        if (!state.readiness.ready) {
            val missingItems = state.readiness.missingItems()
                .filterNot { it == "通知权限" }
                .joinToString("、")
            _uiState.update { it.copy(simulationState = SimulationState.Error("还需要完成：$missingItems")) }
            return
        }

        val context = getApplication<Application>()
        val intent = when (state.editMode) {
            EditMode.Fixed -> {
                val point = state.selectedPoint ?: run {
                    _uiState.update { it.copy(simulationState = SimulationState.Error("请先在地图上选择一个位置")) }
                    return
                }
                MockLocationService.startFixedIntent(context, point)
            }

            EditMode.Route -> {
                if (state.points.size < 2) {
                    _uiState.update { it.copy(simulationState = SimulationState.Error("路线模式至少需要 2 个途经点")) }
                    return
                }
                MockLocationService.startRouteIntent(
                    context,
                    SimulationConfig(
                        points = state.points,
                        speedKmh = state.speedKmh,
                        mode = state.playbackMode,
                    ),
                )
            }
        }

        ContextCompat.startForegroundService(context, intent)
        _uiState.update {
            it.copy(
                simulationState = SimulationState.Running,
                currentPoint = null,
                traveledPoints = emptyList(),
            )
        }
    }

    fun pause() {
        getApplication<Application>().startService(
            Intent(getApplication(), MockLocationService::class.java).setAction(MockLocationService.ACTION_PAUSE),
        )
        _uiState.update { it.copy(simulationState = SimulationState.Paused) }
    }

    fun resume() {
        getApplication<Application>().startService(
            Intent(getApplication(), MockLocationService::class.java).setAction(MockLocationService.ACTION_RESUME),
        )
        _uiState.update { it.copy(simulationState = SimulationState.Running) }
    }

    fun stop() {
        val context = getApplication<Application>()
        context.startService(MockLocationService.stopIntent(context))
        _uiState.update {
            it.copy(
                simulationState = if (it.points.isEmpty()) SimulationState.Idle else SimulationState.Ready,
                currentPoint = null,
                traveledPoints = emptyList(),
            )
        }
    }

    fun openDeveloperOptions() {
        val intent = Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        getApplication<Application>().startActivity(intent)
    }

    fun openLocationSettings() {
        val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        getApplication<Application>().startActivity(intent)
    }

    private fun Context.readiness(): Readiness {
        val hasFineLocationPermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val hasCoarseLocationPermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val hasNotificationPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        val locationManager = getSystemService(LocationManager::class.java)
        val locationEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            locationManager.isLocationEnabled
        } else {
            @Suppress("DEPRECATION")
            locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        }
        return Readiness(
            hasLocationPermission = hasFineLocationPermission || hasCoarseLocationPermission,
            hasNotificationPermission = hasNotificationPermission,
            locationEnabled = locationEnabled,
            mockAppSelected = isMockLocationApp(),
        )
    }

    private fun Context.isMockLocationApp(): Boolean {
        val appOps = getSystemService(AppOpsManager::class.java)
        val mode = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_MOCK_LOCATION,
                    android.os.Process.myUid(),
                    packageName,
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_MOCK_LOCATION,
                    android.os.Process.myUid(),
                    packageName,
                )
            }
        } catch (_: RuntimeException) {
            AppOpsManager.MODE_ERRORED
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }
}

private fun List<RoutePoint>.appendIfMoved(point: RoutePoint): List<RoutePoint> {
    val last = lastOrNull()
    return if (last == null || RouteMath.distanceMeters(last, point) >= 1.0) {
        this + point
    } else {
        this
    }
}

private fun SimulationState.preserveActiveOrReady(points: List<RoutePoint>): SimulationState {
    return when (this) {
        SimulationState.Running,
        SimulationState.Paused,
        is SimulationState.Error -> this
        else -> if (points.isEmpty()) SimulationState.Idle else SimulationState.Ready
    }
}

class MainViewModelFactory(
    private val application: Application,
    private val settingsRepository: SettingsRepository,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return MainViewModel(application, settingsRepository) as T
    }
}
