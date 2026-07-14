package com.example.locationmocker.presentation.ui.screens

import android.content.res.Configuration
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.presentation.ui.components.AppTopBar
import com.example.locationmocker.presentation.ui.components.CoordinateCard
import com.example.locationmocker.presentation.ui.components.MessageTone
import com.example.locationmocker.presentation.ui.components.StateMessage
import com.example.locationmocker.presentation.ui.theme.AppSpacing
import com.example.locationmocker.presentation.ui.theme.LocationMockerTheme

@Composable
fun SearchScreen(
    points: List<RoutePoint>,
    onCoordinateSelected: (RoutePoint) -> Unit,
    onBack: () -> Unit,
    onOpenMap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var query by rememberSaveable { mutableStateOf("") }
    var errorMessage by rememberSaveable { mutableStateOf<String?>(null) }
    val focusManager = LocalFocusManager.current

    fun submit() {
        val result = parseCoordinateInput(query)
        errorMessage = result.error
        result.point?.let {
            focusManager.clearFocus()
            onCoordinateSelected(it)
        }
    }

    Scaffold(
        modifier = modifier,
        topBar = { AppTopBar(title = "搜索与坐标", onBack = onBack) },
        containerColor = MaterialTheme.colorScheme.background,
    ) { paddingValues ->
        Box(
            modifier = Modifier.fillMaxSize().padding(paddingValues),
            contentAlignment = Alignment.TopCenter,
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxWidth().widthIn(max = 680.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(AppSpacing.md),
                verticalArrangement = Arrangement.spacedBy(AppSpacing.md),
            ) {
                item {
                    StateMessage(
                        title = "输入经纬度快速定位",
                        message = "当前版本支持坐标定位；地点名称结果需要搜索服务提供，本页面不会展示未经查询的地点。",
                        tone = MessageTone.Info,
                    )
                }

                item {
                    Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.sm)) {
                        OutlinedTextField(
                            value = query,
                            onValueChange = {
                                query = it
                                if (errorMessage != null) errorMessage = null
                            },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("纬度, 经度") },
                            placeholder = { Text("39.9042, 116.4074") },
                            leadingIcon = { Icon(Icons.Default.MyLocation, contentDescription = null) },
                            trailingIcon = {
                                if (query.isNotEmpty()) {
                                    IconButton(onClick = {
                                        query = ""
                                        errorMessage = null
                                    }) {
                                        Icon(Icons.Default.Clear, contentDescription = "清空坐标输入")
                                    }
                                }
                            },
                            isError = errorMessage != null,
                            supportingText = {
                                Text(errorMessage ?: "支持英文逗号、中文逗号或空格分隔")
                            },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Decimal,
                                imeAction = ImeAction.Search,
                            ),
                            keyboardActions = KeyboardActions(onSearch = { submit() }),
                        )
                        Button(
                            onClick = { submit() },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Icon(Icons.Default.MyLocation, contentDescription = null)
                            Text("在地图中定位", modifier = Modifier.padding(start = AppSpacing.xs))
                        }
                    }
                }

                item {
                    Text("最近选点", style = MaterialTheme.typography.titleMedium)
                }

                if (points.isEmpty()) {
                    item {
                        StateMessage(
                            title = "暂无选点记录",
                            message = "输入坐标，或返回地图直接点击一个位置。",
                            tone = MessageTone.Neutral,
                            actionLabel = "返回地图选点",
                            onAction = onOpenMap,
                        )
                    }
                } else {
                    itemsIndexed(points.asReversed()) { reversedIndex, point ->
                        val originalIndex = points.lastIndex - reversedIndex
                        CoordinateCard(
                            title = if (points.size == 1) "最近选择" else "路线点 ${originalIndex + 1}",
                            point = point,
                            supportingText = "点击后在地图中定位",
                            onClick = { onCoordinateSelected(point) },
                        )
                    }
                }
            }
        }
    }
}
@Preview(name = "搜索页 - 320dp", widthDp = 320, heightDp = 640, showBackground = true)
@Preview(
    name = "搜索页 - 横屏深色",
    widthDp = 640,
    heightDp = 360,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
    showBackground = true,
)
@Composable
private fun SearchScreenPreview() {
    LocationMockerTheme {
        SearchScreen(
            points = listOf(RoutePoint(39.9042, 116.4074)),
            onCoordinateSelected = {},
            onBack = {},
            onOpenMap = {},
        )
    }
}
