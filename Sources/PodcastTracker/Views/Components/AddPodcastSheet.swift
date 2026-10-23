import SwiftUI

struct AddPodcastSheet: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case episode = "Single Episode"
        case playlist = "YouTube Playlist"
        var id: String { rawValue }
    }

    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .episode
    @State private var title = ""
    @State private var url = ""
    @State private var categoryID = LearningCategory.generalID
    @State private var playlistPreview: PlaylistPreview?
    @State private var isLoadingPlaylist = false
    @State private var errorMessage: String?
    @State private var importResult: PlaylistImportResult?
    @State private var previewTask: Task<Void, Never>?
    @State private var isFetchingTitle = false
    @State private var fetchedTitle: String?
    @State private var titleFieldVisible = false
    @State private var fetchError: String?

    private var videoID: String? { Podcast.extractVideoId(from: url) }
    private var availableModes: [Mode] {
        DistributionChannel.allowsExternalMediaTools ? Mode.allCases : [.episode]
    }
    private var canSaveEpisode: Bool {
        let effectiveTitle = title.isEmpty ? (fetchedTitle ?? "") : title
        return !effectiveTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && videoID != nil
    }
    private var shouldShowTitleField: Bool {
        videoID != nil || !title.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if availableModes.count > 1 {
                    Picker("Add", selection: $mode) {
                        ForEach(availableModes) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .episode { episodeForm } else { playlistForm }

                Section("Category") {
                    Picker("Learning Category", selection: $categoryID) {
                        ForEach(viewModel.categories) { category in
                            Label(category.name, systemImage: category.symbolName).tag(category.id)
                        }
                    }
                    Text(DistributionChannel.allowsExternalMediaTools
                         ? "Playlist imports become a separate Collection. This Category is applied only to newly added episodes."
                         : "This Category is applied to the episode you add.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode == .episode ? "Add Episode" : "Import Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { confirmationButton }
            }
        }
        .frame(width: 620, height: mode == .playlist ? 560 : 390)
        .onAppear {
            if viewModel.category(for: categoryID) == nil {
                categoryID = viewModel.categories.first?.id ?? LearningCategory.generalID
            }
        }
        .onChange(of: mode) { _, _ in
            resetPlaylistState()
            titleFieldVisible = false
        }
        .onChange(of: url) { _, newValue in
            if mode == .playlist {
                playlistPreview = nil
                importResult = nil
                errorMessage = nil
            } else if mode == .episode {
                let newVideoID = Podcast.extractVideoId(from: newValue)
                if newVideoID != nil && !newValue.isEmpty {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        titleFieldVisible = true
                    }
                    fetchTitle(for: newValue)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        titleFieldVisible = false
                    }
                    fetchedTitle = nil
                    isFetchingTitle = false
                }
            }
        }
        .onDisappear { previewTask?.cancel() }
    }

    private var episodeForm: some View {
        Section {
            // Title field with smooth appearance animation
            if shouldShowTitleField || titleFieldVisible {
                VStack(alignment: .leading, spacing: 10) {
                    // Text field with inline loading indicator
                    HStack(spacing: 8) {
                        TextField("Title", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                        if isFetchingTitle {
                            ProgressView()
                                .controlSize(.small)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.25, dampingFraction: 0.9), value: isFetchingTitle)

                    // Fetched title preview - appears when we have a fetched title but user hasn't typed
                    if let fetchedTitle, title.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.tint)
                            Text(fetchedTitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer()
                            Text("Tap to edit")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.quinary)
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                    }

                    // Fetch error - shown when auto-fetch fails but we still have a valid video ID
                    if let fetchError, title.isEmpty, fetchedTitle == nil {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text(fetchError)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.quinary)
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }

            // YouTube URL field
            VStack(alignment: .leading, spacing: 8) {
                TextField("YouTube URL", text: $url)
                    .textFieldStyle(.roundedBorder)
                if !url.isEmpty && videoID == nil {
                    Label("Enter a valid YouTube URL or video ID.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Text("Adding an episode never downloads it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Episode")
        }
    }

    private var playlistForm: some View {
        Section("Playlist") {
            TextField("YouTube playlist URL", text: $url)
                .textFieldStyle(.roundedBorder)

            if isLoadingPlaylist {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading playlist metadata…")
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let preview = playlistPreview {
                VStack(alignment: .leading, spacing: 10) {
                    Text(preview.title)
                        .font(.headline)
                    HStack(spacing: 16) {
                        LabeledContent("Available episodes", value: "\(preview.episodes.count)")
                        LabeledContent("Unavailable or private", value: "\(preview.unavailableCount)")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    Text("No videos will be downloaded during import.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }

            if let result = importResult {
                Label("Added \(result.added), reused \(result.reused), skipped \(result.skipped).", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var confirmationButton: some View {
        if mode == .episode {
            Button("Add") {
                let effectiveTitle = title.isEmpty ? (fetchedTitle ?? "") : title
                viewModel.addPodcast(title: effectiveTitle, url: url, categoryID: categoryID)
                dismiss()
            }
            .buttonStyle(.chunky(.primary, size: .small, fullWidth: false))
            .disabled(!canSaveEpisode)
            .animation(.spring(response: 0.2, dampingFraction: 0.9), value: canSaveEpisode)
        } else if importResult != nil {
            Button("Done") { dismiss() }.buttonStyle(.chunky(.primary, size: .small, fullWidth: false))
        } else if let preview = playlistPreview {
            Button("Import \(preview.episodes.count)") {
                importResult = viewModel.importPlaylist(preview, categoryID: categoryID)
                playlistPreview = nil
            }
            .buttonStyle(.chunky(.primary, size: .small, fullWidth: false))
        } else {
            Button("Preview") { loadPlaylist() }
                .buttonStyle(.chunky(.primary, size: .small, fullWidth: false))
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingPlaylist)
        }
    }

    private func loadPlaylist() {
        previewTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            isLoadingPlaylist = true
        }
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
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    isLoadingPlaylist = false
                }
            }
        }
    }

    private func resetPlaylistState() {
        previewTask?.cancel()
        playlistPreview = nil
        importResult = nil
        errorMessage = nil
        isLoadingPlaylist = false
        url = ""
        title = ""
        fetchedTitle = nil
        isFetchingTitle = false
        titleFieldVisible = false
        fetchError = nil
    }

    private func fetchTitle(for urlString: String) {
        guard let videoID = Podcast.extractVideoId(from: urlString) else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            isFetchingTitle = true
            fetchError = nil
        }
        fetchedTitle = nil

        Task {
            // Add a 10 second timeout for the entire fetch operation
            let fetchTask = Task {
                await YouTubeVideoMetadataFetcher.fetch(videoID: videoID)
            }

            // Wait for either the fetch to complete or timeout
            let result = await withTaskGroup(of: YouTubeVideoMetadata?.self) { group in
                group.addTask { await fetchTask.value }
                group.addTask {
                    try? await Task.sleep(for: .seconds(10))
                    return nil // timeout
                }
                // Return first completed result
                for await result in group {
                    group.cancelAll()
                    return result
                }
                return nil
            }

            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if let metadata = result {
                        self.fetchedTitle = metadata.title
                        self.fetchError = nil
                    } else {
                        self.fetchError = "Couldn't fetch title automatically. You can type it manually."
                    }
                    self.isFetchingTitle = false
                }
            }
        }
    }
}
