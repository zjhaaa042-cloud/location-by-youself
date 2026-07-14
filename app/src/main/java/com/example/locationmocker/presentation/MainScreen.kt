@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.example.locationmocker.presentation

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Divider
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

        TopStatusCard(
            readiness = uiState.readiness,
            mapLoaded = mapLoaded,
            hasDeviceLocation = uiState.devicePoint != null,
            onRequestPermissions = onRequestPermissions,
            onOpenLocationSettings = viewModel::openLocationSettings,
            onOpenDeveloperOptions = viewModel::openDeveloperOptions,
            onRefresh = viewModel::refreshReadiness,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .statusBarsPadding()
                .padding(horizontal = 12.dp, vertical = 10.dp)
                .widthIn(max = 620.dp)
                .fillMaxWidth(),
        )

        AnimatedVisibility(
            visible = controlsExpanded,
            modifier = Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(initialOffsetY = { it / 3 }) + fadeIn(),
            exit = slideOutVertically(targetOffsetY = { it / 3 }) + fadeOut(),
        ) {
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
                    .navigationBarsPadding()
                    .padding(start = 12.dp, end = 12.dp, bottom = 92.dp)
                    .widthIn(max = 620.dp)
                    .fillMaxWidth(),
            )
        }

        PlaybackDock(
            state = uiState,
            expanded = controlsExpanded,
            onPlay = viewModel::play,
            onPause = viewModel::pause,
            onResume = viewModel::resume,
            onStop = viewModel::stop,
            onTogglePanel = { controlsExpanded = !controlsExpanded },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(12.dp)
                .widthIn(max = 620.dp)
                .fillMaxWidth(),
        )
    }
}

@Composable
private fun TopStatusCard(
    readiness: Readiness,
    mapLoaded: Boolean,
    hasDeviceLocation: Boolean,
    onRequestPermissions: () -> Unit,
    onOpenLocationSettings: () -> Unit,
    onOpenDeveloperOptions: () -> Unit,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(20.dp),
        shadowElevation = 8.dp,
        tonalElevation = 3.dp,
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f),
    ) {
        Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Surface(
                    shape = CircleShape,
                    color = if (readiness.ready) {
                        MaterialTheme.colorScheme.primaryContainer
                    } else {
                        MaterialTheme.colorScheme.errorContainer
                    },
                ) {
                    Icon(
                        imageVector = if (readiness.ready) Icons.Default.CheckCircle else Icons.Default.WarningAmber,
                        contentDescription = null,
                        tint = if (readiness.ready) {
                            MaterialTheme.colorScheme.onPrimaryContainer
                        } else {
                            MaterialTheme.colorScheme.onErrorContainer
                        },
                        modifier = Modifier.padding(8.dp).size(20.dp),
                    )
                }
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = readinessText(readiness),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = buildMapStatusText(mapLoaded, hasDeviceLocation),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                IconButton(onClick = onRefresh) {
                    Icon(Icons.Default.Refresh, contentDescription = "刷新状态")
                }
            }

            if (!readiness.ready || !readiness.hasNotificationPermission) {
                Spacer(Modifier.height(8.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (!readiness.hasLocationPermission) {
                        AssistChip(onClick = onRequestPermissions, label = { Text("授予定位权限") })
                    }
                    if (!readiness.locationEnabled) {
                        AssistChip(onClick = onOpenLocationSettings, label = { Text("开启定位服务") })
                    }
                    if (!readiness.mockAppSelected) {
                        AssistChip(onClick = onOpenDeveloperOptions, label = { Text("选择模拟位置应用") })
                    }
                    if (readiness.ready && !readiness.hasNotificationPermission) {
                        AssistChip(onClick = onRequestPermissions, label = { Text("开启通知") })
                    }
                }
            }
        }
    }
}

@Composable
private fun PlaybackDock(
    state: MainUiState,
    expanded: Boolean,
    onPlay: () -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onStop: () -> Unit,
    onTogglePanel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(22.dp),
        shadowElevation = 10.dp,
        tonalElevation = 5.dp,
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.97f),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Surface(
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.colorScheme.secondaryContainer,
            ) {
                Icon(
                    imageVector = modeIcon(state.editMode),
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSecondaryContainer,
                    modifier = Modifier.padding(9.dp).size(20.dp),
                )
            }
            Spacer(Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = state.statusText(),
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = "${modeName(state.editMode)} · ${speedLabel(state)}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            when (state.simulationState) {
                SimulationState.Running -> FilledIconButton(onClick = onPause) {
                    Icon(Icons.Default.Pause, contentDescription = "暂停")
                }
                SimulationState.Paused -> FilledIconButton(onClick = onResume) {
                    Icon(Icons.Default.PlayArrow, contentDescription = "继续")
                }
                else -> FilledIconButton(onClick = onPlay) {
                    Icon(Icons.Default.PlayArrow, contentDescription = "开始")
                }
            }
            IconButton(onClick = onStop) {
                Icon(Icons.Default.Stop, contentDescription = "停止")
            }
            IconButton(onClick = onTogglePanel) {
                Icon(
                    imageVector = if (expanded) Icons.Default.ExpandMore else Icons.Default.Tune,
                    contentDescription = if (expanded) "收起控制面板" else "展开控制面板",
                )
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
        shape = RoundedCornerShape(24.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.98f),
        shadowElevation = 12.dp,
        tonalElevation = 5.dp,
    ) {
        Column(
            modifier = Modifier
                .heightIn(max = 480.dp)
                .verticalScroll(rememberScrollState())
                .padding(18.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "模拟控制",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = "选择模式并调整移动参数",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                IconButton(onClick = onCollapse) {
                    Icon(Icons.Default.ExpandMore, contentDescription = "收起")
                }
            }

            Spacer(Modifier.height(14.dp))
            SectionLabel("模拟方式")
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FilterChip(
                    selected = state.editMode == EditMode.Fixed,
                    onClick = { onEditModeChanged(EditMode.Fixed) },
                    label = { Text("定点") },
                    leadingIcon = { Icon(Icons.Default.LocationOn, null, Modifier.size(16.dp)) },
                )
                FilterChip(
                    selected = state.editMode == EditMode.Route,
                    onClick = { onEditModeChanged(EditMode.Route) },
                    label = { Text("路线 ${state.points.size}") },
                    leadingIcon = { Icon(Icons.Default.Route, null, Modifier.size(16.dp)) },
                )
                FilterChip(
                    selected = state.editMode == EditMode.Track,
                    onClick = { onEditModeChanged(EditMode.Track) },
                    label = { Text("操场") },
                    leadingIcon = { Icon(Icons.AutoMirrored.Filled.DirectionsRun, null, Modifier.size(16.dp)) },
                )
            }

            if (state.editMode == EditMode.Track) {
                Spacer(Modifier.height(12.dp))
                TrackStatusRow(trackState = state.trackState, onDetectTrack = onDetectTrack)
                Spacer(Modifier.height(8.dp))
                TrackOrientationRow(
                    orientation = state.trackOrientation,
                    onTrackOrientationChanged = onTrackOrientationChanged,
                )
            }

            Spacer(Modifier.height(16.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionLabel("移动速度", modifier = Modifier.weight(1f))
                Text(
                    text = speedLabel(state),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Bold,
                )
            }
            Slider(
                value = state.speedKmh,
                onValueChange = onSpeedChanged,
                valueRange = if (state.editMode == EditMode.Track) 6f..12f else 5f..120f,
                steps = if (state.editMode == EditMode.Track) 11 else 22,
            )

            SectionLabel("播放方式")
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                PlaybackMode.entries.forEach { mode ->
                    FilterChip(
                        selected = state.playbackMode == mode,
                        onClick = { onPlaybackModeChanged(mode) },
                        label = { Text(mode.displayName()) },
                    )
                }
            }

            Spacer(Modifier.height(14.dp))
            Divider(color = MaterialTheme.colorScheme.outlineVariant)
            Spacer(Modifier.height(10.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedButton(
                    onClick = onUndo,
                    enabled = state.points.isNotEmpty() && state.editMode != EditMode.Track,
                ) {
                    Icon(Icons.AutoMirrored.Filled.Undo, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("撤销")
                }
                OutlinedButton(onClick = onClear, enabled = state.points.isNotEmpty()) {
                    Icon(Icons.Default.DeleteOutline, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("清空")
                }
                Spacer(Modifier.width(4.dp))
                when (state.simulationState) {
                    SimulationState.Running -> Button(onClick = onPause) {
                        Icon(Icons.Default.Pause, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("暂停")
                    }
                    SimulationState.Paused -> Button(onClick = onResume) {
                        Icon(Icons.Default.PlayArrow, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("继续")
                    }
                    else -> Button(onClick = onPlay) {
                        Icon(modeIcon(state.editMode), null, Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(if (state.editMode == EditMode.Track) "开始跑步" else "开始")
                    }
                }
                OutlinedButton(onClick = onStop) {
                    Icon(Icons.Default.Stop, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("停止")
                }
            }
        }
    }
}

@Composable
private fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        modifier = modifier,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        fontWeight = FontWeight.SemiBold,
    )
}

@Composable
private fun TrackOrientationRow(
    orientation: TrackOrientation,
    onTrackOrientationChanged: (TrackOrientation) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SectionLabel("跑道方向")
        FilterChip(
            selected = orientation == TrackOrientation.Vertical,
            onClick = { onTrackOrientationChanged(TrackOrientation.Vertical) },
            label = { Text("竖向") },
        )
        FilterChip(
            selected = orientation == TrackOrientation.Horizontal,
            onClick = { onTrackOrientationChanged(TrackOrientation.Horizontal) },
            label = { Text("横向") },
        )
    }
}

@Composable
private fun TrackStatusRow(trackState: TrackUiState, onDetectTrack: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 12.dp, end = 8.dp, top = 6.dp, bottom = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Default.Route,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Text(
                text = trackState.statusText(),
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.bodySmall,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            OutlinedButton(onClick = onDetectTrack, enabled = trackState != TrackUiState.Detecting) {
                Text(if (trackState == TrackUiState.Detecting) "识别中" else "识别操场")
            }
        }
    }
}

private fun modeIcon(mode: EditMode) = when (mode) {
    EditMode.Fixed -> Icons.Default.LocationOn
    EditMode.Route -> Icons.Default.Route
    EditMode.Track -> Icons.AutoMirrored.Filled.DirectionsRun
}

private fun modeName(mode: EditMode): String = when (mode) {
    EditMode.Fixed -> "定点模式"
    EditMode.Route -> "路线模式"
    EditMode.Track -> "操场模式"
}

private fun speedLabel(state: MainUiState): String = if (state.editMode == EditMode.Track) {
    "%.1f km/h".format(state.speedKmh)
} else {
    "${state.speedKmh.toInt()} km/h"
}

private fun readinessText(readiness: Readiness): String = if (readiness.ready) {
    if (readiness.hasNotificationPermission) "模拟定位已就绪" else "已就绪，建议开启通知"
} else {
    val missing = readiness.missingItems().filterNot { it == "通知权限" }.joinToString("、")
    "还需要：$missing"
}

private fun buildMapStatusText(mapLoaded: Boolean, hasDeviceLocation: Boolean): String {
    val mapText = if (mapLoaded) "地图已加载" else "地图加载中"
    val locationText = if (hasDeviceLocation) "设备已定位" else "正在定位"
    return "$mapText · $locationText"
}

private fun PlaybackMode.displayName(): String = when (this) {
    PlaybackMode.Once -> "单次"
    PlaybackMode.Loop -> "循环"
    PlaybackMode.PingPong -> "往返"
}

private fun TrackUiState.statusText(): String = when (this) {
    TrackUiState.NotSelected -> "点击操场附近位置"
    is TrackUiState.ReadyToDetect -> "点击“识别操场”或重新点选附近位置"
    TrackUiState.Detecting -> "正在识别附近操场"
    is TrackUiState.Detected -> "已识别：$name"
    is TrackUiState.Failed -> message.ifBlank { "未识别到操场" }
}

private fun MainUiState.statusText(): String = when (val state = simulationState) {
    SimulationState.Idle -> if (editMode == EditMode.Track) "点击操场附近位置" else "点击地图选择位置"
    SimulationState.Ready -> when (editMode) {
        EditMode.Track -> trackState.statusText()
        else -> selectedPoint?.let { "%.5f, %.5f".format(it.lat, it.lon) } ?: "已就绪"
    }
    SimulationState.Running -> currentPoint?.let {
        "正在移动：%.5f, %.5f".format(it.lat, it.lon)
    } ?: "正在输出模拟定位"
    SimulationState.Paused -> "已暂停"
    is SimulationState.Error -> state.message
}
