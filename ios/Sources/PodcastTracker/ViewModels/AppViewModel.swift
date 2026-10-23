import Combine
import Foundation
import SwiftUI
import WidgetKit
import UIKit

enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case library = "Library"
    case progress = "Progress"
    case brain = "Brain"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .today: "sun.max"
        case .library: "books.vertical"
        case .progress: "calendar"
        case .brain: "brain"
        }
    }
}

enum PlayerInspectorMode: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case notes = "Notes"
    case chat = "Chat"
    var id: String { rawValue }
}

@MainActor
final class AppViewModel: ObservableObject {
    static let shared = AppViewModel()

    @Published var podcasts: [Podcast] = []
    @Published var stats = UserStats()
    @Published var achievements: [Achievement] = []
    @Published var categories: [LearningCategory] = []
    @Published var activities: [DailyLearningActivity] = []
    @Published var summaries: [PodcastSummary] = []
    @Published private(set) var quirkyConversations: [UUID: [QuirkyChatMessage]] = [:]
    @Published var habitLoop = HabitLoop()
    @Published var habitMessage: String?
    @Published var showDailyCelebration = false
    @Published var recallBusy = false
    @Published var habitSettings = HabitSettings()
    @Published var notificationPreferences = NotificationPreferences()
    @Published var focusCommitments: [FocusCommitment] = []
    @Published var collections: [PodcastCollection] = []

    @Published var selectedSection: AppSection = .today
    @Published var selectedPodcast: Podcast?
    @Published var selectedCategoryID: String?
    @Published var selectedCollectionID: UUID?
    @Published var selectedCalendarDate = Date()
    @Published var inspectorMode: PlayerInspectorMode = .summary
    @Published var inspectorPresented = true
    @Published var searchText = ""
    @Published var showAddPodcast = false
    @Published var showSettings = false
    @Published var showFocusGate = false
    @Published var showRescueSheet = false
    @Published var isTracking = false
    @Published var currentSessionSeconds: Double = 0
    @Published var completedCommitment: FocusCommitment?
    @Published private(set) var playbackStartRequest: PlaybackStartRequest?
    @Published var showLevelUpAlert = false
    @Published var newlyUnlockedAchievement: Achievement?
    @Published var showAchievementPopup = false
    @Published var summaryState: SummaryGenerationState = .idle
    @Published var transcriptImportPresented = false

    private let dataManager = DataManager.shared
    private var playbackCredit = PlaybackCreditTracker()
    private var checkpointSeconds: Double = 0
    private var saveTimer: Timer?
    private var downloadCleanupTimer: Timer?
    private var progressSyncTasks: [UUID: Task<Void, Never>] = [:]
    private var syncInFlight = false
    private var previousLevel = 1
    private var cancellables = Set<AnyCancellable>()

    var continueWatching: [Podcast] {
        podcasts.filter { $0.hasProgress && !$0.isCompleted }
            .sorted { ($0.lastWatchedDate ?? .distantPast) > ($1.lastWatchedDate ?? .distantPast) }
    }

    var nextPodcast: Podcast? {
        continueWatching.first ?? podcasts.filter { !$0.isCompleted }.sorted { $0.dateAdded < $1.dateAdded }.first
    }

    var recentlyAdded: [Podcast] { Array(podcasts.sorted { $0.dateAdded > $1.dateAdded }.prefix(6)) }
    var completedPodcasts: [Podcast] { podcasts.filter(\.isCompleted) }
    var todayActivity: DailyLearningActivity? { activity(for: Date()) }
    var todayWatchedMinutes: Int { Int(habitLoop.learnedSeconds(on: LearningCalendar.dateKey(for: Date())) / 60) }
    var todayRemainingMinutes: Int {
        let day = LearningCalendar.dateKey(for: Date())
        return max(0, Int(ceil((habitLoop.goalSeconds(on: day, fallback: habitSettings.currentDailyGoalMinutes * 60) - habitLoop.learnedSeconds(on: day)) / 60)))
    }

    var activeCommitment: FocusCommitment? {
        guard let podcastID = selectedPodcast?.id else { return nil }
        return focusCommitments.last { $0.podcastID == podcastID && $0.isActive }
    }

    var latestActiveCommitment: FocusCommitment? {
        focusCommitments.last(where: \.isActive)
    }

    var committedPodcast: Podcast? {
        guard let podcastID = latestActiveCommitment?.podcastID else { return nil }
        return podcasts.first { $0.id == podcastID }
    }

    var weeklyRescueInsights: RescueInsights {
        RescueInsightsEngine.weekly(commitments: focusCommitments)
    }

    var learnedDistractionPattern: DistractionPattern? {
        DistractionPatternEngine.leadingPattern(commitments: focusCommitments)
    }

    var preferredDistractionCue: DistractionCue? {
        let completed = focusCommitments.filter { $0.isCompleted && $0.cue.isDistraction }
        guard !completed.isEmpty else { return nil }
        let counts = Dictionary(grouping: completed, by: \.cue).mapValues(\.count)
        return counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue > rhs.key.rawValue : lhs.value < rhs.value
        }?.key
    }

    var filteredPodcasts: [Podcast] {
        let matches = podcasts.filter { podcast in
            let categoryName = category(for: podcast.categoryID)?.name ?? ""
            let collectionNames = collections
                .filter { podcast.collectionIDs.contains($0.id) }
                .map(\.title)
                .joined(separator: " ")
            let matchesSearch = searchText.isEmpty || podcast.title.localizedCaseInsensitiveContains(searchText)
                || categoryName.localizedCaseInsensitiveContains(searchText)
                || collectionNames.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategoryID == nil || podcast.categoryID == selectedCategoryID
            let matchesCollection = selectedCollectionID == nil || podcast.collectionIDs.contains(selectedCollectionID!)
            return matchesSearch && matchesCategory && matchesCollection
        }
        guard let selectedCollectionID,
              let collection = collections.first(where: { $0.id == selectedCollectionID }) else {
            return matches.sorted { $0.dateAdded > $1.dateAdded }
        }
        let positions = Dictionary(uniqueKeysWithValues: collection.videoIDs.enumerated().map { ($0.element, $0.offset) })
        return matches.sorted {
            (positions[$0.youtubeVideoId] ?? .max) < (positions[$1.youtubeVideoId] ?? .max)
        }
    }

    var categoriesUsed: Set<String> {
        Set(podcasts.filter { $0.totalWatchedSeconds > 0 }.map(\.categoryID))
    }

    var streakProtectedToday: Bool { habitLoop.completedGoal(on: LearningCalendar.dateKey(for: Date())) }
    var habitStreakStatus: (count: Int, freezes: Int, frozenDays: Set<String>) { habitLoop.streak(activities: activities) }
    var habitLeague: HabitLeague { habitLoop.league(activities: activities) }

    func reconcileHabitLoop(celebrate: Bool = true) {
        prepareDailyLearningGoal()
        let wins = habitLoop.reconcile(activities: activities, goalMinutes: habitSettings.currentDailyGoalMinutes)
        stats.totalXP = habitLoop.legacyXP + habitLoop.rewardXP
        recomputeStreak()
        presentLevelToastIfNeeded()
        if celebrate, let last = wins.last { habitMessage = last }
        if celebrate { PlayMoments.shared.noteWins(wins) }
        if celebrate, streakProtectedToday,
           habitLoop.insert(.init(id: "celebrated/\(habitLoop.deviceID)/\(LearningCalendar.dateKey(for: Date()))", day: LearningCalendar.dateKey(for: Date()), kind: "baseline")) {
            showDailyCelebration = true
        }
        let today = LearningCalendar.dateKey(for: Date())
        if streakProtectedToday {
            for index in habitLoop.reminderHistory.indices where habitLoop.reminderHistory[index].day == today
                && habitLoop.reminderHistory[index].fireTime <= Date()
                && Date().timeIntervalSince(habitLoop.reminderHistory[index].fireTime) <= 3600
                && habitLoop.learnedSeconds(on: today) >= habitLoop.reminderHistory[index].baselineSeconds + 300 {
                habitLoop.reminderHistory[index].completed = true
            }
        }
    }

    private func prepareDailyLearningGoal() {
        let day = LearningCalendar.dateKey(for: Date())
        habitSettings.currentDailyGoalMinutes = habitLoop.prepareDailyGoal(day: day)
        stats.dailyGoalMinutes = habitSettings.currentDailyGoalMinutes
        FocusModeController.shared.updateGoal(target: habitSettings.currentDailyGoalMinutes * 60,
            localSeconds: habitLoop.localSeconds(on: day), owner: habitLoop.ownerID)
    }

    private func acceptForegroundFocusSync() {
        #if os(iOS)
        guard UIApplication.shared.applicationState == .active else { return }
        #endif
        let day = LearningCalendar.dateKey(for: Date())
        prepareDailyLearningGoal()
        FocusModeController.shared.updateGoal(target: habitSettings.currentDailyGoalMinutes * 60,
            localSeconds: habitLoop.localSeconds(on: day), sharedSeconds: habitLoop.learnedSeconds(on: day), owner: habitLoop.ownerID)
        FocusModeController.shared.checkpoint()
    }

    func purchaseHabitItem(_ item: String) {
        guard AuthManager.shared.isAuthenticated else { habitMessage = "Sign in and sync to spend shared gems. Learning and earning work offline."; return }
        let purchaseOwner = AuthManager.shared.userId
        Task {
            do {
                let result = try await SupabaseClient.shared.syncHabitLoop(habitLoop, purchase: item, purchaseID: UUID().uuidString)
                guard AuthManager.shared.userId == purchaseOwner else { return }
                habitLoop.legacyXP = result.legacyXP
                habitLoop.startedDay = result.startedDay
                habitLoop.merge(result.events)
                reconcileHabitLoop(celebrate: false)
                saveLocalData()
                habitMessage = item == "freeze" ? "Freeze refilled. This does not unlock apps." : "Seven-day promise started · 20 gems staked · 40 back for seven learning days."
            } catch { habitMessage = "Purchase unavailable: \(error.localizedDescription)" }
        }
    }

    func generateRecall(for podcast: Podcast) {
        guard !recallBusy else { return }
        guard let transcript = dataManager.loadTranscript(for: podcast.id), !transcript.text.isEmpty else {
            habitMessage = "Generate a summary or import a transcript first. A takeaway note also completes your reflection quest."; return
        }
        guard let key = KeychainStore.groqAPIKey() else { habitMessage = "Add your Groq key in Settings. Existing reviews remain available offline."; return }
        let reviewOwner = habitLoop.ownerID
        recallBusy = true
        Task {
            defer { recallBusy = false }
            do {
                let questions = try await GroqClient.shared.recallQuestions(transcript: transcript.text, apiKey: key)
                guard habitLoop.ownerID == reviewOwner else { return }
                guard questions.count >= 2, questions.allSatisfy({ $0.isValid(in: transcript.text) }) else { throw GroqError.malformedResponse }
                let review = RecallReview(id: UUID().uuidString, podcastID: podcast.id,
                    transcriptDigest: RecallEvidence.digest(transcript.text), questions: questions,
                    createdDay: LearningCalendar.dateKey(for: Date()))
                habitLoop.reviews.removeAll { $0.podcastID == podcast.id }
                habitLoop.reviews.append(review)
                saveLocalData()
                habitMessage = "Three source-backed questions are ready. Listening alone still unlocks apps."
            } catch { habitMessage = "Review unavailable: \(error.localizedDescription) A takeaway note also counts." }
        }
    }

    func finishRecall(reviewID: String, stage: Int, correct: Int) {
        guard let index = habitLoop.reviews.firstIndex(where: { $0.id == reviewID }),
              (0...3).contains(correct),
              habitLoop.reviews[index].dueStage(on: LearningCalendar.dateKey(for: Date())) == stage else { return }
        let review = habitLoop.reviews[index]
        habitLoop.reviews[index].completedStages.insert(stage)
        let day = LearningCalendar.dateKey(for: Date())
        habitLoop.reflect(on: day)
        habitLoop.insert(.init(id: "recall/\(review.podcastID.uuidString)/\(review.createdDay)/\(stage)", day: day, kind: "xp", value: 10))
        saveData()
        habitMessage = "Review complete · \(correct)/3 correct · +10 XP. Next reviews: days 1, 3 and 7."
    }

    init() {
        loadData()
        startAutoSave()
        startDownloadCleanup()
        setupAuthObserver()
        setupNotificationRoutes()
    }

    func loadData() {
        podcasts = dataManager.loadPodcasts()
        stats = dataManager.loadStats()
        achievements = ProgressionEngine.migrateAchievements(dataManager.loadAchievements())
        categories = dataManager.loadCategories()
        activities = dataManager.loadActivities()
        summaries = dataManager.loadSummaries()
        quirkyConversations = dataManager.loadQuirkyConversations()
        habitSettings = dataManager.loadHabitSettings()
        habitLoop = dataManager.loadHabitLoop(ownerID: AuthManager.shared.userId?.uuidString) ?? {
            var value = HabitLoop(); value.ownerID = AuthManager.shared.userId?.uuidString; value.legacyXP = stats.totalXP
            for milestone in [3, 7, 14, 30, 50, 100, 365] where stats.longestStreak >= milestone {
                value.insert(.init(id: "milestone/\(milestone)", day: value.startedDay, kind: "baseline", value: Double(milestone)))
            }
            return value
        }()
        habitMessage = dataManager.habitPersistenceError
        habitLoop.lastOpenedAt = Date()
        notificationPreferences = dataManager.loadNotificationPreferences()
        focusCommitments = dataManager.loadFocusCommitments()
        collections = dataManager.loadCollections()

        let migrationDate = Date()
        for index in podcasts.indices where podcasts[index].isCompleted && podcasts[index].completedAt == nil {
            podcasts[index].completedAt = migrationDate
        }
        LocalMediaStore.shared.reconcile(with: podcasts, migrationDate: migrationDate)

        seedMissingCategoriesAndRepairReferences()
        prepareDailyLearningGoal()
        stats.dailyGoalMinutes = habitSettings.currentDailyGoalMinutes
        stats.resetDailyIfNeeded()
        stats.resetWeeklyIfNeeded()
        reconcileHabitLoop(celebrate: false)
        FocusModeController.shared.refresh()
        previousLevel = stats.currentLevel.number
        saveLocalData()
        rescheduleNotifications()

        refreshCloudData()
    }

    func saveData() {
        reconcileHabitLoop()
        saveLocalData()
        guard AuthManager.shared.isAuthenticated, !Self.demoMode else { return }
        let syncOwner = AuthManager.shared.userId
        let currentStats = stats
        let currentPodcasts = podcasts
        let currentCategories = categories
        let currentActivities = activities
        let currentSummaries = summaries
        let currentCollections = collections
        Task {
            do {
                if let result = try? await SupabaseClient.shared.syncHabitLoop(habitLoop) {
                    guard AuthManager.shared.userId == syncOwner else { return }
                    habitLoop.legacyXP = result.legacyXP
                    habitLoop.startedDay = result.startedDay
                    habitLoop.merge(result.events)
                    reconcileHabitLoop(celebrate: false)
                    saveLocalData()
                }
                guard AuthManager.shared.userId == syncOwner else { return }
                try await SupabaseClient.shared.upsertStats(currentStats)
                try await SupabaseClient.shared.upsertPodcasts(currentPodcasts, categories: currentCategories)
                try await SupabaseClient.shared.upsertCategories(currentCategories)
                try await SupabaseClient.shared.upsertActivities(currentActivities)
                try await SupabaseClient.shared.upsertSummaries(currentSummaries)
                try await SupabaseClient.shared.upsertCollections(currentCollections)
            } catch {
                print("Cloud sync deferred: \(error.localizedDescription)")
            }
        }
    }

    private func saveLocalData() {
        FocusModeController.shared.checkpoint()
        dataManager.savePodcasts(podcasts)
        dataManager.saveStats(stats)
        dataManager.saveAchievements(achievements)
        dataManager.saveCategories(categories)
        dataManager.saveActivities(activities)
        dataManager.saveSummaries(summaries)
        dataManager.saveQuirkyConversations(quirkyConversations)
        dataManager.saveHabitLoop(habitLoop)
        dataManager.saveHabitSettings(habitSettings)
        dataManager.saveNotificationPreferences(notificationPreferences)
        dataManager.saveFocusCommitments(focusCommitments)
        dataManager.saveCollections(collections)
        updateWidgetSnapshot()
    }

    /// "21:00" / "1:04:30", the timecode the player shows.
    private static func clock(_ seconds: Double) -> String {
        let t = Int(seconds), h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func updateWidgetSnapshot() {
        let next = nextPodcast
        let snapshot = PodTrackioWidgetSnapshot(
            todayWatchedMinutes: todayWatchedMinutes,
            dailyGoalMinutes: Int(habitSettings.currentDailyGoalMinutes),
            currentStreak: stats.currentStreak,
            totalXP: stats.totalXP,
            levelTitle: stats.currentLevel.title,
            libraryCount: podcasts.count,
            completedCount: completedPodcasts.count,
            nextEpisodeID: next?.id,
            nextEpisodeTitle: next?.title,
            nextEpisodeProgress: next?.progressPercentage ?? 0,
            snapshotDay: LearningCalendar.dateKey(for: Date()),
            streakProtected: streakProtectedToday,
            focusMinutesRemaining: FocusModeController.shared.state.enabled ? FocusModeController.shared.state.remainingMinutes : nil,
            focusTargetMinutes: FocusModeController.shared.state.enabled ? Int(FocusModeController.shared.state.dailyTargetSeconds / 60) : nil,
            gems: habitLoop.gems,
            weekStates: weekStrip.map(\.widgetState),
            freezes: habitStreakStatus.freezes,
            questsDone: habitLoop.questCount(on: LearningCalendar.dateKey(for: Date())),
            levelNumber: stats.currentLevel.number,
            levelProgress: levelProgress,
            nextEpisodeResumeLabel: next.map { $0.hasProgress ? "Resume at \(Self.clock($0.lastPlaybackPosition))" : "Ready when you are" },
            hasThumbnail: WidgetThumbnailCache.hasThumbnail(for: next)
        )
        if PodTrackioWidgetSnapshotStore.save(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        WidgetThumbnailCache.refresh(for: next) { [weak self] in self?.updateWidgetSnapshot() }
    }

    func handleAppURL(_ url: URL) {
        guard url.scheme?.lowercased() == "podtrackio" else { return }
        switch url.host?.lowercased() {
        case "today":
            selectedSection = .today
        case "library":
            selectedSection = .library
        case "progress":
            selectedSection = .progress
        case "add":
            showAddPodcast = true
        case "rescue":
            showRescueSheet = true
        case "continue":
            guard let podcast = nextPodcast else {
                showAddPodcast = true
                return
            }
            selectPodcast(podcast)
            playbackStartRequest = PlaybackStartRequest(podcastID: podcast.id)
        case "episode":
            guard let rawID = url.pathComponents.dropFirst().first,
                  let id = UUID(uuidString: rawID),
                  let podcast = podcasts.first(where: { $0.id == id }) else {
                selectedSection = .library
                return
            }
            selectPodcast(podcast)
            playbackStartRequest = PlaybackStartRequest(podcastID: podcast.id)
        default:
            break
        }
    }

    /// Pulls the latest cloud state whenever the app opens or becomes active.
    /// Local playback is merged by edit time before any upload, so a slow
    /// response cannot erase the position the person just reached.
    func refreshCloudData() {
        prepareDailyLearningGoal()
        FocusModeController.shared.refresh()
        guard AuthManager.shared.isAuthenticated, !syncInFlight, !Self.demoMode else { return }
        Task { await syncWithSupabase() }
    }

    private func syncWithSupabase() async {
        guard !syncInFlight else { return }
        let syncOwner = AuthManager.shared.userId
        syncInFlight = true
        defer { syncInFlight = false }
        do {
            let wasComplete = streakProtectedToday
            do {
                let value = try await SupabaseClient.shared.syncHabitLoop(habitLoop)
                guard AuthManager.shared.userId == syncOwner else { return }
                habitLoop.legacyXP = value.legacyXP
                habitLoop.startedDay = value.startedDay
                habitLoop.merge(value.events)
                acceptForegroundFocusSync()
                FocusModeController.shared.message = nil
                reconcileHabitLoop(celebrate: !wasComplete && streakProtectedToday)
                saveLocalData()
            } catch {
                FocusModeController.shared.message = "Learning sync is unavailable. Your local progress is safe. Reopen PodTrackio online to unlock with another device’s learning."
            }
            async let remotePodcasts = SupabaseClient.shared.fetchPodcasts()
            async let remoteStats = SupabaseClient.shared.fetchStats()
            async let remoteCategories = SupabaseClient.shared.fetchCategories()
            async let remoteActivities = SupabaseClient.shared.fetchActivities()
            async let remoteSummaries = SupabaseClient.shared.fetchSummaries()
            async let remoteCollections = SupabaseClient.shared.fetchCollections()
            let result = try await (remotePodcasts, remoteStats, remoteCategories, remoteActivities, remoteSummaries, remoteCollections)

            guard AuthManager.shared.userId == syncOwner else { return }
            podcasts = mergePodcasts(local: podcasts, remote: result.0)
            if let value = result.1 {
                let local = stats
                stats = value
                stats.totalXP = max(local.totalXP, value.totalXP)
                stats.longestStreak = max(local.longestStreak, value.longestStreak)
            }
            if !result.2.isEmpty { categories = mergeByUpdatedAt(local: categories, remote: result.2) }
            if !result.3.isEmpty { activities = mergeByID(local: activities, remote: result.3) }
            if !result.4.isEmpty { summaries = mergeSummaries(local: summaries, remote: result.4) }
            if !result.5.isEmpty { collections = mergeCollections(local: collections, remote: result.5) }
            reconcileHabitLoop(celebrate: false)
            seedMissingCategoriesAndRepairReferences()
            restoreAchievementUnlocks()
            saveLocalData()

            // If we have local podcasts/categories/stats that remote didn't have, persist them upstream
            if AuthManager.shared.isAuthenticated {
                try? await SupabaseClient.shared.upsertPodcasts(podcasts, categories: categories)
                try? await SupabaseClient.shared.upsertStats(stats)
                try? await SupabaseClient.shared.upsertCollections(collections)
            }
        } catch {
            print("Cloud sync unavailable; using the local learning workspace: \(error.localizedDescription)")
        }
    }

    func category(for id: String) -> LearningCategory? { categories.first { $0.id == id } }
    func collection(for id: UUID) -> PodcastCollection? { collections.first { $0.id == id } }
    func summary(for podcastID: UUID) -> PodcastSummary? { summaries.first { $0.podcastID == podcastID } }
    func activity(for date: Date) -> DailyLearningActivity? {
        let key = LearningCalendar.dateKey(for: date)
        return activities.first { $0.dateKey == key }
    }

    func scheduledPodcasts(on date: Date) -> [Podcast] {
        podcasts.filter { podcast in podcast.scheduledAt.map { Calendar.current.isDate($0, inSameDayAs: date) } == true }
            .sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
    }

    func addPodcast(title: String, url: String, categoryID: String) {
        guard let videoID = Podcast.extractVideoId(from: url), category(for: categoryID) != nil else { return }
        guard !podcasts.contains(where: { $0.youtubeVideoId == videoID }) else { return }
        podcasts.append(Podcast(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), url: url,
            youtubeVideoId: videoID,
            thumbnailURL: "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg",
            categoryID: categoryID
        ))
        stats.totalPodcastsAdded += 1
        checkAchievements()
        saveData()
        rescheduleNotifications()
    }

    func importPlaylist(_ preview: PlaylistPreview, categoryID: String) -> PlaylistImportResult {
        guard category(for: categoryID) != nil else {
            return .init(added: 0, reused: 0, skipped: preview.episodes.count + preview.unavailableCount)
        }
        let collection: PodcastCollection
        if let existing = collections.first(where: { $0.sourcePlaylistID == preview.playlistID }) {
            collection = existing
            if let index = collections.firstIndex(where: { $0.id == existing.id }) {
                collections[index].title = preview.title
                collections[index].sourceURL = preview.sourceURL
                let latest = preview.episodes.sorted(by: { $0.playlistIndex < $1.playlistIndex }).map(\.videoID)
                collections[index].videoIDs = latest + existing.videoIDs.filter { !latest.contains($0) }
            }
        } else {
            collection = PodcastCollection(
                title: preview.title,
                sourcePlaylistID: preview.playlistID,
                sourceURL: preview.sourceURL,
                sortOrder: collections.count,
                videoIDs: preview.episodes.sorted(by: { $0.playlistIndex < $1.playlistIndex }).map(\.videoID)
            )
            collections.append(collection)
        }

        var added = 0
        var reused = 0
        for episode in preview.episodes.sorted(by: { $0.playlistIndex < $1.playlistIndex }) {
            if let index = podcasts.firstIndex(where: { $0.youtubeVideoId == episode.videoID }) {
                if !podcasts[index].collectionIDs.contains(collection.id) {
                    podcasts[index].collectionIDs.append(collection.id)
                }
                reused += 1
            } else {
                podcasts.append(Podcast(
                    title: episode.title,
                    url: episode.url,
                    youtubeVideoId: episode.videoID,
                    thumbnailURL: episode.thumbnailURL,
                    collectionIDs: [collection.id],
                    categoryID: categoryID
                ))
                added += 1
            }
        }
        stats.totalPodcastsAdded += added
        checkAchievements()
        saveData()
        rescheduleNotifications()
        return .init(added: added, reused: reused, skipped: preview.unavailableCount)
    }

    func deleteCollection(_ collection: PodcastCollection) {
        collections.removeAll { $0.id == collection.id }
        for index in podcasts.indices { podcasts[index].collectionIDs.removeAll { $0 == collection.id } }
        if selectedCollectionID == collection.id { selectedCollectionID = nil }
        saveData()
        Task { try? await SupabaseClient.shared.deleteCollection(id: collection.id) }
    }

    func removePodcast(_ podcast: Podcast) {
        podcasts.removeAll { $0.id == podcast.id }
        summaries.removeAll { $0.podcastID == podcast.id }
        if selectedPodcast?.id == podcast.id { stopTracking(); selectedPodcast = nil }
        if !podcasts.contains(where: { $0.youtubeVideoId == podcast.youtubeVideoId }) {
            LocalMediaStore.shared.deleteDownload(videoID: podcast.youtubeVideoId)
        }
        saveData()
        Task { try? await SupabaseClient.shared.deletePodcast(id: podcast.id) }
    }

    func selectPodcast(_ podcast: Podcast) {
        playbackStartRequest = nil
        selectedPodcast = podcast
        inspectorPresented = true
    }

    func updateNotes(for podcastID: UUID, notes: String) {
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { habitLoop.reflect(on: LearningCalendar.dateKey(for: Date())) }
        guard let index = podcasts.firstIndex(where: { $0.id == podcastID }) else { return }
        let clean = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstNote = podcasts[index].notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !clean.isEmpty
        podcasts[index].notes = notes
        if firstNote {
            stats.totalNotesTaken += 1
            awardXP(10, activityDate: Date())
        }
        refreshSelectedPodcast()
        checkAchievements()
        saveData()
    }

    func markCompleted(_ podcast: Podcast) {
        guard let index = podcasts.firstIndex(where: { $0.id == podcast.id }), !podcasts[index].isCompleted else { return }
        let completedAt = Date()
        podcasts[index].isCompleted = true
        podcasts[index].completedAt = completedAt
        podcasts[index].scheduledAt = nil
        LocalMediaStore.shared.markCompleted(videoID: podcasts[index].youtubeVideoId, completedAt: completedAt)
        stats.podcastsCompleted += 1
        awardXP(20, activityDate: Date())
        mutateTodayActivity { $0.completedPodcastIDs.insert(podcast.id) }
        refreshSelectedPodcast()
        checkAchievements()
        saveData()
        rescheduleNotifications()
    }

    func schedulePodcast(_ podcast: Podcast, at date: Date) {
        guard let index = podcasts.firstIndex(where: { $0.id == podcast.id }) else { return }
        podcasts[index].scheduledAt = date
        refreshSelectedPodcast()
        saveData()
        rescheduleNotifications()
    }

    func removeSchedule(for podcast: Podcast) {
        guard let index = podcasts.firstIndex(where: { $0.id == podcast.id }) else { return }
        podcasts[index].scheduledAt = nil
        refreshSelectedPodcast()
        saveData()
        rescheduleNotifications()
    }

    func download(_ podcast: Podcast) async throws -> URL {
        try await LocalMediaStore.shared.download(videoID: podcast.youtubeVideoId, completedAt: podcast.completedAt)
    }

    func cancelDownload(_ podcast: Podcast) {
        LocalMediaStore.shared.cancel(videoID: podcast.youtubeVideoId)
    }

    func deleteDownload(_ podcast: Podcast) {
        LocalMediaStore.shared.deleteDownload(videoID: podcast.youtubeVideoId)
    }

    /// Arms a deliberate learning block. Time starts only after the embedded player reports playback.
    func prepareCommitment(
        for podcast: Podcast,
        minutes: Int,
        cue: DistractionCue,
        launchIntent: CommitmentLaunchIntent
    ) {
        guard minutes > 0 else { return }
        if isTracking, selectedPodcast?.id != podcast.id { stopTracking() }
        for index in focusCommitments.indices where focusCommitments[index].isActive {
            focusCommitments[index].cancel()
        }
        focusCommitments.append(FocusCommitment(
            podcastID: podcast.id,
            cue: cue,
            targetSeconds: Double(minutes * 60)
        ))
        completedCommitment = nil
        selectPodcast(podcast)
        if launchIntent.requestsPlaybackStart {
            playbackStartRequest = PlaybackStartRequest(podcastID: podcast.id)
        }
        showRescueSheet = false
        saveLocalData()
        rescheduleNotifications()
    }

    func prepareRescue(cue: DistractionCue, minutes: Int) {
        guard let podcast = nextPodcast else { return }
        prepareCommitment(
            for: podcast,
            minutes: minutes,
            cue: cue,
            launchIntent: .explicitUserAction
        )
    }

    func cancelActiveCommitment() {
        guard let id = activeCommitment?.id,
              let index = focusCommitments.firstIndex(where: { $0.id == id }) else { return }
        focusCommitments[index].cancel()
        saveLocalData()
        rescheduleNotifications()
    }

    func consumePlaybackStartRequest(for podcastID: UUID) -> Bool {
        guard playbackStartRequest?.targets(podcastID) == true else { return false }
        playbackStartRequest = nil
        return true
    }

    func extendCommitment(by minutes: Int) {
        guard let podcast = selectedPodcast else { return }
        prepareCommitment(for: podcast, minutes: minutes, cue: .momentum, launchIntent: .alreadyPlaying)
    }

    func dismissCompletedCommitment() { completedCommitment = nil }

    func handlePlaybackState(podcast: Podcast, isPlaying: Bool) {
        if isPlaying {
            if isTracking, selectedPodcast?.id != podcast.id { stopTracking() }
            if !isTracking { startTracking(podcast: podcast) }
        } else if isTracking, selectedPodcast?.id == podcast.id {
            stopTracking()
        }
    }

    private func startTracking(podcast: Podcast) {
        guard !isTracking else { return }
        selectedPodcast = podcasts.first(where: { $0.id == podcast.id }) ?? podcast
        PlayMoments.shared.trackingStarted(xp: stats.totalXP)
        isTracking = true
        currentSessionSeconds = 0
        stats.sessionsCount += 1
        stats.resetDailyIfNeeded()
        stats.resetWeeklyIfNeeded()
        mutateTodayActivity { $0.sessions += 1 }
        playbackCredit.begin(position: podcast.lastPlaybackPosition)
    }

    func stopTracking() {
        guard isTracking else { return }
        isTracking = false
        playbackCredit.reset()
        reconcileHabitLoop()
        PlayMoments.shared.trackingStopped(seconds: currentSessionSeconds)
        stats.longestSessionSeconds = max(stats.longestSessionSeconds, currentSessionSeconds)
        currentSessionSeconds = 0
        FocusModeController.shared.checkpoint()
        recomputeStreak()
        checkAchievements()
        saveData()
        rescheduleNotifications()
    }

    private func tickTracking(seconds: Double) {
        stats.resetDailyIfNeeded()
        stats.resetWeeklyIfNeeded()
        currentSessionSeconds += seconds
        stats.totalSecondsWatched += seconds
        stats.dailySecondsWatched += seconds
        stats.weeklySecondsWatched += seconds
        let now = Date()
        let key = LearningCalendar.dateKey(for: now)
        prepareDailyLearningGoal()
        let wasProtected = streakProtectedToday
        let blocksBefore = Int(habitLoop.localSeconds(on: key) / 300)
        habitLoop.record(seconds: seconds, day: key, goalMinutes: habitSettings.currentDailyGoalMinutes)
        FocusModeController.shared.updateGoal(target: habitSettings.currentDailyGoalMinutes * 60,
            localSeconds: habitLoop.localSeconds(on: key), owner: habitLoop.ownerID)
        if let index = podcasts.firstIndex(where: { $0.id == selectedPodcast?.id }) {
            podcasts[index].totalWatchedSeconds += seconds
            podcasts[index].lastWatchedDate = now
            selectedPodcast = podcasts[index]
        }
        if let podcastID = selectedPodcast?.id,
           let index = focusCommitments.lastIndex(where: { $0.podcastID == podcastID && $0.isActive }),
           focusCommitments[index].recordWatched(seconds: seconds, now: now) {
            completedCommitment = focusCommitments[index]
        }
        mutateTodayActivity { activity in
            activity.watchedSeconds += seconds
            activity.goalMinutes = habitSettings.currentDailyGoalMinutes
            _ = ProgressionEngine.awardNewTrackedMinutes(activity: &activity)
            if !activity.goalCompleted && activity.watchedSeconds >= activity.goalMinutes * 60 {
                activity.goalCompleted = true
                if !activity.dailyGoalXPAwarded {
                    activity.dailyGoalXPAwarded = true
                    habitLoop.insert(.init(id: "daily-goal/\(key)", day: key, kind: "xp", value: 25))
                }
            }
        }
        checkpointSeconds += seconds
        if checkpointSeconds >= 15 || (!wasProtected && streakProtectedToday)
            || FocusModeController.shared.justUnlocked || Int(habitLoop.localSeconds(on: key) / 300) > blocksBefore {
            checkpointSeconds = 0
            reconcileHabitLoop()
            saveLocalData()
            rescheduleNotifications()
            if !wasProtected && streakProtectedToday { saveData() }
        }
        awardWeeklyGoalIfNeeded()
    }

    func resetPlaybackCredit() { playbackCredit.reset() }

    func updatePlaybackPosition(for podcastID: UUID, position: Double) {
        guard position.isFinite, position >= 0,
              let index = podcasts.firstIndex(where: { $0.id == podcastID }) else { return }
        let seconds = playbackCredit.sample(position: position, playing: isTracking && selectedPodcast?.id == podcastID)
        if seconds > 0 { tickTracking(seconds: seconds) }
        podcasts[index].lastPlaybackPosition = position
        let now = Date()
        if seconds > 0 { podcasts[index].lastWatchedDate = now }
        dataManager.savePodcasts(podcasts)
        scheduleProgressSync(for: podcasts[index])
        refreshSelectedPodcast()
    }

    func updateDuration(for podcastID: UUID, duration: Double) {
        guard let index = podcasts.firstIndex(where: { $0.id == podcastID }) else { return }
        podcasts[index].duration = duration
        refreshSelectedPodcast()
    }

    func setDailyGoal(_ minutes: Double) {
        guard minutes.isFinite, (5...240).contains(minutes) else { return }
        // Today's dated target stays fixed; preference edits apply on the next learning day.
        prepareDailyLearningGoal()
        saveData()
        rescheduleNotifications()
    }

    func setWeeklyGoal(_ hours: Double) { stats.weeklyGoalHours = hours; saveData() }

    func createCategory(name: String, symbolName: String, colorToken: String) throws {
        let value = try CategoryOperations.validatedName(name, in: categories)
        categories.append(.init(name: value, symbolName: symbolName, colorToken: colorToken, sortOrder: categories.count))
        saveData()
    }

    func updateCategory(_ category: LearningCategory) throws {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { throw CategoryValidationError.categoryNotFound }
        var updated = category
        updated.name = try CategoryOperations.validatedName(category.name, excluding: category.id, in: categories)
        updated.createdAt = categories[index].createdAt
        updated.updatedAt = Date()
        categories[index] = updated
        saveData()
    }

    func moveCategories(from offsets: IndexSet, to destination: Int) {
        categories.move(fromOffsets: offsets, toOffset: destination)
        for index in categories.indices { categories[index].sortOrder = index; categories[index].updatedAt = Date() }
        saveData()
    }

    func deleteCategory(id: String, replacementID: String?) throws {
        try CategoryOperations.delete(categoryID: id, replacementID: replacementID, categories: &categories, podcasts: &podcasts)
        saveData()
        Task { try? await SupabaseClient.shared.reassignAndDeleteCategory(id: id, replacementID: replacementID) }
    }

    func storeSummary(_ summary: PodcastSummary) {
        if let index = summaries.firstIndex(where: { $0.podcastID == summary.podcastID }) { summaries[index] = summary }
        else { summaries.append(summary) }
        unlockAchievement("first_summary")
        saveData()
    }

    func toggleAction(podcastID: UUID, actionID: UUID) {
        habitLoop.reflect(on: LearningCalendar.dateKey(for: Date()))
        guard let summaryIndex = summaries.firstIndex(where: { $0.podcastID == podcastID }),
              let actionIndex = summaries[summaryIndex].actionPlan.firstIndex(where: { $0.id == actionID }) else { return }
        summaries[summaryIndex].actionPlan[actionIndex].isCompleted.toggle()
        let complete = !summaries[summaryIndex].actionPlan.isEmpty && summaries[summaryIndex].actionPlan.allSatisfy(\.isCompleted)
        if complete && !summaries[summaryIndex].actionPlanXPGranted {
            summaries[summaryIndex].actionPlanXPGranted = true
            awardXP(15, activityDate: Date())
            unlockAchievement("first_action_plan")
        }
        saveData()
    }

    func askTranscriptQuestion(for podcast: Podcast, question: String, history: [(role: String, content: String)], model: QuirkyModel, answerStyle: QuirkyAnswerStyle) async throws -> String {
        guard let key = KeychainStore.groqAPIKey() else { throw GroqError.missingKey }
        guard let document = DataManager.shared.loadTranscript(for: podcast.id), !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GroqError.server("Generate the summary first so PodTrackio has a transcript to chat about.")
        }
        let context = document.segments.isEmpty ? document.text : document.segments.map {
            let total = Int($0.startSeconds); let stamp = String(format: "%d:%02d", total / 60, total % 60)
            return "[\(stamp)] \($0.text)"
        }.joined(separator: "\n")
        return try await GroqClient.shared.chat(transcript: context, title: podcast.title, question: question, history: history, model: model, answerStyle: answerStyle, apiKey: key)
    }

    func quirkyMessages(for podcastID: UUID) -> [QuirkyChatMessage] { quirkyConversations[podcastID] ?? [] }

    func appendQuirkyMessage(_ message: QuirkyChatMessage, podcastID: UUID) {
        quirkyConversations[podcastID, default: []].append(message)
        dataManager.saveQuirkyConversations(quirkyConversations)
    }

    func clearQuirkyConversation(for podcastID: UUID) {
        quirkyConversations[podcastID] = []
        dataManager.saveQuirkyConversations(quirkyConversations)
    }

    func generateSummary(for podcast: Podcast, transcript: TranscriptDocument? = nil, allowAudioTranscription: Bool = false) {
        guard summaryState.isIdle else { return }
        Task { [self] in
            do {
                let summary = try await SummaryCoordinator.shared.generate(
                    for: podcast, importedTranscript: transcript, allowAudioTranscription: allowAudioTranscription,
                    progress: { [weak self] state in Task { @MainActor in self?.summaryState = state } }
                )
                storeSummary(summary)
                summaryState = .completed
            } catch SummaryPipelineError.audioConsentRequired {
                summaryState = .needsAudioConsent
            } catch SummaryPipelineError.transcriptImportRequired(let reason) {
                summaryState = .needsTranscriptImport(reason)
            } catch is CancellationError {
                summaryState = .failed("Summary generation was cancelled. Your existing summary is unchanged.")
            } catch {
                summaryState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelSummaryGeneration() { SummaryCoordinator.shared.cancel(); summaryState = .idle }

    func rescheduleNotifications() {
        let plan = NotificationPlanner.plan(
            now: Date(), preferences: notificationPreferences, activities: activities,
            currentGoalMinutes: habitSettings.currentDailyGoalMinutes,
            nextPodcast: nextPodcast, isPlaying: isTracking,
            distractionCue: preferredDistractionCue,
            distractionPattern: learnedDistractionPattern,
            habitLoop: habitLoop, focus: FocusModeController.shared.state,
            lastSession: podcasts.compactMap(\.lastWatchedDate).max()
        )
        for item in plan {
            if let index = habitLoop.reminderHistory.firstIndex(where: { $0.id == item.id }) {
                if habitLoop.reminderHistory[index].fireTime > Date() { habitLoop.reminderHistory[index].fireTime = item.fireDate; habitLoop.reminderHistory[index].baselineSeconds = habitLoop.learnedSeconds(on: item.id.components(separatedBy: ".")[1]) }
            } else {
                habitLoop.reminderHistory.append(.init(id: item.id, day: LearningCalendar.dateKey(for: item.fireDate), template: item.template,
                    fireTime: item.fireDate, baselineSeconds: habitLoop.learnedSeconds(on: LearningCalendar.dateKey(for: item.fireDate))))
            }
        }
        habitLoop.reminderHistory = Array(habitLoop.reminderHistory.sorted { $0.fireTime > $1.fireTime }.prefix(180))
        dataManager.saveHabitLoop(habitLoop)
        let scheduled = podcasts.compactMap { podcast -> ScheduledPodcastNotification? in
            guard let date = podcast.scheduledAt, date > Date(), !podcast.isCompleted else { return nil }
            return .init(podcastID: podcast.id, title: podcast.title, fireDate: date)
        }
        Task {
            await NotificationManager.shared.replaceLearningReminders(with: plan)
            await NotificationManager.shared.replaceScheduledPodcastReminders(with: scheduled)
        }
    }

    private func mutateTodayActivity(_ mutation: (inout DailyLearningActivity) -> Void) {
        let key = LearningCalendar.dateKey(for: Date())
        if let index = activities.firstIndex(where: { $0.dateKey == key }) {
            mutation(&activities[index])
        } else {
            var activity = DailyLearningActivity(dateKey: key, goalMinutes: habitSettings.currentDailyGoalMinutes)
            mutation(&activity)
            activities.append(activity)
        }
    }

    private func awardXP(_ amount: Int, activityDate: Date) {
        let key = LearningCalendar.dateKey(for: activityDate)
        let id = amount == 100 ? "weekly-goal/\(LearningCalendar.weekKey(for: activityDate))" : "activity/\(UUID().uuidString)"
        habitLoop.insert(.init(id: id, day: key, kind: "xp", value: Double(amount)))
        stats.totalXP = habitLoop.legacyXP + habitLoop.rewardXP
        if let index = activities.firstIndex(where: { $0.dateKey == key }) { activities[index].xpEarned += amount }
        else { activities.append(.init(dateKey: key, goalMinutes: habitSettings.currentDailyGoalMinutes, xpEarned: amount)) }
        presentLevelToastIfNeeded()
    }

    private func awardWeeklyGoalIfNeeded() {
        guard stats.weeklyGoalProgress >= 1 else { return }
        let week = LearningCalendar.weekKey(for: Date())
        guard habitSettings.lastWeeklyGoalAwardKey != week else { return }
        habitSettings.lastWeeklyGoalAwardKey = week
        mutateTodayActivity { $0.weeklyGoalXPAwarded = true }
        awardXP(100, activityDate: Date())
    }

    private func presentLevelToastIfNeeded() {
        let level = stats.currentLevel.number
        if level > previousLevel { previousLevel = level; showLevelUpAlert = true }
    }

    private func recomputeStreak() {
        let status = habitLoop.streak(activities: activities)
        stats.currentStreak = status.count
        stats.longestStreak = max(stats.longestStreak, status.count)
        if streakProtectedToday { stats.lastActiveDate = Date() }
    }

    func checkAchievements() {
        let checks: [String: Bool] = [
            "first_listen": stats.totalSecondsWatched > 0, "one_hour": stats.totalHoursWatched >= 1,
            "five_hours": stats.totalHoursWatched >= 5, "ten_hours": stats.totalHoursWatched >= 10,
            "twentyfive_hours": stats.totalHoursWatched >= 25, "fifty_hours": stats.totalHoursWatched >= 50,
            "hundred_hours": stats.totalHoursWatched >= 100, "streak_3": stats.longestStreak >= 3,
            "streak_7": stats.longestStreak >= 7, "streak_14": stats.longestStreak >= 14,
            "streak_30": stats.longestStreak >= 30, "streak_100": stats.longestStreak >= 100,
            "first_note": stats.totalNotesTaken >= 1, "ten_notes": stats.totalNotesTaken >= 10,
            "twentyfive_notes": stats.totalNotesTaken >= 25, "five_podcasts": stats.totalPodcastsAdded >= 5,
            "ten_podcasts": stats.totalPodcastsAdded >= 10, "twentyfive_podcasts": stats.totalPodcastsAdded >= 25,
            "three_categories": categoriesUsed.count >= 3, "six_categories": categoriesUsed.count >= 6,
            "complete_first": stats.podcastsCompleted >= 1, "complete_five": stats.podcastsCompleted >= 5,
            "complete_ten": stats.podcastsCompleted >= 10, "weekly_goal": stats.weeklyGoalProgress >= 1,
            "daily_goal_7": stats.currentStreak >= 7, "level_5": stats.currentLevel.number >= 5,
            "level_10": stats.currentLevel.number >= 10
        ]
        for (id, shouldUnlock) in checks where shouldUnlock { unlockAchievement(id) }
    }

    private func unlockAchievement(_ id: String) {
        guard let index = achievements.firstIndex(where: { $0.id == id }), !achievements[index].isUnlocked else { return }
        achievements[index].isUnlocked = true
        achievements[index].unlockedDate = Date()
        if !stats.unlockedAchievementIds.contains(id) { stats.unlockedAchievementIds.append(id) }
        newlyUnlockedAchievement = achievements[index]
        showAchievementPopup = true
    }

    private func restoreAchievementUnlocks() {
        let ids = Set(stats.unlockedAchievementIds)
        for index in achievements.indices where ids.contains(achievements[index].id) { achievements[index].isUnlocked = true }
    }

    private func seedMissingCategoriesAndRepairReferences() {
        if categories.isEmpty { categories = LearningCategory.defaults }
        let IDs = Set(categories.map(\.id))
        if !IDs.contains(LearningCategory.generalID), let general = LearningCategory.defaults.first { categories.append(general) }
        let valid = Set(categories.map(\.id))
        for index in podcasts.indices where !valid.contains(podcasts[index].categoryID) { podcasts[index].categoryID = LearningCategory.generalID }
    }

    private func refreshSelectedPodcast() {
        guard let id = selectedPodcast?.id else { return }
        selectedPodcast = podcasts.first { $0.id == id }
    }

    private func mergeByUpdatedAt(local: [LearningCategory], remote: [LearningCategory]) -> [LearningCategory] {
        var values = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for item in remote where item.updatedAt > (values[item.id]?.updatedAt ?? .distantPast) { values[item.id] = item }
        return values.values.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func mergeByID(local: [DailyLearningActivity], remote: [DailyLearningActivity]) -> [DailyLearningActivity] {
        var values = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for item in remote {
            guard var local = values[item.id] else { values[item.id] = item; continue }
            local.watchedSeconds = max(local.watchedSeconds, item.watchedSeconds)
            local.sessions = max(local.sessions, item.sessions)
            local.goalCompleted = local.goalCompleted || item.goalCompleted
            local.xpEarned = max(local.xpEarned, item.xpEarned)
            local.xpAwardedMinutes = max(local.xpAwardedMinutes, item.xpAwardedMinutes)
            local.completedPodcastIDs.formUnion(item.completedPodcastIDs)
            local.dailyGoalXPAwarded = local.dailyGoalXPAwarded || item.dailyGoalXPAwarded
            local.weeklyGoalXPAwarded = local.weeklyGoalXPAwarded || item.weeklyGoalXPAwarded
            values[item.id] = local
        }
        return values.values.sorted { $0.dateKey < $1.dateKey }
    }

    private func mergeSummaries(local: [PodcastSummary], remote: [PodcastSummary]) -> [PodcastSummary] {
        var values = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for item in remote where item.generatedAt > (values[item.id]?.generatedAt ?? .distantPast) { values[item.id] = item }
        return Array(values.values)
    }

    private func mergeCollections(local: [PodcastCollection], remote: [PodcastCollection]) -> [PodcastCollection] {
        var values = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for item in remote { values[item.id] = item }
        return values.values.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func mergePodcasts(local: [Podcast], remote: [Podcast]) -> [Podcast] {
        var values = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for remotePodcast in remote {
            if let localPodcast = values[remotePodcast.id] {
                values[remotePodcast.id] = Podcast.mergedForSync(local: localPodcast, remote: remotePodcast)
            } else {
                values[remotePodcast.id] = remotePodcast
            }
        }
        return values.values.sorted { $0.dateAdded > $1.dateAdded }
    }

    private func scheduleProgressSync(for podcast: Podcast) {
        progressSyncTasks[podcast.id]?.cancel()
        let categoriesSnapshot = categories
        progressSyncTasks[podcast.id] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, AuthManager.shared.isAuthenticated else { return }
                try await SupabaseClient.shared.upsertPodcasts([podcast], categories: categoriesSnapshot)
            } catch is CancellationError {
                return
            } catch {
                print("Progress sync deferred: \(error.localizedDescription)")
            }
            await MainActor.run { self?.progressSyncTasks[podcast.id] = nil }
        }
    }

    private func startAutoSave() {
        saveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.saveData() }
        }
    }

    private func startDownloadCleanup() {
        downloadCleanupTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in
            Task { @MainActor in LocalMediaStore.shared.cleanupExpired() }
        }
    }

    private func setupAuthObserver() {
        AuthManager.shared.$isAuthenticated.dropFirst().receive(on: RunLoop.main).sink { [weak self] authenticated in
            guard let self else { return }
            if authenticated { self.loadData() }
            else {
                self.stopTracking()
                self.habitLoop = self.dataManager.loadHabitLoop() ?? HabitLoop()
                self.stats.totalXP = self.habitLoop.legacyXP + self.habitLoop.rewardXP
                self.selectedPodcast = nil; self.selectedSection = .today
            }
        }.store(in: &cancellables)
    }

    private func setupNotificationRoutes() {
        NotificationCenter.default.publisher(for: .openPodcastFromNotification).sink { [weak self] note in
            guard let id = note.object as? UUID else { return }
            Task { @MainActor in if let podcast = self?.podcasts.first(where: { $0.id == id }) { self?.selectPodcast(podcast) } }
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .startFiveMinutesFromNotification).sink { [weak self] note in
            guard let id = note.object as? UUID else { return }
            Task { @MainActor in
                if let podcast = self?.podcasts.first(where: { $0.id == id }) {
                    self?.prepareCommitment(
                        for: podcast,
                        minutes: 5,
                        cue: .notification,
                        launchIntent: .notificationDeepLink
                    )
                }
            }
        }.store(in: &cancellables)
    }

    isolated deinit {
        saveTimer?.invalidate()
        downloadCleanupTimer?.invalidate()
        progressSyncTasks.values.forEach { $0.cancel() }
    }
}

extension SummaryGenerationState {
    var isIdle: Bool {
        switch self { case .idle, .completed, .failed: true; default: false }
    }
}
