package com.tangenix.podtrackio

import android.content.Context
import android.content.ContextWrapper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.tangenix.podtrackio.data.Json
import com.tangenix.podtrackio.data.LocalStore
import com.tangenix.podtrackio.domain.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.time.LocalDate
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class HabitPersistenceInstrumentedTest {
    private suspend fun fixture(check: suspend (Context, LocalStore) -> Unit) {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(base.cacheDir, "habit-test-${UUID.randomUUID()}").apply { mkdirs() }
        val context = object : ContextWrapper(base) { override fun getFilesDir() = directory }
        try { check(context, LocalStore(context)) } finally { directory.deleteRecursively() }
    }

    @Test fun chestAndCachedRecallSurviveAtomicRoundTrip() = runBlocking {
        fixture { _, store ->
            val day = LocalDate.now().toString()
            val loop = HabitLoop()
            repeat(90) { loop.record(10.0, day, 15.0) }; loop.reflect(day)
            loop.reconcile(emptyList(), 15.0, chestRoll = 95)
            loop.reviews = listOf(RecallReview(podcastID = "episode", transcriptDigest = "hash", questions = listOf(
                RecallQuestion("q", "What helps?", listOf("Practice", "Cars", "Dogs", "Weather"), 0, "Practice helps.", "Deliberate practice helps learning.")
            )))
            store.save(AppSnapshot(habitLoop = loop))
            val restored = store.load().habitLoop
            restored.reconcile(emptyList(), 15.0, chestRoll = 0)
            assertEquals(35, restored.gems)
            assertEquals(45, restored.rewardXP)
            assertEquals("Deliberate practice helps learning.", restored.reviews.single().questions.single().evidence)
        }
    }

    @Test fun claimingGuestCannotCopyRewardsIntoAnotherAccount() = runBlocking {
        fixture { _, store ->
            val guest = HabitLoop(events = listOf(HabitEvent("chest/${LocalDate.now()}", "${LocalDate.now()}", "gems", 20.0)))
            store.save(AppSnapshot(habitLoop = guest))
            val first = store.bindHabitOwner("11111111-1111-4111-8111-111111111111", guest)
            val second = store.bindHabitOwner("22222222-2222-4222-8222-222222222222", first)
            assertEquals(20, first.gems); assertEquals(0, second.gems)
            assertEquals(20, store.bindHabitOwner(first.ownerID, second).gems)
        }
    }

    @Test fun corruptWorkspaceIsPreservedAndLegacyFilesGetDefaults() = runBlocking {
        fixture { context, store ->
            val file = File(context.filesDir, "podtrackio_state.json")
            val legacy = Json.gson.toJsonTree(AppSnapshot()).asJsonObject.apply { remove("habitLoop") }
            file.writeText(legacy.toString())
            assertNotNull(store.load().habitLoop.deviceID)
            file.writeText("{broken")
            store.load()
            assertTrue(runCatching { store.save(AppSnapshot()) }.isFailure)
            assertEquals("{broken", file.readText())
        }
    }
}
