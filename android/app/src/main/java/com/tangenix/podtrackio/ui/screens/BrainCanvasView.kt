package com.tangenix.podtrackio.ui.screens

import android.annotation.SuppressLint
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebResourceRequest
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.tangenix.podtrackio.data.Json
import com.tangenix.podtrackio.domain.BrainSource
import com.tangenix.podtrackio.domain.brainGraphEdges

internal data class CanvasNode(val id: String, val sourceID: String, val title: String, val kind: String)
internal data class CanvasLink(val source: String, val target: String, val type: String)
internal data class CanvasPayload(val nodes: List<CanvasNode>, val links: List<CanvasLink>, val dark: Boolean, val reduceMotion: Boolean)

internal fun canvasPayload(documents: List<BrainSource>, dark: Boolean, reduceMotion: Boolean): CanvasPayload {
    val nodes = mutableListOf<CanvasNode>(); val links = mutableListOf<CanvasLink>(); val seen = mutableSetOf<String>()
    documents.forEach { source ->
        val episode = "episode:${source.podcastId}"
        if (seen.add(source.podcastId)) nodes += CanvasNode(episode, source.id, source.title, "Episode")
        nodes += CanvasNode(source.id, source.id, source.kind, source.kind)
        links += CanvasLink(episode, source.id, "document")
    }
    val pairs = mutableSetOf<String>()
    brainGraphEdges(documents).filterNot { it.sharedEpisode }.forEach { edge ->
        val ids = listOf("episode:${documents[edge.from].podcastId}", "episode:${documents[edge.to].podcastId}").sorted()
        if (pairs.add(ids.joinToString())) links += CanvasLink(ids[0], ids[1], "topic")
    }
    return CanvasPayload(nodes, links, dark, reduceMotion)
}

private class CanvasBridge {
    var select: (String) -> Unit = {}
    @JavascriptInterface fun selectNode(id: String) { select(id) }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun BrainCanvasView(documents: List<BrainSource>, modifier: Modifier = Modifier, onSelect: (BrainSource) -> Unit) {
    val dark = androidx.compose.material3.MaterialTheme.colorScheme.surface.let { it.red * 0.299f + it.green * 0.587f + it.blue * 0.114f < 0.5f }
    val context = androidx.compose.ui.platform.LocalContext.current
    val reduceMotion = android.provider.Settings.Global.getFloat(context.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    val payload = remember(documents, dark, reduceMotion) { Json.gson.toJson(canvasPayload(documents, dark, reduceMotion)) }
    val latestSelect by rememberUpdatedState(onSelect)
    val latestDocuments by rememberUpdatedState(documents)
    val latestPayload by rememberUpdatedState(payload)
    val bridge = remember { CanvasBridge() }
    AndroidView(modifier = modifier, factory = { ctx ->
        WebView(ctx).apply {
            setBackgroundColor(android.graphics.Color.TRANSPARENT)
            settings.javaScriptEnabled = true
            settings.allowFileAccess = true
            settings.allowContentAccess = false
            settings.blockNetworkLoads = true
            settings.builtInZoomControls = false
            settings.displayZoomControls = false
            settings.setSupportZoom(false)
            addJavascriptInterface(bridge, "BrainCanvasNative")
            bridge.select = { id -> post { latestDocuments.firstOrNull { it.id == id }?.let(latestSelect) } }
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) { view.evaluateJavascript("window.brainGraph?.setData($latestPayload);", null) }
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = request.url.toString() != "file:///android_asset/brain-canvas/index.html"
            }
            loadUrl("file:///android_asset/brain-canvas/index.html")
        }
    }, update = { web -> web.evaluateJavascript("window.brainGraph?.setData($payload);", null) }, onReset = null, onRelease = { web ->
        web.evaluateJavascript("window.brainGraph?.dispose();", null)
        web.removeJavascriptInterface("BrainCanvasNative"); web.stopLoading(); web.destroy()
    })
}
