package com.tangenix.podtrackio.domain

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale

class ModelsTest {
    @Test
    fun `extractVideoId accepts supported YouTube forms`() {
        val id = "dQw4w9WgXcQ"
        assertEquals(id, Podcast.extractVideoId(id))
        assertEquals(id, Podcast.extractVideoId("https://www.youtube.com/watch?v=$id&t=10"))
        assertEquals(id, Podcast.extractVideoId("https://youtu.be/$id?si=test"))
        assertEquals(id, Podcast.extractVideoId("https://www.youtube.com/shorts/$id"))
        assertEquals(id, Podcast.extractVideoId("https://www.youtube.com/embed/$id"))
    }

    @Test
    fun `extractVideoId rejects unrelated and malformed inputs`() {
        assertNull(Podcast.extractVideoId("https://example.com/watch?v=dQw4w9WgXcQ"))
        assertNull(Podcast.extractVideoId("too-short"))
        assertNull(Podcast.extractVideoId(""))
    }

    @Test
    fun `sync merge keeps the newest playback mutation`() {
        val local = podcast(lastWatched = "2026-09-04T10:00:00Z", position = 55.0)
        val remote = podcast(lastWatched = "2026-09-04T11:00:00Z", position = 155.0)
        assertSame(remote, local.mergedForSync(remote))
        assertSame(remote, remote.mergedForSync(local))
    }

    @Test
    fun `sync merge falls back to date added before first watch`() {
        val older = podcast(added = "2026-09-01T10:00:00Z")
        val newer = podcast(added = "2026-09-02T10:00:00Z")
        assertSame(newer, older.mergedForSync(newer))
    }

    @Test
    fun `quirky context remains bounded and prioritizes question terms`() {
        val filler = (1..1_000).joinToString("\n") { "General filler line $it about an unrelated topic." }
        val transcript = "$filler\nThe antifragile strategy uses optionality and redundancy.\nMore explanation of optionality.\n$filler"
        val excerpt = QuirkyContext.transcriptExcerpt(transcript, "What does optionality mean in the antifragile strategy?")
        assertTrue(excerpt.length <= QuirkyContext.MAX_TRANSCRIPT_CHARS)
        assertTrue(excerpt.contains("optionality"))
        assertTrue(excerpt.contains("antifragile"))
    }

    @Test
    fun `formatDuration supports tablet player time labels`() {
        assertEquals("0:00", formatDuration(-1.0))
        assertEquals("2:05", formatDuration(125.0))
        assertEquals("1:01:01", formatDuration(3661.0))
    }

    @Test
    fun `adaptive daily targets repeat twice and ignore misses`() {
        val loop = HabitLoop()
        assertEquals(5.0, loop.prepareDailyGoal("2026-10-20"), .001)
        loop.insert(HabitEvent("playback/mac/2026-10-20", "2026-10-20", "playback", 300.0))
        assertEquals(5.0, loop.prepareDailyGoal("2026-10-21"), .001)
        loop.insert(HabitEvent("playback/phone/2026-10-21", "2026-10-21", "playback", 300.0))
        assertEquals(6.0, loop.prepareDailyGoal("2026-10-22"), .001)
        assertEquals(6.0, loop.prepareDailyGoal("2026-10-25"), .001)
        loop.insert(HabitEvent("playback/mac/2026-10-25", "2026-10-25", "playback", 300.0))
        assertFalse(loop.completedGoal("2026-10-25"))
        loop.insert(HabitEvent("playback/phone/2026-10-25", "2026-10-25", "playback", 60.0))
        assertTrue(loop.completedGoal("2026-10-25"))
        assertEquals(6.0, loop.prepareDailyGoal("2026-10-25"), .001)
    }

    @Test
    fun `adaptive distraction pattern needs repetition and leads by ten minutes`() {
        val zone = ZoneId.systemDefault()
        val now = LocalDate.of(2026, 9, 10).atTime(18, 0).atZone(zone).toInstant()
        val observations = listOf(40, 44, 48).mapIndexed { index, minute ->
            FocusCommitment(
                podcastId = "episode-$index",
                cue = DistractionCue.SCROLLING,
                targetSeconds = 300.0,
                createdAt = LocalDate.of(2026, 9, 3).atTime(16, minute).atZone(zone).toInstant(),
            )
        }
        val pattern = DistractionPatternEngine.leadingPattern(observations, now)
        assertEquals(DistractionCue.SCROLLING, pattern?.cue)
        assertEquals(16, pattern?.hour)
        assertEquals(34, pattern?.minute)
        assertEquals(3, pattern?.observations)
        assertNull(DistractionPatternEngine.leadingPattern(observations.take(2), now))
    }

    private fun podcast(
        added: String = "2026-09-01T09:00:00Z",
        lastWatched: String? = null,
        position: Double = 0.0,
    ) = Podcast(
        id = "podcast-id",
        title = "Test episode",
        url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        youtubeVideoId = "dQw4w9WgXcQ",
        dateAdded = Instant.parse(added),
        lastWatchedDate = lastWatched?.let(Instant::parse),
        lastPlaybackPosition = position,
    )
}
