package com.tangenix.podtrackio

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.tangenix.podtrackio.data.AuthRepository
import com.tangenix.podtrackio.data.AuthState
import com.tangenix.podtrackio.domain.AnswerStyle
import com.tangenix.podtrackio.domain.AppSnapshot
import com.tangenix.podtrackio.domain.DailyLearningActivity
import com.tangenix.podtrackio.domain.DistractionCue
import com.tangenix.podtrackio.domain.DownloadQuality
import com.tangenix.podtrackio.domain.FocusCommitment
import com.tangenix.podtrackio.domain.HabitSettings
import com.tangenix.podtrackio.domain.LearningCategory
import com.tangenix.podtrackio.domain.LearningCalendar
import com.tangenix.podtrackio.domain.NotificationPreferences
import com.tangenix.podtrackio.domain.PlaylistPreview
import com.tangenix.podtrackio.domain.Podcast
import com.tangenix.podtrackio.domain.PodcastCollection
import com.tangenix.podtrackio.domain.PodcastSummary
import com.tangenix.podtrackio.domain.QuirkyMessage
import com.tangenix.podtrackio.domain.QuirkyModel
import com.tangenix.podtrackio.domain.SummaryAction
import com.tangenix.podtrackio.domain.TranscriptDocument
import com.tangenix.podtrackio.domain.TranscriptSource
import com.tangenix.podtrackio.domain.UserStats
import com.tangenix.podtrackio.domain.allAchievements
import com.tangenix.podtrackio.domain.localDate
import com.tangenix.podtrackio.domain.todayKey
import com.tangenix.podtrackio.domain.weekKey
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale
import java.util.UUID
import kotlin.math.max

enum class AppSection(val title: String) { TODAY("Today"), LIBRARY("Library"), PROGRESS("Progress"), BRAIN("Brain") }
enum class InspectorMode(val title: String) { SUMMARY("Summary"), NOTES("Notes"), QUIRKY("Quirky") }

data class PodTrackioUiState(
    val loaded: Boolean = false,
    val snapshot: AppSnapshot = AppSnapshot(),
    val section: AppSection = AppSection.TODAY,
    val selectedPodcastId: String? = null,
    val inspectorMode: InspectorMode = InspectorMode.SUMMARY,
    val inspectorVisible: Boolean = true,
    val search: String = "",
    val selectedCategoryId: String? = null,
    val selectedCollectionId: String? = null,
    val syncing: Boolean = false,
    val message: String? = null,
    val summaryStatus: String? = null,
    val chatBusy: Boolean = false,
    val brainBusy: Boolean = false,
    val downloadProgress: Map<String, Float> = emptyMap(),
    val playingPodcastId: String? = null,
    val demoMode: Boolean = false,
) {
    val selectedPodcast get() = snapshot.podcasts.firstOrNull { it.id == selectedPodcastId }
    val filteredPodcasts get() = snapshot.podcasts.filter { podcast ->
        val queryMatches = search.isBlank() || podcast.title.contains(search, true) || podcast.notes.contains(search, true) ||
            snapshot.categories.firstOrNull { it.id == podcast.categoryId }?.name?.contains(search, true) == true
        val categoryMatches = selectedCategoryId == null || podcast.categoryId == selectedCategoryId
        val collectionMatches = selectedCollectionId == null || selectedCollectionId in podcast.collectionIds
        queryMatches && categoryMatches && collectionMatches
    }.sortedByDescending { it.dateAdded }
}

class PodTrackioViewModel(private val container: AppContainer) : ViewModel() {
    private val _ui = MutableStateFlow(PodTrackioUiState())
    val ui: StateFlow<PodTrackioUiState> = _ui.asStateFlow()
    val auth: StateFlow<AuthState> = container.auth.state

    private var persistJob: Job? = null
    private var syncJob: Job? = null
    private val progressSyncJobs = mutableMapOf<String, Job>()
    private val lastProgress = mutableMapOf<String, Double>()
    private var lastSyncedUser: String? = null

    val externalMediaToolsAvailable get() = container.mediaTools.supportsExternalMediaTools

    init {
        viewModelScope.launch {
            val loaded = container.localStore.load()
            val habits = LearningCalendar.evaluateBuildUp(loaded.habitSettings, loaded.activities)
            val reconciled = loaded.copy(
                downloads = container.downloads.reconcile(loaded.downloads),
                habitSettings = habits,
                stats = loaded.stats.copy(dailyGoalMinutes = habits.currentDailyGoalMinutes),
            )
            _ui.update { it.copy(loaded = true, snapshot = reconciled) }
            container.auth.restore()
        }
        viewModelScope.launch {
            container.auth.state.collect { state ->
                val userId = state.profile?.id
                if (state.isAuthenticated && userId != null && lastSyncedUser != userId) {
                    lastSyncedUser = userId
                    sync()
                }
                if (!state.isAuthenticated && !state.restoring) {
                    lastSyncedUser = null
                    _ui.update { it.copy(selectedPodcastId = null, playingPodcastId = null, section = AppSection.TODAY) }
                }
            }
        }
    }

    fun oauthUri(provider: String): Uri = container.auth.oauthUri(provider)
    fun clearAuthError() = container.auth.clearError()
    fun handleAuthCallback(uri: Uri) { viewModelScope.launch { container.auth.handleCallback(uri) } }
    fun signOut() { viewModelScope.launch { container.auth.signOut() } }

    /** Debug-build UI fixture. It never creates a session, writes Supabase, or ships as a visible release action. */
    fun enableDemoMode() {
        val now = Instant.now()
        val habits = Podcast(
            id = "demo-habits", title = "Build Better Habits with Systems",
            url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ", youtubeVideoId = "dQw4w9WgXcQ",
            thumbnailUrl = "https://img.youtube.com/vi/dQw4w9WgXcQ/mqdefault.jpg",
            lastPlaybackPosition = 742.0, duration = 2_460.0, totalWatchedSeconds = 742.0,
            lastWatchedDate = now.minusSeconds(1_800), categoryId = "self-improvement",
        )
        val ai = Podcast(
            id = "demo-ai", title = "The Future of Artificial Intelligence",
            url = "https://www.youtube.com/watch?v=aircAruvnKk", youtubeVideoId = "aircAruvnKk",
            thumbnailUrl = "https://img.youtube.com/vi/aircAruvnKk/mqdefault.jpg",
            scheduledAt = now.plusSeconds(7_200), categoryId = "technology",
        )
        val deepWork = Podcast(
            id = "demo-focus", title = "A Practical Guide to Deep Work",
            url = "https://www.youtube.com/watch?v=5MgBikgcWnY", youtubeVideoId = "5MgBikgcWnY",
            thumbnailUrl = "https://img.youtube.com/vi/5MgBikgcWnY/mqdefault.jpg",
            isCompleted = true, completedAt = now.minusSeconds(86_400), duration = 1_800.0,
            totalWatchedSeconds = 1_800.0, categoryId = "business", notes = "Protect the first hour of the day for demanding work.",
        )
        val summary = PodcastSummary(
            podcastId = habits.id,
            brief = "Lasting habits come from making the desired behavior obvious, easy, and repeatable inside a system you can sustain.",
            keyTopics = listOf(com.tangenix.podtrackio.domain.SummaryPoint(title = "Systems over goals", explanation = "Use a repeatable process instead of relying on motivation.")),
            majorTakeaways = listOf(com.tangenix.podtrackio.domain.SummaryTakeaway(title = "Reduce friction", explanation = "Prepare the environment before willpower is needed.")),
            actionPlan = listOf(SummaryAction(title = "Design one cue", detail = "Place the next action where you will see it tomorrow.")),
            transcriptSource = TranscriptSource.pasted,
        )
        val fixture = AppSnapshot(
            podcasts = listOf(habits, ai, deepWork),
            categories = LearningCategory.defaults,
            summaries = listOf(summary),
            transcripts = mapOf(habits.id to TranscriptDocument(habits.id, TranscriptSource.pasted, "A demo transcript about systems, cues, repetition, and reducing friction.")),
            stats = UserStats(
                totalSecondsWatched = 9_540.0, currentStreak = 6, longestStreak = 12, totalXp = 380,
                weeklySecondsWatched = 7_200.0, dailySecondsWatched = 1_320.0, podcastsCompleted = 1,
                totalNotesTaken = 1, totalPodcastsAdded = 3, sessionsCount = 8,
                unlockedAchievementIds = listOf("first_listen", "one_hour", "streak_3", "first_note", "complete_first"),
            ),
        )
        _ui.update { it.copy(snapshot = fixture, demoMode = true, section = AppSection.TODAY, selectedPodcastId = null) }
    }

    fun selectSection(section: AppSection) = _ui.update { it.copy(section = section, selectedPodcastId = null) }
    fun selectPodcast(id: String?) = _ui.update { it.copy(selectedPodcastId = id) }
    fun setInspector(mode: InspectorMode) = _ui.update { it.copy(inspectorMode = mode) }
    suspend fun fetchVideoTitle(videoId: String): String? = container.mediaTools.fetchVideoTitle(videoId)

    fun toggleInspector() = _ui.update { it.copy(inspectorVisible = !it.inspectorVisible) }
    fun setSearch(value: String) = _ui.update { it.copy(search = value) }
    fun filterCategory(id: String?) = _ui.update { it.copy(selectedCategoryId = id, selectedCollectionId = null) }
    fun filterCollection(id: String?) = _ui.update { it.copy(selectedCollectionId = id, selectedCategoryId = null) }
    fun clearMessage() = _ui.update { it.copy(message = null) }

    fun addEpisode(title: String, input: String, categoryId: String): Boolean {
        val videoId = Podcast.extractVideoId(input) ?: return false.also { showMessage("Enter a valid YouTube URL or video ID.") }
        val state = _ui.value.snapshot
        if (state.podcasts.any { it.youtubeVideoId == videoId }) return false.also { showMessage("That episode is already in your library.") }
        val podcast = Podcast(
            title = title.trim().ifBlank { "Untitled episode" }, url = "https://www.youtube.com/watch?v=$videoId",
            youtubeVideoId = videoId, thumbnailUrl = "https://img.youtube.com/vi/$videoId/mqdefault.jpg",
            categoryId = categoryId.takeIf { id -> state.categories.any { it.id == id } } ?: LearningCategory.GENERAL_ID,
        )
        mutate { snapshot -> snapshot.copy(
            podcasts = snapshot.podcasts + podcast,
            stats = snapshot.stats.copy(totalPodcastsAdded = snapshot.stats.totalPodcastsAdded + 1),
        ) }
        checkAchievements()
        scheduleAndSync()
        return true
    }

    suspend fun previewPlaylist(url: String): PlaylistPreview = container.mediaTools.previewPlaylist(url)

    fun importPlaylist(preview: PlaylistPreview, categoryId: String): Triple<Int, Int, Int> {
        val snapshot = _ui.value.snapshot
        var collection = snapshot.collections.firstOrNull { it.sourcePlaylistId == preview.playlistId }
        if (collection == null) {
            collection = PodcastCollection(
                title = preview.title, sourcePlaylistId = preview.playlistId, sourceUrl = preview.sourceUrl,
                sortOrder = snapshot.collections.size, videoIds = preview.episodes.sortedBy { it.playlistIndex }.map { it.videoId },
            )
        } else {
            val newest = preview.episodes.sortedBy { it.playlistIndex }.map { it.videoId }
            collection = collection.copy(title = preview.title, sourceUrl = preview.sourceUrl, videoIds = newest + collection.videoIds.filterNot(newest::contains))
        }
        var added = 0
        var reused = 0
        val podcasts = snapshot.podcasts.toMutableList()
        preview.episodes.sortedBy { it.playlistIndex }.forEach { episode ->
            val index = podcasts.indexOfFirst { it.youtubeVideoId == episode.videoId }
            if (index >= 0) {
                if (collection!!.id !in podcasts[index].collectionIds) podcasts[index] = podcasts[index].copy(collectionIds = podcasts[index].collectionIds + collection!!.id)
                reused += 1
            } else {
                podcasts += Podcast(
                    title = episode.title, url = episode.url, youtubeVideoId = episode.videoId, thumbnailUrl = episode.thumbnailUrl,
                    collectionIds = listOf(collection!!.id), categoryId = categoryId,
                )
                added += 1
            }
        }
        val finalCollection = collection!!
        mutate { it.copy(
            podcasts = podcasts,
            collections = it.collections.filterNot { value -> value.id == finalCollection.id } + finalCollection,
            stats = it.stats.copy(totalPodcastsAdded = it.stats.totalPodcastsAdded + added),
        ) }
        checkAchievements(); scheduleAndSync()
        return Triple(added, reused, preview.unavailableCount)
    }

    fun removePodcast(id: String) {
        val podcast = _ui.value.snapshot.podcasts.firstOrNull { it.id == id } ?: return
        val download = _ui.value.snapshot.downloads[podcast.youtubeVideoId]
        mutate { snapshot -> snapshot.copy(
            podcasts = snapshot.podcasts.filterNot { it.id == id }, summaries = snapshot.summaries.filterNot { it.podcastId == id },
            transcripts = snapshot.transcripts - id, quirkyConversations = snapshot.quirkyConversations - id,
        ) }
        if (_ui.value.selectedPodcastId == id) selectPodcast(null)
        viewModelScope.launch {
            download?.let { container.downloads.delete(it) }
            runCatching { container.supabase.deletePodcast(id) }
        }
        persist()
    }

    fun deleteCollection(id: String) {
        mutate { snapshot -> snapshot.copy(
            collections = snapshot.collections.filterNot { it.id == id },
            podcasts = snapshot.podcasts.map { it.copy(collectionIds = it.collectionIds - id) },
        ) }
        filterCollection(null)
        viewModelScope.launch { runCatching { container.supabase.deleteCollection(id) } }
        persist()
    }

    fun updateNotes(podcastId: String, notes: String) {
        mutate { snapshot ->
            val before = snapshot.podcasts.firstOrNull { it.id == podcastId }?.notes.orEmpty()
            snapshot.copy(
                podcasts = snapshot.podcasts.map { if (it.id == podcastId) it.copy(notes = notes) else it },
                stats = if (before.isBlank() && notes.isNotBlank()) snapshot.stats.copy(totalNotesTaken = snapshot.stats.totalNotesTaken + 1) else snapshot.stats,
            )
        }
        checkAchievements(); scheduleProgressSync(podcastId)
    }

    fun markCompleted(podcastId: String) {
        val wasComplete = _ui.value.snapshot.podcasts.firstOrNull { it.id == podcastId }?.isCompleted ?: return
        mutate { snapshot ->
            val now = Instant.now()
            val videoId = snapshot.podcasts.firstOrNull { it.id == podcastId }?.youtubeVideoId
            snapshot.copy(
                podcasts = snapshot.podcasts.map { if (it.id == podcastId) it.copy(isCompleted = true, completedAt = it.completedAt ?: now) else it },
                stats = if (!wasComplete) snapshot.stats.copy(podcastsCompleted = snapshot.stats.podcastsCompleted + 1, totalXp = snapshot.stats.totalXp + 20) else snapshot.stats,
                downloads = if (!wasComplete && videoId != null && snapshot.downloads[videoId] != null && snapshot.downloads[videoId]?.expiresAt == null) {
                    snapshot.downloads + (videoId to snapshot.downloads.getValue(videoId).copy(expiresAt = now.plusSeconds(7 * 24 * 60 * 60)))
                } else snapshot.downloads,
            )
        }
        checkAchievements(); scheduleAndSync()
    }

    fun schedulePodcast(podcastId: String, instant: Instant?) {
        mutate { snapshot -> snapshot.copy(podcasts = snapshot.podcasts.map { if (it.id == podcastId) it.copy(scheduledAt = instant) else it }) }
        scheduleAndSync()
    }

    fun setDailyGoal(minutes: Double) {
        mutate { snapshot -> snapshot.copy(
            stats = snapshot.stats.copy(dailyGoalMinutes = minutes),
            habitSettings = snapshot.habitSettings.copy(currentDailyGoalMinutes = minutes),
            activities = upsertToday(snapshot.activities, minutes) { it.copy(goalMinutes = minutes) },
        ) }
        scheduleAndSync()
    }

    fun setWeeklyGoal(hours: Double) {
        mutate { it.copy(stats = it.stats.copy(weeklyGoalHours = hours)) }
        scheduleAndSync()
    }

    fun createCategory(name: String, color: String) {
        val trimmed = name.trim()
        if (trimmed.isBlank() || _ui.value.snapshot.categories.any { it.name.equals(trimmed, true) }) {
            showMessage("Category names must be unique and non-empty."); return
        }
        mutate { it.copy(categories = it.categories + LearningCategory(name = trimmed, colorToken = color, sortOrder = it.categories.size)) }
        scheduleAndSync()
    }

    fun updateCategory(id: String, name: String, color: String) {
        val trimmed = name.trim()
        if (trimmed.isBlank() || _ui.value.snapshot.categories.any { it.id != id && it.name.equals(trimmed, true) }) {
            showMessage("Category names must be unique and non-empty."); return
        }
        mutate { snapshot -> snapshot.copy(categories = snapshot.categories.map {
            if (it.id == id) it.copy(name = trimmed, colorToken = color, updatedAt = Instant.now()) else it
        }) }
        scheduleAndSync()
    }

    fun moveCategory(id: String, direction: Int) {
        val values = _ui.value.snapshot.categories.sortedBy { it.sortOrder }.toMutableList()
        val from = values.indexOfFirst { it.id == id }
        val to = (from + direction).coerceIn(0, values.lastIndex)
        if (from < 0 || from == to) return
        val item = values.removeAt(from)
        values.add(to, item)
        mutate { snapshot -> snapshot.copy(categories = values.mapIndexed { index, value -> value.copy(sortOrder = index, updatedAt = Instant.now()) }) }
        scheduleAndSync()
    }

    fun deleteCategory(id: String, replacementId: String?) {
        val snapshot = _ui.value.snapshot
        if (snapshot.categories.size <= 1) return showMessage("PodTrackio needs at least one category.")
        val used = snapshot.podcasts.any { it.categoryId == id }
        if (used && (replacementId == null || replacementId == id)) return showMessage("Choose a replacement category first.")
        mutate { value -> value.copy(
            categories = value.categories.filterNot { it.id == id }.mapIndexed { index, item -> item.copy(sortOrder = index, updatedAt = Instant.now()) },
            podcasts = value.podcasts.map { if (it.categoryId == id) it.copy(categoryId = replacementId!!) else it },
        ) }
        viewModelScope.launch { runCatching { container.supabase.reassignAndDeleteCategory(id, replacementId) } }
        scheduleAndSync()
    }

    fun startRescue(podcastId: String, minutes: Int, cue: DistractionCue) {
        val commitment = FocusCommitment(podcastId = podcastId, cue = cue, targetSeconds = minutes * 60.0)
        mutate { it.copy(focusCommitments = it.focusCommitments + commitment) }
        selectPodcast(podcastId)
        showMessage("$minutes-minute focus promise started. Only real playback counts.")
        persist()
    }

    fun cancelActiveCommitment() {
        mutate { snapshot -> snapshot.copy(focusCommitments = snapshot.focusCommitments.map {
            if (it.isActive) it.copy(cancelledAt = Instant.now()) else it
        }) }
        persist()
    }

    fun extendCommitment(minutes: Int) {
        val completed = _ui.value.snapshot.focusCommitments.lastOrNull { it.completedAt != null && it.cancelledAt == null } ?: return
        mutate { snapshot -> snapshot.copy(
            focusCommitments = snapshot.focusCommitments + FocusCommitment(podcastId = completed.podcastId, cue = completed.cue, targetSeconds = minutes * 60.0),
        ) }
        persist()
    }

    fun dismissCompletedCommitment() {
        mutate { snapshot -> snapshot.copy(focusCommitments = snapshot.focusCommitments.map { item ->
            if (item.completedAt != null && item.cancelledAt == null) item.copy(cancelledAt = item.completedAt) else item
        }) }
        persist()
    }

    fun onPlaybackProgress(podcastId: String, position: Double, duration: Double, playing: Boolean) {
        val previous = lastProgress[podcastId]
        lastProgress[podcastId] = position
        val delta = if (playing && previous != null) (position - previous).takeIf { it in 0.2..2.5 } ?: 0.0 else 0.0
        val now = Instant.now()
        mutate(immediatePersist = false) { snapshot ->
            var stats = snapshot.stats
            var activities = snapshot.activities
            var commitments = snapshot.focusCommitments
            if (delta > 0) {
                val oldMinutes = snapshot.activities.firstOrNull { it.dateKey == todayKey() }?.xpAwardedMinutes ?: 0
                activities = upsertToday(activities, snapshot.habitSettings.currentDailyGoalMinutes) { activity ->
                    val watched = activity.watchedSeconds + delta
                    val completedMinutes = (watched / 60).toInt()
                    val earned = max(0, completedMinutes - activity.xpAwardedMinutes)
                    val goalReached = watched >= activity.goalMinutes * 60
                    activity.copy(
                        watchedSeconds = watched, xpAwardedMinutes = completedMinutes,
                        xpEarned = activity.xpEarned + earned + if (goalReached && !activity.dailyGoalXpAwarded) 25 else 0,
                        goalCompleted = activity.goalCompleted || goalReached,
                        dailyGoalXpAwarded = activity.dailyGoalXpAwarded || goalReached,
                    )
                }
                val today = activities.first { it.dateKey == todayKey() }
                val xpGain = max(0, today.xpAwardedMinutes - oldMinutes) + if (today.dailyGoalXpAwarded && !(snapshot.activities.firstOrNull { it.dateKey == todayKey() }?.dailyGoalXpAwarded ?: false)) 25 else 0
                val streak = updateStreak(stats, today)
                stats = streak.copy(
                    totalSecondsWatched = streak.totalSecondsWatched + delta,
                    dailySecondsWatched = streak.dailySecondsWatched + delta,
                    weeklySecondsWatched = streak.weeklySecondsWatched + delta,
                    totalXp = streak.totalXp + xpGain,
                )
                commitments = commitments.map { item ->
                    if (item.isActive && item.podcastId == podcastId) {
                        val watched = (item.watchedSeconds + delta).coerceAtMost(item.targetSeconds)
                        item.copy(watchedSeconds = watched, completedAt = if (watched >= item.targetSeconds) now else null)
                    } else item
                }
            }
            snapshot.copy(
                podcasts = snapshot.podcasts.map { item -> if (item.id == podcastId) item.copy(
                    lastPlaybackPosition = position.coerceAtLeast(0.0), duration = duration.takeIf { it > 0 } ?: item.duration,
                    lastWatchedDate = if (playing) now else item.lastWatchedDate,
                    totalWatchedSeconds = item.totalWatchedSeconds + delta,
                ) else item },
                stats = stats, activities = activities, focusCommitments = commitments,
            )
        }
        _ui.update { it.copy(playingPodcastId = podcastId.takeIf { playing }) }
        persist(delayMs = 1_500)
        scheduleProgressSync(podcastId)
    }

    fun setTranscript(podcastId: String, text: String, source: TranscriptSource = TranscriptSource.pasted) {
        val trimmed = text.trim()
        if (trimmed.isBlank()) return showMessage("Paste a transcript before saving.")
        mutate { it.copy(transcripts = it.transcripts + (podcastId to TranscriptDocument(podcastId, source, trimmed))) }
        showMessage("Transcript saved on this tablet.")
        persist()
    }

    fun generateSummary(podcastId: String, useDownloadedAudio: Boolean = false) {
        val podcast = _ui.value.snapshot.podcasts.firstOrNull { it.id == podcastId } ?: return
        viewModelScope.launch {
            _ui.update { it.copy(summaryStatus = "Preparing transcript…") }
            runCatching {
                var transcript = _ui.value.snapshot.transcripts[podcastId]
                if (transcript == null) {
                    transcript = if (useDownloadedAudio) {
                        val record = _ui.value.snapshot.downloads[podcast.youtubeVideoId] ?: error("Download this episode first.")
                        _ui.update { it.copy(summaryStatus = "Transcribing downloaded media…") }
                        container.ai.transcribe(podcast, File(record.filePath))
                    } else container.ai.fetchTranscript(podcast)
                    mutate { it.copy(transcripts = it.transcripts + (podcastId to transcript)) }
                }
                _ui.update { it.copy(summaryStatus = "Building your learning brief…") }
                val summary = container.ai.summarize(podcast, transcript)
                mutate { snapshot -> snapshot.copy(
                    summaries = snapshot.summaries.filterNot { it.podcastId == podcastId } + summary,
                    stats = unlock(snapshot.stats, "first_summary"),
                ) }
                scheduleAndSync()
                _ui.update { it.copy(summaryStatus = null, inspectorMode = InspectorMode.SUMMARY, message = "Learning brief ready.") }
            }.onFailure { error -> _ui.update { it.copy(summaryStatus = null, message = error.message ?: "Summary generation failed.") } }
        }
    }

    fun askQuirky(podcastId: String, question: String, model: QuirkyModel, style: AnswerStyle) {
        if (question.isBlank()) return
        val podcast = _ui.value.snapshot.podcasts.firstOrNull { it.id == podcastId } ?: return
        val transcript = _ui.value.snapshot.transcripts[podcastId] ?: return showMessage("Generate a summary or add a transcript first.")
        val history = _ui.value.snapshot.quirkyConversations[podcastId].orEmpty()
        val userMessage = QuirkyMessage(role = "user", content = question.trim())
        mutate { it.copy(quirkyConversations = it.quirkyConversations + (podcastId to (history + userMessage))) }
        viewModelScope.launch {
            _ui.update { it.copy(chatBusy = true) }
            runCatching { container.ai.chat(podcast, transcript, question, history, model, style) }
                .onSuccess { answer ->
                    mutate { snapshot ->
                        val current = snapshot.quirkyConversations[podcastId].orEmpty()
                        snapshot.copy(quirkyConversations = snapshot.quirkyConversations + (podcastId to (current + QuirkyMessage(role = "assistant", content = answer))))
                    }
                }.onFailure { showMessage(it.message ?: "Quirky could not answer.") }
            _ui.update { it.copy(chatBusy = false) }
        }
    }

    fun updateBrain(transform: (com.tangenix.podtrackio.domain.BrainState) -> com.tangenix.podtrackio.domain.BrainState) {
        mutate { it.copy(brain = transform(it.brain)) }
    }

    fun askBrain(question: String, model: QuirkyModel = QuirkyModel.DEEP, style: AnswerStyle = AnswerStyle.MEDIUM) {
        if (_ui.value.brainBusy || question.isBlank()) return
        if (question.length > 2000) return showMessage("Keep your question under 2,000 characters.")
        val snapshot = _ui.value.snapshot
        val prior = snapshot.brain
        _ui.update { it.copy(brainBusy = true) }
        updateBrain { it.copy(messages = it.messages + com.tangenix.podtrackio.domain.BrainMessage(role = "user", text = question)) }
        viewModelScope.launch {
            runCatching {
                val sources = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
                    com.tangenix.podtrackio.domain.BrainIndex.build(snapshot).retrieve(question + " " + prior.messages.takeLast(4).filter { it.role == "user" }.joinToString(" ") { it.text })
                }
                val reply = container.ai.brainReply(prior, sources, question, model, style)
                updateBrain { state ->
                    val additions = if (state.rememberPreferences) reply.memories.take(3).filter {
                        !it.evidence.isNullOrBlank() && question.contains(it.evidence) && it.evidence.length <= 300 && state.memories.none { m -> m.text.equals(it.evidence, true) }
                    }.map { com.tangenix.podtrackio.domain.PersonalMemory(text = it.evidence, evidence = it.evidence) } else emptyList()
                    state.copy(messages = state.messages + com.tangenix.podtrackio.domain.BrainMessage(role = "assistant", text = reply.answer, sources = sources), memories = (state.memories + additions).take(100))
                }
            }.onFailure { showMessage(it.message ?: "Brain could not answer.") }
            _ui.update { it.copy(brainBusy = false) }
        }
    }

    fun clearQuirky(podcastId: String) {
        mutate { it.copy(quirkyConversations = it.quirkyConversations + (podcastId to emptyList())) }
    }

    fun toggleAction(podcastId: String, actionId: String) {
        mutate { snapshot ->
            var grant = false
            val summaries = snapshot.summaries.map { summary ->
                if (summary.podcastId != podcastId) summary else {
                    val actions = summary.actionPlan.map { if (it.id == actionId) it.copy(isCompleted = !it.isCompleted) else it }
                    val done = actions.isNotEmpty() && actions.all(SummaryAction::isCompleted)
                    grant = done && !summary.actionPlanXpGranted
                    summary.copy(actionPlan = actions, actionPlanXpGranted = summary.actionPlanXpGranted || done)
                }
            }
            snapshot.copy(summaries = summaries, stats = if (grant) unlock(snapshot.stats.copy(totalXp = snapshot.stats.totalXp + 15), "first_action_plan") else snapshot.stats)
        }
        scheduleAndSync()
    }

    fun download(podcastId: String) {
        val podcast = _ui.value.snapshot.podcasts.firstOrNull { it.id == podcastId } ?: return
        viewModelScope.launch {
            _ui.update { it.copy(downloadProgress = it.downloadProgress + (podcastId to 0f)) }
            runCatching {
                val currentBytes = _ui.value.snapshot.downloads.values.sumOf { it.byteCount }
                container.downloads.download(podcast, _ui.value.snapshot.downloadQuality, MAX_DOWNLOAD_BYTES, currentBytes) { progress ->
                    _ui.update { it.copy(downloadProgress = it.downloadProgress + (podcastId to progress)) }
                }
            }.onSuccess { record ->
                mutate { it.copy(downloads = it.downloads + (podcast.youtubeVideoId to record)) }
                showMessage("Saved for offline playback.")
            }.onFailure { showMessage(it.message ?: "Download failed.") }
            _ui.update { it.copy(downloadProgress = it.downloadProgress - podcastId) }
        }
    }

    fun deleteDownload(podcastId: String) {
        val podcast = _ui.value.snapshot.podcasts.firstOrNull { it.id == podcastId } ?: return
        val record = _ui.value.snapshot.downloads[podcast.youtubeVideoId] ?: return
        viewModelScope.launch { container.downloads.delete(record) }
        mutate { it.copy(downloads = it.downloads - podcast.youtubeVideoId) }
    }

    suspend fun playbackUri(podcastId: String): String {
        val podcast = _ui.value.snapshot.podcasts.firstOrNull { it.id == podcastId } ?: error("Episode not found.")
        _ui.value.snapshot.downloads[podcast.youtubeVideoId]?.let { record ->
            if (File(record.filePath).exists()) return Uri.fromFile(File(record.filePath)).toString()
        }
        return container.mediaTools.resolve(podcast.youtubeVideoId, _ui.value.snapshot.downloadQuality).url
    }

    fun setDownloadQuality(quality: DownloadQuality) = mutate { it.copy(downloadQuality = quality) }
    fun setTheme(theme: String) = mutate { it.copy(theme = theme) }
    fun setHabitSettings(settings: HabitSettings) {
        mutate { snapshot -> snapshot.copy(
            habitSettings = settings,
            stats = snapshot.stats.copy(dailyGoalMinutes = settings.currentDailyGoalMinutes),
        ) }
        scheduleAndSync()
    }
    fun setNotificationPreferences(preferences: NotificationPreferences) {
        mutate { it.copy(notificationPreferences = preferences) }
        viewModelScope.launch { container.reminders.reschedule(_ui.value.snapshot) }
    }

    fun storeGroqKey(value: String?) { container.ai.groqKey = value; showMessage(if (value.isNullOrBlank()) "Groq key removed." else "Groq key saved in Android Keystore.") }
    fun storeTranscriptKey(value: String?) { container.ai.transcriptApiKey = value; showMessage(if (value.isNullOrBlank()) "TranscriptAPI key removed." else "TranscriptAPI key saved in Android Keystore.") }
    fun hasGroqKey() = !container.ai.groqKey.isNullOrBlank()
    fun hasTranscriptKey() = !container.ai.transcriptApiKey.isNullOrBlank()
    fun testGroq() { viewModelScope.launch { runCatching { container.ai.testGroq() }.onSuccess { showMessage("Connected to Groq.") }.onFailure { showMessage(it.message ?: "Connection failed.") } } }

    fun refreshCloud() { if (auth.value.isAuthenticated) sync() }

    private fun sync() {
        if (syncJob?.isActive == true) return
        val user = auth.value.profile ?: return
        syncJob = viewModelScope.launch {
            _ui.update { it.copy(syncing = true) }
            runCatching {
                val local = _ui.value.snapshot
                val remote = container.supabase.fetchWorkspace(user.id)
                val podcasts = mergePodcasts(local.podcasts, remote.podcasts)
                val categories = mergeCategories(local.categories, remote.categories)
                val activities = mergeById(local.activities, remote.activities) { it.dateKey }
                val summaries = mergeSummaries(local.summaries, remote.summaries)
                val collections = mergeById(local.collections, remote.collections) { it.id }.sortedBy { it.sortOrder }
                val merged = local.copy(
                    podcasts = podcasts, categories = categories, activities = activities,
                    summaries = summaries, collections = collections, stats = remote.stats ?: local.stats,
                )
                _ui.update { it.copy(snapshot = merged) }
                container.localStore.save(merged)
                container.supabase.pushWorkspace(user.id, podcasts, categories, activities, summaries, collections, merged.stats)
                container.reminders.reschedule(merged)
            }.onFailure { error -> showMessage("Cloud sync deferred. Your local workspace is safe. ${error.message.orEmpty().take(180)}") }
            _ui.update { it.copy(syncing = false) }
        }
    }

    private fun scheduleProgressSync(podcastId: String) {
        progressSyncJobs[podcastId]?.cancel()
        progressSyncJobs[podcastId] = viewModelScope.launch {
            delay(4_000)
            val user = auth.value.profile ?: return@launch
            val state = _ui.value.snapshot
            val podcast = state.podcasts.firstOrNull { it.id == podcastId } ?: return@launch
            runCatching { container.supabase.pushPodcast(user.id, podcast, state.categories) }
            progressSyncJobs.remove(podcastId)
        }
    }

    private fun scheduleAndSync() {
        persist()
        viewModelScope.launch { container.reminders.reschedule(_ui.value.snapshot) }
        if (auth.value.isAuthenticated) sync()
    }

    private fun mutate(immediatePersist: Boolean = true, operation: (AppSnapshot) -> AppSnapshot) {
        _ui.update { state -> state.copy(snapshot = operation(state.snapshot)) }
        if (immediatePersist) persist()
    }

    private fun persist(delayMs: Long = 0) {
        persistJob?.cancel()
        persistJob = viewModelScope.launch {
            if (delayMs > 0) delay(delayMs)
            container.localStore.save(_ui.value.snapshot)
        }
    }

    private fun showMessage(message: String) = _ui.update { it.copy(message = message) }

    private fun checkAchievements() {
        mutate { snapshot ->
            val stats = snapshot.stats
            val watchedHours = stats.totalSecondsWatched / 3600
            val notes = snapshot.podcasts.count { it.notes.isNotBlank() }
            val completed = snapshot.podcasts.count(Podcast::isCompleted)
            val categories = snapshot.podcasts.filter { it.totalWatchedSeconds > 0 }.map { it.categoryId }.toSet().size
            val unlock = buildSet {
                if (stats.totalSecondsWatched > 0) add("first_listen")
                listOf(1 to "one_hour", 5 to "five_hours", 10 to "ten_hours", 25 to "twentyfive_hours", 50 to "fifty_hours", 100 to "hundred_hours").forEach { if (watchedHours >= it.first) add(it.second) }
                listOf(3 to "streak_3", 7 to "streak_7", 14 to "streak_14", 30 to "streak_30", 100 to "streak_100").forEach { if (stats.currentStreak >= it.first) add(it.second) }
                if (notes >= 1) add("first_note"); if (notes >= 10) add("ten_notes"); if (notes >= 25) add("twentyfive_notes")
                if (snapshot.podcasts.size >= 5) add("five_podcasts"); if (snapshot.podcasts.size >= 10) add("ten_podcasts"); if (snapshot.podcasts.size >= 25) add("twentyfive_podcasts")
                if (categories >= 3) add("three_categories"); if (categories >= 6) add("six_categories")
                if (completed >= 1) add("complete_first"); if (completed >= 5) add("complete_five"); if (completed >= 10) add("complete_ten")
                if (stats.level.number >= 5) add("level_5"); if (stats.level.number >= 10) add("level_10")
            }
            snapshot.copy(stats = stats.copy(unlockedAchievementIds = (stats.unlockedAchievementIds + unlock).distinct()))
        }
    }

    private fun updateStreak(stats: UserStats, activity: DailyLearningActivity): UserStats {
        if (!activity.qualifiesForStreak) return stats
        val last = stats.lastActiveDate?.localDate()
        val today = LocalDate.now()
        if (last == today) return stats
        val streak = if (last == today.minusDays(1)) stats.currentStreak + 1 else 1
        return stats.copy(currentStreak = streak, longestStreak = max(stats.longestStreak, streak), lastActiveDate = Instant.now())
    }

    private fun unlock(stats: UserStats, id: String) = if (id in stats.unlockedAchievementIds) stats else stats.copy(unlockedAchievementIds = stats.unlockedAchievementIds + id)

    private fun upsertToday(
        activities: List<DailyLearningActivity>,
        goal: Double,
        update: (DailyLearningActivity) -> DailyLearningActivity,
    ): List<DailyLearningActivity> {
        val key = todayKey()
        val current = activities.firstOrNull { it.dateKey == key } ?: DailyLearningActivity(key, goalMinutes = goal)
        return activities.filterNot { it.dateKey == key } + update(current)
    }

    private fun mergePodcasts(local: List<Podcast>, remote: List<Podcast>): List<Podcast> {
        val values = local.associateBy { it.id }.toMutableMap()
        remote.forEach { item -> values[item.id] = values[item.id]?.mergedForSync(item) ?: item }
        return values.values.sortedByDescending { it.dateAdded }
    }

    private fun mergeCategories(local: List<LearningCategory>, remote: List<LearningCategory>): List<LearningCategory> {
        if (remote.isEmpty()) return local.ifEmpty { LearningCategory.defaults }
        val values = local.associateBy { it.id }.toMutableMap()
        remote.forEach { item -> if (item.updatedAt > (values[item.id]?.updatedAt ?: Instant.MIN)) values[item.id] = item }
        return values.values.sortedBy { it.sortOrder }
    }

    private fun mergeSummaries(local: List<PodcastSummary>, remote: List<PodcastSummary>): List<PodcastSummary> {
        val values = local.associateBy { it.podcastId }.toMutableMap()
        remote.forEach { item -> if (item.generatedAt > (values[item.podcastId]?.generatedAt ?: Instant.MIN)) values[item.podcastId] = item }
        return values.values.toList()
    }

    private fun <T> mergeById(local: List<T>, remote: List<T>, id: (T) -> String): List<T> {
        val values = local.associateBy(id).toMutableMap()
        remote.forEach { values[id(it)] = it }
        return values.values.toList()
    }

    class Factory(private val container: AppContainer) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T = PodTrackioViewModel(container) as T
    }

    companion object { const val MAX_DOWNLOAD_BYTES: Long = 8L * 1_024 * 1_024 * 1_024 }
}
