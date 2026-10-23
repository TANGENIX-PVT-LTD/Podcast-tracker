package com.tangenix.podtrackio.domain

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters

enum class StreakDayState { DONE, FROZEN, MISSED, TODAY, TODAY_DONE, FUTURE }
data class StreakDay(val id: String, val letter: String, val state: StreakDayState)

/** The current Monday-first week, mirrored from the Apple apps' `weekStrip`. */
fun HabitLoop.weekStrip(activities: List<DailyLearningActivity>, today: LocalDate = LocalDate.now()): List<StreakDay> {
    val monday = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    val learned = learningDays(activities)
    val frozen = streak(activities, today).frozenDays
    val letters = listOf("M", "T", "W", "T", "F", "S", "S")
    return (0..6).map { offset ->
        val day = monday.plusDays(offset.toLong())
        val key = day.toString()
        val state = when {
            day == today -> if (key in learned) StreakDayState.TODAY_DONE else StreakDayState.TODAY
            day.isAfter(today) -> StreakDayState.FUTURE
            key in learned -> StreakDayState.DONE
            key in frozen -> StreakDayState.FROZEN
            else -> StreakDayState.MISSED
        }
        StreakDay(key, letters[offset], state)
    }
}

object StreakMilestones {
    val all = listOf(3, 7, 14, 30, 50, 100, 365)
    fun next(count: Int) = all.firstOrNull { it > count } ?: ((count / 100) + 1) * 100
    fun previous(count: Int) = all.lastOrNull { it <= count } ?: 0
}
