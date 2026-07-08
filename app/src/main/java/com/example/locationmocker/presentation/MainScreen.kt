@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.example.locationmocker.presentation

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Undo
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.locationmocker.domain.model.PlaybackMode
import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.model.SimulationState
import com.example.locationmocker.domain.track.TrackOrientation

@Composable
fun MainScreen(
    viewModel: MainViewModel,
    onRequestPermissions: () -> Unit,
) {
    val uiState by viewModel.uiState.collectAsState()
    var controlsExpanded by rememberSaveable { mutableStateOf(false) }
    var mapLoaded by rememberSaveable { mutableStateOf(false) }
    var trackDetectionRequestId by rememberSaveable { mutableStateOf(0) }
    var trackDetectionTarget by remember { mutableStateOf<RoutePoint?>(null) }

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
            onMapTapped = viewModel::onMapTapped,
            onTrackDetectionRequested = viewModel::detectTrackWithSegment,
            modifier = Modifier.fillMaxSize(),
        )

        Surface(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(12.dp),
            shape = RoundedCornerShape(8.dp),
            tonalElevation = 2.dp,
            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
        ) {
            ReadinessBar(
                readiness = uiState.readiness,
                onRequestPermissions = onRequestPermissions,
                onOpenLocationSettings = viewModel::openLocationSettings,
                onOpenDeveloperOptions = viewModel::openDeveloperOptions,
                onRefresh = viewModel::refreshReadiness,
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
            )
        }

        Surface(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(12.dp),
            shape = RoundedCornerShape(8.dp),
            tonalElevation = 2.dp,
            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.88f),
        ) {
            Text(
                text = buildMapStatusText(mapLoaded, uiState.devicePoint != null),
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                style = MaterialTheme.typography.labelMedium,
            )
        }

        FloatingPlaybackControls(
            state = uiState,
            onPlay = viewModel::play,
            onPause = viewModel::pause,
            onResume = viewModel::resume,
            onStop = viewModel::stop,
            onTogglePanel = { controlsExpanded = !controlsExpanded },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .navigationBarsPadding()
                .padding(12.dp),
        )

        if (controlsExpanded) {
            SecondaryControlPanel(
                state = uiState,
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
                onPlay = viewModel::play,
                onPause = viewModel::pause,
                onResume = viewModel::resume,
                onStop = viewModel::stop,
                onCollapse = { controlsExpanded = false },
                onUndo = viewModel::undoLastPoint,
                onClear = viewModel::clearPoints,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .fillMaxWidth()
                    .widthIn(max = 560.dp)
                    .navigationBarsPadding()
                    .padding(start = 12.dp, end = 96.dp, bottom = 12.dp)
                    .shadow(8.dp, RoundedCornerShape(8.dp)),
            )
        }
    }
}

@Composable
private fun ReadinessBar(
    readiness: Readiness,
    onRequestPermissions: () -> Unit,
    onOpenLocationSettings: () -> Unit,
    onOpenDeveloperOptions: () -> Unit,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.LocationOn, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(
                text = readinessText(readiness),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.width(6.dp))
            IconButton(onClick = onRefresh, modifier = Modifier.size(32.dp)) {
                Icon(Icons.Default.Refresh, contentDescription = "\u5237\u65b0\u72b6\u6001")
            }
        }

        if (!readiness.ready) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (!readiness.hasLocationPermission) {
                    AssistChip(onClick = onRequestPermissions, label = { Text("\u5b9a\u4f4d\u6743\u9650") })
                }
                if (!readiness.locationEnabled) {
                    AssistChip(onClick = onOpenLocationSettings, label = { Text("\u5b9a\u4f4d\u670d\u52a1") })
                }
                if (!readiness.mockAppSelected) {
                    AssistChip(onClick = onOpenDeveloperOptions, label = { Text("\u6a21\u62df\u4f4d\u7f6e\u5e94\u7528") })
                }
            }
        } else if (!readiness.hasNotificationPermission) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AssistChip(onClick = onRequestPermissions, label = { Text("\u5f00\u542f\u901a\u77e5") })
            }
        }
    }
}

@Composable
private fun FloatingPlaybackControls(
    state: MainUiState,
    onPlay: () -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onStop: () -> Unit,
    onTogglePanel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(8.dp),
        tonalElevation = 5.dp,
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.95f),
    ) {
        Column(
            modifier = Modifier.padding(6.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            when (state.simulationState) {
                SimulationState.Running -> {
                    IconButton(onClick = onPause) {
                        Icon(Icons.Default.Pause, contentDescription = "\u6682\u505c")
                    }
                }

                SimulationState.Paused -> {
                    IconButton(onClick = onResume) {
                        Icon(Icons.Default.PlayArrow, contentDescription = "\u7ee7\u7eed")
                    }
                }

                else -> {
                    IconButton(onClick = onPlay) {
                        Icon(Icons.Default.PlayArrow, contentDescription = "\u5f00\u59cb")
                    }
                }
            }

            IconButton(onClick = onStop) {
                Icon(Icons.Default.Stop, contentDescription = "\u505c\u6b62")
            }

            Button(onClick = onTogglePanel) {
                Text("\u63a7\u5236")
            }
        }
    }
}

@Composable
private fun SecondaryControlPanel(
    state: MainUiState,
    onEditModeChanged: (EditMode) -> Unit,
    onSpeedChanged: (Float) -> Unit,
    onPlaybackModeChanged: (PlaybackMode) -> Unit,
    onTrackOrientationChanged: (TrackOrientation) -> Unit,
    onDetectTrack: () -> Unit,
    onPlay: () -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onStop: () -> Unit,
    onCollapse: () -> Unit,
    onUndo: () -> Unit,
    onClear: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f),
        tonalElevation = 4.dp,
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                FilterChip(
                    selected = state.editMode == EditMode.Fixed,
                    onClick = { onEditModeChanged(EditMode.Fixed) },
                    label = { Text("\u5b9a\u70b9") },
                )
                FilterChip(
                    selected = state.editMode == EditMode.Route,
                    onClick = { onEditModeChanged(EditMode.Route) },
                    label = { Text("\u8def\u7ebf ${state.points.size}") },
                )
                FilterChip(
                    selected = state.editMode == EditMode.Track,
                    onClick = { onEditModeChanged(EditMode.Track) },
                    label = { Text("\u64cd\u573a") },
                    leadingIcon = {
                        Icon(Icons.Default.DirectionsRun, contentDescription = null, modifier = Modifier.size(16.dp))
                    },
                )
                Spacer(Modifier.weight(1f))
                IconButton(onClick = onUndo, enabled = state.points.isNotEmpty() && state.editMode != EditMode.Track) {
                    Icon(Icons.Default.Undo, contentDescription = "\u64a4\u9500\u4e0a\u4e00\u4e2a\u70b9")
                }
                IconButton(onClick = onClear, enabled = state.points.isNotEmpty()) {
                    Icon(Icons.Default.Delete, contentDescription = "\u6e05\u7a7a\u70b9\u4f4d")
                }
                OutlinedButton(onClick = onCollapse) {
                    Text("\u6536\u8d77")
                }
            }

            if (state.editMode == EditMode.Track) {
                Spacer(Modifier.height(8.dp))
                TrackStatusRow(
                    trackState = state.trackState,
                    onDetectTrack = onDetectTrack,
                )
                Spacer(Modifier.height(6.dp))
                TrackOrientationRow(
                    orientation = state.trackOrientation,
                    onTrackOrientationChanged = onTrackOrientationChanged,
                )
            }

            Spacer(Modifier.height(8.dp))
            Text(
                text = if (state.editMode == EditMode.Track) {
                    "\u6162\u8dd1\u901f\u5ea6 ${"%.1f".format(state.speedKmh)} km/h"
                } else {
                    "\u901f\u5ea6 ${state.speedKmh.toInt()} km/h"
                },
                style = MaterialTheme.typography.labelLarge,
            )
            Slider(
                value = state.speedKmh,
                onValueChange = onSpeedChanged,
                valueRange = if (state.editMode == EditMode.Track) 6f..12f else 5f..120f,
                steps = if (state.editMode == EditMode.Track) 11 else 22,
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                PlaybackMode.entries.forEach { mode ->
                    FilterChip(
                        selected = state.playbackMode == mode,
                        onClick = { onPlaybackModeChanged(mode) },
                        label = { Text(mode.displayName()) },
                    )
                }
            }

            Spacer(Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = state.statusText(),
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                when (state.simulationState) {
                    SimulationState.Running -> {
                        IconButton(onClick = onPause) {
                            Icon(Icons.Default.Pause, contentDescription = "\u6682\u505c")
                        }
                    }

                    SimulationState.Paused -> {
                        IconButton(onClick = onResume) {
                            Icon(Icons.Default.PlayArrow, contentDescription = "\u7ee7\u7eed")
                        }
                    }

                    else -> {
                        Button(onClick = onPlay) {
                            Icon(
                                imageVector = if (state.editMode == EditMode.Track) {
                                    Icons.Default.DirectionsRun
                                } else {
                                    Icons.Default.PlayArrow
                                },
                                contentDescription = null,
                            )
                            Spacer(Modifier.width(4.dp))
                            Text(if (state.editMode == EditMode.Track) "\u5f00\u59cb\u8dd1\u6b65" else "\u5f00\u59cb")
                        }
                    }
                }
                Spacer(Modifier.width(8.dp))
                OutlinedButton(onClick = onStop) {
                    Icon(Icons.Default.Stop, contentDescription = null)
                    Spacer(Modifier.width(4.dp))
                    Text("\u505c\u6b62")
                }
            }
        }
    }
}

@Composable
private fun TrackOrientationRow(
    orientation: TrackOrientation,
    onTrackOrientationChanged: (TrackOrientation) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "\u8dd1\u9053\u65b9\u5411",
            style = MaterialTheme.typography.labelLarge,
            maxLines = 1,
        )
        FilterChip(
            selected = orientation == TrackOrientation.Vertical,
            onClick = { onTrackOrientationChanged(TrackOrientation.Vertical) },
            label = { Text("\u7ad6\u5411") },
        )
        FilterChip(
            selected = orientation == TrackOrientation.Horizontal,
            onClick = { onTrackOrientationChanged(TrackOrientation.Horizontal) },
            label = { Text("\u6a2a\u5411") },
        )
    }
}

@Composable
private fun TrackStatusRow(
    trackState: TrackUiState,
    onDetectTrack: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Default.Route, contentDescription = null, modifier = Modifier.size(18.dp))
        Text(
            text = trackState.statusText(),
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        OutlinedButton(
            onClick = onDetectTrack,
            enabled = trackState != TrackUiState.Detecting,
        ) {
            Text(if (trackState == TrackUiState.Detecting) "\u8bc6\u522b\u4e2d" else "\u8bc6\u522b\u64cd\u573a")
        }
    }
}

private fun readinessText(readiness: Readiness): String {
    return if (readiness.ready) {
        if (readiness.hasNotificationPermission) {
            "\u5df2\u51c6\u5907\u597d\u6a21\u62df\u5b9a\u4f4d"
        } else {
            "\u5df2\u51c6\u5907\u597d\uff0c\u5efa\u8bae\u5f00\u542f\u901a\u77e5"
        }
    } else {
        val missing = readiness.missingItems()
            .filterNot { it == "\u901a\u77e5\u6743\u9650" }
            .joinToString("\u3001")
        "\u8fd8\u9700\u8981\uff1a$missing"
    }
}

private fun buildMapStatusText(mapLoaded: Boolean, hasDeviceLocation: Boolean): String {
    val mapText = if (mapLoaded) "\u9ad8\u5fb7\u5e95\u56fe\u5df2\u52a0\u8f7d" else "\u9ad8\u5fb7\u5e95\u56fe\u52a0\u8f7d\u4e2d"
    val locationText = if (hasDeviceLocation) "\u5df2\u5b9a\u4f4d" else "\u5b9a\u4f4d\u4e2d"
    return "$mapText \u00b7 $locationText"
}

private fun PlaybackMode.displayName(): String = when (this) {
    PlaybackMode.Once -> "\u5355\u6b21"
    PlaybackMode.Loop -> "\u5faa\u73af"
    PlaybackMode.PingPong -> "\u5f80\u8fd4"
}

private fun TrackUiState.statusText(): String = when (this) {
    TrackUiState.NotSelected -> "\u70b9\u51fb\u64cd\u573a\u9644\u8fd1\u4f4d\u7f6e"
    is TrackUiState.ReadyToDetect -> "\u70b9\u51fb\u201c\u8bc6\u522b\u64cd\u573a\u201d\u6216\u91cd\u65b0\u70b9\u9009\u9644\u8fd1\u4f4d\u7f6e"
    TrackUiState.Detecting -> "\u6b63\u5728\u8bc6\u522b\u9644\u8fd1\u64cd\u573a"
    is TrackUiState.Detected -> "\u5df2\u8bc6\u522b\uff1a$name"
    is TrackUiState.Failed -> message.ifBlank { "\u672a\u8bc6\u522b\u5230\u64cd\u573a" }
}

private fun MainUiState.statusText(): String = when (val state = simulationState) {
    SimulationState.Idle -> if (editMode == EditMode.Track) "\u70b9\u51fb\u64cd\u573a\u9644\u8fd1\u4f4d\u7f6e" else "\u70b9\u51fb\u5730\u56fe\u9009\u62e9\u4f4d\u7f6e"
    SimulationState.Ready -> when (editMode) {
        EditMode.Track -> trackState.statusText()
        else -> selectedPoint?.let { "%.5f, %.5f".format(it.lat, it.lon) } ?: "\u5df2\u5c31\u7eea"
    }
    SimulationState.Running -> currentPoint?.let {
        "\u6b63\u5728\u79fb\u52a8\uff1a%.5f, %.5f".format(it.lat, it.lon)
    } ?: "\u6b63\u5728\u8f93\u51fa\u6a21\u62df\u5b9a\u4f4d"
    SimulationState.Paused -> "\u5df2\u6682\u505c"
    is SimulationState.Error -> state.message
}
