package com.tangenix.podtrackio.domain

import java.time.Instant
import java.time.LocalDate
import java.time.DayOfWeek
import java.time.temporal.TemporalAdjusters
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

class PlaybackCreditTracker {
    private var position: Double? = null
    private var uptime: Double? = null
    fun reset() { position = null; uptime = null }
    fun begin(next: Double, now: Double = System.nanoTime() / 1e9) { position = next; uptime = now }
    fun sample(next: Double, playing: Boolean, now: Double = System.nanoTime() / 1e9): Double {
        val previous = position; val time = uptime
        position = next; uptime = now
        if (!playing || !next.isFinite() || previous == null || time == null) return 0.0
        val elapsed = now - time; val advance = next - previous
        return if (elapsed > 0 && elapsed <= 10 && advance > 0 && advance <= elapsed * 4 + .25) elapsed else 0.0
    }
}

data class HabitEvent(val id: String, val day: String, val kind: String, val value: Double = 0.0, val detail: String = "")
data class RecallQuestion(val id: String, val question: String, val choices: List<String>, val answer: Int, val explanation: String, val evidence: String) {
    fun isValid(transcript: String) = question.isNotBlank() && choices.size == 4 && choices.distinct().size == 4 && choices.all { it.isNotBlank() }
        && answer in 0..3 && explanation.isNotBlank() && evidence.length >= 12 && transcript.contains(evidence, ignoreCase = true)
}
data class RecallReview(val id: String = UUID.randomUUID().toString(), val podcastID: String, val transcriptDigest: String,
    val questions: List<RecallQuestion>, val createdDay: String = LocalDate.now().toString(), val completedStages: Set<Int> = emptySet()) {
    fun dueStage(day: LocalDate = LocalDate.now()): Int? {
        val elapsed = java.time.temporal.ChronoUnit.DAYS.between(LocalDate.parse(createdDay), day)
        return listOf(0, 1, 3, 7).firstOrNull { elapsed >= it && it !in completedStages }
    }
}
data class HabitReminderExposure(val id: String, val day: String, val template: Int, val fireTime: Instant, val baselineSeconds: Double = 0.0, val completed: Boolean = false)
data class HabitStreak(val count: Int, val freezes: Int, val frozenDays: Set<String>)
data class HabitLeague(val tier: Int, val targetMinutes: Double, val minutes: Double, val activeDays: Int, val history: List<Pair<String, Double>>) {
    val title get() = listOf("Bronze", "Silver", "Gold", "Platinum", "Diamond")[tier.coerceIn(0, 4)]
}
data class HabitSyncResponse(val legacyXP: Int, val startedDay: String, val events: List<HabitEvent>)

data class HabitLoop(
    var ownerID: String? = null,
    var startedDay: String = LocalDate.now().toString(),
    var deviceID: String = UUID.randomUUID().toString(),
    var legacyXP: Int = 0,
    var events: List<HabitEvent> = emptyList(),
    var reviews: List<RecallReview> = emptyList(),
    var lastOpenedAt: Instant? = null,
    var soundsEnabled: Boolean = true,
    var hapticsEnabled: Boolean = true,
    var reminderHistory: List<HabitReminderExposure> = emptyList(),
) {
    val rewardXP: Int get() {
        val ordinary = events.filter { it.kind == "xp" && !it.id.startsWith("boost-xp/") }.sumOf { it.value.toInt() }
        val allocation = boostAllocation().first
        val bonus = events.filter { it.kind == "xp" && it.id.startsWith("boost-xp/") }.groupBy { it.day }
        return ordinary + bonus.entries.sumOf { (day, receipts) -> min(receipts.size, ((allocation[day] ?: 0.0) / 60).toInt()) }
    }
    val gems get() = max(0, events.filter { it.kind == "gems" || it.kind == "spend" }.sumOf { it.value.toInt() })
    val badges get() = events.filter { it.kind == "badge" }.sortedByDescending { it.day }
    private fun boostAllocation(): Pair<Map<String, Double>, Double> {
        val grants = events.filter { it.kind == "boost" }.groupBy { it.day }.mapValues { (_, rows) -> rows.sumOf { it.value } }
        val uses = events.filter { it.kind == "boost-use" }.groupBy { it.day }.mapValues { (_, rows) -> rows.sumOf { it.value } }
        var balance = 0.0
        val byDay = mutableMapOf<String, Double>()
        (grants.keys + uses.keys).sorted().forEach { day ->
            balance += grants[day] ?: 0.0
            val credit = min(balance, uses[day] ?: 0.0)
            byDay[day] = credit; balance -= credit
        }
        return byDay to balance
    }
    val boostSeconds get() = boostAllocation().second
    fun has(id: String) = events.any { it.id == id }
    fun learnedSeconds(day: String) = events.filter { it.kind == "playback" && it.day == day }.sumOf { it.value }
    fun localSeconds(day: String) = events.firstOrNull { it.id == "playback/$deviceID/$day" }?.value ?: 0.0
    fun questCount(day: String) = (1..3).count { has("quest/$day/$it/xp") }
    fun goalSeconds(day: String, fallback: Double = 300.0): Double =
        events.firstOrNull { it.id == "adaptive-goal/$day" }?.value ?: events.firstOrNull { it.id == "goal/$day" }?.value ?: fallback
    fun completedGoal(day: String) = learnedSeconds(day) >= goalSeconds(day)
    fun prepareDailyGoal(day: String = LocalDate.now().toString()): Double {
        events.firstOrNull { it.id == "adaptive-goal/$day" }?.let { return it.value / 60 }
        val successes = events.count { it.id.startsWith("adaptive-goal/") && it.day < day && learnedSeconds(it.day) >= it.value }
        val minutes = min(60, 5 + successes / 2).toDouble()
        insert(HabitEvent("adaptive-goal/$day", day, "goal", minutes * 60, "daily-v2"))
        return minutes
    }
    fun insert(event: HabitEvent): Boolean {
        if (has(event.id) || !event.value.isFinite()) return false
        events = events + event
        return true
    }
    fun record(seconds: Double, day: String, goalMinutes: Double) {
        if (!seconds.isFinite() || seconds <= 0 || seconds > 10) return
        insert(HabitEvent("goal/$day", day, "goal", max(5.0, goalMinutes) * 60))
        val id = "playback/$deviceID/$day"
        val old = events.firstOrNull { it.id == id }
        events = events.filterNot { it.id == id } + HabitEvent(id, day, "playback", (old?.value ?: 0.0) + seconds)
        val boosted = min(seconds, boostSeconds)
        if (boosted > 0) {
            val boostId = "boost-use/$deviceID/$day"
            val used = events.firstOrNull { it.id == boostId }?.value ?: 0.0
            events = events.filterNot { it.id == boostId } + HabitEvent(boostId, day, "boost-use", used + boosted)
        }
    }
    fun reflect(day: String = LocalDate.now().toString()) { insert(HabitEvent("reflection/$day", day, "reflection")) }
    private fun playbackByDay() = events.filter { it.kind == "playback" }.groupBy { it.day }.mapValues { (_, values) -> values.sumOf { it.value } }
    fun learningDays(activities: List<DailyLearningActivity>): Set<String> {
        val adaptiveDays = events.filter { it.id.startsWith("adaptive-goal/") }.map { it.day }.toSet()
        return activities.filter { it.dateKey !in adaptiveDays && it.qualifiesForStreak }.map { it.dateKey }.toSet() +
            playbackByDay().filter { (day, seconds) -> seconds >= if (day in adaptiveDays) goalSeconds(day) else 300.0 }.keys
    }

    fun streak(activities: List<DailyLearningActivity>, today: LocalDate = LocalDate.now()): HabitStreak {
        val learned = learningDays(activities)
        var cursor = learned.minOrNull()?.let(LocalDate::parse) ?: return HabitStreak(0, 2, emptySet())
        var freezes = 2; var count = 0; var active = 0
        val frozen = mutableSetOf<String>()
        val refills = events.filter { it.kind == "freeze-refill" }.groupingBy { it.day }.eachCount()
        while (!cursor.isAfter(today)) {
            val key = cursor.toString()
            if (key >= startedDay) freezes = min(2, freezes + (refills[key] ?: 0))
            if (key in learned) {
                count++
                if (key >= startedDay) { active++; if (active % 7 == 0) freezes = min(2, freezes + 1) }
            } else if (cursor < today) {
                if (key >= startedDay && count > 0 && freezes > 0) { freezes--; frozen.add(key) } else count = 0
            }
            cursor = cursor.plusDays(1)
        }
        return HabitStreak(count, freezes, frozen)
    }

    fun reconcile(activities: List<DailyLearningActivity>, goalMinutes: Double, today: LocalDate = LocalDate.now(), chestRoll: Int = (0..99).random()): List<String> {
        val day = today.toString(); val wins = mutableListOf<String>(); val seconds = learnedSeconds(day)
        val now = Instant.now()
        reminderHistory = reminderHistory.map { exposure ->
            if (exposure.day == day && exposure.fireTime <= now && now.epochSecond - exposure.fireTime.epochSecond <= 3600 && seconds >= exposure.baselineSeconds + 300) exposure.copy(completed = true) else exposure
        }
        for (minute in 1..(seconds / 60).toInt()) insert(HabitEvent("minute/$day/$minute", day, "xp", 1.0))
        val bonus = events.filter { it.kind == "boost-use" && it.day == day }.sumOf { it.value }
        for (minute in 1..(bonus / 60).toInt()) insert(HabitEvent("boost-xp/$day/$minute", day, "xp", 1.0))
        val target = goalSeconds(day, goalMinutes * 60)
        listOf(seconds >= 300, seconds >= target, has("reflection/$day")).forEachIndexed { index, achieved ->
            val number = index + 1
            if (achieved && insert(HabitEvent("quest/$day/$number/xp", day, "xp", 10.0))) {
                insert(HabitEvent("quest/$day/$number/gems", day, "gems", 5.0)); wins += "Quest complete · +10 XP · +5 gems"
            }
        }
        if (questCount(day) == 3 && !has("chest/$day")) {
            val reward = if (chestRoll.coerceIn(0, 99) < 60) 5 else if (chestRoll.coerceIn(0, 99) < 90) 10 else 20
            insert(HabitEvent("chest/$day", day, "gems", reward.toDouble()))
            insert(HabitEvent("boost/$day", day, "boost", 900.0))
            wins += "Daily chest · $reward gems · 15-minute XP boost"
        }
        val status = streak(activities, today)
        listOf(3, 7, 14, 30, 50, 100, 365).filter { seconds >= target && status.count >= it }.forEach {
            if (insert(HabitEvent("milestone/$it", day, "badge", it.toDouble(), "$it-day streak"))) wins += "$it-day streak protected"
        }
        val week = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)); val weekKey = week.toString()
        val learned = learningDays(activities)
        if (learned.count { it >= weekKey && it <= day && it >= startedDay } >= 5) insert(HabitEvent("weekly/$weekKey", day, "badge", detail = "Five-day week · $weekKey"))
        val month = day.take(7)
        if (events.count { it.id.startsWith("quest/$month") && it.kind == "xp" } >= 20) insert(HabitEvent("monthly/$month", day, "badge", detail = "20-quest month · $month"))
        activeWager(day)?.let { wager ->
            val start = LocalDate.parse(wager.day)
            if (today >= start.plusDays(6) && (0L..6L).all { start.plusDays(it).toString() in learned }) {
                if (insert(HabitEvent("wager-reward/${wager.day}", day, "gems", 40.0))) wins += "Seven promises kept · +40 gems"
            }
        }
        var targetWeek = events.filter { it.kind == "league-target" }.minByOrNull { it.day }?.day?.let(LocalDate::parse) ?: week
        while (targetWeek <= week) {
            val targetKey = targetWeek.toString()
            if (!has("league-target/$targetKey")) {
                val priorGoal = events.filter { it.kind == "goal" && it.day < targetKey }.maxByOrNull { it.day }?.value
                val daily = if (targetWeek == week) goalMinutes else priorGoal?.div(60) ?: goalMinutes
                val previous = previousWeeks(activities, targetWeek).map { it.second }.sorted()
                val median = (previous[1] + previous[2]) / 2
                insert(HabitEvent("league-target/$targetKey", targetKey, "league-target", max(daily * 5, median)))
            }
            targetWeek = targetWeek.plusWeeks(1)
        }
        events.filter { it.kind == "league-target" && it.day < weekKey }.forEach { targetEvent ->
            val end = LocalDate.parse(targetEvent.day).plusDays(7).toString()
            val activeDays = learned.count { it >= targetEvent.day && it < end }
            val total = activityMinutes(activities, targetEvent.day, end)
            val change = if (total >= targetEvent.value && activeDays >= 5) 1.0 else if (total >= targetEvent.value * .6) 0.0 else -1.0
            val id = "league-result/${targetEvent.day}"
            events = events.filterNot { it.id == id } + HabitEvent(id, targetEvent.day, "league-result", change)
        }
        return wins
    }

    fun activeWager(day: String) = events.filter { it.kind == "wager" && it.day <= day && !has("wager-reward/${it.day}") }.maxByOrNull { it.day }
    fun league(activities: List<DailyLearningActivity>, today: LocalDate = LocalDate.now()): HabitLeague {
        val start = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)); val key = start.toString(); val end = start.plusDays(7).toString()
        val tier = events.filter { it.kind == "league-result" }.sortedBy { it.day }.fold(0) { tier, event -> (tier + event.value.toInt()).coerceIn(0, 4) }
        return HabitLeague(tier, events.firstOrNull { it.id == "league-target/$key" }?.value ?: 75.0, activityMinutes(activities, key, end),
            learningDays(activities).count { it >= key && it < end }, previousWeeks(activities, start))
    }
    private fun previousWeeks(activities: List<DailyLearningActivity>, before: LocalDate) = (1L..4L).map {
        val start = before.minusWeeks(it)
        start.toString() to activityMinutes(activities, start.toString(), start.plusDays(7).toString())
    }
    fun activityMinutes(activities: List<DailyLearningActivity>, from: String, to: String): Double {
        val totals = activities.groupBy { it.dateKey }.mapValues { (_, values) -> values.maxOf { it.watchedSeconds } }.toMutableMap()
        playbackByDay().forEach { (day, seconds) -> totals[day] = max(totals[day] ?: 0.0, seconds) }
        return totals.filterKeys { it >= from && it < to }.values.sum() / 60
    }
    fun merge(remote: List<HabitEvent>) {
        val byId = events.associateBy { it.id }.toMutableMap()
        remote.filter { it.value.isFinite() }.forEach { incoming ->
            val old = byId[incoming.id]
            if (old == null || incoming.kind !in listOf("playback", "boost-use") || incoming.value > old.value) byId[incoming.id] = incoming
        }
        events = byId.values.sortedBy { it.id }
    }
}
