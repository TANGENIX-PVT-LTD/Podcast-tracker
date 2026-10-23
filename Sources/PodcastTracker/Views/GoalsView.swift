import SwiftUI

struct LearningProgressView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var displayedMonth = Date()
    @State private var showScheduleSheet = false
    @State private var showStreak = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your progress").font(Play.rounded(34, .black))
                    Text("Minutes first. XP and levels are supporting signals.").foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 18) {
                    StreakHero { showStreak = true }
                    VStack(spacing: 18) { LevelCard(); LeagueCard() }
                }
                calendar
                goals
                ReplacementReview()
                AchievementsView()
            }.padding(28).frame(maxWidth: 1080, alignment: .leading)
        }
        .sheet(isPresented: $showStreak) { StreakDetailView() }
        .sheet(isPresented: $showScheduleSheet) {
            ScheduleDaySheet(day: viewModel.selectedCalendarDate).environmentObject(viewModel)
        }
    }

    private var calendar: some View {
        VStack(spacing: 16) {
            HStack {
                Text(displayedMonth.formatted(.dateTime.month(.wide).year())).font(Play.rounded(22, .heavy))
                Spacer()
                Button("Previous Month", systemImage: "chevron.left") { shiftMonth(-1) }.labelStyle(.iconOnly)
                Button("Today") { displayedMonth = Date(); viewModel.selectedCalendarDate = Date() }
                Button("Next Month", systemImage: "chevron.right") { shiftMonth(1) }.labelStyle(.iconOnly)
            }
            MonthGrid(
                month: displayedMonth,
                selection: $viewModel.selectedCalendarDate,
                learned: viewModel.habitLoop.learningDays(activities: viewModel.activities),
                frozen: viewModel.habitStreakStatus.frozenDays,
                scheduledDates: viewModel.podcasts.compactMap(\.scheduledAt)
            )
            if let day = viewModel.activity(for: viewModel.selectedCalendarDate) {
                HStack(spacing: 24) {
                    Label("\(Int(day.watchedSeconds / 60)) minutes", systemImage: "timer")
                    Label("\(day.sessions) sessions", systemImage: "play.circle")
                    Label("\(day.xpEarned) XP", systemImage: "sparkles")
                    Label("\(day.completedPodcastIDs.count) completed", systemImage: "checkmark.circle")
                }.font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No recorded activity on this day.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Text("Scheduled").font(.headline)
                Spacer()
                Button("Add Podcast", systemImage: "calendar.badge.plus") { showScheduleSheet = true }
                    .buttonStyle(.chunky(.secondary, size: .small, fullWidth: false))
            }
            let scheduled = viewModel.scheduledPodcasts(on: viewModel.selectedCalendarDate)
            if scheduled.isEmpty {
                Text("Nothing scheduled for this day.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(scheduled) { podcast in
                    HStack {
                        Image(systemName: "play.rectangle")
                        VStack(alignment: .leading) {
                            Text(podcast.title).lineLimit(1)
                            if let date = podcast.scheduledAt {
                                Text(date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Open") { viewModel.selectPodcast(podcast) }.buttonStyle(.chunky(.secondary, size: .small, fullWidth: false))
                        Button("Remove Schedule", systemImage: "xmark") { viewModel.removeSchedule(for: podcast) }
                            .labelStyle(.iconOnly).buttonStyle(.chunky(.secondary, size: .small, fullWidth: false))
                    }
                }
            }
        }.padding(20).chunkyCard(cornerRadius: 20)
    }

    private var goals: some View {
        HStack(spacing: 16) {
            GoalCard(title: "Daily", value: viewModel.habitLoop.learnedSeconds(on: LearningCalendar.dateKey(for: Date())), target: viewModel.habitSettings.currentDailyGoalMinutes * 60, label: "\(viewModel.todayWatchedMinutes) / \(Int(viewModel.habitSettings.currentDailyGoalMinutes)) min")
            GoalCard(title: "Weekly", value: viewModel.stats.weeklySecondsWatched, target: viewModel.stats.weeklyGoalHours * 3600, label: "\(viewModel.stats.formattedWeeklyTime) / \(viewModel.stats.weeklyGoalHours.formatted())h")
        }
    }

    private func shiftMonth(_ value: Int) { displayedMonth = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth }
}

private struct ReplacementReview: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private var insights: RescueInsights { viewModel.weeklyRescueInsights }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Distraction replacement", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.title2.bold())
                    Text("A private, local view of whether Rescue is changing the behavior that matters.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Rescue Me", systemImage: "bolt.fill") { viewModel.showRescueSheet = true }
                    .buttonStyle(.chunky(.primary, size: .small, fullWidth: false))
                    .disabled(viewModel.nextPodcast == nil)
            }

            HStack(spacing: 0) {
                insightMetric("Rescues completed", value: "\(insights.completed)")
                Divider().frame(height: 38).padding(.horizontal, 20)
                insightMetric("Minutes reclaimed", value: "\(insights.reclaimedMinutes)")
                Divider().frame(height: 38).padding(.horizontal, 20)
                insightMetric("Promises kept", value: completionLabel)
                Spacer()
            }

            if let cue = insights.leadingCue {
                Label("Biggest pull this week: \(cue.title)", systemImage: cue.symbolName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(insights.coachingMessage)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(20)
        .background(.quaternary.opacity(0.28), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private var completionLabel: String {
        guard let rate = insights.completionRate else { return "—" }
        return rate.formatted(.percent.precision(.fractionLength(0)))
    }

    private func insightMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct GoalCard: View {
    let title: String; let value: Double; let target: Double; let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(Play.rounded(13, .heavy)).tracking(0.8).foregroundStyle(.secondary)
            PlayProgressBar(value: min(value / max(target, 1), 1), tint: title == "Daily" ? Play.Palette.flame : Play.Palette.gem, height: 12)
            Text(label).font(Play.rounded(14, .bold))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).chunkyCard(cornerRadius: 18)
    }
}

private struct MonthGrid: View {
    let month: Date
    @Binding var selection: Date
    let learned: Set<String>
    let frozen: Set<String>
    let scheduledDates: [Date]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private var days: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let blanks = Array<Date?>(repeating: nil, count: weekday - 1)
        return blanks + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }.map(Optional.some)
    }
    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { Text($0.uppercased()).font(Play.rounded(11, .heavy)).foregroundStyle(.secondary) }
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date { dayButton(date) } else { Color.clear.frame(height: 40) }
            }
        }
    }
    private func dayButton(_ date: Date) -> some View {
        let key = LearningCalendar.dateKey(for: date)
        return Button { selection = date; PlayFeedback.play(.select, sound: false) } label: {
            PlayCalendarDay(day: Calendar.current.component(.day, from: date), learned: learned.contains(key), frozen: frozen.contains(key),
                            scheduled: scheduledDates.contains { Calendar.current.isDate($0, inSameDayAs: date) },
                            selected: Calendar.current.isDate(date, inSameDayAs: selection), isToday: Calendar.current.isDateInToday(date))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }
}
