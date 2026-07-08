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
import com.example.locationmocker.data.TrackDetector
import com.example.locationmocker.domain.model.PlaybackMode
import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.model.RouteProfile
import com.example.locationmocker.domain.model.SimulationConfig
import com.example.locationmocker.domain.model.SimulationState
import com.example.locationmocker.domain.route.RouteMath
import com.example.locationmocker.domain.track.SegmentedTrack
import com.example.locationmocker.domain.track.TrackDetectionResult
import com.example.locationmocker.domain.track.TrackOrientation
import com.example.locationmocker.domain.track.TrackRoutePlanner
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
    Track,
}

sealed interface TrackUiState {
    data object NotSelected : TrackUiState
    data class ReadyToDetect(val point: RoutePoint) : TrackUiState
    data object Detecting : TrackUiState
    data class Detected(val name: String, val center: RoutePoint) : TrackUiState
    data class Failed(val message: String) : TrackUiState
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
        if (!hasLocationPermission) add("\u5b9a\u4f4d\u6743\u9650")
        if (!locationEnabled) add("\u7cfb\u7edf\u5b9a\u4f4d\u5f00\u5173")
        if (!mockAppSelected) add("\u6a21\u62df\u4f4d\u7f6e\u5e94\u7528")
        if (!hasNotificationPermission) add("\u901a\u77e5\u6743\u9650")
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
    val trackState: TrackUiState = TrackUiState.NotSelected,
    val trackOrientation: TrackOrientation = TrackOrientation.Vertical,
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

    private val trackDetector = TrackDetector(application.applicationContext)
    private val trackRoutePlanner = TrackRoutePlanner()

    init {
        viewModelScope.launch {
            settingsRepository.settings.collect { saved ->
                _uiState.update {
                    it.copy(
                        speedKmh = saved.speedKmh,
                        playbackMode = saved.playbackMode,
                        points = saved.points,
                        trackOrientation = saved.trackOrientation,
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
                        state.copy(simulationState = SimulationState.Error(progress.errorMessage))
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
        _uiState.update {
            if (mode == EditMode.Track) {
                it.copy(
                    editMode = mode,
                    speedKmh = it.speedKmh.coerceIn(6f, 12f),
                    playbackMode = PlaybackMode.Loop,
                )
            } else {
                it.copy(editMode = mode)
            }
        }
    }

    fun onMapTapped(lat: Double, lon: Double, segmentedTrack: SegmentedTrack? = null) {
        val newPoint = RoutePoint(lat = lat, lon = lon)
        val editMode = _uiState.value.editMode
        val updatedPoints = when (editMode) {
            EditMode.Fixed -> listOf(newPoint)
            EditMode.Route -> _uiState.value.points + newPoint
            EditMode.Track -> listOf(newPoint)
        }
        _uiState.update {
            it.copy(
                points = updatedPoints,
                simulationState = SimulationState.Ready,
                trackState = if (editMode == EditMode.Track) {
                    TrackUiState.ReadyToDetect(newPoint)
                } else {
                    it.trackState
                },
            )
        }
        viewModelScope.launch { settingsRepository.savePoints(updatedPoints) }
        if (editMode == EditMode.Track) {
            detectTrack(newPoint, segmentedTrack)
        }
    }

    fun detectTrackNearSelected() {
        val point = _uiState.value.trackDetectionAnchor() ?: run {
            _uiState.update {
                it.copy(simulationState = SimulationState.Error("\u8bf7\u5148\u5728\u5730\u56fe\u4e0a\u70b9\u51fb\u64cd\u573a\u9644\u8fd1\u4f4d\u7f6e"))
            }
            return
        }
        detectTrack(point, null)
    }

    fun detectTrackWithSegment(origin: RoutePoint, segmentedTrack: SegmentedTrack?) {
        detectTrack(origin, segmentedTrack)
    }

    fun setTrackOrientation(orientation: TrackOrientation) {
        val state = _uiState.value
        val center = when (val trackState = state.trackState) {
            is TrackUiState.Detected -> trackState.center
            is TrackUiState.ReadyToDetect -> trackState.point
            else -> state.selectedPoint
        }

        _uiState.update { it.copy(trackOrientation = orientation) }
        viewModelScope.launch { settingsRepository.saveTrackOrientation(orientation) }

        if (state.editMode == EditMode.Track && center != null) {
            val route = trackRoutePlanner.buildCounterClockwiseRoute(
                center = center,
                orientation = orientation,
            )
            _uiState.update {
                it.copy(
                    points = route,
                    simulationState = SimulationState.Ready,
                    trackState = when (it.trackState) {
                        is TrackUiState.Detected -> it.trackState
                        else -> TrackUiState.Detected("\u624b\u52a8\u8dd1\u9053", center)
                    },
                )
            }
            viewModelScope.launch {
                settingsRepository.savePoints(route)
                settingsRepository.saveTrack("\u624b\u52a8\u8dd1\u9053", center)
            }
        }
    }

    fun undoLastPoint() {
        val updated = _uiState.value.points.dropLast(1)
        _uiState.update {
            it.copy(
                points = updated,
                simulationState = if (updated.isEmpty()) SimulationState.Idle else SimulationState.Ready,
                trackState = if (it.editMode == EditMode.Track && updated.isEmpty()) {
                    TrackUiState.NotSelected
                } else {
                    it.trackState
                },
            )
        }
        viewModelScope.launch { settingsRepository.savePoints(updated) }
    }

    fun clearPoints() {
        _uiState.update {
            it.copy(
                points = emptyList(),
                simulationState = SimulationState.Idle,
                trackState = TrackUiState.NotSelected,
            )
        }
        viewModelScope.launch { settingsRepository.savePoints(emptyList()) }
    }

    fun setSpeed(speedKmh: Float) {
        val state = _uiState.value
        val clamped = if (state.editMode == EditMode.Track) {
            speedKmh.coerceIn(6f, 12f)
        } else {
            speedKmh.coerceIn(5f, 120f)
        }
        _uiState.update { it.copy(speedKmh = clamped) }
        if (
            state.editMode == EditMode.Track &&
            (state.simulationState == SimulationState.Running || state.simulationState == SimulationState.Paused)
        ) {
            val context = getApplication<Application>()
            context.startService(MockLocationService.updateSpeedIntent(context, clamped))
        }
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
                .filterNot { it == "\u901a\u77e5\u6743\u9650" }
                .joinToString("\u3001")
            _uiState.update { it.copy(simulationState = SimulationState.Error("\u8fd8\u9700\u8981\u5b8c\u6210\uff1a$missingItems")) }
            return
        }

        val context = getApplication<Application>()
        val intent = when (state.editMode) {
            EditMode.Fixed -> {
                val point = state.selectedPoint ?: run {
                    _uiState.update { it.copy(simulationState = SimulationState.Error("\u8bf7\u5148\u5728\u5730\u56fe\u4e0a\u9009\u62e9\u4e00\u4e2a\u4f4d\u7f6e")) }
                    return
                }
                MockLocationService.startFixedIntent(context, point)
            }

            EditMode.Route -> {
                if (state.points.size < 2) {
                    _uiState.update { it.copy(simulationState = SimulationState.Error("\u8def\u7ebf\u6a21\u5f0f\u81f3\u5c11\u9700\u8981 2 \u4e2a\u9014\u7ecf\u70b9")) }
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

            EditMode.Track -> {
                if (state.points.size < 2 || state.trackState !is TrackUiState.Detected) {
                    _uiState.update { it.copy(simulationState = SimulationState.Error("\u8bf7\u5148\u8bc6\u522b\u64cd\u573a\u5e76\u751f\u6210\u8dd1\u9053")) }
                    return
                }
                MockLocationService.startRouteIntent(
                    context,
                    SimulationConfig(
                        points = state.points,
                        speedKmh = state.speedKmh.coerceIn(6f, 12f),
                        mode = state.playbackMode,
                        updateIntervalMs = TRACK_RUNNING_INTERVAL_MS,
                        routeProfile = RouteProfile.TrackRunning,
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

    private fun detectTrack(origin: RoutePoint, segmentedTrack: SegmentedTrack? = null) {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    trackState = TrackUiState.Detecting,
                    simulationState = SimulationState.Ready,
                )
            }

            if (segmentedTrack != null && segmentedTrack.confidence >= 55) {
                val route = trackRoutePlanner.buildCounterClockwiseRoute(
                    center = segmentedTrack.center,
                    orientation = segmentedTrack.orientation,
                    rotationDegrees = segmentedTrack.rotationDegrees,
                    outerWidthMeters = segmentedTrack.outerWidthMeters,
                    outerHeightMeters = segmentedTrack.outerHeightMeters,
                )
                _uiState.update {
                    it.copy(
                        points = route,
                        trackState = TrackUiState.Detected("\u5730\u56fe\u5206\u5272\u8dd1\u9053", segmentedTrack.center),
                        simulationState = SimulationState.Ready,
                        playbackMode = PlaybackMode.Loop,
                        speedKmh = it.speedKmh.coerceIn(6f, 12f),
                        trackOrientation = segmentedTrack.orientation,
                    )
                }
                settingsRepository.savePoints(route)
                settingsRepository.saveTrack("\u5730\u56fe\u5206\u5272\u8dd1\u9053", segmentedTrack.center)
                settingsRepository.saveTrackOrientation(segmentedTrack.orientation)
                return@launch
            }

            _uiState.update {
                it.copy(
                    points = listOf(origin),
                    trackState = TrackUiState.Failed("\u672a\u80fd\u7a33\u5b9a\u8bc6\u522b\u8089\u7c89\u8272\u8dd1\u9053\uff0c\u8bf7\u653e\u5927\u5230\u6574\u6761\u8dd1\u9053\u6e05\u6670\u53ef\u89c1\u540e\u91cd\u8bd5"),
                    simulationState = SimulationState.Error("\u672a\u80fd\u7a33\u5b9a\u8bc6\u522b\u8dd1\u9053"),
                )
            }
        }
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

fun MainUiState.trackDetectionTarget(): RoutePoint? = trackDetectionAnchor()

private fun MainUiState.trackDetectionAnchor(): RoutePoint? {
    return when (val state = trackState) {
        is TrackUiState.Detected -> state.center
        is TrackUiState.ReadyToDetect -> state.point
        else -> selectedPoint
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

private const val TRACK_RUNNING_INTERVAL_MS = 250L
