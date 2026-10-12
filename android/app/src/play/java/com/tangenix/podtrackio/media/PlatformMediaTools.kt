package com.tangenix.podtrackio.media

import android.content.Context
import com.tangenix.podtrackio.domain.DownloadQuality
import com.tangenix.podtrackio.domain.PlaylistPreview

class PlatformMediaTools(context: Context) : MediaTools {
    override val supportsExternalMediaTools = false
    override suspend fun initialize() = Unit
    override suspend fun resolve(videoId: String, quality: DownloadQuality): ResolvedMedia =
        throw MediaToolsUnavailable("Direct media playback and downloads are available in the PodTrackio Full build.")
    override suspend fun previewPlaylist(url: String): PlaylistPreview =
        throw MediaToolsUnavailable("Playlist import is available in the PodTrackio Full build.")

    override suspend fun fetchVideoTitle(videoId: String): String? = null
}
