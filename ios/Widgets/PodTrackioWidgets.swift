import AppIntents
import SwiftUI
import WidgetKit

private enum PodTrackioWidgetRoute {
    static let today = URL(string: "podtrackio://today")!
    static let progress = URL(string: "podtrackio://progress")!
    static let continueLearning = URL(string: "podtrackio://continue")!
    static let rescue = URL(string: "podtrackio://rescue")!
    static let addEpisode = URL(string: "podtrackio://add")!

    static func episode(_ id: UUID?) -> URL {
        guard let id else { return continueLearning }
        return URL(string: "podtrackio://episode/\(id.uuidString)")!
    }
}

// MARK: - Timeline

struct PodTrackioWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: PodTrackioWidgetSnapshot
}

struct PodTrackioWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PodTrackioWidgetEntry {
        PodTrackioWidgetEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (PodTrackioWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : PodTrackioWidgetEntry(date: .now, snapshot: PodTrackioWidgetSnapshotStore.load()))
    }

    /// Entries at the moments the mood should change on its own: now, 6pm (at risk), 10pm (last call) and midnight.
    func getTimeline(in context: Context, completion: @escaping (Timeline<PodTrackioWidgetEntry>) -> Void) {
        let snapshot = PodTrackioWidgetSnapshotStore.load()
        let calendar = Calendar.current
        let now = Date()
        var dates = [now]
        for hour in [18, 22] {
            if let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now), date > now { dates.append(date) }
        }
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) { dates.append(midnight) }
        completion(Timeline(entries: dates.map { PodTrackioWidgetEntry(date: $0, snapshot: snapshot) },
                            policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

extension PodTrackioWidgetSnapshot {
    static let preview: PodTrackioWidgetSnapshot = {
        var s = PodTrackioWidgetSnapshot(todayWatchedMinutes: 6, dailyGoalMinutes: 9, currentStreak: 12, totalXP: 1196,
            levelTitle: "Expert", libraryCount: 5, completedCount: 1, nextEpisodeID: nil,
            nextEpisodeTitle: "How to Speak — Patrick Winston", nextEpisodeProgress: 0.35)
        s.snapshotDay = LearningCalendar.todayKeyForWidgets
        s.weekStates = ["done", "done", "done", "done", "today", "future", "future"]
        s.questsDone = 1; s.gems = 245; s.levelNumber = 5; s.levelProgress = 0.39
        s.nextEpisodeResumeLabel = "Resume at 21:00"; s.hasThumbnail = true
        return s
    }()
}

private enum LearningCalendar {
    static var todayKeyForWidgets: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Streak state → look and voice

private struct StreakMood {
    let mood: WidgetEchoMood
    let flame: WidgetFlameState
    let line: String
    let style: Style
    enum Style { case lit, safe, night, fresh }

    init(_ s: PodTrackioWidgetSnapshot, at date: Date) {
        let hour = Calendar.current.component(.hour, from: date)
        let left = s.remainingMinutes
        if s.protectedToday {
            mood = s.currentQuestsDone < 3 ? .proud : .cheer; flame = .lit; style = .safe
            line = s.currentQuestsDone < 3 ? "Safe! \(3 - s.currentQuestsDone) quest\(3 - s.currentQuestsDone == 1 ? "" : "s") to the chest" : "All done. See you tomorrow!"
        } else if s.currentStreak == 0 {
            mood = .happy; flame = .ash; style = .fresh
            line = "Light your first flame · \(left) min"
        } else if hour >= 22 {
            mood = .worried; flame = .dim; style = .night
            line = "Last call! \(left) min saves it"
        } else if s.atRisk(at: date) {
            mood = .worried; flame = .dim; style = .night
            line = "\(left) min keeps it alive"
        } else if hour < 7 {
            mood = .sleepy; flame = .lit; style = .lit
            line = "\(left) min today keeps it going"
        } else {
            mood = .happy; flame = .lit; style = .lit
            line = "\(left) min to day \(s.currentStreak + 1)"
        }
    }

    var dark: Bool { style != .fresh }
    /// The colour ink takes on white parts of a coloured background.
    var ink: Color {
        switch style {
        case .lit: WPalette.flameDeep
        case .safe: Color(red: 0.27, green: 0.64, blue: 0.0)
        case .night: WPalette.nightBottom
        case .fresh: WPalette.flame
        }
    }

    @ViewBuilder var background: some View {
        switch style {
        case .lit:
            LinearGradient(colors: [Color(red: 1, green: 0.69, blue: 0.12), WPalette.flameDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .safe:
            LinearGradient(colors: [Color(red: 0.47, green: 0.86, blue: 0.07), Color(red: 0.27, green: 0.64, blue: 0.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .night:
            ZStack {
                LinearGradient(colors: [WPalette.nightTop, WPalette.nightBottom], startPoint: .top, endPoint: .bottom)
                ForEach(0..<9, id: \.self) { i in
                    Circle().fill(.white.opacity(0.55)).frame(width: i % 3 == 0 ? 3 : 2)
                        .position(x: CGFloat((i * 47) % 90) + 70, y: CGFloat((i * 19) % 46) + 6)
                }
            }
        case .fresh:
            Color(uiColor: .systemBackground)
        }
    }
}

// MARK: - Streak widget (home + Lock Screen)

private struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: PodTrackioWidgetEntry

    var body: some View {
        let s = entry.snapshot
        let look = StreakMood(s, at: entry.date)
        let onColor: Color = look.style == .fresh ? .primary : .white
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: s.dailyProgress) {
                    Image(systemName: "flame.fill")
                } currentValueLabel: {
                    VStack(spacing: -2) {
                        Image(systemName: "flame.fill").font(.system(size: 11, weight: .bold))
                        Text("\(s.currentStreak)").font(.system(size: 17, weight: .heavy, design: .rounded))
                    }
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").widgetAccentable()
                        Text("\(s.currentStreak)-day streak").font(.headline.weight(.heavy))
                    }
                    Text(s.protectedToday ? "Safe today" : "\(s.remainingMinutes) min to keep it").font(.caption)
                    ProgressView(value: s.dailyProgress).widgetAccentable()
                }
                .fontDesign(.rounded)
            case .accessoryInline:
                Label(s.protectedToday ? "\(s.currentStreak)-day streak · safe" : "\(s.currentStreak) days · \(s.remainingMinutes) min to go", systemImage: "flame.fill")
            case .systemMedium:
                HStack(spacing: 14) {
                    smallContent(s, look, onColor)
                    VStack(alignment: .leading, spacing: 10) {
                        WidgetWeekStrip(states: s.currentWeekStates, dot: 20, dark: look.dark, ink: look.ink)
                        WidgetBar(value: s.dailyProgress, label: "\(s.currentWatchedMinutes) / \(s.dailyGoalMinutes) min",
                                  tint: look.dark ? .white : WPalette.flame, height: 16, dark: look.dark,
                                  labelOnFill: look.dark ? look.ink : .white)
                        HStack(spacing: 5) {
                            ForEach(0..<3, id: \.self) { i in
                                Image(systemName: i < s.currentQuestsDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(i < s.currentQuestsDone ? (look.dark ? Color.white : WPalette.success) : onColor.opacity(0.45))
                            }
                            Image(systemName: s.currentQuestsDone == 3 ? "gift.fill" : "gift").font(.system(size: 12, weight: .bold)).foregroundStyle(onColor.opacity(0.85))
                            Spacer()
                            Image(systemName: "diamond.fill").font(.system(size: 11)).foregroundStyle(look.style == .fresh ? WPalette.gem : .white)
                            Text("\(s.gems)").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(onColor)
                        }
                    }
                }
            default:
                smallContent(s, look, onColor)
            }
        }
        .containerBackground(for: .widget) { if renderingMode == .fullColor { look.background } else { Color.clear } }
        .widgetURL(PodTrackioWidgetRoute.today)
    }

    private func smallContent(_ s: PodTrackioWidgetSnapshot, _ look: StreakMood, _ onColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: -4) {
                    Text("\(s.currentStreak)")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(look.style == .fresh ? WPalette.flame : .white)
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .widgetAccentable()
                    Text(s.currentStreak == 1 ? "day streak" : "day streak")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(onColor.opacity(0.9))
                }
                Spacer(minLength: 2)
                WidgetFlame(state: look.flame, size: 34)
            }
            Spacer(minLength: 4)
            HStack(alignment: .bottom, spacing: 4) {
                Text(look.line)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(onColor.opacity(0.92))
                    .lineLimit(3).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                WidgetEcho(mood: look.mood, size: 60)
                    .padding(.bottom, -6).padding(.trailing, -6)
            }
        }
    }
}

struct PodTrackioMomentumWidget: Widget {
    let kind = "com.tangenix.podtrackio.momentum"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PodTrackioWidgetProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Echo keeps an eye on your streak, and gets worried when it's at risk.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Daily goal

private struct DailyGoalWidgetView: View {
    let entry: PodTrackioWidgetEntry

    var body: some View {
        let s = entry.snapshot
        let done = s.protectedToday
        let progress = max(0.001, s.dailyProgress)
        let colors = done ? [Color(red: 0.27, green: 0.64, blue: 0.0), WPalette.success, Color(red: 0.6, green: 0.9, blue: 0.2)]
                          : [WPalette.gold, WPalette.flame, WPalette.flameDeep]
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke((done ? WPalette.success : WPalette.flame).opacity(0.14), lineWidth: 13)
                Circle().trim(from: 0, to: progress)
                    .stroke(AngularGradient(colors: colors, center: .center, startAngle: .zero, endAngle: .degrees(360 * progress)),
                            style: StrokeStyle(lineWidth: 13, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: (done ? WPalette.success : WPalette.flame).opacity(0.4), radius: 4)
                    .widgetAccentable()
                VStack(spacing: -1) {
                    if done {
                        WidgetEcho(mood: .cheer, size: 46)
                        Text("Goal met!").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(WPalette.success)
                    } else {
                        WidgetFlame(state: s.currentWatchedMinutes > 0 ? .lit : .ash, size: 18)
                        Text("\(s.currentWatchedMinutes)").font(.system(size: 28, weight: .heavy, design: .rounded)).monospacedDigit()
                        Text("of \(s.dailyGoalMinutes) min").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i < s.currentQuestsDone ? WPalette.gold : Color.primary.opacity(0.1)).frame(height: 7)
                }
                Image(systemName: s.currentQuestsDone == 3 ? "gift.fill" : "gift").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(s.currentQuestsDone == 3 ? WPalette.goldLip : .secondary)
            }
        }
        .fontDesign(.rounded)
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
        .widgetURL(PodTrackioWidgetRoute.today)
    }
}

struct PodTrackioDailyGoalWidget: Widget {
    let kind = "com.tangenix.podtrackio.daily-goal"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PodTrackioWidgetProvider()) { entry in
            DailyGoalWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Goal")
        .description("Today's minutes and quests at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Up next

private extension PodTrackioWidgetSnapshot {
    var thumbnail: UIImage? {
        guard hasThumbnail, let url = PodTrackioWidgetSnapshotStore.thumbnailURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private struct EpisodeThumbnail: View {
    let snapshot: PodTrackioWidgetSnapshot
    var height: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = snapshot.thumbnail {
                Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor).aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [WPalette.echo, Color(red: 0.43, green: 0.27, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay { Image(systemName: "play.fill").font(.title2).foregroundStyle(.white.opacity(0.9)) }
            }
            if snapshot.nextEpisodeProgress > 0 {
                GeometryReader { proxy in
                    Rectangle().fill(Color.red).frame(width: proxy.size.width * snapshot.nextEpisodeProgress, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }
}

/// Full-bleed episode art under a scrim, like a Now Playing card.
private struct UpNextWidgetView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: PodTrackioWidgetEntry

    var body: some View {
        let s = entry.snapshot
        let empty = s.nextEpisodeTitle == nil
        let percent = Int((s.nextEpisodeProgress * 100).rounded())
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Label(empty ? "GET STARTED" : (percent > 0 ? "\(percent)% WATCHED" : "UP NEXT"), systemImage: empty ? "sparkles" : "headphones")
                    .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.35)))
                Spacer()
                if empty || s.thumbnail == nil { WidgetEcho(mood: empty ? .happy : .cheer, size: 54).padding(.top, -6) }
            }
            Spacer(minLength: 0)
            Text(s.nextEpisodeTitle ?? "Build your learning queue")
                .font(.system(.headline, design: .rounded, weight: .heavy)).foregroundStyle(.white)
                .lineLimit(2).shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            HStack(alignment: .center) {
                Text(empty ? "Add an episode to begin" : (s.nextEpisodeResumeLabel ?? "Tap to continue"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                Spacer(minLength: 6)
                WidgetPill(title: empty ? "Add" : (percent > 0 ? "Continue" : "Start"), symbol: empty ? "plus" : "play.fill", tint: WPalette.flame)
            }
            if !empty {
                Capsule().fill(.white.opacity(0.25)).frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in Capsule().fill(Color.red).frame(width: proxy.size.width * s.nextEpisodeProgress) }
                    }
                    .widgetAccentable()
            }
        }
        .containerBackground(for: .widget) {
            if renderingMode == .fullColor {
                ZStack {
                    if let image = s.thumbnail {
                        Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        LinearGradient(colors: [WPalette.echo, Color(red: 0.43, green: 0.27, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    LinearGradient(stops: [.init(color: .black.opacity(0.25), location: 0), .init(color: .black.opacity(0.15), location: 0.3), .init(color: .black.opacity(0.85), location: 1)], startPoint: .top, endPoint: .bottom)
                }
            } else {
                Color.clear
            }
        }
        .widgetURL(empty ? PodTrackioWidgetRoute.addEpisode : PodTrackioWidgetRoute.episode(s.nextEpisodeID))
    }
}

struct PodTrackioUpNextWidget: Widget {
    let kind = "com.tangenix.podtrackio.up-next"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PodTrackioWidgetProvider()) { entry in
            UpNextWidgetView(entry: entry)
        }
        .configurationDisplayName("Up Next")
        .description("Jump back into the episode that matters next.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Learning HQ

private struct LearningHQWidgetView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: PodTrackioWidgetEntry

    var body: some View {
        let s = entry.snapshot
        let look = StreakMood(s, at: entry.date)
        let onColor: Color = look.dark ? .white : .primary
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    WidgetEcho(mood: look.mood, size: 56)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(s.currentStreak)").font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(look.dark ? .white : WPalette.flame).widgetAccentable()
                            Text("day streak").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(onColor)
                        }
                        Text(look.line).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(onColor.opacity(0.85)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        Text("LVL \(s.levelNumber)").font(.system(size: 10, weight: .heavy, design: .rounded))
                        Text(s.levelTitle).font(.system(size: 12, weight: .heavy, design: .rounded)).lineLimit(1)
                    }
                    .foregroundStyle(look.dark ? .white : WPalette.goldLip)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(look.dark ? Color.white.opacity(0.2) : WPalette.gold.opacity(0.18)))
                }
                WidgetWeekStrip(states: s.currentWeekStates, dot: 24, dark: look.dark, ink: look.ink)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14)
            .background { if renderingMode == .fullColor { look.background } }

            VStack(spacing: 10) {
                VStack(spacing: 8) {
                    quest("Learn for 5 minutes", "headphones", WPalette.gem, done: s.currentQuestsDone >= 1, value: min(1, Double(s.currentWatchedMinutes) / 5), label: nil)
                    quest("Hit today's goal", "target", WPalette.flame, done: s.protectedToday, value: s.dailyProgress,
                          label: "\(s.currentWatchedMinutes) / \(s.dailyGoalMinutes) min")
                    quest("Recall or save a takeaway", "lightbulb.fill", Color(red: 0.81, green: 0.51, blue: 1), done: s.currentQuestsDone >= 3, value: s.currentQuestsDone >= 3 ? 1 : 0, label: nil)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 2))
                Spacer(minLength: 0)
                Link(destination: s.nextEpisodeTitle == nil ? PodTrackioWidgetRoute.addEpisode : PodTrackioWidgetRoute.episode(s.nextEpisodeID)) {
                    HStack(spacing: 12) {
                        EpisodeThumbnail(snapshot: s, height: 46).frame(width: 82)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.nextEpisodeTitle ?? "Add your next episode").font(.system(.subheadline, design: .rounded, weight: .bold)).lineLimit(1)
                            Text(s.nextEpisodeResumeLabel ?? "Tap to start").font(.system(size: 12, design: .rounded)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        WidgetPill(title: "Go", tint: Color.accentColor)
                    }
                }
            }
            .padding(16)
        }
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
        .widgetURL(PodTrackioWidgetRoute.today)
    }

    private func quest(_ title: String, _ symbol: String, _ color: Color, done: Bool, value: Double, label: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .bold, design: .rounded))
                WidgetBar(value: done ? 1 : value, label: done ? "Done" : label, tint: done ? WPalette.success : WPalette.gold, height: 12,
                          labelOnFill: done ? .white : Color(red: 0.55, green: 0.36, blue: 0.0))
            }
            Image(systemName: done ? "gift.fill" : "gift").font(.system(size: 14)).foregroundStyle(done ? WPalette.goldLip : Color(uiColor: .systemGray3))
        }
    }
}

struct PodTrackioLearningHQWidget: Widget {
    let kind = "com.tangenix.podtrackio.learning-hq"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PodTrackioWidgetProvider()) { entry in
            LearningHQWidgetView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Learning HQ")
        .description("Echo, your streak, today's quests and your next episode.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Controls

struct ResumeLearningControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tangenix.podtrackio.control.resume") {
            ControlWidgetButton(action: OpenURLIntent(PodTrackioWidgetRoute.continueLearning)) {
                Label("Resume Learning", systemImage: "play.fill")
            }
        }
        .displayName("Resume Learning")
        .description("Open your next PodTrackio episode.")
    }
}

struct RescueLearningControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tangenix.podtrackio.control.rescue") {
            ControlWidgetButton(action: OpenURLIntent(PodTrackioWidgetRoute.rescue)) {
                Label("Rescue Me", systemImage: "bolt.shield.fill")
            }
        }
        .displayName("Rescue Me")
        .description("Replace a distraction with five minutes of learning.")
    }
}

struct AddEpisodeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tangenix.podtrackio.control.add") {
            ControlWidgetButton(action: OpenURLIntent(PodTrackioWidgetRoute.addEpisode)) {
                Label("Add Episode", systemImage: "plus")
            }
        }
        .displayName("Add Episode")
        .description("Open PodTrackio’s episode importer.")
    }
}

@main
struct PodTrackioWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PodTrackioMomentumWidget()
        PodTrackioDailyGoalWidget()
        PodTrackioUpNextWidget()
        PodTrackioLearningHQWidget()
        ResumeLearningControl()
        RescueLearningControl()
        AddEpisodeControl()
    }
}

#Preview("Streak", as: .systemSmall) { PodTrackioMomentumWidget() } timeline: {
    PodTrackioWidgetEntry(date: .now, snapshot: .preview)
}
