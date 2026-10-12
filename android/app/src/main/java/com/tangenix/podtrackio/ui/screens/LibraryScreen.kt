package com.tangenix.podtrackio.ui.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import java.time.LocalDateTime
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Schedule
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
import com.tangenix.podtrackio.domain.LearningCategory
import com.tangenix.podtrackio.domain.Podcast
import com.tangenix.podtrackio.domain.formatDuration
import coil3.compose.AsyncImage
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(ui: PodTrackioUiState, viewModel: PodTrackioViewModel, onAdd: () -> Unit) {
    val snapshot = ui.snapshot
    var schedulingPodcast by remember { mutableStateOf<Podcast?>(null) }

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 28.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Filter Bar - matches macOS filterBar with horizontal scroll
        FilterBar(
            ui = ui,
            viewModel = viewModel,
            modifier = Modifier.fillMaxWidth()
        )

        // Content - matches macOS List with .listStyle(.inset)
        if (ui.filteredPodcasts.isEmpty()) {
            ContentUnavailableView(
                title = if (snapshot.podcasts.isEmpty()) "Your library is empty" else "No matching episodes",
                subtitle = if (snapshot.podcasts.isEmpty()) "Add a YouTube episode you genuinely want to learn from." else "Try a different search or category.",
                onAddClick = onAdd,
                showAddButton = snapshot.podcasts.isEmpty(),
            )
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(ui.filteredPodcasts, key = { it.id }) { podcast ->
                    PodcastLibraryRow(
                        podcast = podcast,
                        category = snapshot.categories.firstOrNull { it.id == podcast.categoryId },
                        selected = ui.selectedPodcastId == podcast.id,
                        onClick = { viewModel.selectPodcast(podcast.id) },
                        onScheduleClick = { schedulingPodcast = podcast },
                        onDownloadClick = {
                            val state = snapshot.downloads[podcast.youtubeVideoId]
                            if (state != null) viewModel.deleteDownload(podcast.id)
                            else viewModel.download(podcast.id)
                        },
                        onDeleteClick = { viewModel.removePodcast(podcast.id) },
                        onMarkCompleteClick = { viewModel.markCompleted(podcast.id) },
                        downloadState = snapshot.downloads[podcast.youtubeVideoId],
                        downloadProgress = ui.downloadProgress[podcast.id],
                    )
                }
            }
        }
    }

    // Schedule Dialog - matches macOS SchedulePodcastSheet
    schedulingPodcast?.let { podcast ->
        ScheduleDialog(
            podcast = podcast,
            onDismiss = { schedulingPodcast = null },
            onSelect = { instant ->
                viewModel.schedulePodcast(podcast.id, instant)
                schedulingPodcast = null
            }
        )
    }
}

@Composable
private fun FilterBar(
    ui: PodTrackioUiState,
    viewModel: PodTrackioViewModel,
    modifier: Modifier = Modifier,
) {
    val snapshot = ui.snapshot
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // Search Field - matches macOS searchable
        OutlinedTextField(
            value = ui.search,
            onValueChange = viewModel::setSearch,
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            leadingIcon = { Icon(Icons.Rounded.Search, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
            placeholder = { Text("Search episodes, notes, and categories") },
            label = { Text("Search") },
        )

        // Category/Collection Chips - matches macOS horizontal scrollable filter bar
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            // Categories
            if (snapshot.categories.isNotEmpty()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    FilterChip(
                        selected = ui.selectedCategoryId == null && ui.selectedCollectionId == null,
                        onClick = { viewModel.filterCategory(null) },
                        label = { Text("All") },
                        modifier = Modifier.padding(start = 4.dp),
                    )
                    snapshot.categories.forEach { category ->
                        FilterChip(
                            selected = ui.selectedCategoryId == category.id,
                            onClick = { viewModel.filterCategory(category.id) },
                            label = { Text(category.name) },
                        )
                    }
                }
            }

            // Collections
            if (snapshot.collections.isNotEmpty()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    FilterChip(
                        selected = ui.selectedCollectionId == null,
                        onClick = { viewModel.filterCollection(null) },
                        label = { Text("All Collections") },
                        modifier = Modifier.padding(start = 4.dp),
                    )
                    snapshot.collections.sortedBy { it.sortOrder }.forEach { collection ->
                        FilterChip(
                            selected = ui.selectedCollectionId == collection.id,
                            onClick = { viewModel.filterCollection(collection.id) },
                            label = { Text(collection.title) },
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PodcastLibraryRow(
    podcast: Podcast,
    category: LearningCategory?,
    selected: Boolean,
    onClick: () -> Unit,
    onScheduleClick: () -> Unit,
    onDownloadClick: () -> Unit,
    onDeleteClick: () -> Unit,
    onMarkCompleteClick: () -> Unit,
    downloadState: com.tangenix.podtrackio.domain.DownloadRecord?,
    downloadProgress: Float?,
) {
    val container = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerLow
    val isDownloaded = downloadState != null
    val isDownloading = downloadProgress != null

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 4.dp),
        shape = RoundedCornerShape(12.dp),
        color = container,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Thumbnail - matches macOS 132x74
            AsyncImage(
                model = podcast.thumbnailUrl,
                contentDescription = null,
                modifier = Modifier
                    .size(width = 132.dp, height = 74.dp)
                    .clip(RoundedCornerShape(9.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant),
            )

            // Content - matches macOS VStack
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text(podcast.title, style = MaterialTheme.typography.titleMedium, maxLines = 2, fontWeight = FontWeight.Bold)

                Row(
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    category?.let { cat ->
                        Text("${cat.name}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                    }
                    if (podcast.isCompleted) {
                        Text("Completed", style = MaterialTheme.typography.labelSmall, color = Color(0xFF2E8B57))
                    } else if (podcast.hasProgress) {
                        Text("${(podcast.progress * 100).toInt()}% watched", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    podcast.scheduledAt?.let { scheduledAt ->
                        val formatter = DateTimeFormatter.ofPattern("MMM d, h:mm a").withZone(ZoneId.systemDefault())
                        Text(formatter.format(scheduledAt), style = MaterialTheme.typography.labelSmall, color = Color(0xFFFF8C00))
                    }
                    // Download status
                    when {
                        isDownloading -> Text("Downloading…", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                        isDownloaded -> Text("Offline", style = MaterialTheme.typography.labelSmall, color = Color(0xFF2E8B57))
                        false -> Text("Download failed", style = MaterialTheme.typography.labelSmall, color = Color(0xFFDC2626))
                    }
                }

                if (podcast.hasProgress) {
                    LinearProgressIndicator(
                        progress = podcast.progress,
                        modifier = Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(50.dp)),
                    )
                }
            }

            // Actions - matches macOS trailing buttons
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                IconButton(onClick = onClick) {
                    Icon(Icons.Rounded.PlayArrow, "Open", tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
                }
                if (!podcast.isCompleted) {
                    IconButton(onClick = onMarkCompleteClick) {
                        Icon(Icons.Rounded.CheckCircle, "Mark complete")
                    }
                }
                IconButton(onClick = onScheduleClick) {
                    Icon(Icons.Rounded.Schedule, "Schedule")
                }
                IconButton(onClick = onDownloadClick) {
                    Icon(Icons.Rounded.Download, if (isDownloaded) "Delete download" else "Download")
                }
                IconButton(onClick = onDeleteClick) {
                    Icon(Icons.Rounded.Delete, "Delete", tint = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}

@Composable
private fun ContentUnavailableView(
    title: String,
    subtitle: String,
    onAddClick: () -> Unit,
    showAddButton: Boolean = true,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Icon(Icons.Rounded.PlayArrow, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(48.dp))
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            if (showAddButton) {
                Button(onClick = onAddClick) { Text("Add Episode") }
            }
        }
    }
}

@Composable
private fun ScheduleDialog(podcast: Podcast, onDismiss: () -> Unit, onSelect: (Instant?) -> Unit) {
    val context = LocalContext.current
    val zone = ZoneId.systemDefault()
    val now = LocalDateTime.now()
    val tonight = now.toLocalDate().atTime(20, 0).let { if (it.isAfter(now)) it else it.plusDays(1) }.atZone(zone).toInstant()
    val tomorrow = now.toLocalDate().plusDays(1).atTime(9, 0).atZone(zone).toInstant()
    val weekend = generateSequence(now.toLocalDate()) { it.plusDays(1) }.first { it.dayOfWeek.value == 6 }.atTime(10, 0).atZone(zone).toInstant()
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (podcast.scheduledAt == null) "Schedule Podcast" else "Reschedule Podcast") },
        text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(podcast.title, maxLines = 2)
            listOf("Tonight at 8" to tonight, "Tomorrow at 9" to tomorrow, "Saturday at 10" to weekend).forEach { (label, value) ->
                OutlinedButton(onClick = { onSelect(value) }, Modifier.fillMaxWidth()) { Text(label) }
            }
            OutlinedButton(
                onClick = {
                    val initial = podcast.scheduledAt?.atZone(zone)?.toLocalDateTime() ?: now.plusHours(1)
                    DatePickerDialog(context, { _, year, month, day ->
                        TimePickerDialog(context, { _, hour, minute ->
                            onSelect(LocalDateTime.of(year, month + 1, day, hour, minute).atZone(zone).toInstant())
                        }, initial.hour, initial.minute, false).show()
                    }, initial.year, initial.monthValue - 1, initial.dayOfMonth).show()
                },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Choose date and time") }
            if (podcast.scheduledAt != null) TextButton(onClick = { onSelect(null) }) { Text("Remove schedule") }
        } },
        confirmButton = { },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
