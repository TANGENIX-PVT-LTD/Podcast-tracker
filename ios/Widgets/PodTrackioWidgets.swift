import AppIntents
import SwiftUI
import WidgetKit

private enum PodTrackioWidgetRoute {
    static let today = URL(string: "podtrackio://today")!
    static let continueLearning = URL(string: "podtrackio://continue")!
    static let rescue = URL(string: "podtrackio://rescue")!
    static let addEpisode = URL(string: "podtrackio://add")!

    static func episode(_ id: UUID?) -> URL {
        guard let id else { return continueLearning }
        return URL(string: "podtrackio://episode/\(id.uuidString)")!
    }
}

struct PodTrackioWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: PodTrackioWidgetSnapshot
}

struct PodTrackioWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PodTrackioWidgetEntry {
        PodTrackioWidgetEntry(
            date: .now,
            snapshot: PodTrackioWidgetSnapshot(
                todayWatchedMinutes: 18,
                dailyGoalMinutes: 30,
                currentStreak: 7,
                totalXP: 680,
                levelTitle: "Scholar",
                libraryCount: 42,
                completedCount: 12,
                nextEpisodeID: nil,
                nextEpisodeTitle: "The next idea worth keeping",
                nextEpisodeProgress: 0.38
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PodTrackioWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PodTrackioWidgetEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func entry() -> PodTrackioWidgetEntry {
        PodTrackioWidgetEntry(date: .now, snapshot: PodTrackioWidgetSnapshotStore.load())
    }
}

private struct PodTrackioWidgetBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.035, green: 0.055, blue: 0.15),
                Color(red: 0.10, green: 0.14, blue: 0.34),
                Color(red: 0.06, green: 0.34, blue: 0.42)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.cyan.opacity(0.26))
                .frame(width: 150, height: 150)
                .blur(radius: 34)
                .offset(x: 38, y: -50)
        }
    }
}

private struct MomentumWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PodTrackioWidgetEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.snapshot.dailyProgress) {
                Image(systemName: "headphones")
            } currentValueLabel: {
                Text("\(entry.snapshot.currentWatchedMinutes)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Learning streak", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                Text("\(entry.snapshot.currentStreak) days · \(entry.snapshot.currentWatchedMinutes)/\(entry.snapshot.dailyGoalMinutes) min")
                    .font(.caption2)
                ProgressView(value: entry.snapshot.dailyProgress)
                    .widgetAccentable()
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "headphones.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.cyan)
                    Spacer()
                    Label("\(entry.snapshot.currentStreak)", systemImage: "flame.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                Text("\(entry.snapshot.currentWatchedMinutes) min")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(entry.snapshot.protectedToday ? "Streak protected · \(entry.snapshot.gems) gems" : "\(entry.snapshot.dailyGoalMinutes) minutes protects today")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                if let minutes = entry.snapshot.currentFocusMinutesRemaining {
                    Text(minutes == 0 ? "Apps unlocked" : "\(minutes) minutes to unlock apps").font(.caption2).foregroundStyle(.white.opacity(0.8))
                }
                ProgressView(value: entry.snapshot.dailyProgress)
                    .tint(.cyan)
            }
            .containerBackground(for: .widget) { PodTrackioWidgetBackground() }
            .widgetURL(PodTrackioWidgetRoute.today)
        }
    }
}

struct PodTrackioMomentumWidget: Widget {
    let kind = "com.tangenix.podtrackio.momentum"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PodTrackioWidgetProvider()) { entry in
            MomentumWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Momentum")
        .description("See today’s learning goal and your current streak.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

private struct UpNextWidgetView: View {
    let entry: PodTrackioWidgetEntry

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(.white.opacity(0.10))
                Circle()
                    .trim(from: 0, to: max(entry.snapshot.nextEpisodeProgress, 0.04))
                    .stroke(
                        AngularGradient(colors: [.cyan, .blue, .purple, .cyan], center: .center),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Image(systemName: "play.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text("UP NEXT")
                    .font(.caption2.bold())
                    .tracking(1.3)
                    .foregroundStyle(.cyan)
                Text(entry.snapshot.nextEpisodeTitle ?? "Build your learning queue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(entry.snapshot.nextEpisodeTitle == nil ? "Add an episode to begin" : "Tap to continue learning")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { PodTrackioWidgetBackground() }
        .widgetURL(PodTrackioWidgetRoute.episode(entry.snapshot.nextEpisodeID))
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

private struct LearningHQWidgetView: View {
    let entry: PodTrackioWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PODTRACKIO")
                        .font(.caption2.bold())
                        .tracking(1.5)
                        .foregroundStyle(.cyan)
                    Text("Learning HQ")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                Label("\(entry.snapshot.currentStreak) day streak", systemImage: "flame.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                metric("Today", "\(entry.snapshot.currentWatchedMinutes)m", "timer")
                metric("Level", entry.snapshot.levelTitle, "graduationcap.fill")
                metric("Library", "\(entry.snapshot.libraryCount)", "books.vertical.fill")
            }

            Link(destination: PodTrackioWidgetRoute.episode(entry.snapshot.nextEpisodeID)) {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.13), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CONTINUE")
                            .font(.caption2.bold())
                            .foregroundStyle(.cyan)
                        Text(entry.snapshot.nextEpisodeTitle ?? "Add your next episode")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(12)
                .background(.white.opacity(0.09), in: .rect(cornerRadius: 16))
            }
        }
        .containerBackground(for: .widget) { PodTrackioWidgetBackground() }
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(.cyan)
            Text(value).font(.headline).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 15))
    }
}

struct PodTrackioLearningHQWidget: Widget {
    let kind = "com.tangenix.podtrackio.learning-hq"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PodTrackioWidgetProvider()) { entry in
            LearningHQWidgetView(entry: entry)
        }
        .configurationDisplayName("Learning HQ")
        .description("Your goal, level, library, and next episode at a glance.")
        .supportedFamilies([.systemLarge])
    }
}

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
        PodTrackioUpNextWidget()
        PodTrackioLearningHQWidget()
        ResumeLearningControl()
        RescueLearningControl()
        AddEpisodeControl()
    }
}
