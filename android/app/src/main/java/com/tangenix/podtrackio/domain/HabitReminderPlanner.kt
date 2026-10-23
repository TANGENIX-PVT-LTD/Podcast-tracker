package com.tangenix.podtrackio.domain

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max

data class HabitReminder(val id: String, val day: String, val slot: Int, val fireTime: Instant, val template: Int,
    val title: String, val body: String, val podcastId: String)

object HabitReminderPlanner {
    fun plan(snapshot: AppSnapshot, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): List<HabitReminder> {
        val prefs = snapshot.notificationPreferences
        if (!prefs.isEnabled) return emptyList()
        val next = snapshot.podcasts.firstOrNull { it.hasProgress } ?: snapshot.podcasts.firstOrNull { !it.isCompleted } ?: return emptyList()
        val loop = snapshot.habitLoop
        val lastSession = snapshot.podcasts.mapNotNull { it.lastWatchedDate }.maxOrNull()
        val lastReturn = loop.lastOpenedAt ?: now
        val latest = maxOf(lastReturn, lastSession ?: lastReturn)
        val finalDay = latest.atZone(zone).toLocalDate().plusDays(7)
        val today = now.atZone(zone).toLocalDate()
        val status = loop.streak(snapshot.activities, today)
        return (0L..7L).flatMap { offset ->
            val date = today.plusDays(offset); val day = date.toString()
            val weekday = date.dayOfWeek.value % 7 + 1
            val activity = snapshot.activities.firstOrNull { it.dateKey == day }
            val learned = max(activity?.watchedSeconds ?: 0.0, loop.learnedSeconds(day))
            val target = loop.goalSeconds(day, snapshot.habitSettings.currentDailyGoalMinutes * 60)
            if (weekday !in prefs.enabledWeekdays || date > finalDay || activity?.goalCompleted == true || learned >= target) return@flatMap emptyList()
            val final = date == finalDay
            val slots = if (final) mutableListOf(prefs.evening) else mutableListOf(prefs.morning, prefs.afternoon, prefs.evening)
            if (!final && lastSession != null) {
                val at = lastSession.atZone(zone); val minute = at.hour * 60 + at.minute
                val closest = slots.indices.minByOrNull { abs(slots[it].hour * 60 + slots[it].minute - minute) }
                if (closest != null && abs(slots[closest].hour * 60 + slots[closest].minute - minute) <= 90) slots[closest] = TimeOfDay(at.hour, at.minute)
            }
            if (!final) DistractionPatternEngine.leadingPattern(snapshot.focusCommitments)?.takeIf { it.weekday == weekday }?.let { pattern ->
                val minute = pattern.hour * 60 + pattern.minute
                val closest = slots.indices.minBy { abs(slots[it].hour * 60 + slots[it].minute - minute) }
                slots[closest] = TimeOfDay(pattern.hour, pattern.minute)
            }
            slots.mapIndexedNotNull { index, time ->
                val fire = date.atTime(time.hour, time.minute).atZone(zone).toInstant()
                val id = "learning.$day.habit$index"
                if (fire <= now || isQuiet(time, prefs) || loop.reminderHistory.any { it.id == id && it.fireTime <= now }) return@mapIndexedNotNull null
                val template = loop.reminderHistory.firstOrNull { it.id == id }?.template ?: chooseTemplate(loop.reminderHistory, day, index, now)
                val protected = date == today && day in loop.learningDays(snapshot.activities)
                val remaining = max(0, ceil(target / 60 - learned / 60).toInt())
                val title = when {
                    final -> "These reminders will take a break"
                    protected -> "Streak safe. $remaining minutes to your target."
                    date == today && status.count > 0 && status.freezes == 0 -> "Your ${status.count}-day streak has $remaining minutes left to defend."
                    else -> listOf("The scroll can wait.", "Five useful minutes first.", "Your next idea is waiting.", "Keep the promise you picked.", "Tiny session. Real momentum.", "Learning called. Pick up?")[template]
                }
                val body = when {
                    final -> "We’ll pause motivational reminders after today until you return. Your learning is here whenever you’re ready."
                    protected -> "Continue ${next.title}. Only actual playback counts toward your daily target."
                    status.freezes > 0 && date == today -> "$remaining minutes completes today’s learning goal. A freeze protects continuity, not app access."
                    else -> "Start one five-minute block with ${next.title}."
                }
                HabitReminder(id, day, index, fire, template, title, body, next.id)
            }
        }.sortedBy { it.fireTime }
    }

    fun recordExposures(loop: HabitLoop, plan: List<HabitReminder>, now: Instant = Instant.now()): List<HabitReminderExposure> {
        val history = loop.reminderHistory.associateBy { it.id }.toMutableMap()
        plan.forEach { item ->
            val old = history[item.id]
            if (old == null || old.fireTime > now) history[item.id] = HabitReminderExposure(item.id, item.day, item.template, item.fireTime, loop.learnedSeconds(item.day))
        }
        return history.values.sortedByDescending { it.fireTime }.take(180)
    }

    private fun chooseTemplate(history: List<HabitReminderExposure>, day: String, slot: Int, now: Instant): Int {
        val previous = history.filter { it.fireTime < now }.sortedByDescending { it.fireTime }
        val recent = previous.take(3).map { it.template }.toSet()
        val candidates = (0..5).filter { it !in recent }
        val seed = day.fold(slot) { sum, ch -> (sum + ch.code) % 10000 }
        if (previous.size < 6 || seed % 5 == 0) return candidates[seed % candidates.size]
        return candidates.maxBy { candidate ->
            val exposures = previous.filter { it.template == candidate }
            (exposures.count { it.completed } + 1.0) / (exposures.size + 2.0)
        }
    }

    private fun isQuiet(time: TimeOfDay, prefs: NotificationPreferences): Boolean {
        if (!prefs.quietHoursEnabled) return false
        val minute = time.hour * 60 + time.minute
        val start = prefs.quietHoursStart.hour * 60 + prefs.quietHoursStart.minute
        val end = prefs.quietHoursEnd.hour * 60 + prefs.quietHoursEnd.minute
        return if (start <= end) minute in start until end else minute >= start || minute < end
    }
}
