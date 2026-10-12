package com.tangenix.podtrackio.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.tangenix.podtrackio.PodTrackioViewModel
import com.tangenix.podtrackio.data.AuthState
import com.tangenix.podtrackio.domain.AnswerStyle
import com.tangenix.podtrackio.domain.AppSnapshot
import com.tangenix.podtrackio.domain.DistractionCue
import com.tangenix.podtrackio.domain.DownloadQuality
import com.tangenix.podtrackio.domain.LearningCategory
import com.tangenix.podtrackio.domain.PlaylistPreview
import com.tangenix.podtrackio.domain.Podcast
import com.tangenix.podtrackio.domain.TimeOfDay
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

@Composable
fun AddContentDialog(snapshot: AppSnapshot, viewModel: PodTrackioViewModel, onDismiss: () -> Unit) {
    var playlistMode by remember { mutableStateOf(false) }
    var title by remember { mutableStateOf("") }
    var url by remember { mutableStateOf("") }
    var fetchedTitle by remember { mutableStateOf<String?>(null) }
    var titleFetchAttempted by remember { mutableStateOf(false) }
    var category by remember { mutableStateOf(snapshot.categories.firstOrNull()?.id.orEmpty()) }
    var preview by remember { mutableStateOf<PlaylistPreview?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    // Extract video ID from URL input
    val videoId = remember(url) { Podcast.extractVideoId(url) }

    // Fetch video title when video ID changes and we're in single episode mode
    LaunchedEffect(videoId, playlistMode) {
        if (!playlistMode && videoId != null && !titleFetchAttempted) {
            titleFetchAttempted = true
            val titleFromLink = viewModel.fetchVideoTitle(videoId)
            if (titleFromLink != null && titleFromLink.isNotBlank()) {
                fetchedTitle = titleFromLink
                // Only auto-fill if user hasn't manually entered a title yet
                if (title.isBlank()) {
                    title = titleFromLink
                }
            }
        } else if (videoId == null) {
            // Reset when URL is cleared
            titleFetchAttempted = false
            fetchedTitle = null
        }
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        androidx.compose.material3.Card(Modifier.fillMaxWidth(.68f)) {
            Column(Modifier.padding(26.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text("Add to your learning library", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(selected = !playlistMode, onClick = { playlistMode = false; preview = null; titleFetchAttempted = false; fetchedTitle = null }, label = { Text("Single episode") })
                    FilterChip(selected = playlistMode, onClick = { playlistMode = true; preview = null }, label = { Text("YouTube playlist") })
                }
                // Show title field when URL has been entered (videoId extracted) or user has typed a title
                if (!playlistMode && (videoId != null || title.isNotBlank())) {
                    OutlinedTextField(
                        value = title,
                        onValueChange = { title = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Episode title") },
                        singleLine = true,
                    )
                }
                OutlinedTextField(
                    value = url,
                    onValueChange = { url = it; preview = null },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(if (playlistMode) "Playlist URL" else "YouTube URL or video ID") },
                    singleLine = true,
                )
                Text("Category", style = MaterialTheme.typography.labelLarge)
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    snapshot.categories.take(6).forEach { item ->
                        FilterChip(selected = category == item.id, onClick = { category = item.id }, label = { Text(item.name) })
                    }
                }
                if (playlistMode && !viewModel.externalMediaToolsAvailable) {
                    Text("Playlist extraction is available in the full sideload build. This Play-safe build keeps synced playback and AI features but omits external media extraction.", color = MaterialTheme.colorScheme.error)
                }
                preview?.let {
                    Text(it.title, fontWeight = FontWeight.Bold)
                    Text("${it.episodes.size} available episodes${if (it.unavailableCount > 0) " · ${it.unavailableCount} unavailable" else ""}")
                    it.episodes.take(5).forEach { episode -> Text("• ${episode.title}", style = MaterialTheme.typography.bodySmall) }
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onDismiss) { Text("Cancel") }
                    Spacer(Modifier.width(8.dp))
                    Button(
                        enabled = !busy && url.isNotBlank() && (!playlistMode || viewModel.externalMediaToolsAvailable),
                        onClick = {
                            if (!playlistMode) {
                                if (viewModel.addEpisode(title, url, category)) onDismiss()
                            } else if (preview != null) {
                                viewModel.importPlaylist(preview!!, category)
                                onDismiss()
                            } else scope.launch {
                                busy = true; error = null
                                runCatching { viewModel.previewPlaylist(url) }
                                    .onSuccess { preview = it }
                                    .onFailure { error = it.message ?: "Could not read that playlist." }
                                busy = false
                            }
                        },
                    ) { Text(if (busy) "Reading…" else if (playlistMode && preview == null) "Preview playlist" else "Add") }
                }
            }
        }
    }
}

@Composable
fun FocusRescueDialog(podcasts: List<Podcast>, onDismiss: () -> Unit, onStart: (String, Int, DistractionCue) -> Unit) {
    var selected by remember { mutableStateOf(podcasts.firstOrNull()?.id) }
    var minutes by remember { mutableStateOf(10) }
    var cue by remember { mutableStateOf(DistractionCue.SCROLLING) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Rescue my focus") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Make a tiny watch-time promise. Only continuous playback earns progress.")
                podcasts.take(8).forEach { podcast ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected == podcast.id, onClick = { selected = podcast.id })
                        Text(podcast.title, maxLines = 2)
                    }
                }
                Text("Promise: $minutes minutes", fontWeight = FontWeight.Bold)
                Slider(minutes.toFloat(), { minutes = it.roundToInt() }, valueRange = 5f..30f, steps = 4)
                Text("What pulled you away?")
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(DistractionCue.SCROLLING, DistractionCue.STREAMING, DistractionCue.GAMING).forEach { item ->
                        FilterChip(cue == item, { cue = item }, label = { Text(item.name.lowercase().replaceFirstChar(Char::uppercase)) })
                    }
                }
            }
        },
        confirmButton = { Button(enabled = selected != null, onClick = { selected?.let { onStart(it, minutes, cue) } }) { Text("Start promise") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Not now") } },
    )
}

@Composable
fun SettingsDialog(snapshot: AppSnapshot, auth: AuthState, viewModel: PodTrackioViewModel, onDismiss: () -> Unit) {
    var groq by remember { mutableStateOf("") }
    var transcript by remember { mutableStateOf("") }
    var dailyGoal by remember { mutableStateOf(snapshot.stats.dailyGoalMinutes.toFloat()) }
    var weeklyGoal by remember { mutableStateOf(snapshot.stats.weeklyGoalHours.toFloat()) }
    var categoryName by remember { mutableStateOf("") }
    var editingCategory by remember { mutableStateOf<LearningCategory?>(null) }
    var deletingCategory by remember { mutableStateOf<LearningCategory?>(null) }
    val notification = snapshot.notificationPreferences
    val habits = snapshot.habitSettings
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        androidx.compose.material3.Card(Modifier.fillMaxWidth(.72f)) {
            Column(Modifier.padding(28.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Settings", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                        Text(
                            auth.profile?.email ?: auth.profile?.displayName ?: "Local preview",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (auth.isAuthenticated) {
                        OutlinedButton(onClick = viewModel::refreshCloud, enabled = !auth.restoring) { Text("Sync now") }
                        Spacer(Modifier.width(8.dp))
                        TextButton(onClick = viewModel::signOut) { Text("Sign out") }
                    } else {
                        Text("Debug fixture · no cloud writes", style = MaterialTheme.typography.labelMedium)
                    }
                }
                HorizontalDivider()
                Text("Appearance", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text("The same six PodTrackio themes, rendered with Android Material color roles.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("system" to "System", "ocean" to "Ocean", "orchid" to "Orchid", "forest" to "Forest", "sunset" to "Sunset", "midnight" to "Midnight").forEach { (value, label) ->
                        FilterChip(snapshot.theme == value, { viewModel.setTheme(value) }, label = { Text(label) })
                    }
                }
                Text("Goals", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text("Daily: ${dailyGoal.roundToInt()} minutes")
                Slider(dailyGoal, { dailyGoal = it }, valueRange = 5f..120f, steps = 22, onValueChangeFinished = { viewModel.setDailyGoal(dailyGoal.toDouble()) })
                Text("Weekly: ${"%.1f".format(weeklyGoal)} hours")
                Slider(weeklyGoal, { weeklyGoal = it }, valueRange = 1f..20f, steps = 18, onValueChangeFinished = { viewModel.setWeeklyGoal(weeklyGoal.toDouble()) })
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Adaptive build-up", fontWeight = FontWeight.SemiBold)
                        Text("After five successful days, next week's daily target rises by ${habits.buildUpStepMinutes.roundToInt()} minutes up to ${habits.targetDailyGoalMinutes.roundToInt()}.", style = MaterialTheme.typography.bodySmall)
                    }
                    Switch(habits.adaptiveBuildUpEnabled, { viewModel.setHabitSettings(habits.copy(adaptiveBuildUpEnabled = it)) })
                }
                Text("Long-term daily target: ${habits.targetDailyGoalMinutes.roundToInt()} minutes")
                Slider(
                    habits.targetDailyGoalMinutes.toFloat(),
                    { viewModel.setHabitSettings(habits.copy(targetDailyGoalMinutes = it.toDouble())) },
                    valueRange = 15f..120f,
                    steps = 20,
                    enabled = habits.adaptiveBuildUpEnabled,
                )
                HorizontalDivider()
                Text("Notifications", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { Text("Learning reminders", fontWeight = FontWeight.SemiBold); Text("Morning, afternoon and evening prompts", style = MaterialTheme.typography.bodySmall) }
                    Switch(notification.isEnabled, { enabled -> viewModel.setNotificationPreferences(notification.copy(isEnabled = enabled)) })
                }
                TimeSettingRow("Morning", notification.morning) { viewModel.setNotificationPreferences(notification.copy(morning = it)) }
                TimeSettingRow("Afternoon", notification.afternoon) { viewModel.setNotificationPreferences(notification.copy(afternoon = it)) }
                TimeSettingRow("Evening", notification.evening) { viewModel.setNotificationPreferences(notification.copy(evening = it)) }
                Text("Reminder days", style = MaterialTheme.typography.labelLarge)
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat").forEachIndexed { index, name ->
                        val day = index + 1
                        FilterChip(day in notification.enabledWeekdays, {
                            val updated = if (day in notification.enabledWeekdays) notification.enabledWeekdays - day else notification.enabledWeekdays + day
                            viewModel.setNotificationPreferences(notification.copy(enabledWeekdays = updated))
                        }, label = { Text(name) })
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Quiet hours", Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
                    Switch(notification.quietHoursEnabled, { viewModel.setNotificationPreferences(notification.copy(quietHoursEnabled = it)) })
                }
                if (notification.quietHoursEnabled) {
                    TimeSettingRow("From", notification.quietHoursStart) { viewModel.setNotificationPreferences(notification.copy(quietHoursStart = it)) }
                    TimeSettingRow("Until", notification.quietHoursEnd) { viewModel.setNotificationPreferences(notification.copy(quietHoursEnd = it)) }
                }
                Text("After three similar Rescue attempts, PodTrackio can place one local reminder ten minutes before that distraction window.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                HorizontalDivider()
                Text("Downloads", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                val downloadedBytes = snapshot.downloads.values.sumOf { it.byteCount }
                Text("${humanBytes(downloadedBytes)} used of 8 GB. Unfinished episodes are never removed to make room.", style = MaterialTheme.typography.bodySmall)
                Text("Offline quality", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    DownloadQuality.entries.forEach { value -> FilterChip(snapshot.downloadQuality == value, { viewModel.setDownloadQuality(value) }, label = { Text(value.label) }) }
                }
                snapshot.downloads.values.sortedByDescending { it.downloadedAt }.forEach { record ->
                    val podcast = snapshot.podcasts.firstOrNull { it.youtubeVideoId == record.videoId }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(podcast?.title ?: record.videoId, fontWeight = FontWeight.SemiBold)
                            Text("${humanBytes(record.byteCount)}${record.resolutionHeight?.let { " · ${it}p" }.orEmpty()}${record.expiresAt?.let { " · removes seven days after completion" }.orEmpty()}", style = MaterialTheme.typography.bodySmall)
                        }
                        podcast?.let { TextButton(onClick = { viewModel.deleteDownload(it.id) }) { Text("Delete") } }
                    }
                }
                HorizontalDivider()
                BrainMemorySettings(snapshot.brain, viewModel)
                Text("AI connections", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text("Keys stay encrypted in Android Keystore and are never synced to Supabase.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                OutlinedTextField(groq, { groq = it }, Modifier.fillMaxWidth(), label = { Text(if (viewModel.hasGroqKey()) "Replace Groq key" else "Groq API key") }, visualTransformation = PasswordVisualTransformation(), singleLine = true)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { viewModel.storeGroqKey(groq); groq = "" }, enabled = groq.isNotBlank()) { Text("Save Groq key") }
                    OutlinedButton(onClick = viewModel::testGroq, enabled = viewModel.hasGroqKey()) { Text("Test") }
                    TextButton(onClick = { viewModel.storeGroqKey(null) }, enabled = viewModel.hasGroqKey()) { Text("Remove") }
                }
                OutlinedTextField(transcript, { transcript = it }, Modifier.fillMaxWidth(), label = { Text(if (viewModel.hasTranscriptKey()) "Replace TranscriptAPI key" else "TranscriptAPI key") }, visualTransformation = PasswordVisualTransformation(), singleLine = true)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { viewModel.storeTranscriptKey(transcript); transcript = "" }, enabled = transcript.isNotBlank()) { Text("Save Transcript key") }
                    TextButton(onClick = { viewModel.storeTranscriptKey(null) }, enabled = viewModel.hasTranscriptKey()) { Text("Remove") }
                }
                HorizontalDivider()
                Text("Categories", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text("Names and order sync without breaking episode references.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(categoryName, { categoryName = it }, Modifier.weight(1f), label = { Text("New category") }, singleLine = true)
                    Spacer(Modifier.width(8.dp))
                    Button(onClick = { viewModel.createCategory(categoryName, "blue"); categoryName = "" }) { Text("Create") }
                }
                snapshot.categories.sortedBy { it.sortOrder }.forEachIndexed { index, category ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(category.name, Modifier.weight(1f))
                        TextButton(enabled = index > 0, onClick = { viewModel.moveCategory(category.id, -1) }) { Text("Up") }
                        TextButton(enabled = index < snapshot.categories.lastIndex, onClick = { viewModel.moveCategory(category.id, 1) }) { Text("Down") }
                        TextButton(onClick = { editingCategory = category }) { Text("Edit") }
                        TextButton(enabled = snapshot.categories.size > 1, onClick = { deletingCategory = category }) { Text("Delete") }
                    }
                }
                if (snapshot.collections.isNotEmpty()) {
                    Text("Imported playlists", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    snapshot.collections.forEach { collection ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(collection.title, Modifier.weight(1f))
                            TextButton(onClick = { viewModel.deleteCollection(collection.id) }) { Text("Remove") }
                        }
                    }
                }
                Button(onClick = onDismiss, Modifier.align(Alignment.End)) { Text("Done") }
            }
        }
    }
    editingCategory?.let { category ->
        CategoryEditDialog(category, onDismiss = { editingCategory = null }) { name, color ->
            viewModel.updateCategory(category.id, name, color); editingCategory = null
        }
    }
    deletingCategory?.let { category ->
        CategoryDeleteDialog(
            category = category,
            categories = snapshot.categories,
            inUse = snapshot.podcasts.any { it.categoryId == category.id },
            onDismiss = { deletingCategory = null },
            onDelete = { replacement -> viewModel.deleteCategory(category.id, replacement); deletingCategory = null },
        )
    }
}

@Composable
private fun TimeSettingRow(label: String, value: TimeOfDay, onChange: (TimeOfDay) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        TextButton(onClick = { onChange(value.copy(hour = (value.hour + 23) % 24)) }) { Text("−") }
        Text("%02d:%02d".format(value.hour, value.minute), fontWeight = FontWeight.SemiBold)
        TextButton(onClick = { onChange(value.copy(hour = (value.hour + 1) % 24)) }) { Text("+") }
    }
}

@Composable
private fun CategoryEditDialog(category: LearningCategory, onDismiss: () -> Unit, onSave: (String, String) -> Unit) {
    var name by remember(category.id) { mutableStateOf(category.name) }
    var color by remember(category.id) { mutableStateOf(category.colorToken) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Edit category") },
        text = { Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedTextField(name, { name = it }, label = { Text("Name") }, singleLine = true)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf("blue", "green", "orange", "purple", "red").forEach { value -> FilterChip(color == value, { color = value }, label = { Text(value.replaceFirstChar(Char::uppercase)) }) }
            }
        } },
        confirmButton = { Button(enabled = name.isNotBlank(), onClick = { onSave(name, color) }) { Text("Save") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun CategoryDeleteDialog(
    category: LearningCategory,
    categories: List<LearningCategory>,
    inUse: Boolean,
    onDismiss: () -> Unit,
    onDelete: (String?) -> Unit,
) {
    var replacement by remember(category.id) { mutableStateOf(categories.firstOrNull { it.id != category.id }?.id) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Delete ${category.name}?") },
        text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(if (inUse) "Choose where its episodes should move." else "This category is unused.")
            if (inUse) categories.filter { it.id != category.id }.forEach { candidate ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(replacement == candidate.id, { replacement = candidate.id })
                    Text(candidate.name)
                }
            }
        } },
        confirmButton = { Button(enabled = !inUse || replacement != null, onClick = { onDelete(replacement.takeIf { inUse }) }) { Text("Delete") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

private fun humanBytes(bytes: Long): String = when {
    bytes >= 1_073_741_824 -> "%.1f GB".format(bytes / 1_073_741_824.0)
    bytes >= 1_048_576 -> "%.1f MB".format(bytes / 1_048_576.0)
    bytes >= 1_024 -> "%.1f KB".format(bytes / 1_024.0)
    else -> "$bytes B"
}

@Composable
fun TranscriptDialog(initial: String, onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var value by remember(initial) { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Episode transcript") },
        text = { OutlinedTextField(value, { value = it }, Modifier.fillMaxWidth().height(300.dp), label = { Text("Paste or edit transcript") }) },
        confirmButton = { Button(enabled = value.isNotBlank(), onClick = { onSave(value) }) { Text("Save on tablet") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
