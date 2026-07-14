package com.example.locationmocker.presentation.ui.screens

import android.content.res.Configuration
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.example.locationmocker.BuildConfig
import com.example.locationmocker.domain.model.PlaybackMode
import com.example.locationmocker.domain.track.TrackOrientation
import com.example.locationmocker.presentation.EditMode
import com.example.locationmocker.presentation.MainUiState
import com.example.locationmocker.presentation.Readiness
import com.example.locationmocker.presentation.ui.components.AppTopBar
import com.example.locationmocker.presentation.ui.components.MessageTone
import com.example.locationmocker.presentation.ui.components.PermissionChecklist
import com.example.locationmocker.presentation.ui.components.SimulationPreferenceSections
import com.example.locationmocker.presentation.ui.components.StateMessage
import com.example.locationmocker.presentation.ui.theme.AppElevation
import com.example.locationmocker.presentation.ui.theme.AppSpacing
import com.example.locationmocker.presentation.ui.theme.LocationMockerTheme

@Composable
fun SettingsScreen(
    state: MainUiState,
    onEditModeChanged: (EditMode) -> Unit,
    onSpeedChanged: (Float) -> Unit,
    onPlaybackModeChanged: (PlaybackMode) -> Unit,
    onTrackOrientationChanged: (TrackOrientation) -> Unit,
    onRequestPermissions: () -> Unit,
    onOpenLocationSettings: () -> Unit,
    onOpenDeveloperOptions: () -> Unit,
    onRefreshReadiness: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier,
        topBar = { AppTopBar(title = "设置") },
        containerColor = MaterialTheme.colorScheme.background,
    ) { paddingValues ->
        Box(
            modifier = Modifier.fillMaxSize().padding(paddingValues),
            contentAlignment = Alignment.TopCenter,
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxWidth().widthIn(max = 680.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(AppSpacing.md),
                verticalArrangement = Arrangement.spacedBy(AppSpacing.lg),
            ) {
                item {
                    SettingsGroup(title = "模拟默认值") {
                        SimulationPreferenceSections(
                            state = state,
                            onEditModeChanged = onEditModeChanged,
                            onSpeedChanged = onSpeedChanged,
                            onPlaybackModeChanged = onPlaybackModeChanged,
                            onTrackOrientationChanged = onTrackOrientationChanged,
                        )
                    }
                }

                item {
                    SettingsGroup(title = "权限与系统配置") {
                        PermissionChecklist(
                            readiness = state.readiness,
                            onRequestPermissions = onRequestPermissions,
                            onOpenLocationSettings = onOpenLocationSettings,
                            onOpenDeveloperOptions = onOpenDeveloperOptions,
                        )
                        OutlinedButton(
                            onClick = onRefreshReadiness,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Icon(Icons.Default.Refresh, contentDescription = null)
                            Text("刷新权限状态", modifier = Modifier.padding(start = AppSpacing.xs))
                        }
                    }
                }

                item {
                    StateMessage(
                        title = "安全与使用说明",
                        message = "本应用仅用于开发调试、轨迹验证和个人测试。系统会标记模拟位置；应用不会隐藏模拟定位、绕过安全检测或规避第三方服务限制。",
                        tone = MessageTone.Info,
                    )
                }

                item {
                    SettingsGroup(title = "关于") {
                        Text("定位模拟器", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "版本 ${BuildConfig.VERSION_NAME}",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            "界面会跟随系统切换亮色或深色主题。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SettingsGroup(
    title: String,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.xs)) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        Card(
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            elevation = CardDefaults.cardElevation(defaultElevation = AppElevation.card),
        ) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(AppSpacing.md),
                verticalArrangement = Arrangement.spacedBy(AppSpacing.md),
                content = content,
            )
        }
    }
}

@Preview(name = "设置页 - 320dp", widthDp = 320, heightDp = 640, showBackground = true)
@Preview(
    name = "设置页 - 横屏深色",
    widthDp = 640,
    heightDp = 360,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
    showBackground = true,
)
@Composable
private fun SettingsScreenPreview() {
    LocationMockerTheme {
        SettingsScreen(
            state = MainUiState(
                readiness = Readiness(
                    hasLocationPermission = true,
                    locationEnabled = false,
                    mockAppSelected = false,
                ),
            ),
            onEditModeChanged = {},
            onSpeedChanged = {},
            onPlaybackModeChanged = {},
            onTrackOrientationChanged = {},
            onRequestPermissions = {},
            onOpenLocationSettings = {},
            onOpenDeveloperOptions = {},
            onRefreshReadiness = {},
        )
    }
}
