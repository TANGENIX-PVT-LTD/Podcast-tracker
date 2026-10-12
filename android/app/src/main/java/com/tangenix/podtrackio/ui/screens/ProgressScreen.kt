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

import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProgressScreen(ui: PodTrackioUiState, viewModel: PodTrackioViewModel) {
    val stats = ui.snapshot.stats
    val unlocked = stats.unlockedAchievementIds.toSet()
    var displayedMonth by remember { mutableStateOf(YearMonth.now()) }
    var selectedDate by remember { mutableStateOf(LocalDate.now()) }
    var scheduleDay by remember { mutableStateOf(false) }

    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 28.dp, vertical = 16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(24.dp),
            horizontalAlignment = Alignment.Start,
        ) {
            // Header
            Text("Progress", style = MaterialTheme.typography.displaySmall.copy(fontWeight = FontWeight.Bold))

            // Metrics Grid - matches macOS layout
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
    val scheduled = snapshot.podcasts.filter { podcast ->
        podcast.scheduledAt?.atZone(ZoneId.systemDefault())?.toLocalDate() == selectedDate && !podcast.isCompleted
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
        shape = RoundedCornerShape(16.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
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
                            val activity = snapshot.activities.firstOrNull { it.dateKey == date.toString() }
                            val hasSchedule = snapshot.podcasts.any { it.scheduledAt?.atZone(ZoneId.systemDefault())?.toLocalDate() == date && !it.isCompleted }
                            val isSelected = date == selectedDate
                            val isToday = date == LocalDate.now()

                            Surface(
                                modifier = Modifier
                                    .weight(1f)
                                    .height(44.dp)
                                    .clickable { onDate(date) },
                                shape = RoundedCornerShape(11.dp),
                                color = when {
                                    isSelected -> MaterialTheme.colorScheme.primaryContainer
                                    isToday -> MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
                                    else -> Color.Transparent
                                },
                            ) {
                                Column(
                                    modifier = Modifier.fillMaxSize(),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.Center,
                                ) {
                                    Text(
                                        date.dayOfMonth.toString(),
                                        style = if (isSelected) MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold) else MaterialTheme.typography.bodySmall,
                                        color = if (isSelected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface,
                                    )
                                    Text(
                                        (if (activity != null) "●" else "") + (if (hasSchedule) " ●" else ""),
                                        color = if (activity?.goalCompleted == true) Color(0xFF2E8B57) else MaterialTheme.colorScheme.primary,
                                        style = MaterialTheme.typography.labelSmall,
                                    )
                                }
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
        Text("Achievements", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.fillMaxWidth().height((160 * ((achievements.size + 2) / 3)).dp),
        ) {
            items(achievements) { achievement ->
                val earned = achievement.id in unlocked
                AchievementCard(achievement = achievement, earned = earned)
            }
        }
    }
}

@Composable
private fun AchievementCard(achievement: com.tangenix.podtrackio.domain.Achievement, earned: Boolean) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (earned) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f) else MaterialTheme.colorScheme.surfaceContainerLow,
        ),
        shape = RoundedCornerShape(16.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(
            modifier = Modifier.padding(16.dp).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(
                if (earned) Icons.Rounded.Timer else Icons.Rounded.Lock,
                null,
                tint = if (earned) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(32.dp),
            )
            Text(achievement.title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Text(achievement.description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Text(if (earned) "Unlocked" else "+${achievement.xpReward} XP", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
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
