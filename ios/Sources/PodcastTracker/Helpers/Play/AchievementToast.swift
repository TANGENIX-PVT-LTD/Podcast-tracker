import SwiftUI

/// Achievement unlocks drop in from the top as a chunky badge card, then slide away.
struct AchievementToast: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var badgePop = false

    var body: some View {
        VStack {
            if viewModel.showAchievementPopup, let achievement = viewModel.newlyUnlockedAchievement {
                HStack(spacing: 12) {
                    Image(systemName: achievement.iconName).font(.system(size: 20, weight: .black)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Play.Palette.gold.gradient))
                        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 3).padding(3))
                        .scaleEffect(badgePop ? 1 : 0.3)
                        .rotationEffect(.degrees(badgePop ? 0 : -40))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ACHIEVEMENT UNLOCKED").font(Play.rounded(11, .heavy)).tracking(0.6).foregroundStyle(Play.Palette.goldLip)
                        Text(achievement.title).font(Play.rounded(16, .heavy))
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: 380)
                .chunkyCard(cornerRadius: 18, border: Play.Palette.gold)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .task(id: achievement.id) {
                    badgePop = false
                    PlayFeedback.play(.success, sound: false); PlayFeedback.sound("pop")
                    withAnimation(Play.Motion.or(Play.Motion.bouncy.delay(0.15), reduceMotion: reduceMotion)) { badgePop = true }
                    try? await Task.sleep(for: .seconds(3.2))
                    withAnimation(Play.Motion.gentle) { viewModel.showAchievementPopup = false }
                }
            }
            Spacer()
        }
        .padding(.top, 8)
        .animation(Play.Motion.or(Play.Motion.bouncy, reduceMotion: reduceMotion), value: viewModel.showAchievementPopup)
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
