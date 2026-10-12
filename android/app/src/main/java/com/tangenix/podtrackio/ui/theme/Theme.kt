package com.tangenix.podtrackio.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val PodOrange = Color(0xFFF36B32)
val PodOrangeSoft = Color(0xFFFFDCCB)
val Ink = Color(0xFF201A17)
val Canvas = Color(0xFFFFF8F5)
val Night = Color(0xFF181210)
val NightSurface = Color(0xFF241C19)

private val LightColors = lightColorScheme(
    primary = PodOrange,
    onPrimary = Color.White,
    primaryContainer = PodOrangeSoft,
    onPrimaryContainer = Color(0xFF391000),
    secondary = Color(0xFF755747),
    background = Canvas,
    surface = Color(0xFFFFF8F5),
    surfaceVariant = Color(0xFFF5DED4),
    onBackground = Ink,
    onSurface = Ink,
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFFFFB690),
    onPrimary = Color(0xFF5B1B00),
    primaryContainer = Color(0xFF7C2D0B),
    onPrimaryContainer = PodOrangeSoft,
    secondary = Color(0xFFE4BEAA),
    background = Night,
    surface = NightSurface,
    surfaceVariant = Color(0xFF51443E),
    onBackground = Color(0xFFF4DFD7),
    onSurface = Color(0xFFF4DFD7),
)

private fun themedLight(primary: Color, primaryContainer: Color, background: Color) = lightColorScheme(
    primary = primary,
    onPrimary = Color.White,
    primaryContainer = primaryContainer,
    onPrimaryContainer = Ink,
    secondary = primary.copy(alpha = .82f),
    background = background,
    surface = background,
    surfaceVariant = primaryContainer.copy(alpha = .72f),
    onBackground = Ink,
    onSurface = Ink,
)

private val OceanColors = themedLight(Color(0xFF147AC7), Color(0xFFBDE9F4), Color(0xFFDEF3FA))
private val OrchidColors = themedLight(Color(0xFF7A45D1), Color(0xFFE2C9F3), Color(0xFFF3E7FA))
private val ForestColors = themedLight(Color(0xFF1F8559), Color(0xFFC7E7C7), Color(0xFFE3F4E5))
private val SunsetColors = themedLight(Color(0xFFE04D3B), Color(0xFFF8C9AA), Color(0xFFFFE9DC))
private val MidnightColors = darkColorScheme(
    primary = Color(0xFF919CFF), onPrimary = Color(0xFF11163C),
    primaryContainer = Color(0xFF303875), onPrimaryContainer = Color(0xFFE0E3FF),
    secondary = Color(0xFFB8C1FF), background = Color(0xFF0F1229), surface = Color(0xFF1A2042),
    surfaceVariant = Color(0xFF30385F), onBackground = Color(0xFFE5E6F5), onSurface = Color(0xFFE5E6F5),
)

@Composable
fun PodTrackioTheme(preference: String = "system", content: @Composable () -> Unit) {
    val colors = when (preference) {
        "ocean" -> OceanColors
        "orchid" -> OrchidColors
        "forest" -> ForestColors
        "sunset" -> SunsetColors
        "midnight" -> MidnightColors
        "dark" -> DarkColors // Migrates the first Android prototype preference.
        "light" -> LightColors
        else -> if (isSystemInDarkTheme()) DarkColors else LightColors
    }
    MaterialTheme(
        colorScheme = colors,
        typography = androidx.compose.material3.Typography(),
        content = content,
    )
}
