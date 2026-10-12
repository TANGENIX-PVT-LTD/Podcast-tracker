import SwiftUI

struct IOSEpisodeEditor: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case episode = "Episode"
        case playlist = "Playlist"
        var id: String { rawValue }
    }

    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .episode
    @State private var title = ""
    @State private var url = ""
    @State private var categoryID = LearningCategory.generalID
    @State private var playlistPreview: PlaylistPreview?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var importResult: PlaylistImportResult?
    @State private var previewTask: Task<Void, Never>?
    @State private var isFetchingTitle = false
    @State private var fetchedTitle: String?
    @State private var titleFetchTask: Task<Void, Never>?

    private var validVideoID: String? { Podcast.extractVideoId(from: url) }
    private var shouldShowTitleField: Bool { validVideoID != nil || !title.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Add", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .episode { episodeSection } else { playlistSection }

                Section("Learning category") {
                    Picker("Category", selection: $categoryID) {
                        ForEach(viewModel.categories) { category in
                            Label(category.name, systemImage: category.symbolName).tag(category.id)
                        }
                    }
                    Text(mode == .playlist
                         ? "The playlist becomes a Collection; this category is assigned to newly added episodes."
                         : "You can change categories later in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(mode == .episode ? "Add Episode" : "Import Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { confirmationButton }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if viewModel.category(for: categoryID) == nil {
                categoryID = viewModel.categories.first?.id ?? LearningCategory.generalID
            }
        }
        .onChange(of: mode) { _, _ in reset() }
        .onDisappear { previewTask?.cancel() }
    }

    private var episodeSection: some View {
        Section {
            // Title field - appears when URL is valid or user has typed
            if shouldShowTitleField {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Episode title", text: $title, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                    if isFetchingTitle {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Fetching title…")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if let fetched = fetchedTitle {
                        Label {
                            Text(fetched)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.footnote)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .animation(.smooth(duration: 0.25), value: isFetchingTitle)
                .animation(.smooth(duration: 0.25), value: fetchedTitle)
            }

            // URL field - always visible
            VStack(alignment: .leading, spacing: 6) {
                TextField("YouTube URL or video ID", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onChange(of: url) { _, newValue in
                        handleURLChange(newValue)
                    }

                if !url.isEmpty && validVideoID == nil {
                    Label("Enter a valid YouTube URL or 11-character video ID.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.smooth(duration: 0.2), value: validVideoID)

            // Note text
            Text("Adding an episode does not download it. Offline playback remains a separate choice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("YouTube episode")
        }
    }

    private func handleURLChange(_ newURL: String) {
        let videoID = Podcast.extractVideoId(from: newURL)
        if videoID != nil {
            // Show title field when valid URL is entered
            if title.isEmpty && fetchedTitle == nil && !isFetchingTitle {
                fetchVideoTitle(videoID: videoID!)
            }
        } else {
            // Reset fetched title when URL becomes invalid
            withAnimation(.smooth(duration: 0.2)) {
                fetchedTitle = nil
            }
        }
    }

    private func fetchVideoTitle(videoID: String) {
        titleFetchTask?.cancel()
        withAnimation(.smooth(duration: 0.2)) {
            isFetchingTitle = true
            fetchedTitle = nil
        }

        titleFetchTask = Task {
            do {
                let title = try await YouTubeMetadataFetcher.fetchTitle(videoID: videoID)
                if !Task.isCancelled {
                    await MainActor.run {
                        withAnimation(.smooth(duration: 0.25)) {
                            self.fetchedTitle = title
                            self.title = title
                            self.isFetchingTitle = false
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        withAnimation(.smooth(duration: 0.2)) {
                            self.isFetchingTitle = false
                        }
                    }
                }
            }
        }
    }

    private var playlistSection: some View {
        Section("Public YouTube playlist") {
            TextField("Playlist URL", text: $url)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            if isLoading {
                HStack { ProgressView(); Text("Reading playlist…").foregroundStyle(.secondary) }
            }
            if let preview = playlistPreview {
                VStack(alignment: .leading, spacing: 8) {
                    Text(preview.title).font(.headline)
                    LabeledContent("Available episodes", value: "\(preview.episodes.count)")
                    LabeledContent("Unavailable or private", value: "\(preview.unavailableCount)")
                    Text("Videos are not downloaded during import.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let result = importResult {
                Label("Added \(result.added), reused \(result.reused), skipped \(result.skipped).", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var confirmationButton: some View {
        if mode == .episode {
            Button("Add") {
                viewModel.addPodcast(title: title, url: url, categoryID: categoryID)
                dismiss()
            }
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || validVideoID == nil)
        } else if importResult != nil {
            Button("Done") { dismiss() }
        } else if let preview = playlistPreview {
            Button("Import \(preview.episodes.count)") {
                importResult = viewModel.importPlaylist(preview, categoryID: categoryID)
                playlistPreview = nil
            }
        } else {
            Button("Preview") { loadPlaylist() }
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
    }

    private func loadPlaylist() {
        previewTask?.cancel()
        isLoading = true
        errorMessage = nil
        importResult = nil
        let input = url
        previewTask = Task {
            do {
                playlistPreview = try await PlaylistImporter.preview(url: input)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func reset() {
        previewTask?.cancel()
        titleFetchTask?.cancel()
        title = ""
        url = ""
        playlistPreview = nil
        importResult = nil
        errorMessage = nil
        isLoading = false
        isFetchingTitle = false
        fetchedTitle = nil
    }
}

struct IOSRescueSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cue: DistractionCue = .scrolling
    @State private var minutes = 5

    var body: some View {
        NavigationStack {
            Form {
                Section("What is pulling you away?") {
                    Picker("Distraction", selection: $cue) {
                        ForEach(DistractionCue.rescueChoices) { item in
                            Label(item.title, systemImage: item.symbolName).tag(item)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Section("Make the smallest promise you will keep") {
                    Picker("Learning block", selection: $minutes) {
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("20 min").tag(20)
                    }
                    .pickerStyle(.segmented)
                }
                if let podcast = viewModel.nextPodcast {
                    Section("Ready next") {
                        Text(podcast.title).font(.headline)
                        if podcast.hasProgress {
                            LabeledContent("Resume from", value: podcast.lastPlaybackPosition.podTimestamp)
                        }
                    }
                }
                Section {
                    Text("The timer begins only after playback starts. Pausing never creates fake watch time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Distraction Rescue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        viewModel.prepareRescue(cue: cue, minutes: minutes)
                        dismiss()
                    }
                    .disabled(viewModel.nextPodcast == nil)
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct IOSSchedulePodcastSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let podcast: Podcast
    @State private var scheduledDate: Date

    init(podcast: Podcast, day: Date? = nil) {
        self.podcast = podcast
        _scheduledDate = State(initialValue: day ?? podcast.scheduledAt ?? Date().addingTimeInterval(3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Episode") { Text(podcast.title).font(.headline) }
                Section("Reminder") {
                    DatePicker("Watch on", selection: $scheduledDate, displayedComponents: [.date, .hourAndMinute])
                    if scheduledDate <= Date() {
                        Label("Past times remain in your calendar but do not trigger a notification.", systemImage: "clock.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                if podcast.scheduledAt != nil {
                    Section {
                        Button("Remove Schedule", role: .destructive) {
                            viewModel.removeSchedule(for: podcast)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(podcast.scheduledAt == nil ? "Schedule Episode" : "Reschedule Episode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.schedulePodcast(podcast, at: scheduledDate)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct IOSScheduleDaySheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let day: Date
    @State private var podcastID: UUID?
    @State private var time: Date

    init(day: Date) {
        self.day = day
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = 18
        _time = State(initialValue: Calendar.current.date(from: components) ?? day)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Episode", selection: $podcastID) {
                    Text("Choose an episode").tag(Optional<UUID>.none)
                    ForEach(viewModel.podcasts.filter { !$0.isCompleted }) { podcast in
                        Text(podcast.title).tag(Optional(podcast.id))
                    }
                }
                DatePicker("Time", selection: $time, displayedComponents: [.hourAndMinute])
            }
            .navigationTitle("Schedule Episode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        guard let podcastID,
                              let podcast = viewModel.podcasts.first(where: { $0.id == podcastID }) else { return }
                        viewModel.schedulePodcast(podcast, at: time)
                        dismiss()
                    }
                    .disabled(podcastID == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
