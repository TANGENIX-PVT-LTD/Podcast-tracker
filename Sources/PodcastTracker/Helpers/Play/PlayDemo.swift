import SwiftUI

extension AppViewModel {
    /// Demo data must never sync to (or be replaced by) the cloud.
    nonisolated static var demoMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-PodTrackioDemo")
        #else
        false
        #endif
    }
}

#if DEBUG

/// Debug-only QA tools: `-PodTrackioDemo` seeds a believable 12-day-streak account without signing in,
/// and `-PodTrackioMoment <name>` (or Settings → Preview moments) replays each reward moment.
@MainActor
enum PlayDemo {
    static let moments = ["streak", "milestone", "chest", "level", "session", "freeze", "quiz", "achievement"]
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-PodTrackioDemo") }

    static func installIfRequested(_ vm: AppViewModel, auth: AuthManager) {
        guard isOn else { return }
        auth.isAuthenticated = true
        // Signing in triggers an async reload from disk; seed after it lands.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.6))
            seed(vm)
        }
    }

    private static func seed(_ vm: AppViewModel) {
        let calendar = Calendar.current
        let today = Date()
        func key(_ offset: Int) -> String { LearningCalendar.dateKey(for: calendar.date(byAdding: .day, value: offset, to: today)!) }
        let episodes: [(String, String)] = [
            ("How to Speak — Patrick Winston", "Unzc731iCUY"), ("Inside the mind of a master procrastinator", "arj7oStGLkU"),
            ("The first 20 hours: how to learn anything", "5MgBikgcWnY"), ("Grit: the power of passion and perseverance", "H14bBuluwB8"),
            ("Steve Jobs' 2005 Stanford commencement", "UF8uR6Z6KLc")
        ]
        vm.podcasts = episodes.enumerated().map { index, item in
            Podcast(title: item.0, url: "https://youtu.be/\(item.1)", youtubeVideoId: item.1,
                    thumbnailURL: "https://i.ytimg.com/vi/\(item.1)/hqdefault.jpg",
                    dateAdded: calendar.date(byAdding: .day, value: -20 + index, to: today)!,
                    totalWatchedSeconds: index < 3 ? Double(1800 - index * 400) : 0,
                    lastWatchedDate: index < 3 ? calendar.date(byAdding: .day, value: -index, to: today) : nil,
                    lastPlaybackPosition: index == 0 ? 1260 : 0, isCompleted: index == 2, duration: 3600)
        }
        vm.summaries = [
            PodcastSummary(podcastID: vm.podcasts[0].id, brief: "Speaking is a skill: start with an empowerment promise, cycle on the subject, build a fence around your idea, and end with a contribution, not a thank-you.",
                           keyTopics: [.init(title: "Empowerment promise", explanation: "Tell people what they will know by the end that they don't know now."),
                                       .init(title: "Cycling", explanation: "Repeat the core idea three times; a fraction of listeners is always fogged out.")],
                           majorTakeaways: [.init(title: "Verbal punctuation", explanation: "Signal structure so people can rejoin after drifting.")],
                           actionPlan: [.init(title: "Write your empowerment promise", detail: "One sentence for your next talk.")],
                           generatedAt: today, transcriptSource: .captions, model: "demo"),
            PodcastSummary(podcastID: vm.podcasts[2].id, brief: "You can get reasonably good at almost anything in about 20 hours of deliberate practice by deconstructing the skill and removing barriers.",
                           keyTopics: [.init(title: "Deconstruct the skill", explanation: "Break it into the smallest sub-skills and practise the most important first."),
                                       .init(title: "Remove practice barriers", explanation: "Distractions and setup friction are what stop people practising.")],
                           majorTakeaways: [.init(title: "The frustration barrier", explanation: "The first hours feel bad; push through them.")],
                           actionPlan: [.init(title: "Commit 20 hours", detail: "Schedule 45 minutes a day for a month.")],
                           generatedAt: today, transcriptSource: .captions, model: "demo")
        ]
        var loop = HabitLoop()
        loop.startedDay = key(-30)
        for offset in -13 ... -1 where offset != -5 {
            loop.events.append(.init(id: "adaptive-goal/\(key(offset))", day: key(offset), kind: "goal", value: 540))
            loop.events.append(.init(id: "playback/\(loop.deviceID)/\(key(offset))", day: key(offset), kind: "playback", value: 600 + Double(offset * -20)))
        }
        loop.events.append(.init(id: "adaptive-goal/\(key(0))", day: key(0), kind: "goal", value: 540))
        loop.events.append(.init(id: "playback/\(loop.deviceID)/\(key(0))", day: key(0), kind: "playback", value: 372))
        loop.events.append(.init(id: "demo/gems", day: key(-10), kind: "gems", value: 240))
        loop.legacyXP = 1180
        vm.habitLoop = loop
        vm.reconcileHabitLoop(celebrate: false)
        vm.stats.longestStreak = max(vm.stats.longestStreak, 19)
        vm.showDailyCelebration = false
        vm.showLevelUpAlert = false
        vm.checkAchievements()
        vm.showAchievementPopup = false
        vm.saveData()
        vm.showDailyCelebration = false
        vm.showLevelUpAlert = false
        PlayMoments.shared.chestGems = nil
        Task { try? await Task.sleep(for: .seconds(0.3)); vm.showLevelUpAlert = false }

        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-PodTrackioSection"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1),
           let section = AppSection.allCases.first(where: { $0.rawValue.lowercased() == ProcessInfo.processInfo.arguments[index + 1] }) {
            vm.selectedSection = section
        }
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-PodTrackioMoment"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
            let moment = ProcessInfo.processInfo.arguments[index + 1]
            Task { try? await Task.sleep(for: .seconds(1.2)); trigger(moment, vm: vm) }
        }
    }

    static func trigger(_ moment: String, vm: AppViewModel) {
        switch moment {
        case "streak": vm.showDailyCelebration = true
        case "milestone":
            vm.stats.currentStreak = 7; vm.showDailyCelebration = true
        case "chest": PlayMoments.shared.chestGems = 10
        case "level": vm.showLevelUpAlert = true
        case "session": PlayMoments.shared.session = SessionSummary(seconds: 840, xp: 26, quests: 2, goalProgress: 1)
        case "freeze": PlayMoments.shared.freezeSavedStreak = max(1, vm.stats.currentStreak)
        case "quiz":
            BrainStore.shared.quiz = BrainQuiz(title: "How to Speak", questions: [
                RecallQuestion(id: "1", question: "What should a talk open with?", choices: ["A joke", "An empowerment promise", "A thank-you", "Your biography"], answer: 1,
                               explanation: "Winston recommends telling people what they'll know by the end.", evidence: "start with an empowerment promise"),
                RecallQuestion(id: "2", question: "Why cycle on your main idea?", choices: ["It fills time", "Some listeners are always fogged out", "Slides require it", "To sound confident"], answer: 1,
                               explanation: "Repeating the idea lets drifting listeners rejoin.", evidence: "a fraction of listeners is always fogged out"),
                RecallQuestion(id: "3", question: "How should a talk end?", choices: ["Thank you", "Questions?", "A contribution", "A summary slide"], answer: 2,
                               explanation: "End with what you contributed, not a thank-you.", evidence: "end with a contribution, not a thank-you")
            ])
            vm.selectedSection = .brain
        case "achievement":
            if let first = vm.achievements.first { vm.newlyUnlockedAchievement = first; vm.showAchievementPopup = true }
        default: break
        }
    }
}

/// Settings section listing every reward moment for QA.
struct PreviewMomentsSection: View {
    @EnvironmentObject private var viewModel: AppViewModel
    var body: some View {
        Section("Preview moments (debug)") {
            ForEach(PlayDemo.moments, id: \.self) { moment in
                Button(moment.capitalized) { PlayDemo.trigger(moment, vm: viewModel) }
            }
        }
    }
}
#endif
