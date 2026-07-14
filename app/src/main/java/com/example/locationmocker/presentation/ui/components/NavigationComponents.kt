@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.example.locationmocker.presentation.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Map
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector
import com.example.locationmocker.presentation.ui.theme.AppElevation

enum class AppDestination(
    val label: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector,
) {
    Map("地图", Icons.Filled.Map, Icons.Outlined.Map),
    Saved("保存", Icons.Filled.Bookmark, Icons.Outlined.BookmarkBorder),
    Settings("设置", Icons.Filled.Settings, Icons.Outlined.Settings),
    Search("搜索", Icons.Filled.Map, Icons.Outlined.Map),
}

@Composable
fun AppBottomNavigation(
    current: AppDestination,
    onSelect: (AppDestination) -> Unit,
) {
    NavigationBar(tonalElevation = AppElevation.floating) {
        listOf(AppDestination.Map, AppDestination.Saved, AppDestination.Settings).forEach { destination ->
            val selected = current == destination
            NavigationBarItem(
                selected = selected,
                onClick = { onSelect(destination) },
                icon = {
                    Icon(
                        imageVector = if (selected) destination.selectedIcon else destination.unselectedIcon,
                        contentDescription = null,
                    )
                },
                label = { Text(destination.label) },
                alwaysShowLabel = true,
                colors = NavigationBarItemDefaults.colors(
                    indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                ),
            )
        }
    }
}

@Composable
fun AppTopBar(
    title: String,
    onBack: (() -> Unit)? = null,
) {
    TopAppBar(
        title = { Text(title) },
        navigationIcon = {
            if (onBack != null) {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                }
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = MaterialTheme.colorScheme.surface,
            scrolledContainerColor = MaterialTheme.colorScheme.surface,
        ),
    )
}
