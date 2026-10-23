import Foundation

struct PodTrackioWidgetSnapshot: Codable, Equatable, Sendable {
    static let empty = PodTrackioWidgetSnapshot(
        todayWatchedMinutes: 0,
        dailyGoalMinutes: 30,
        currentStreak: 0,
        totalXP: 0,
        levelTitle: "Newcomer",
        libraryCount: 0,
        completedCount: 0,
        nextEpisodeID: nil,
        nextEpisodeTitle: nil,
        nextEpisodeProgress: 0
    )

    let todayWatchedMinutes: Int
    let dailyGoalMinutes: Int
    let currentStreak: Int
    let totalXP: Int
    let levelTitle: String
    let libraryCount: Int
    let completedCount: Int
    let nextEpisodeID: UUID?
    let nextEpisodeTitle: String?
    let nextEpisodeProgress: Double
    var snapshotDay: String = ""
    var streakProtected: Bool = false
    var focusBlocksRemaining: Int? = nil
    var focusTargetBlocks: Int? = nil
    var focusMinutesRemaining: Int? = nil
    var focusTargetMinutes: Int? = nil
    var gems: Int = 0
    /// Monday-first week: done, frozen, missed, today, todayDone, future.
    var weekStates: [String] = []
    var freezes: Int = 2
    var questsDone: Int = 0
    var levelNumber: Int = 1
    var levelProgress: Double = 0
    var nextEpisodeResumeLabel: String? = nil
    var hasThumbnail: Bool = false

    private var todayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var currentWatchedMinutes: Int { snapshotDay == todayKey ? todayWatchedMinutes : 0 }

    var currentFocusBlocksRemaining: Int? { snapshotDay == todayKey ? focusBlocksRemaining : focusTargetBlocks }

    var currentFocusMinutesRemaining: Int? { snapshotDay == todayKey ? focusMinutesRemaining : focusTargetMinutes }

    var protectedToday: Bool {
        streakProtected && snapshotDay == todayKey
    }

    var dailyProgress: Double {
        min(max(Double(currentWatchedMinutes) / Double(max(dailyGoalMinutes, 1)), 0), 1)
    }

    var remainingMinutes: Int { max(0, dailyGoalMinutes - currentWatchedMinutes) }

    var currentQuestsDone: Int { snapshotDay == todayKey ? questsDone : 0 }

    /// After 6pm with a live, unprotected streak. Evaluated per timeline entry, so the widget turns worried on its own.
    func atRisk(at date: Date) -> Bool {
        !protectedToday && currentStreak > 0 && Calendar.current.component(.hour, from: date) >= 18
    }

    /// Week states shifted correctly even if the snapshot is from an earlier day this week.
    var currentWeekStates: [String] {
        guard weekStates.count == 7 else { return Array(repeating: "future", count: 7) }
        guard snapshotDay != todayKey else { return weekStates }
        let todayIndex = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        return weekStates.enumerated().map { index, state in
            if index == todayIndex { return "today" }
            if state == "today" { return index < todayIndex ? "missed" : "future" }
            if state == "todayDone" { return "done" }
            return state
        }
    }
}

extension PodTrackioWidgetSnapshot {
    enum CodingKeys: String, CodingKey {
        case todayWatchedMinutes, dailyGoalMinutes, currentStreak, totalXP, levelTitle, libraryCount, completedCount
        case nextEpisodeID, nextEpisodeTitle, nextEpisodeProgress, snapshotDay, streakProtected, focusBlocksRemaining, focusTargetBlocks, focusMinutesRemaining, focusTargetMinutes, gems
        case weekStates, freezes, questsDone, levelNumber, levelProgress, nextEpisodeResumeLabel, hasThumbnail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(todayWatchedMinutes: try c.decode(Int.self, forKey: .todayWatchedMinutes),
            dailyGoalMinutes: try c.decode(Int.self, forKey: .dailyGoalMinutes), currentStreak: try c.decode(Int.self, forKey: .currentStreak),
            totalXP: try c.decode(Int.self, forKey: .totalXP), levelTitle: try c.decode(String.self, forKey: .levelTitle),
            libraryCount: try c.decode(Int.self, forKey: .libraryCount), completedCount: try c.decode(Int.self, forKey: .completedCount),
            nextEpisodeID: try c.decodeIfPresent(UUID.self, forKey: .nextEpisodeID), nextEpisodeTitle: try c.decodeIfPresent(String.self, forKey: .nextEpisodeTitle),
            nextEpisodeProgress: try c.decode(Double.self, forKey: .nextEpisodeProgress), snapshotDay: try c.decodeIfPresent(String.self, forKey: .snapshotDay) ?? "",
            streakProtected: try c.decodeIfPresent(Bool.self, forKey: .streakProtected) ?? false,
            focusBlocksRemaining: try c.decodeIfPresent(Int.self, forKey: .focusBlocksRemaining), focusTargetBlocks: try c.decodeIfPresent(Int.self, forKey: .focusTargetBlocks),
            focusMinutesRemaining: try c.decodeIfPresent(Int.self, forKey: .focusMinutesRemaining),
            focusTargetMinutes: try c.decodeIfPresent(Int.self, forKey: .focusTargetMinutes),
            gems: try c.decodeIfPresent(Int.self, forKey: .gems) ?? 0,
            weekStates: try c.decodeIfPresent([String].self, forKey: .weekStates) ?? [],
            freezes: try c.decodeIfPresent(Int.self, forKey: .freezes) ?? 2,
            questsDone: try c.decodeIfPresent(Int.self, forKey: .questsDone) ?? 0,
            levelNumber: try c.decodeIfPresent(Int.self, forKey: .levelNumber) ?? 1,
            levelProgress: try c.decodeIfPresent(Double.self, forKey: .levelProgress) ?? 0,
            nextEpisodeResumeLabel: try c.decodeIfPresent(String.self, forKey: .nextEpisodeResumeLabel),
            hasThumbnail: try c.decodeIfPresent(Bool.self, forKey: .hasThumbnail) ?? false)
    }
}

enum PodTrackioWidgetSnapshotStore {
    static let appGroupID = "group.com.tangenix.podtrackio"
    private static let snapshotKey = "podtrackio.widget.snapshot.v1"

    /// The next episode's thumbnail, cached by the app so widgets can show it without network access.
    static var thumbnailURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?.appendingPathComponent("widget-next-thumbnail.jpg")
    }

    static func load() -> PodTrackioWidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(PodTrackioWidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    @discardableResult
    static func save(_ snapshot: PodTrackioWidgetSnapshot) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(snapshot) else { return false }
        if defaults.data(forKey: snapshotKey) == data { return false }
        defaults.set(data, forKey: snapshotKey)
        return true
    }
}
