package com.tangenix.podtrackio.media

import android.content.Context
import com.google.gson.JsonObject
import com.tangenix.podtrackio.data.Json
import com.tangenix.podtrackio.domain.DownloadQuality
import com.tangenix.podtrackio.domain.PlaylistEpisode
import com.tangenix.podtrackio.domain.PlaylistPreview
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.URI

class PlatformMediaTools(private val context: Context) : MediaTools {
    override val supportsExternalMediaTools = true
    @Volatile private var initialized = false

    override suspend fun initialize() = withContext(Dispatchers.IO) {
        if (!initialized) {
            YoutubeDL.getInstance().init(context.applicationContext)
            initialized = true
        }
    }

    override suspend fun resolve(videoId: String, quality: DownloadQuality): ResolvedMedia = withContext(Dispatchers.IO) {
        initialize()
        require(videoId.matches(Regex("^[A-Za-z0-9_-]{11}$"))) { "Invalid YouTube video ID." }
        val request = YoutubeDLRequest("https://www.youtube.com/watch?v=$videoId").apply {
            addOption("--no-playlist")
            addOption("--no-warnings")
            addOption("-f", "best[height<=${quality.maxHeight}][ext=mp4]/18/best[height<=${quality.maxHeight}]")
        }
        val info = YoutubeDL.getInstance().getInfo(request)
        val directUrl = info.url?.takeIf { it.isNotBlank() } ?: error("No playable stream was returned.")
        ResolvedMedia(directUrl, info.height, info.fileSize.takeIf { it > 0 } ?: info.fileSizeApproximate.takeIf { it > 0 })
    }

    override suspend fun previewPlaylist(url: String): PlaylistPreview = withContext(Dispatchers.IO) {
        initialize()
        val playlistId = runCatching {
            URI(url.trim()).rawQuery.orEmpty().split('&').firstNotNullOfOrNull { pair ->
                pair.split('=', limit = 2).let { it.getOrNull(1)?.takeIf { _ -> it.firstOrNull() == "list" } }
            }
        }.getOrNull()?.takeIf(String::isNotBlank) ?: error("Enter a valid public YouTube playlist URL.")
        val request = YoutubeDLRequest(url.trim()).apply {
            addOption("--flat-playlist")
            addOption("--dump-single-json")
            addOption("--no-warnings")
            addOption("--no-download")
        }
        val response = YoutubeDL.getInstance().execute(request)
        val root = Json.gson.fromJson(response.out, JsonObject::class.java)
        var unavailable = 0
        val episodes = root.getAsJsonArray("entries")?.mapIndexedNotNull { index, element ->
            val item = element?.takeIf { it.isJsonObject }?.asJsonObject
            val id = item?.get("id")?.takeUnless { it.isJsonNull }?.asString
            val title = item?.get("title")?.takeUnless { it.isJsonNull }?.asString
            if (id?.length != 11 || title.isNullOrBlank() || title.contains("private video", true) || title.contains("deleted video", true)) {
                unavailable += 1
                null
            } else {
                PlaylistEpisode(
                    videoId = id,
                    title = title,
                    url = "https://www.youtube.com/watch?v=$id",
                    thumbnailUrl = item.get("thumbnail")?.takeUnless { it.isJsonNull }?.asString
                        ?: "https://img.youtube.com/vi/$id/mqdefault.jpg",
                    playlistIndex = index,
                )
            }
        }.orEmpty()
        check(episodes.isNotEmpty()) { "No available videos were found in this playlist." }
        PlaylistPreview(
            playlistId = root.get("id")?.takeUnless { it.isJsonNull }?.asString ?: playlistId,
            title = root.get("title")?.takeUnless { it.isJsonNull }?.asString ?: "YouTube Playlist",
            sourceUrl = url.trim(), episodes = episodes, unavailableCount = unavailable,
        )
    }

    override suspend fun fetchVideoTitle(videoId: String): String? = withContext(Dispatchers.IO) {
        initialize()
        require(videoId.matches(Regex("^[A-Za-z0-9_-]{11}$"))) { "Invalid YouTube video ID." }
        val request = YoutubeDLRequest("https://www.youtube.com/watch?v=$videoId").apply {
            addOption("--no-playlist")
            addOption("--no-warnings")
            addOption("--get-title")
        }
        val response = YoutubeDL.getInstance().execute(request)
        response.out.trim().takeIf(String::isNotBlank)
    }
}
