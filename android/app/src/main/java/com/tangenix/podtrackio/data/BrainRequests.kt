package com.tangenix.podtrackio.data

import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.tangenix.podtrackio.domain.*

internal fun brainRequestBody(state: BrainState, sources: List<BrainSource>, question: String, model: QuirkyModel, style: AnswerStyle): JsonObject {
    fun message(role: String, content: String) = JsonObject().apply { addProperty("role", role); addProperty("content", content) }
        val messages = JsonArray().apply {
            add(message("system", com.tangenix.podtrackio.domain.BrainPrompt.system(state, sources) + "\nANSWER STRUCTURE:\n" + when (style) {
                AnswerStyle.CONCISE -> "Maximum 140 words. Start with ## Answer, then ## Key points with 2-3 brief bullets. Add one next move only when useful."
                AnswerStyle.MEDIUM -> "Use 250-600 words. Start with ## Answer, then 2-5 scannable sections. Keep paragraphs short."
                AnswerStyle.DETAILED -> "Be as thorough as the question and sources require. Use Markdown headings, evidence, reasoning and a practical plan. Do not pad unsupported detail."
            }))
            state.messages.takeLast(4).forEach { add(message(it.role, it.text.take(700))) }
            add(message("user", question))
        }
        val body = JsonObject().apply {
            addProperty("model", model.modelId); add("messages", messages)
            addProperty("temperature", if (model == QuirkyModel.BALANCED) 1.0 else 0.55)
            addProperty("reasoning_effort", when (model) { QuirkyModel.DEEP -> "high"; QuirkyModel.BALANCED -> "medium"; QuirkyModel.INSTANT -> "low" })
            if (model == QuirkyModel.BALANCED) addProperty("reasoning_format", "hidden") else addProperty("include_reasoning", false)
            addProperty("max_completion_tokens", when (style) { AnswerStyle.CONCISE -> 1800; AnswerStyle.MEDIUM -> 2600; AnswerStyle.DETAILED -> 3600 })
            add("response_format", JsonObject().apply { addProperty("type", "json_object") })
        }
    return body
}
