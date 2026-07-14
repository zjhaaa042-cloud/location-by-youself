@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.example.locationmocker.presentation.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import com.example.locationmocker.domain.model.PlaybackMode
import com.example.locationmocker.domain.track.TrackOrientation
import com.example.locationmocker.presentation.EditMode
import com.example.locationmocker.presentation.MainUiState
import com.example.locationmocker.presentation.TrackUiState
import com.example.locationmocker.presentation.ui.theme.AppSpacing

@Composable
fun SimulationPreferenceSections(
    state: MainUiState,
    onEditModeChanged: (EditMode) -> Unit,
    onSpeedChanged: (Float) -> Unit,
    onPlaybackModeChanged: (PlaybackMode) -> Unit,
    onTrackOrientationChanged: (TrackOrientation) -> Unit,
) {
    SettingsSection(title = "选点方式") {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(AppSpacing.xs),
        ) {
            ModeChip(
                label = "定点",
                selected = state.editMode == EditMode.Fixed,
                onClick = { onEditModeChanged(EditMode.Fixed) },
                modifier = Modifier.weight(1f),
            )
            ModeChip(
                label = "路线 ${state.points.size}",
                selected = state.editMode == EditMode.Route,
                onClick = { onEditModeChanged(EditMode.Route) },
                modifier = Modifier.weight(1f),
            )
            ModeChip(
                label = "操场",
                selected = state.editMode == EditMode.Track,
                onClick = { onEditModeChanged(EditMode.Track) },
                modifier = Modifier.weight(1f),
            )
        }
    }

    SettingsSection(title = "移动速度", trailing = state.speedLabel()) {
        Slider(
            value = state.speedKmh,
            onValueChange = onSpeedChanged,
            valueRange = if (state.editMode == EditMode.Track) 6f..12f else 5f..120f,
            steps = if (state.editMode == EditMode.Track) 11 else 22,
        )
    }

    SettingsSection(title = "播放方式") {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(AppSpacing.xs),
        ) {
            PlaybackMode.entries.forEach { mode ->
                FilterChip(
                    selected = state.playbackMode == mode,
                    onClick = { onPlaybackModeChanged(mode) },
                    label = { Text(mode.displayName()) },
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }

    if (state.editMode == EditMode.Track) {
        SettingsSection(title = "跑道方向") {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(AppSpacing.xs),
            ) {
                TrackOrientation.entries.forEach { orientation ->
                    FilterChip(
                        selected = state.trackOrientation == orientation,
                        onClick = { onTrackOrientationChanged(orientation) },
                        label = { Text(if (orientation == TrackOrientation.Vertical) "竖向" else "横向") },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

@Composable
private fun ModeChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label, maxLines = 1) },
        modifier = modifier,
    )
}

@Composable
private fun SettingsSection(
    title: String,
    trailing: String? = null,
    content: @Composable () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.xs)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = title,
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (trailing != null) {
                Text(
                    text = trailing,
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
        content()
    }
}

fun TrackUiState.displayText(): String = when (this) {
    TrackUiState.NotSelected -> "请先点击地图上的操场附近位置"
    is TrackUiState.ReadyToDetect -> "位置已选择，可以识别附近操场"
    TrackUiState.Detecting -> "正在分析当前地图画面"
    is TrackUiState.Detected -> "已识别：$name"
    is TrackUiState.Failed -> message.ifBlank { "未识别到操场，请调整地图缩放后重试" }
}

fun MainUiState.speedLabel(): String = if (editMode == EditMode.Track) {
    "%.1f km/h".format(speedKmh)
} else {
    "${speedKmh.toInt()} km/h"
}

fun PlaybackMode.displayName(): String = when (this) {
    PlaybackMode.Once -> "单次"
    PlaybackMode.Loop -> "循环"
    PlaybackMode.PingPong -> "往返"
}
