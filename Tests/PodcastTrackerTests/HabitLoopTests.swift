import Foundation
import Testing
@testable import PodcastTracker

@Suite("Habit loop and strict focus")
struct HabitLoopTests {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func date(_ key: String) -> Date { LearningCalendar.date(from: key, calendar: calendar)! }
    private func play(_ seconds: Int, loop: inout HabitLoop, day: String = "2026-10-22") {
        for _ in 0..<(seconds / 10) { loop.record(seconds: 10, day: day, goalMinutes: 15) }
    }

    @Test func countsElapsedTimeRatherThanSeekingOrPlaybackSpeed() {
        var tracker = PlaybackCreditTracker()
        #expect(tracker.sample(position: 10, playing: true, uptime: 100) == 0)
        #expect(tracker.sample(position: 14, playing: true, uptime: 101) == 1)
        #expect(tracker.sample(position: 14, playing: true, uptime: 102) == 0)
        #expect(tracker.sample(position: 90, playing: true, uptime: 103) == 0)
        #expect(tracker.sample(position: 91, playing: false, uptime: 104) == 0)
        #expect(tracker.sample(position: 92, playing: true, uptime: 130) == 0)
        tracker.reset()
        #expect(tracker.sample(position: 400, playing: true, uptime: 131) == 0)
    }

    @Test func seededPlaybackCreditsTheFirstElapsedSecond() {
        var tracker = PlaybackCreditTracker()
        tracker.begin(position: 0, uptime: 10)
        #expect(tracker.sample(position: 0.5, playing: true, uptime: 11) == 1)
    }

    @Test func lateSyncCorrectsLeagueAndInactiveWeeksDemote() {
        var loop = HabitLoop(); loop.startedDay = "2026-10-12"
        _ = loop.reconcile(activities: [], goalMinutes: 15, now: date("2026-10-12"), calendar: calendar)
        _ = loop.reconcile(activities: [], goalMinutes: 15, now: date("2026-10-19"), calendar: calendar)
        #expect(loop.league(activities: [], now: date("2026-10-19"), calendar: calendar).tier == 0)
        let history = (12...16).map { DailyLearningActivity(dateKey: "2026-10-\($0)", watchedSeconds: 900, goalMinutes: 15) }
        _ = loop.reconcile(activities: history, goalMinutes: 60, now: date("2026-10-19"), calendar: calendar)
        let promoted = loop.league(activities: history, now: date("2026-10-19"), calendar: calendar)
        #expect(promoted.tier == 1)
        #expect(promoted.targetMinutes == 75) // The existing target stays frozen after goal changes.
        _ = loop.reconcile(activities: history, goalMinutes: 15, now: date("2026-11-02"), calendar: calendar)
        #expect(loop.league(activities: history, now: date("2026-11-02"), calendar: calendar).tier == 0)
        #expect(loop.has("league-result/2026-10-26"))
    }

    @Test func sevenActualDaysRefillAFreezeAndPayOnePromise() {
        var loop = HabitLoop(); loop.startedDay = "2026-10-01"
        loop.insert(.init(id: "wager/2026-10-04", day: "2026-10-04", kind: "wager"))
        var history = [DailyLearningActivity(dateKey: "2026-10-01", watchedSeconds: 300, goalMinutes: 15)]
        history += (4...9).map { DailyLearningActivity(dateKey: String(format: "2026-10-%02d", $0), watchedSeconds: 300, goalMinutes: 15) }
        let before = loop.streak(activities: history, now: date("2026-10-10"), calendar: calendar)
        #expect(before.freezes == 1)
        _ = loop.reconcile(activities: history, goalMinutes: 15, now: date("2026-10-10"), calendar: calendar)
        #expect(!loop.has("wager-reward/2026-10-04"))
        history.append(.init(dateKey: "2026-10-10", watchedSeconds: 300, goalMinutes: 15))
        _ = loop.reconcile(activities: history, goalMinutes: 15, now: date("2026-10-10"), calendar: calendar)
        #expect(loop.gems == 40)
        _ = loop.reconcile(activities: history, goalMinutes: 15, now: date("2026-10-11"), calendar: calendar)
        #expect(loop.gems == 40)
    }

    @Test func focusAcceptsSharedCreditOnlyWhenExplicitlySynced() {
        var focus = FocusDayState()
        focus.updateGoal(target: 360, localSeconds: 60, owner: "owner")
        #expect({ focus.configure(enabled: true) }())
        #expect({ !focus.configure(enabled: false) }())
        var loop = HabitLoop()
        loop.merge([.init(id: "playback/mac/\(focus.day)", day: focus.day, kind: "playback", value: 360)])
        #expect(focus.isLocked) // A remote ledger merge alone cannot remove a shield.
        focus.updateGoal(target: 360, localSeconds: 60, sharedSeconds: 360, owner: "another-account")
        #expect(focus.isLocked)
        focus.updateGoal(target: 360, localSeconds: 60, sharedSeconds: 360, owner: "owner")
        #expect(!focus.isLocked)
        #expect({ focus.configure(enabled: false) }())
    }

    @Test func focusReblocksAtMidnightAndSupportsGoalsOverThirtyMinutes() {
        var focus = FocusDayState(); focus.enabled = true
        focus.updateGoal(target: 3600, localSeconds: 0, sharedSeconds: 3600, owner: "owner")
        #expect(!focus.isLocked)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        #expect(focus.remainingSeconds(on: tomorrow) == 3600)
        focus.updateGoal(target: 3600, localSeconds: 0, owner: "owner", now: tomorrow)
        #expect(focus.creditedSeconds == 0)
        focus.updateGoal(target: .infinity, localSeconds: 9000, owner: "owner", now: tomorrow)
        #expect(focus.creditedSeconds == 0)
    }

    @Test func adaptiveGoalsRepeatTwiceThenGrowAndMissesHold() {
        var loop = HabitLoop()
        #expect({ loop.prepareDailyGoal(day: "2026-10-20") == 5 }())
        loop.insert(.init(id: "playback/mac/2026-10-20", day: "2026-10-20", kind: "playback", value: 300))
        #expect({ loop.prepareDailyGoal(day: "2026-10-21") == 5 }())
        loop.insert(.init(id: "playback/phone/2026-10-21", day: "2026-10-21", kind: "playback", value: 300))
        #expect({ loop.prepareDailyGoal(day: "2026-10-22") == 6 }())
        #expect({ loop.prepareDailyGoal(day: "2026-10-25") == 6 }())
        loop.insert(.init(id: "playback/mac/2026-10-25", day: "2026-10-25", kind: "playback", value: 180))
        loop.insert(.init(id: "playback/phone/2026-10-25", day: "2026-10-25", kind: "playback", value: 120))
        let oldActivity = DailyLearningActivity(dateKey: "2026-10-25", watchedSeconds: 300, goalMinutes: 15)
        #expect(!loop.learningDays(activities: [oldActivity]).contains("2026-10-25"))
        loop.insert(.init(id: "playback/tablet/2026-10-25", day: "2026-10-25", kind: "playback", value: 60))
        #expect(loop.completedGoal(on: "2026-10-25"))
        #expect(loop.learningDays(activities: [oldActivity]).contains("2026-10-25"))
        #expect({ loop.prepareDailyGoal(day: "2026-10-25") == 6 }())
        #expect({ loop.prepareDailyGoal(day: "2026-10-26") == 6 }())
    }

    @Test func legacyFocusSnapshotsAndPastStreakDaysSurvive() throws {
        let data = Data(#"{"enabled":true,"blocks":2,"day":"2026-10-22","creditedSeconds":400,"selectedBundleIDs":[],"selectedNames":[]}"#.utf8)
        let restored = try JSONDecoder().decode(FocusDayState.self, from: data)
        #expect(restored.dailyTargetSeconds == 600)
        var loop = HabitLoop()
        let legacy = DailyLearningActivity(dateKey: "2026-10-21", watchedSeconds: 300, goalMinutes: 60)
        _ = loop.prepareDailyGoal(day: "2026-10-22")
        #expect(loop.learningDays(activities: [legacy]).contains("2026-10-21"))
    }

    @Test func rewardsAndChestArePersistentAndIdempotent() throws {
        var loop = HabitLoop(); loop.startedDay = "2026-10-22"
        play(900, loop: &loop)
        loop.reflect(on: "2026-10-22")
        let first = loop.reconcile(activities: [], goalMinutes: 15, now: date("2026-10-22"), chestRoll: 95, calendar: calendar)
        #expect(first.count == 4)
        #expect(loop.questCount(on: "2026-10-22") == 3)
        #expect(loop.gems == 35)
        #expect(loop.rewardXP == 45)
        #expect(loop.boostSeconds == 900)
        let restored = try JSONDecoder().decode(HabitLoop.self, from: JSONEncoder().encode(loop))
        var replayed = restored
        #expect(replayed.reconcile(activities: [], goalMinutes: 15, now: date("2026-10-22"), chestRoll: 0, calendar: calendar).isEmpty)
        #expect(replayed.gems == 35)
        #expect(replayed.rewardXP == 45)
        play(60, loop: &replayed)
        _ = replayed.reconcile(activities: [], goalMinutes: 15, now: date("2026-10-22"), calendar: calendar)
        #expect(replayed.rewardXP == 47)
        #expect(replayed.boostSeconds == 840)
    }

    @Test func concurrentOfflineBoostUseCannotMultiplyTheEarnedBudget() {
        var loop = HabitLoop()
        loop.insert(.init(id: "boost/2026-10-20", day: "2026-10-20", kind: "boost", value: 900))
        for day in ["2026-10-20", "2026-10-21"] {
            loop.insert(.init(id: "boost-use/device/\(day)", day: day, kind: "boost-use", value: 900))
            for minute in 1...15 { loop.insert(.init(id: "boost-xp/\(day)/\(minute)", day: day, kind: "xp", value: 1)) }
        }
        #expect(loop.rewardXP == 15)
        loop.insert(.init(id: "boost/2026-10-22", day: "2026-10-22", kind: "boost", value: 900))
        #expect(loop.rewardXP == 15)
        #expect(loop.boostSeconds == 900)
    }

    @Test func legacyDaysKeepTheirOriginalFiveMinuteThreshold() {
        var loop = HabitLoop(); loop.startedDay = "2026-10-22"
        play(300, loop: &loop)
        _ = loop.reconcile(activities: [], goalMinutes: 15, now: date("2026-10-22"), calendar: calendar)
        #expect(loop.streak(activities: [], now: date("2026-10-22"), calendar: calendar).count == 1)
        #expect(loop.questCount(on: "2026-10-22") == 1)
        #expect(loop.goalSeconds(on: "2026-10-22", fallback: 3600) == 900)
    }

    @Test func freezesPreserveButNeverAdvanceStreaks() {
        var loop = HabitLoop(); loop.startedDay = "2026-10-19"
        let activity = DailyLearningActivity(dateKey: "2026-10-19", watchedSeconds: 300, goalMinutes: 15)
        let frozen = loop.streak(activities: [activity], now: date("2026-10-22"), calendar: calendar)
        #expect(frozen.count == 1)
        #expect(frozen.freezes == 0)
        #expect(frozen.frozenDays.count == 2)
        let broken = loop.streak(activities: [activity], now: date("2026-10-23"), calendar: calendar)
        #expect(broken.count == 0)
    }

    @Test func migrationDoesNotGrantOldQuestsOrMilestones() {
        var loop = HabitLoop(); loop.startedDay = "2026-10-22"; loop.legacyXP = 500
        let history = (19...22).map { DailyLearningActivity(dateKey: "2026-10-\($0)", watchedSeconds: 900, goalMinutes: 15) }
        _ = loop.reconcile(activities: history, goalMinutes: 15, now: date("2026-10-22"), calendar: calendar)
        #expect(loop.rewardXP == 0)
        #expect(loop.gems == 0)
        #expect(loop.badges.isEmpty)
        #expect(loop.streak(activities: history, now: date("2026-10-22"), calendar: calendar).count == 4)
    }

    @Test func mergingKeepsLocalProgressAndUsesCanonicalRewards() {
        var loop = HabitLoop()
        loop.insert(.init(id: "playback/local/2026-10-22", day: "2026-10-22", kind: "playback", value: 310))
        loop.insert(.init(id: "chest/2026-10-22", day: "2026-10-22", kind: "gems", value: 20))
        let remote: [HabitEvent] = [
            .init(id: "playback/local/2026-10-22", day: "2026-10-22", kind: "playback", value: 300),
            .init(id: "playback/remote/2026-10-22", day: "2026-10-22", kind: "playback", value: 100),
            .init(id: "chest/2026-10-22", day: "2026-10-22", kind: "gems", value: 5)]
        loop.merge(remote); loop.merge(remote)
        #expect(loop.learnedSeconds(on: "2026-10-22") == 410)
        #expect(loop.events.count == 3)
        #expect(loop.gems == 5)
    }

    @Test func recallRequiresEvidenceAndHonorsReviewSchedule() {
        let text = "An actual transcript passage about deliberate practice."
        let valid = RecallQuestion(id: "1", question: "What is discussed?", choices: ["Deliberate practice", "Cars", "Dogs", "Weather"], answer: 0, explanation: "The speaker discusses practice.", evidence: "transcript passage about deliberate practice")
        #expect(valid.isValid(in: text))
        var invalid = valid; invalid.evidence = "Invented source material that never appears"
        #expect(!invalid.isValid(in: text))
        var review = RecallReview(id: "review", podcastID: UUID(), transcriptDigest: "hash", questions: [valid], createdDay: "2026-10-22")
        #expect(review.dueStage(on: "2026-10-22", calendar: calendar) == 0)
        review.completedStages = [0]
        #expect(review.dueStage(on: "2026-10-22", calendar: calendar) == nil)
        #expect(review.dueStage(on: "2026-10-23", calendar: calendar) == 1)
        review.completedStages = [0, 1, 3, 7]
        #expect(review.dueStage(on: "2026-11-22", calendar: calendar) == nil)
    }

    @Test func reminderCapQuietHoursAndSevenDayPause() {
        var loop = HabitLoop(); loop.lastOpenedAt = date("2026-10-22")
        let podcast = Podcast(title: "An idea", url: "https://youtu.be/abcdefghijk", youtubeVideoId: "abcdefghijk")
        let now = date("2026-10-22")
        let plan = HabitReminderPlanner.plan(now: now, preferences: .init(), activities: [], goalMinutes: 15,
            nextPodcast: podcast, isPlaying: false, loop: loop, focus: nil, lastSession: nil, pattern: nil, calendar: calendar)
        let grouped = Dictionary(grouping: plan) { LearningCalendar.dateKey(for: $0.fireDate, calendar: calendar) }
        #expect(grouped.values.allSatisfy { $0.count <= 3 })
        #expect(plan.allSatisfy { (8..<22).contains(calendar.component(.hour, from: $0.fireDate)) })
        #expect(grouped["2026-10-29"]?.count == 1)
        let after = HabitReminderPlanner.plan(now: date("2026-10-30"), preferences: .init(), activities: [], goalMinutes: 15,
            nextPodcast: podcast, isPlaying: false, loop: loop, focus: nil, lastSession: nil, pattern: nil, calendar: calendar)
        #expect(after.isEmpty)
        let rescued = HabitReminderPlanner.plan(now: now, preferences: .init(), activities: [], goalMinutes: 15,
            nextPodcast: podcast, isPlaying: false, loop: loop, focus: nil, lastSession: nil,
            pattern: .init(cue: .scrolling, weekday: 5, hour: 9, minute: 0, observations: 3), calendar: calendar)
        #expect(rescued.contains { $0.stage == .rescue && calendar.component(.hour, from: $0.fireDate) == 9 })
        #expect(rescued.contains { $0.stage == .afternoon && calendar.component(.hour, from: $0.fireDate) == 14 })
        play(900, loop: &loop)
        let protected = HabitReminderPlanner.plan(now: now, preferences: .init(), activities: [], goalMinutes: 15,
            nextPodcast: podcast, isPlaying: false, loop: loop, focus: nil, lastSession: nil, pattern: nil, calendar: calendar)
        #expect(!protected.contains { LearningCalendar.dateKey(for: $0.fireDate, calendar: calendar) == "2026-10-22" })
    }
}
