import SwiftUI

struct IOSTodayView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let onAdd: () -> Void
    let onRescue: () -> Void
    @State private var showStreak = false
    @State private var showQuests = false

    private var day: String { LearningCalendar.dateKey(for: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                goalHeader
                if let next = viewModel.nextPodcast { upNext(next) } else { emptyLibrary }
                quests
                rhythm
                rescueRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { IOSStatsBar { showStreak = true } }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onAdd) { Label("Add Episode", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showStreak) { IOSStreakSheet() }
        .sheet(isPresented: $showQuests) { IOSQuestsSheet() }
    }

    // Echo + today's goal + week: the one status block on the page.
    private var goalHeader: some View {
        let line = EchoLines.today(viewModel)
        return Button { showStreak = true } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    EchoView(mood: line.mood, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(headline).font(.headline).foregroundStyle(.primary)
                        Text(line.text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    PlayRing(value: viewModel.dailyGoalProgress, tint: viewModel.streakProtectedToday ? Play.Palette.success : Play.Palette.flame, lineWidth: 6) {
                        Text("\(viewModel.todayWatchedMinutes)").font(.subheadline.weight(.heavy)).monospacedDigit()
                    }
                    .frame(width: 48, height: 48)
                }
                IOSWeekStrip(days: viewModel.weekStrip)
            }
            .padding(16)
            .outlined(20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your streak")
    }

    private var headline: String {
        let streak = viewModel.stats.currentStreak
        if streak == 0 { return "No streak yet" }
        return viewModel.streakProtectedToday ? "\(streak)-day streak · safe today" : "\(streak)-day streak"
    }

    private func upNext(_ podcast: Podcast) -> some View {
        IOSSection(podcast.hasProgress ? "Continue learning" : "Up next") {
            VStack(alignment: .leading, spacing: 14) {
                Button { viewModel.selectPodcast(podcast) } label: {
                    PodcastThumbnail(podcast: podcast, width: nil, height: 196)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                        .overlay(alignment: .bottom) {
                            if podcast.hasProgress {
                                GeometryReader { proxy in
                                    Rectangle().fill(Play.Palette.error).frame(width: proxy.size.width * podcast.progressPercentage, height: 4)
                                }
                                .frame(height: 4)
                                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous))
                            }
                        }
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 4) {
                    Text(podcast.title).font(.headline).lineLimit(2)
                    Text(podcast.hasProgress ? "Resume at \(podcast.lastPlaybackPosition.podTimestamp)" : "Ready when you are")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button {
                    viewModel.selectPodcast(podcast)
                } label: {
                    Text(podcast.hasProgress ? "Continue" : "Start")
                }
                .buttonStyle(.chunky(viewModel.streakAtRisk ? .flame : .primary))
                .accessibilityLabel("\(podcast.hasProgress ? "Resume" : "Open") \(podcast.title)")
            }
        }
    }

    private var quests: some View {
        IOSSection("Daily quests", accessory: {
            Button("See all") { showQuests = true }
        }) {
            VStack(spacing: 0) {
                let seconds = viewModel.habitLoop.learnedSeconds(on: day)
                let goal = max(1, Int(viewModel.habitSettings.currentDailyGoalMinutes))
                questRow(1, "Learn for 5 minutes", "headphones", Play.Palette.gem,
                         min(1, seconds / 300), "\(min(5, Int(seconds / 60))) / 5")
                Divider().padding(.leading, 62)
                questRow(2, "Hit today's goal", "target", Play.Palette.flame,
                         viewModel.dailyGoalProgress, "\(min(goal, viewModel.todayWatchedMinutes)) / \(goal)")
                Divider().padding(.leading, 62)
                let reflected = viewModel.habitLoop.has("reflection/\(day)")
                questRow(3, "Recall or save a takeaway", "lightbulb.fill", Play.Palette.purple, reflected ? 1 : 0, reflected ? "1 / 1" : "0 / 1")
            }
            .outlined(20)
        }
    }

    private func questRow(_ number: Int, _ title: String, _ symbol: String, _ color: Color, _ progress: Double, _ label: String) -> some View {
        let done = viewModel.habitLoop.has("quest/\(day)/\(number)/xp")
        return HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3.weight(.bold)).foregroundStyle(color).frame(width: 34)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold))
                IOSQuestBar(value: done ? 1 : progress, label: done ? "Done" : label, tint: done ? Play.Palette.success : Play.Palette.gold)
            }
            Image(systemName: done ? "gift.fill" : "gift").font(.title3).foregroundStyle(done ? Play.Palette.gold : Color(.systemGray3))
                .symbolEffect(.bounce, value: done)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var rhythm: some View {
        IOSSection("Your rhythm") {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    IOSStatTile(symbol: "flame.fill", color: Play.Palette.flame, value: "\(viewModel.stats.currentStreak)", label: "Day streak")
                    IOSStatTile(symbol: "bolt.fill", color: Play.Palette.gold, value: "\(viewModel.stats.totalXP)", label: "Total XP")
                }
                GridRow {
                    IOSStatTile(symbol: "shield.lefthalf.filled", color: Play.Palette.gem, value: viewModel.habitLeague.title, label: "League")
                    IOSStatTile(symbol: viewModel.stats.currentLevel.iconName, color: Play.Palette.purple, value: viewModel.stats.currentLevel.title, label: "Level \(viewModel.stats.currentLevel.number)")
                }
            }
        }
    }

    private var rescueRow: some View {
        Button(action: onRescue) {
            HStack(spacing: 14) {
                Image(systemName: "bolt.shield.fill").font(.title2).foregroundStyle(Play.Palette.flame).frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("About to waste time?").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text("Swap the impulse for a 5-minute win").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .outlined(20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyLibrary: some View {
        VStack(spacing: 14) {
            EchoView(mood: .happy, size: 110)
            Text("Build your learning queue").font(.title3.bold())
            Text("Add a YouTube episode or playlist you genuinely want to learn from.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Add an episode", action: onAdd).buttonStyle(.chunky)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

struct IOSLibraryView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var mediaStore = LocalMediaStore.shared
    let onAdd: () -> Void
    @State private var schedulingPodcast: Podcast?
    @State private var deletingPodcast: Podcast?

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                filterBar
                if viewModel.filteredPodcasts.isEmpty {
                    ContentUnavailableView(
                        viewModel.podcasts.isEmpty ? "Your library is empty" : "No matching episodes",
                        systemImage: "books.vertical",
                        description: Text(viewModel.podcasts.isEmpty
                                          ? "Add one episode or import a playlist to begin."
                                          : "Try another search, category, or collection.")
                    )
                } else {
                    List {
                        ForEach(viewModel.filteredPodcasts) { podcast in
                            Button { viewModel.selectPodcast(podcast) } label: {
                                IOSPodcastRow(podcast: podcast)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if !podcast.isCompleted {
                                    Button { viewModel.markCompleted(podcast) } label: {
                                        Label("Complete", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { deletingPodcast = podcast } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button { schedulingPodcast = podcast } label: {
                                    Label("Schedule", systemImage: "calendar")
                                }
                                .tint(.orange)
                                downloadSwipeAction(for: podcast)
                            }
                            .contextMenu { contextMenu(for: podcast) }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Library")
        .searchable(text: $viewModel.searchText, prompt: "Episodes, categories, collections")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onAdd) { Label("Add Episode", systemImage: "plus") }
            }
        }
        .sheet(item: $schedulingPodcast) { podcast in
            IOSSchedulePodcastSheet(podcast: podcast)
        }
        .confirmationDialog(
            "Delete this episode?",
            isPresented: Binding(get: { deletingPodcast != nil }, set: { if !$0 { deletingPodcast = nil } }),
            presenting: deletingPodcast
        ) { podcast in
            Button("Delete \(podcast.title)", role: .destructive) { viewModel.removePodcast(podcast) }
        } message: { _ in
            Text("Its local notes and summary will be removed. Cloud deletion syncs when available.")
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", selected: viewModel.selectedCategoryID == nil) { viewModel.selectedCategoryID = nil }
                    ForEach(viewModel.categories) { category in
                        chip(category.name, symbol: category.symbolName, selected: viewModel.selectedCategoryID == category.id, tint: category.color) {
                            viewModel.selectedCategoryID = viewModel.selectedCategoryID == category.id ? nil : category.id
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            if !viewModel.collections.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("All collections", symbol: "rectangle.stack", selected: viewModel.selectedCollectionID == nil) {
                            viewModel.selectedCollectionID = nil
                        }
                        ForEach(viewModel.collections.sorted { $0.sortOrder < $1.sortOrder }) { collection in
                            chip(collection.title, selected: viewModel.selectedCollectionID == collection.id) {
                                viewModel.selectedCollectionID = viewModel.selectedCollectionID == collection.id ? nil : collection.id
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func chip(_ title: String, symbol: String? = nil, selected: Bool, tint: Color = .accentColor, action: @escaping () -> Void) -> some View {
        Group {
            if selected {
                Button(action: action) {
                    if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            } else {
                Button(action: action) {
                    if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
                }
                .buttonStyle(.bordered)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .font(.subheadline.weight(.semibold))
    }

    @ViewBuilder
    private func downloadSwipeAction(for podcast: Podcast) -> some View {
        switch mediaStore.state(for: podcast.youtubeVideoId) {
        case .notDownloaded, .failed:
            Button { Task { _ = try? await viewModel.download(podcast) } } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .tint(.blue)
        case .queued, .downloading:
            Button { viewModel.cancelDownload(podcast) } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
            .tint(.gray)
        case .downloaded:
            Button { viewModel.deleteDownload(podcast) } label: {
                Label("Remove", systemImage: "arrow.down.circle.fill")
            }
            .tint(.gray)
        }
    }

    @ViewBuilder
    private func contextMenu(for podcast: Podcast) -> some View {
        Button("Open", systemImage: "play.fill") { viewModel.selectPodcast(podcast) }
        if !podcast.isCompleted {
            Button("Mark Complete", systemImage: "checkmark.circle") { viewModel.markCompleted(podcast) }
        }
        Button(podcast.scheduledAt == nil ? "Schedule" : "Reschedule", systemImage: "calendar") {
            schedulingPodcast = podcast
        }
        switch mediaStore.state(for: podcast.youtubeVideoId) {
        case .notDownloaded, .failed:
            Button("Download", systemImage: "arrow.down.circle") { Task { _ = try? await viewModel.download(podcast) } }
        case .queued, .downloading:
            Button("Cancel Download", systemImage: "xmark.circle") { viewModel.cancelDownload(podcast) }
        case .downloaded:
            Button("Delete Download", systemImage: "trash", role: .destructive) { viewModel.deleteDownload(podcast) }
        }
        Divider()
        Button("Delete Episode", systemImage: "trash", role: .destructive) { deletingPodcast = podcast }
    }
}

private struct IOSPodcastRow: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var mediaStore = LocalMediaStore.shared
    let podcast: Podcast

    var body: some View {
        HStack(spacing: 14) {
            PodcastThumbnail(podcast: podcast, width: 112, height: 63)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(podcast.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let category = viewModel.category(for: podcast.categoryID) {
                        Label(category.name, systemImage: category.symbolName).foregroundStyle(category.color)
                    }
                    if podcast.isCompleted {
                        Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if podcast.hasProgress {
                        Text("\(Int(podcast.progressPercentage * 100))%")
                    }
                    if case .downloaded = mediaStore.state(for: podcast.youtubeVideoId) {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if podcast.hasProgress { ProgressView(value: podcast.progressPercentage).tint(Play.Palette.error) }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
