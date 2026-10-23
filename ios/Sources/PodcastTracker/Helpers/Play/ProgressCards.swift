import SwiftUI

/// Personal league: tier badge, weekly target bar, and what it takes to promote.
struct LeagueCard: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private static let tierColors: [Color] = [Color(hex: 0xCD7F32), Color(hex: 0xA8B4C0), Play.Palette.gold, Color(hex: 0x6ED8D0), Color(hex: 0x8FB8FF)]

    var body: some View {
        let league = viewModel.habitLeague
        let color = Self.tierColors[min(4, max(0, league.tier))]
        let minutesLeft = max(0, Int(league.targetMinutes - league.minutes))
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Image(systemName: "shield.fill").font(.system(size: 50)).foregroundStyle(color.gradient)
                    Image(systemName: "trophy.fill").font(.system(size: 20, weight: .black)).foregroundStyle(.white).offset(y: -2)
                }
                .frame(width: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(league.title.uppercased()) LEAGUE").font(Play.rounded(13, .heavy)).tracking(0.8).foregroundStyle(color)
                    Text(promotionLine(minutesLeft: minutesLeft, daysLeft: max(0, 5 - league.activeDays)))
                        .font(Play.rounded(17, .heavy))
                    Text("You vs. your last 4 weeks. Resets Monday.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            PlayProgressBar(value: min(1, league.minutes / max(1, league.targetMinutes)), tint: color, height: 12)
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { day in
                    Capsule().fill(day < league.activeDays ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color.secondary.opacity(0.15)))
                        .frame(height: 8)
                }
            }
            .accessibilityLabel("\(league.activeDays) of 5 active days")
        }
        .padding(16)
        .chunkyCard(cornerRadius: 20)
    }

    private func promotionLine(minutesLeft: Int, daysLeft: Int) -> String {
        switch (minutesLeft, daysLeft) {
        case (0, 0): "Promotion locked in!"
        case (0, _): "Minutes done · \(daysLeft) more active day\(daysLeft == 1 ? "" : "s")"
        case (_, 0): "\(minutesLeft) min to promote"
        default: "\(minutesLeft) min · \(daysLeft) day\(daysLeft == 1 ? "" : "s") to promote"
        }
    }
}

/// Achievement as a collectible badge: gold medallion when earned, grey lock otherwise.
struct AchievementBadgeTile: View {
    let achievement: Achievement

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(achievement.isUnlocked ? Play.Palette.goldLip : Color.secondary.opacity(0.25)).offset(y: 4)
                Circle().fill(achievement.isUnlocked ? AnyShapeStyle(Play.Palette.gold.gradient) : AnyShapeStyle(Color.secondary.opacity(0.15)))
                    .overlay(Circle().strokeBorder(.white.opacity(achievement.isUnlocked ? 0.55 : 0.2), lineWidth: 3).padding(5))
                Image(systemName: achievement.isUnlocked ? achievement.iconName : "lock.fill")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(achievement.isUnlocked ? .white : .secondary)
            }
            .frame(width: 62, height: 62)
            Text(achievement.title).font(Play.rounded(13, .heavy)).multilineTextAlignment(.center).lineLimit(2)
            Text(achievement.description).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .top)
        .padding(12)
        .chunkyCard(cornerRadius: 18)
        .opacity(achievement.isUnlocked ? 1 : 0.75)
        .accessibilityElement(children: .combine)
        .accessibilityValue(achievement.isUnlocked ? "Unlocked" : "Locked")
    }
}

/// Calendar day cell shared by iOS and macOS month grids.
struct PlayCalendarDay: View {
    var day: Int
    var learned: Bool
    var frozen: Bool
    var scheduled: Bool
    var selected: Bool
    var isToday: Bool

    var body: some View {
        ZStack {
            if learned {
                Circle().fill(Play.Palette.flame.gradient)
            } else if frozen {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Play.Palette.ice.gradient).rotationEffect(.degrees(8))
            } else if isToday {
                Circle().strokeBorder(Play.Palette.flame, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
            if selected { Circle().strokeBorder(Play.themeTint, lineWidth: 3).padding(-3) }
            Text("\(day)").font(Play.rounded(13, learned || frozen ? .heavy : .semibold)).monospacedDigit()
                .foregroundStyle(learned || frozen ? .white : .primary)
            if scheduled {
                Circle().fill(Play.Palette.gem).frame(width: 6, height: 6).offset(y: 15)
            }
        }
        .frame(width: 34, height: 34)
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
    }
}
