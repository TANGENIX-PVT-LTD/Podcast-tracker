package com.tangenix.podtrackio.domain

import java.net.URI
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

data class Podcast(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val url: String,
    val youtubeVideoId: String,
    val thumbnailUrl: String? = null,
    val dateAdded: Instant = Instant.now(),
    val notes: String = "",
    val totalWatchedSeconds: Double = 0.0,
    val lastWatchedDate: Instant? = null,
    val lastPlaybackPosition: Double = 0.0,
    val isCompleted: Boolean = false,
    val completedAt: Instant? = null,
    val scheduledAt: Instant? = null,
    val collectionIds: List<String> = emptyList(),
    val categoryId: String = LearningCategory.GENERAL_ID,
    val duration: Double? = null,
) {
    val hasProgress: Boolean get() = lastPlaybackPosition > 0 && !isCompleted
    val progress: Float get() = duration?.takeIf { it > 0 }?.let {
        (lastPlaybackPosition / it).coerceIn(0.0, 1.0).toFloat()
    } ?: 0f

    fun mergedForSync(remote: Podcast): Podcast {
        val localStamp = lastWatchedDate ?: dateAdded
        val remoteStamp = remote.lastWatchedDate ?: remote.dateAdded
        return if (remoteStamp > localStamp) remote else this
    }

    companion object {
        private val videoIdPattern = Regex("^[A-Za-z0-9_-]{11}$")

        fun extractVideoId(input: String): String? {
            val value = input.trim()
            if (videoIdPattern.matches(value)) return value
            return runCatching {
                val uri = URI(value)
                val host = uri.host?.lowercase(Locale.ROOT).orEmpty()
                when {
                    host == "youtu.be" || host.endsWith(".youtu.be") ->
                        uri.path.trim('/').substringBefore('/').substringBefore('?')
                    host.endsWith("youtube.com") && uri.path == "/watch" ->
                        uri.rawQuery.orEmpty().split('&').firstNotNullOfOrNull { pair ->
                            val parts = pair.split('=', limit = 2)
                            parts.getOrNull(1)?.takeIf { parts.firstOrNull() == "v" }
                        }
                    host.endsWith("youtube.com") && uri.path.startsWith("/embed/") ->
                        uri.path.removePrefix("/embed/").substringBefore('/')
                    host.endsWith("youtube.com") && uri.path.startsWith("/shorts/") ->
                        uri.path.removePrefix("/shorts/").substringBefore('/')
                    else -> null
                }
            }.getOrNull()?.takeIf(videoIdPattern::matches)
        }
    }
}

data class PodcastCollection(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val sourcePlaylistId: String,
    val sourceUrl: String,
    val dateAdded: Instant = Instant.now(),
    val sortOrder: Int = 0,
    val videoIds: List<String> = emptyList(),
)

data class PlaylistEpisode(
    val videoId: String,
    val title: String,
    val url: String,
    val thumbnailUrl: String?,
    val playlistIndex: Int,
)

data class PlaylistPreview(
    val playlistId: String,
    val title: String,
    val sourceUrl: String,
    val episodes: List<PlaylistEpisode>,
    val unavailableCount: Int,
)

data class LearningCategory(
    val id: String = UUID.randomUUID().toString().lowercase(Locale.ROOT),
    val name: String,
    val symbolName: String = "book",
    val colorToken: String = "blue",
    val sortOrder: Int,
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now(),
) {
    companion object {
        const val GENERAL_ID = "general"
        val defaults = listOf(
            LearningCategory(GENERAL_ID, "General", "book", "gray", 0),
            LearningCategory("technology", "Technology", "memory", "blue", 1),
            LearningCategory("science", "Science", "science", "green", 2),
            LearningCategory("business", "Business", "business", "orange", 3),
            LearningCategory("self-improvement", "Self Improvement", "self_improvement", "purple", 4),
            LearningCategory("history", "History", "history", "brown", 5),
            LearningCategory("philosophy", "Philosophy", "psychology", "indigo", 6),
            LearningCategory("programming", "Programming", "code", "cyan", 7),
            LearningCategory("mathematics", "Mathematics", "function", "red", 8),
            LearningCategory("language", "Language", "language", "teal", 9),
            LearningCategory("health", "Health", "favorite", "pink", 10),
            LearningCategory("finance", "Finance", "trending_up", "yellow", 11),
        )

        fun stableId(legacyName: String?): String = defaults
            .firstOrNull { it.name.equals(legacyName, ignoreCase = true) }?.id ?: GENERAL_ID
    }
}

data class DailyLearningActivity(
    val dateKey: String,
    val watchedSeconds: Double = 0.0,
    val sessions: Int = 0,
    val goalMinutes: Double,
    val goalCompleted: Boolean = false,
    val xpEarned: Int = 0,
    val completedPodcastIds: Set<String> = emptySet(),
    val xpAwardedMinutes: Int = 0,
    val dailyGoalXpAwarded: Boolean = false,
    val weeklyGoalXpAwarded: Boolean = false,
) {
    val qualifiesForStreak: Boolean get() = watchedSeconds >= 300
}

data class UserStats(
    val id: String = "default",
    val totalSecondsWatched: Double = 0.0,
    val currentStreak: Int = 0,
    val longestStreak: Int = 0,
    val lastActiveDate: Instant? = null,
    val totalXp: Int = 0,
    val weeklyGoalHours: Double = 5.0,
    val dailyGoalMinutes: Double = 30.0,
    val weeklySecondsWatched: Double = 0.0,
    val dailySecondsWatched: Double = 0.0,
    val weekStartDate: Instant? = null,
    val dayStartDate: Instant? = null,
    val unlockedAchievementIds: List<String> = emptyList(),
    val podcastsCompleted: Int = 0,
    val totalNotesTaken: Int = 0,
    val totalPodcastsAdded: Int = 0,
    val sessionsCount: Int = 0,
    val longestSessionSeconds: Double = 0.0,
) {
    val level: Level get() = Level.forXp(totalXp)
    val weeklyProgress: Float get() = (weeklySecondsWatched / max(weeklyGoalHours * 3600, 1.0)).coerceIn(0.0, 1.0).toFloat()
    val dailyProgress: Float get() = (dailySecondsWatched / max(dailyGoalMinutes * 60, 1.0)).coerceIn(0.0, 1.0).toFloat()
}

data class Level(val number: Int, val title: String, val minXp: Int, val xpToNext: Int) {
    companion object {
        val values = listOf(
            Level(1, "Newcomer", 0, 100), Level(2, "Listener", 100, 200),
            Level(3, "Enthusiast", 300, 300), Level(4, "Scholar", 600, 400),
            Level(5, "Expert", 1000, 500), Level(6, "Guru", 1500, 1000),
            Level(7, "Master", 2500, 1500), Level(8, "Sage", 4000, 2000),
            Level(9, "Legend", 6000, 4000), Level(10, "Grandmaster", 10000, 0),
        )
        fun forXp(xp: Int): Level = values.lastOrNull { xp >= it.minXp } ?: values.first()
    }
}

data class Achievement(
    val id: String,
    val title: String,
    val description: String,
    val xpReward: Int,
    val category: String,
)

val allAchievements = listOf(
    Achievement("first_listen", "First Steps", "Watch your first episode", 10, "Listening"),
    Achievement("one_hour", "Hour Power", "Watch 1 hour", 25, "Listening"),
    Achievement("five_hours", "Deep Diver", "Watch 5 hours", 50, "Listening"),
    Achievement("ten_hours", "Knowledge Seeker", "Watch 10 hours", 100, "Listening"),
    Achievement("twentyfive_hours", "Marathon Listener", "Watch 25 hours", 200, "Listening"),
    Achievement("fifty_hours", "Podcast Warrior", "Watch 50 hours", 500, "Listening"),
    Achievement("hundred_hours", "Century Club", "Watch 100 hours", 1000, "Listening"),
    Achievement("streak_3", "Getting Started", "Maintain a 3-day streak", 30, "Streak"),
    Achievement("streak_7", "Week Warrior", "Maintain a 7-day streak", 75, "Streak"),
    Achievement("streak_14", "Fortnight Focus", "Maintain a 14-day streak", 150, "Streak"),
    Achievement("streak_30", "Monthly Master", "Maintain a 30-day streak", 300, "Streak"),
    Achievement("streak_100", "Unstoppable", "Maintain a 100-day streak", 1000, "Streak"),
    Achievement("first_note", "Scribbler", "Write your first note", 10, "Notes"),
    Achievement("ten_notes", "Note Taker", "Write notes for 10 episodes", 50, "Notes"),
    Achievement("twentyfive_notes", "Studious Scholar", "Write notes for 25 episodes", 150, "Notes"),
    Achievement("five_podcasts", "Explorer", "Add 5 episodes", 25, "Explorer"),
    Achievement("ten_podcasts", "Curator", "Add 10 episodes", 50, "Explorer"),
    Achievement("twentyfive_podcasts", "Collector", "Add 25 episodes", 100, "Explorer"),
    Achievement("three_categories", "Diverse Thinker", "Learn across 3 categories", 50, "Explorer"),
    Achievement("six_categories", "Renaissance Mind", "Learn across 6 categories", 150, "Explorer"),
    Achievement("complete_first", "Completionist", "Finish one episode", 20, "Mastery"),
    Achievement("complete_five", "Achiever", "Finish 5 episodes", 100, "Mastery"),
    Achievement("complete_ten", "Dedicated Learner", "Finish 10 episodes", 200, "Mastery"),
    Achievement("weekly_goal", "Goal Crusher", "Complete your weekly goal", 75, "Mastery"),
    Achievement("daily_goal_7", "Consistency King", "Hit your daily goal 7 days in a row", 200, "Mastery"),
    Achievement("first_summary", "Distilled", "Generate your first summary", 0, "Mastery"),
    Achievement("first_action_plan", "Applied Learning", "Complete an action plan", 0, "Mastery"),
    Achievement("level_5", "Rising Star", "Reach Level 5", 100, "Milestone"),
    Achievement("level_10", "Transcendence", "Reach Level 10", 500, "Milestone"),
)

enum class TranscriptSource { transcriptAPI, captions, groqWhisper, imported, pasted }

data class TranscriptSegment(val text: String, val startSeconds: Double, val durationSeconds: Double? = null)
data class TranscriptDocument(
    val podcastId: String,
    val source: TranscriptSource,
    val text: String,
    val segments: List<TranscriptSegment> = emptyList(),
    val createdAt: Instant = Instant.now(),
)

data class SummaryPoint(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val explanation: String,
    val timestampSeconds: Double? = null,
)
data class SummarySection(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val introduction: String? = null,
    val points: List<SummaryPoint> = emptyList(),
)
data class SummaryTakeaway(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val explanation: String,
)
data class SummaryAction(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val detail: String,
    val isCompleted: Boolean = false,
)
data class PodcastSummary(
    val podcastId: String,
    val brief: String,
    val keyTopics: List<SummaryPoint> = emptyList(),
    val majorTakeaways: List<SummaryTakeaway> = emptyList(),
    val actionPlan: List<SummaryAction> = emptyList(),
    val sections: List<SummarySection> = emptyList(),
    val generatedAt: Instant = Instant.now(),
    val transcriptSource: TranscriptSource,
    val model: String = "openai/gpt-oss-120b",
    val actionPlanXpGranted: Boolean = false,
)

enum class QuirkyModel(val modelId: String, val label: String) {
    DEEP("openai/gpt-oss-120b", "Deep"),
    BALANCED("qwen/qwen3-32b", "Balanced"),
    INSTANT("openai/gpt-oss-20b", "Instant"),
}
enum class AnswerStyle { CONCISE, MEDIUM, DETAILED }
data class QuirkyMessage(
    val id: String = UUID.randomUUID().toString(),
    val role: String,
    val content: String,
    val createdAt: Instant = Instant.now(),
)

enum class DistractionCue { SCROLLING, STREAMING, ANIME, GAMING, OTHER, NOTIFICATION, TODAY, MOMENTUM }
data class FocusCommitment(
    val id: String = UUID.randomUUID().toString(),
    val podcastId: String,
    val cue: DistractionCue,
    val targetSeconds: Double,
    val watchedSeconds: Double = 0.0,
    val createdAt: Instant = Instant.now(),
    val completedAt: Instant? = null,
    val cancelledAt: Instant? = null,
) {
    val isActive get() = completedAt == null && cancelledAt == null
    val progress get() = (watchedSeconds / max(targetSeconds, 1.0)).coerceIn(0.0, 1.0).toFloat()
}

data class HabitSettings(
    val adaptiveBuildUpEnabled: Boolean = true,
    val currentDailyGoalMinutes: Double = 5.0,
    val startingDailyGoalMinutes: Double = 5.0,
    val targetDailyGoalMinutes: Double = 60.0,
    val buildUpStepMinutes: Double = 1.0,
    val minimumQualifyingSessionMinutes: Double = 5.0,
    val lastEvaluatedWeekKey: String? = null,
    val lastWeeklyGoalAwardKey: String? = null,
)


data class TimeOfDay(val hour: Int, val minute: Int)
data class NotificationPreferences(
    val isEnabled: Boolean = true,
    val morning: TimeOfDay = TimeOfDay(9, 0),
    val afternoon: TimeOfDay = TimeOfDay(14, 0),
    val evening: TimeOfDay = TimeOfDay(20, 0),
    val enabledWeekdays: Set<Int> = (1..7).toSet(),
    val quietHoursEnabled: Boolean = true,
    val quietHoursStart: TimeOfDay = TimeOfDay(22, 0),
    val quietHoursEnd: TimeOfDay = TimeOfDay(8, 0),
)

data class DistractionPattern(
    val cue: DistractionCue,
    /** Calendar-compatible numbering: Sunday = 1, Monday = 2, … Saturday = 7. */
    val weekday: Int,
    val hour: Int,
    val minute: Int,
    val observations: Int,
)

object DistractionPatternEngine {
    private data class Bucket(val cue: DistractionCue, val weekday: Int, val twoHourBlock: Int)

    fun leadingPattern(
        commitments: List<FocusCommitment>,
        now: Instant = Instant.now(),
        minimumObservations: Int = 3,
    ): DistractionPattern? {
        if (minimumObservations <= 0) return null
        val lookback = now.minusSeconds(28L * 24 * 60 * 60)
        val distractions = setOf(DistractionCue.SCROLLING, DistractionCue.STREAMING, DistractionCue.ANIME, DistractionCue.GAMING, DistractionCue.OTHER)
        val grouped = commitments.filter { it.cue in distractions && it.createdAt >= lookback && it.createdAt < now }
            .groupBy { item ->
                val date = item.createdAt.atZone(ZoneId.systemDefault())
                Bucket(item.cue, date.dayOfWeek.value % 7 + 1, date.hour / 2)
            }
            .filterValues { it.size >= minimumObservations }
        val winner = grouped.entries.sortedWith(
            compareByDescending<Map.Entry<Bucket, List<FocusCommitment>>> { it.value.size }
                .thenByDescending { it.value.maxOf(FocusCommitment::createdAt) }
                .thenBy { it.key.weekday }
                .thenBy { it.key.twoHourBlock }
                .thenBy { it.key.cue.name },
        ).firstOrNull() ?: return null
        val minuteValues = winner.value.map {
            val date = it.createdAt.atZone(ZoneId.systemDefault())
            date.hour * 60 + date.minute
        }.sorted()
        val proactiveMinute = max(0, minuteValues[minuteValues.size / 2] - 10)
        return DistractionPattern(winner.key.cue, winner.key.weekday, proactiveMinute / 60, proactiveMinute % 60, winner.value.size)
    }
}

enum class DownloadQuality(val maxHeight: Int, val label: String) {
    SAVER_480(480, "480p Saver"), STANDARD_720(720, "720p Standard"), HIGH_1080(1080, "1080p High")
}
data class DownloadRecord(
    val videoId: String,
    val filePath: String,
    val byteCount: Long,
    val resolutionHeight: Int?,
    val downloadedAt: Instant = Instant.now(),
    val expiresAt: Instant? = null,
)

data class AppSnapshot(
    val habitLoop: HabitLoop = HabitLoop(),
    val brain: BrainState = BrainState(),
    val podcasts: List<Podcast> = emptyList(),
    val categories: List<LearningCategory> = LearningCategory.defaults,
    val activities: List<DailyLearningActivity> = emptyList(),
    val summaries: List<PodcastSummary> = emptyList(),
    val collections: List<PodcastCollection> = emptyList(),
    val stats: UserStats = UserStats(),
    val transcripts: Map<String, TranscriptDocument> = emptyMap(),
    val quirkyConversations: Map<String, List<QuirkyMessage>> = emptyMap(),
    val focusCommitments: List<FocusCommitment> = emptyList(),
    val habitSettings: HabitSettings = HabitSettings(),
    val notificationPreferences: NotificationPreferences = NotificationPreferences(),
    val downloads: Map<String, DownloadRecord> = emptyMap(),
    val downloadQuality: DownloadQuality = DownloadQuality.HIGH_1080,
    val theme: String = "system",
)

data class AuthSession(val accessToken: String, val refreshToken: String)
data class UserProfile(val id: String, val email: String?, val displayName: String?, val avatarUrl: String?)

fun todayKey(): String = LocalDate.now().toString()
fun weekKey(): String {
    return weekKey(LocalDate.now())
}
fun weekKey(today: LocalDate): String {
    val fields = WeekFields.of(Locale.getDefault())
    return "%04d-W%02d".format(today.get(fields.weekBasedYear()), today.get(fields.weekOfWeekBasedYear()))
}
fun Instant.localDate(): LocalDate = atZone(ZoneId.systemDefault()).toLocalDate()
fun formatDuration(seconds: Double): String {
    val total = max(0, seconds.toInt())
    val hours = total / 3600
    val minutes = (total % 3600) / 60
    val secs = total % 60
    return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, secs) else "%d:%02d".format(minutes, secs)
}

object QuirkyContext {
    const val MAX_TRANSCRIPT_CHARS = 9_000
    const val MAX_HISTORY_CHARS = 600
    const val MAX_HISTORY_MESSAGES = 3

    fun transcriptExcerpt(transcript: String, question: String): String {
        if (transcript.length <= MAX_TRANSCRIPT_CHARS) return transcript
        val terms = question.lowercase().split(Regex("[^a-z0-9]+")).filter { it.length > 2 }.toSet()
        val lines = transcript.lines()
        val ranked = lines.indices.sortedByDescending { index ->
            lines[index].lowercase().split(Regex("[^a-z0-9]+")).toSet().intersect(terms).size
        }
        val selected = linkedSetOf<Int>()
        ranked.filter { index -> lines[index].lowercase().split(Regex("[^a-z0-9]+")).toSet().intersect(terms).isNotEmpty() }
            .forEach { index ->
                for (nearby in max(0, index - 2)..min(lines.lastIndex, index + 2)) selected += nearby
                if (selected.size >= 80) return@forEach
            }
        if (selected.isEmpty()) return transcript.take(MAX_TRANSCRIPT_CHARS)
        val result = StringBuilder()
        selected.sorted().forEach { index ->
            val next = if (result.isEmpty()) lines[index] else "\n${lines[index]}"
            if (result.length + next.length <= MAX_TRANSCRIPT_CHARS) result.append(next)
        }
        return result.toString().ifEmpty { transcript.take(MAX_TRANSCRIPT_CHARS) }
    }
}
