package com.example.locationmocker.presentation.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.presentation.ui.theme.AppElevation
import com.example.locationmocker.presentation.ui.theme.AppIconSize
import com.example.locationmocker.presentation.ui.theme.AppSpacing

@Composable
fun LocationSearchBar(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier
            .heightIn(min = AppSpacing.touch)
            .clickable(onClick = onClick),
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface,
        tonalElevation = AppElevation.floating,
        shadowElevation = AppElevation.floating,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = AppSpacing.md, vertical = AppSpacing.sm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Default.Search, contentDescription = null, modifier = Modifier.size(AppIconSize.standard))
            Spacer(Modifier.width(AppSpacing.sm))
            Column(modifier = Modifier.weight(1f)) {
                Text("搜索地点或输入坐标", style = MaterialTheme.typography.bodyMedium)
                Text(
                    "也可以直接点击地图选点",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(Icons.Default.ChevronRight, contentDescription = null)
        }
    }
}

@Composable
fun CoordinateCard(
    title: String,
    point: RoutePoint?,
    modifier: Modifier = Modifier,
    supportingText: String? = null,
    onClick: (() -> Unit)? = null,
) {
    val interactionModifier = if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier
    Card(
        modifier = modifier.then(interactionModifier),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = AppElevation.card),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(AppSpacing.md),
            horizontalArrangement = Arrangement.spacedBy(AppSpacing.sm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Default.LocationOn,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(AppIconSize.standard),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = point?.formatCoordinate() ?: "尚未获取坐标",
                    style = MaterialTheme.typography.titleSmall.copy(fontFamily = FontFamily.Monospace),
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (supportingText != null) {
                    Text(
                        text = supportingText,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (onClick != null) {
                Icon(Icons.Default.ChevronRight, contentDescription = null)
            }
        }
    }
}

fun RoutePoint.formatCoordinate(): String = "%.6f, %.6f".format(lat, lon)
