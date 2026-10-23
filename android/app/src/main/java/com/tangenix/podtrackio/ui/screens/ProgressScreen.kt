package com.tangenix.podtrackio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.width
import androidx.compose.ui.draw.clip
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import com.tangenix.podtrackio.PodTrackioUiState
import com.tangenix.podtrackio.PodTrackioViewModel
import com.tangenix.podtrackio.domain.allAchievements
import com.tangenix.podtrackio.domain.formatDuration
import com.tangenix.podtrackio.domain.todayKey
import com.tangenix.podtrackio.ui.components.EpisodeRow
import com.tangenix.podtrackio.ui.components.MetricCard
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.rounded.WorkspacePremium
import com.tangenix.podtrackio.ui.play.*

import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProgressScreen(ui: PodTrackioUiState, viewModel: PodTrackioViewModel) {
    val stats = ui.snapshot.stats
    val unlocked = stats.unlockedAchievementIds.toSet()
    var displayedMonth by remember { mutableStateOf(YearMonth.now()) }
    var selectedDate by remember { mutableStateOf(LocalDate.now()) }
    var scheduleDay by remember { mutableStateOf(false) }

    val info = remember(ui.snapshot.habitLoop, ui.snapshot.activities, stats) { ui.snapshot.streakInfo() }
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 28.dp, vertical = 16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(24.dp),
            horizontalAlignment = Alignment.Start,
        ) {
            Text("Your progress", style = playType(32))
            Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                Box(Modifier.weight(1f)) { StreakHero(info, {}) }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    LevelCard(stats)
                    LeagueCard(ui.snapshot.habitLoop.league(ui.snapshot.activities))
                }
            }
            MetricsProgressGrid(stats = stats)

            // Learning Calendar - matches macOS LearningCalendarCard
            LearningCalendarCard(
                ui = ui,
                displayedMonth = displayedMonth,
                selectedDate = selectedDate,
                onMonth = { displayedMonth = it },
                onDate = { selectedDate = it },
                onOpen = viewModel::selectPodcast,
                onRemoveSchedule = { viewModel.schedulePodcast(it, null) },
                onAddSchedule = { scheduleDay = true },
            )

            // Achievements - matches macOS AchievementsView
            AchievementsSection(
                achievements = allAchievements,
                unlocked = unlocked,
            )
        }
    }

    if (scheduleDay) ScheduleForDayDialog(
        date = selectedDate,
        podcasts = ui.snapshot.podcasts.filterNot { it.isCompleted },
        onDismiss = { scheduleDay = false },
        onSchedule = { podcastId, hour ->
            val instant = selectedDate.atTime(hour, 0).atZone(ZoneId.systemDefault()).toInstant()
            viewModel.schedulePodcast(podcastId, instant); scheduleDay = false
        },
    )
}

@Composable
private fun MetricsProgressGrid(stats: com.tangenix.podtrackio.domain.UserStats) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(3),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.fillMaxWidth().height(160.dp),
    ) {
        items(listOf(
            ProgressMetricData("Lifetime learning", "${(stats.totalSecondsWatched / 3600).toInt()}h ${(stats.totalSecondsWatched / 60).toInt() % 60}m", "${stats.sessionsCount} sessions", Icons.Rounded.Timer, null),
            ProgressMetricData("Weekly goal", "${(stats.weeklySecondsWatched / 3600).let { "%.1f".format(it) }}h", "of ${stats.weeklyGoalHours.let { "%.1f".format(it) }} hours", Icons.Rounded.Timer, stats.weeklyProgress),
            ProgressMetricData("Completed", "${stats.podcastsCompleted}", "${stats.totalNotesTaken} episodes with notes", Icons.Rounded.CheckCircle, null),
        )) { metric ->
            ProgressMetricCard(metric)
        }
    }
}

@Composable
private fun ProgressMetricCard(metric: ProgressMetricData) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
        shape = RoundedCornerShape(16.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(
            modifier = Modifier.padding(18.dp).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            horizontalAlignment = Alignment.Start,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(metric.icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Text(metric.title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(metric.value, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold))
            Text(metric.detail, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            metric.progress?.let {
                LinearProgressIndicator(progress = it, modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(50.dp)))
            }
        }
    }
}

private data class ProgressMetricData(
    val title: String,
    val value: String,
    val detail: String,
    val icon: androidx.compose.ui.graphics.vector.ImageVector,
    val progress: Float? = null,
)

@Composable
private fun LearningCalendarCard(
    ui: PodTrackioUiState,
    displayedMonth: YearMonth,
    selectedDate: LocalDate,
    onMonth: (YearMonth) -> Unit,
    onDate: (LocalDate) -> Unit,
    onOpen: (String?) -> Unit,
    onRemoveSchedule: (String) -> Unit,
    onAddSchedule: () -> Unit,
) {
    val snapshot = ui.snapshot
    val days = buildList<LocalDate?> {
        val first = displayedMonth.atDay(1)
        repeat(first.dayOfWeek.value % 7) { add(null) }
        (1..displayedMonth.lengthOfMonth()).forEach { add(displayedMonth.atDay(it)) }
        while (size % 7 != 0) add(null)
    }
    val selectedActivity = snapshot.activities.firstOrNull { it.dateKey == selectedDate.toString() }
    val learnedDays = remember(snapshot.habitLoop, snapshot.activities) { snapshot.habitLoop.learningDays(snapshot.activities) }
    val frozenDays = remember(snapshot.habitLoop, snapshot.activities) { snapshot.habitLoop.streak(snapshot.activities).frozenDays }
    val scheduled = snapshot.podcasts.filter { podcast ->
        podcast.scheduledAt?.atZone(ZoneId.systemDefault())?.toLocalDate() == selectedDate && !podcast.isCompleted
    }

    Box(Modifier.fillMaxWidth().chunkyCard(20.dp)) {
        Column(
            modifier = Modifier.padding(18.dp).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Month Header
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    "${displayedMonth.month.name.lowercase().replaceFirstChar { it.uppercase() }} ${displayedMonth.year}",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = { onMonth(displayedMonth.minusMonths(1)) }) { Text("Previous") }
                TextButton(onClick = { onMonth(YearMonth.now()); onDate(LocalDate.now()) }) { Text("Today") }
                TextButton(onClick = { onMonth(displayedMonth.plusMonths(1)) }) { Text("Next") }
            }

            // Weekday Headers
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(0.dp),
            ) {
                listOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat").forEach { day ->
                    Text(day, Modifier.weight(1f).fillMaxWidth(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                }
            }

            // Calendar Grid
            days.chunked(7).forEach { week ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(0.dp),
                ) {
                    week.forEach { date ->
                        if (date == null) {
                            Spacer(Modifier.weight(1f).height(44.dp))
                        } else {
                            val hasSchedule = snapshot.podcasts.any { it.scheduledAt?.atZone(ZoneId.systemDefault())?.toLocalDate() == date && !it.isCompleted }
                            val isSelected = date == selectedDate
                            val isToday = date == LocalDate.now()
                            val key = date.toString()
                            val learned = key in learnedDays
                            val frozen = key in frozenDays
                            Box(Modifier.weight(1f).height(44.dp).clickable { PlayFeedback.play(Cue.SELECT, sound = false); onDate(date) }, contentAlignment = Alignment.Center) {
                                Box(Modifier.size(36.dp).clip(if (frozen) RoundedCornerShape(9.dp) else CircleShape).background(when {
                                    learned -> Palette.flame; frozen -> Palette.ice; else -> Color.Transparent
                                }).then(if (isSelected) Modifier.border(3.dp, MaterialTheme.colorScheme.primary, CircleShape) else if (isToday && !learned) Modifier.border(2.dp, Palette.flame, CircleShape) else Modifier),
                                    contentAlignment = Alignment.Center) {
                                    Text(date.dayOfMonth.toString(), style = playType(13, if (learned || frozen) FontWeight.Black else FontWeight.SemiBold),
                                        color = if (learned || frozen) Color.White else MaterialTheme.colorScheme.onSurface)
                                }
                                if (hasSchedule) Box(Modifier.align(Alignment.BottomCenter).size(6.dp).clip(CircleShape).background(Palette.gem))
                            }
                        }
                    }
                }
            }

            // Selected Day Details
            Text(
                if (selectedActivity == null) "No recorded activity on ${selectedDate.format(DateTimeFormatter.ofPattern("MMM d", Locale.getDefault()))}."
                else "${(selectedActivity.watchedSeconds / 60).roundToInt()} minutes · ${selectedActivity.sessions} sessions · ${selectedActivity.xpEarned} XP",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.fillMaxWidth(),
            )

            // Scheduled for this day
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("Scheduled", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                OutlinedButton(onClick = onAddSchedule) { Text("Add episode") }
            }

            if (scheduled.isEmpty()) {
                Text("Nothing scheduled for this day.", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.fillMaxWidth())
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    scheduled.forEach { podcast ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Text(podcast.title, Modifier.weight(1f), maxLines = 1)
                            TextButton(onClick = { onOpen(podcast.id) }) { Text("Open") }
                            TextButton(onClick = { onRemoveSchedule(podcast.id) }) { Text("Remove") }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AchievementsSection(
    achievements: List<com.tangenix.podtrackio.domain.Achievement>,
    unlocked: Set<String>,
) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Achievements", style = playType(24))
        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.fillMaxWidth().height((190 * ((achievements.size + 2) / 3)).dp),
        ) {
            items(achievements.sortedByDescending { it.id in unlocked }) { achievement ->
                val earned = achievement.id in unlocked
                AchievementCard(achievement = achievement, earned = earned)
            }
        }
    }
}

@Composable
private fun AchievementCard(achievement: com.tangenix.podtrackio.domain.Achievement, earned: Boolean) {
    Column(Modifier.fillMaxWidth().chunkyCard(18.dp).padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(62.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.matchParentSize().padding(top = 4.dp).clip(CircleShape).background(if (earned) Palette.goldLip else Color.Gray.copy(alpha = .25f)))
            Box(Modifier.matchParentSize().padding(bottom = 4.dp).clip(CircleShape).background(if (earned) Palette.gold else Color.Gray.copy(alpha = .15f)), contentAlignment = Alignment.Center) {
                Icon(if (earned) Icons.Rounded.WorkspacePremium else Icons.Rounded.Lock, null, tint = if (earned) Color.White else MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(28.dp))
            }
        }
        Text(achievement.title, style = playType(13), textAlign = androidx.compose.ui.text.style.TextAlign.Center, maxLines = 2)
        Text(achievement.description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.Center, maxLines = 3)
        Text(if (earned) "Unlocked" else "+${achievement.xpReward} XP", style = playType(12), color = if (earned) Palette.success else Palette.goldLip)
    }
}

@Composable
private fun ScheduleForDayDialog(date: LocalDate, podcasts: List<com.tangenix.podtrackio.domain.Podcast>, onDismiss: () -> Unit, onSchedule: (String, Int) -> Unit) {
    var selected by remember { mutableStateOf(podcasts.firstOrNull()?.id) }
    var hour by remember { mutableStateOf(9) }
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Schedule for ${date.format(DateTimeFormatter.ofPattern("MMM d", Locale.getDefault()))}") },
        text = { Column(Modifier.verticalScroll(rememberScrollState())) {
            podcasts.forEach { podcast ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    androidx.compose.material3.RadioButton(selected == podcast.id, { selected = podcast.id })
                    Text(podcast.title, maxLines = 2, modifier = Modifier.weight(1f))
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Start time", Modifier.weight(1f))
                TextButton(onClick = { hour = (hour + 23) % 24 }) { Text("−") }
                Text("%02d:00".format(hour), fontWeight = FontWeight.Bold)
                TextButton(onClick = { hour = (hour + 1) % 24 }) { Text("+") }
            }
        } },
        confirmButton = { Button(enabled = selected != null, onClick = { selected?.let { onSchedule(it, hour) } }) { Text("Schedule") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
