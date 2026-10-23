import SwiftUI

/// Native sheet behind the flame: big count, this week, the month, streak goal, freezes, milestones.
struct IOSStreakSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("play.streakGoal") private var streakGoal = 0
    @AppStorage("play.streakGoalStart") private var streakGoalStart = 0
    @State private var month = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    IOSSection("This week") { IOSWeekStrip(days: viewModel.weekStrip).padding(16).outlined(20) }
                    IOSSection("Calendar") { calendar }
                    IOSSection("Streak goal") { goal }
                    IOSSection("Streak freezes") { freezes }
                    IOSSection("Milestones") { milestones }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
    }

    private var hero: some View {
        let count = viewModel.stats.currentStreak
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(viewModel.flameState == .ash ? Color.secondary : Play.Palette.flame)
                    .contentTransition(.numericText())
                Text("day streak").font(.title3.bold()).foregroundStyle(viewModel.flameState == .ash ? Color.secondary : Play.Palette.flame)
                Text(EchoLines.streakDetail(viewModel)).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
            Spacer(minLength: 0)
            StreakFlame(state: viewModel.flameState, size: 108)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var calendar: some View {
        VStack(spacing: 12) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button("Previous month", systemImage: "chevron.left") { shift(-1) }.labelStyle(.iconOnly)
                Button("Next month", systemImage: "chevron.right") { shift(1) }.labelStyle(.iconOnly)
            }
            let learned = viewModel.habitLoop.learningDays(activities: viewModel.activities)
            let frozen = viewModel.habitStreakStatus.frozenDays
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
                ForEach(Array(Calendar.current.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let key = LearningCalendar.dateKey(for: date)
                        ZStack {
                            if learned.contains(key) { Circle().fill(Play.Palette.flame) }
                            else if frozen.contains(key) { Circle().fill(Play.Palette.ice) }
                            else if Calendar.current.isDateInToday(date) { Circle().strokeBorder(Play.Palette.flame, lineWidth: 2) }
                            Text("\(Calendar.current.component(.day, from: date))").font(.footnote.weight(learned.contains(key) || frozen.contains(key) ? .bold : .regular))
                                .foregroundStyle(learned.contains(key) || frozen.contains(key) ? Color.white : Color.primary)
                        }
                        .frame(width: 34, height: 34)
                    } else { Color.clear.frame(height: 34) }
                }
            }
        }
        .padding(16)
        .outlined(20)
    }

    private var days: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let blanks = Array<Date?>(repeating: nil, count: calendar.component(.weekday, from: interval.start) - 1)
        return blanks + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }.map(Optional.some)
    }

    private func shift(_ value: Int) { month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month }

    @ViewBuilder private var goal: some View {
        let count = viewModel.stats.currentStreak
        if streakGoal > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text(count >= streakGoal ? "Goal smashed: \(streakGoal) days" : "Committed to \(streakGoal) days").font(.headline)
                IOSQuestBar(value: Double(min(count, streakGoal)) / Double(streakGoal), label: "\(min(count, streakGoal)) / \(streakGoal)", tint: Play.Palette.flame)
                if count >= streakGoal { Button("Set a bigger goal") { streakGoal = 0 }.font(.subheadline.weight(.semibold)) }
            }
            .padding(16).outlined(20)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("People who commit to a goal keep their streaks far longer. Pick yours.").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach([7, 14, 30, 50], id: \.self) { days in
                        Button("\(days) days") {
                            streakGoal = max(days, count + 1); streakGoalStart = count
                            PlayFeedback.play(.success); PlayFeedback.sound("pop")
                        }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                        .tint(Play.Palette.flame)
                    }
                }
            }
            .padding(16).outlined(20)
        }
    }

    private var freezes: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { index in
                    let owned = index < viewModel.habitStreakStatus.freezes
                    Image(systemName: "snowflake").font(.title3.weight(.bold))
                        .foregroundStyle(owned ? Color.white : Color(.systemGray3))
                        .frame(width: 40, height: 40)
                        .background(owned ? Play.Palette.ice : Color(.systemGray6), in: .rect(cornerRadius: 10, style: .continuous))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.habitStreakStatus.freezes) of 2 equipped").font(.headline)
                Text("Covers a missed day automatically. Refills every 7 learning days.").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16).outlined(20)
    }

    private var milestones: some View {
        let count = viewModel.stats.currentStreak
        let next = StreakMilestones.next(after: count), previous = StreakMilestones.previous(before: count)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(next)-day badge").font(.headline)
                Spacer()
                Text("\(next - count) to go").font(.subheadline).foregroundStyle(.secondary)
            }
            IOSQuestBar(value: Double(count - previous) / Double(max(1, next - previous)), label: "\(count) / \(next)", tint: Play.Palette.gold)
            HStack(spacing: 6) {
                ForEach(StreakMilestones.all, id: \.self) { milestone in
                    Text("\(milestone)").font(.caption.weight(.heavy))
                        .foregroundStyle(count >= milestone ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(count >= milestone ? Play.Palette.gold : Color(.systemGray6), in: Capsule())
                }
            }
        }
        .padding(16).outlined(20)
    }
}

/// Native sheet for quests, the chest, the shop, the league and recall reviews.
struct IOSQuestsSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var review: RecallReview?
    @State private var reviewStage = 0

    private var day: String { LearningCalendar.dateKey(for: Date()) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    quest(1, "Learn for 5 minutes", "headphones", Play.Palette.gem, min(1, viewModel.habitLoop.learnedSeconds(on: day) / 300))
                    quest(2, "Hit today's goal", "target", Play.Palette.flame, viewModel.dailyGoalProgress)
                    quest(3, "Recall or save a takeaway", "lightbulb.fill", Play.Palette.purple, viewModel.habitLoop.has("reflection/\(day)") ? 1 : 0)
                } header: { Text("Daily quests") } footer: {
                    Text(viewModel.habitLoop.has("chest/\(day)") ? "Today's chest is open." : "Finish all three to open today's chest: 5–20 gems and 15 minutes of double XP.")
                }

                Section("League") {
                    let league = viewModel.habitLeague
                    LabeledContent("\(league.title) league") {
                        Text("\(Int(league.minutes)) / \(Int(league.targetMinutes)) min").monospacedDigit()
                    }
                    LabeledContent("Active days", value: "\(league.activeDays) / 5")
                    Text("Meet both targets by Sunday to promote. Reach 60% of the minutes to hold your tier.").font(.footnote).foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("Gems") { Label("\(viewModel.habitLoop.gems)", systemImage: "diamond.fill").foregroundStyle(Play.Palette.gem) }
                    Button { viewModel.purchaseHabitItem("freeze") } label: {
                        LabeledContent("Refill a streak freeze") { Label("100", systemImage: "diamond.fill") }
                    }
                    .disabled(viewModel.habitLoop.gems < 100 || viewModel.habitStreakStatus.freezes >= 2)
                    Button { viewModel.purchaseHabitItem("wager") } label: {
                        LabeledContent("Seven-day promise") { Label("20", systemImage: "diamond.fill") }
                    }
                    .disabled(viewModel.habitLoop.gems < 20)
                } header: { Text("Shop") } footer: {
                    Text("A promise returns 40 gems after seven learning days in a row. Purchases sync with your account.")
                }

                Section("Recall") {
                    ForEach(viewModel.habitLoop.reviews) { cached in
                        if let stage = cached.dueStage(on: day) {
                            Button("Review \(viewModel.podcasts.first { $0.id == cached.podcastID }?.title ?? "episode")") {
                                reviewStage = stage; review = cached
                            }
                        }
                    }
                    if let podcast = viewModel.nextPodcast ?? viewModel.podcasts.first {
                        Button(viewModel.recallBusy ? "Preparing questions…" : "Create a review for \(podcast.title)") { viewModel.generateRecall(for: podcast) }
                            .disabled(viewModel.recallBusy || viewModel.habitLoop.reviews.contains { $0.podcastID == podcast.id })
                    }
                }

                if !viewModel.habitLoop.badges.isEmpty {
                    Section("Badges") {
                        ForEach(viewModel.habitLoop.badges.prefix(12)) { badge in
                            Label(badge.detail, systemImage: "rosette").foregroundStyle(Play.Palette.goldLip)
                        }
                    }
                }
                if let message = viewModel.habitMessage { Section { Text(message).font(.footnote) } }
            }
            .navigationTitle("Quests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fullScreenCover(item: $review) { value in
                PlayQuizView(title: reviewStage == 0 ? "First recall" : "Day \(reviewStage) review", questions: value.questions) { correct in
                    viewModel.finishRecall(reviewID: value.id, stage: reviewStage, correct: correct)
                    review = nil
                } onClose: { review = nil }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func quest(_ number: Int, _ title: String, _ symbol: String, _ color: Color, _ progress: Double) -> some View {
        let done = viewModel.habitLoop.has("quest/\(day)/\(number)/xp")
        return HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3.weight(.bold)).foregroundStyle(color).frame(width: 30)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold))
                IOSQuestBar(value: done ? 1 : progress, label: done ? "Done · +10 XP" : "+10 XP", tint: done ? Play.Palette.success : Play.Palette.gold)
            }
        }
        .padding(.vertical, 4)
    }
}
