package com.tangenix.podtrackio.media

import com.tangenix.podtrackio.domain.DownloadQuality
import com.tangenix.podtrackio.domain.PlaylistPreview

data class ResolvedMedia(val url: String, val height: Int?, val expectedBytes: Long?)

interface MediaTools {
    val supportsExternalMediaTools: Boolean
    suspend fun initialize()
    suspend fun resolve(videoId: String, quality: DownloadQuality): ResolvedMedia
    suspend fun previewPlaylist(url: String): PlaylistPreview
    suspend fun fetchVideoTitle(videoId: String): String?
}

class MediaToolsUnavailable(message: String) : IllegalStateException(message)
