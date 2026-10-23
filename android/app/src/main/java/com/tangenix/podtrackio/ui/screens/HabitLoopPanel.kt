package com.tangenix.podtrackio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.tangenix.podtrackio.PodTrackioUiState
import com.tangenix.podtrackio.PodTrackioViewModel
import com.tangenix.podtrackio.domain.DistractionCue
import com.tangenix.podtrackio.domain.RecallReview
import com.tangenix.podtrackio.domain.StreakMilestones
import com.tangenix.podtrackio.ui.play.*
import java.time.LocalDate

@Composable
fun HabitLoopPanel(ui: PodTrackioUiState, viewModel: PodTrackioViewModel) {
    val state = ui.snapshot
    val loop = state.habitLoop
    val day = LocalDate.now().toString()
    val info = remember(loop, state.activities, state.stats) { state.streakInfo() }
    var details by remember { mutableStateOf(false) }
    var streakOpen by remember { mutableStateOf(false) }
    var review by remember { mutableStateOf<RecallReview?>(null) }
    LaunchedEffect(ui.habitMessage) {
        val message = ui.habitMessage ?: return@LaunchedEffect
        if (message.startsWith("Quest complete") || message.startsWith("Review complete")) { PlayFeedback.play(Cue.SUCCESS, sound = false); PlayFeedback.sound(com.tangenix.podtrackio.R.raw.pop) }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        StreakHero(info, { streakOpen = true })
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            val done = loop.questCount(day)
            ChunkyTile({ details = true }, radius = 14.dp) {
                Row(Modifier.padding(horizontal = 12.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(if (done == 3) Icons.Rounded.Redeem else Icons.Rounded.Assignment, null, tint = if (done == 3) Palette.gold else Palette.flame)
                    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(if (done == 3) "All quests done!" else "${3 - done} quest${if (3 - done == 1) "" else "s"} left today", style = playType(14))
                        PlayProgressBar(done / 3f, Modifier.width(130.dp), Palette.gold, 9.dp)
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            val next = state.podcasts.firstOrNull { it.hasProgress } ?: state.podcasts.firstOrNull { !it.isCompleted }
            if (!info.protected && next != null) ChunkyButton(if (info.atRisk) "Save streak" else "Learn now", {
                viewModel.startRescue(next.id, kotlin.math.ceil((loop.goalSeconds(day) - loop.learnedSeconds(day)) / 60).toInt().coerceAtLeast(1), DistractionCue.TODAY)
            }, kind = if (info.atRisk) ChunkyKind.FLAME else ChunkyKind.PRIMARY, small = true, fullWidth = false, icon = Icons.Rounded.PlayArrow)
        }
        ui.habitMessage?.takeUnless { it.startsWith("Quest complete") || it.startsWith("Daily chest") }?.let { message ->
            Row(Modifier.fillMaxWidth().chunkyCard(14.dp, lip = 2.dp).padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(message, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                IconButton(viewModel::dismissHabitMessage) { Icon(Icons.Rounded.Close, "Dismiss") }
            }
        }
    }
    if (details) QuestsDialog(ui, viewModel, onReview = { review = it }) { details = false }
    if (streakOpen) StreakDetailDialog(info) { streakOpen = false }
    review?.let { cached ->
        val stage = cached.dueStage()
        if (stage != null) PlayQuiz(if (stage == 0) "First recall" else "Day $stage review", cached.questions, onFinish = { correct ->
            viewModel.finishRecall(cached.id, stage, correct); review = null
        }, onClose = { review = null })
    }
}

@Composable
private fun QuestsDialog(ui: PodTrackioUiState, viewModel: PodTrackioViewModel, onReview: (RecallReview) -> Unit, onDismiss: () -> Unit) {
    val state = ui.snapshot
    val loop = state.habitLoop
    val day = LocalDate.now().toString()
    val info = state.streakInfo()
    Dialog(onDismissRequest = onDismiss) {
        Surface(shape = RoundedCornerShape(28.dp), color = MaterialTheme.colorScheme.surface) {
            Column(Modifier.padding(22.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Daily quests", Modifier.weight(1f), style = playType(22))
                    IconButton(onDismiss) { Icon(Icons.Rounded.Close, "Close") }
                }
                val seconds = loop.learnedSeconds(day)
                listOf(Triple("Learn for five minutes", Icons.Rounded.Headphones, (seconds / 300).toFloat()),
                    Triple("Complete today's goal", Icons.Rounded.TrackChanges, info.goalProgress),
                    Triple("Recall or capture a takeaway", Icons.Rounded.Lightbulb, if (loop.has("reflection/$day")) 1f else 0f)).forEachIndexed { index, (title, icon, progress) ->
                    val complete = loop.has("quest/$day/${index + 1}/xp")
                    Row(Modifier.fillMaxWidth().chunkyCard(16.dp, lip = 3.dp).padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).background(if (complete) Palette.success else Palette.flame), contentAlignment = Alignment.Center) {
                            Icon(if (complete) Icons.Rounded.Check else icon, null, tint = Color.White)
                        }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(title, style = playType(15, FontWeight.Bold))
                            PlayProgressBar(if (complete) 1f else progress.coerceIn(0f, 1f), tint = if (complete) Palette.success else Palette.gold, height = 10.dp)
                        }
                        Text(if (complete) "Done" else "+10 XP", style = playType(12), color = if (complete) Palette.success else Palette.goldLip)
                    }
                }
                Text(if (loop.has("chest/$day")) "Today's chest is open" else "Finish all three to open today's chest", style = playType(14, FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
                HorizontalDivider()
                LeagueCard(loop.league(state.activities))
                Text("${info.freezes}/2 freezes · ${(loop.boostSeconds / 60).toInt()} boosted minutes left", style = playType(14, FontWeight.Bold))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ChunkyButton("Refill freeze · 100", { viewModel.purchaseHabitItem("freeze") }, kind = ChunkyKind.GEM, small = true, fullWidth = false, enabled = loop.gems >= 100 && info.freezes < 2)
                    val wager = loop.activeWager(day)
                    val currentWager = wager != null && LocalDate.now() < LocalDate.parse(wager.day).plusDays(7)
                    ChunkyButton("7-day promise · 20", { viewModel.purchaseHabitItem("wager") }, kind = ChunkyKind.FLAME, small = true, fullWidth = false, enabled = loop.gems >= 20 && !currentWager)
                }
                Text("Seven actual learning days return 40 gems. Missing a day loses the stake; freezes do not satisfy the promise. Purchases need account sync.", style = MaterialTheme.typography.bodySmall)
                HorizontalDivider()
                Text("Optional recall", style = playType(16))
                loop.reviews.filter { it.dueStage() != null }.forEach { cached ->
                    ChunkyButton("Review: ${state.podcasts.firstOrNull { it.id == cached.podcastID }?.title ?: "Cached episode"}", { onReview(cached); onDismiss() }, kind = ChunkyKind.SUCCESS, small = true)
                }
                val next = ui.selectedPodcast ?: state.podcasts.firstOrNull { !it.isCompleted } ?: state.podcasts.firstOrNull()
                if (next != null) TextButton(onClick = { viewModel.generateRecall(next.id) }, enabled = !ui.recallBusy && loop.reviews.none { it.podcastID == next.id }) {
                    Text(if (ui.recallBusy) "Preparing source-backed questions…" else "Create review: ${next.title}")
                }
                loop.badges.take(12).forEach { Text("✦ ${it.detail}", style = playType(13, FontWeight.Bold), color = Palette.goldLip) }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Celebration sounds", Modifier.weight(1f))
                    Switch(checked = loop.soundsEnabled, onCheckedChange = { viewModel.setHabitFeedback(it, loop.hapticsEnabled) })
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Haptics", Modifier.weight(1f))
                    Switch(checked = loop.hapticsEnabled, onCheckedChange = { viewModel.setHabitFeedback(loop.soundsEnabled, it) })
                }
            }
        }
    }
}

/** Full streak page: flame, milestone ladder, freezes and a personal streak-goal pledge. */
@Composable
private fun StreakDetailDialog(info: StreakInfo, onDismiss: () -> Unit) {
    val prefs = LocalContext.current.getSharedPreferences("play", android.content.Context.MODE_PRIVATE)
    var goal by remember { mutableIntStateOf(prefs.getInt("streakGoal", 0)) }
    val count = info.count
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.widthIn(max = 560.dp).fillMaxWidth(.92f), shape = RoundedCornerShape(28.dp), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.padding(22.dp).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                StreakFlame(info.flame, 120.dp)
                RollingNumber(count, 64, Palette.flame)
                Text("day streak · longest ${info.longest}", style = playType(16, FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
                EchoSays(if (info.atRisk) EchoMood.WORRIED else if (info.protected) EchoMood.PROUD else EchoMood.HAPPY,
                    when { info.atRisk -> "Your flame is flickering. ${(info.goalMinutes - info.watchedMinutes).coerceAtLeast(1)} minutes saves it."; count == 0 -> "Every legendary streak started at day one."
                        else -> "${StreakMilestones.next(count) - count} more days to your ${StreakMilestones.next(count)}-day badge!" }, size = 72.dp)
                Box(Modifier.fillMaxWidth().chunkyCard().padding(14.dp)) { WeekStrip(info.days) }
                Column(Modifier.fillMaxWidth().chunkyCard().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    val next = StreakMilestones.next(count); val previous = StreakMilestones.previous(count)
                    Text("NEXT MILESTONE · $next DAYS", style = playType(13), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
                    PlayProgressBar((count - previous).toFloat() / (next - previous).coerceAtLeast(1), tint = Palette.gold)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        StreakMilestones.all.forEach { m ->
                            Text("$m", Modifier.weight(1f).clip(RoundedCornerShape(50)).background(if (count >= m) Palette.gold else Color.Gray.copy(alpha = .12f)).padding(vertical = 6.dp),
                                style = playType(12), color = if (count >= m) Color.White else MaterialTheme.colorScheme.onSurface.copy(alpha = .5f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                        }
                    }
                }
                Column(Modifier.fillMaxWidth().chunkyCard().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("STREAK GOAL", style = playType(13), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
                    if (goal > 0) {
                        Text(if (count >= goal) "Goal smashed: $goal days!" else "Committed to $goal days", style = playType(17))
                        PlayProgressBar(count.coerceAtMost(goal).toFloat() / goal, tint = Palette.flame)
                    } else {
                        Text("People who commit to a streak goal are far more likely to keep going. Pick yours.", style = MaterialTheme.typography.bodyMedium)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            listOf(7, 14, 30, 50).forEach { g ->
                                ChunkyButton("$g", { goal = maxOf(g, count + 1); prefs.edit().putInt("streakGoal", goal).apply(); PlayFeedback.play(Cue.SUCCESS); PlayFeedback.sound(com.tangenix.podtrackio.R.raw.pop) },
                                    Modifier.weight(1f), kind = if (g == 14) ChunkyKind.FLAME else ChunkyKind.SECONDARY, small = true)
                            }
                        }
                    }
                }
                Row(Modifier.fillMaxWidth().chunkyCard().padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    repeat(2) { i ->
                        Box(Modifier.size(52.dp).clip(RoundedCornerShape(14.dp)).background(if (i < info.freezes) Palette.ice else Color.Gray.copy(alpha = .1f)), contentAlignment = Alignment.Center) {
                            Icon(Icons.Rounded.AcUnit, null, tint = if (i < info.freezes) Color.White else Color.Gray)
                        }
                    }
                    Column(Modifier.weight(1f)) {
                        Text("${info.freezes}/2 freezes equipped", style = playType(16))
                        Text("A freeze covers a missed day automatically. Every 7 learning days refills one.", style = MaterialTheme.typography.bodySmall)
                    }
                }
                ChunkyButton("Done", onDismiss)
            }
        }
    }
}
