package com.example.locationmocker.presentation.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat

@Immutable
data class AppSemanticColors(
    val success: Color,
    val onSuccess: Color,
    val successContainer: Color,
    val onSuccessContainer: Color,
    val warning: Color,
    val onWarning: Color,
    val warningContainer: Color,
    val onWarningContainer: Color,
)

private val LightSemanticColors = AppSemanticColors(
    success = Color(0xFF006C4C),
    onSuccess = Color.White,
    successContainer = Color(0xFF8BF8C8),
    onSuccessContainer = Color(0xFF002114),
    warning = Color(0xFF8A5100),
    onWarning = Color.White,
    warningContainer = Color(0xFFFFDDB5),
    onWarningContainer = Color(0xFF2C1600),
)

private val DarkSemanticColors = AppSemanticColors(
    success = Color(0xFF65DBA6),
    onSuccess = Color(0xFF003824),
    successContainer = Color(0xFF005137),
    onSuccessContainer = Color(0xFF8BF8C8),
    warning = Color(0xFFFFB95C),
    onWarning = Color(0xFF492900),
    warningContainer = Color(0xFF683C00),
    onWarningContainer = Color(0xFFFFDDB5),
)

private val LocalAppSemanticColors = staticCompositionLocalOf { LightSemanticColors }

val MaterialTheme.appColors: AppSemanticColors
    @Composable get() = LocalAppSemanticColors.current

private val LightColorScheme = lightColorScheme(
    primary = Color(0xFF006B5C),
    onPrimary = Color.White,
    primaryContainer = Color(0xFF9EF2DC),
    onPrimaryContainer = Color(0xFF00201A),
    secondary = Color(0xFF486A73),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFCBE8F0),
    onSecondaryContainer = Color(0xFF031F26),
    tertiary = Color(0xFF765A00),
    background = Color(0xFFF5FAF7),
    onBackground = Color(0xFF171D1B),
    surface = Color(0xFFF8FBF9),
    onSurface = Color(0xFF171D1B),
    surfaceVariant = Color(0xFFDBE5E1),
    onSurfaceVariant = Color(0xFF3F4945),
    outline = Color(0xFF6F7975),
    outlineVariant = Color(0xFFBFC9C5),
    error = Color(0xFFBA1A1A),
    onError = Color.White,
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF410002),
)

private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFF74D9C5),
    onPrimary = Color(0xFF00382F),
    primaryContainer = Color(0xFF005045),
    onPrimaryContainer = Color(0xFF94F7E0),
    secondary = Color(0xFFA8CDDB),
    onSecondary = Color(0xFF10353E),
    secondaryContainer = Color(0xFF294A56),
    onSecondaryContainer = Color(0xFFCBE8F0),
    tertiary = Color(0xFFE9C349),
    background = Color(0xFF0E1211),
    onBackground = Color(0xFFDEE4E1),
    surface = Color(0xFF101513),
    onSurface = Color(0xFFDEE4E1),
    surfaceVariant = Color(0xFF3F4945),
    onSurfaceVariant = Color(0xFFBFC9C5),
    outline = Color(0xFF89938F),
    outlineVariant = Color(0xFF3F4945),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
)

private val AppTypography = Typography(
    titleLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 22.sp,
        lineHeight = 28.sp,
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp,
        lineHeight = 24.sp,
    ),
    titleSmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 14.sp,
        lineHeight = 20.sp,
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 21.sp,
    ),
    bodySmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 18.sp,
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Medium,
        fontSize = 14.sp,
        lineHeight = 20.sp,
    ),
)

private val AppShapes = Shapes(
    small = androidx.compose.foundation.shape.RoundedCornerShape(8.dp),
    medium = androidx.compose.foundation.shape.RoundedCornerShape(12.dp),
    large = androidx.compose.foundation.shape.RoundedCornerShape(16.dp),
    extraLarge = androidx.compose.foundation.shape.RoundedCornerShape(24.dp),
)

@Composable
fun LocationMockerTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme
    val semanticColors = if (darkTheme) DarkSemanticColors else LightSemanticColors
    val view = LocalView.current

    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = Color.Transparent.toArgb()
            window.navigationBarColor = colorScheme.surface.toArgb()
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !darkTheme
                isAppearanceLightNavigationBars = !darkTheme
            }
        }
    }

    CompositionLocalProvider(LocalAppSemanticColors provides semanticColors) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = AppTypography,
            shapes = AppShapes,
            content = content,
        )
    }
}
