package com.tangenix.podtrackio.data

import android.content.Context
import android.util.AtomicFile
import com.tangenix.podtrackio.domain.AppSnapshot
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File

class LocalStore(private val context: Context) {
    private val mutex = Mutex()
    private var unreadableSnapshot = false
    private val unreadableHabitFiles = mutableSetOf<String>()
    private val file = AtomicFile(File(context.filesDir, "podtrackio_state.json"))

    suspend fun load(): AppSnapshot = withContext(Dispatchers.IO) {
        mutex.withLock {
            if (!file.baseFile.exists()) return@withLock AppSnapshot()
            runCatching {
                file.openRead().bufferedReader().use { reader ->
                    Json.gson.fromJson(reader, AppSnapshot::class.java)
                }
            }.onFailure { unreadableSnapshot = true }.getOrNull()?.sanitized() ?: AppSnapshot()
        }
    }

    suspend fun save(snapshot: AppSnapshot) = withContext(Dispatchers.IO) {
        mutex.withLock {
            check(!unreadableSnapshot) { "Unreadable workspace was preserved; restore it before saving." }
            val stream = file.startWrite()
            try {
                stream.write(Json.gson.toJson(snapshot.sanitized()).toByteArray(Charsets.UTF_8))
                file.finishWrite(stream)
            } catch (error: Throwable) {
                file.failWrite(stream)
                throw error
            }
            saveHabitFile(snapshot.habitLoop)
            runCatching { com.tangenix.podtrackio.widgets.LearningWidgetProvider.updateAll(context, snapshot) }
        }
    }

    private fun habitFile(ownerID: String?): AtomicFile {
        val suffix = ownerID?.let { java.util.UUID.fromString(it).toString() } ?: "guest"
        return AtomicFile(File(context.filesDir, "habit_loop_$suffix.json"))
    }

    private fun saveHabitFile(loop: com.tangenix.podtrackio.domain.HabitLoop) {
        val target = habitFile(loop.ownerID)
        check(target.baseFile.path !in unreadableHabitFiles) { "Unreadable habit data was preserved; restore it before saving." }
        val output = target.startWrite()
        try {
            output.write(Json.gson.toJson(loop).toByteArray(Charsets.UTF_8))
            target.finishWrite(output)
        } catch (error: Throwable) { target.failWrite(output); throw error }
    }

    suspend fun bindHabitOwner(ownerID: String?, fallback: com.tangenix.podtrackio.domain.HabitLoop): com.tangenix.podtrackio.domain.HabitLoop = withContext(Dispatchers.IO) {
        mutex.withLock {
            val target = habitFile(ownerID)
            if (target.baseFile.exists()) {
                try {
                    val result = target.openRead().bufferedReader().use { Json.gson.fromJson(it, com.tangenix.podtrackio.domain.HabitLoop::class.java) }
                    check(result.ownerID == ownerID) { "Habit owner does not match." }
                    return@withLock result
                } catch (error: Throwable) { unreadableHabitFiles.add(target.baseFile.path); throw error }
            }
            if (fallback.ownerID == ownerID || fallback.ownerID == null) {
                val claimed = fallback.copy(ownerID = ownerID)
                saveHabitFile(claimed)
                if (ownerID != null && fallback.ownerID == null) {
                    val guest = habitFile(null).baseFile
                    if (guest.exists()) check(guest.renameTo(File(guest.path + ".claimed-" + java.util.UUID.randomUUID())))
                }
                claimed
            } else com.tangenix.podtrackio.domain.HabitLoop(ownerID = ownerID)
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
