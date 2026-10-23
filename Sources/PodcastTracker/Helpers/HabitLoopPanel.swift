import SwiftUI
#if os(iOS)
import FamilyControls
#endif

struct HabitLoopPanel: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var focus = FocusModeController.shared
    @State private var showFocus = false
    @State private var review: RecallReview?
    @State private var reviewStage = 0
    @State private var showDetails = false
    @State private var showRewards = false
    @State private var showStreak = false

    private var day: String { LearningCalendar.dateKey(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StreakHero { showStreak = true }
            HStack(spacing: 10) { questButton; Spacer(minLength: 4); actions }
            if let message = viewModel.habitMessage, !isWin(message) {
                HStack(alignment: .top) {
                    Text(message).font(.caption).accessibilityAddTraits(.updatesFrequently)
                    Spacer()
                    Button("Dismiss", systemImage: "xmark.circle") { viewModel.habitMessage = nil }.labelStyle(.iconOnly)
                }
                .padding(12).chunkyCard(cornerRadius: 14, lip: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .popover(isPresented: $showRewards) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Daily quests").font(Play.rounded(22, .heavy))
                        Spacer()
                        Button("Close", systemImage: "xmark") { showRewards = false }.labelStyle(.iconOnly)
                    }
                    questRows
                    if let message = viewModel.habitMessage { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                    DisclosureGroup("Rewards, reviews & your league", isExpanded: $showDetails) {
                        details.padding(.top, 12)
                        Text("Three quests earn a chest: 5/10/20 gems (60/30/10%) and a 15-minute playback XP boost.")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                    }
                }.padding(20)
            }
            #if os(macOS)
            .sheet(item: $review) { value in quiz(value) }
            .frame(width: 440, height: showDetails ? 620 : 420)
            #else
            .fullScreenCover(item: $review) { value in quiz(value) }
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.medium, .large])
            #endif
        }
        .sheet(isPresented: $showFocus) { FocusModeSettingsView() }
        .sheet(isPresented: $showStreak) { StreakDetailView() }
        .animation(reduceMotion ? nil : Play.Motion.gentle, value: viewModel.habitMessage)
        .onChange(of: viewModel.habitMessage) { _, message in
            guard !viewModel.showDailyCelebration, isWin(message), !(message?.hasPrefix("Daily chest") ?? false) else { return }
            PlayFeedback.play(.success, sound: false)
            PlayFeedback.sound("pop")
        }
    }

    private func quiz(_ value: RecallReview) -> some View {
        PlayQuizView(title: reviewStage == 0 ? "First recall" : "Day \(reviewStage) review", questions: value.questions) { correct in
            viewModel.finishRecall(reviewID: value.id, stage: reviewStage, correct: correct)
            review = nil
        } onClose: { review = nil }
    }

    private var questButton: some View {
        let done = viewModel.habitLoop.questCount(on: day)
        return Button { showRewards = true } label: {
            HStack(spacing: 10) {
                Image(systemName: done == 3 ? "gift.fill" : "scroll.fill").font(.system(size: 20, weight: .bold))
                    .foregroundStyle(done == 3 ? Play.Palette.gold.gradient : Play.Palette.flame.gradient)
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : done)
                VStack(alignment: .leading, spacing: 5) {
                    Text(done == 3 ? "All quests done!" : "\(3 - done) quest\(3 - done == 1 ? "" : "s") left today").font(Play.rounded(14, .heavy))
                    PlayProgressBar(value: Double(done) / 3, tint: Play.Palette.gold, height: 9, showsGlow: false).frame(width: 130)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
        .buttonStyle(ChunkyTileStyle(cornerRadius: 14))
        .fixedSize()
        .accessibilityLabel("\(done) of 3 daily quests complete")
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button { showFocus = true } label: {
                Image(systemName: focus.state.isLocked ? "lock.fill" : "lock.shield.fill").font(.system(size: 15, weight: .bold))
                    .padding(.horizontal, 2)
            }
            .buttonStyle(.chunky(.secondary, size: .small, fullWidth: false))
            .accessibilityLabel(focus.state.enabled ? (focus.state.isLocked ? "\(focus.state.remainingMinutes) minutes to unlock apps" : "Apps unlocked") : "Focus Mode")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var questRows: some View {
        let seconds = viewModel.habitLoop.learnedSeconds(on: day)
        let quests: [(String, String, Double)] = [
            ("Learn for five minutes", "headphones", min(1, seconds / 300)),
            ("Complete today’s goal", "target", viewModel.dailyGoalProgress),
            ("Recall or capture a takeaway", "lightbulb.fill", viewModel.habitLoop.has("reflection/\(day)") ? 1 : 0)
        ]
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(quests.enumerated()), id: \.offset) { index, quest in
                let complete = viewModel.habitLoop.has("quest/\(day)/\(index + 1)/xp")
                HStack(spacing: 12) {
                    Image(systemName: complete ? "checkmark" : quest.1).font(.system(size: 18, weight: .black))
                        .foregroundStyle(.white).frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(complete ? Play.Palette.success : Play.Palette.flame))
                        .symbolEffect(.bounce, options: .nonRepeating, value: complete && !reduceMotion)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(quest.0).font(Play.rounded(15, .bold))
                        PlayProgressBar(value: complete ? 1 : quest.2, tint: complete ? Play.Palette.success : Play.Palette.gold, height: 10, showsGlow: false)
                    }
                    Text(complete ? "Done" : "+10 XP").font(Play.rounded(12, .heavy)).foregroundStyle(complete ? Play.Palette.success : Play.Palette.goldLip)
                }
                .padding(12).chunkyCard(cornerRadius: 16, lip: 3)
                .accessibilityElement(children: .combine)
                .accessibilityValue(complete ? "Complete, 10 XP and 5 gems earned" : "Not complete, 10 XP and 5 gems available")
            }
            HStack(spacing: 10) {
                Image(systemName: "gift.fill").font(.title2).foregroundStyle(Play.Palette.gold.gradient)
                Text(viewModel.habitLoop.has("chest/\(day)") ? "Today’s chest is open" : "Finish all three to open today’s chest")
                    .font(Play.rounded(14, .bold)).foregroundStyle(.secondary)
            }
        }
    }

    private func isWin(_ message: String?) -> Bool {
        guard let message else { return false }
        return ["Quest complete", "Daily chest", "Review complete"].contains { message.hasPrefix($0) } || message.contains("-day streak protected")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            let league = viewModel.habitLeague
            Label("\(league.title) · your personal league", systemImage: "trophy.fill").font(Play.rounded(16, .heavy))
            Text("\(Int(league.minutes))/\(Int(league.targetMinutes)) minutes · \(league.activeDays)/5 active days")
            PlayProgressBar(value: min(1, league.minutes / max(1, league.targetMinutes)), tint: Play.Palette.gem, height: 12)
            Text("Meet both targets to promote. Reach 60% of the minutes to hold. Otherwise, drop one tier. Monday starts a new week.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(league.history, id: \.0) { row in
                HStack { Text("Your week of \(row.0)"); Spacer(); Text("\(Int(row.1)) min") }.font(.caption)
            }
            Divider()
            Text("\(viewModel.habitStreakStatus.freezes)/2 freezes · \(Int(viewModel.habitLoop.boostSeconds / 60)) boosted learning minutes left")
            HStack {
                Button("Refill freeze · 100") { viewModel.purchaseHabitItem("freeze") }
                    .buttonStyle(.chunky(.gem, size: .small, fullWidth: false))
                    .disabled(viewModel.habitLoop.gems < 100 || viewModel.habitStreakStatus.freezes >= 2)
                Button("7-day promise · 20") { viewModel.purchaseHabitItem("wager") }
                    .buttonStyle(.chunky(.flame, size: .small, fullWidth: false))
                    .disabled(viewModel.habitLoop.gems < 20 || wagerIsCurrent)
            }
            Text("Seven actual learning days return 40 gems. A missed day loses the 20-gem stake; freezes do not satisfy the promise. Purchases require account sync. Freezes never unlock apps.")
                .font(.caption).foregroundStyle(.secondary)
            if let wager = viewModel.habitLoop.events.filter({ $0.kind == "wager" }).max(by: { $0.day < $1.day }) {
                Text("Promise started \(wager.day) · \(viewModel.habitLoop.has("wager-reward/\(wager.day)") ? "Completed" : wagerIsCurrent ? "In progress" : "Ended")")
                    .font(.caption)
            }
            Divider()
            Text("Optional recall").font(Play.rounded(16, .heavy))
            ForEach(viewModel.habitLoop.reviews) { cached in
                if let stage = cached.dueStage(on: day) {
                    Button("Review: \(viewModel.podcasts.first { $0.id == cached.podcastID }?.title ?? "Cached episode")") {
                        reviewStage = stage; review = cached
                    }
                    .buttonStyle(.chunky(.success, size: .small))
                    .lineLimit(1)
                }
            }
            if let podcast = viewModel.selectedPodcast ?? viewModel.nextPodcast ?? viewModel.podcasts.first {
                Button(viewModel.recallBusy ? "Preparing source-backed questions…" : "Create a review for \(podcast.title)") {
                    viewModel.generateRecall(for: podcast)
                }.disabled(viewModel.recallBusy || viewModel.habitLoop.reviews.contains { $0.podcastID == podcast.id })
                    .lineLimit(2)
            }
            Text("Uses your cached transcript and Groq key. Reviews repeat on days 1, 3 and 7. Listening alone unlocks apps.")
                .font(.caption).foregroundStyle(.secondary)
            if !viewModel.habitLoop.badges.isEmpty {
                Text("Your collection").font(Play.rounded(16, .heavy))
                ForEach(viewModel.habitLoop.badges.prefix(12)) { badge in
                    Label(badge.detail, systemImage: "rosette").font(.caption.weight(.semibold)).foregroundStyle(Play.Palette.goldLip)
                }
            }
            Toggle("Celebration sounds", isOn: $viewModel.habitLoop.soundsEnabled)
            Toggle("Celebration haptics", isOn: $viewModel.habitLoop.hapticsEnabled)
        }.onChange(of: viewModel.habitLoop.soundsEnabled) { viewModel.saveData() }
            .onChange(of: viewModel.habitLoop.hapticsEnabled) { viewModel.saveData() }
    }

    private var wagerIsCurrent: Bool {
        guard let wager = viewModel.habitLoop.activeWager(on: day), let start = LearningCalendar.date(from: wager.day),
              let end = Calendar.current.date(byAdding: .day, value: 7, to: start) else { return false }
        return Date() < end
    }
}

struct FocusModeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var controller = FocusModeController.shared
        @State private var reviewed = false
    #if os(iOS)
    @State private var choice = FamilyActivitySelection()
    @State private var picker = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("Learn first") {
                    Text("Complete your adaptive daily learning goal on either device to unlock apps until midnight. Open PodTrackio on iPhone to sync learning completed on your Mac.")
                    LabeledContent("Today's goal", value: "\(Int(controller.state.dailyTargetSeconds / 60)) minutes")
                    Text("Starts at five minutes. Every two successful days add one minute, up to 60. Missed days hold the level; today's target stays fixed.").font(.caption).foregroundStyle(.secondary)
                    if controller.state.isLocked {
                        Label("\(controller.state.remainingMinutes) minutes remaining. No in-app bypass.", systemImage: "lock.fill")
                    }
                }
                #if os(iOS)
                Section("Screen Time access") {
                    Button("Allow Screen Time access") { Task { await controller.authorize() } }
                    Text("\(String(describing: controller.authorization))").font(.caption)
                    Button("Choose individual apps") { picker = true }.disabled(controller.state.isLocked)
                    ForEach(Array(choice.applicationTokens), id: \.self) { token in Label(token).labelStyle(.titleAndIcon) }
                    Toggle("I checked that PodTrackio and my playback apps are not selected", isOn: $reviewed)
                        .disabled(controller.state.isLocked)
                    Text("Choose individual apps only, without categories or websites. You can revoke access in iPhone Settings; PodTrackio cannot prevent that.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                #else
                Section("Mac gate") {
                    Button("Choose distracting apps…") { controller.chooseApps(); reviewed = false }.disabled(controller.state.isLocked)
                    ForEach(controller.state.selectedNames, id: \.self) { Text($0) }
                    Toggle("I reviewed these apps", isOn: $reviewed).disabled(controller.state.isLocked)
                    Text("Best effort: selected apps are hidden while PodTrackio runs. Their work stays open. Quitting PodTrackio bypasses the gate.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                #endif
                Section {
                    Button(controller.state.enabled ? "Save reviewed settings" : "Activate strict Focus Mode") {
                        #if os(iOS)
                        controller.configure(enabled: true, selection: choice)
                        #else
                        controller.configure(enabled: true)
                        #endif
                    }.disabled(controller.state.isLocked || !reviewed)
                    if controller.state.enabled && !controller.state.isLocked {
                        Button("Disable future blocking", role: .destructive) {
                            controller.configure(enabled: false)
                        }
                    }
                    Text("Once activated, finish today's target before editing apps, reducing the target, or disabling future blocking. Both devices must use the same account. Signing out and streak freezes do not unlock apps.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let message = controller.message { Section { Text(message) } }
            }
            .formStyle(.grouped)
            .navigationTitle("Strict Focus Mode")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        #endif
        .onAppear {
            controller.refresh()
            #if os(iOS)
            choice = controller.selection
            #endif
        }
        #if os(iOS)
        .familyActivityPicker(isPresented: $picker, selection: $choice)
        #endif
    }
}
