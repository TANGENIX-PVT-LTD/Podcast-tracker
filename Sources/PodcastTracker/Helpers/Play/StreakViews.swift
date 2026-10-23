import SwiftUI

extension AppViewModel {
    /// After 6pm with an unprotected live streak: loss-aversion moment, never shown when there's nothing to lose.
    var streakAtRisk: Bool {
        !streakProtectedToday && stats.currentStreak > 0 && Calendar.current.component(.hour, from: Date()) >= 18
    }

    var flameState: StreakFlame.State {
        if streakProtectedToday { return .lit }
        if stats.currentStreak == 0 { return .ash }
        return streakAtRisk ? .dim : .lit
    }

    var dailyGoalProgress: Double {
        let day = LearningCalendar.dateKey(for: Date())
        let goal = habitLoop.goalSeconds(on: day, fallback: habitSettings.currentDailyGoalMinutes * 60)
        return min(1, habitLoop.learnedSeconds(on: day) / max(60, goal))
    }

    var weekStrip: [StreakDay] { habitLoop.weekStrip(activities: activities) }

    var levelProgress: Double {
        let level = stats.currentLevel
        guard level.xpToNext > 0 else { return 1 }
        return min(1, Double(stats.totalXP - level.minXP) / Double(level.xpToNext))
    }

    var xpToNextLevel: Int {
        let level = stats.currentLevel
        return max(0, level.minXP + level.xpToNext - stats.totalXP)
    }
}

/// Level identity card: badge ring, title, XP bar to the next title.
struct LevelCard: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        let level = viewModel.stats.currentLevel
        HStack(spacing: 14) {
            PlayRing(value: viewModel.levelProgress, tint: Play.Palette.gold, lineWidth: 7) {
                Image(systemName: level.iconName).font(.system(size: 22, weight: .black)).foregroundStyle(Play.Palette.gold.gradient)
            }
            .frame(width: 62, height: 62)
            VStack(alignment: .leading, spacing: 5) {
                Text("LEVEL \(level.number)").font(Play.rounded(12, .heavy)).tracking(0.8).foregroundStyle(Play.Palette.goldLip)
                Text(level.title).font(Play.rounded(20, .black))
                Text(level.xpToNext > 0 ? "\(viewModel.xpToNextLevel) XP to \(Level.levels[min(Level.levels.count - 1, level.number)].title)" : "Top level reached")
                    .font(Play.rounded(13, .bold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(viewModel.stats.totalXP)").font(Play.rounded(22, .black)).foregroundStyle(Play.Palette.goldLip).contentTransition(.numericText())
                Text("total XP").font(Play.rounded(12, .bold)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .chunkyCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }
}

struct WeekStripView: View {
    var days: [StreakDay]
    var compact = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            ForEach(days) { day in
                VStack(spacing: 5) {
                    Text(day.letter).font(Play.rounded(compact ? 11 : 13, .bold))
                        .foregroundStyle(day.state == .today || day.state == .todayDone ? Play.Palette.flame : .secondary)
                    cell(day).frame(width: compact ? 26 : 34, height: compact ? 26 : 34)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(day))
            }
        }
    }

    @ViewBuilder private func cell(_ day: StreakDay) -> some View {
        let empty = scheme == .dark ? Color.white.opacity(0.10) : Color(hex: 0xE5E5E5)
        switch day.state {
        case .done, .todayDone:
            Circle().fill(Play.Palette.flame.gradient)
                .overlay(Image(systemName: "checkmark").font(.system(size: compact ? 11 : 14, weight: .black)).foregroundStyle(.white))
                .overlay(Circle().strokeBorder(Play.Palette.flameDeep.opacity(0.35), lineWidth: 2))
                .transition(.scale(scale: 0.2).combined(with: .opacity))
        case .frozen:
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Play.Palette.ice.gradient)
                .overlay(Image(systemName: "snowflake").font(.system(size: compact ? 11 : 14, weight: .bold)).foregroundStyle(.white))
                .rotationEffect(.degrees(8))
        case .today:
            // Time-driven pulse: repeatForever animations leak into parent transitions.
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                let pulse = reduceMotion ? 0 : sin(context.date.timeIntervalSinceReferenceDate * 3.5)
                Circle().strokeBorder(Play.Palette.flame, style: StrokeStyle(lineWidth: 3, dash: [5, 4]))
                    .scaleEffect(1 + 0.07 * pulse)
            }
        case .missed:
            Circle().fill(empty).overlay(Image(systemName: "xmark").font(.system(size: compact ? 9 : 11, weight: .bold)).foregroundStyle(.secondary.opacity(0.6)))
        case .future:
            Circle().fill(empty)
        }
    }

    private func label(_ day: StreakDay) -> String {
        switch day.state {
        case .done, .todayDone: "\(day.id), learned"
        case .frozen: "\(day.id), protected by a freeze"
        case .today: "Today, not yet learned"
        case .missed: "\(day.id), missed"
        case .future: "\(day.id), upcoming"
        }
    }
}

/// The hero streak card: flame, rolling count, week strip, goal bar and an at-risk state.
struct StreakHero: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onOpen: () -> Void = {}
    @State private var introCount: Int?
    @State private var flameHop = 0
    /// The hero counts up once per launch, so opening the app feels like the streak "turns on".
    @MainActor private static var introPlayed = false

    var body: some View {
        let risk = viewModel.streakAtRisk
        let count = viewModel.stats.currentStreak
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: !risk || reduceMotion)) { context in
                        StreakFlame(state: viewModel.flameState, size: 66)
                            .scaleEffect(risk && !reduceMotion ? 1 + 0.05 * sin(context.date.timeIntervalSinceReferenceDate * 4.5) : 1)
                    }
                    .hop(flameHop, height: 12)
                    VStack(alignment: .leading, spacing: 0) {
                        RollingNumber(value: introCount ?? count, font: Play.rounded(42, .black), digitHeight: 46,
                                      color: viewModel.flameState == .ash ? Play.Palette.ash : Play.Palette.flame)
                            .frame(height: 46)
                        Text("day streak").font(Play.rounded(15, .bold)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 4) {
                            ForEach(0..<2, id: \.self) { index in
                                Image(systemName: "snowflake").font(.system(size: 13, weight: .black))
                                    .foregroundStyle(index < viewModel.habitStreakStatus.freezes ? Play.Palette.iceDeep : Color.secondary.opacity(0.3))
                                    .frame(width: 24, height: 24)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(index < viewModel.habitStreakStatus.freezes ? Play.Palette.ice.opacity(0.3) : Color.secondary.opacity(0.08)))
                            }
                        }
                        .accessibilityLabel("\(viewModel.habitStreakStatus.freezes) of 2 streak freezes")
                        Text(statusLine).font(Play.rounded(13, .bold))
                            .foregroundStyle(risk ? Play.Palette.error : viewModel.streakProtectedToday ? Play.Palette.success : .secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                WeekStripView(days: viewModel.weekStrip)
                VStack(alignment: .leading, spacing: 6) {
                    PlayProgressBar(value: viewModel.dailyGoalProgress, tint: viewModel.streakProtectedToday ? Play.Palette.success : Play.Palette.flame, height: 14)
                    HStack {
                        Text("\(viewModel.todayWatchedMinutes) / \(Int(viewModel.habitSettings.currentDailyGoalMinutes)) min today")
                        Spacer()
                        let next = StreakMilestones.next(after: count)
                        Text("\(next - count) to \(next)-day badge")
                    }
                    .font(Play.rounded(12, .bold)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChunkyTileStyle(selected: risk, tint: risk ? Play.Palette.error : nil, cornerRadius: 22))
        .accessibilityLabel("\(count)-day streak. \(statusLine). Open streak details.")
        .task {
            guard !Self.introPlayed, !reduceMotion, count > 0 else { return }
            Self.introPlayed = true
            introCount = 0
            await Choreo.run([
                .at(0.35, .land, sound: false) { introCount = nil },
                .at(0.62, .pop, sound: false, intensity: 0.7) { flameHop += 1 }
            ])
        }
        .onChange(of: count) { old, new in if new > old { flameHop += 1 } }
    }

    private var statusLine: String {
        if viewModel.streakProtectedToday { return "Safe today" }
        if viewModel.streakAtRisk { return "Save it · \(viewModel.todayRemainingMinutes) min" }
        if viewModel.stats.currentStreak == 0 { return "Light it today" }
        return "\(viewModel.todayRemainingMinutes) min to go"
    }
}

/// Full streak page: hero, calendar, freezes, milestone ladder and a personal streak goal.
struct StreakDetailView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("play.streakGoal") private var streakGoal = 0
    @AppStorage("play.streakGoalStart") private var streakGoalStart = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    let count = viewModel.stats.currentStreak
                    VStack(spacing: 6) {
                        StreakFlame(state: viewModel.flameState, size: 120)
                        OdometerText(value: count, font: Play.rounded(64, .black))
                        Text("day streak").font(Play.rounded(18, .bold)).foregroundStyle(.secondary)
                        Text("Longest: \(viewModel.stats.longestStreak) days").font(Play.rounded(14, .bold)).foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    EchoSays(mood: viewModel.streakAtRisk ? .worried : viewModel.streakProtectedToday ? .proud : .happy, text: EchoLines.streakDetail(viewModel), size: 72)

                    section("This week") { WeekStripView(days: viewModel.weekStrip) }

                    section("Next milestone") {
                        let next = StreakMilestones.next(after: count), previous = StreakMilestones.previous(before: count)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "rosette").foregroundStyle(Play.Palette.gold.gradient).font(.title2.bold())
                                Text("\(next)-day badge").font(Play.rounded(17, .heavy))
                                Spacer()
                                Text("\(next - count) to go").font(Play.rounded(14, .bold)).foregroundStyle(.secondary)
                            }
                            // Endowed progress: measure from the last milestone so the bar is never empty.
                            PlayProgressBar(value: Double(count - previous) / Double(max(1, next - previous)), tint: Play.Palette.gold)
                            HStack(spacing: 6) {
                                ForEach(StreakMilestones.all, id: \.self) { milestone in
                                    Text("\(milestone)").font(Play.rounded(12, .heavy))
                                        .foregroundStyle(count >= milestone ? .white : .secondary)
                                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                                        .background(Capsule().fill(count >= milestone ? AnyShapeStyle(Play.Palette.gold.gradient) : AnyShapeStyle(Color.secondary.opacity(0.12))))
                                }
                            }
                        }
                    }

                    section("Streak goal") {
                        if streakGoal > 0 {
                            let reached = max(0, count - streakGoalStart)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(count >= streakGoal ? "Goal smashed: \(streakGoal) days!" : "Committed to \(streakGoal) days").font(Play.rounded(17, .heavy))
                                PlayProgressBar(value: Double(min(count, streakGoal)) / Double(streakGoal), tint: Play.Palette.flame)
                                Text("\(min(count, streakGoal)) of \(streakGoal) days · \(reached) since you committed").font(Play.rounded(13, .bold)).foregroundStyle(.secondary)
                                if count >= streakGoal { Button("Set a bigger goal") { streakGoal = 0 }.buttonStyle(.chunky(.flame, size: .small)) }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("People who commit to a streak goal are far more likely to keep going. Pick yours.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                HStack(spacing: 10) {
                                    ForEach([7, 14, 30, 50], id: \.self) { goal in
                                        Button("\(goal)") {
                                            streakGoal = max(goal, count + 1); streakGoalStart = count
                                            PlayFeedback.play(.success); PlayFeedback.sound("pop")
                                        }.buttonStyle(.chunky(goal == 14 ? .flame : .secondary, size: .small))
                                    }
                                }
                                Text("days").font(Play.rounded(12, .bold)).foregroundStyle(.secondary)
                            }
                        }
                    }

                    section("Streak freezes") {
                        HStack(spacing: 14) {
                            ForEach(0..<2, id: \.self) { index in
                                let owned = index < viewModel.habitStreakStatus.freezes
                                Image(systemName: "snowflake").font(.system(size: 26, weight: .black)).foregroundStyle(owned ? .white : .secondary.opacity(0.4))
                                    .frame(width: 56, height: 56)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(owned ? AnyShapeStyle(Play.Palette.ice.gradient) : AnyShapeStyle(Color.secondary.opacity(0.1))))
                                    .rotationEffect(.degrees(index == 0 ? -6 : 6))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(viewModel.habitStreakStatus.freezes)/2 equipped").font(Play.rounded(16, .heavy))
                                Text("A freeze covers a missed day automatically. Every 7 learning days refills one.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if viewModel.habitStreakStatus.freezes < 2 {
                            Button("Refill a freeze · 100 gems") { viewModel.purchaseHabitItem("freeze") }
                                .buttonStyle(.chunky(.gem, size: .small)).disabled(viewModel.habitLoop.gems < 100)
                                .padding(.top, 6)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(ThemeBackdrop())
            .navigationTitle("Streak")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 640)
        #endif
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(Play.rounded(13, .heavy)).tracking(0.8).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .chunkyCard()
    }
}
