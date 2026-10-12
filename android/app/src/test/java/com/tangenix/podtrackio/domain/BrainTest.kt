package com.tangenix.podtrackio.domain

import org.junit.Assert.*
import org.junit.Test
import com.tangenix.podtrackio.data.Json

class BrainTest {
    @Test fun retrievalRanksEvidenceAndRejectsUnrelatedQuery() {
        val index = BrainIndex(listOf(
            BrainSource("a", "one", "Gardening", "Transcript", "plants sunlight water"),
            BrainSource("b", "two", "Learning", "Transcript", "spaced repetition improves retention")
        ))
        assertEquals("b", index.retrieve("spaced repetition").first().id)
        assertTrue(index.retrieve("quantum computing").isEmpty())
    }
    @Test fun retrievalBoundsAndDiversifies() {
        val index = BrainIndex((0..11).map { BrainSource("$it", if (it < 10) "one" else "two", "Memory", "Transcript", "memory practice retention") })
        val result = index.retrieve("memory", budget = 300)
        assertTrue(result.count { it.podcastId == "one" } <= 3)
        assertEquals(2, result.map { it.podcastId }.distinct().size)
        assertTrue(result.sumOf { it.text.length } <= 300)
    }
    @Test fun broadQuestionsSelectSummariesAcrossEpisodes() {
        val index = BrainIndex(listOf(BrainSource("a", "one", "Design", "Summary", "visual hierarchy"), BrainSource("b", "two", "Learning", "Summary", "spaced repetition")))
        assertEquals(2, index.retrieve("What have I learned?").size)
    }
    @Test fun oldSnapshotHasDefaultBrain() {
        val snapshot = Json.gson.fromJson("{}", AppSnapshot::class.java)
        assertNotNull(snapshot.brain)
        assertTrue(snapshot.brain.messages.isEmpty())
    }
    @Test fun composerSelectionsChangeTheActualProviderRequest() {
        for (model in QuirkyModel.entries) for (style in AnswerStyle.entries) {
            val request = com.tangenix.podtrackio.data.brainRequestBody(BrainState(), emptyList(), "Explain", model, style)
            assertEquals(model.modelId, request["model"].asString)
            assertEquals(when (model) { QuirkyModel.DEEP -> "high"; QuirkyModel.BALANCED -> "medium"; else -> "low" }, request["reasoning_effort"].asString)
            assertEquals(when (style) { AnswerStyle.CONCISE -> 1800; AnswerStyle.MEDIUM -> 2600; AnswerStyle.DETAILED -> 3600 }, request["max_completion_tokens"].asInt)
            val system = request.getAsJsonArray("messages").first().asJsonObject["content"].asString
            assertTrue(system.contains("ANSWER STRUCTURE"))
            if (style == AnswerStyle.CONCISE) assertTrue(system.contains("140 words"))
        }
    }

    @Test fun promptSeparatesEvidenceAndDisablesExtraction() {
        val prompt = BrainPrompt.system(BrainState(rememberPreferences = false), emptyList())
        assertTrue(prompt.contains("Memory extraction enabled: false"))
        assertTrue(prompt.contains("untrusted data"))
        assertTrue(prompt.contains("No relevant passages found"))
    }
}
