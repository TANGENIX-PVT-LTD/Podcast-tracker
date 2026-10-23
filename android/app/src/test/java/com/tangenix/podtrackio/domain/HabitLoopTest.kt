package com.tangenix.podtrackio.domain

import org.junit.Assert.*
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

class HabitLoopTest {
    private val day = LocalDate.parse("2026-10-22")
    private fun play(loop: HabitLoop, seconds: Int) { repeat(seconds / 10) { loop.record(10.0, day.toString(), 15.0) } }

    @Test fun `elapsed credit ignores skips duplicates pauses and suspension`() {
        val credit = PlaybackCreditTracker()
        assertEquals(0.0, credit.sample(10.0, true, 100.0), .001)
        assertEquals(1.0, credit.sample(14.0, true, 101.0), .001)
        assertEquals(0.0, credit.sample(14.0, true, 102.0), .001)
        assertEquals(0.0, credit.sample(90.0, true, 103.0), .001)
        assertEquals(0.0, credit.sample(91.0, false, 104.0), .001)
        assertEquals(0.0, credit.sample(92.0, true, 130.0), .001)
    }

    @Test fun `first elapsed second counts at half speed`() {
        val tracker = PlaybackCreditTracker(); tracker.begin(0.0, 10.0)
        assertEquals(1.0, tracker.sample(.5, true, 11.0), .001)
    }

    @Test fun `late progress corrects leagues and inactive weeks demote`() {
        val loop = HabitLoop(startedDay = "2026-10-12")
        loop.reconcile(emptyList(), 15.0, LocalDate.parse("2026-10-12"))
        loop.reconcile(emptyList(), 15.0, LocalDate.parse("2026-10-19"))
        val history = (12..16).map { DailyLearningActivity("2026-10-$it", 900.0, goalMinutes = 15.0) }
        loop.reconcile(history, 60.0, LocalDate.parse("2026-10-19"))
        assertEquals(1, loop.league(history, LocalDate.parse("2026-10-19")).tier)
        assertEquals(75.0, loop.league(history, LocalDate.parse("2026-10-19")).targetMinutes, .001)
        loop.reconcile(history, 15.0, LocalDate.parse("2026-11-02"))
        assertEquals(0, loop.league(history, LocalDate.parse("2026-11-02")).tier)
        assertTrue(loop.has("league-result/2026-10-26"))
    }

    @Test fun `promise needs actual learning and rewards only once`() {
        val loop = HabitLoop(startedDay = "2026-10-01", events = listOf(HabitEvent("wager/2026-10-04", "2026-10-04", "wager")))
        val history = mutableListOf(DailyLearningActivity("2026-10-01", 300.0, goalMinutes = 15.0))
        history += (4..9).map { DailyLearningActivity("2026-10-" + it.toString().padStart(2, '0'), 300.0, goalMinutes = 15.0) }
        assertEquals(1, loop.streak(history, LocalDate.parse("2026-10-10")).freezes)
        loop.reconcile(history, 15.0, LocalDate.parse("2026-10-10")); assertEquals(0, loop.gems)
        history += DailyLearningActivity("2026-10-10", 300.0, goalMinutes = 15.0)
        loop.reconcile(history, 15.0, LocalDate.parse("2026-10-10")); assertEquals(40, loop.gems)
        loop.reconcile(history, 15.0, LocalDate.parse("2026-10-11")); assertEquals(40, loop.gems)
    }

    @Test fun `chest survives replay and boosts only future playback`() {
        val loop = HabitLoop(startedDay = day.toString())
        play(loop, 900); loop.reflect(day.toString())
        assertEquals(4, loop.reconcile(emptyList(), 15.0, day, 95).size)
        assertEquals(35, loop.gems); assertEquals(45, loop.rewardXP)
        assertEquals(900.0, loop.boostSeconds, .001)
        assertTrue(loop.reconcile(emptyList(), 15.0, day, 0).isEmpty())
        assertEquals(35, loop.gems)
        play(loop, 60); loop.reconcile(emptyList(), 15.0, day)
        assertEquals(47, loop.rewardXP); assertEquals(840.0, loop.boostSeconds, .001)
    }

    @Test fun `offline devices cannot multiply an earned boost budget`() {
        val loop = HabitLoop(events = listOf(HabitEvent("boost/2026-10-20", "2026-10-20", "boost", 900.0)))
        listOf("2026-10-20", "2026-10-21").forEach { day ->
            loop.insert(HabitEvent("boost-use/device/$day", day, "boost-use", 900.0))
            (1..15).forEach { minute -> loop.insert(HabitEvent("boost-xp/$day/$minute", day, "xp", 1.0)) }
        }
        assertEquals(15, loop.rewardXP)
        loop.insert(HabitEvent("boost/2026-10-22", "2026-10-22", "boost", 900.0))
        assertEquals(15, loop.rewardXP); assertEquals(900.0, loop.boostSeconds, .001)
    }

    @Test fun `legacy history does not receive retroactive rewards`() {
        val loop = HabitLoop(startedDay = day.toString(), legacyXP = 500)
        val history = (19..22).map { DailyLearningActivity(dateKey = "2026-10-$it", watchedSeconds = 900.0, goalMinutes = 15.0) }
        loop.reconcile(history, 15.0, day)
        assertEquals(0, loop.rewardXP); assertEquals(0, loop.gems); assertTrue(loop.badges.isEmpty())
        assertEquals(4, loop.streak(history, day).count)
    }

    @Test fun `freezes preserve continuity without adding learning days`() {
        val loop = HabitLoop(startedDay = "2026-10-19")
        val history = listOf(DailyLearningActivity(dateKey = "2026-10-19", watchedSeconds = 300.0, goalMinutes = 15.0))
        val preserved = loop.streak(history, day)
        assertEquals(1, preserved.count); assertEquals(0, preserved.freezes); assertEquals(2, preserved.frozenDays.size)
        assertEquals(0, loop.streak(history, day.plusDays(1)).count)
    }

    @Test fun `sync merges monotonic contributions and canonical receipts`() {
        val loop = HabitLoop(events = listOf(HabitEvent("playback/local/$day", "$day", "playback", 310.0), HabitEvent("chest/$day", "$day", "gems", 20.0)))
        val remote = listOf(HabitEvent("playback/local/$day", "$day", "playback", 300.0), HabitEvent("playback/remote/$day", "$day", "playback", 100.0), HabitEvent("chest/$day", "$day", "gems", 5.0))
        loop.merge(remote); loop.merge(remote)
        assertEquals(3, loop.events.size); assertEquals(410.0, loop.learnedSeconds("$day"), .001); assertEquals(5, loop.gems)
    }

    @Test fun `recall requires real evidence and honors review schedule`() {
        val text = "An actual transcript passage about deliberate practice."
        val question = RecallQuestion("1", "What is discussed?", listOf("Practice", "Cars", "Dogs", "Weather"), 0, "The speaker discusses practice.", "transcript passage about deliberate practice")
        assertTrue(question.isValid(text)); assertFalse(question.copy(evidence = "This passage does not exist anywhere").isValid(text))
        val review = RecallReview(podcastID = "episode", transcriptDigest = "hash", questions = listOf(question), createdDay = day.toString())
        assertEquals(0, review.dueStage(day)); assertNull(review.copy(completedStages = setOf(0)).dueStage(day))
        assertEquals(1, review.copy(completedStages = setOf(0)).dueStage(day.plusDays(1)))
        assertNull(review.copy(completedStages = setOf(0, 1, 3, 7)).dueStage(day.plusDays(30)))
    }

    @Test fun `reminders respect quiet hours daily cap and actual pause`() {
        val now = Instant.parse("2026-10-22T00:00:00Z")
        val snapshot = AppSnapshot(habitLoop = HabitLoop(lastOpenedAt = now), podcasts = listOf(Podcast(title = "An idea", url = "https://youtu.be/abcdefghijk", youtubeVideoId = "abcdefghijk")))
        val plan = HabitReminderPlanner.plan(snapshot, now, ZoneOffset.UTC)
        assertTrue(plan.groupBy { it.day }.values.all { it.size <= 3 })
        assertTrue(plan.all { it.fireTime.atZone(ZoneOffset.UTC).hour in 8..21 })
        assertEquals(1, plan.count { it.day == "2026-10-29" })
        assertTrue(HabitReminderPlanner.plan(snapshot, Instant.parse("2026-10-30T00:00:00Z"), ZoneOffset.UTC).isEmpty())
        val zone = java.time.ZoneId.systemDefault()
        val commitments = listOf("2026-10-01", "2026-10-08", "2026-10-15").map {
            FocusCommitment(podcastId = "episode", cue = DistractionCue.SCROLLING, targetSeconds = 300.0,
                createdAt = LocalDate.parse(it).atTime(9, 10).atZone(zone).toInstant())
        }
        val rescued = HabitReminderPlanner.plan(snapshot.copy(focusCommitments = commitments), now, zone)
        assertTrue(rescued.any { it.day == "2026-10-22" && it.fireTime.atZone(zone).hour == 14 })
        play(snapshot.habitLoop, 900)
        assertFalse(HabitReminderPlanner.plan(snapshot, now, ZoneOffset.UTC).any { it.day == "2026-10-22" })
    }
}
