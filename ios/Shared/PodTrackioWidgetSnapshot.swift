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

    var dailyProgress: Double {
        min(max(Double(todayWatchedMinutes) / Double(max(dailyGoalMinutes, 1)), 0), 1)
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
