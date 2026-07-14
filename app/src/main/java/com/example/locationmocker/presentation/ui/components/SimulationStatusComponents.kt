package com.example.locationmocker.presentation.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import com.example.locationmocker.domain.model.SimulationState
import com.example.locationmocker.presentation.EditMode
import com.example.locationmocker.presentation.MainUiState
import com.example.locationmocker.presentation.ui.theme.AppElevation
import com.example.locationmocker.presentation.ui.theme.AppIconSize
import com.example.locationmocker.presentation.ui.theme.AppSpacing

@Composable
fun SimulationControlPanel(
    state: MainUiState,
    wasStopped: Boolean,
    onPlay: () -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onStop: () -> Unit,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val presentation = state.simulationPresentation(wasStopped)
    val displayPoint = state.currentPoint ?: state.selectedPoint ?: state.devicePoint

    Card(
        modifier = modifier.semantics { stateDescription = presentation.badgeText },
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = AppElevation.floating),
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(AppSpacing.md)) {
            Column(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(AppSpacing.sm),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        StatusBadge(text = presentation.badgeText, tone = presentation.tone)
                        Spacer(Modifier.height(AppSpacing.xs))
                        Text(
                            text = presentation.message,
                            style = MaterialTheme.typography.bodyMedium,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    IconButton(onClick = onOpenSettings, modifier = Modifier.size(AppSpacing.touch)) {
                        Icon(Icons.Default.Tune, contentDescription = "打开模拟参数")
                    }
                }

                if (displayPoint != null) {
                    Spacer(Modifier.height(AppSpacing.sm))
                    Text(
                        text = when {
                            state.currentPoint != null -> "当前模拟坐标"
                            state.selectedPoint != null -> "已选坐标"
                            else -> "设备坐标"
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = displayPoint.formatCoordinate(),
                        style = MaterialTheme.typography.titleSmall.copy(fontFamily = FontFamily.Monospace),
                        fontWeight = FontWeight.SemiBold,
                    )
                }

                Spacer(Modifier.height(AppSpacing.md))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(AppSpacing.xs),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    when (state.simulationState) {
                        SimulationState.Running -> Button(onClick = onPause, modifier = Modifier.weight(1f)) {
                            Icon(Icons.Default.Pause, contentDescription = null, modifier = Modifier.size(AppIconSize.compact))
                            Spacer(Modifier.width(AppSpacing.xs))
                            Text("暂停模拟")
                        }
                        SimulationState.Paused -> Button(onClick = onResume, modifier = Modifier.weight(1f)) {
                            Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(AppIconSize.compact))
                            Spacer(Modifier.width(AppSpacing.xs))
                            Text("继续模拟")
                        }
                        else -> Button(onClick = onPlay, modifier = Modifier.weight(1f)) {
                            Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(AppIconSize.compact))
                            Spacer(Modifier.width(AppSpacing.xs))
                            Text(if (state.editMode == EditMode.Track) "开始跑步" else "开始模拟")
                        }
                    }
                    if (state.simulationState == SimulationState.Running || state.simulationState == SimulationState.Paused) {
                        OutlinedButton(onClick = onStop) {
                            Icon(Icons.Default.Stop, contentDescription = null, modifier = Modifier.size(AppIconSize.compact))
                            Spacer(Modifier.width(AppSpacing.xs))
                            Text("停止")
                        }
                    }
                }
            }
        }
    }
}

private data class SimulationPresentation(
    val badgeText: String,
    val tone: MessageTone,
    val message: String,
)

private fun MainUiState.simulationPresentation(wasStopped: Boolean): SimulationPresentation = when (val value = simulationState) {
    SimulationState.Idle -> SimulationPresentation(
        badgeText = "未启动",
        tone = MessageTone.Neutral,
        message = if (editMode == EditMode.Track) "点击地图上的操场附近位置" else "搜索坐标或点击地图选择位置",
    )
    SimulationState.Ready -> SimulationPresentation(
        badgeText = if (wasStopped) "已停止" else "等待启动",
        tone = MessageTone.Info,
        message = if (wasStopped) {
            "模拟已停止，已选坐标仍然保留"
        } else {
            when (editMode) {
                EditMode.Fixed -> "位置已选择，可以开始模拟"
                EditMode.Route -> "已选择 ${points.size} 个路线点"
                EditMode.Track -> trackState.displayText()
            }
        },
    )
    SimulationState.Running -> SimulationPresentation(
        badgeText = "运行中",
        tone = MessageTone.Success,
        message = if (editMode == EditMode.Track) "正在输出自然跑步轨迹" else "正在持续输出模拟位置",
    )
    SimulationState.Paused -> SimulationPresentation(
        badgeText = "已暂停",
        tone = MessageTone.Warning,
        message = "当前位置已保留，可以继续或停止模拟",
    )
    is SimulationState.Error -> SimulationPresentation(
        badgeText = if (value.message.contains("定位")) "定位失败" else "无法启动",
        tone = MessageTone.Error,
        message = value.message,
    )
}
