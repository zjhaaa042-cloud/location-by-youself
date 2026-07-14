package com.example.locationmocker.presentation.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.locationmocker.presentation.MainUiState
import com.example.locationmocker.presentation.ui.components.LocationSearchBar
import com.example.locationmocker.presentation.ui.components.MessageTone
import com.example.locationmocker.presentation.ui.components.PermissionBanner
import com.example.locationmocker.presentation.ui.components.SimulationControlPanel
import com.example.locationmocker.presentation.ui.components.StateMessage
import com.example.locationmocker.presentation.ui.components.StatusBadge
import com.example.locationmocker.presentation.ui.theme.AppSpacing
import com.example.locationmocker.presentation.ui.theme.AppLayout

@Composable
fun MapHomeOverlay(
    state: MainUiState,
    mapLoaded: Boolean,
    mapLoadSlow: Boolean,
    wasStopped: Boolean,
    contentPadding: PaddingValues,
    onSearch: () -> Unit,
    onLocateDevice: () -> Unit,
    onRequestPermissions: () -> Unit,
    onOpenLocationSettings: () -> Unit,
    onOpenDeveloperOptions: () -> Unit,
    onPlay: () -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onStop: () -> Unit,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val compactHeight = maxHeight < AppLayout.compactLandscapeHeight
        val landscape = maxWidth > maxHeight
        val topAlignment = if (compactHeight && landscape) Alignment.TopStart else Alignment.TopCenter
        val bottomAlignment = if (compactHeight && landscape) Alignment.BottomEnd else Alignment.BottomCenter
        val topMaxWidth = if (compactHeight && landscape) {
            AppLayout.compactSearchWidth
        } else {
            AppLayout.maxMapOverlayWidth
        }
        val controlMaxWidth = if (compactHeight && landscape) {
            AppLayout.compactControlWidth
        } else {
            AppLayout.maxMapOverlayWidth
        }

        Column(
            modifier = Modifier
                .align(topAlignment)
                .statusBarsPadding()
                .padding(horizontal = AppSpacing.sm, vertical = AppSpacing.xs)
                .widthIn(max = topMaxWidth)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.xs),
        ) {
            LocationSearchBar(onClick = onSearch, modifier = Modifier.fillMaxWidth())
            if (mapLoadSlow && !mapLoaded) {
                StateMessage(
                    title = "地图加载异常",
                    message = "请检查网络连接和高德地图服务配置；网络恢复后页面会继续等待加载。",
                    tone = MessageTone.Offline,
                )
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(AppSpacing.xs),
                ) {
                    StatusBadge(
                        text = if (mapLoaded) "地图已加载" else "地图加载中",
                        tone = if (mapLoaded) MessageTone.Success else MessageTone.Loading,
                    )
                    StatusBadge(
                        text = if (state.devicePoint != null) "设备已定位" else "正在定位",
                        tone = if (state.devicePoint != null) MessageTone.Info else MessageTone.Loading,
                    )
                }
            }
            if (compactHeight) {
                if (!state.readiness.ready) {
                    StatusBadge(text = "权限未就绪，请前往设置", tone = MessageTone.Warning)
                }
            } else {
                PermissionBanner(
                    readiness = state.readiness,
                    onRequestPermissions = onRequestPermissions,
                    onOpenLocationSettings = onOpenLocationSettings,
                    onOpenDeveloperOptions = onOpenDeveloperOptions,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }

        FilledIconButton(
            onClick = onLocateDevice,
            enabled = state.devicePoint != null,
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .padding(end = AppSpacing.sm)
                .size(48.dp),
        ) {
            Icon(
                imageVector = Icons.Default.MyLocation,
                contentDescription = if (state.devicePoint == null) {
                    "正在获取当前位置"
                } else {
                    "定位到当前位置"
                },
            )
        }

        SimulationControlPanel(
            state = state,
            wasStopped = wasStopped,
            onPlay = onPlay,
            onPause = onPause,
            onResume = onResume,
            onStop = onStop,
            onOpenSettings = onOpenSettings,
            modifier = Modifier
                .align(bottomAlignment)
                .padding(
                    start = AppSpacing.sm,
                    end = AppSpacing.sm,
                    bottom = contentPadding.calculateBottomPadding() + AppSpacing.sm,
                )
                .widthIn(max = controlMaxWidth)
                .fillMaxWidth(),
        )
    }
}
