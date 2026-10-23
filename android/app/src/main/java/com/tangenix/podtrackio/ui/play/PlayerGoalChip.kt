package com.tangenix.podtrackio.ui.play

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

/** Live daily-goal ring for the player; each credited minute floats a "+1 XP" with a tick. */
@Composable
fun PlayerGoalChip(info: StreakInfo, modifier: Modifier = Modifier) {
    val ring = remember { Animatable(0f) }
    LaunchedEffect(info.goalProgress) { ring.animateTo(info.goalProgress, tween(500)) }
    val floaters = remember { mutableStateListOf<Int>() }
    var previous by remember { mutableIntStateOf(info.watchedMinutes) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(info.watchedMinutes) {
        if (info.watchedMinutes > previous) {
            PlayFeedback.play(Cue.TICK, sound = false)
            val id = info.watchedMinutes
            floaters += id
            scope.launch { kotlinx.coroutines.delay(1200); floaters -= id }
        }
        previous = info.watchedMinutes
    }
    val tint = if (info.protected) Palette.success else Palette.flame
    Box(modifier) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.size(28.dp), contentAlignment = Alignment.Center) {
                val track = if (isDarkSurface()) Color.White.copy(alpha = .1f) else Color(0xFFE5E5E5)
                Canvas(Modifier.fillMaxSize()) {
                    drawArc(track, 0f, 360f, false, style = Stroke(4.dp.toPx()))
                    drawArc(tint, -90f, 360f * ring.value, false, style = Stroke(4.dp.toPx(), cap = StrokeCap.Round))
                }
                Icon(if (info.protected) Icons.Rounded.Check else Icons.Rounded.LocalFireDepartment, null, tint = tint, modifier = Modifier.size(13.dp))
            }
            Text(if (info.protected) "Goal done" else "${info.watchedMinutes}/${info.goalMinutes} min", style = playType(14))
        }
        floaters.forEach { id ->
            key(id) {
                val rise = remember { Animatable(0f) }
                LaunchedEffect(Unit) { rise.animateTo(1f, tween(1100)) }
                Text("+1 XP", style = playType(13), color = Palette.goldLip,
                    modifier = Modifier.align(Alignment.TopEnd).graphicsLayer { translationY = -34 * rise.value * density; alpha = 1 - rise.value })
            }
        }
    }
}
