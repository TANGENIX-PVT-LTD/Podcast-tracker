package com.tangenix.podtrackio.data

import com.google.gson.JsonArray
import com.google.gson.JsonElement
import com.google.gson.JsonNull
import com.google.gson.JsonObject
import com.google.gson.JsonPrimitive
import com.tangenix.podtrackio.domain.DailyLearningActivity
import com.tangenix.podtrackio.domain.LearningCategory
import com.tangenix.podtrackio.domain.Podcast
import com.tangenix.podtrackio.domain.PodcastCollection
import com.tangenix.podtrackio.domain.PodcastSummary
import com.tangenix.podtrackio.domain.SummaryAction
import com.tangenix.podtrackio.domain.SummaryPoint
import com.tangenix.podtrackio.domain.SummarySection
import com.tangenix.podtrackio.domain.SummaryTakeaway
import com.tangenix.podtrackio.domain.TranscriptSource
import com.tangenix.podtrackio.domain.UserStats
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.util.UUID
import java.util.concurrent.TimeUnit

data class RemoteWorkspace(
    val podcasts: List<Podcast>,
    val categories: List<LearningCategory>,
    val activities: List<DailyLearningActivity>,
    val summaries: List<PodcastSummary>,
    val collections: List<PodcastCollection>,
    val stats: UserStats?,
)

class SupabaseApi(
    private val auth: AuthRepository,
    private val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .build(),
) {
    suspend fun fetchWorkspace(userId: String): RemoteWorkspace = RemoteWorkspace(
        podcasts = fetchRows("podcasts", userId).mapNotNull(::podcastFromJson),
        categories = fetchRows("categories", userId).mapNotNull(::categoryFromJson),
        activities = fetchRows("daily_learning_activity", userId).mapNotNull(::activityFromJson),
        summaries = fetchRows("podcast_summaries", userId).mapNotNull(::summaryFromJson),
        collections = fetchRows("podcast_collections", userId).mapNotNull(::collectionFromJson),
        stats = fetchStats(userId),
    )

    suspend fun pushWorkspace(
        userId: String,
        podcasts: List<Podcast>,
        categories: List<LearningCategory>,
        activities: List<DailyLearningActivity>,
        summaries: List<PodcastSummary>,
        collections: List<PodcastCollection>,
        stats: UserStats,
    ) {
        upsertRows("podcasts", podcasts.map { podcastToJson(it, userId, categories) }, 10)
        upsertRows("categories", categories.map { categoryToJson(it, userId) })
        upsertRows("daily_learning_activity", activities.map { activityToJson(it, userId) })
        upsertRows("podcast_summaries", summaries.map { summaryToJson(it, userId) })
        upsertRows("podcast_collections", collections.map { collectionToJson(it, userId) })
        upsertRows("user_stats", listOf(statsToJson(stats, userId)))
    }

    suspend fun pushPodcast(userId: String, podcast: Podcast, categories: List<LearningCategory>) {
        upsertRows("podcasts", listOf(podcastToJson(podcast, userId, categories)))
    }

    suspend fun deletePodcast(id: String) = delete("podcasts", "id", id)
    suspend fun deleteCollection(id: String) = delete("podcast_collections", "id", id)

    suspend fun reassignAndDeleteCategory(id: String, replacementId: String?) {
        val body = JsonObject().apply {
            addProperty("category_to_delete", id)
            add("replacement_category", replacementId?.let(::JsonPrimitive) ?: JsonNull.INSTANCE)
        }
        request("/rest/v1/rpc/reassign_and_delete_category", "POST", body)
    }

    private suspend fun fetchStats(userId: String): UserStats? = fetchRows("user_stats", userId, "id")
        .firstOrNull()?.let(::statsFromJson)

    private suspend fun fetchRows(table: String, userId: String, ownerColumn: String = "user_id"): List<JsonObject> {
        val encoded = URLEncoder.encode(userId, StandardCharsets.UTF_8.name())
        val result = request("/rest/v1/$table?select=*&$ownerColumn=eq.$encoded", "GET")
        return result?.asJsonArray?.mapNotNull { it.takeIf(JsonElement::isJsonObject)?.asJsonObject }.orEmpty()
    }

    private suspend fun upsertRows(table: String, rows: List<JsonObject>, batchSize: Int = 50) {
        rows.chunked(batchSize).forEach { batch ->
            val array = JsonArray().apply { batch.forEach(::add) }
            request("/rest/v1/$table", "POST", array, mapOf("Prefer" to "resolution=merge-duplicates,return=minimal"))
        }
    }

    private suspend fun delete(table: String, key: String, value: String) {
        val encoded = URLEncoder.encode(value, StandardCharsets.UTF_8.name())
        request("/rest/v1/$table?$key=eq.$encoded", "DELETE")
    }

    private suspend fun request(
        path: String,
        method: String,
        body: JsonElement? = null,
        extraHeaders: Map<String, String> = emptyMap(),
        retry: Boolean = true,
    ): JsonElement? {
        val session = auth.state.value.session ?: error("Sign in before syncing.")
        val requestBody = body?.let { Json.gson.toJson(it).toRequestBody(JSON_MEDIA) }
        val builder = Request.Builder()
            .url(auth.projectUrl + path)
            .header("apikey", com.tangenix.podtrackio.BuildConfig.SUPABASE_ANON_KEY)
            .header("Authorization", "Bearer ${session.accessToken}")
            .header("Content-Type", "application/json")
        extraHeaders.forEach(builder::header)
        when (method) {
            "GET" -> builder.get()
            "POST" -> builder.post(requestBody ?: ByteArray(0).toRequestBody(JSON_MEDIA))
            "DELETE" -> builder.delete(requestBody)
            else -> error("Unsupported method $method")
        }
        val response = withContext(Dispatchers.IO) { http.newCall(builder.build()).execute() }
        response.use {
            if (it.code == 401 && retry && auth.refresh()) return request(path, method, body, extraHeaders, false)
            val text = it.body?.string().orEmpty()
            check(it.isSuccessful) { "Supabase ${it.code}: ${text.take(500)}" }
            if (text.isBlank()) return null
            return Json.gson.fromJson(text, JsonElement::class.java)
        }
    }

    private fun podcastFromJson(json: JsonObject): Podcast? = runCatching {
        Podcast(
            id = json.string("id") ?: return null,
            title = json.string("title").orEmpty(),
            url = json.string("url").orEmpty(),
            youtubeVideoId = json.string("youtube_video_id").orEmpty(),
            thumbnailUrl = json.string("thumbnail_url"),
            dateAdded = json.instant("date_added") ?: Instant.now(),
            notes = json.string("notes").orEmpty(),
            totalWatchedSeconds = json.double("total_watched_seconds"),
            lastWatchedDate = json.instant("last_watched_date"),
            lastPlaybackPosition = json.double("last_playback_position"),
            isCompleted = json.bool("is_completed"),
            completedAt = json.instant("completed_at"),
            scheduledAt = json.instant("scheduled_at"),
            collectionIds = json.stringList("collection_ids"),
            categoryId = json.string("category_id") ?: LearningCategory.stableId(json.string("category")),
            duration = json.nullableDouble("duration"),
        )
    }.getOrNull()

    private fun podcastToJson(value: Podcast, userId: String, categories: List<LearningCategory>) = JsonObject().apply {
        addProperty("user_id", userId); addProperty("id", value.id); addProperty("title", value.title)
        addProperty("url", value.url); addProperty("youtube_video_id", value.youtubeVideoId)
        addNullable("thumbnail_url", value.thumbnailUrl); addProperty("date_added", value.dateAdded.toString())
        addProperty("notes", value.notes); addProperty("total_watched_seconds", value.totalWatchedSeconds)
        addNullable("last_watched_date", value.lastWatchedDate?.toString())
        addProperty("last_playback_position", value.lastPlaybackPosition); addProperty("is_completed", value.isCompleted)
        addNullable("completed_at", value.completedAt?.toString()); addNullable("scheduled_at", value.scheduledAt?.toString())
        add("collection_ids", value.collectionIds.toJsonArray()); addProperty("category_id", value.categoryId)
        addProperty("category", categories.firstOrNull { it.id == value.categoryId }?.name ?: "General")
        addNullable("duration", value.duration)
    }

    private fun categoryFromJson(json: JsonObject): LearningCategory? = runCatching {
        LearningCategory(
            id = json.string("id") ?: return null,
            name = json.string("name").orEmpty(),
            symbolName = json.string("symbol_name") ?: "book",
            colorToken = json.string("color_token") ?: "blue",
            sortOrder = json.int("sort_order"),
            createdAt = json.instant("created_at") ?: Instant.now(),
            updatedAt = json.instant("updated_at") ?: Instant.now(),
        )
    }.getOrNull()

    private fun categoryToJson(value: LearningCategory, userId: String) = JsonObject().apply {
        addProperty("user_id", userId); addProperty("id", value.id); addProperty("name", value.name)
        addProperty("symbol_name", value.symbolName); addProperty("color_token", value.colorToken)
        addProperty("sort_order", value.sortOrder); addProperty("created_at", value.createdAt.toString())
        addProperty("updated_at", value.updatedAt.toString())
    }

    private fun activityFromJson(json: JsonObject): DailyLearningActivity? = runCatching {
        DailyLearningActivity(
            dateKey = json.string("date_key") ?: return null,
            watchedSeconds = json.double("watched_seconds"), sessions = json.int("sessions"),
            goalMinutes = json.double("goal_minutes"), goalCompleted = json.bool("goal_completed"),
            xpEarned = json.int("xp_earned"), completedPodcastIds = json.stringList("completed_podcast_ids").toSet(),
            xpAwardedMinutes = json.int("xp_awarded_minutes"), dailyGoalXpAwarded = json.bool("daily_goal_xp_awarded"),
            weeklyGoalXpAwarded = json.bool("weekly_goal_xp_awarded"),
        )
    }.getOrNull()

    private fun activityToJson(value: DailyLearningActivity, userId: String) = JsonObject().apply {
        addProperty("user_id", userId); addProperty("date_key", value.dateKey)
        addProperty("watched_seconds", value.watchedSeconds); addProperty("sessions", value.sessions)
        addProperty("goal_minutes", value.goalMinutes); addProperty("goal_completed", value.goalCompleted)
        addProperty("xp_earned", value.xpEarned); add("completed_podcast_ids", value.completedPodcastIds.toList().toJsonArray())
        addProperty("xp_awarded_minutes", value.xpAwardedMinutes); addProperty("daily_goal_xp_awarded", value.dailyGoalXpAwarded)
        addProperty("weekly_goal_xp_awarded", value.weeklyGoalXpAwarded)
    }

    private fun collectionFromJson(json: JsonObject): PodcastCollection? = runCatching {
        PodcastCollection(
            id = json.string("id") ?: return null, title = json.string("title").orEmpty(),
            sourcePlaylistId = json.string("source_playlist_id").orEmpty(), sourceUrl = json.string("source_url").orEmpty(),
            dateAdded = json.instant("date_added") ?: Instant.now(), sortOrder = json.int("sort_order"),
            videoIds = json.stringList("video_ids"),
        )
    }.getOrNull()

    private fun collectionToJson(value: PodcastCollection, userId: String) = JsonObject().apply {
        addProperty("user_id", userId); addProperty("id", value.id); addProperty("title", value.title)
        addProperty("source_playlist_id", value.sourcePlaylistId); addProperty("source_url", value.sourceUrl)
        addProperty("date_added", value.dateAdded.toString()); addProperty("sort_order", value.sortOrder)
        add("video_ids", value.videoIds.toJsonArray())
    }

    private fun summaryFromJson(json: JsonObject): PodcastSummary? = runCatching {
        PodcastSummary(
            podcastId = json.string("podcast_id") ?: return null,
            brief = json.string("brief").orEmpty(),
            keyTopics = json.array("key_topics").mapNotNull { pointFromJson(it.asJsonObject) },
            majorTakeaways = json.array("major_takeaways").mapNotNull { takeawayFromJson(it.asJsonObject) },
            actionPlan = json.array("action_plan").mapNotNull { actionFromJson(it.asJsonObject) },
            sections = json.array("dynamic_sections").mapNotNull { sectionFromJson(it.asJsonObject) },
            generatedAt = json.instant("generated_at") ?: Instant.now(),
            transcriptSource = runCatching { TranscriptSource.valueOf(json.string("transcript_source").orEmpty()) }.getOrDefault(TranscriptSource.imported),
            model = json.string("model") ?: "openai/gpt-oss-120b",
            actionPlanXpGranted = json.bool("action_plan_xp_granted"),
        )
    }.getOrNull()

    private fun summaryToJson(value: PodcastSummary, userId: String) = JsonObject().apply {
        addProperty("user_id", userId); addProperty("podcast_id", value.podcastId); addProperty("brief", value.brief)
        add("key_topics", value.keyTopics.map(::pointToJson).toJsonArrayElements())
        add("major_takeaways", value.majorTakeaways.map(::takeawayToJson).toJsonArrayElements())
        add("action_plan", value.actionPlan.map(::actionToJson).toJsonArrayElements())
        add("dynamic_sections", value.sections.map(::sectionToJson).toJsonArrayElements())
        addProperty("generated_at", value.generatedAt.toString()); addProperty("transcript_source", value.transcriptSource.name)
        addProperty("model", value.model); addProperty("action_plan_xp_granted", value.actionPlanXpGranted)
    }

    private fun pointFromJson(json: JsonObject) = SummaryPoint(
        id = json.string("id") ?: UUID.randomUUID().toString(), title = json.string("title").orEmpty(),
        explanation = json.string("explanation").orEmpty(), timestampSeconds = json.nullableDouble("timestampSeconds") ?: json.nullableDouble("timestamp_seconds"),
    )
    private fun pointToJson(value: SummaryPoint) = JsonObject().apply {
        addProperty("id", value.id); addProperty("title", value.title); addProperty("explanation", value.explanation)
        addNullable("timestampSeconds", value.timestampSeconds)
    }
    private fun takeawayFromJson(json: JsonObject) = SummaryTakeaway(
        id = json.string("id") ?: UUID.randomUUID().toString(), title = json.string("title").orEmpty(), explanation = json.string("explanation").orEmpty(),
    )
    private fun takeawayToJson(value: SummaryTakeaway) = JsonObject().apply {
        addProperty("id", value.id); addProperty("title", value.title); addProperty("explanation", value.explanation)
    }
    private fun actionFromJson(json: JsonObject) = SummaryAction(
        id = json.string("id") ?: UUID.randomUUID().toString(), title = json.string("title").orEmpty(),
        detail = json.string("detail").orEmpty(), isCompleted = json.bool("isCompleted") || json.bool("is_completed"),
    )
    private fun actionToJson(value: SummaryAction) = JsonObject().apply {
        addProperty("id", value.id); addProperty("title", value.title); addProperty("detail", value.detail); addProperty("isCompleted", value.isCompleted)
    }
    private fun sectionFromJson(json: JsonObject) = SummarySection(
        id = json.string("id") ?: UUID.randomUUID().toString(), title = json.string("title").orEmpty(),
        introduction = json.string("introduction"), points = json.array("points").map { pointFromJson(it.asJsonObject) },
    )
    private fun sectionToJson(value: SummarySection) = JsonObject().apply {
        addProperty("id", value.id); addProperty("title", value.title); addNullable("introduction", value.introduction)
        add("points", value.points.map(::pointToJson).toJsonArrayElements())
    }

    private fun statsFromJson(json: JsonObject) = UserStats(
        id = json.string("id") ?: "default", totalSecondsWatched = json.double("total_seconds_watched"),
        currentStreak = json.int("current_streak"), longestStreak = json.int("longest_streak"),
        lastActiveDate = json.instant("last_active_date"), totalXp = json.int("total_xp"),
        weeklyGoalHours = json.double("weekly_goal_hours", 5.0), dailyGoalMinutes = json.double("daily_goal_minutes", 30.0),
        weeklySecondsWatched = json.double("weekly_seconds_watched"), dailySecondsWatched = json.double("daily_seconds_watched"),
        weekStartDate = json.instant("week_start_date"), dayStartDate = json.instant("day_start_date"),
        unlockedAchievementIds = json.stringList("unlocked_achievement_ids"), podcastsCompleted = json.int("podcasts_completed"),
        totalNotesTaken = json.int("total_notes_taken"), totalPodcastsAdded = json.int("total_podcasts_added"),
        sessionsCount = json.int("sessions_count"), longestSessionSeconds = json.double("longest_session_seconds"),
    )

    private fun statsToJson(value: UserStats, userId: String) = JsonObject().apply {
        addProperty("id", userId); addProperty("total_seconds_watched", value.totalSecondsWatched)
        addProperty("current_streak", value.currentStreak); addProperty("longest_streak", value.longestStreak)
        addNullable("last_active_date", value.lastActiveDate?.toString()); addProperty("total_xp", value.totalXp)
        addProperty("weekly_goal_hours", value.weeklyGoalHours); addProperty("daily_goal_minutes", value.dailyGoalMinutes)
        addProperty("weekly_seconds_watched", value.weeklySecondsWatched); addProperty("daily_seconds_watched", value.dailySecondsWatched)
        addNullable("week_start_date", value.weekStartDate?.toString()); addNullable("day_start_date", value.dayStartDate?.toString())
        add("unlocked_achievement_ids", value.unlockedAchievementIds.toJsonArray()); addProperty("podcasts_completed", value.podcastsCompleted)
        addProperty("total_notes_taken", value.totalNotesTaken); addProperty("total_podcasts_added", value.totalPodcastsAdded)
        addProperty("sessions_count", value.sessionsCount); addProperty("longest_session_seconds", value.longestSessionSeconds)
    }

    private fun JsonObject.string(key: String): String? = get(key)?.takeUnless { it.isJsonNull }?.asString
    private fun JsonObject.double(key: String, fallback: Double = 0.0): Double = get(key)?.takeUnless { it.isJsonNull }?.asDouble ?: fallback
    private fun JsonObject.nullableDouble(key: String): Double? = get(key)?.takeUnless { it.isJsonNull }?.asDouble
    private fun JsonObject.int(key: String): Int = get(key)?.takeUnless { it.isJsonNull }?.asInt ?: 0
    private fun JsonObject.bool(key: String): Boolean = get(key)?.takeUnless { it.isJsonNull }?.asBoolean ?: false
    private fun JsonObject.instant(key: String): Instant? = string(key)?.let { runCatching { Instant.parse(it) }.getOrNull() }
    private fun JsonObject.array(key: String): JsonArray = getAsJsonArray(key) ?: JsonArray()
    private fun JsonObject.stringList(key: String): List<String> = array(key).mapNotNull { it.takeUnless(JsonElement::isJsonNull)?.asString }
    private fun JsonObject.addNullable(key: String, value: String?) = add(key, value?.let(::JsonPrimitive) ?: JsonNull.INSTANCE)
    private fun JsonObject.addNullable(key: String, value: Double?) = add(key, value?.let(::JsonPrimitive) ?: JsonNull.INSTANCE)
    private fun List<String>.toJsonArray() = JsonArray().apply { this@toJsonArray.forEach(::add) }
    private fun List<JsonObject>.toJsonArrayElements() = JsonArray().apply { this@toJsonArrayElements.forEach(::add) }

    companion object { private val JSON_MEDIA = "application/json".toMediaType() }
}
