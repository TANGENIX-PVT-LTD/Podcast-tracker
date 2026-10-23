import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ScrollView {
            let line = EchoLines.today(viewModel)
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                        .font(Play.rounded(13, .heavy)).tracking(0.8).foregroundStyle(.secondary)
                    EchoSays(mood: line.mood, text: line.text, size: 96)
                }
                .staggered(0, appeared)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 18) { primaryColumn }.frame(minWidth: 460)
                        VStack(alignment: .leading, spacing: 18) { secondaryColumn }.frame(width: 380)
                    }
                    VStack(alignment: .leading, spacing: 18) { primaryColumn; secondaryColumn }
                }
            }
            .padding(28)
            .frame(maxWidth: 1180, alignment: .leading)
        }
        .onAppear { withAnimation(Play.Motion.or(Play.Motion.gentle, reduceMotion: reduceMotion)) { appeared = true } }
    }

    @ViewBuilder private var primaryColumn: some View {
        HabitLoopPanel().staggered(1, appeared)
        if let next = viewModel.nextPodcast { nextEpisode(next).staggered(2, appeared) }
        else {
            VStack(spacing: 14) {
                EchoView(mood: .happy, size: 110)
                Text("Build your learning queue").font(Play.rounded(22, .heavy))
                Button("Add your first episode", systemImage: "plus") { viewModel.showAddPodcast = true }.buttonStyle(.chunky(.primary, fullWidth: false))
            }
            .frame(maxWidth: .infinity).padding(24).chunkyCard(cornerRadius: 22).staggered(2, appeared)
        }
        rescueCard.staggered(3, appeared)
    }

    @ViewBuilder private var secondaryColumn: some View {
        LevelCard().staggered(2, appeared)
        LeagueCard().staggered(3, appeared)
        recentActivity.staggered(4, appeared)
    }

    private var rescueCard: some View {
        let insights = viewModel.weeklyRescueInsights
        return HStack(spacing: 16) {
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Play.Palette.flame.gradient))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("About to waste time?").font(Play.rounded(17, .heavy))
                Text(insights.attempts > 0 ? "\(insights.completed) kept · \(insights.reclaimedMinutes) min reclaimed this week" : "Name the impulse. Replace it with one small learning win.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Rescue me", systemImage: "bolt.fill") { viewModel.showRescueSheet = true }
                .buttonStyle(.chunky(.flame, size: .small, fullWidth: false))
                .disabled(viewModel.nextPodcast == nil)
        }
        .padding(16)
        .chunkyCard(cornerRadius: 20)
    }

    private func nextEpisode(_ podcast: Podcast) -> some View {
        HStack(spacing: 20) {
            AsyncImage(url: podcast.thumbnailURL.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() }
                placeholder: { Rectangle().fill(.quaternary).overlay { Image(systemName: "play.rectangle") } }
                .frame(width: 210, height: 118).clipShape(.rect(cornerRadius: 14))
                .overlay(alignment: .topLeading) {
                    Text(podcast.hasProgress ? "CONTINUE" : "UP NEXT").font(Play.rounded(11, .heavy)).tracking(0.6).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Play.themeTint)).padding(8)
                }
            VStack(alignment: .leading, spacing: 10) {
                Text(podcast.title).font(Play.rounded(20, .heavy)).lineLimit(2)
                if podcast.hasProgress { PlayProgressBar(value: podcast.progressPercentage, tint: Play.themeTint, height: 10, showsGlow: false) }
                HStack(spacing: 12) {
                    Button(podcast.hasProgress ? "Continue learning" : "Start learning", systemImage: "play.fill") {
                        if viewModel.todayRemainingMinutes > 0 {
                            viewModel.prepareCommitment(for: podcast, minutes: viewModel.todayRemainingMinutes, cue: .today, launchIntent: .explicitUserAction)
                        } else { viewModel.selectPodcast(podcast) }
                    }
                    .buttonStyle(.chunky(viewModel.streakAtRisk ? .flame : .primary, size: .small, fullWidth: false))
                    Text(viewModel.streakProtectedToday ? "Daily goal complete" : "\(viewModel.todayRemainingMinutes) min to today’s goal")
                        .font(Play.rounded(13, .bold)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .chunkyCard(cornerRadius: 22)
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent activity").font(Play.rounded(20, .heavy))
            if viewModel.activities.isEmpty { Text("Your accurate daily history begins here.").foregroundStyle(.secondary) }
            let learned = viewModel.habitLoop.learningDays(activities: viewModel.activities)
            ForEach(viewModel.activities.sorted { $0.dateKey > $1.dateKey }.prefix(5)) { day in
                let done = learned.contains(day.dateKey)
                HStack(spacing: 10) {
                    Image(systemName: done ? "flame.fill" : "moon.zzz.fill").font(.system(size: 13, weight: .black)).foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(done ? AnyShapeStyle(Play.Palette.flame.gradient) : AnyShapeStyle(Play.Palette.ash)))
                    Text(LearningCalendar.date(from: day.dateKey)?.formatted(date: .abbreviated, time: .omitted) ?? day.dateKey).font(Play.rounded(14, .bold))
                    Spacer()
                    Text("\(Int(max(day.watchedSeconds, viewModel.habitLoop.learnedSeconds(on: day.dateKey)) / 60)) min").foregroundStyle(.secondary)
                    Text("+\(day.xpEarned) XP").font(Play.rounded(13, .heavy)).foregroundStyle(Play.Palette.goldLip)
                }
            }
        }
        .padding(16)
        .chunkyCard(cornerRadius: 20)
    }
}


struct DistractionRescueSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cue: DistractionCue = .scrolling
    @State private var minutes = 5

    var body: some View {
        NavigationStack {
            Form {
                Section("What is pulling you away?") {
                    Picker("Distraction", selection: $cue) {
                        ForEach(DistractionCue.rescueChoices) { item in
                            Label(item.title, systemImage: item.symbolName).tag(item)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .accessibilityHint("This only personalizes your rescue history and reminders")
                }

                Section("Make the smallest promise you will keep") {
                    Picker("Learning block", selection: $minutes) {
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("20 min").tag(20)
                    }
                    .pickerStyle(.segmented)
                }

                if let podcast = viewModel.nextPodcast {
                    Section("Ready next") {
                        LabeledContent("Episode", value: podcast.title)
                        if podcast.hasProgress {
                            LabeledContent("Resume from", value: podcast.lastPlaybackPosition.formattedTime)
                        }
                    }
                }

                Text("The timer begins only when the video is actually playing. Pausing keeps your progress; it never fakes watch time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .navigationTitle("Distraction Rescue")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace It with \(minutes) Minutes", systemImage: "play.fill") {
                        viewModel.prepareRescue(cue: cue, minutes: minutes)
                    }
                    .buttonStyle(.chunky(.primary, size: .small, fullWidth: false))
                    .disabled(viewModel.nextPodcast == nil)
                }
            }
        }
        .frame(width: 560, height: 560)
    }
}
