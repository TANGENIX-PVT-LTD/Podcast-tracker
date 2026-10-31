import SwiftUI

/// Live, quiet daily-goal progress stays beside the playback controls.
struct PlayerGoalChip: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(protected ? "Daily goal complete" : "\(viewModel.todayWatchedMinutes) of \(Int(viewModel.habitSettings.currentDailyGoalMinutes)) minutes today")
    }
}
