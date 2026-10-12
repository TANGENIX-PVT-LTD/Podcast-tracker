package com.tangenix.podtrackio

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.tangenix.podtrackio.data.LocalStore
import com.tangenix.podtrackio.data.SecureStore
import com.tangenix.podtrackio.domain.AppSnapshot
import com.tangenix.podtrackio.domain.DownloadQuality
import com.tangenix.podtrackio.domain.Podcast
import com.tangenix.podtrackio.media.PlatformMediaTools
import com.tangenix.podtrackio.media.DownloadRepository
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FullRuntimeInstrumentedTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun androidKeystoreAndAtomicJsonStoreRoundTrip() = runBlocking {
        val secureStore = SecureStore(context)
        val testKey = "instrumented_runtime_secret"
        secureStore.put(testKey, "encrypted-value")
        assertEquals("encrypted-value", secureStore.get(testKey))
        secureStore.remove(testKey)

        val store = LocalStore(context)
        val previous = store.load()
        try {
            val fixture = AppSnapshot(podcasts = listOf(Podcast(
                id = "round-trip", title = "Round trip",
                url = "https://www.youtube.com/watch?v=aircAruvnKk",
                youtubeVideoId = "aircAruvnKk", lastPlaybackPosition = 91.0,
            )))
            store.save(fixture)
            assertEquals(91.0, store.load().podcasts.single().lastPlaybackPosition, 0.001)
        } finally {
            store.save(previous)
        }
    }

    @Test
    fun resolvesPublicYouTubeEpisodeForNativeMedia3Playback() = runBlocking {
        val mediaTools = PlatformMediaTools(context)
        val media = withTimeout(120_000) {
            mediaTools.initialize()
            mediaTools.resolve("aircAruvnKk", DownloadQuality.SAVER_480)
        }
        assertTrue(media.url.startsWith("https://"))
        assertTrue(media.url.length > 100)
        assertTrue(media.height == null || media.height!! <= 480)
    }

    @Test
    fun downloadsAndDeletesShortEpisodeForOfflinePlayback() = runBlocking {
        val podcast = Podcast(
            id = "download-runtime",
            title = "Offline runtime test",
            url = "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            youtubeVideoId = "jNQXAC9IVRw",
        )
        val repository = DownloadRepository(context, PlatformMediaTools(context))
        repository.fileFor(podcast.youtubeVideoId).delete()
        val record = withTimeout(120_000) {
            repository.download(podcast, DownloadQuality.SAVER_480) { }
        }
        assertTrue(repository.fileFor(podcast.youtubeVideoId).exists())
        assertTrue(record.byteCount > 0)
        assertTrue(repository.reconcile(mapOf(record.videoId to record)).containsKey(record.videoId))
        repository.delete(record)
        assertTrue(!repository.fileFor(podcast.youtubeVideoId).exists())
    }
}
