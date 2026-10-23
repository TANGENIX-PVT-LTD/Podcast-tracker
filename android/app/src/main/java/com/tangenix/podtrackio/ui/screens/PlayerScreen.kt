package com.tangenix.podtrackio.ui.screens

import com.tangenix.podtrackio.ui.play.streakInfo
import android.annotation.SuppressLint
import android.app.Activity
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Fullscreen
import androidx.compose.material.icons.rounded.FullscreenExit
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.runtime.key
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
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
import kotlinx.coroutines.isActive
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

@Composable
fun PlayerScreen(
    podcast: Podcast,
    ui: PodTrackioUiState,
    viewModel: PodTrackioViewModel,
    modifier: Modifier = Modifier,
) {
    var transcriptOpen by remember { mutableStateOf(false) }
    var scheduleOpen by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var fullScreen by rememberSaveable(podcast.id) { mutableStateOf(false) }
    var seekRequest by remember(podcast.id) { mutableStateOf<Pair<Long, Double>?>(null) }
    val summary = ui.snapshot.summaries.firstOrNull { it.podcastId == podcast.id }
    val transcript = ui.snapshot.transcripts[podcast.id]
    val context = LocalContext.current
    val transcriptPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            runCatching { context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }.orEmpty() }
                .onSuccess { viewModel.setTranscript(podcast.id, it, TranscriptSource.imported) }
        }
    }
    val importTranscript = { transcriptPicker.launch(arrayOf("text/plain", "text/vtt", "application/x-subrip", "application/octet-stream")) }
    val seekTo: (Double) -> Unit = { seconds -> viewModel.resetPlaybackCredit(); seekRequest = System.nanoTime() to seconds }
    val activity = context as? Activity
    DisposableEffect(activity, fullScreen) {
        val controller = activity?.window?.let { window -> WindowCompat.getInsetsController(window, window.decorView) }
        if (fullScreen) {
            controller?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller?.hide(WindowInsetsCompat.Type.systemBars())
        } else {
            controller?.show(WindowInsetsCompat.Type.systemBars())
        }
        onDispose { if (fullScreen) controller?.show(WindowInsetsCompat.Type.systemBars()) }
    }

    val currentPodcast = ui.snapshot.podcasts.firstOrNull { it.id == podcast.id } ?: podcast

    androidx.activity.compose.BackHandler { if (fullScreen) fullScreen = false else viewModel.selectPodcast(null) }
    var toolsVisible by rememberSaveable(podcast.id) { mutableStateOf(true) }
    val configuration = androidx.compose.ui.platform.LocalConfiguration.current
    val wide = configuration.screenWidthDp >= 900
    Column(modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)
        .then(if (fullScreen) Modifier else Modifier.systemBarsPadding().imePadding())) {
        if (!fullScreen) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton({ viewModel.selectPodcast(null) }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back to library") }
                Text(podcast.title, Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                com.tangenix.podtrackio.ui.play.PlayerGoalChip(ui.snapshot.streakInfo(), Modifier.padding(horizontal = 12.dp))
                TextButton({ toolsVisible = !toolsVisible }) { Text(if (toolsVisible) "Hide learning tools" else "Show learning tools") }
            }
        }
        Row(Modifier.weight(1f).fillMaxWidth()) {
            Column(Modifier.weight(1f).fillMaxHeight()) {
                // A stable composition keeps the same Media3 player alive when fullscreen or tools change.
                Box(Modifier.fillMaxWidth().weight(1f).background(Color.Black)) {
                    if (viewModel.externalMediaToolsAvailable) NativePlayer(podcast, viewModel, seekRequest, ui.playbackStartRequest)
                    else EmbeddedYouTubePlayer(podcast, viewModel, ui.playbackStartRequest, seekRequest)
                    Surface(Modifier.align(Alignment.TopEnd).padding(12.dp), color = Color.Black.copy(alpha = .66f), shape = RoundedCornerShape(12.dp)) {
                        IconButton({ fullScreen = !fullScreen }, Modifier.size(48.dp)) {
                            Icon(if (fullScreen) Icons.Rounded.FullscreenExit else Icons.Rounded.Fullscreen,
                                if (fullScreen) "Exit full screen" else "Enter full screen", tint = Color.White)
                        }
                    }
                }
                if (!fullScreen) {
                    ui.downloadProgress[podcast.id]?.let { LinearProgressIndicator(progress = { it }, modifier = Modifier.fillMaxWidth()) }
                    EpisodeActions(currentPodcast, ui, viewModel, { scheduleOpen = true }, { confirmDelete = true }, Modifier.padding(12.dp))
                    ui.snapshot.focusCommitments.lastOrNull { it.isActive && it.podcastId == podcast.id }?.let {
                        CommitmentBar(it, ui.playingPodcastId == podcast.id, false, viewModel::cancelActiveCommitment, Modifier.fillMaxWidth())
                    }
                    ui.snapshot.focusCommitments.lastOrNull { it.podcastId == podcast.id && it.completedAt != null && it.cancelledAt == null }?.let {
                        CommitmentWin(it, { viewModel.extendCommitment(5) }, { viewModel.extendCommitment(10) }, viewModel::dismissCompletedCommitment)
                    }
                }
            }
            if (!fullScreen && toolsVisible && wide) {
                InspectorSidebar(podcast, ui, viewModel, Modifier.width(400.dp).fillMaxHeight(),
                    onTranscript = { transcriptOpen = true }, onImportTranscript = importTranscript, onSeek = seekTo)
            }
        }
        if (!fullScreen && toolsVisible && !wide) {
            InspectorSidebar(podcast, ui, viewModel, Modifier.fillMaxWidth().weight(1f),
                onTranscript = { transcriptOpen = true }, onImportTranscript = importTranscript, onSeek = seekTo)
        }
    }

    // Dialogs
    if (transcriptOpen) TranscriptDialog(
        initial = transcript?.text.orEmpty(),
        onDismiss = { transcriptOpen = false },
        onSave = { viewModel.setTranscript(podcast.id, it); transcriptOpen = false },
    )
    if (scheduleOpen) ScheduleDialog(podcast, onDismiss = { scheduleOpen = false }, onSelect = { viewModel.schedulePodcast(podcast.id, it); scheduleOpen = false })
    if (confirmDelete) AlertDialog(
        onDismissRequest = { confirmDelete = false },
        title = { Text("Remove this episode?") },
        text = { Text("PodTrackio will remove it from your synced library. Any tablet download is deleted too.") },
        confirmButton = { Button(onClick = { viewModel.removePodcast(podcast.id); confirmDelete = false }) { Text("Remove") } },
        dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel") } },
    )
}

@Composable
private fun CommitmentBar(
    commitment: com.tangenix.podtrackio.domain.FocusCommitment,
    isPlaying: Boolean,
    isStarting: Boolean,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val cue = commitment.cue
    val cueIcon = when (cue) {
        com.tangenix.podtrackio.domain.DistractionCue.TODAY -> Icons.Rounded.Timer
        com.tangenix.podtrackio.domain.DistractionCue.SCROLLING -> Icons.Rounded.Timer
        com.tangenix.podtrackio.domain.DistractionCue.STREAMING -> Icons.Rounded.Timer
        com.tangenix.podtrackio.domain.DistractionCue.ANIME -> Icons.Rounded.Timer
        com.tangenix.podtrackio.domain.DistractionCue.GAMING -> Icons.Rounded.Timer
        com.tangenix.podtrackio.domain.DistractionCue.OTHER -> Icons.Rounded.Timer
        com.tangenix.podtrackio.domain.DistractionCue.NOTIFICATION -> Icons.Rounded.Timer
        com.tangenix.podtrackio.domain.DistractionCue.MOMENTUM -> Icons.Rounded.Timer
    }

    Card(
        modifier = modifier.background(MaterialTheme.colorScheme.surfaceContainerHigh),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        shape = RoundedCornerShape(0.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Icon(
                cueIcon,
                null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(24.dp),
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        if (isPlaying) "Useful time in progress"
                        else if (isStarting) "Starting your learning block…"
                        else "Your ${(commitment.targetSeconds / 60).toInt()}-minute promise is ready",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Spacer(Modifier.weight(1f))
                    Text(
                        if (isPlaying) "${((commitment.targetSeconds - commitment.watchedSeconds) / 60).toInt()} min left"
                        else if (isStarting) "Opening at your last position"
                        else "Press Play to begin",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                LinearProgressIndicator(
                    progress = commitment.progress,
                    modifier = Modifier.fillMaxWidth(),
                    color = MaterialTheme.colorScheme.primary,
                    trackColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.2f),
                )
            }
            IconButton(onClick = onCancel) {
                Icon(Icons.Rounded.Close, "Cancel commitment", tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun CommitmentWin(
    commitment: com.tangenix.podtrackio.domain.FocusCommitment,
    onExtend5: () -> Unit,
    onExtend10: () -> Unit,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val targetMinutes = (commitment.targetSeconds / 60).toInt()
    val cueTitle = when (commitment.cue) {
        com.tangenix.podtrackio.domain.DistractionCue.SCROLLING -> "scrolling"
        com.tangenix.podtrackio.domain.DistractionCue.STREAMING -> "streaming"
        com.tangenix.podtrackio.domain.DistractionCue.ANIME -> "anime"
        com.tangenix.podtrackio.domain.DistractionCue.GAMING -> "gaming"
        com.tangenix.podtrackio.domain.DistractionCue.OTHER -> "distraction"
        com.tangenix.podtrackio.domain.DistractionCue.NOTIFICATION -> "notifications"
        com.tangenix.podtrackio.domain.DistractionCue.TODAY -> "today"
        com.tangenix.podtrackio.domain.DistractionCue.MOMENTUM -> "momentum"
    }
    val isDistraction = commitment.cue in setOf(
        com.tangenix.podtrackio.domain.DistractionCue.SCROLLING,
        com.tangenix.podtrackio.domain.DistractionCue.STREAMING,
        com.tangenix.podtrackio.domain.DistractionCue.ANIME,
        com.tangenix.podtrackio.domain.DistractionCue.GAMING,
        com.tangenix.podtrackio.domain.DistractionCue.OTHER,
        com.tangenix.podtrackio.domain.DistractionCue.NOTIFICATION,
    )
    val title = if (isDistraction) "$targetMinutes minutes reclaimed from $cueTitle" else "You kept your $targetMinutes-minute promise"

    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(16.dp),
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Icon(Icons.Rounded.CheckCircle, null, tint = Color(0xFF2E8B57), modifier = Modifier.size(28.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text("The video can keep playing. Extend only if you want the next small win.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Button(onClick = onExtend5) { Text("+5") }
            OutlinedButton(onClick = onExtend10) { Text("+10") }
            TextButton(onClick = onDone) { Text("Done") }
        }
    }
}

@Composable
private fun VideoWorkspace(
    podcast: Podcast,
    ui: PodTrackioUiState,
    viewModel: PodTrackioViewModel,
    seekRequest: Pair<Long, Double>?,
    modifier: Modifier,
    onFullScreen: () -> Unit,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f)) {
            Card(Modifier.fillMaxSize(), shape = RoundedCornerShape(22.dp)) {
                if (viewModel.externalMediaToolsAvailable) NativePlayer(podcast, viewModel, seekRequest, ui.playbackStartRequest)
                else EmbeddedYouTubePlayer(podcast, viewModel, ui.playbackStartRequest, seekRequest)
            }
            Surface(
                modifier = Modifier.align(Alignment.TopEnd).padding(12.dp),
                color = Color.Black.copy(alpha = .66f),
                shape = RoundedCornerShape(12.dp),
            ) {
                IconButton(onClick = onFullScreen, modifier = Modifier.size(48.dp)) {
                    Icon(Icons.Rounded.Fullscreen, "Enter full screen", tint = Color.White)
                }
            }
        }
        if (!viewModel.externalMediaToolsAvailable) {
            Text("Embedded playback reports actual learning time. The full build adds native playback, playlists and downloads.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        ui.downloadProgress[podcast.id]?.let { progress ->
            LinearProgressIndicator(progress = { progress }, Modifier.fillMaxWidth())
            Text("Saving for offline playback… ${(progress * 100).toInt()}%", style = MaterialTheme.typography.labelSmall)
        }
    }
}

@Composable
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
private fun NativePlayer(podcast: Podcast, viewModel: PodTrackioViewModel, seekRequest: Pair<Long, Double>?, playRequest: String?) {
    val context = LocalContext.current
    var mediaUri by remember(podcast.id) { mutableStateOf<String?>(null) }
    var error by remember(podcast.id) { mutableStateOf<String?>(null) }
    var player by remember(podcast.id) { mutableStateOf<ExoPlayer?>(null) }
    LaunchedEffect(podcast.id) {
        runCatching { viewModel.playbackUri(podcast.id) }
            .onSuccess { mediaUri = it }
            .onFailure { error = it.message ?: "Could not prepare this episode." }
    }
    DisposableEffect(mediaUri) {
        val uri = mediaUri
        if (uri != null) {
            val instance = ExoPlayer.Builder(context).build().apply {
                val observed = this
                addListener(object : Player.Listener {
                    override fun onIsPlayingChanged(isPlaying: Boolean) {
                        if (isPlaying) viewModel.beginPlaybackCredit(podcast.id, observed.currentPosition / 1_000.0)
                        else viewModel.resetPlaybackCredit()
                    }
                    override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) { viewModel.resetPlaybackCredit() }
                })
                setMediaItem(MediaItem.fromUri(uri))
                prepare()
                seekTo((podcast.lastPlaybackPosition * 1_000).toLong())
                playWhenReady = false
            }
            player = instance
            onDispose {
                viewModel.onPlaybackProgress(podcast.id, instance.currentPosition / 1_000.0, instance.duration.coerceAtLeast(0) / 1_000.0, false)
                instance.release()
                player = null
            }
        } else onDispose { }
    }
    LaunchedEffect(player, podcast.id) {
        while (isActive) {
            delay(1_000)
            player?.let { value ->
                viewModel.onPlaybackProgress(
                    podcast.id,
                    value.currentPosition.coerceAtLeast(0) / 1_000.0,
                    value.duration.coerceAtLeast(0) / 1_000.0,
                    value.isPlaying,
                )
            }
        }
    }
    LaunchedEffect(player, playRequest) {
        if (player != null && playRequest == podcast.id && viewModel.consumePlaybackStart(podcast.id)) player?.play()
    }
    LaunchedEffect(player, seekRequest) {
        seekRequest?.second?.let { seconds -> player?.seekTo((seconds * 1_000).toLong()) }
    }
    when {
        error != null -> Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(error.orEmpty(), color = Color.White)
                TextButton(onClick = { error = null; mediaUri = null }) { Icon(Icons.Rounded.Refresh, null); Text("Try again") }
            }
        }
        player == null -> Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        else -> AndroidView(
            factory = { PlayerView(it).apply { this.player = player; useController = true; setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING) } },
            update = { it.player = player },
            modifier = Modifier.fillMaxSize().background(Color.Black),
        )
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun EmbeddedYouTubePlayer(podcast: Podcast, viewModel: PodTrackioViewModel, playRequest: String?, seekRequest: Pair<Long, Double>?) {
    var error by remember(podcast.id) { mutableStateOf<String?>(null) }
    var lastSeek by remember(podcast.id) { mutableStateOf<Long?>(null) }
    val released = remember(podcast.id) { java.util.concurrent.atomic.AtomicBoolean(false) }
    key(podcast.id) {
        Box(Modifier.fillMaxSize()) {
            AndroidView(
                factory = { context -> WebView(context).apply {
                    val browser = this
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    settings.javaScriptEnabled = true
                    settings.mediaPlaybackRequiresUserGesture = false
                    settings.allowFileAccess = false
                    settings.allowContentAccess = false
                    webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean = request?.isForMainFrame == true
                    }
                    addJavascriptInterface(object {
                        @JavascriptInterface fun progress(position: Double, duration: Double, playing: Boolean) {
                            if (!position.isFinite() || !duration.isFinite() || position !in 0.0..604800.0 || duration !in 0.0..604800.0) return
                            browser.post { if (!released.get()) viewModel.onPlaybackProgress(podcast.id, position, duration, playing) }
                        }
                        @JavascriptInterface fun state(position: Double, playing: Boolean) {
                            if (!position.isFinite() || position !in 0.0..604800.0) return
                            browser.post {
                                if (released.get()) return@post
                                if (playing) viewModel.beginPlaybackCredit(podcast.id, position) else viewModel.resetPlaybackCredit()
                            }
                        }
                        @JavascriptInterface fun failure(code: Int) {
                            browser.post { error = "YouTube could not play this video (code $code). Try another episode; no learning credit was added." }
                        }
                    }, "PodTrackioLearning")
                    val autoPlay = viewModel.consumePlaybackStart(podcast.id)
                    loadDataWithBaseURL("https://www.youtube.com", learningPlayerDocument(podcast.youtubeVideoId, podcast.lastPlaybackPosition.toInt(), autoPlay), "text/html", "utf-8", null)
                } },
                update = { browser ->
                    if (playRequest == podcast.id && viewModel.consumePlaybackStart(podcast.id)) browser.evaluateJavascript("window.podTrackioPlay && window.podTrackioPlay();", null)
                    if (seekRequest != null && lastSeek != seekRequest.first) {
                        lastSeek = seekRequest.first
                        viewModel.resetPlaybackCredit()
                        val seconds = seekRequest.second.takeIf { it.isFinite() }?.coerceAtLeast(0.0) ?: 0.0
                        browser.evaluateJavascript("window.podTrackioSeek && window.podTrackioSeek($seconds);", null)
                    }
                },
                onRelease = { browser ->
                    released.set(true)
                    viewModel.stopEmbeddedPlayback(podcast.id)
                    browser.removeJavascriptInterface("PodTrackioLearning")
                    browser.stopLoading(); browser.loadUrl("about:blank"); browser.destroy()
                },
                modifier = Modifier.fillMaxSize().background(Color.Black),
            )
            error?.let { Text(it, Modifier.align(Alignment.BottomCenter).background(Color.Black).padding(16.dp), color = Color.White) }
        }
    }
}

internal fun learningPlayerDocument(videoId: String, startSeconds: Int, autoPlay: Boolean): String {
    require(Regex("^[A-Za-z0-9_-]{11}$").matches(videoId)) { "Invalid YouTube video ID" }
    val start = startSeconds.coerceIn(0, 604800)
    return """<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body,#player{width:100%;height:100%;margin:0;background:#000}</style></head><body><div id="player"></div>
        <script>
        var player, wantPlay=$autoPlay;
        window.podTrackioPlay=function(){wantPlay=true;if(player&&player.playVideo)player.playVideo();};
        window.podTrackioSeek=function(seconds){if(player&&player.seekTo)player.seekTo(seconds,true);};
        function report(){if(player&&player.getCurrentTime&&player.getPlayerState){
            PodTrackioLearning.progress(player.getCurrentTime(),player.getDuration(),player.getPlayerState()===1);}}
        function onYouTubeIframeAPIReady(){player=new YT.Player('player',{videoId:'$videoId',width:'100%',height:'100%',
            playerVars:{start:$start,playsinline:1,origin:'https://www.youtube.com'},events:{
            onReady:function(){if(wantPlay)player.playVideo();report();},
            onStateChange:function(e){PodTrackioLearning.state(player.getCurrentTime(),e.data===1);report();},
            onError:function(e){PodTrackioLearning.failure(e.data);}}});}
        setInterval(report,1000);
        </script><script src="https://www.youtube.com/iframe_api"></script></body></html>""".trimIndent()
}

@Composable
private fun EpisodeActions(
    podcast: Podcast,
    ui: PodTrackioUiState,
    viewModel: PodTrackioViewModel,
    onScheduleClick: () -> Unit,
    onDeleteClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val downloaded = ui.snapshot.downloads.containsKey(podcast.youtubeVideoId)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { viewModel.markCompleted(podcast.id) }, enabled = !podcast.isCompleted) {
                Icon(Icons.Rounded.CheckCircle, null)
                Spacer(Modifier.width(6.dp))
                Text(if (podcast.isCompleted) "Completed" else "Mark Complete")
            }
            if (viewModel.externalMediaToolsAvailable) {
                OutlinedButton(onClick = { if (downloaded) viewModel.deleteDownload(podcast.id) else viewModel.download(podcast.id) }) {
                    Icon(if (downloaded) Icons.Rounded.Delete else Icons.Rounded.Download, null)
                    Spacer(Modifier.width(6.dp))
                    Text(if (downloaded) "Delete download" else "Download")
                }
            }
            OutlinedButton(onClick = onScheduleClick) {
                Icon(Icons.Rounded.Schedule, null)
                Spacer(Modifier.width(6.dp))
                Text("Schedule")
            }
            OutlinedButton(onClick = onDeleteClick) {
                Icon(Icons.Rounded.Delete, null)
                Spacer(Modifier.width(6.dp))
                Text("Remove")
            }
        }
        ui.snapshot.focusCommitments.lastOrNull { it.isActive && it.podcastId == podcast.id }?.let {
            LinearProgressIndicator(progress = { it.progress }, Modifier.fillMaxWidth())
            Text("Focus promise: ${formatDuration(it.watchedSeconds)} / ${formatDuration(it.targetSeconds)}", style = MaterialTheme.typography.labelMedium)
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
        title = { Text("Schedule episode") },
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

@Composable
private fun PlayerTranscriptDialog(
    initial: String,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit,
) {
    var text by remember { mutableStateOf(initial) }
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Transcript") },
        text = {
            Column(Modifier.fillMaxWidth().height(400.dp)) {
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    modifier = Modifier.fillMaxSize(),
                    maxLines = Int.MAX_VALUE,
                    minLines = 20,
                    placeholder = { Text("Paste transcript here…") },
                    singleLine = false,
                )
            }
        },
        confirmButton = { Button(onClick = { onSave(text); onDismiss() }) { Text("Save") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
