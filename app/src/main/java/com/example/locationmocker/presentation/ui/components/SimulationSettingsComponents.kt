@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.example.locationmocker.presentation.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Route
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import com.example.locationmocker.domain.model.PlaybackMode
import com.example.locationmocker.domain.track.TrackOrientation
import com.example.locationmocker.presentation.EditMode
import com.example.locationmocker.presentation.MainUiState
import com.example.locationmocker.presentation.TrackUiState
import com.example.locationmocker.presentation.ui.theme.AppIconSize
import com.example.locationmocker.presentation.ui.theme.AppSpacing

@Composable
fun SimulationSettingsSheet(
    state: MainUiState,
    onDismiss: () -> Unit,
    onEditModeChanged: (EditMode) -> Unit,
    onSpeedChanged: (Float) -> Unit,
    onPlaybackModeChanged: (PlaybackMode) -> Unit,
    onTrackOrientationChanged: (TrackOrientation) -> Unit,
    onDetectTrack: () -> Unit,
    onUndo: () -> Unit,
    onClear: () -> Unit,
) {
    var confirmClear by remember { mutableStateOf(false) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(horizontal = AppSpacing.md, vertical = AppSpacing.xs),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.md),
        ) {
            Column {
                Text("模拟参数", style = MaterialTheme.typography.titleLarge)
                Text(
                    "调整选点方式、移动速度和路线播放规则",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            SimulationPreferenceSections(
                state = state,
                onEditModeChanged = onEditModeChanged,
                onSpeedChanged = onSpeedChanged,
                onPlaybackModeChanged = onPlaybackModeChanged,
                onTrackOrientationChanged = onTrackOrientationChanged,
            )

            if (state.editMode == EditMode.Track) {
                TrackDetectionSection(trackState = state.trackState, onDetectTrack = onDetectTrack)
            }

            Divider()
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(AppSpacing.xs),
            ) {
                OutlinedButton(
                    onClick = onUndo,
                    enabled = state.points.isNotEmpty() && state.editMode != EditMode.Track,
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = null, modifier = Modifier.size(AppIconSize.compact))
                    Spacer(Modifier.size(AppSpacing.xs))
                    Text("撤销一点")
                }
                OutlinedButton(
                    onClick = { confirmClear = true },
                    enabled = state.points.isNotEmpty(),
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Default.DeleteOutline, contentDescription = null, modifier = Modifier.size(AppIconSize.compact))
                    Spacer(Modifier.size(AppSpacing.xs))
                    Text("清空选点")
                }
            }
            Spacer(Modifier.size(AppSpacing.sm))
        }
    }

    if (confirmClear) {
        ConfirmActionDialog(
            title = "清空全部选点？",
            message = "当前定点或路线坐标将被移除，此操作无法撤销。",
            confirmLabel = "清空",
            onConfirm = {
                confirmClear = false
                onClear()
            },
            onDismiss = { confirmClear = false },
        )
    }
}

@Composable
private fun TrackDetectionSection(trackState: TrackUiState, onDetectTrack: () -> Unit) {
    StateMessage(
        title = "操场识别",
        message = trackState.displayText(),
        tone = when (trackState) {
            TrackUiState.Detecting -> MessageTone.Loading
            is TrackUiState.Detected -> MessageTone.Success
            is TrackUiState.Failed -> MessageTone.Error
            else -> MessageTone.Info
        },
        actionLabel = if (trackState == TrackUiState.Detecting) null else "识别操场",
        onAction = if (trackState == TrackUiState.Detecting) null else onDetectTrack,
    )
}
