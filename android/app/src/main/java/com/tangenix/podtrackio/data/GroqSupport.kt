package com.tangenix.podtrackio.data

import com.google.gson.JsonObject
import com.tangenix.podtrackio.domain.BrainMemoryCandidate
import com.tangenix.podtrackio.domain.QuirkyModel

/** Ordered model candidates per tier; the first one Groq serves for this key wins. Mirrors the Apple apps. */
val QuirkyModel.preferredIds: List<String> get() = when (this) {
    QuirkyModel.DEEP -> listOf("openai/gpt-oss-120b", "moonshotai/kimi-k2-instruct-0905", "llama-3.3-70b-versatile")
    QuirkyModel.BALANCED -> listOf("qwen/qwen3-32b", "qwen/qwen3.6-27b", "openai/gpt-oss-20b", "llama-3.3-70b-versatile")
    QuirkyModel.INSTANT -> listOf("openai/gpt-oss-20b", "llama-3.1-8b-instant", "llama-3.3-70b-versatile")
}

val QuirkyModel.reasoningEffort get() = when (this) { QuirkyModel.DEEP -> "high"; QuirkyModel.BALANCED -> "medium"; QuirkyModel.INSTANT -> "low" }
val QuirkyModel.fallbackEffort get() = if (this == QuirkyModel.BALANCED) "none" else "low"

object GroqCatalog {
    private var cache: Triple<Int, Set<String>, Long>? = null
    fun invalidate() { cache = null }
    fun cached(key: String): Set<String>? = cache?.takeIf { it.first == key.hashCode() && System.currentTimeMillis() - it.third < 86_400_000 }?.second
    fun store(key: String, ids: Set<String>) { cache = Triple(key.hashCode(), ids, System.currentTimeMillis()) }

    fun pick(tier: QuirkyModel, ids: Set<String>, excluding: String? = null): String {
        val fallbacks = QuirkyModel.entries.flatMap { it.preferredIds }
        return (tier.preferredIds + fallbacks).firstOrNull { it in ids && it != excluding }
            ?: ids.sorted().firstOrNull { it != excluding && "whisper" !in it && "guard" !in it && "tts" !in it }
            ?: tier.modelId
    }
}

/** Reasoning knobs differ per family; sending the wrong one gets the whole request rejected. */
fun JsonObject.applyReasoning(modelId: String, effort: String) {
    remove("reasoning_effort"); remove("include_reasoning"); remove("reasoning_format")
    when {
        modelId.startsWith("openai/gpt-oss") -> { addProperty("reasoning_effort", if (effort in setOf("low", "medium", "high")) effort else "low"); addProperty("include_reasoning", false) }
        modelId.startsWith("qwen/") -> { addProperty("reasoning_effort", if (effort == "none") "none" else "default"); addProperty("reasoning_format", "hidden") }
    }
}

object BrainParsing {
    fun jsonObject(text: String): String? {
        var body = text.trim()
        if (body.startsWith("```")) body = body.lines().drop(1).joinToString("\n").substringBeforeLast("```")
        val start = body.indexOf('{'); val end = body.lastIndexOf('}')
        return if (start in 0 until end) body.substring(start, end + 1) else null
    }

    fun memories(text: String): List<BrainMemoryCandidate> = runCatching {
        val obj = Json.gson.fromJson(jsonObject(text) ?: return emptyList(), JsonObject::class.java)
        obj.getAsJsonArray("memories")?.mapNotNull { el ->
            val o = el.asJsonObject
            BrainMemoryCandidate(o.get("text")?.asString ?: return@mapNotNull null, o.get("evidence")?.asString ?: return@mapNotNull null)
        }.orEmpty()
    }.getOrDefault(emptyList())

    /** Accepts `{"answer": …}` JSON, fenced JSON, or plain Markdown. */
    fun answer(text: String): String = runCatching {
        Json.gson.fromJson(jsonObject(text), JsonObject::class.java)?.get("answer")?.asString?.takeIf { it.isNotBlank() }
    }.getOrNull() ?: text.trim()

    /** Drops citations that don't point at a retrieved source instead of discarding the answer. */
    fun sanitizeCitations(text: String, sourceCount: Int): String =
        Regex("\\s?\\[S([0-9]+)\\]").replace(text) { m -> if ((m.groupValues[1].toIntOrNull() ?: 0) in 1..sourceCount) m.value else "" }

    fun cited(text: String): List<Int> = Regex("\\[S([0-9]+)\\]").findAll(text).mapNotNull { it.groupValues[1].toIntOrNull() }.distinct().toList()

    fun timestamp(passage: String): Double? = Regex("\\[([0-9]+)s\\]").find(passage)?.groupValues?.get(1)?.toDoubleOrNull()
}

/** What the person wants Brain to do with their library. */
enum class BrainMode(val title: String, val placeholder: String, val instruction: String) {
    ASK("Ask", "Ask anything about your learning…", ""),
    QUIZ("Quiz me", "Topic or episode to be quizzed on…", ""),
    CONNECT("Connect ideas", "A theme to connect across episodes (optional)…",
        "MODE: Connect ideas. Find 3–5 non-obvious connections between DIFFERENT episodes. For each: a bold one-line title, which episodes, the shared idea, where they disagree, and one way to use it. Cite every claim."),
    PLAN("Action plan", "What do you want to achieve?",
        "MODE: Action plan. Turn the relevant learning into a 7-day plan: one concrete, small action per day with a success check, each grounded in a cited source. End with the single most important first step."),
    RECAP("Recap my week", "Anything to focus the recap on? (optional)",
        "MODE: Weekly recap. Summarise what the user learned from this week's episodes: 3–6 key ideas with citations, one surprising insight, and one question worth exploring next.");
    val allowsEmpty get() = this == CONNECT || this == RECAP
}
