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
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.locationmocker.domain.model.PlaybackMode
import com.example.locationmocker.domain.model.SimulationState

@Composable
fun MainScreen(
    viewModel: MainViewModel,
    onRequestPermissions: () -> Unit,
) {
    val uiState by viewModel.uiState.collectAsState()
    var controlsExpanded by rememberSaveable { mutableStateOf(false) }
    var mapLoaded by rememberSaveable { mutableStateOf(false) }

    Box(modifier = Modifier.fillMaxSize()) {
        AmapView(
            points = uiState.points,
            devicePoint = uiState.devicePoint,
            currentPoint = uiState.currentPoint,
            traveledPoints = uiState.traveledPoints,
            routeMode = uiState.editMode == EditMode.Route,
            onMapLoaded = { mapLoaded = true },
            onDeviceLocationChanged = viewModel::onDeviceLocationChanged,
            onMapTapped = viewModel::onMapTapped,
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
                onPlay = viewModel::play,
                onPause = viewModel::pause,
                onResume = viewModel::resume,
                onStop = viewModel::stop,
                onCollapse = { controlsExpanded = false },
                onUndo = viewModel::undoLastPoint,
                onClear = viewModel::clearPoints,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .widthIn(max = 460.dp)
                    .navigationBarsPadding()
                    .padding(start = 12.dp, end = 84.dp, bottom = 12.dp)
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
            )
            Spacer(Modifier.width(6.dp))
            IconButton(onClick = onRefresh, modifier = Modifier.size(32.dp)) {
                Icon(Icons.Default.Refresh, contentDescription = "刷新状态")
            }
        }

        if (!readiness.ready) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (!readiness.hasLocationPermission) {
                    AssistChip(onClick = onRequestPermissions, label = { Text("定位权限") })
                }
                if (!readiness.locationEnabled) {
                    AssistChip(onClick = onOpenLocationSettings, label = { Text("定位服务") })
                }
                if (!readiness.mockAppSelected) {
                    AssistChip(onClick = onOpenDeveloperOptions, label = { Text("模拟位置应用") })
                }
            }
        } else if (!readiness.hasNotificationPermission) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AssistChip(onClick = onRequestPermissions, label = { Text("开启通知") })
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
                        Icon(Icons.Default.Pause, contentDescription = "暂停")
                    }
                }

                SimulationState.Paused -> {
                    IconButton(onClick = onResume) {
                        Icon(Icons.Default.PlayArrow, contentDescription = "继续")
                    }
                }

                else -> {
                    IconButton(onClick = onPlay) {
                        Icon(Icons.Default.PlayArrow, contentDescription = "开始")
                    }
                }
            }

            IconButton(onClick = onStop) {
                Icon(Icons.Default.Stop, contentDescription = "停止")
            }

            Button(onClick = onTogglePanel) {
                Text("控制")
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
        Column(modifier = Modifier.padding(14.dp)) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                FilterChip(
                    selected = state.editMode == EditMode.Fixed,
                    onClick = { onEditModeChanged(EditMode.Fixed) },
                    label = { Text("定点") },
                )
                FilterChip(
                    selected = state.editMode == EditMode.Route,
                    onClick = { onEditModeChanged(EditMode.Route) },
                    label = { Text("路线 ${state.points.size}") },
                )
                Spacer(Modifier.weight(1f))
                IconButton(onClick = onUndo, enabled = state.points.isNotEmpty()) {
                    Icon(Icons.Default.Undo, contentDescription = "撤销上一个点")
                }
                IconButton(onClick = onClear, enabled = state.points.isNotEmpty()) {
                    Icon(Icons.Default.Delete, contentDescription = "清空点位")
                }
                OutlinedButton(onClick = onCollapse) {
                    Text("收起")
                }
            }

            Spacer(Modifier.height(4.dp))
            Text(
                text = "速度 ${state.speedKmh.toInt()} km/h",
                style = MaterialTheme.typography.labelLarge,
            )
            Slider(
                value = state.speedKmh,
                onValueChange = onSpeedChanged,
                valueRange = 5f..120f,
                steps = 22,
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                PlaybackMode.entries.forEach { mode ->
                    FilterChip(
                        selected = state.playbackMode == mode,
                        onClick = { onPlaybackModeChanged(mode) },
                        label = { Text(mode.name) },
                    )
                }
            }

            Spacer(Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = state.statusText(),
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.bodyMedium,
                )
                when (state.simulationState) {
                    SimulationState.Running -> {
                        IconButton(onClick = onPause) {
                            Icon(Icons.Default.Pause, contentDescription = "暂停")
                        }
                    }

                    SimulationState.Paused -> {
                        IconButton(onClick = onResume) {
                            Icon(Icons.Default.PlayArrow, contentDescription = "继续")
                        }
                    }

                    else -> {
                        Button(onClick = onPlay) {
                            Icon(Icons.Default.PlayArrow, contentDescription = null)
                            Spacer(Modifier.width(4.dp))
                            Text("开始")
                        }
                    }
                }
                Spacer(Modifier.width(8.dp))
                OutlinedButton(onClick = onStop) {
                    Icon(Icons.Default.Stop, contentDescription = null)
                    Spacer(Modifier.width(4.dp))
                    Text("停止")
                }
            }
        }
    }
}

private fun readinessText(readiness: Readiness): String {
    return if (readiness.ready) {
        if (readiness.hasNotificationPermission) {
            "已准备好模拟定位"
        } else {
            "已准备好，建议开启通知"
        }
    } else {
        val missing = readiness.missingItems()
            .filterNot { it == "通知权限" }
            .joinToString("、")
        "还需要：$missing"
    }
}

private fun buildMapStatusText(mapLoaded: Boolean, hasDeviceLocation: Boolean): String {
    val mapText = if (mapLoaded) "高德底图已加载" else "高德底图加载中"
    val locationText = if (hasDeviceLocation) "已定位" else "定位中"
    return "$mapText · $locationText"
}

private fun MainUiState.statusText(): String = when (val state = simulationState) {
    SimulationState.Idle -> "点击地图选择位置"
    SimulationState.Ready -> selectedPoint?.let { "%.5f, %.5f".format(it.lat, it.lon) } ?: "已就绪"
    SimulationState.Running -> currentPoint?.let {
        "正在移动：%.5f, %.5f".format(it.lat, it.lon)
    } ?: "正在输出模拟定位"
    SimulationState.Paused -> "已暂停"
    is SimulationState.Error -> state.message
}
