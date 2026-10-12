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
    Scaffold(snackbarHost = { SnackbarHost(snackbar) },
        contentWindowInsets = if (selected != null) WindowInsets(0, 0, 0, 0) else ScaffoldDefaults.contentWindowInsets
    ) { padding ->
        if (selected != null) {
            PlayerScreen(selected, ui, viewModel, Modifier.fillMaxSize())
        } else Row(Modifier.fillMaxSize().padding(padding)) {
            Surface(color = MaterialTheme.colorScheme.surfaceContainerLow) {
                Column(Modifier.width(220.dp).fillMaxHeight().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Image(painterResource(R.drawable.podtrackio_logo), "PodTrackio logo", Modifier.size(40.dp))
                        Text("PodTrackio", Modifier.padding(start = 10.dp), style = MaterialTheme.typography.titleLarge)
                    }
                    Spacer(Modifier.height(20.dp))
                    AppSection.entries.forEach { section ->
                        if (ui.section == section) Button({ viewModel.selectSection(section) }, Modifier.fillMaxWidth()) { Text(section.title) }
                        else TextButton({ viewModel.selectSection(section) }, Modifier.fillMaxWidth()) { Text(section.title) }
                    }
                    HorizontalDivider()
                    Text("Collections", style = MaterialTheme.typography.labelLarge)
                    ui.snapshot.collections.forEach { collection ->
                        TextButton({ viewModel.selectSection(AppSection.LIBRARY); viewModel.filterCollection(collection.id) }, Modifier.fillMaxWidth()) { Text(collection.title) }
                    }
                    Spacer(Modifier.weight(1f))
                    TextButton({ settingsOpen = true }, Modifier.fillMaxWidth()) { Text("Settings") }
                }
            }
            VerticalDivider()
            Column(Modifier.weight(1f)) {
                Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(ui.section.title, Modifier.weight(1f), style = MaterialTheme.typography.headlineSmall)
                    Button({ addOpen = true }) { Text("Add episode") }
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
    if (addOpen) AddContentDialog(ui.snapshot, viewModel) { addOpen = false }
    if (settingsOpen) SettingsDialog(ui.snapshot, auth, viewModel) { settingsOpen = false }
}
