import Foundation

/// Echo's voice: warm, specific, never guilt-tripping. Lines are chosen from real state.
@MainActor
enum EchoLines {
    struct Line { var mood: EchoMood; var text: String }

    static func today(_ vm: AppViewModel, now: Date = Date()) -> Line {
        let streak = vm.stats.currentStreak
        let left = vm.todayRemainingMinutes
        let hour = Calendar.current.component(.hour, from: now)
        let quests = vm.habitLoop.questCount(on: LearningCalendar.dateKey(for: now))
        if vm.podcasts.isEmpty { return Line(mood: .happy, text: "Add one episode you're curious about. I'll keep you company!") }
        if vm.streakProtectedToday {
            if quests < 3 { return Line(mood: .proud, text: "Streak safe! \(3 - quests) quest\(3 - quests == 1 ? "" : "s") left, then the chest is yours.") }
            return Line(mood: .cheer, text: "Everything done today. You're on fire! 🔥")
        }
        if vm.streakAtRisk { return Line(mood: .worried, text: "Just \(left) minute\(left == 1 ? "" : "s") keeps your \(streak)-day flame alive. We've got this!") }
        if streak == 0 { return Line(mood: .happy, text: "Let's light your first flame. \(left) minutes is all it takes.") }
        if isMonday(now) && hour < 14 { return Line(mood: .happy, text: "Fresh week, fresh league. \(left) minutes starts it strong.") }
        switch hour {
        case ..<12: return Line(mood: .happy, text: "Morning! \(left) minutes keeps your \(streak)-day streak growing.")
        case ..<18: return Line(mood: .idle, text: "\(left) minutes to protect day \(streak + 1). Ready when you are.")
        default: return Line(mood: .idle, text: "Evening listen? \(left) minutes and day \(streak + 1) is yours.")
        }
    }

    static func streakDetail(_ vm: AppViewModel) -> String {
        let count = vm.stats.currentStreak
        let next = StreakMilestones.next(after: count)
        if vm.streakAtRisk { return "Your flame is flickering. \(vm.todayRemainingMinutes) minutes saves it." }
        if count == 0 { return "Every legendary streak started at day one." }
        return "\(next - count) more day\(next - count == 1 ? "" : "s") to your \(next)-day badge!"
    }

    static func celebration(streak: Int) -> String {
        switch streak {
        case 1: "Day one! Every great streak starts here."
        case 3: "Three in a row. A habit is forming!"
        case 7: "A whole week! You're officially a regular."
        case 14: "Two weeks strong. This is who you are now."
        case 30: "Thirty days! Legendary consistency."
        case 50, 100, 365: "\(streak) days. I'm speechless. Well, almost."
        default: ["Streak extended! Your brain thanks you.", "Another day, another flame. Nice!", "Consistency is your superpower.", "Keep stacking those days!"][streak % 4]
        }
    }

    static func quizFeedback(correct: Bool, combo: Int) -> String {
        if correct { return combo >= 3 ? "\(combo) in a row! Unstoppable." : ["Nice!", "Correct!", "You remembered!", "Exactly right!"][combo % 4] }
        return ["Not quite. Here's the source.", "Close! Check the evidence.", "Good try. This one's worth another listen."][combo % 3]
    }
}

private func isMonday(_ date: Date) -> Bool { Calendar.current.component(.weekday, from: date) == 2 }
