package com.tangenix.podtrackio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.automirrored.rounded.Chat
import androidx.compose.material.icons.automirrored.rounded.Notes
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.tangenix.podtrackio.PodTrackioUiState
import com.tangenix.podtrackio.PodTrackioViewModel
import com.tangenix.podtrackio.domain.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun BrainScreen(ui: PodTrackioUiState, viewModel: PodTrackioViewModel) {
    val context = LocalContext.current
    val preferences = remember { context.getSharedPreferences("brain_composer", android.content.Context.MODE_PRIVATE) }
    var question by rememberSaveable { mutableStateOf("") }
    var filter by rememberSaveable { mutableStateOf("") }
    var workspace by rememberSaveable { mutableStateOf("Canvas") }
    var model by remember { mutableStateOf(runCatching { QuirkyModel.valueOf(preferences.getString("model", "BALANCED")!!) }.getOrDefault(QuirkyModel.BALANCED)) }
    var style by remember { mutableStateOf(runCatching { AnswerStyle.valueOf(preferences.getString("style", "MEDIUM")!!) }.getOrDefault(AnswerStyle.MEDIUM)) }
    var settings by remember { mutableStateOf(false) }
    var inspected by remember { mutableStateOf<BrainSource?>(null) }
    var selected by remember { mutableStateOf<BrainSource?>(null) }
    var newChat by remember { mutableStateOf(false) }
    val clipboard = LocalClipboardManager.current
    val index by produceState(BrainIndex(emptyList()), ui.snapshot.podcasts, ui.snapshot.summaries, ui.snapshot.transcripts, ui.snapshot.quirkyConversations, ui.snapshot.brain.messages) { value = withContext(Dispatchers.Default) { BrainIndex.build(ui.snapshot) } }
    val documents = remember(index, filter) { index.sources.distinctBy { it.podcastId + it.kind }.filter { filter.isBlank() || (it.title + it.text).contains(filter, true) }.sortedWith(compareBy({ it.title }, { it.kind })) }
    val scroll = rememberLazyListState()
    fun send() { if (question.isNotBlank() && !ui.brainBusy) { viewModel.askBrain(question.trim(), model, style); question = ""; workspace = "Chat" } }
    LaunchedEffect(ui.snapshot.brain.messages.size, workspace) { if (workspace == "Chat" && ui.snapshot.brain.messages.isNotEmpty()) scroll.scrollToItem(ui.snapshot.brain.messages.size - 1) }
    val surface = MaterialTheme.colorScheme.surfaceContainerLow
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface), horizontalAlignment = Alignment.CenterHorizontally) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.weight(1f).widthIn(max = 330.dp).clip(RoundedCornerShape(12.dp)).background(surface)) {
                    listOf("Canvas", "Chat", "Sources").forEach { mode -> TextButton({ workspace = mode }, Modifier.weight(1f), colors = ButtonDefaults.textButtonColors(containerColor = if (mode == workspace) MaterialTheme.colorScheme.surfaceContainerHighest else Color.Transparent)) { Text(mode, fontWeight = if (mode == workspace) FontWeight.SemiBold else FontWeight.Normal) } }
                }
                IconButton({ newChat = true }, enabled = !ui.brainBusy) { Icon(Icons.Rounded.EditNote, "New conversation") }
                IconButton({ settings = true }) { Icon(Icons.Rounded.AccountCircle, "Personal memories") }
            }
            if (workspace != "Chat") {
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(surface).padding(horizontal = 12.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Search, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    BasicTextField(filter, { filter = it }, Modifier.weight(1f).padding(start = 10.dp), singleLine = true, textStyle = LocalTextStyle.current.copy(color = MaterialTheme.colorScheme.onSurface), decorationBox = { inner -> if (filter.isEmpty()) Text("Search your learning", color = MaterialTheme.colorScheme.onSurfaceVariant); inner() })
                    if (filter.isNotEmpty()) IconButton({ filter = "" }, Modifier.size(24.dp)) { Icon(Icons.Rounded.Close, "Clear search", Modifier.size(18.dp)) }
                }
            }
        }
        Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 10.dp).clip(RoundedCornerShape(16.dp))) {
            when (workspace) {
                "Canvas" -> {
                    BrainCanvasView(documents, Modifier.fillMaxSize()) { selected = it }
                    selected?.let { source ->
                        Surface(Modifier.align(Alignment.BottomStart).padding(start = 14.dp, bottom = 82.dp).widthIn(max = 350.dp), shape = RoundedCornerShape(18.dp), shadowElevation = 8.dp, color = surface) {
                            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) { Text(source.kind, Modifier.weight(1f), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant); IconButton({ selected = null }, Modifier.size(28.dp)) { Icon(Icons.Rounded.Close, "Close selection", Modifier.size(16.dp)) } }
                                Text(source.title, style = MaterialTheme.typography.titleSmall, maxLines = 2)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { OutlinedButton({ inspected = source }) { Text("Read source") }; Button({ question = "What are the key lessons from ${source.title}?"; workspace = "Chat" }) { Text("Ask Brain") } }
                            }
                        }
                    }
                }
                "Sources" -> LazyColumn(Modifier.fillMaxSize().padding(horizontal = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(documents, key = { it.id }) { source -> Surface(onClick = { inspected = source }, shape = RoundedCornerShape(16.dp), color = surface) { Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(sourceIcon(source.kind), null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary)
                        Column(Modifier.weight(1f).padding(horizontal = 14.dp)) { Text(source.title, style = MaterialTheme.typography.bodyLarge); Text(source.kind, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        Icon(Icons.AutoMirrored.Rounded.ArrowForward, "Inspect", Modifier.size(16.dp))
                    } } }
                }
                else -> LazyColumn(Modifier.fillMaxSize().widthIn(max = 800.dp).align(Alignment.Center).padding(horizontal = 18.dp), state = scroll, verticalArrangement = Arrangement.spacedBy(24.dp), contentPadding = PaddingValues(vertical = 24.dp)) {
                    if (ui.snapshot.brain.messages.isEmpty()) item {
                        Column(Modifier.fillMaxWidth().padding(top = 24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            Icon(Icons.Rounded.Psychology, null, Modifier.size(38.dp), tint = MaterialTheme.colorScheme.primary)
                            Text("Think with everything you've learned.", style = MaterialTheme.typography.headlineSmall)
                            Text("Connect ideas across ${index.sources.map { it.podcastId }.distinct().size} episodes. Follow the evidence.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                            listOf("What themes connect my podcasts?", "Turn my learning into a practical plan", "Help me design a prompt for my goals").forEach { prompt -> OutlinedButton({ question = prompt }, Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp)) { Text(prompt, Modifier.weight(1f)); Icon(Icons.Rounded.NorthWest, null, Modifier.size(16.dp)) } }
                        }
                    }
                    items(ui.snapshot.brain.messages, key = { it.id }) { message ->
                        if (message.role == "user") Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                            Surface(Modifier.widthIn(max = 650.dp).padding(start = 24.dp), shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh) { SelectionContainer { Text(message.text, Modifier.padding(horizontal = 18.dp, vertical = 12.dp), lineHeight = 24.sp) } }
                        } else Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Psychology, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Text("Brain", Modifier.padding(start = 8.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            BrainAnswerText(message.text)
                            Row {
                                TextButton({ clipboard.setText(AnnotatedString(message.text)) }) { Icon(Icons.Rounded.ContentCopy, "Copy", Modifier.size(14.dp)); Text("Copy", Modifier.padding(start = 6.dp)) }
                                var sourcesOpen by remember { mutableStateOf(false) }
                                Box {
                                    if (message.sources.isNotEmpty()) TextButton({ sourcesOpen = true }) { Text("${message.sources.size} sources") }
                                    DropdownMenu(sourcesOpen, { sourcesOpen = false }) { message.sources.forEachIndexed { i, source -> DropdownMenuItem(text = { Text("[S${i + 1}] ${source.title} · ${source.kind}") }, onClick = { inspected = source; sourcesOpen = false }) } }
                                }
                            }
                        }
                    }
                    if (ui.brainBusy) item { Row(verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp); Text("${modelTitle(model)} · connecting your sources…", Modifier.padding(start = 12.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) } }
                }
            }
        }
        Surface(Modifier.padding(horizontal = 16.dp, vertical = 12.dp).widthIn(max = 800.dp).fillMaxWidth().imePadding(), shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.surfaceContainer, border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant), shadowElevation = 3.dp) {
            Column(Modifier.padding(horizontal = 18.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                BasicTextField(question, { question = it }, Modifier.fillMaxWidth().heightIn(min = 28.dp, max = 140.dp), textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface), keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send), keyboardActions = KeyboardActions(onSend = { send() }), decorationBox = { inner -> if (question.isEmpty()) Text("Ask anything about your learning…", color = MaterialTheme.colorScheme.onSurfaceVariant); inner() })
                Row(verticalAlignment = Alignment.CenterVertically) {
                    var modelMenu by remember { mutableStateOf(false) }; var styleMenu by remember { mutableStateOf(false) }
                    Box {
                        TextButton({ modelMenu = true }, contentPadding = PaddingValues(horizontal = 0.dp)) { Icon(if (model == QuirkyModel.INSTANT) Icons.Rounded.Bolt else Icons.Rounded.Psychology, null, Modifier.size(16.dp)); Text(modelTitle(model), Modifier.padding(start = 6.dp), fontSize = 12.sp); Icon(Icons.Rounded.KeyboardArrowDown, null, Modifier.size(16.dp)) }
                        DropdownMenu(modelMenu, { modelMenu = false }) { QuirkyModel.entries.forEach { value -> DropdownMenuItem(text = { Text(modelTitle(value)) }, trailingIcon = { if (value == model) Icon(Icons.Rounded.Check, null) }, onClick = { model = value; preferences.edit().putString("model", value.name).apply(); modelMenu = false }) } }
                    }
                    Spacer(Modifier.width(14.dp))
                    Box {
                        TextButton({ styleMenu = true }, contentPadding = PaddingValues(horizontal = 0.dp)) { Icon(Icons.AutoMirrored.Rounded.Notes, null, Modifier.size(16.dp)); Text(styleTitle(style), Modifier.padding(start = 6.dp), fontSize = 12.sp); Icon(Icons.Rounded.KeyboardArrowDown, null, Modifier.size(16.dp)) }
                        DropdownMenu(styleMenu, { styleMenu = false }) { AnswerStyle.entries.forEach { value -> DropdownMenuItem(text = { Text(styleTitle(value)) }, trailingIcon = { if (value == style) Icon(Icons.Rounded.Check, null) }, onClick = { style = value; preferences.edit().putString("style", value.name).apply(); styleMenu = false }) } }
                    }
                    Spacer(Modifier.weight(1f))
                    IconButton({ send() }, enabled = question.isNotBlank() && !ui.brainBusy, modifier = Modifier.size(44.dp).clip(CircleShape).background(if (question.isNotBlank() && !ui.brainBusy) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.15f))) { Icon(Icons.Rounded.ArrowUpward, "Send question", tint = MaterialTheme.colorScheme.surface) }
                }
            }
        }
    }
    if (settings) Dialog({ settings = false }) { Surface(shape = MaterialTheme.shapes.large) { Column(Modifier.padding(20.dp).verticalScroll(rememberScrollState())) { BrainMemorySettings(ui.snapshot.brain, viewModel); TextButton({ settings = false }) { Text("Done") } } } }
    inspected?.let { source -> AlertDialog(onDismissRequest = { inspected = null }, title = { Text(source.title) }, text = { Column(Modifier.verticalScroll(rememberScrollState())) { Text(source.kind, style = MaterialTheme.typography.labelLarge); SelectionContainer { Text(source.text) } } }, confirmButton = { TextButton({ viewModel.selectPodcast(source.podcastId); inspected = null }) { Text("Open episode") } }, dismissButton = { TextButton({ inspected = null }) { Text("Done") } }) }
    if (newChat) AlertDialog(onDismissRequest = { newChat = false }, title = { Text("Start a new conversation?") }, text = { Text("Your podcast knowledge and personal memories stay available.") }, confirmButton = { TextButton({ viewModel.updateBrain { it.copy(messages = emptyList()) }; workspace = "Chat"; newChat = false }) { Text("Clear conversation") } }, dismissButton = { TextButton({ newChat = false }) { Text("Cancel") } })
}

private fun modelTitle(model: QuirkyModel) = if (model == QuirkyModel.DEEP) "Deep Reasoning" else model.label
private fun styleTitle(style: AnswerStyle) = when (style) { AnswerStyle.CONCISE -> "Concise"; AnswerStyle.MEDIUM -> "Default"; AnswerStyle.DETAILED -> "Detailed" }
private fun sourceIcon(kind: String) = when (kind) { "Transcript" -> Icons.Rounded.Description; "Summary" -> Icons.Rounded.AutoAwesome; else -> Icons.AutoMirrored.Rounded.Chat }

@Composable
private fun BrainAnswerText(text: String) {
    SelectionContainer { Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        text.split("\n\n").forEach { block ->
            if (block.startsWith("#")) Text(block.replace(Regex("^#{1,6}\\s*"), ""), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            else if (block.startsWith("```")) Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceContainer) { Text(block.lines().drop(1).dropLast(1).joinToString("\n"), Modifier.padding(14.dp), fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace) }
            else Text(block.replace("**", "").replace(Regex("(?m)^- "), "• "), style = MaterialTheme.typography.bodyLarge, lineHeight = 25.sp)
        }
    } }
}
@Composable
fun BrainMemorySettings(brain: BrainState, viewModel: PodTrackioViewModel) {
    var newMemory by remember { mutableStateOf("") }
    var clear by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Personal memory", style = MaterialTheme.typography.titleLarge)
        OutlinedTextField(brain.goal, { text -> viewModel.updateBrain { it.copy(goal = text) } }, label = { Text("What do you want to achieve?") }, modifier = Modifier.fillMaxWidth())
        Row(verticalAlignment = Alignment.CenterVertically) { Text("Use personal memories", Modifier.weight(1f)); Switch(brain.personalization, { value -> viewModel.updateBrain { it.copy(personalization = value) } }) }
        Row(verticalAlignment = Alignment.CenterVertically) { Text("Remember explicit preferences from Brain chat", Modifier.weight(1f)); Switch(brain.rememberPreferences, { value -> viewModel.updateBrain { it.copy(rememberPreferences = value) } }) }
        Text("Brain chats and memories stay on this device. Relevant sources and enabled personal context are sent to your AI provider when you ask. Listening alone does not establish personality or beliefs.", style = MaterialTheme.typography.bodySmall)
        brain.memories.forEach { memory ->
            OutlinedTextField(memory.text, { text -> viewModel.updateBrain { it.copy(memories = it.memories.map { m -> if (m.id == memory.id) m.copy(text = text.take(300)) else m }) } }, label = { Text("Memory") }, modifier = Modifier.fillMaxWidth())
            Text("From: ${memory.evidence}", style = MaterialTheme.typography.bodySmall)
            TextButton({ viewModel.updateBrain { it.copy(memories = it.memories.filterNot { m -> m.id == memory.id }) } }) { Text("Forget") }
        }
        OutlinedTextField(newMemory, { newMemory = it }, label = { Text("Add a preference or goal") }, modifier = Modifier.fillMaxWidth())
        Button({ viewModel.updateBrain { it.copy(memories = it.memories + PersonalMemory(text = newMemory.take(300), evidence = "Added in Settings")) }; newMemory = "" }, enabled = newMemory.isNotBlank() && brain.memories.size < 100) { Text("Add memory") }
        TextButton({ clear = true }) { Text("Clear Brain conversation") }
        Text("After forgetting a memory, clear the conversation too if it still contains that information.", style = MaterialTheme.typography.bodySmall)
    }
    if (clear) AlertDialog(onDismissRequest = { clear = false }, title = { Text("Clear Brain conversation?") }, confirmButton = { TextButton({ viewModel.updateBrain { it.copy(messages = emptyList()) }; clear = false }) { Text("Clear") } }, dismissButton = { TextButton({ clear = false }) { Text("Cancel") } })
}
