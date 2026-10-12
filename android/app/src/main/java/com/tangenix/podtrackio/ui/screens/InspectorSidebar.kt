package com.tangenix.podtrackio.ui.screens

import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Send
import androidx.compose.material.icons.rounded.TextFields
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tangenix.podtrackio.InspectorMode
import com.tangenix.podtrackio.PodTrackioUiState
import com.tangenix.podtrackio.PodTrackioViewModel
import com.tangenix.podtrackio.domain.AnswerStyle
import com.tangenix.podtrackio.domain.Podcast
import com.tangenix.podtrackio.domain.PodcastSummary
import com.tangenix.podtrackio.domain.QuirkyModel
import com.tangenix.podtrackio.domain.TranscriptSource
import com.tangenix.podtrackio.domain.formatDuration
import kotlinx.coroutines.delay
import java.time.Instant

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InspectorSidebar(
    podcast: Podcast,
    ui: PodTrackioUiState,
    viewModel: PodTrackioViewModel,
    modifier: Modifier = Modifier,
    onTranscript: () -> Unit = {},
    onImportTranscript: () -> Unit = {},
    onSeek: (Double) -> Unit = {},
) {
    val summary = ui.snapshot.summaries.firstOrNull { it.podcastId == podcast.id }
    val hasTranscript = ui.snapshot.transcripts.containsKey(podcast.id)
    var transcriptMenuOpen by remember { mutableStateOf(false) }

    Card(
        modifier = modifier
            .background(MaterialTheme.colorScheme.surfaceContainerLow),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        ),
        shape = RoundedCornerShape(0.dp),
        elevation = CardDefaults.cardElevation(
            defaultElevation = 0.dp,
        ),
    ) {
        Column(modifier = Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(0.dp)) {
            // Tab Bar - matches macOS Picker with .pickerStyle(.segmented)
            Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                InspectorMode.entries.forEach { mode ->
                    FilterChip(ui.inspectorMode == mode, { viewModel.setInspector(mode) }, label = { Text(mode.title) })
                }
                Box {
                    IconButton({ transcriptMenuOpen = true }) { Icon(Icons.Rounded.MoreVert, "Transcript options") }
                    DropdownMenu(transcriptMenuOpen, { transcriptMenuOpen = false }) {
                        DropdownMenuItem(text = { Text(if (hasTranscript) "Edit transcript" else "Paste transcript") }, onClick = { transcriptMenuOpen = false; onTranscript() })
                        DropdownMenuItem(text = { Text("Import transcript") }, onClick = { transcriptMenuOpen = false; onImportTranscript() })
                    }
                }
            }

            androidx.compose.material3.HorizontalDivider(
                modifier = Modifier.padding(horizontal = 16.dp),
                color = MaterialTheme.colorScheme.outlineVariant,
            )

            // Content - matches macOS inspector content
            when (ui.inspectorMode) {
                InspectorMode.SUMMARY -> SummaryInspector(
                    podcast = podcast,
                    summary = summary,
                    onTranscript = onTranscript,
                    onImportTranscript = onImportTranscript,
                    onSeek = onSeek,
                    hasTranscript = hasTranscript,
                    ui = ui,
                    viewModel = viewModel,
                    modifier = Modifier.weight(1f).fillMaxWidth().padding(16.dp),
                )
                InspectorMode.NOTES -> NotesInspector(
                    podcast = podcast,
                    viewModel = viewModel,
                    modifier = Modifier.weight(1f).fillMaxWidth().padding(16.dp),
                )
                InspectorMode.QUIRKY -> QuirkyInspector(
                    podcast = podcast,
                    hasTranscript = hasTranscript,
                    ui = ui,
                    viewModel = viewModel,
                    modifier = Modifier.weight(1f).fillMaxWidth().padding(16.dp),
                )
            }
        }
    }
}

@Composable
private fun SummaryInspector(
    podcast: Podcast,
    summary: PodcastSummary?,
    onTranscript: () -> Unit,
    onImportTranscript: () -> Unit,
    onSeek: (Double) -> Unit,
    hasTranscript: Boolean,
    ui: PodTrackioUiState,
    viewModel: PodTrackioViewModel,
    modifier: Modifier,
) {
    if (summary == null) {
        Column(
            modifier = modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            androidx.compose.foundation.layout.Spacer(Modifier.height(32.dp))
            Icon(Icons.Rounded.AutoAwesome, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(48.dp))
            Text("Build a faithful learning brief", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text(
                if (hasTranscript) "Turn the saved transcript into topics, takeaways and an action plan."
                else "Fetch the transcript automatically or paste your own.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            androidx.compose.foundation.layout.Spacer(Modifier.height(16.dp))
            ui.summaryStatus?.let {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    CircularProgressIndicator()
                    Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } ?: Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { viewModel.generateSummary(podcast.id) }) {
                    Icon(Icons.Rounded.AutoAwesome, null, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(if (hasTranscript) "Generate summary" else "Fetch transcript + summarize")
                }
            }
        }
        return
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Text("Learning brief", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text(summary.brief)

        if (summary.keyTopics.isNotEmpty()) {
            Text("Key topics", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            summary.keyTopics.forEach { item ->
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(item.title, Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
                        item.timestampSeconds?.let { timestamp ->
                            TextButton(onClick = { onSeek(timestamp) }) { Text(formatDuration(timestamp)) }
                        }
                    }
                    Text(item.explanation, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        summary.sections.forEach { section ->
            Text(section.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            section.introduction?.takeIf { it.isNotBlank() }?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            section.points.forEach { point ->
                Row(verticalAlignment = Alignment.Top) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(point.title, fontWeight = FontWeight.SemiBold)
                        Text(point.explanation, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    point.timestampSeconds?.let { timestamp ->
                        TextButton(onClick = { onSeek(timestamp) }) { Text(formatDuration(timestamp)) }
                    }
                }
            }
        }

        if (summary.majorTakeaways.isNotEmpty()) {
            Text("Major takeaways", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            summary.majorTakeaways.forEach { item ->
                Text("• ${item.title}: ${item.explanation}")
            }
        }

        if (summary.actionPlan.isNotEmpty()) {
            Text("Action plan", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            summary.actionPlan.forEach { action ->
                Row(verticalAlignment = Alignment.Top) {
                    androidx.compose.material3.Checkbox(action.isCompleted, onCheckedChange = { viewModel.toggleAction(podcast.id, action.id) })
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(action.title, fontWeight = FontWeight.SemiBold)
                        Text(action.detail, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }

        OutlinedButton(onClick = { viewModel.generateSummary(podcast.id) }) { Text("Regenerate") }
    }
}

@Composable
private fun NotesInspector(podcast: Podcast, viewModel: PodTrackioViewModel, modifier: Modifier) {
    var notes by remember(podcast.id, podcast.notes) { mutableStateOf(podcast.notes) }
    Column(modifier) {
        Text("Notes", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text("Saved locally immediately and synced to your account.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        androidx.compose.foundation.layout.Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = notes,
            onValueChange = { notes = it; viewModel.updateNotes(podcast.id, it) },
            modifier = Modifier.fillMaxSize(),
            placeholder = { Text("Capture ideas, quotes and questions…") },
            maxLines = Int.MAX_VALUE,
            minLines = 20,
        )
    }
}

@Composable
private fun QuirkyInspector(
    podcast: Podcast,
    hasTranscript: Boolean,
    ui: PodTrackioUiState,
    viewModel: PodTrackioViewModel,
    modifier: Modifier,
) {
    var question by remember(podcast.id) { mutableStateOf("") }
    var model by remember { mutableStateOf(QuirkyModel.DEEP) }
    var style by remember { mutableStateOf(AnswerStyle.MEDIUM) }
    val messages = ui.snapshot.quirkyConversations[podcast.id].orEmpty()

    Column(modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Ask Quirky", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            if (messages.isNotEmpty()) TextButton(onClick = { viewModel.clearQuirky(podcast.id) }) { Text("Clear") }
        }

        if (!hasTranscript) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Rounded.TextFields, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(48.dp).fillMaxWidth())
                Text("Quirky answers only from this episode's transcript—no fabricated context.", color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                Button(onClick = { viewModel.generateSummary(podcast.id) }) { Text("Fetch transcript") }
            }
        } else {
            // Model selector - matches macOS Menu
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                QuirkyModel.entries.forEach { value ->
                    FilterChip(
                        selected = model == value,
                        onClick = { model = value },
                        label = { Text(value.label) },
                    )
                }
            }

            // Style selector - matches macOS Menu
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                AnswerStyle.entries.forEach { value ->
                    FilterChip(
                        selected = style == value,
                        onClick = { style = value },
                        label = { Text(value.name.lowercase().replaceFirstChar(Char::uppercase)) },
                    )
                }
            }

            // Conversation
            Column(
                Modifier.weight(1f)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (messages.isEmpty()) {
                    Text("Try: \"Explain the core idea like I'm new to it.\"", color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.fillMaxWidth())
                }
                messages.forEach { message ->
                    Surface(
                        color = if (message.role == "user") MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHighest,
                        shape = RoundedCornerShape(15.dp),
                        modifier = Modifier
                            .fillMaxWidth(if (message.role == "user") .84f else 1f)
                            .wrapContentSize(),
                    ) {
                        Text(message.content, Modifier.padding(16.dp))
                    }
                }
                if (ui.chatBusy) {
                    Row(horizontalArrangement = Arrangement.Center) {
                        CircularProgressIndicator(Modifier.size(24.dp))
                    }
                }
            }

            // Input - matches macOS composer
            Row(verticalAlignment = Alignment.Bottom) {
                OutlinedTextField(
                    value = question,
                    onValueChange = { question = it },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("Ask about this episode") },
                    maxLines = 3,
                    minLines = 1,
                )
                Spacer(Modifier.width(8.dp))
                Button(
                    enabled = question.isNotBlank() && !ui.chatBusy,
                    onClick = { viewModel.askQuirky(podcast.id, question, model, style); question = "" },
                ) {
                    Icon(Icons.Rounded.Send, null, modifier = Modifier.size(20.dp))
                }
            }
        }
    }
}
