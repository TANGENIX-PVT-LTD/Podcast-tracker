import SwiftUI

/// Achievement unlocks drop in from the top as a chunky badge card, then slide away.
struct AchievementToast: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack {
            if viewModel.showAchievementPopup, let achievement = viewModel.newlyUnlockedAchievement {
                FeedbackReceipt(title: "Achievement unlocked: \(achievement.title)",
                                detail: achievement.description, symbol: achievement.iconName) {
                    viewModel.showAchievementPopup = false
                }
                .padding(16)
                .transition(.opacity)
                .task(id: achievement.id) {
                    do { try await Task.sleep(for: .seconds(6)) } catch { return }
                    guard viewModel.newlyUnlockedAchievement?.id == achievement.id else { return }
                    viewModel.showAchievementPopup = false
                }
            }
            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: viewModel.showAchievementPopup)
    }
}

/// Compact streak + gem readout for sidebars, menu bars and toolbars.
struct StreakBadge: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                StreakFlame(state: viewModel.flameState, size: 24, showsFace: false)
                Text("\(viewModel.stats.currentStreak)").font(Play.rounded(16, .black))
                    .foregroundStyle(viewModel.flameState == .ash ? Play.Palette.ash : Play.Palette.flame)
                    .contentTransition(.numericText()).playPop(on: viewModel.stats.currentStreak)
            }
            PlayStatPill(symbol: "diamond.fill", value: "\(viewModel.habitLoop.gems)", color: Play.Palette.gem, label: "gems")
            PlayStatPill(symbol: "bolt.fill", value: "\(viewModel.stats.totalXP)", color: Play.Palette.goldLip, label: "XP")
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
