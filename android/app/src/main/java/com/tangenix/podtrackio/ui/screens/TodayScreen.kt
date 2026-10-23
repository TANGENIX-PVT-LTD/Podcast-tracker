package com.tangenix.podtrackio.ui.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.ui.draw.clip
import kotlin.math.max
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.NorthEast
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tangenix.podtrackio.PodTrackioUiState
import com.tangenix.podtrackio.PodTrackioViewModel
import com.tangenix.podtrackio.domain.DistractionCue
import com.tangenix.podtrackio.domain.FocusCommitment
import com.tangenix.podtrackio.domain.formatDuration
import com.tangenix.podtrackio.domain.todayKey
import coil3.compose.AsyncImage
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.graphics.graphicsLayer
import com.tangenix.podtrackio.ui.play.*

@Composable
fun TodayScreen(ui: PodTrackioUiState, viewModel: PodTrackioViewModel, onAdd: () -> Unit) {
    val snapshot = ui.snapshot
    val resume = snapshot.podcasts.filter { it.hasProgress && !it.isCompleted }.sortedByDescending { it.lastWatchedDate }
    val nextPodcast = resume.firstOrNull() ?: snapshot.podcasts.filter { !it.isCompleted }.minByOrNull { it.dateAdded }
    var rescue by remember { mutableStateOf(false) }
    val insights = computeRescueInsights(snapshot.focusCommitments)
    val info = remember(snapshot.habitLoop, snapshot.activities, snapshot.stats) { snapshot.streakInfo() }
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }

    BoxWithConstraints(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        val wide = maxWidth > 900.dp
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Column(Modifier.staggered(0, appeared), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(LocalDate.now().format(java.time.format.DateTimeFormatter.ofPattern("EEEE, d MMMM")).uppercase(), style = playType(13),
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = .55f))
                val line = echoLine(info, snapshot.podcasts.isEmpty(), snapshot.habitLoop.questCount(todayKey()))
                EchoSays(line.first, line.second, size = 96.dp)
            }
            if (wide) Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                Column(Modifier.weight(1.3f), verticalArrangement = Arrangement.spacedBy(18.dp)) { PrimaryColumn(ui, viewModel, nextPodcast, insights, appeared, onAdd) { rescue = true } }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(18.dp)) { SecondaryColumn(ui, appeared) }
            } else {
                PrimaryColumn(ui, viewModel, nextPodcast, insights, appeared, onAdd) { rescue = true }
                SecondaryColumn(ui, appeared)
            }
        }
    }

    if (rescue) FocusRescueDialog(
        podcasts = snapshot.podcasts.filterNot { it.isCompleted },
        onDismiss = { rescue = false },
        onStart = { id, minutes, cue -> viewModel.startRescue(id, minutes, cue); rescue = false },
    )
}

/** Echo's line for today: warm, specific, never guilt-tripping. */
private fun echoLine(info: StreakInfo, empty: Boolean, quests: Int): Pair<EchoMood, String> {
    val left = (info.goalMinutes - info.watchedMinutes).coerceAtLeast(0)
    val hour = java.time.LocalTime.now().hour
    return when {
        empty -> EchoMood.HAPPY to "Add one episode you're curious about. I'll keep you company!"
        info.protected && quests < 3 -> EchoMood.PROUD to "Streak safe! ${3 - quests} quest${if (3 - quests == 1) "" else "s"} left, then the chest is yours."
        info.protected -> EchoMood.CHEER to "Everything done today. You're on fire!"
        info.atRisk -> EchoMood.WORRIED to "Just $left minute${if (left == 1) "" else "s"} keeps your ${info.count}-day flame alive. We've got this!"
        info.count == 0 -> EchoMood.HAPPY to "Let's light your first flame. $left minutes is all it takes."
        LocalDate.now().dayOfWeek == java.time.DayOfWeek.MONDAY && hour < 14 -> EchoMood.HAPPY to "Fresh week, fresh league. $left minutes starts it strong."
        hour < 12 -> EchoMood.HAPPY to "Morning! $left minutes keeps your ${info.count}-day streak growing."
        else -> EchoMood.IDLE to "$left minutes to protect day ${info.count + 1}. Ready when you are."
    }
}

@Composable
private fun PrimaryColumn(ui: PodTrackioUiState, viewModel: PodTrackioViewModel, next: com.tangenix.podtrackio.domain.Podcast?, insights: RescueInsights,
                          appeared: Boolean, onAdd: () -> Unit, onRescue: () -> Unit) {
    Box(Modifier.staggered(1, appeared)) { HabitLoopPanel(ui, viewModel) }
    if (next != null) Row(Modifier.staggered(2, appeared).fillMaxWidth().chunkyCard(22.dp).padding(14.dp), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Box {
            AsyncImage(next.thumbnailUrl, next.title, Modifier.width(200.dp).height(112.dp).clip(RoundedCornerShape(14.dp)), contentScale = androidx.compose.ui.layout.ContentScale.Crop)
            Text(if (next.hasProgress) "CONTINUE" else "UP NEXT", Modifier.padding(8.dp).clip(RoundedCornerShape(50)).background(MaterialTheme.colorScheme.primary).padding(horizontal = 8.dp, vertical = 3.dp),
                style = playType(11), color = Color.White)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(next.title, style = playType(19, FontWeight.ExtraBold), maxLines = 2)
            if (next.hasProgress) PlayProgressBar(next.progress.toFloat(), tint = MaterialTheme.colorScheme.primary, height = 10.dp)
            ChunkyButton(if (next.hasProgress) "Continue learning" else "Start learning", { viewModel.selectPodcast(next.id) }, small = true, fullWidth = false, icon = Icons.Rounded.PlayArrow)
        }
    } else Column(Modifier.staggered(2, appeared).fillMaxWidth().chunkyCard(22.dp).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Echo(EchoMood.HAPPY, 110.dp)
        Text("Build your learning queue", style = playType(22))
        ChunkyButton("Add your first episode", onAdd, fullWidth = false, icon = Icons.Rounded.Add)
    }
    Row(Modifier.staggered(3, appeared).fillMaxWidth().chunkyCard(20.dp).padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(Modifier.size(46.dp).clip(RoundedCornerShape(14.dp)).background(Palette.flame), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Bolt, null, tint = Color.White) }
        Column(Modifier.weight(1f)) {
            Text("About to waste time?", style = playType(17))
            Text(if (insights.attempts > 0) "${insights.completed} kept · ${insights.reclaimedMinutes} min reclaimed this week" else "Swap the impulse for one honest 5-minute win.",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
        }
        ChunkyButton("Rescue", onRescue, kind = ChunkyKind.FLAME, small = true, fullWidth = false, enabled = next != null)
    }
}

@Composable
private fun SecondaryColumn(ui: PodTrackioUiState, appeared: Boolean) {
    val snapshot = ui.snapshot
    Box(Modifier.staggered(2, appeared)) { LevelCard(snapshot.stats) }
    Box(Modifier.staggered(3, appeared)) { LeagueCard(snapshot.habitLoop.league(snapshot.activities)) }
    val learned = snapshot.habitLoop.learningDays(snapshot.activities)
    Column(Modifier.staggered(4, appeared).fillMaxWidth().chunkyCard(20.dp).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Recent activity", style = playType(20))
        if (snapshot.activities.isEmpty()) Text("Your accurate daily history begins here.", color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
        snapshot.activities.sortedByDescending { it.dateKey }.take(5).forEach { day ->
            val done = day.dateKey in learned
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.size(28.dp).clip(CircleShape).background(if (done) Palette.flame else Palette.ash), contentAlignment = Alignment.Center) {
                    Icon(if (done) Icons.Rounded.LocalFireDepartment else Icons.Rounded.Bedtime, null, tint = Color.White, modifier = Modifier.size(16.dp))
                }
                Text(day.dateKey, Modifier.weight(1f), style = playType(14, FontWeight.Bold))
                Text("${(maxOf(day.watchedSeconds, snapshot.habitLoop.learnedSeconds(day.dateKey)) / 60).toInt()} min", color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
                Text("+${day.xpEarned} XP", style = playType(13), color = Palette.goldLip)
            }
        }
    }
}

/** Cards rise in one after another on first appearance. */
@Composable
fun Modifier.staggered(index: Int, appeared: Boolean): Modifier {
    val progress by animateFloatAsState(if (appeared) 1f else 0f, spring(dampingRatio = .8f, stiffness = 220f), label = "stagger$index")
    var delayed by remember { mutableStateOf(false) }
    LaunchedEffect(appeared) { if (appeared) { kotlinx.coroutines.delay(index * 60L); delayed = true } }
    val p = if (delayed) progress else 0f
    return this.graphicsLayer { alpha = p; translationY = (1 - p) * 18 * density }
}

private fun computeRescueInsights(commitments: List<FocusCommitment>): RescueInsights {
    val now = Instant.now()
    val weekAgo = now.minusSeconds(7L * 24 * 60 * 60)
    val distractions = commitments.filter { it.cue in setOf(
        DistractionCue.SCROLLING, DistractionCue.STREAMING, DistractionCue.ANIME, DistractionCue.GAMING, DistractionCue.OTHER
    ) && it.createdAt >= weekAgo && it.createdAt < now }
    val completed = distractions.count { it.completedAt != null }
    val reclaimedMinutes = distractions.filter { it.completedAt != null }.sumOf { (it.targetSeconds / 60).toInt() }
    return RescueInsights(attempts = distractions.size, completed = completed, reclaimedMinutes = reclaimedMinutes)
}

data class RescueInsights(
    val attempts: Int,
    val completed: Int,
    val reclaimedMinutes: Int,
)

