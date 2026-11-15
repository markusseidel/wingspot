package site.wingspot.app

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBarItemColors
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.Typography
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

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
    background = Color.White, onBackground = Color(0xFF000000),
    surface = Color.White, onSurface = Color(0xFF000000),
    surfaceVariant = Color(0xFFE5E5EA), onSurfaceVariant = Color(0xFF737378),
    surfaceContainerLowest = Color.White, surfaceContainerLow = Color(0xFFF7F7FA), surfaceContainer = Color(0xFFF2F2F7),
    surfaceContainerHigh = Color(0xFFE9E9EE), surfaceContainerHighest = Color(0xFFF2F2F7),
    outline = Color(0xFFC6C6C8), outlineVariant = Color(0xFFE5E5EA), error = Color(0xFFFF3B30),
)

private val Dark = darkColorScheme(
    primary = Brand.Orange, onPrimary = Color.White,
    primaryContainer = Color(0xFF5A2A0E), onPrimaryContainer = Color(0xFFFFE2D1),
    secondary = Color(0xFF9DB4D6), onSecondary = Brand.Navy,
    secondaryContainer = Brand.Navy, onSecondaryContainer = Color(0xFFE1E6EE),
    tertiary = Color(0xFF0A84FF),
    background = Color.Black, onBackground = Color.White,
    surface = Color(0xFF1C1C1E), onSurface = Color.White,
    surfaceVariant = Color(0xFF2C2C2E), onSurfaceVariant = Color(0xFF9A9AA0),
    surfaceContainerLowest = Color.Black, surfaceContainerLow = Color(0xFF141416), surfaceContainer = Color(0xFF1C1C1E),
    surfaceContainerHigh = Color(0xFF2C2C2E), surfaceContainerHighest = Color(0xFF3A3A3C),
    outline = Color(0xFF38383A), outlineVariant = Color(0xFF38383A), error = Color(0xFFFF453A),
)

@Composable
fun WingspotTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) Dark else Light, typography = WingspotTypography, content = content)
}

/** Like the iPhone app: bold large titles, semibold headings, 17 sp body text. */
private val WingspotTypography = Typography().let { base ->
    base.copy(
        headlineMedium = base.headlineMedium.copy(fontSize = 34.sp, lineHeight = 40.sp, fontWeight = FontWeight.Bold),
        headlineSmall = base.headlineSmall.copy(fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.Bold),
        titleLarge = base.titleLarge.copy(fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.Bold),
        titleMedium = base.titleMedium.copy(fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold),
        titleSmall = base.titleSmall.copy(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold),
        labelLarge = base.labelLarge.copy(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold),
        bodyLarge = base.bodyLarge.copy(fontSize = 17.sp, lineHeight = 22.sp),
        bodyMedium = base.bodyMedium.copy(fontSize = 15.sp, lineHeight = 20.sp),
        bodySmall = base.bodySmall.copy(fontSize = 13.sp, lineHeight = 18.sp),
    )
}

/** The second kind of button in the iPhone app: a light grey pill with orange text. */
@Composable
fun OutlinedButton(
    onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable RowScope.() -> Unit,
) = FilledTonalButton(
    onClick = onClick, modifier = modifier, enabled = enabled, content = content,
    colors = ButtonDefaults.filledTonalButtonColors(
        containerColor = MaterialTheme.colorScheme.surfaceContainerHigh, contentColor = MaterialTheme.colorScheme.primary,
    ),
    contentPadding = PaddingValues(horizontal = 24.dp, vertical = 14.dp),
)

/** A rounded, filled field like the iPhone's, instead of Material's outlined box. */
@Composable
fun OutlinedTextField(
    value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
    label: (@Composable () -> Unit)? = null, placeholder: (@Composable () -> Unit)? = null,
    leadingIcon: (@Composable () -> Unit)? = null, trailingIcon: (@Composable () -> Unit)? = null,
    supportingText: (@Composable () -> Unit)? = null, isError: Boolean = false,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default, keyboardActions: KeyboardActions = KeyboardActions.Default,
    singleLine: Boolean = false, minLines: Int = 1, maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE,
) = TextField(
    value = value, onValueChange = onValueChange, modifier = modifier, enabled = enabled, label = label, placeholder = placeholder,
    leadingIcon = leadingIcon, trailingIcon = trailingIcon, supportingText = supportingText, isError = isError,
    visualTransformation = visualTransformation, keyboardOptions = keyboardOptions, keyboardActions = keyboardActions,
    singleLine = singleLine, minLines = minLines, maxLines = maxLines, shape = RoundedCornerShape(14.dp),
    colors = TextFieldDefaults.colors(
        focusedContainerColor = MaterialTheme.colorScheme.surfaceContainer, unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
        disabledContainerColor = MaterialTheme.colorScheme.surfaceContainer, errorContainerColor = MaterialTheme.colorScheme.surfaceContainer,
        focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent,
        disabledIndicatorColor = Color.Transparent, errorIndicatorColor = Color.Transparent,
    ),
)

/** The tab bar's colours: the selected tab is orange, like on the iPhone. */
@Composable
fun tabColors(): NavigationBarItemColors = NavigationBarItemDefaults.colors(
    selectedIconColor = MaterialTheme.colorScheme.primary, selectedTextColor = MaterialTheme.colorScheme.primary,
    unselectedIconColor = MaterialTheme.colorScheme.onSurface, unselectedTextColor = MaterialTheme.colorScheme.onSurface,
    indicatorColor = MaterialTheme.colorScheme.surfaceContainerHigh,
)

/** A small grey heading above a group, like a section header in an iPhone list. */
@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier) {
    Text(text, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = modifier)
}

/** What a screen shows when there is nothing to show yet: a big grey symbol, a bold line and a grey explanation. */
@Composable
fun EmptyState(icon: Int, title: String, text: String, modifier: Modifier = Modifier, action: (@Composable () -> Unit)? = null) {
    Column(modifier.fillMaxWidth().padding(top = 72.dp, start = 16.dp, end = 16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(painterResource(icon), contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(56.dp))
        Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
        Text(text, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        if (action != null) Column(Modifier.padding(top = 12.dp)) { action() }
    }
}
