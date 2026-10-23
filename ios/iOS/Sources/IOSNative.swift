import SwiftUI

// iOS-native building blocks. The page is plain system background; containers are flat and outlined with
// a 2pt hairline (systemGray5 adapts to dark mode); type uses Dynamic Type text styles in SF Rounded
// (set once at the root). The 3D "lip" stays only on the primary call-to-action buttons.

extension View {
    func outlined(_ radius: CGFloat = 16) -> some View {
        background(Color(.systemBackground), in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color(.systemGray5), lineWidth: 2))
    }
}

/// A titled page section: bold title, optional trailing accessory, content below.
struct IOSSection<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3.bold())
                Spacer()
                accessory.font(.subheadline.weight(.semibold))
            }
            content
        }
    }
}

extension IOSSection where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.accessory = EmptyView(); self.content = content()
    }
}

extension IOSSection {
    init(_ title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title; self.accessory = accessory(); self.content = content()
    }
}

/// Profile-style stat tile: colored glyph, big number, quiet label.
struct IOSStatTile: View {
    let symbol: String
    let color: Color
    let value: String
    let label: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.title3.weight(.bold)).foregroundStyle(color).frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline.weight(.heavy)).monospacedDigit().contentTransition(.numericText())
                Text(label).font(.footnote).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .outlined()
        .accessibilityElement(children: .combine)
    }
}

/// A Duolingo quest bar: rounded track with the fraction written inside it.
struct IOSQuestBar: View {
    var value: Double
    var label: String
    var tint: Color = Play.Palette.gold
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5))
                Capsule().fill(tint).frame(width: max(value > 0 ? 18 : 0, proxy.size.width * min(1, shown)))
                    .overlay(alignment: .top) { Capsule().fill(.white.opacity(0.3)).frame(height: 3).padding(.horizontal, 8).padding(.top, 3) }
                Text(label).font(.caption2.weight(.heavy)).foregroundStyle(shown > 0.45 ? .white : .secondary)
                    .frame(maxWidth: .infinity).monospacedDigit()
            }
        }
        .frame(height: 18)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) { shown = value } }
        .onChange(of: value) { _, new in withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { shown = new } }
        .accessibilityElement().accessibilityLabel(label)
    }
}

/// Seven compact day cells, Monday first.
struct IOSWeekStrip: View {
    var days: [StreakDay]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    Text(day.letter).font(.caption.weight(.bold))
                        .foregroundStyle(day.state == .today || day.state == .todayDone ? Play.Palette.flame : .secondary)
                    cell(day.state).frame(width: 30, height: 30)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.id), \(label(day.state))")
            }
        }
    }

    @ViewBuilder private func cell(_ state: StreakDay.State) -> some View {
        switch state {
        case .done, .todayDone:
            Circle().fill(Play.Palette.flame)
                .overlay(Image(systemName: "checkmark").font(.caption.weight(.black)).foregroundStyle(.white))
        case .frozen:
            Circle().fill(Play.Palette.ice)
                .overlay(Image(systemName: "snowflake").font(.caption.weight(.bold)).foregroundStyle(.white))
        case .today:
            Circle().strokeBorder(Play.Palette.flame, style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))
        case .missed, .future:
            Circle().fill(Color(.systemGray6))
        }
    }

    private func label(_ state: StreakDay.State) -> String {
        switch state {
        case .done, .todayDone: "learned"; case .frozen: "freeze used"; case .today: "today"; case .missed: "missed"; case .future: "upcoming"
        }
    }
}

/// Toolbar stats in the top bar, like Duolingo's flame / gems row. Tapping the flame opens the streak.
struct IOSStatsBar: View {
    @EnvironmentObject private var viewModel: AppViewModel
    var onStreak: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onStreak) {
                HStack(spacing: 3) {
                    StreakFlame(state: viewModel.flameState, size: 22, showsFace: false)
                    Text("\(viewModel.stats.currentStreak)")
                        .foregroundStyle(viewModel.flameState == .ash ? Color.secondary : Play.Palette.flame)
                }
            }
            .accessibilityLabel("\(viewModel.stats.currentStreak)-day streak")
            HStack(spacing: 3) {
                Image(systemName: "diamond.fill").foregroundStyle(Play.Palette.gem)
                Text("\(viewModel.habitLoop.gems)").foregroundStyle(Play.Palette.gem)
            }
            .accessibilityElement(children: .combine)
        }
        .font(.headline.weight(.heavy))
        .monospacedDigit()
        .buttonStyle(.plain)
        .fixedSize()
        .padding(.horizontal, 6)
    }
}
