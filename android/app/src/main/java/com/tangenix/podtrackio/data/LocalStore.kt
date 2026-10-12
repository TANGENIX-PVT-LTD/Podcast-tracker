package com.tangenix.podtrackio.data

import android.content.Context
import android.util.AtomicFile
import com.tangenix.podtrackio.domain.AppSnapshot
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File

class LocalStore(context: Context) {
    private val mutex = Mutex()
    private val file = AtomicFile(File(context.filesDir, "podtrackio_state.json"))

    suspend fun load(): AppSnapshot = withContext(Dispatchers.IO) {
        mutex.withLock {
            if (!file.baseFile.exists()) return@withLock AppSnapshot()
            runCatching {
                file.openRead().bufferedReader().use { reader ->
                    Json.gson.fromJson(reader, AppSnapshot::class.java)
                }
            }.getOrNull()?.sanitized() ?: AppSnapshot()
        }
    }

    suspend fun save(snapshot: AppSnapshot) = withContext(Dispatchers.IO) {
        mutex.withLock {
            val stream = file.startWrite()
            try {
                stream.bufferedWriter().use { writer -> Json.gson.toJson(snapshot.sanitized(), writer) }
                file.finishWrite(stream)
            } catch (error: Throwable) {
                file.failWrite(stream)
                throw error
            }
        }
    }

    private fun AppSnapshot.sanitized(): AppSnapshot {
        val categories = categories.ifEmpty { com.tangenix.podtrackio.domain.LearningCategory.defaults }
        val validIds = categories.mapTo(mutableSetOf()) { it.id }
        return copy(
            categories = categories.sortedBy { it.sortOrder },
            podcasts = podcasts.map { podcast ->
                if (podcast.categoryId in validIds) podcast
                else podcast.copy(categoryId = com.tangenix.podtrackio.domain.LearningCategory.GENERAL_ID)
            }.distinctBy { it.id },
        )
    }
}
