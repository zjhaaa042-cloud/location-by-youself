package com.example.locationmocker.presentation

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.presentation.ui.components.AppBottomNavigation
import com.example.locationmocker.presentation.ui.components.AppDestination
import com.example.locationmocker.presentation.ui.components.SimulationSettingsSheet
import com.example.locationmocker.presentation.ui.screens.MapHomeOverlay
import com.example.locationmocker.presentation.ui.screens.SavedScreen
import com.example.locationmocker.presentation.ui.screens.SearchScreen
import com.example.locationmocker.presentation.ui.screens.SettingsScreen
import kotlinx.coroutines.delay

@Composable
fun MainScreen(
    viewModel: MainViewModel,
    onRequestPermissions: () -> Unit,
) {
    val uiState by viewModel.uiState.collectAsState()
    var destinationName by rememberSaveable { mutableStateOf(AppDestination.Map.name) }
    val destination = AppDestination.valueOf(destinationName)
    var controlsExpanded by rememberSaveable { mutableStateOf(false) }
    var mapLoaded by rememberSaveable { mutableStateOf(false) }
    var mapLoadSlow by rememberSaveable { mutableStateOf(false) }
    var wasStopped by rememberSaveable { mutableStateOf(false) }
    var trackDetectionRequestId by rememberSaveable { mutableIntStateOf(0) }
    var trackDetectionTarget by remember { mutableStateOf<RoutePoint?>(null) }

    fun navigateTo(next: AppDestination) {
        destinationName = next.name
    }

    fun selectCoordinate(point: RoutePoint) {
        wasStopped = false
        viewModel.onMapTapped(point.lat, point.lon)
        navigateTo(AppDestination.Map)
    }

    LaunchedEffect(mapLoaded) {
        mapLoadSlow = false
        if (!mapLoaded) {
            delay(12_000)
            if (!mapLoaded) mapLoadSlow = true
        }
    }

    BackHandler(enabled = controlsExpanded || destination != AppDestination.Map) {
        when {
            controlsExpanded -> controlsExpanded = false
            destination != AppDestination.Map -> navigateTo(AppDestination.Map)
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        AmapView(
            points = uiState.points,
            devicePoint = uiState.devicePoint,
            currentPoint = uiState.currentPoint,
            traveledPoints = uiState.traveledPoints,
            routeMode = uiState.editMode != EditMode.Fixed,
            showPointMarkers = uiState.editMode != EditMode.Track,
            enableTrackSegmentation = uiState.editMode == EditMode.Track,
            trackDetectionRequestId = trackDetectionRequestId,
            trackDetectionTarget = trackDetectionTarget,
            onMapLoaded = { mapLoaded = true },
            onDeviceLocationChanged = viewModel::onDeviceLocationChanged,
            onMapTapped = { lat, lon, segmentedTrack ->
                wasStopped = false
                viewModel.onMapTapped(lat, lon, segmentedTrack)
            },
            onTrackDetectionRequested = viewModel::detectTrackWithSegment,
            modifier = Modifier.fillMaxSize(),
        )

        Scaffold(
            modifier = Modifier.fillMaxSize(),
            containerColor = androidx.compose.ui.graphics.Color.Transparent,
            bottomBar = {
                if (destination != AppDestination.Search) {
                    AppBottomNavigation(current = destination, onSelect = ::navigateTo)
                }
            },
        ) { innerPadding ->
            when (destination) {
                AppDestination.Map -> MapHomeOverlay(
                    state = uiState,
                    mapLoaded = mapLoaded,
                    mapLoadSlow = mapLoadSlow,
                    wasStopped = wasStopped,
                    contentPadding = innerPadding,
                    onSearch = { navigateTo(AppDestination.Search) },
                    onRequestPermissions = onRequestPermissions,
                    onOpenLocationSettings = viewModel::openLocationSettings,
                    onOpenDeveloperOptions = viewModel::openDeveloperOptions,
                    onPlay = {
                        wasStopped = false
                        viewModel.play()
                    },
                    onPause = viewModel::pause,
                    onResume = {
                        wasStopped = false
                        viewModel.resume()
                    },
                    onStop = {
                        viewModel.stop()
                        wasStopped = true
                    },
                    onOpenSettings = { controlsExpanded = true },
                )

                AppDestination.Saved -> SavedScreen(
                    points = uiState.points,
                    onOpenMap = { navigateTo(AppDestination.Map) },
                    onSelectCoordinate = ::selectCoordinate,
                    modifier = Modifier.fillMaxSize().padding(bottom = innerPadding.calculateBottomPadding()),
                )

                AppDestination.Settings -> SettingsScreen(
                    state = uiState,
                    onEditModeChanged = viewModel::setEditMode,
                    onSpeedChanged = viewModel::setSpeed,
                    onPlaybackModeChanged = viewModel::setPlaybackMode,
                    onTrackOrientationChanged = viewModel::setTrackOrientation,
                    onRequestPermissions = onRequestPermissions,
                    onOpenLocationSettings = viewModel::openLocationSettings,
                    onOpenDeveloperOptions = viewModel::openDeveloperOptions,
                    onRefreshReadiness = viewModel::refreshReadiness,
                    modifier = Modifier.fillMaxSize().padding(bottom = innerPadding.calculateBottomPadding()),
                )

                AppDestination.Search -> SearchScreen(
                    points = uiState.points,
                    onCoordinateSelected = ::selectCoordinate,
                    onBack = { navigateTo(AppDestination.Map) },
                    onOpenMap = { navigateTo(AppDestination.Map) },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        if (controlsExpanded) {
            SimulationSettingsSheet(
                state = uiState,
                onDismiss = { controlsExpanded = false },
                onEditModeChanged = viewModel::setEditMode,
                onSpeedChanged = viewModel::setSpeed,
                onPlaybackModeChanged = viewModel::setPlaybackMode,
                onTrackOrientationChanged = viewModel::setTrackOrientation,
                onDetectTrack = {
                    val target = uiState.trackDetectionTarget()
                    if (target == null) {
                        viewModel.detectTrackNearSelected()
                    } else {
                        trackDetectionTarget = target
                        trackDetectionRequestId += 1
                    }
                },
                onUndo = viewModel::undoLastPoint,
                onClear = viewModel::clearPoints,
            )
        }
    }
}
