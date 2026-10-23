import SwiftUI

/// Live daily-goal ring for the player. Each credited minute floats a "+1 XP" and ticks.
struct PlayerGoalChip: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floaters: [Floater] = []

    private struct Floater: Identifiable { let id = UUID(); var rise = false }

    var body: some View {
        let protected = viewModel.streakProtectedToday
        HStack(spacing: 8) {
            PlayRing(value: viewModel.dailyGoalProgress, tint: protected ? Play.Palette.success : Play.Palette.flame, lineWidth: 4) {
                Image(systemName: protected ? "checkmark" : "flame.fill").font(.system(size: 11, weight: .black))
                    .foregroundStyle(protected ? Play.Palette.success : Play.Palette.flame)
            }
            .frame(width: 26, height: 26)
            Text(protected ? "Goal done" : "\(viewModel.todayWatchedMinutes)/\(Int(viewModel.habitSettings.currentDailyGoalMinutes)) min")
                .font(Play.rounded(14, .heavy)).monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .overlay(alignment: .top) {
            ZStack {
                ForEach(floaters) { floater in
                    Text("+1 XP").font(Play.rounded(13, .black)).foregroundStyle(Play.Palette.goldLip)
                        .offset(y: floater.rise ? -34 : 0)
                        .opacity(floater.rise ? 0 : 1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(protected ? "Daily goal complete" : "\(viewModel.todayWatchedMinutes) of \(Int(viewModel.habitSettings.currentDailyGoalMinutes)) minutes today")
        .onChange(of: viewModel.todayWatchedMinutes) { old, new in
            guard new > old else { return }
            PlayFeedback.play(.tick, sound: false)
            guard !reduceMotion else { return }
            let floater = Floater()
            floaters.append(floater)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                withAnimation(.easeOut(duration: 1.1)) {
                    if let index = floaters.firstIndex(where: { $0.id == floater.id }) { floaters[index].rise = true }
                }
                try? await Task.sleep(for: .seconds(1.2))
                floaters.removeAll { $0.id == floater.id }
            }
        }
    }
}
