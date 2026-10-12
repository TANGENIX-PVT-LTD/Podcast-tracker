import SwiftUI

struct IOSTodayView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let onAdd: () -> Void
    let onRescue: () -> Void

    var body: some View {
        ZStack {
            ThemeBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PodSpacing.section) {
                    header
                    if let next = viewModel.nextPodcast {
                        nextEpisode(next)
                        rescueCard
                    } else {
                        emptyLibrary
                    }
                    metrics
                    recentActivity
                }
                .padding(PodSpacing.page)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onAdd) { Label("Add Episode", systemImage: "plus") }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(viewModel.todayRemainingMinutes == 0
                 ? "Learning complete."
                 : "Make the next \(viewModel.todayRemainingMinutes) minutes count.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func nextEpisode(_ podcast: Podcast) -> some View {
        Button { viewModel.selectPodcast(podcast) } label: {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .bottomLeading) {
                    PodcastThumbnail(podcast: podcast, width: nil, height: 205)
                        .frame(maxWidth: .infinity)
                    Text(podcast.hasProgress ? "CONTINUE LEARNING" : "UP NEXT")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.62), in: Capsule())
                        .padding(12)
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text(podcast.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if podcast.hasProgress {
                        ProgressView(value: podcast.progressPercentage)
                        Text("Resume at \(podcast.lastPlaybackPosition.podTimestamp)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Open episode", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .foregroundStyle(.tint)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .podCard(cornerRadius: 24)
        .accessibilityLabel("\(podcast.hasProgress ? "Resume" : "Open") \(podcast.title)")
    }

    private var rescueCard: some View {
        IOSGlassSurface(cornerRadius: 22, interactive: true, tint: .accentColor.opacity(0.12)) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("About to waste time?").font(.headline)
                        Text("Replace the impulse with one honest five-minute learning win.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(action: onRescue) {
                    Label("Start a Rescue", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
            }
            .padding(18)
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Your rhythm", subtitle: "Measured from real playback time")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metric("Today", value: "\(viewModel.todayWatchedMinutes)m", detail: "\(viewModel.todayRemainingMinutes)m left", symbol: "timer")
                metric("Streak", value: "\(viewModel.stats.currentStreak)", detail: "days", symbol: "flame.fill")
                metric("Level", value: "\(viewModel.stats.currentLevel.number)", detail: viewModel.stats.currentLevel.title, symbol: viewModel.stats.currentLevel.iconName)
                metric("Library", value: "\(viewModel.podcasts.count)", detail: "episodes", symbol: "books.vertical.fill")
            }
        }
    }

    private func metric(_ title: String, value: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .contentTransition(.numericText())
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .podCard(cornerRadius: 18)
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Recent activity")
            if viewModel.activities.isEmpty {
                Text("Your accurate daily history starts with the first episode you play.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.activities.sorted { $0.dateKey > $1.dateKey }.prefix(5)) { day in
                    HStack(spacing: 12) {
                        Image(systemName: day.goalCompleted ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(day.goalCompleted ? .green : .secondary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LearningCalendar.date(from: day.dateKey)?.formatted(date: .abbreviated, time: .omitted) ?? day.dateKey)
                                .font(.subheadline.weight(.semibold))
                            Text("\(Int(day.watchedSeconds / 60)) min · \(day.sessions) sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(day.xpEarned) XP").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    }
                    .padding(14)
                    .podCard(cornerRadius: 16)
                }
            }
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("Build your learning queue", systemImage: "books.vertical")
        } description: {
            Text("Add a YouTube episode or playlist you genuinely want to learn from.")
        } actions: {
            Button("Add Episode", systemImage: "plus", action: onAdd)
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .podCard(cornerRadius: 24)
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
            ThemeBackdrop()
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
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
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
                .buttonStyle(.glassProminent)
                .tint(tint)
            } else {
                Button(action: action) {
                    if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
                }
                .buttonStyle(.glass)
            }
        }
        .font(.caption.weight(.semibold))
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
            PodcastThumbnail(podcast: podcast, width: 116, height: 68)
            VStack(alignment: .leading, spacing: 7) {
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
                if podcast.hasProgress { ProgressView(value: podcast.progressPercentage) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .podCard(cornerRadius: 18)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}
