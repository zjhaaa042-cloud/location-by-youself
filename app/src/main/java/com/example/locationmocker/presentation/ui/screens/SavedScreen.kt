package com.example.locationmocker.presentation.ui.screens

import android.content.res.Configuration
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.presentation.ui.components.AppTopBar
import com.example.locationmocker.presentation.ui.components.CoordinateCard
import com.example.locationmocker.presentation.ui.components.MessageTone
import com.example.locationmocker.presentation.ui.components.StateMessage
import com.example.locationmocker.presentation.ui.theme.AppSpacing
import com.example.locationmocker.presentation.ui.theme.LocationMockerTheme

private enum class SavedTab(val label: String) {
    Favorites("收藏地点"),
    History("历史记录"),
}

@Composable
fun SavedScreen(
    points: List<RoutePoint>,
    onOpenMap: () -> Unit,
    onSelectCoordinate: (RoutePoint) -> Unit,
    modifier: Modifier = Modifier,
) {
    var selectedTab by rememberSaveable { mutableIntStateOf(SavedTab.History.ordinal) }

    Scaffold(
        modifier = modifier,
        topBar = { AppTopBar(title = "保存的位置") },
        containerColor = MaterialTheme.colorScheme.background,
    ) { paddingValues ->
        Box(
            modifier = Modifier.fillMaxSize().padding(paddingValues),
            contentAlignment = Alignment.TopCenter,
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxWidth().widthIn(max = 680.dp),
                verticalArrangement = Arrangement.spacedBy(AppSpacing.md),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = AppSpacing.lg),
            ) {
                item {
                    TabRow(selectedTabIndex = selectedTab) {
                        SavedTab.entries.forEachIndexed { index, tab ->
                            Tab(
                                selected = selectedTab == index,
                                onClick = { selectedTab = index },
                                text = { Text(tab.label) },
                            )
                        }
                    }
                }

                if (selectedTab == SavedTab.Favorites.ordinal) {
                    item {
                        StateMessage(
                            title = "还没有收藏地点",
                            message = "当前业务层尚未提供收藏数据源。你仍可以在地图上选点，并在历史记录中快速返回最近坐标。",
                            tone = MessageTone.Neutral,
                            actionLabel = "前往地图选点",
                            onAction = onOpenMap,
                            modifier = Modifier.padding(horizontal = AppSpacing.md),
                        )
                    }
                } else if (points.isEmpty()) {
                    item {
                        StateMessage(
                            title = "暂无历史记录",
                            message = "完成一次地图选点后，最后保留的坐标会显示在这里。",
                            tone = MessageTone.Neutral,
                            actionLabel = "前往地图选点",
                            onAction = onOpenMap,
                            modifier = Modifier.padding(horizontal = AppSpacing.md),
                        )
                    }
                } else {
                    item {
                        Text(
                            text = "最近保留的选点",
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.padding(horizontal = AppSpacing.md),
                        )
                    }
                    item {
                        Text(
                            text = "这些坐标来自当前持久化的定点或路线，不包含时间信息。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = AppSpacing.md),
                        )
                    }
                    itemsIndexed(points.asReversed()) { reversedIndex, point ->
                        val originalIndex = points.lastIndex - reversedIndex
                        CoordinateCard(
                            title = if (points.size == 1) "最近选择" else "路线点 ${originalIndex + 1}",
                            point = point,
                            supportingText = "点击后返回地图定位",
                            onClick = { onSelectCoordinate(point) },
                            modifier = Modifier.padding(horizontal = AppSpacing.md),
                        )
                    }
                }
            }
        }
    }
}

@Preview(name = "保存页 - 320dp", widthDp = 320, heightDp = 640, showBackground = true)
@Preview(
    name = "保存页 - 横屏深色",
    widthDp = 640,
    heightDp = 360,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
    showBackground = true,
)
@Composable
private fun SavedScreenPreview() {
    LocationMockerTheme {
        SavedScreen(
            points = listOf(
                RoutePoint(39.9042, 116.4074),
                RoutePoint(39.9142, 116.4174),
            ),
            onOpenMap = {},
            onSelectCoordinate = {},
        )
    }
}
