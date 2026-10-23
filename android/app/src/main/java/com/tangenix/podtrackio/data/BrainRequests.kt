package com.tangenix.podtrackio.data

import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.tangenix.podtrackio.domain.*

/** The composer selections drive the provider request: model, reasoning, budget and Brain mode. */
internal fun brainRequestBody(state: BrainState, sources: List<BrainSource>, question: String, modelId: String, model: QuirkyModel, style: AnswerStyle, mode: BrainMode): JsonObject {
    fun message(role: String, content: String) = JsonObject().apply { addProperty("role", role); addProperty("content", content) }
    val messages = JsonArray().apply {
        add(message("system", BrainPrompt.system(state, sources, mode.instruction) + "\nANSWER STRUCTURE:\n" + when (style) {
            AnswerStyle.CONCISE -> "Maximum 140 words. Start with ## Answer, then ## Key points with 2-3 brief bullets. Add one next move only when useful."
            AnswerStyle.MEDIUM -> "Use 250-600 words. Start with ## Answer, then 2-5 scannable sections. Keep paragraphs short."
            AnswerStyle.DETAILED -> "Be as thorough as the question and sources require. Use Markdown headings, evidence, reasoning and a practical plan. Do not pad unsupported detail."
        }))
        state.messages.filter { it.text.isNotBlank() }.takeLast(4).forEach { add(message(it.role, it.text.take(700))) }
        add(message("user", question))
    }
    return JsonObject().apply {
        addProperty("model", modelId); add("messages", messages)
        addProperty("temperature", if (model == QuirkyModel.BALANCED) 0.6 else 0.55)
        addProperty("max_completion_tokens", when (style) { AnswerStyle.CONCISE -> 1800; AnswerStyle.MEDIUM -> 2600; AnswerStyle.DETAILED -> 3600 })
        applyReasoning(modelId, model.reasoningEffort)
    }
}
