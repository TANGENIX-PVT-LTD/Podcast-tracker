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
}

extension PodTrackioWidgetSnapshot {
    enum CodingKeys: String, CodingKey {
        case todayWatchedMinutes, dailyGoalMinutes, currentStreak, totalXP, levelTitle, libraryCount, completedCount
        case nextEpisodeID, nextEpisodeTitle, nextEpisodeProgress, snapshotDay, streakProtected, focusBlocksRemaining, focusTargetBlocks, focusMinutesRemaining, focusTargetMinutes, gems
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
            gems: try c.decodeIfPresent(Int.self, forKey: .gems) ?? 0)
    }
}

enum PodTrackioWidgetSnapshotStore {
    static let appGroupID = "group.com.tangenix.podtrackio"
    private static let snapshotKey = "podtrackio.widget.snapshot.v1"

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
