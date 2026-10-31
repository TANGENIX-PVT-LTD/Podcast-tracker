import SwiftUI

struct SessionSummary: Equatable {
    var seconds: Double
    var xp: Int
    var quests: Int
    var goalProgress: Double
}

/// Queues the full-screen reward moments so they play one at a time, in a sensible order.
@MainActor
final class PlayMoments: ObservableObject {
    static let shared = PlayMoments()
    @Published var chestGems: Int?
    @Published var session: SessionSummary?
    @Published var freezeSavedStreak: Int?
    private var sessionStartXP: Int?
    private var sessionSeconds: Double = 0

    /// Reads reconcile wins (e.g. "Daily chest · 10 gems · …") for moments that need their own screen.
    func noteWins(_ wins: [String]) {
        for win in wins where win.hasPrefix("Daily chest") {
            chestGems = win.split(separator: "·").dropFirst().first
                .flatMap { Int($0.trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? "") } ?? 5
        }
    }

    func trackingStarted(xp: Int) { if sessionStartXP == nil { sessionStartXP = xp; sessionSeconds = 0 } }
    func trackingStopped(seconds: Double) { sessionSeconds += seconds }

    /// Called when the player closes. Only real sessions (5+ minutes) earn a results screen.
    func playerClosed(viewModel: AppViewModel) {
        defer { sessionStartXP = nil; sessionSeconds = 0 }
        let seconds = sessionSeconds + (viewModel.isTracking ? viewModel.currentSessionSeconds : 0)
        guard let start = sessionStartXP, seconds >= 300 else { return }
        session = SessionSummary(seconds: seconds, xp: max(0, viewModel.stats.totalXP - start),
                                 quests: viewModel.habitLoop.questCount(on: LearningCalendar.dateKey(for: Date())),
                                 goalProgress: viewModel.dailyGoalProgress)
    }

    /// Shows the "freeze saved you" moment once, the first time the app opens after a frozen day.
    func checkFreeze(viewModel: AppViewModel) {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return }
        let key = LearningCalendar.dateKey(for: yesterday)
        let ack = "play.freezeAck.\(key)"
        guard viewModel.habitStreakStatus.frozenDays.contains(key), !UserDefaults.standard.bool(forKey: ack) else { return }
        UserDefaults.standard.set(true, forKey: ack)
        freezeSavedStreak = viewModel.stats.currentStreak
    }
}

/// One nonblocking receipt groups related rewards; it never takes over the player.
struct PlayMomentsOverlay: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var moments = PlayMoments.shared
    var active = true

    private var receipt: String? {
        var details: [String] = []
        if let summary = moments.session {
            details.append("\(Int(summary.seconds / 60)) minutes listened · +\(summary.xp) XP")
        }
        if viewModel.showDailyCelebration { details.append("Daily goal complete · \(viewModel.stats.currentStreak)-day streak") }
        if let gems = moments.chestGems { details.append("All daily quests complete · +\(gems) gems") }
        if viewModel.showLevelUpAlert { details.append("Level \(viewModel.stats.currentLevel.number) · \(viewModel.stats.currentLevel.title)") }
        if let streak = moments.freezeSavedStreak { details.append("A freeze protected your \(streak)-day streak yesterday") }
        return details.isEmpty ? nil : details.joined(separator: "\n")
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if active, scenePhase == .active, let receipt {
                FeedbackReceipt(title: moments.session == nil ? "Progress saved" : "Session complete",
                                detail: receipt, symbol: "checkmark.circle.fill", onDismiss: dismiss)
                    .padding(16)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(y: 8).combined(with: .opacity), removal: .opacity))
                    .task(id: receipt) {
                        do { try await Task.sleep(for: .seconds(7)) } catch { return }
                        dismiss()
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(reduceMotion ? nil : .smooth(duration: 0.24, extraBounce: 0), value: receipt)
        .onChange(of: scenePhase) { _, phase in if phase != .active { dismiss() } }
    }

    private func dismiss() {
        viewModel.showDailyCelebration = false
        viewModel.showLevelUpAlert = false
        moments.session = nil
        moments.chestGems = nil
        moments.freezeSavedStreak = nil
    }
}

struct FeedbackReceipt: View {
    var title: String
    var detail: String
    var symbol: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Play.themeTint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(16)
        .frame(maxWidth: 400, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }
}

/// Results for an explicitly completed quiz. The action is available immediately.
struct MomentScaffold<Content: View>: View {
    var glow: Color = Play.Palette.flame
    var buttonTitle = "Continue"
    var buttonKind: ChunkyButtonStyle.Kind = .primary
    var showsButton: Bool
    var shake = 0
    var flash = 0
    var flashColor: Color = .white
    var onContinue: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                content
                Button(buttonTitle, action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(24).frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
    }
}
