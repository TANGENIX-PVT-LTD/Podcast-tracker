package com.tangenix.podtrackio.domain

import com.google.gson.JsonObject
import com.tangenix.podtrackio.data.BrainParsing
import com.tangenix.podtrackio.data.GroqCatalog
import com.tangenix.podtrackio.data.applyReasoning
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate

class PlayTest {
    @Test fun weekStripMarksLearnedFrozenTodayAndFuture() {
        val today = LocalDate.of(2026, 10, 23) // Friday
        val loop = HabitLoop(startedDay = "2026-09-01")
        listOf("2026-10-19", "2026-10-20", "2026-10-22").forEach {
            loop.insert(HabitEvent("playback/d/$it", it, "playback", 600.0))
        }
        val strip = loop.weekStrip(emptyList(), today)
        assertEquals(listOf("M", "T", "W", "T", "F", "S", "S"), strip.map { it.letter })
        assertEquals(StreakDayState.DONE, strip[0].state)
        assertEquals(StreakDayState.FROZEN, strip[2].state)
        assertEquals(StreakDayState.TODAY, strip[4].state)
        assertEquals(StreakDayState.FUTURE, strip[6].state)
        assertEquals(30, StreakMilestones.next(14)); assertEquals(14, StreakMilestones.previous(20))
    }

    @Test fun reasoningParametersMatchEachModelFamily() {
        val oss = JsonObject().apply { applyReasoning("openai/gpt-oss-120b", "high") }
        assertEquals("high", oss["reasoning_effort"].asString); assertFalse(oss["include_reasoning"].asBoolean)
        val qwen = JsonObject().apply { applyReasoning("qwen/qwen3-32b", "medium") }
        assertEquals("default", qwen["reasoning_effort"].asString); assertEquals("hidden", qwen["reasoning_format"].asString)
        val llama = JsonObject().apply { applyReasoning("llama-3.3-70b-versatile", "high") }
        assertFalse(llama.has("reasoning_effort"))
    }

    @Test fun catalogFallsBackToWhatTheKeyCanUse() {
        val ids = setOf("openai/gpt-oss-20b", "llama-3.3-70b-versatile", "whisper-large-v3")
        assertEquals("openai/gpt-oss-20b", GroqCatalog.pick(QuirkyModel.BALANCED, ids))
        assertEquals("llama-3.3-70b-versatile", GroqCatalog.pick(QuirkyModel.DEEP, ids))
        assertEquals("llama-3.3-70b-versatile", GroqCatalog.pick(QuirkyModel.INSTANT, ids, excluding = "openai/gpt-oss-20b"))
    }

    @Test fun lenientParsingKeepsGoodAnswers() {
        assertEquals("Hi [S1]", BrainParsing.answer("```json\n{\"answer\":\"Hi [S1]\"}\n```"))
        assertEquals("## Answer\nPlain", BrainParsing.answer("## Answer\nPlain"))
        assertEquals(1, BrainParsing.memories("Sure! {\"memories\":[{\"text\":\"Likes examples\",\"evidence\":\"I like examples\"}]}").size)
        assertEquals("A [S1]. B.", BrainParsing.sanitizeCitations("A [S1]. B [S7].", 2))
        assertEquals(listOf(2, 1), BrainParsing.cited("x [S2] y [S1] z [S2]"))
        assertEquals(95.0, BrainParsing.timestamp("[95s] hello [120s]")!!, 0.0)
    }
}
