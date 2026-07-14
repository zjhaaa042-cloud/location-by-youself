package com.example.locationmocker.presentation.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.example.locationmocker.presentation.Readiness
import com.example.locationmocker.presentation.ui.theme.AppIconSize
import com.example.locationmocker.presentation.ui.theme.appColors

@Composable
fun PermissionBanner(
    readiness: Readiness,
    onRequestPermissions: () -> Unit,
    onOpenLocationSettings: () -> Unit,
    onOpenDeveloperOptions: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val issue = when {
        !readiness.hasLocationPermission -> Triple(
            "需要定位权限",
            "用于读取设备位置并在地图上显示当前位置。",
            "授权" to onRequestPermissions,
        )
        !readiness.locationEnabled -> Triple(
            "系统定位服务已关闭",
            "开启定位服务后才能获取当前位置。",
            "去开启" to onOpenLocationSettings,
        )
        !readiness.mockAppSelected -> Triple(
            "尚未选择模拟位置应用",
            "请在开发者选项中选择“定位模拟器”。",
            "去设置" to onOpenDeveloperOptions,
        )
        !readiness.hasNotificationPermission -> Triple(
            "建议开启通知",
            "运行时可持续查看前台服务状态。",
            "开启通知" to onRequestPermissions,
        )
        else -> null
    }

    if (issue != null) {
        StateMessage(
            title = issue.first,
            message = issue.second,
            tone = if (readiness.ready) MessageTone.Info else MessageTone.Warning,
            actionLabel = issue.third.first,
            onAction = issue.third.second,
            modifier = modifier,
        )
    }
}

@Composable
fun PermissionChecklist(
    readiness: Readiness,
    onRequestPermissions: () -> Unit,
    onOpenLocationSettings: () -> Unit,
    onOpenDeveloperOptions: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxWidth()) {
        PermissionRow(
            title = "定位权限",
            ready = readiness.hasLocationPermission,
            readyText = "已授权",
            missingText = "未授权",
            actionLabel = "授权",
            onAction = onRequestPermissions,
        )
        Divider()
        PermissionRow(
            title = "系统定位服务",
            ready = readiness.locationEnabled,
            readyText = "已开启",
            missingText = "已关闭",
            actionLabel = "去开启",
            onAction = onOpenLocationSettings,
        )
        Divider()
        PermissionRow(
            title = "模拟位置应用",
            ready = readiness.mockAppSelected,
            readyText = "已选择本应用",
            missingText = "尚未选择",
            actionLabel = "去设置",
            onAction = onOpenDeveloperOptions,
        )
        Divider()
        PermissionRow(
            title = "通知权限",
            ready = readiness.hasNotificationPermission,
            readyText = "已授权",
            missingText = "未授权（不影响核心定位）",
            actionLabel = "授权",
            onAction = onRequestPermissions,
        )
    }
}

@Composable
private fun PermissionRow(
    title: String,
    ready: Boolean,
    readyText: String,
    missingText: String,
    actionLabel: String,
    onAction: () -> Unit,
) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = {
            Text(
                text = if (ready) readyText else missingText,
                color = if (ready) MaterialTheme.appColors.success else MaterialTheme.appColors.warning,
            )
        },
        leadingContent = {
            Icon(
                imageVector = if (ready) Icons.Default.CheckCircle else Icons.Default.WarningAmber,
                contentDescription = null,
                tint = if (ready) MaterialTheme.appColors.success else MaterialTheme.appColors.warning,
                modifier = Modifier.size(AppIconSize.standard),
            )
        },
        trailingContent = {
            if (!ready) {
                TextButton(onClick = onAction) { Text(actionLabel) }
            }
        },
    )
}
