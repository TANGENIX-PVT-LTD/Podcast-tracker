/* Preserved duplicate draft. Active dialogs are implemented in Dialogs.kt.
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material3.AssistChip
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
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioGroup
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tangenix.podtrackio.PodTrackioUiState
import com.tangenix.podtrackio.PodTrackioViewModel
import com.tangenix.podtrackio.domain.DistractionCue
import com.tangenix.podtrackio.domain.allAchievements
import com.tangenix.podtrackio.domain.formatDuration
import com.tangenix.podtrackio.domain.todayKey
import com.tangenix.podtrackio.ui.components.EpisodeRow
import com.tangenix.podtrackio.ui.components.MetricCard
import kotlin.math.roundToInt
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

private val rescueCues = listOf(
    DistractionCue.SCROLLING to "Scrolling",
    DistractionCue.STREAMING to "Streaming",
    DistractionCue.ANIME to "Anime",
    DistractionCue.GAMING to "Gaming",
    DistractionCue.OTHER to "Other",
    DistractionCue.NOTIFICATION to "Notifications",
    DistractionCue.TODAY to "Today",
    DistractionCue.MOMENTUM to "Momentum",
)

@Composable
private fun FocusRescueDialog(
    podcasts: List<com.tangenix.podtrackio.domain.Podcast>,
    onDismiss: () -> Unit,
    onStart: (String, Int, DistractionCue) -> Unit,
) {
    var selectedCue by remember { mutableStateOf(DistractionCue.SCROLLING) }
    var minutes by remember { mutableStateOf(5) }
    var selectedPodcast by remember { mutableStateOf(podcasts.firstOrNull()?.id) }

    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Distraction Rescue") },
        text = { Column(Modifier.verticalScroll(rememberScrollState())) {
            Text("What is pulling you away?", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            RadioGroup(selected = selectedCue, onClick = { selectedCue = it }) {
                rescueCues.forEach { (cue, title) ->
                    RadioButton(
                        selected = selectedCue == cue,
                        onClick = { selectedCue = cue },
                    ) {
                        Text(title)
                    }
                }
            }
            Text("Make the smallest promise you will keep", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(5, 10, 20).forEach { min ->
                    FilterChip(
                        selected = minutes == min,
                        onClick = { minutes = min },
                        label = { Text("${min} min") },
                    )
                }
            }
        } },
        confirmButton = { Button(enabled = selectedPodcast != null, onClick = { selectedPodcast?.let { onStart(it, minutes, selectedCue) } }) { Text("Replace It with $minutes Minutes") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
fun AddContentDialog(
    snapshot: com.tangenix.podtrackio.data.AppSnapshot,
    viewModel: PodTrackioViewModel,
    onDismiss: () -> Unit,
) {
    var url by remember { mutableStateOf("") }
    var title by remember { mutableStateOf("") }
    var categoryId by remember { mutableStateOf(snapshot.categories.firstOrNull()?.id ?: "") }

    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Episode") },
        text = { Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            OutlinedTextField(
                value = url,
                onValueChange = { url = it },
                label = { Text("YouTube URL") },
                placeholder = { Text("https://youtube.com/watch?v=...") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            OutlinedTextField(
                value = title,
                onValueChange = { title = it },
                label = { Text("Title (optional)") },
                placeholder = { Text("Auto-fetched from URL") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            androidx.compose.material3.DropdownMenu(
                expanded = true,
                onDismissRequest = {},
            ) {
                snapshot.categories.forEach { cat ->
                    androidx.compose.material3.DropdownMenuItem(onClick = { categoryId = cat.id }) {
                        Text(cat.name)
                    }
                }
            }
        } },
        confirmButton = { Button(onClick = { viewModel.addPodcast(url, title, categoryId); onDismiss() }, enabled = url.isNotBlank()) { Text("Add") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
fun SettingsDialog(
    snapshot: com.tangenix.podtrackio.data.AppSnapshot,
    auth: com.tangenix.podtrackio.data.AuthState,
    viewModel: PodTrackioViewModel,
    onDismiss: () -> Unit,
) {
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Settings") },
        text = { Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Demo Mode", Modifier.weight(1f))
                androidx.compose.material3.Switch(checked = snapshot.habitSettings?.demoMode == true, onCheckedChange = { viewModel.setDemoMode(it) })
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Daily Goal: ${snapshot.habitSettings?.dailyGoalMinutes?.roundToInt() ?: 30} min", Modifier.weight(1f))
                OutlinedButton(onClick = {  show goal picker  }) { Text("Change") }
            }
            if (auth.isAuthenticated) {
                TextButton(onClick = { viewModel.signOut(); onDismiss() }) { Text("Sign Out") }
            }
        } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Close") } },
    )
}
*/
