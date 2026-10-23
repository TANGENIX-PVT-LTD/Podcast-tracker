package com.tangenix.podtrackio.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.tangenix.podtrackio.*
import com.tangenix.podtrackio.R
import com.tangenix.podtrackio.data.AuthState
import com.tangenix.podtrackio.ui.screens.*
import com.tangenix.podtrackio.ui.play.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*

@Composable
fun PodTrackioApp(viewModel: PodTrackioViewModel, ui: PodTrackioUiState, auth: AuthState) {
    if (!ui.loaded || auth.restoring) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }
    if (!auth.isAuthenticated && !ui.demoMode) {
        LoginScreen(viewModel, auth)
        return
    }
    val snackbar = remember { SnackbarHostState() }
    var addOpen by remember { mutableStateOf(false) }
    var settingsOpen by remember { mutableStateOf(false) }
    LaunchedEffect(ui.message) {
        ui.message?.let { snackbar.showSnackbar(it); viewModel.clearMessage() }
    }
    val selected = ui.selectedPodcast
    val context = androidx.compose.ui.platform.LocalContext.current
    LaunchedEffect(ui.snapshot.habitLoop.hapticsEnabled, ui.snapshot.habitLoop.soundsEnabled) {
        PlayFeedback.hapticsEnabled = ui.snapshot.habitLoop.hapticsEnabled
        PlayFeedback.soundsEnabled = ui.snapshot.habitLoop.soundsEnabled
    }
    LaunchedEffect(ui.loaded) { if (ui.loaded) viewModel.checkFreezeSaved(context.getSharedPreferences("play", android.content.Context.MODE_PRIVATE)) }
    val streak = remember(ui.snapshot.habitLoop, ui.snapshot.activities, ui.snapshot.stats) { ui.snapshot.streakInfo() }
    Box(Modifier.fillMaxSize()) {
    Scaffold(snackbarHost = { SnackbarHost(snackbar) },
        contentWindowInsets = if (selected != null) WindowInsets(0, 0, 0, 0) else ScaffoldDefaults.contentWindowInsets
    ) { padding ->
        if (selected != null) {
            PlayerScreen(selected, ui, viewModel, Modifier.fillMaxSize())
        } else Row(Modifier.fillMaxSize().padding(padding)) {
            Surface(color = MaterialTheme.colorScheme.surfaceContainerLow) {
                Column(Modifier.width(232.dp).fillMaxHeight().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Image(painterResource(R.drawable.podtrackio_logo), "PodTrackio logo", Modifier.size(40.dp))
                        Text("PodTrackio", Modifier.padding(start = 10.dp), style = playType(20))
                    }
                    StreakBadge(streak, ui.snapshot.habitLoop.gems, ui.snapshot.stats.totalXp)
                    Spacer(Modifier.height(8.dp))
                    AppSection.entries.forEach { section ->
                        val icon = when (section) {
                            AppSection.TODAY -> Icons.Rounded.WbSunny; AppSection.LIBRARY -> Icons.Rounded.LibraryBooks
                            AppSection.PROGRESS -> Icons.Rounded.BarChart; AppSection.BRAIN -> Icons.Rounded.Psychology
                        }
                        ChunkyTile({ PlayFeedback.play(Cue.SELECT, sound = false); viewModel.selectSection(section) }, Modifier.fillMaxWidth(), selected = ui.section == section, radius = 14.dp) {
                            Row(Modifier.padding(horizontal = 14.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(icon, null, tint = if (ui.section == section) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
                                Text(section.title.uppercase(), Modifier.padding(start = 12.dp), style = playType(14),
                                    color = if (ui.section == section) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = .7f))
                            }
                        }
                    }
                    HorizontalDivider(Modifier.padding(vertical = 6.dp))
                    Text("Collections", style = playType(13), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
                    ui.snapshot.collections.forEach { collection ->
                        TextButton({ viewModel.selectSection(AppSection.LIBRARY); viewModel.filterCollection(collection.id) }, Modifier.fillMaxWidth()) { Text(collection.title) }
                    }
                    Spacer(Modifier.weight(1f))
                    ChunkyButton("Settings", { settingsOpen = true }, kind = ChunkyKind.SECONDARY, small = true, icon = Icons.Rounded.Settings)
                }
            }
            VerticalDivider()
            Column(Modifier.weight(1f)) {
                Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(ui.section.title, Modifier.weight(1f), style = playType(28))
                    ChunkyButton("Add episode", { addOpen = true }, small = true, fullWidth = false, icon = Icons.Rounded.Add)
                }
                Box(Modifier.weight(1f)) {
                    when (ui.section) {
                        AppSection.TODAY -> TodayScreen(ui, viewModel) { addOpen = true }
                        AppSection.LIBRARY -> LibraryScreen(ui, viewModel) { addOpen = true }
                        AppSection.PROGRESS -> ProgressScreen(ui, viewModel)
                        AppSection.BRAIN -> BrainScreen(ui, viewModel)
                    }
                }
            }
        }
    }
    MomentHost(ui.moments.firstOrNull(), ui.snapshot) { viewModel.dismissMoment() }
    }
    if (addOpen) AddContentDialog(ui.snapshot, viewModel) { addOpen = false }
    if (settingsOpen) SettingsDialog(ui.snapshot, auth, viewModel) { settingsOpen = false }
}
