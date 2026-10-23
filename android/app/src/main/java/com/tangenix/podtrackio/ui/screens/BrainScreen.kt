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
import kotlinx.coroutines.launch
import androidx.compose.foundation.horizontalScroll
import com.tangenix.podtrackio.ui.play.*

@Composable
fun BrainScreen(ui: PodTrackioUiState, viewModel: PodTrackioViewModel) {
    val context = LocalContext.current
    val preferences = remember { context.getSharedPreferences("brain_composer", android.content.Context.MODE_PRIVATE) }
    var question by rememberSaveable { mutableStateOf("") }
    var filter by rememberSaveable { mutableStateOf("") }
    var workspace by rememberSaveable { mutableStateOf("Chat") }
    var mode by remember { mutableStateOf(com.tangenix.podtrackio.data.BrainMode.ASK) }
    var savedNote by remember { mutableStateOf<String?>(null) }
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
    fun send(text: String = question) {
        if (ui.brainBusy || (text.isBlank() && !mode.allowsEmpty)) return
        PlayFeedback.play(Cue.TAP, sound = false)
        viewModel.askBrain(text.trim(), model, style, mode); question = ""; workspace = "Chat"
    }
    LaunchedEffect(ui.snapshot.brain.messages.size, ui.snapshot.brain.messages.lastOrNull()?.text?.length, workspace) {
        if (workspace == "Chat" && ui.snapshot.brain.messages.isNotEmpty()) scroll.animateScrollToItem(scroll.layoutInfo.totalItemsCount.coerceAtLeast(1) - 1)
    }
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
                else -> LazyColumn(Modifier.fillMaxSize().widthIn(max = 800.dp).align(Alignment.Center).padding(horizontal = 18.dp), state = scroll, verticalArrangement = Arrangement.spacedBy(22.dp), contentPadding = PaddingValues(vertical = 22.dp)) {
                    if (!viewModel.hasGroqKey() || ui.brainNeedsKey) item { BrainKeyCard(viewModel) }
                    val episodes = index.sources.map { it.podcastId }.distinct().size
                    if (ui.snapshot.brain.messages.isEmpty()) item {
                        Column(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            Echo(EchoMood.HAPPY, 118.dp)
                            Text("Think with everything you've learned.", style = playType(24))
                            Text(if (episodes == 0) "Generate a summary or import a transcript, and I'll be able to answer from it."
                                else "I've read $episodes episode${if (episodes == 1) "" else "s"}. Ask, get quizzed, connect ideas or turn them into a plan.",
                                color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                            val titles = ui.snapshot.podcasts.filter { p -> index.sources.any { it.podcastId == p.id } }.sortedByDescending { it.lastWatchedDate }.map { it.title }
                            buildList {
                                titles.firstOrNull()?.let { add("Quiz me on $it" to com.tangenix.podtrackio.data.BrainMode.QUIZ); add("What are the key lessons from $it?" to com.tangenix.podtrackio.data.BrainMode.ASK) }
                                if (titles.size > 1) add("Connect ideas across my episodes" to com.tangenix.podtrackio.data.BrainMode.CONNECT)
                                add("Recap what I learned this week" to com.tangenix.podtrackio.data.BrainMode.RECAP)
                                add("Turn my learning into a 7-day plan" to com.tangenix.podtrackio.data.BrainMode.PLAN)
                            }.take(4).forEach { (prompt, starterMode) ->
                                ChunkyTile({ mode = starterMode; send(prompt) }, Modifier.fillMaxWidth(), radius = 16.dp, enabled = !ui.brainBusy && episodes > 0) {
                                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Icon(modeIcon(starterMode), null, tint = MaterialTheme.colorScheme.primary)
                                        Text(prompt, Modifier.weight(1f).padding(horizontal = 12.dp), style = playType(15, FontWeight.Bold))
                                        Icon(Icons.Rounded.NorthEast, null, Modifier.size(16.dp))
                                    }
                                }
                            }
                        }
                    }
                    items(ui.snapshot.brain.messages, key = { it.id }) { message ->
                        if (message.role == "user") Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                            SelectionContainer { Text(message.text, Modifier.widthIn(max = 620.dp).padding(start = 40.dp).clip(RoundedCornerShape(20.dp)).background(MaterialTheme.colorScheme.primary).padding(horizontal = 16.dp, vertical = 12.dp),
                                color = Color.White, style = playType(16, FontWeight.SemiBold)) }
                        } else Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            val streaming = ui.brainStreamingId == message.id
                            Echo(if (streaming) EchoMood.TALKING else EchoMood.IDLE, 44.dp)
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                if (message.text.isBlank() && streaming) Text("…", style = playType(20)) else BrainAnswerText(message.text)
                                val cited = com.tangenix.podtrackio.data.BrainParsing.cited(message.text).filter { it in 1..message.sources.size }
                                if (!streaming && cited.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    cited.forEach { n ->
                                        val source = message.sources[n - 1]
                                        ChunkyTile({ viewModel.openCitation(source) }, radius = 12.dp) {
                                            Row(Modifier.padding(horizontal = 10.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                                Text("S$n", Modifier.clip(RoundedCornerShape(50)).background(if (source.kind == "Transcript") Palette.gem else Palette.purple).padding(horizontal = 6.dp, vertical = 1.dp), style = playType(12), color = Color.White)
                                                Text(source.title, style = playType(13, FontWeight.Bold), maxLines = 1, modifier = Modifier.widthIn(max = 180.dp))
                                                if (com.tangenix.podtrackio.data.BrainParsing.timestamp(source.text) != null) Icon(Icons.Rounded.PlayArrow, null, Modifier.size(14.dp))
                                            }
                                        }
                                    }
                                }
                                if (!streaming && message.text.isNotBlank()) Row(verticalAlignment = Alignment.CenterVertically) {
                                    TextButton({ clipboard.setText(AnnotatedString(message.text)); PlayFeedback.play(Cue.TAP, sound = false) }) { Icon(Icons.Rounded.ContentCopy, "Copy", Modifier.size(14.dp)); Text("Copy", Modifier.padding(start = 6.dp)) }
                                    val target = cited.firstOrNull()?.let { message.sources[it - 1] } ?: message.sources.firstOrNull()
                                    if (target != null) TextButton({ viewModel.saveBrainNote(target.podcastId, message.text); savedNote = message.id; PlayFeedback.play(Cue.SUCCESS, sound = false); PlayFeedback.sound(com.tangenix.podtrackio.R.raw.pop) }) {
                                        Icon(if (savedNote == message.id) Icons.Rounded.CheckCircle else Icons.Rounded.Download, null, Modifier.size(14.dp), tint = if (savedNote == message.id) Palette.success else LocalContentColor.current)
                                        Text(if (savedNote == message.id) "Saved to notes" else "Save as note", Modifier.padding(start = 6.dp))
                                    }
                                    var sourcesOpen by remember { mutableStateOf(false) }
                                    Box {
                                        if (message.sources.isNotEmpty()) TextButton({ sourcesOpen = true }) { Text("${message.sources.size} sources") }
                                        DropdownMenu(sourcesOpen, { sourcesOpen = false }) { message.sources.forEachIndexed { i, source -> DropdownMenuItem(text = { Text("[S${i + 1}] ${source.title} · ${source.kind}") }, onClick = { inspected = source; sourcesOpen = false }) } }
                                    }
                                }
                            }
                        }
                    }
                    if (ui.brainBusy && ui.brainStreamingId == null) item {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Echo(EchoMood.THINKING, 56.dp)
                            Column { Text(if (mode == com.tangenix.podtrackio.data.BrainMode.QUIZ) "Writing your quiz…" else "Thinking it through…", style = playType(16)); Text("${modelTitle(model)} · reading your sources", style = MaterialTheme.typography.bodySmall) }
                        }
                    }
                    ui.brainError?.let { error -> item {
                        Row(Modifier.fillMaxWidth().chunkyCard(16.dp, fill = Palette.error.copy(alpha = .08f), border = Palette.error.copy(alpha = .45f)).padding(14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Echo(EchoMood.WORRIED, 52.dp)
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Text(error, style = MaterialTheme.typography.bodyMedium)
                                ui.snapshot.brain.messages.lastOrNull()?.takeIf { it.role == "user" }?.let { last ->
                                    ChunkyButton("Try again", { viewModel.askBrain(last.text, model, style, mode, retry = true) }, kind = ChunkyKind.DANGER, small = true, fullWidth = false, enabled = !ui.brainBusy)
                                }
                            }
                        }
                    } }
                }
            }
        }
        Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp).widthIn(max = 800.dp).fillMaxWidth().imePadding().chunkyCard(22.dp).padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                com.tangenix.podtrackio.data.BrainMode.entries.forEach { option ->
                    ChunkyTile({ mode = option; PlayFeedback.play(Cue.SELECT, sound = false) }, selected = mode == option, radius = 12.dp) {
                        Row(Modifier.padding(horizontal = 11.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(modeIcon(option), null, Modifier.size(16.dp), tint = if (mode == option) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(option.title, style = playType(13, FontWeight.Bold), color = if (mode == option) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            BasicTextField(question, { question = it }, Modifier.fillMaxWidth().heightIn(min = 28.dp, max = 140.dp), textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface), keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send), keyboardActions = KeyboardActions(onSend = { send() }), decorationBox = { inner -> if (question.isEmpty()) Text(mode.placeholder, color = MaterialTheme.colorScheme.onSurfaceVariant); inner() })
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
                ChunkyButton(if (mode == com.tangenix.podtrackio.data.BrainMode.QUIZ) "Quiz" else "Send", { send() }, small = true, fullWidth = false,
                    enabled = !ui.brainBusy && (question.isNotBlank() || mode.allowsEmpty), icon = Icons.Rounded.ArrowUpward)
            }
        }
    }
    ui.brainQuiz?.let { (title, questions) ->
        PlayQuiz(title, questions, onFinish = { correct -> viewModel.finishBrainQuiz(correct, questions.size) }, onClose = viewModel::closeBrainQuiz)
    }
    if (settings) Dialog({ settings = false }) { Surface(shape = MaterialTheme.shapes.large) { Column(Modifier.padding(20.dp).verticalScroll(rememberScrollState())) { BrainMemorySettings(ui.snapshot.brain, viewModel); TextButton({ settings = false }) { Text("Done") } } } }
    inspected?.let { source -> AlertDialog(onDismissRequest = { inspected = null }, title = { Text(source.title) }, text = { Column(Modifier.verticalScroll(rememberScrollState())) { Text(source.kind, style = MaterialTheme.typography.labelLarge); SelectionContainer { Text(source.text) } } }, confirmButton = { TextButton({ viewModel.selectPodcast(source.podcastId); inspected = null }) { Text("Open episode") } }, dismissButton = { TextButton({ inspected = null }) { Text("Done") } }) }
    if (newChat) AlertDialog(onDismissRequest = { newChat = false }, title = { Text("Start a new conversation?") }, text = { Text("Your podcast knowledge and personal memories stay available.") }, confirmButton = { TextButton({ viewModel.updateBrain { it.copy(messages = emptyList()) }; workspace = "Chat"; newChat = false }) { Text("Clear conversation") } }, dismissButton = { TextButton({ newChat = false }) { Text("Cancel") } })
}

private fun modelTitle(model: QuirkyModel) = if (model == QuirkyModel.DEEP) "Deep Reasoning" else model.label
private fun styleTitle(style: AnswerStyle) = when (style) { AnswerStyle.CONCISE -> "Concise"; AnswerStyle.MEDIUM -> "Default"; AnswerStyle.DETAILED -> "Detailed" }
private fun modeIcon(mode: com.tangenix.podtrackio.data.BrainMode) = when (mode) {
    com.tangenix.podtrackio.data.BrainMode.ASK -> Icons.AutoMirrored.Rounded.Chat
    com.tangenix.podtrackio.data.BrainMode.QUIZ -> Icons.Rounded.Checklist
    com.tangenix.podtrackio.data.BrainMode.CONNECT -> Icons.Rounded.Hub
    com.tangenix.podtrackio.data.BrainMode.PLAN -> Icons.Rounded.Assignment
    com.tangenix.podtrackio.data.BrainMode.RECAP -> Icons.Rounded.EventRepeat
}

/** Inline Groq key setup, so Brain works without hunting through Settings. */
@Composable
private fun BrainKeyCard(viewModel: PodTrackioViewModel) {
    var key by remember { mutableStateOf("") }
    var status by remember { mutableStateOf<String?>(null) }
    var ok by remember { mutableStateOf(false) }
    var testing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val uriHandler = androidx.compose.ui.platform.LocalUriHandler.current
    Column(Modifier.fillMaxWidth().chunkyCard(20.dp, border = if (ok) Palette.success else MaterialTheme.colorScheme.primary.copy(alpha = .6f)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Echo(if (ok) EchoMood.CHEER else EchoMood.THINKING, 64.dp)
            Column {
                Text(if (ok) "Brain is connected!" else "Connect Brain in 30 seconds", style = playType(18))
                Text("Brain uses your own free Groq API key, stored encrypted on this device only.", style = MaterialTheme.typography.bodySmall)
            }
        }
        if (!ok) {
            TextButton({ uriHandler.openUri("https://console.groq.com/keys") }) { Text("Get a free key at console.groq.com") }
            OutlinedTextField(key, { key = it }, Modifier.fillMaxWidth(), placeholder = { Text("Paste your gsk_… key") }, singleLine = true,
                visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation())
            ChunkyButton(if (testing) "Checking…" else "Save & test", {
                testing = true
                scope.launch {
                    viewModel.saveAndTestGroq(key.trim()).onSuccess { ok = true; status = "Connected. Ask me anything about your episodes."; PlayFeedback.play(Cue.CORRECT) }
                        .onFailure { status = it.message; PlayFeedback.play(Cue.WRONG) }
                    testing = false
                }
            }, kind = ChunkyKind.SUCCESS, small = true, enabled = !testing && key.trim().length >= 20)
        }
        status?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = if (ok) Palette.success else Palette.error) }
    }
}

private fun sourceIcon(kind: String) = when (kind) { "Transcript" -> Icons.Rounded.Description; "Summary" -> Icons.Rounded.AutoAwesome; else -> Icons.AutoMirrored.Rounded.Chat }

@Composable
private fun BrainAnswerText(text: String) {
    SelectionContainer { Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        text.split("\n\n").forEach { block ->
            if (block.startsWith("#")) Text(block.replace(Regex("^#{1,6}\\s*"), ""), style = playType(18))
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
