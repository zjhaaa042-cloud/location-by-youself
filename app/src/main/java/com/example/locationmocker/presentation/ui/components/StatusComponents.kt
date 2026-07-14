package com.example.locationmocker.presentation.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.LiveRegionMode
import com.example.locationmocker.presentation.ui.theme.AppElevation
import com.example.locationmocker.presentation.ui.theme.AppIconSize
import com.example.locationmocker.presentation.ui.theme.AppSpacing
import com.example.locationmocker.presentation.ui.theme.appColors

enum class MessageTone {
    Neutral,
    Info,
    Success,
    Warning,
    Error,
    Offline,
    Loading,
}

private data class ToneStyle(
    val container: Color,
    val content: Color,
    val icon: ImageVector,
)

@Composable
private fun toneStyle(tone: MessageTone): ToneStyle = when (tone) {
    MessageTone.Neutral -> ToneStyle(
        MaterialTheme.colorScheme.surfaceVariant,
        MaterialTheme.colorScheme.onSurfaceVariant,
        Icons.Default.Info,
    )
    MessageTone.Info -> ToneStyle(
        MaterialTheme.colorScheme.secondaryContainer,
        MaterialTheme.colorScheme.onSecondaryContainer,
        Icons.Default.Info,
    )
    MessageTone.Success -> ToneStyle(
        MaterialTheme.appColors.successContainer,
        MaterialTheme.appColors.onSuccessContainer,
        Icons.Default.CheckCircle,
    )
    MessageTone.Warning -> ToneStyle(
        MaterialTheme.appColors.warningContainer,
        MaterialTheme.appColors.onWarningContainer,
        Icons.Default.WarningAmber,
    )
    MessageTone.Error -> ToneStyle(
        MaterialTheme.colorScheme.errorContainer,
        MaterialTheme.colorScheme.onErrorContainer,
        Icons.Default.ErrorOutline,
    )
    MessageTone.Offline -> ToneStyle(
        MaterialTheme.colorScheme.errorContainer,
        MaterialTheme.colorScheme.onErrorContainer,
        Icons.Default.CloudOff,
    )
    MessageTone.Loading -> ToneStyle(
        MaterialTheme.colorScheme.secondaryContainer,
        MaterialTheme.colorScheme.onSecondaryContainer,
        Icons.Default.Info,
    )
}

@Composable
fun StatusBadge(
    text: String,
    tone: MessageTone,
    modifier: Modifier = Modifier,
) {
    val style = toneStyle(tone)
    Surface(
        modifier = modifier,
        shape = CircleShape,
        color = style.container,
        contentColor = style.content,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = AppSpacing.sm, vertical = AppSpacing.xs),
            horizontalArrangement = Arrangement.spacedBy(AppSpacing.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (tone == MessageTone.Loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(AppIconSize.compact),
                    strokeWidth = androidx.compose.ui.unit.Dp.Hairline,
                    color = style.content,
                )
            } else {
                Icon(style.icon, contentDescription = null, modifier = Modifier.size(AppIconSize.compact))
            }
            Text(text = text, style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Composable
fun StateMessage(
    title: String,
    message: String,
    tone: MessageTone,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    val style = toneStyle(tone)
    Card(
        modifier = modifier.semantics { liveRegion = LiveRegionMode.Polite },
        colors = CardDefaults.cardColors(containerColor = style.container, contentColor = style.content),
        elevation = CardDefaults.cardElevation(defaultElevation = AppElevation.card),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(AppSpacing.md),
            horizontalArrangement = Arrangement.spacedBy(AppSpacing.sm),
            verticalAlignment = Alignment.Top,
        ) {
            if (tone == MessageTone.Loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(AppIconSize.standard),
                    color = style.content,
                    strokeWidth = androidx.compose.ui.unit.Dp.Hairline,
                )
            } else {
                Icon(style.icon, contentDescription = null, modifier = Modifier.size(AppIconSize.standard))
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleSmall)
                Text(message, style = MaterialTheme.typography.bodySmall)
                if (actionLabel != null && onAction != null) {
                    FilledTonalButton(
                        onClick = onAction,
                        modifier = Modifier.padding(top = AppSpacing.sm),
                    ) {
                        Text(actionLabel)
                    }
                }
            }
        }
    }
}
