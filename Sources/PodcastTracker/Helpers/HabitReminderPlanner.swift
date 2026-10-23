import Foundation

enum HabitReminderPlanner {
    static func plan(now: Date, preferences: NotificationPreferences, activities: [DailyLearningActivity],
                     goalMinutes: Double, nextPodcast: Podcast?, isPlaying: Bool, loop: HabitLoop,
                     focus: FocusDayState?, lastSession: Date?, pattern: DistractionPattern?, calendar: Calendar = .current) -> [LearningNotificationPlanItem] {
        guard preferences.isEnabled, let nextPodcast else { return [] }
        let lastReturn = loop.lastOpenedAt ?? now
        let latest = max(lastReturn, lastSession ?? lastReturn)
        guard let finalDate = calendar.date(byAdding: .day, value: 7, to: latest) else { return [] }
        var result: [LearningNotificationPlanItem] = []
        for offset in 0..<8 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: now),
                  preferences.enabledWeekdays.contains(calendar.component(.weekday, from: date)),
                  calendar.startOfDay(for: date) <= calendar.startOfDay(for: finalDate) else { continue }
            let day = LearningCalendar.dateKey(for: date, calendar: calendar)
            let today = offset == 0
            if today && (isPlaying || focus?.enabled == true && focus?.isLocked == false) { continue }
            let activity = activities.first { $0.dateKey == day }
            let learned = max(activity?.watchedSeconds ?? 0, loop.learnedSeconds(on: day))
            let target = loop.goalSeconds(on: day, fallback: goalMinutes * 60)
            if (activity?.goalCompleted == true || learned >= target) && !(today && focus?.isLocked == true) { continue }
            let final = calendar.isDate(date, inSameDayAs: finalDate)
            var slots: [(LearningNotificationStage, NotificationPreferences.TimeOfDay)] = [(.morning, preferences.morning), (.afternoon, preferences.afternoon), (.evening, preferences.evening)]
            if final { slots = [(.evening, preferences.evening)] }
            if !final, let lastSession {
                let minute = calendar.component(.hour, from: lastSession) * 60 + calendar.component(.minute, from: lastSession)
                if let index = slots.indices.min(by: { abs(slots[$0].1.hour * 60 + slots[$0].1.minute - minute) < abs(slots[$1].1.hour * 60 + slots[$1].1.minute - minute) }),
                   abs(slots[index].1.hour * 60 + slots[index].1.minute - minute) <= 90 {
                    slots[index].1 = .init(hour: minute / 60, minute: minute % 60)
                }
            }
            if !final, let pattern, pattern.weekday == calendar.component(.weekday, from: date), slots.count == 3 {
                let minute = pattern.hour * 60 + pattern.minute
                if let index = slots.indices.min(by: { abs(slots[$0].1.hour * 60 + slots[$0].1.minute - minute) < abs(slots[$1].1.hour * 60 + slots[$1].1.minute - minute) }) {
                    slots[index] = (.rescue, .init(hour: pattern.hour, minute: pattern.minute))
                }
            }
            for (index, slot) in slots.enumerated() {
                var components = calendar.dateComponents([.year, .month, .day], from: date)
                components.hour = slot.1.hour; components.minute = slot.1.minute
                guard let fire = calendar.date(from: components), fire > now, !isQuiet(fire, preferences, calendar) else { continue }
                let id = "learning.\(day).habit\(index)"
                if loop.reminderHistory.contains(where: { $0.id == id && $0.fireTime <= now }) { continue }
                let template = loop.reminderHistory.first { $0.id == id }?.template ?? chooseTemplate(history: loop.reminderHistory, day: day, slot: index, now: now)
                let protected = today && (loop.completedGoal(on: day))
                let status = loop.streak(activities: activities, now: now, calendar: calendar)
                let remaining = today && focus?.isLocked == true ? Int(ceil((focus?.remainingSeconds() ?? 0) / 60))
                    : max(0, Int(ceil(target / 60 - learned / 60)))
                let title: String
                if final { title = "These reminders will take a break" }
                else if protected { title = "Streak safe. \(remaining) minutes to your target." }
                else if today && status.count > 0 && status.freezes == 0 { title = "Your \(status.count)-day streak has \(remaining) minutes left to defend." }
                else { title = ["The scroll can wait.", "Five useful minutes first.", "Your next idea is waiting.", "Keep the promise you picked.", "Tiny session. Real momentum.", "Learning called. Pick up?"][template] }
                let body = final ? "We’ll pause motivational reminders after today until you return. Your learning is here whenever you’re ready."
                    : protected ? "Continue \(nextPodcast.title). Only actual playback counts toward your daily target."
                    : status.freezes > 0 && today ? "\(remaining) minutes completes today’s learning goal. A freeze can protect continuity, but it won’t unlock apps."
                    : "Start one five-minute block with \(nextPodcast.title)."
                result.append(.init(id: id, fireDate: fire, stage: slot.0, title: title, body: body, podcastID: nextPodcast.id, template: template))
            }
        }
        return result.sorted { $0.fireDate < $1.fireDate }
    }

    static func chooseTemplate(history: [HabitReminderExposure], day: String, slot: Int, now: Date) -> Int {
        let previous = history.filter { $0.fireTime < now }.sorted { $0.fireTime > $1.fireTime }
        let recent = Set(previous.prefix(3).map(\.template))
        let candidates = (0..<6).filter { !recent.contains($0) }
        let seed = day.utf8.reduce(slot) { ($0 + Int($1)) % 10_000 }
        if previous.count < 6 || seed % 5 == 0 { return candidates[seed % candidates.count] }
        return candidates.max { a, b in
            func rate(_ template: Int) -> Double {
                let exposures = previous.filter { $0.template == template }
                return Double(exposures.filter(\.completed).count + 1) / Double(exposures.count + 2)
            }
            return rate(a) < rate(b)
        } ?? 0
    }

    private static func isQuiet(_ date: Date, _ preferences: NotificationPreferences, _ calendar: Calendar) -> Bool {
        guard preferences.quietHoursEnabled else { return false }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let start = preferences.quietHoursStart.hour * 60 + preferences.quietHoursStart.minute
        let end = preferences.quietHoursEnd.hour * 60 + preferences.quietHoursEnd.minute
        return start <= end ? (start..<end).contains(minute) : minute >= start || minute < end
    }
}
