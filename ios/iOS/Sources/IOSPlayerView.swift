import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct IOSPlayerView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var mediaStore = LocalMediaStore.shared
    let podcast: Podcast
    @StateObject private var playerController = PlayerController()
    @State private var inspectorMode: PlayerInspectorMode = .summary
    @State private var playbackSource: NativePlaybackSource = .stream
    @State private var listenMode = false
    @State private var useNativePlayer = true
    @State private var playbackFailed = false
    @State private var playbackAttemptID = UUID()
    @State private var retryCount = 0
    @State private var showSchedule = false
    @State private var showPasteTranscript = false
    @State private var showFileImporter = false
    @State private var downloadError: String?

    private var currentPodcast: Podcast {
        viewModel.podcasts.first(where: { $0.id == podcast.id }) ?? podcast
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        player
                        if let commitment = viewModel.activeCommitment, commitment.podcastID == currentPodcast.id {
                            IOSCommitmentCard(commitment: commitment, isStarting: playerController.isPlaybackStartPending)
                        }
                        episodeHeader
                        inspector
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Now Learning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "chevron.down") { dismiss() }
                }
                ToolbarItem(placement: .principal) { PlayerGoalChip() }
                ToolbarItem(placement: .topBarTrailing) { actionMenu }
            }
        }
        .overlay { PlayMomentsOverlay() }
        .sheet(isPresented: $showSchedule) { IOSSchedulePodcastSheet(podcast: currentPodcast) }
        .sheet(isPresented: $showPasteTranscript) { IOSPasteTranscriptSheet(podcast: currentPodcast) }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.plainText, .data]) { result in
            guard case .success(let url) = result else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url),
               let document = try? TranscriptImporter.document(
                   data: data,
                   fileExtension: url.pathExtension,
                   podcastID: currentPodcast.id
               ) {
                viewModel.generateSummary(for: currentPodcast, transcript: document)
            }
        }
        .task(id: currentPodcast.id) {
            choosePlaybackSource()
            startRequestedPlaybackIfNeeded()
        }
        .onChange(of: viewModel.playbackStartRequest) { _, request in
            if request?.targets(currentPodcast.id) == true { startRequestedPlaybackIfNeeded() }
        }
        .onDisappear {
            if viewModel.isTracking, viewModel.selectedPodcast?.id == currentPodcast.id {
                viewModel.stopTracking()
            }
        }
    }

    @ViewBuilder
    private var player: some View {
        Group {
            if playbackFailed {
                playbackUnavailable
            } else if useNativePlayer {
                let attempt = playbackAttemptID
                ZStack {
                    IOSNativePlayerView(
                        videoID: currentPodcast.youtubeVideoId,
                        title: currentPodcast.title,
                        startPosition: currentPodcast.lastPlaybackPosition,
                        reloadID: attempt,
                        source: playbackSource,
                        listenOnly: listenMode,
                        controller: playerController,
                        onTimeUpdate: { viewModel.updatePlaybackPosition(for: currentPodcast.id, position: $0) },
                        onDurationReady: { viewModel.updateDuration(for: currentPodcast.id, duration: $0) },
                        onPlayStateChange: handlePlayStateChange,
                        onFailure: { handleNativeFailure(attempt) }
                    )
                    .id(attempt)

                    if listenMode {
                        IOSListenModeOverlay(
                            title: currentPodcast.title,
                            controller: playerController,
                            onExit: { switchListenMode(false) }
                        )
                    }
                }
            } else {
                IOSYouTubeWebView(
                    videoID: currentPodcast.youtubeVideoId,
                    startPosition: currentPodcast.lastPlaybackPosition,
                    controller: playerController,
                    onTimeUpdate: { viewModel.updatePlaybackPosition(for: currentPodcast.id, position: $0) },
                    onDurationReady: { viewModel.updateDuration(for: currentPodcast.id, duration: $0) },
                    onPlayStateChange: handlePlayStateChange,
                    onError: { playbackFailed = true }
                )
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(.black)
    }

    private var episodeHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(currentPodcast.title)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let category = viewModel.category(for: currentPodcast.categoryID) {
                    Label(category.name, systemImage: category.symbolName).foregroundStyle(category.color)
                }
                if currentPodcast.isCompleted {
                    Label("Completed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if currentPodcast.hasProgress {
                    Label("\(Int(currentPodcast.progressPercentage * 100))%", systemImage: "chart.bar.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption.weight(.medium))

            if currentPodcast.hasProgress { ProgressView(value: currentPodcast.progressPercentage).tint(Play.Palette.error) }

            HStack(spacing: 10) {
                Button(listenMode ? "Watching" : "Listen Mode", systemImage: listenMode ? "play.rectangle.fill" : "headphones") {
                    switchListenMode(!listenMode)
                }
                .buttonStyle(.glassProminent)
                .tint(listenMode ? .indigo : .cyan)

                if listenMode {
                    sleepTimerMenu
                }
            }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button(currentPodcast.isCompleted ? "Completed" : "Mark Complete", systemImage: currentPodcast.isCompleted ? "checkmark.circle.fill" : "checkmark.circle") {
                        if !currentPodcast.isCompleted {
                            viewModel.markCompleted(currentPodcast)
                            PlayFeedback.play(.success, sound: false); PlayFeedback.sound("complete")
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(currentPodcast.isCompleted)
                    Button(currentPodcast.scheduledAt == nil ? "Schedule" : "Reschedule", systemImage: "calendar.badge.clock") {
                        showSchedule = true
                    }
                    .buttonStyle(.glass)
                    downloadButton
                }
            }
            if case .downloading = mediaStore.state(for: currentPodcast.youtubeVideoId) {
                let fraction = mediaStore.activeDownloadProgress[currentPodcast.youtubeVideoId] ?? 0
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Downloading", systemImage: "arrow.down.circle.fill")
                        Spacer()
                        Text("\(Int((fraction * 100).rounded()))% · \(Int(((1 - fraction) * 100).rounded()))% remaining")
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.semibold))
                    ProgressView(value: fraction)
                        .tint(.cyan)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Download progress")
                .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
            }
            if let downloadError {
                Label(downloadError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 18)
    }

    private var inspector: some View {
        VStack(spacing: 14) {
            Picker("Learning tools", selection: $inspectorMode) {
                ForEach(PlayerInspectorMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)

            Group {
                switch inspectorMode {
                case .summary:
                    IOSSummaryView(
                        podcast: currentPodcast,
                        playerController: playerController,
                        onPaste: { showPasteTranscript = true },
                        onImport: { showFileImporter = true }
                    )
                case .notes:
                    IOSNotesView(podcast: currentPodcast)
                case .chat:
                    IOSQuirkyChatView(podcast: currentPodcast)
                }
            }
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        switch mediaStore.state(for: currentPodcast.youtubeVideoId) {
        case .notDownloaded, .failed:
            Button("Download", systemImage: "arrow.down.circle") { beginDownload() }
                .buttonStyle(.glass)
        case .queued, .downloading:
            let fraction = mediaStore.activeDownloadProgress[currentPodcast.youtubeVideoId]
            Button(fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "Cancel", systemImage: "xmark.circle") {
                viewModel.cancelDownload(currentPodcast)
            }
                .buttonStyle(.glass)
        case .downloaded:
            Button("Offline", systemImage: "checkmark.circle.fill") {
                playbackSource = .local
                useNativePlayer = true
                playbackFailed = false
                playbackAttemptID = UUID()
            }
            .buttonStyle(.glass)
            .tint(.green)
        }
    }

    private var actionMenu: some View {
        Menu {
            Button(listenMode ? "Switch to Video" : "Listen in Background", systemImage: listenMode ? "play.rectangle" : "headphones") {
                switchListenMode(!listenMode)
            }
            Button("Open in YouTube", systemImage: "safari") {
                if let url = URL(string: currentPodcast.url) { UIApplication.shared.open(url) }
            }
            Button("Schedule", systemImage: "calendar") { showSchedule = true }
            switch mediaStore.state(for: currentPodcast.youtubeVideoId) {
            case .downloaded:
                Button("Delete Download", systemImage: "trash", role: .destructive) {
                    viewModel.deleteDownload(currentPodcast)
                    if playbackSource == .local {
                        playbackSource = .stream
                        playbackAttemptID = UUID()
                    }
                }
            default:
                EmptyView()
            }
        } label: {
            Label("Episode Actions", systemImage: "ellipsis.circle")
        }
    }

    private var playbackUnavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.slash.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.7))
            Text("This episode could not play in PodTrackio").font(.headline).foregroundStyle(.white)
            Text("The video may block embedded playback or its stream may have expired.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.66))
                .multilineTextAlignment(.center)
            HStack {
                Button("Retry", systemImage: "arrow.clockwise") {
                    playbackFailed = false
                    useNativePlayer = true
                    retryCount = 0
                    playbackAttemptID = UUID()
                }
                .buttonStyle(.glassProminent)
                Button("YouTube", systemImage: "safari") {
                    if let url = URL(string: currentPodcast.url) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.glass)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    private func choosePlaybackSource() {
        if mediaStore.cachedPlayableURL(videoId: currentPodcast.youtubeVideoId) != nil {
            playbackSource = .local
        } else {
            playbackSource = .stream
        }
        useNativePlayer = true
        playbackFailed = false
        retryCount = 0
        playbackAttemptID = UUID()
    }

    private func startRequestedPlaybackIfNeeded() {
        guard viewModel.consumePlaybackStartRequest(for: currentPodcast.id) else { return }
        playerController.requestPlaybackStart()
    }

    private func handlePlayStateChange(_ playing: Bool) {
        if playing { retryCount = 0 }
        playerController.playerStateDidChange(isPlaying: playing)
        viewModel.handlePlaybackState(podcast: currentPodcast, isPlaying: playing)
    }

    private func handleNativeFailure(_ attempt: UUID) {
        guard playbackAttemptID == attempt else { return }
        if retryCount < 2 {
            retryCount += 1
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard playbackAttemptID == attempt else { return }
                playbackAttemptID = UUID()
            }
        } else if playbackSource == .stream && !listenMode {
            useNativePlayer = false
        } else {
            playbackFailed = true
        }
    }

    private var sleepTimerMenu: some View {
        Menu {
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) minutes") { playerController.startSleepTimer(minutes: minutes) }
            }
            if playerController.sleepTimerDeadline != nil {
                Divider()
                Button("Turn Off Timer", role: .destructive) { playerController.cancelSleepTimer() }
            }
        } label: {
            Label(
                playerController.sleepTimerDeadline == nil ? "Sleep Timer" : "Timer Set",
                systemImage: playerController.sleepTimerDeadline == nil ? "moon.zzz" : "timer"
            )
        }
        .buttonStyle(.glass)
    }

    private func switchListenMode(_ enabled: Bool) {
        if playerController.isPlaying { playerController.requestPlaybackStart() }
        listenMode = enabled
        useNativePlayer = true
        playbackFailed = false
        retryCount = 0
        playbackAttemptID = UUID()
    }

    private func beginDownload() {
        downloadError = nil
        Task {
            do {
                _ = try await viewModel.download(currentPodcast)
            } catch is CancellationError {
                return
            } catch {
                downloadError = error.localizedDescription
            }
        }
    }
}

private struct IOSListenModeOverlay: View {
    let title: String
    @ObservedObject var controller: PlayerController
    let onExit: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo.opacity(0.96), Color.cyan.opacity(0.62), Color.black.opacity(0.94)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 10) {
                HStack {
                    Label("LISTEN MODE", systemImage: "headphones")
                        .font(.caption.bold())
                        .tracking(1.1)
                    Spacer()
                    Button("Show Video", systemImage: "play.rectangle", action: onExit)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                }
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 24) {
                    Button { controller.skip(by: -15) } label: {
                        Image(systemName: "gobackward.15").font(.title2)
                    }
                    Button { controller.togglePlayback() } label: {
                        Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2.bold())
                            .frame(width: 48, height: 48)
                            .background(.white.opacity(0.18), in: Circle())
                    }
                    Button { controller.skip(by: 30) } label: {
                        Image(systemName: "goforward.30").font(.title2)
                    }
                }
                .buttonStyle(.plain)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let remaining = controller.sleepTimerRemaining {
                        Label("Stops in \(formatted(remaining))", systemImage: "moon.zzz.fill")
                            .font(.caption.monospacedDigit())
                    } else {
                        Text("Original audio · continues with screen locked")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.white.opacity(0.78))
            }
            .foregroundStyle(.white)
            .padding(18)
        }
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct IOSCommitmentCard: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let commitment: FocusCommitment
    let isStarting: Bool

    var body: some View {
        IOSGlassSurface(cornerRadius: 18, tint: .accentColor.opacity(0.12)) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label(commitment.cue.isDistraction ? "Distraction Rescue" : "Focus commitment", systemImage: "timer")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(isStarting ? "Starting…" : viewModel.isTracking ? "Playing" : "Paused")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(viewModel.isTracking ? .green : .secondary)
                }
                ProgressView(value: commitment.progress)
                HStack {
                    Text("\(Int(ceil(commitment.remainingSeconds / 60))) min left")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", role: .destructive) { viewModel.cancelActiveCommitment() }
                        .font(.caption)
                }
            }
            .padding(15)
        }
        .padding(.horizontal, 18)
    }
}

private struct IOSSummaryView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let podcast: Podcast
    let playerController: PlayerController
    let onPaste: () -> Void
    let onImport: () -> Void

    var body: some View {
        Group {
            if let summary = viewModel.summary(for: podcast.id) {
                summaryContent(summary)
            } else {
                emptyState
            }
        }
        .padding(.horizontal, 18)
    }

    private func summaryContent(_ summary: PodcastSummary) -> some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            IOSGlassSurface(cornerRadius: 20) {
                Text(summary.brief)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(17)
            }
            if summary.sections.isEmpty {
                summarySection("Key topics", symbol: "list.number") {
                    ForEach(Array(summary.keyTopics.enumerated()), id: \.element.id) { index, topic in
                        learningPoint(index: index + 1, title: topic.title, explanation: topic.explanation, timestamp: topic.timestampSeconds)
                    }
                }
                summarySection("Major takeaways", symbol: "lightbulb.max.fill") {
                    ForEach(summary.majorTakeaways) { takeaway in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(takeaway.title).font(.headline)
                            Text(takeaway.explanation).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            } else {
                ForEach(summary.sections) { section in
                    summarySection(section.title, symbol: "text.book.closed.fill") {
                        if let introduction = section.introduction {
                            Text(introduction).foregroundStyle(.secondary)
                        }
                        ForEach(Array(section.points.enumerated()), id: \.element.id) { index, point in
                            learningPoint(index: index + 1, title: point.title, explanation: point.explanation, timestamp: point.timestampSeconds)
                        }
                    }
                }
            }
            if !summary.actionPlan.isEmpty {
                summarySection("Try this", symbol: "checklist") {
                    ForEach(summary.actionPlan) { action in
                        Button { viewModel.toggleAction(podcastID: podcast.id, actionID: action.id) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: action.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(action.isCompleted ? .green : .secondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(action.title).font(.headline).foregroundStyle(.primary)
                                    Text(action.detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 5)
                    }
                }
            }
            Text("Generated \(summary.generatedAt.formatted(date: .abbreviated, time: .shortened)) · \(summary.model)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func learningPoint(index: Int, title: String, explanation: String, timestamp: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(index)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22, alignment: .leading)
                Text(title).font(.headline)
                Spacer()
                if let timestamp {
                    Button(timestamp.podTimestamp) { playerController.seek(to: timestamp) }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
            Text(explanation).foregroundStyle(.secondary).padding(.leading, 22)
        }
        .padding(.vertical, 5)
    }

    private func summarySection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.title3.bold())
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        IOSGlassSurface(cornerRadius: 24) {
            VStack(spacing: 16) {
                Image(systemName: "text.document.badge.sparkles")
                    .font(.system(size: 38))
                    .foregroundStyle(.tint)
                Text("Turn this episode into a study guide").font(.title3.bold()).multilineTextAlignment(.center)
                Text(statusCopy).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                controls
                HStack {
                    Button("Paste transcript", action: onPaste)
                    Button("Import file", action: onImport)
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(22)
        }
    }

    private var statusCopy: String {
        switch viewModel.summaryState {
        case .idle, .completed: "PodTrackio fetches a timestamped transcript, then Groq turns it into a source-faithful learning guide."
        case .fetchingTranscript: "Fetching a timestamped transcript…"
        case .fetchingCaptions: "Looking for public captions…"
        case .needsAudioConsent: "No captions were available. Audio transcription downloads media and uses Groq credits."
        case .downloadingAudio(let progress): "Downloading audio… \(Int(progress * 100))%"
        case .transcribing(let current, let total): "Transcribing part \(current) of \(total)…"
        case .synthesizing: "Finding the ideas, frameworks, examples, and actions in this episode…"
        case .needsTranscriptImport(let reason): "Automatic extraction failed: \(reason)"
        case .failed(let message): message
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch viewModel.summaryState {
        case .fetchingTranscript, .fetchingCaptions, .downloadingAudio, .transcribing, .synthesizing:
            HStack { ProgressView(); Button("Cancel") { viewModel.cancelSummaryGeneration() }.buttonStyle(.glass) }
        case .needsAudioConsent:
            Button("Transcribe Audio", systemImage: "waveform") {
                viewModel.generateSummary(for: podcast, allowAudioTranscription: true)
            }
            .buttonStyle(.glassProminent)
        case .needsTranscriptImport:
            Button("Paste Transcript", action: onPaste).buttonStyle(.glassProminent)
        default:
            Button("Generate Summary", systemImage: "sparkles") { viewModel.generateSummary(for: podcast) }
                .buttonStyle(.glassProminent)
        }
    }
}

private struct IOSNotesView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let podcast: Podcast
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Notes", subtitle: "Saved automatically and synced with your episode")
            TextEditor(text: $notes)
                .frame(minHeight: 320)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .onAppear { notes = podcast.notes }
                .onChange(of: notes) { _, value in viewModel.updateNotes(for: podcast.id, notes: value) }
        }
        .padding(.horizontal, 18)
    }
}

private struct IOSQuirkyChatView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let podcast: Podcast
    @State private var draft = ""
    @State private var isThinking = false
    @State private var errorMessage: String?
    @State private var responseTask: Task<Void, Never>?
    @AppStorage("quirky.selectedModel") private var selectedModelRaw = QuirkyModel.balanced.rawValue
    @AppStorage("quirky.answerStyle") private var answerStyleRaw = QuirkyAnswerStyle.medium.rawValue
    @FocusState private var composerFocused: Bool

    private var selectedModel: QuirkyModel { QuirkyModel(rawValue: selectedModelRaw) ?? .balanced }
    private var answerStyle: QuirkyAnswerStyle { QuirkyAnswerStyle(rawValue: answerStyleRaw) ?? .medium }
    private var messages: [QuirkyChatMessage] { viewModel.quirkyMessages(for: podcast.id) }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                QuirkyMark(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quirky").font(.headline)
                    Text("Your transcript mentor").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                modelMenu
                answerStyleMenu
                if !messages.isEmpty {
                    Button("New Chat", systemImage: "square.and.pencil") {
                        viewModel.clearQuirkyConversation(for: podcast.id)
                        errorMessage = nil
                    }
                    .labelStyle(.iconOnly)
                    .disabled(isThinking)
                }
            }

            if messages.isEmpty {
                VStack(spacing: 10) {
                    Text("What do you want to understand?").font(.title3.bold())
                    Text("Recover missing steps, challenge an idea, or apply the lesson to a real project.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    suggestion("Recover the complete framework", icon: "list.number")
                    suggestion("Apply the strongest lesson", icon: "arrow.triangle.branch")
                    suggestion("Challenge the speaker’s advice", icon: "checkmark.seal")
                }
                .padding(.vertical, 16)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in QuirkyMessageBubble(message: message) }
                    if isThinking {
                        HStack { QuirkyMark(size: 28); ProgressView(); Text("Thinking with \(selectedModel.title.lowercased()) reasoning…").font(.caption).foregroundStyle(.secondary); Spacer() }
                    }
                }
            }

            VStack(spacing: 8) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Ask about this episode…", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($composerFocused)
                    Button { send() } label: {
                        Image(systemName: "arrow.up").font(.headline).frame(width: 34, height: 34)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                }
                .padding(11)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text("Grounded in the saved transcript · \(selectedModel.title) reasoning")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .onDisappear { responseTask?.cancel() }
    }

    private var modelMenu: some View {
        Menu {
            ForEach(QuirkyModel.allCases) { model in
                Button { selectedModelRaw = model.rawValue } label: {
                    Label(model.title, systemImage: model == selectedModel ? "checkmark" : model.symbol)
                }
            }
        } label: {
            Label(selectedModel.title, systemImage: selectedModel.symbol).font(.caption.weight(.semibold))
        }
        .disabled(isThinking)
    }

    private var answerStyleMenu: some View {
        Menu {
            ForEach(QuirkyAnswerStyle.allCases) { style in
                Button { answerStyleRaw = style.rawValue } label: {
                    Label(style.title, systemImage: style == answerStyle ? "checkmark" : "text.alignleft")
                }
            }
        } label: {
            Label(answerStyle.title, systemImage: "text.alignleft")
                .font(.caption.weight(.semibold))
        }
        .disabled(isThinking)
    }

    private func suggestion(_ title: String, icon: String) -> some View {
        Button {
            let prompt: String
            switch icon {
            case "list.number": prompt = "Find the main framework or process in this video. Give me every step in order, explain each one, and cite the relevant timestamps."
            case "arrow.triangle.branch": prompt = "Help me apply the strongest lesson from this video to one of my projects. Give me a useful first pass, then ask one question to personalize it."
            default: prompt = "Stress-test the speaker's core advice. What is strong, what depends on assumptions, and where could following it blindly fail?"
            }
            send(prompt)
        } label: {
            HStack { Image(systemName: icon).foregroundStyle(.tint).frame(width: 22); Text(title); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.tertiary) }
                .font(.subheadline)
                .padding(13)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .podCard(cornerRadius: 15)
    }

    private func send(_ suggested: String? = nil) {
        let question = (suggested ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }
        let model = selectedModel
        let style = answerStyle
        let history = messages.map { ($0.role == .user ? "user" : "assistant", $0.text) }
        draft = ""
        errorMessage = nil
        isThinking = true
        viewModel.appendQuirkyMessage(.init(role: .user, text: question, model: nil), podcastID: podcast.id)
        responseTask = Task {
            do {
                let answer = try await viewModel.askTranscriptQuestion(
                    for: podcast,
                    question: question,
                    history: history,
                    model: model,
                    answerStyle: style
                )
                guard !Task.isCancelled else { return }
                viewModel.appendQuirkyMessage(.init(role: .quirky, text: answer, model: model, answerStyle: style), podcastID: podcast.id)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            isThinking = false
        }
    }
}

private struct QuirkyMark: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.14))
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct QuirkyMessageBubble: View {
    let message: QuirkyChatMessage
    private var rendered: AttributedString { (try? AttributedString(markdown: message.text)) ?? AttributedString(message.text) }

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                QuirkyMark(size: 30)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Quirky").font(.caption.bold())
                        if let model = message.model { Text(model.title).font(.caption2).foregroundStyle(.tertiary) }
                    }
                    Text(rendered).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 12)
            }
        }
    }
}

struct IOSPasteTranscriptSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let podcast: Podcast
    @State private var text = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body.monospaced())
                .padding()
                .navigationTitle("Paste Transcript")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Summarize") {
                            viewModel.generateSummary(
                                for: podcast,
                                transcript: TranscriptImporter.document(text: text, podcastID: podcast.id)
                            )
                            dismiss()
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}
