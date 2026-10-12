package com.tangenix.podtrackio.media

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import com.tangenix.podtrackio.domain.DownloadQuality
import com.tangenix.podtrackio.domain.DownloadRecord
import com.tangenix.podtrackio.domain.Podcast
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant

class DownloadRepository(
    private val context: Context,
    private val mediaTools: MediaTools,
) {
    private val manager = context.getSystemService(DownloadManager::class.java)

    fun fileFor(videoId: String): File = File(
        context.getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: context.filesDir,
        "$videoId.mp4",
    )

    suspend fun download(
        podcast: Podcast,
        quality: DownloadQuality,
        maximumStorageBytes: Long = 8L * 1_024 * 1_024 * 1_024,
        currentStorageBytes: Long = 0,
        onProgress: (Float) -> Unit,
    ): DownloadRecord {
        val media = mediaTools.resolve(podcast.youtubeVideoId, quality)
        media.expectedBytes?.let { expected ->
            check(currentStorageBytes + expected <= maximumStorageBytes) { "The 8 GB PodTrackio download limit would be exceeded." }
        }
        val destination = fileFor(podcast.youtubeVideoId)
        if (destination.exists()) destination.delete()
        val request = DownloadManager.Request(Uri.parse(media.url))
            .setTitle(podcast.title)
            .setDescription("Saving for offline learning")
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(false)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_MOVIES, destination.name)
        val id = manager.enqueue(request)
        while (true) {
            val state = query(id)
            state.progress?.let(onProgress)
            when (state.status) {
                DownloadManager.STATUS_SUCCESSFUL -> break
                DownloadManager.STATUS_FAILED -> error("The download failed (reason ${state.reason}).")
            }
            delay(750)
        }
        check(destination.exists() && destination.length() > 0) { "The downloaded file could not be found." }
        if (currentStorageBytes + destination.length() > maximumStorageBytes) {
            destination.delete()
            error("The 8 GB PodTrackio download limit was reached.")
        }
        return DownloadRecord(podcast.youtubeVideoId, destination.absolutePath, destination.length(), media.height, Instant.now())
    }

    suspend fun delete(record: DownloadRecord) = withContext(Dispatchers.IO) { File(record.filePath).delete() }

    fun reconcile(records: Map<String, DownloadRecord>): Map<String, DownloadRecord> {
        val now = Instant.now()
        records.values.filter { it.expiresAt?.isBefore(now) == true }.forEach { File(it.filePath).delete() }
        val result = records.filterValues { File(it.filePath).exists() && it.expiresAt?.isBefore(now) != true }.toMutableMap()
        val directory = context.getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: return result
        directory.listFiles { file -> file.extension.equals("mp4", true) }?.forEach { file ->
            val videoId = file.nameWithoutExtension
            if (videoId.matches(Regex("^[A-Za-z0-9_-]{11}$")) && result[videoId] == null) {
                result[videoId] = DownloadRecord(videoId, file.absolutePath, file.length(), null, Instant.ofEpochMilli(file.lastModified()))
            }
        }
        return result
    }

    private fun query(id: Long): QueryState {
        manager.query(DownloadManager.Query().setFilterById(id)).use { cursor ->
            check(cursor.moveToFirst()) { "The system download disappeared." }
            val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val reason = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
            val downloaded = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            return QueryState(status, reason, if (total > 0) downloaded.toFloat() / total else null)
        }
    }

    private data class QueryState(val status: Int, val reason: Int, val progress: Float?)
}
