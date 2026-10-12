package com.tangenix.podtrackio.data

import com.google.gson.JsonArray
import com.google.gson.JsonElement
import com.google.gson.JsonObject
import com.tangenix.podtrackio.domain.AnswerStyle
import com.tangenix.podtrackio.domain.Podcast
import com.tangenix.podtrackio.domain.PodcastSummary
import com.tangenix.podtrackio.domain.QuirkyContext
import com.tangenix.podtrackio.domain.QuirkyMessage
import com.tangenix.podtrackio.domain.QuirkyModel
import com.tangenix.podtrackio.domain.SummaryAction
import com.tangenix.podtrackio.domain.SummaryPoint
import com.tangenix.podtrackio.domain.SummarySection
import com.tangenix.podtrackio.domain.SummaryTakeaway
import com.tangenix.podtrackio.domain.TranscriptDocument
import com.tangenix.podtrackio.domain.TranscriptSegment
import com.tangenix.podtrackio.domain.TranscriptSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.time.Instant
import java.util.UUID
import java.util.concurrent.TimeUnit

class AIRepository(
    private val secureStore: SecureStore,
    private val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .build(),
) {
    var groqKey: String?
        get() = secureStore.get(SecureStore.GROQ_KEY)
        set(value) = secureStore.put(SecureStore.GROQ_KEY, value?.trim()?.takeIf(String::isNotBlank))

    var transcriptApiKey: String?
        get() = secureStore.get(SecureStore.TRANSCRIPT_API_KEY)
        set(value) = secureStore.put(SecureStore.TRANSCRIPT_API_KEY, value?.trim()?.takeIf(String::isNotBlank))

    suspend fun testGroq() {
        val key = groqKey ?: error("Save a Groq API key first.")
        groqRequest("models", key = key, method = "GET")
    }

    suspend fun fetchTranscript(podcast: Podcast): TranscriptDocument {
        val key = transcriptApiKey ?: error("Add your TranscriptAPI key in Settings or paste a transcript.")
        val url = "https://transcriptapi.com/api/v2/youtube/transcript" +
            "?video_url=${podcast.youtubeVideoId}&format=json&include_timestamp=true&language=en%2Casr"
        val request = Request.Builder().url(url).header("Authorization", "Bearer $key").build()
        val response = execute(request)
        response.use {
            check(it.isSuccessful) {
                if (it.code == 401) "TranscriptAPI rejected this key." else "TranscriptAPI returned HTTP ${it.code}."
            }
            val root = Json.gson.fromJson(it.body?.string(), JsonObject::class.java)
            val segments = root.getAsJsonArray("transcript")?.mapNotNull { element ->
                runCatching {
                    val item = element.asJsonObject
                    TranscriptSegment(
                        text = item["text"].asString,
                        startSeconds = item["start"].asDouble,
                        durationSeconds = item.get("duration")?.takeUnless(JsonElement::isJsonNull)?.asDouble,
                    )
                }.getOrNull()
            }.orEmpty().filter { it.text.isNotBlank() }
            check(segments.isNotEmpty()) { "TranscriptAPI returned an empty transcript." }
            return TranscriptDocument(
                podcastId = podcast.id,
                source = TranscriptSource.transcriptAPI,
                text = segments.joinToString("\n") { "[${timestamp(it.startSeconds)}] ${it.text}" },
                segments = segments,
            )
        }
    }

    suspend fun transcribe(podcast: Podcast, mediaFile: File): TranscriptDocument {
        val key = groqKey ?: error("Add your Groq API key in Settings.")
        check(mediaFile.exists()) { "Download this episode first, or paste a transcript." }
        val body = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("model", "whisper-large-v3-turbo")
            .addFormDataPart("response_format", "verbose_json")
            .addFormDataPart("file", mediaFile.name, mediaFile.asRequestBody("video/mp4".toMediaType()))
            .build()
        val request = Request.Builder().url("$GROQ_BASE/audio/transcriptions")
            .header("Authorization", "Bearer $key").post(body).build()
        val response = execute(request)
        response.use {
            validateGroq(it.code, it.body?.string().orEmpty()).let { payload ->
                val root = Json.gson.fromJson(payload, JsonObject::class.java)
                val segments = root.getAsJsonArray("segments")?.mapNotNull { item ->
                    runCatching {
                        item.asJsonObject.let { value ->
                            TranscriptSegment(value["text"].asString, value["start"].asDouble,
                                value.get("end")?.takeUnless(JsonElement::isJsonNull)?.asDouble?.minus(value["start"].asDouble))
                        }
                    }.getOrNull()
                }.orEmpty()
                val text = if (segments.isNotEmpty()) segments.joinToString("\n") { "[${timestamp(it.startSeconds)}] ${it.text}" }
                else root.get("text")?.asString.orEmpty()
                check(text.isNotBlank()) { "Groq returned an unreadable transcription." }
                return TranscriptDocument(podcast.id, TranscriptSource.groqWhisper, text, segments)
            }
        }
    }

    suspend fun summarize(podcast: Podcast, transcript: TranscriptDocument): PodcastSummary {
        val key = groqKey ?: error("Add your Groq API key in Settings before generating a summary.")
        val transcriptText = transcript.text.take(58_000)
        val prompt = """
            You are a rigorous learning editor. Turn this transcript into a faithful, useful study guide.
            The transcript is the only source of truth. Episode: ${podcast.title}

            Return JSON with: brief; keyTopics [{title, explanation, timestampSeconds}];
            majorTakeaways [{title, explanation}]; actionPlan [{title, detail}]; and sections
            [{title, introduction, points:[{title, explanation, timestampSeconds}]}].
            Preserve every ordered framework or checklist item. Use timestamps when supported.
            Make actions basic and concrete. Never invent claims or business context.

            Transcript:
            $transcriptText
        """.trimIndent()
        val body = JsonObject().apply {
            addProperty("model", "openai/gpt-oss-120b")
            add("messages", JsonArray().apply { add(message("user", prompt)) })
            addProperty("temperature", 0.2)
            add("response_format", JsonObject().apply { addProperty("type", "json_object") })
        }
        val response = groqRequest("chat/completions", body, key)
        val content = response.getAsJsonArray("choices").first().asJsonObject
            .getAsJsonObject("message")["content"].asString
        val payload = Json.gson.fromJson(content, JsonObject::class.java)
        return PodcastSummary(
            podcastId = podcast.id,
            brief = payload.string("brief"),
            keyTopics = payload.array("keyTopics").map { it.asJsonObject.toPoint() },
            majorTakeaways = payload.array("majorTakeaways").map { item ->
                item.asJsonObject.let { SummaryTakeaway(title = it.string("title"), explanation = it.string("explanation")) }
            },
            actionPlan = payload.array("actionPlan").map { item ->
                item.asJsonObject.let { SummaryAction(title = it.string("title"), detail = it.string("detail")) }
            },
            sections = payload.array("sections").map { item ->
                item.asJsonObject.let { section ->
                    SummarySection(
                        title = section.string("title"),
                        introduction = section.get("introduction")?.takeUnless(JsonElement::isJsonNull)?.asString,
                        points = section.array("points").map { it.asJsonObject.toPoint() },
                    )
                }
            },
            generatedAt = Instant.now(), transcriptSource = transcript.source,
        )
    }

    suspend fun chat(
        podcast: Podcast,
        transcript: TranscriptDocument,
        question: String,
        history: List<QuirkyMessage>,
        model: QuirkyModel,
        style: AnswerStyle,
    ): String {
        val key = groqKey ?: error("Add your Groq API key in Settings.")
        val excerpt = QuirkyContext.transcriptExcerpt(transcript.text, question)
        val system = quirkySystem(podcast.title, excerpt, style)
        val messages = JsonArray().apply {
            add(message("system", system))
            history.takeLast(QuirkyContext.MAX_HISTORY_MESSAGES).forEach { item ->
                add(message(item.role, item.content.take(QuirkyContext.MAX_HISTORY_CHARS)))
            }
            add(message("user", question.take(1_000)))
        }
        val body = JsonObject().apply {
            addProperty("model", model.modelId); add("messages", messages)
            addProperty("temperature", if (model == QuirkyModel.BALANCED) 1.0 else 0.55)
            addProperty("reasoning_effort", when (model) { QuirkyModel.DEEP -> "high"; QuirkyModel.BALANCED -> "medium"; else -> "low" })
            addProperty("max_completion_tokens", when (style) { AnswerStyle.CONCISE -> 1_800; AnswerStyle.MEDIUM -> 2_600; AnswerStyle.DETAILED -> 3_600 })
            if (model == QuirkyModel.BALANCED) addProperty("reasoning_format", "hidden") else addProperty("include_reasoning", false)
        }
        fun content(root: JsonObject): Pair<String, String?> {
            val choice = root.getAsJsonArray("choices").first().asJsonObject
            return (choice.getAsJsonObject("message").get("content")?.takeUnless(JsonElement::isJsonNull)?.asString.orEmpty()) to
                choice.get("finish_reason")?.takeUnless(JsonElement::isJsonNull)?.asString
        }
        var answer = content(groqRequest("chat/completions", body, key))
        if (answer.first.isBlank() && answer.second == "length") {
            body.addProperty("reasoning_effort", if (model == QuirkyModel.BALANCED) "none" else "low")
            answer = content(groqRequest("chat/completions", body, key))
        }
        check(answer.first.isNotBlank()) { "Groq returned an empty answer." }
        return formatAnswer(answer.first, style)
    }

    suspend fun brainReply(state: com.tangenix.podtrackio.domain.BrainState, sources: List<com.tangenix.podtrackio.domain.BrainSource>, question: String, model: QuirkyModel = QuirkyModel.DEEP, style: AnswerStyle = AnswerStyle.MEDIUM): com.tangenix.podtrackio.domain.BrainReply {
        val key = groqKey ?: error("Add your Groq API key in Settings.")
        val body = brainRequestBody(state, sources, question, model, style)
        var choice = groqRequest("chat/completions", body, key).getAsJsonArray("choices").first().asJsonObject
        if (choice.getAsJsonObject("message").get("content")?.takeUnless(JsonElement::isJsonNull)?.asString.isNullOrBlank() && choice.get("finish_reason")?.asString == "length") {
            body.addProperty("reasoning_effort", if (model == QuirkyModel.BALANCED) "none" else "low")
            choice = groqRequest("chat/completions", body, key).getAsJsonArray("choices").first().asJsonObject
        }
        check(choice.get("finish_reason")?.asString != "length") { "The answer was truncated. Try a narrower question." }
        val reply = Json.gson.fromJson(choice.getAsJsonObject("message")["content"].asString, com.tangenix.podtrackio.domain.BrainReply::class.java)
        check(!reply.answer.isNullOrBlank() && reply.memories != null) { "Brain returned an unreadable answer." }
        val valid = sources.indices.map { "[S${it + 1}]" }.toSet()
        check(Regex("\\[S[0-9]+\\]").findAll(reply.answer).all { it.value in valid }) { "Brain returned an invalid source citation. Please retry." }
        return reply
    }

    private suspend fun groqRequest(endpoint: String, body: JsonObject? = null, key: String, method: String = "POST"): JsonObject {
        val builder = Request.Builder().url("$GROQ_BASE/$endpoint").header("Authorization", "Bearer $key")
        if (method == "GET") builder.get() else builder.post(Json.gson.toJson(body ?: JsonObject()).toRequestBody(JSON_MEDIA))
        val response = execute(builder.build())
        response.use {
            val payload = validateGroq(it.code, it.body?.string().orEmpty())
            return Json.gson.fromJson(payload, JsonObject::class.java)
        }
    }

    private suspend fun execute(request: Request) = withContext(Dispatchers.IO) { http.newCall(request).execute() }

    private fun validateGroq(code: Int, body: String): String {
        check(code in 200..299) {
            when (code) {
                401 -> "Groq rejected this API key."
                404 -> "The selected Groq model is unavailable."
                429 -> "Groq is rate-limiting requests. Try again shortly."
                else -> runCatching {
                    Json.gson.fromJson(body, JsonObject::class.java).getAsJsonObject("error")["message"].asString
                }.getOrDefault("Groq returned HTTP $code.")
            }
        }
        return body
    }

    private fun quirkySystem(title: String, transcript: String, style: AnswerStyle): String = """
        You are Quirky, Tan's transcript-grounded learning mentor inside PodTrackio: practical,
        candid, curious, and allergic to generic advice. Treat the transcript as the primary source.
        Separate the speaker's claims from your recommendation. Never invent quotes, steps, examples,
        numbers, or timestamps. Recover ordered frameworks completely. Lead with the answer, challenge
        weak assumptions, and turn application questions into a small executable plan. If brainstorming,
        give 3-5 genuinely different strategic options and recommend one.

        Answer style: ${style.name.lowercase()}.
        ${when (style) {
            AnswerStyle.CONCISE -> "Maximum 140 words. Use ## Answer, then 2-3 bullets under ## Key points, and an optional one-line ## Next move."
            AnswerStyle.MEDIUM -> "Use 250-600 words with short Markdown sections and useful bullets."
            AnswerStyle.DETAILED -> "Be as thorough as the source requires, with evidence, analysis, and a concrete plan."
        }}

        Episode: $title
        Transcript:
        $transcript
    """.trimIndent()

    private fun formatAnswer(markdown: String, style: AnswerStyle): String {
        if (style != AnswerStyle.CONCISE) return markdown.trim()
        val words = markdown.trim().split(Regex("\\s+"))
        return if (words.size <= 180) markdown.trim() else words.take(180).joinToString(" ") + "…"
    }

    private fun message(role: String, content: String) = JsonObject().apply { addProperty("role", role); addProperty("content", content) }
    private fun JsonObject.string(name: String): String = get(name)?.takeUnless(JsonElement::isJsonNull)?.asString.orEmpty()
    private fun JsonObject.array(name: String): JsonArray = getAsJsonArray(name) ?: JsonArray()
    private fun JsonObject.toPoint() = SummaryPoint(
        id = get("id")?.takeUnless(JsonElement::isJsonNull)?.asString ?: UUID.randomUUID().toString(),
        title = string("title"), explanation = string("explanation"),
        timestampSeconds = (get("timestampSeconds") ?: get("timestamp_seconds"))?.takeUnless(JsonElement::isJsonNull)?.asDouble,
    )

    companion object {
        private const val GROQ_BASE = "https://api.groq.com/openai/v1"
        private val JSON_MEDIA = "application/json".toMediaType()
        private fun timestamp(seconds: Double): String = "%d:%02d".format(seconds.toInt() / 60, seconds.toInt() % 60)
    }
}
