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
import com.tangenix.podtrackio.ui.components.EpisodeRow
import com.tangenix.podtrackio.ui.components.MetricCard
import coil3.compose.AsyncImage
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale

@Composable
fun TodayScreen(ui: PodTrackioUiState, viewModel: PodTrackioViewModel, onAdd: () -> Unit) {
    val snapshot = ui.snapshot
    val today = snapshot.activities.firstOrNull { it.dateKey == todayKey() }
    val resume = snapshot.podcasts.filter { it.hasProgress }.sortedByDescending { it.lastWatchedDate }.take(1)
    val scheduled = snapshot.podcasts.filter { !it.isCompleted && it.scheduledAt != null }.sortedBy { it.scheduledAt }.take(1)
    val nextPodcast = (resume + scheduled).distinctBy { it.id }.firstOrNull()
    var rescue by remember { mutableStateOf(false) }

    // Compute rescue insights from focus commitments
    val rescueInsights = computeRescueInsights(snapshot.focusCommitments)

    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 28.dp, vertical = 28.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(28.dp),
            horizontalAlignment = Alignment.Start
        ) {
            // Header - matches macOS header
            TodayHeader(
                todayRemainingMinutes = ((snapshot.stats.dailyGoalMinutes * 60 - (today?.watchedSeconds ?: snapshot.stats.dailySecondsWatched)) / 60).coerceAtLeast(0.0).toInt(),
                isComplete = (today?.watchedSeconds ?: snapshot.stats.dailySecondsWatched) >= snapshot.stats.dailyGoalMinutes * 60
            )

            // Rescue Card - matches macOS rescueCard
            RescueCard(
                insights = rescueInsights,
                hasNextPodcast = nextPodcast != null,
                onRescueClick = { rescue = true }
            )

            // Next Episode - matches macOS nextEpisode
            nextPodcast?.let { podcast ->
                NextEpisodeCard(
                    podcast = podcast,
                    category = snapshot.categories.firstOrNull { it.id == podcast.categoryId },
                    onResume = { viewModel.selectPodcast(podcast.id) },
                    onRescue = {
                        viewModel.startRescue(podcast.id, 5, DistractionCue.TODAY)
                    }
                )
            } ?: ContentUnavailableView(
                title = "Build your learning queue",
                subtitle = "Add an educational episode to begin.",
                onAddClick = onAdd
            )

            // Metrics Grid - matches macOS LazyVGrid with 3 columns
            MetricsGrid(
                todayWatchedMinutes = ((today?.watchedSeconds ?: snapshot.stats.dailySecondsWatched) / 60).toInt(),
                todayRemainingMinutes = ((snapshot.stats.dailyGoalMinutes * 60 - (today?.watchedSeconds ?: snapshot.stats.dailySecondsWatched)) / 60).coerceAtLeast(0.0).toInt(),
                currentStreak = snapshot.stats.currentStreak,
                dailyGoalMinutes = snapshot.stats.dailyGoalMinutes.toInt(),
                dailyProgress = snapshot.stats.dailyProgress,
                adaptiveEnabled = snapshot.habitSettings.adaptiveBuildUpEnabled
            )

            // Recent Activity - matches macOS recentActivity
            RecentActivitySection(activities = snapshot.activities)
        }
    }

    if (rescue) FocusRescueDialog(
        podcasts = snapshot.podcasts.filterNot { it.isCompleted },
        onDismiss = { rescue = false },
        onStart = { id, minutes, cue -> viewModel.startRescue(id, minutes, cue); rescue = false },
    )
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

@Composable
private fun TodayHeader(
    todayRemainingMinutes: Int,
    isComplete: Boolean,
) {
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(
            LocalDate.now().format(java.time.format.DateTimeFormatter.ofPattern("EEEE, MMMM d", Locale.getDefault())),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            if (isComplete) "Today's learning is complete."
            else "Make the next $todayRemainingMinutes minutes count.",
            style = MaterialTheme.typography.displaySmall.copy(fontWeight = FontWeight.Bold),
        )
    }
}

@Composable
private fun RescueCard(
    insights: RescueInsights,
    hasNextPodcast: Boolean,
    onRescueClick: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
        shape = RoundedCornerShape(18.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Row(
            modifier = Modifier.padding(18.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Box(
                modifier = Modifier.size(34.dp),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Rounded.Bolt,
                    null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(34.dp)
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("About to waste time?", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text("Name the impulse. Replace it with one small learning win.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (insights.attempts > 0) {
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("${insights.completed} kept · ${insights.reclaimedMinutes} min", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
                    Text("replaced this week", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Button(
                onClick = onRescueClick,
                enabled = hasNextPodcast,
                modifier = Modifier.height(40.dp),
            ) {
                Icon(Icons.Rounded.Bolt, null, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Text("Rescue Me")
            }
        }
    }
}

@Composable
private fun NextEpisodeCard(
    podcast: com.tangenix.podtrackio.domain.Podcast,
    category: com.tangenix.podtrackio.domain.LearningCategory?,
    onResume: () -> Unit,
    onRescue: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
        shape = RoundedCornerShape(18.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Row(
            modifier = Modifier.padding(20.dp),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            // Thumbnail
            AsyncImage(
                model = podcast.thumbnailUrl,
                contentDescription = null,
                modifier = Modifier
                    .size(width = 220.dp, height = 124.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant),
            )

            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("UP NEXT", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(podcast.title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), maxLines = 2)
                LinearProgressIndicator(progress = podcast.progress, modifier = Modifier.fillMaxWidth())

                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(onClick = onResume) {
                        Icon(Icons.Rounded.PlayArrow, null, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Resume")
                    }
                    OutlinedButton(onClick = onRescue) {
                        Icon(Icons.Rounded.Timer, null, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Start 5 Minutes")
                    }
                }
            }
            Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
private fun MetricsGrid(
    todayWatchedMinutes: Int,
    todayRemainingMinutes: Int,
    currentStreak: Int,
    dailyGoalMinutes: Int,
    dailyProgress: Float,
    adaptiveEnabled: Boolean,
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(3),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.fillMaxWidth().height(160.dp),
    ) {
        items(listOf(
            TodayMetricData("Today", "$todayWatchedMinutes min", "$todayRemainingMinutes remaining", Icons.Rounded.Timer, dailyProgress),
            TodayMetricData("Streak", "$currentStreak days", "5 minutes keeps it alive", Icons.Rounded.LocalFireDepartment, null),
            TodayMetricData("Daily Goal", "${dailyGoalMinutes} min/day", if (adaptiveEnabled) "Adapts each week" else "Fixed target", Icons.Rounded.PlayArrow, null),
        )) { metric ->
            MetricCard(metric)
        }
    }
}

@Composable
private fun MetricCard(metric: TodayMetricData) {
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

private data class TodayMetricData(
    val title: String,
    val value: String,
    val detail: String,
    val icon: androidx.compose.ui.graphics.vector.ImageVector,
    val progress: Float? = null,
)

@Composable
private fun RecentActivitySection(activities: List<com.tangenix.podtrackio.domain.DailyLearningActivity>) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Recent activity", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        if (activities.isEmpty()) {
            Text("Your accurate daily history begins here.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            activities
                .sortedByDescending { it.dateKey }
                .take(5)
                .forEach { day ->
                    val date = LocalDate.parse(day.dateKey)
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(
                            if (day.goalCompleted) Icons.Rounded.CheckCircle else Icons.Rounded.CheckCircle,
                            null,
                            tint = if (day.goalCompleted) Color(0xFF2E8B57) else MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(date.format(java.time.format.DateTimeFormatter.ofPattern("MMM d", Locale.getDefault())))
                        Spacer(Modifier.weight(1f))
                        Text("${(day.watchedSeconds / 60).toInt()} min · ${day.xpEarned} XP", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
        }
    }
}

@Composable
private fun ContentUnavailableView(title: String, subtitle: String, onAddClick: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
        shape = RoundedCornerShape(18.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Icon(Icons.Rounded.NorthEast, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(48.dp))
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Button(onClick = onAddClick) { Text("Add your first episode") }
        }
    }
}
