package site.wingspot.app

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** The colours of the iPhone app: the orange accent of the app icon on the system's neutral backgrounds, with its navy. */
object Brand {
    val Orange = Color(0xFFFF6B1A)
    val Navy = Color(0xFF0B1F3A)
}

private val Light = lightColorScheme(
    primary = Brand.Orange, onPrimary = Color.White,
    primaryContainer = Color(0xFFFFE2D1), onPrimaryContainer = Brand.Navy,
    secondary = Brand.Navy, onSecondary = Color.White,
    secondaryContainer = Color(0xFFE1E6EE), onSecondaryContainer = Brand.Navy,
    tertiary = Color(0xFF007AFF),
    background = Color(0xFFF2F2F7), onBackground = Color(0xFF000000),
    surface = Color.White, onSurface = Color(0xFF000000),
    surfaceVariant = Color(0xFFE5E5EA), onSurfaceVariant = Color(0xFF3C3C43),
    outline = Color(0xFFC6C6C8), error = Color(0xFFFF3B30),
)

private val Dark = darkColorScheme(
    primary = Brand.Orange, onPrimary = Color.White,
    primaryContainer = Color(0xFF5A2A0E), onPrimaryContainer = Color(0xFFFFE2D1),
    secondary = Color(0xFF9DB4D6), onSecondary = Brand.Navy,
    secondaryContainer = Brand.Navy, onSecondaryContainer = Color(0xFFE1E6EE),
    tertiary = Color(0xFF0A84FF),
    background = Color.Black, onBackground = Color.White,
    surface = Color(0xFF1C1C1E), onSurface = Color.White,
    surfaceVariant = Color(0xFF2C2C2E), onSurfaceVariant = Color(0xFFEBEBF5),
    outline = Color(0xFF38383A), error = Color(0xFFFF453A),
)

@Composable
fun WingspotTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) Dark else Light, content = content)
}
