import Foundation

struct FocusDayState: Codable, Equatable, Sendable {
    var enabled = false
    var blocks = 3 // Legacy snapshot compatibility.
    var day = LearningCalendar.dateKey(for: Date())
    var creditedSeconds: Double = 0
    var selectedBundleIDs: [String] = []
    var selectedNames: [String] = []
    var targetSeconds: Double? = nil
    var remoteSeconds: Double? = nil
    var ownerID: String? = nil

    var dailyTargetSeconds: Double { targetSeconds ?? Double(blocks * 300) }
    func remainingSeconds(on date: Date = Date()) -> Double {
        max(0, dailyTargetSeconds - (day == LearningCalendar.dateKey(for: date) ? creditedSeconds : 0))
    }
    var isLocked: Bool { enabled && remainingSeconds() > 0 }
    var remainingMinutes: Int { Int(ceil(remainingSeconds() / 60)) }

    /// Remote credit is admitted only by a foreground sync. Playback can then add local credit offline.
    mutating func updateGoal(target: Double, localSeconds: Double, sharedSeconds: Double? = nil, owner: String?, now: Date = Date()) {
        guard target.isFinite, (300...14400).contains(target), localSeconds.isFinite, localSeconds >= 0,
              ownerID == nil || ownerID == owner else { return }
        let key = LearningCalendar.dateKey(for: now)
        if day != key { day = key; creditedSeconds = 0; remoteSeconds = 0 }
        ownerID = owner
        targetSeconds = target
        if let sharedSeconds, sharedSeconds.isFinite, sharedSeconds >= localSeconds {
            remoteSeconds = max(remoteSeconds ?? 0, sharedSeconds - localSeconds)
        }
        creditedSeconds = min(86400, localSeconds + (remoteSeconds ?? 0))
    }

    mutating func configure(enabled: Bool) -> Bool {
        guard !isLocked else { return false }
        self.enabled = enabled
        return true
    }
}
