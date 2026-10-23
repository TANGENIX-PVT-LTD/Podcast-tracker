import SwiftUI

struct AchievementsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Achievements").font(Play.rounded(24, .heavy))
            Text("Earned through consistent learning, not repeatable taps.").foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
                ForEach(viewModel.achievements.sorted { $0.isUnlocked && !$1.isUnlocked }) { achievement in
                    AchievementBadgeTile(achievement: achievement)
                }
            }
        }
    }
}
