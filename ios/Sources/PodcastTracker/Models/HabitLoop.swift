import Foundation

struct PlaybackCreditTracker {
    private var lastPosition: Double?
    private var lastTime: Double?

    mutating func reset() { lastPosition = nil; lastTime = nil }
    mutating func begin(position: Double, uptime: Double = ProcessInfo.processInfo.systemUptime) {
        lastPosition = position; lastTime = uptime
    }

    mutating func sample(position: Double, playing: Bool, uptime: Double = ProcessInfo.processInfo.systemUptime) -> Double {
        defer { lastPosition = position; lastTime = uptime }
        guard playing, position.isFinite, let previous = lastPosition, let time = lastTime else { return 0 }
        let elapsed = uptime - time
        let advance = position - previous
        guard elapsed > 0, elapsed <= 10, advance > 0, advance <= elapsed * 4 + 0.25 else { return 0 }
        return elapsed
    }
}

struct HabitEvent: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var day: String
    var kind: String
    var value: Double = 0
    var detail: String = ""
}

struct RecallQuestion: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var question: String
    var choices: [String]
    var answer: Int
    var explanation: String
    var evidence: String

    func isValid(in transcript: String) -> Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && choices.count == 4
            && Set(choices).count == 4 && choices.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && (0..<4).contains(answer) && !explanation.isEmpty && evidence.count >= 12
            && transcript.range(of: evidence, options: [.caseInsensitive]) != nil
    }
}

struct RecallReview: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var podcastID: UUID
    var transcriptDigest: String
    var questions: [RecallQuestion]
    var createdDay: String
    var completedStages: Set<Int> = []

    func dueStage(on day: String, calendar: Calendar = .current) -> Int? {
        guard let start = LearningCalendar.date(from: createdDay, calendar: calendar),
              let date = LearningCalendar.date(from: day, calendar: calendar) else { return nil }
        let days = calendar.dateComponents([.day], from: start, to: date).day ?? 0
        return [0, 1, 3, 7].first { days >= $0 && !completedStages.contains($0) }
    }
}

struct HabitLeague: Equatable {
    var tier: Int
    var targetMinutes: Double
    var minutes: Double
    var activeDays: Int
    var history: [(String, Double)]
    static let titles = ["Bronze", "Silver", "Gold", "Platinum", "Diamond"]
    var title: String { Self.titles[min(4, max(0, tier))] }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tier == rhs.tier && lhs.targetMinutes == rhs.targetMinutes && lhs.minutes == rhs.minutes && lhs.activeDays == rhs.activeDays
            && lhs.history.elementsEqual(rhs.history, by: { $0.0 == $1.0 && $0.1 == $1.1 })
    }
}

struct HabitLoop: Codable, Sendable {
    var ownerID: String?
    var startedDay = LearningCalendar.dateKey(for: Date())
    var deviceID = UUID().uuidString
    var legacyXP = 0
    var events: [HabitEvent] = []
    var reviews: [RecallReview] = []
    var lastOpenedAt: Date?
    var soundsEnabled = true
    var hapticsEnabled = true
    var reminderHistory: [HabitReminderExposure] = []

    var rewardXP: Int {
        let ordinary = events.filter { $0.kind == "xp" && !$0.id.hasPrefix("boost-xp/") }.reduce(0) { $0 + Int($1.value) }
        let bonus = Dictionary(grouping: events.filter { $0.kind == "xp" && $0.id.hasPrefix("boost-xp/") }, by: \.day)
        let allocation = boostAllocation.byDay
        return ordinary + bonus.reduce(0) { $0 + min($1.value.count, Int((allocation[$1.key] ?? 0) / 60)) }
    }
    var gems: Int { max(0, events.filter { $0.kind == "gems" || $0.kind == "spend" }.reduce(0) { $0 + Int($1.value) }) }
    var badges: [HabitEvent] { events.filter { $0.kind == "badge" }.sorted { $0.day > $1.day } }
    private var boostAllocation: (byDay: [String: Double], remaining: Double) {
        let grants = Dictionary(grouping: events.filter { $0.kind == "boost" }, by: \.day).mapValues { $0.reduce(0) { $0 + $1.value } }
        let uses = Dictionary(grouping: events.filter { $0.kind == "boost-use" }, by: \.day).mapValues { $0.reduce(0) { $0 + $1.value } }
        var balance = 0.0, byDay: [String: Double] = [:]
        for day in Set(grants.keys).union(uses.keys).sorted() {
            balance += grants[day] ?? 0
            let credit = min(balance, uses[day] ?? 0)
            byDay[day] = credit; balance -= credit
        }
        return (byDay, balance)
    }
    var boostSeconds: Double { boostAllocation.remaining }

    func learnedSeconds(on day: String) -> Double {
        events.filter { $0.kind == "playback" && $0.day == day }.reduce(0) { $0 + $1.value }
    }

    func localSeconds(on day: String) -> Double {
        events.first { $0.id == "playback/\(deviceID)/\(day)" }?.value ?? 0
    }

    func has(_ id: String) -> Bool { events.contains { $0.id == id } }
    func questCount(on day: String) -> Int { (1...3).filter { has("quest/\(day)/\($0)/xp") }.count }
    func goalSeconds(on day: String, fallback: Double) -> Double {
        events.first { $0.id == "adaptive-goal/\(day)" }?.value ?? events.first { $0.id == "goal/\(day)" }?.value ?? fallback
    }

    /// A dated receipt freezes the target; only completed days advance the next level.
    @discardableResult
    mutating func prepareDailyGoal(day: String) -> Double {
        if let goal = events.first(where: { $0.id == "adaptive-goal/\(day)" }) { return goal.value / 60 }
        let completed = events.filter { $0.id.hasPrefix("adaptive-goal/") && $0.day < day
            && learnedSeconds(on: $0.day) >= $0.value }.count
        let minutes = min(60, 5 + Double(completed / 2))
        insert(.init(id: "adaptive-goal/\(day)", day: day, kind: "goal", value: minutes * 60,
                     detail: "daily-v2"))
        return minutes
    }

    func completedGoal(on day: String) -> Bool {
        learnedSeconds(on: day) >= goalSeconds(on: day, fallback: 300)
    }

    @discardableResult
    mutating func insert(_ event: HabitEvent) -> Bool {
        guard !has(event.id), event.value.isFinite else { return false }
        events.append(event)
        return true
    }

    mutating func record(seconds: Double, day: String, goalMinutes: Double) {
        guard seconds.isFinite, seconds > 0, seconds <= 10 else { return }
        insert(.init(id: "goal/\(day)", day: day, kind: "goal", value: max(5, goalMinutes) * 60))
        let id = "playback/\(deviceID)/\(day)"
        if let index = events.firstIndex(where: { $0.id == id }) { events[index].value += seconds }
        else { events.append(.init(id: id, day: day, kind: "playback", value: seconds)) }
        let boost = min(seconds, boostSeconds)
        if boost > 0 {
            let boostID = "boost-use/\(deviceID)/\(day)"
            if let index = events.firstIndex(where: { $0.id == boostID }) { events[index].value += boost }
            else { events.append(.init(id: boostID, day: day, kind: "boost-use", value: boost)) }
        }
    }

    mutating func reflect(on day: String) {
        insert(.init(id: "reflection/\(day)", day: day, kind: "reflection"))
    }

    @discardableResult
    mutating func reconcile(activities: [DailyLearningActivity], goalMinutes: Double, now: Date = Date(), chestRoll: Int = Int.random(in: 0..<100), calendar: Calendar = .current) -> [String] {
        let day = LearningCalendar.dateKey(for: now, calendar: calendar)
        var wins: [String] = []
        let seconds = learnedSeconds(on: day)
        let minutes = Int(seconds / 60)
        if minutes > 0 {
            for minute in 1...minutes { insert(.init(id: "minute/\(day)/\(minute)", day: day, kind: "xp", value: 1)) }
        }
        let bonusMinutes = Int(events.filter { $0.kind == "boost-use" && $0.day == day }.reduce(0) { $0 + $1.value } / 60)
        if bonusMinutes > 0 {
            for minute in 1...bonusMinutes { insert(.init(id: "boost-xp/\(day)/\(minute)", day: day, kind: "xp", value: 1)) }
        }
        let target = goalSeconds(on: day, fallback: goalMinutes * 60)
        for (number, achieved) in [(1, seconds >= 300), (2, seconds >= target), (3, has("reflection/\(day)"))] where achieved {
            if insert(.init(id: "quest/\(day)/\(number)/xp", day: day, kind: "xp", value: 10)) {
                insert(.init(id: "quest/\(day)/\(number)/gems", day: day, kind: "gems", value: 5))
                wins.append("Quest complete · +10 XP · +5 gems")
            }
        }
        if questCount(on: day) == 3, !has("chest/\(day)") {
            let roll = min(99, max(0, chestRoll))
            let reward = roll < 60 ? 5 : roll < 90 ? 10 : 20
            insert(.init(id: "chest/\(day)", day: day, kind: "gems", value: Double(reward)))
            insert(.init(id: "boost/\(day)", day: day, kind: "boost", value: 900))
            wins.append("Daily chest · \(reward) gems · 15-minute XP boost")
        }
        let status = streak(activities: activities, now: now, calendar: calendar)
        for milestone in [3, 7, 14, 30, 50, 100, 365] where seconds >= target && status.count >= milestone {
            if insert(.init(id: "milestone/\(milestone)", day: day, kind: "badge", value: Double(milestone), detail: "\(milestone)-day streak")) {
                wins.append("\(milestone)-day streak protected")
            }
        }
        let week = weekStart(for: now, calendar: calendar)
        let weekKey = LearningCalendar.dateKey(for: week, calendar: calendar)
        let weekDays = learningDays(activities: activities).filter { $0 >= weekKey && $0 <= day && $0 >= startedDay }.count
        if weekDays >= 5 { insert(.init(id: "weekly/\(weekKey)", day: day, kind: "badge", detail: "Five-day week · \(weekKey)")) }
        let month = String(day.prefix(7))
        if events.filter({ $0.id.hasPrefix("quest/\(month)") && $0.kind == "xp" }).count >= 20 {
            insert(.init(id: "monthly/\(month)", day: day, kind: "badge", detail: "20-quest month · \(month)"))
        }
        if let wager = activeWager(on: day), let start = LearningCalendar.date(from: wager.day, calendar: calendar),
           let end = calendar.date(byAdding: .day, value: 6, to: start) {
            let endKey = LearningCalendar.dateKey(for: end, calendar: calendar)
            let learned = learningDays(activities: activities)
            if day >= endKey && (0..<7).allSatisfy({ offset in
                calendar.date(byAdding: .day, value: offset, to: start).map { learned.contains(LearningCalendar.dateKey(for: $0, calendar: calendar)) } == true
            }) {
                if insert(.init(id: "wager-reward/\(wager.day)", day: day, kind: "gems", value: 40)) { wins.append("Seven promises kept · +40 gems") }
            }
        }
        let firstWeek = events.filter { $0.kind == "league-target" }.map(\.day).min()
        var targetWeek = firstWeek.flatMap { LearningCalendar.date(from: $0, calendar: calendar) } ?? week
        while targetWeek <= week {
            let targetKey = LearningCalendar.dateKey(for: targetWeek, calendar: calendar)
            if !has("league-target/\(targetKey)") {
                let previousGoal = events.filter { $0.kind == "goal" && $0.day < targetKey }.max { $0.day < $1.day }?.value
                let daily = targetWeek == week ? goalMinutes : (previousGoal.map { $0 / 60 } ?? goalMinutes)
                let history = previousWeeks(activities: activities, before: targetWeek, calendar: calendar).map(\.1).sorted()
                let median = (history[1] + history[2]) / 2
                insert(.init(id: "league-target/\(targetKey)", day: targetKey, kind: "league-target", value: max(daily * 5, median)))
            }
            guard let next = calendar.date(byAdding: .day, value: 7, to: targetWeek) else { break }
            targetWeek = next
        }
        for target in events.filter({ $0.kind == "league-target" && $0.day < weekKey }) {
            guard let start = LearningCalendar.date(from: target.day, calendar: calendar),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { continue }
            let endKey = LearningCalendar.dateKey(for: end, calendar: calendar)
            let days = learningDays(activities: activities).filter { $0 >= target.day && $0 < endKey }.count
            let total = activityMinutes(activities: activities, from: target.day, to: endKey)
            let change = total >= target.value && days >= 5 ? 1.0 : total >= target.value * 0.6 ? 0 : -1
            let id = "league-result/\(target.day)"
            if let index = events.firstIndex(where: { $0.id == id }) { events[index].value = change }
            else { insert(.init(id: id, day: target.day, kind: "league-result", value: change)) }
        }
        return wins
    }

    private var playbackByDay: [String: Double] {
        events.filter { $0.kind == "playback" }.reduce(into: [:]) { $0[$1.day, default: 0] += $1.value }
    }

    func learningDays(activities: [DailyLearningActivity]) -> Set<String> {
        let adaptiveDays = Set(events.filter { $0.id.hasPrefix("adaptive-goal/") }.map(\.day))
        let legacy = activities.filter { !adaptiveDays.contains($0.dateKey) && $0.qualifiesForStreak }.map(\.dateKey)
        return Set(legacy).union(playbackByDay.filter { $0.value >= (adaptiveDays.contains($0.key) ? goalSeconds(on: $0.key, fallback: 300) : 300) }.map(\.key))
    }

    func streak(activities: [DailyLearningActivity], now: Date = Date(), calendar: Calendar = .current) -> (count: Int, freezes: Int, frozenDays: Set<String>) {
        let learned = learningDays(activities: activities)
        let today = LearningCalendar.dateKey(for: now, calendar: calendar)
        var freezes = 2, count = 0, activeDays = 0
        var frozen: Set<String> = []
        let refills = Dictionary(grouping: events.filter { $0.kind == "freeze-refill" }, by: \.day).mapValues(\.count)
        guard let first = learned.sorted().first, var cursor = LearningCalendar.date(from: first, calendar: calendar) else { return (0, 2, []) }
        while cursor <= now {
            let key = LearningCalendar.dateKey(for: cursor, calendar: calendar)
            if key >= startedDay {
                freezes = min(2, freezes + (refills[key] ?? 0))
            }
            if learned.contains(key) {
                count += 1
                if key >= startedDay {
                    activeDays += 1
                    if activeDays % 7 == 0 { freezes = min(2, freezes + 1) }
                }
            } else if key < today {
                if key >= startedDay && count > 0 && freezes > 0 { freezes -= 1; frozen.insert(key) }
                else { count = 0 }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return (count, freezes, frozen)
    }

    func activeWager(on day: String) -> HabitEvent? {
        events.filter { $0.kind == "wager" && $0.day <= day && !has("wager-reward/\($0.day)") }
            .max { $0.day < $1.day }
    }

    func league(activities: [DailyLearningActivity], now: Date = Date(), calendar: Calendar = .current) -> HabitLeague {
        let start = weekStart(for: now, calendar: calendar)
        let key = LearningCalendar.dateKey(for: start, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
        let endKey = LearningCalendar.dateKey(for: end, calendar: calendar)
        let tier = events.filter { $0.kind == "league-result" }.sorted { $0.day < $1.day }.reduce(0) { min(4, max(0, $0 + Int($1.value))) }
        return .init(tier: tier, targetMinutes: events.first { $0.id == "league-target/\(key)" }?.value ?? 75,
                     minutes: activityMinutes(activities: activities, from: key, to: endKey),
                     activeDays: learningDays(activities: activities).filter { $0 >= key && $0 < endKey }.count,
                     history: previousWeeks(activities: activities, before: start, calendar: calendar))
    }

    func activityMinutes(activities: [DailyLearningActivity], from start: String, to end: String) -> Double {
        var totals = Dictionary(activities.map { ($0.dateKey, $0.watchedSeconds) }, uniquingKeysWith: max)
        for (key, seconds) in playbackByDay { totals[key] = max(totals[key] ?? 0, seconds) }
        return totals.filter { $0.key >= start && $0.key < end }.values.reduce(0, +) / 60
    }

    private func previousWeeks(activities: [DailyLearningActivity], before start: Date, calendar: Calendar) -> [(String, Double)] {
        (1...4).compactMap { offset in
            guard let from = calendar.date(byAdding: .day, value: -7 * offset, to: start),
                  let to = calendar.date(byAdding: .day, value: 7, to: from) else { return nil }
            let key = LearningCalendar.dateKey(for: from, calendar: calendar)
            return (key, activityMinutes(activities: activities, from: key, to: LearningCalendar.dateKey(for: to, calendar: calendar)))
        }
    }

    private func weekStart(for date: Date, calendar: Calendar) -> Date {
        var monday = calendar; monday.firstWeekday = 2; monday.minimumDaysInFirstWeek = 4
        return monday.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    mutating func merge(_ remote: [HabitEvent]) {
        var byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.value >= b.value ? a : b })
        for item in remote where item.value.isFinite {
            if let old = byID[item.id] {
                if ["playback", "boost-use"].contains(item.kind) { byID[item.id] = old.value >= item.value ? old : item }
                else { byID[item.id] = item }
            } else { byID[item.id] = item }
        }
        events = byID.values.sorted { $0.id < $1.id }
    }
}

struct HabitReminderExposure: Codable, Sendable {
    var id: String
    var day: String
    var template: Int
    var fireTime: Date
    var baselineSeconds: Double = 0
    var completed = false
}

