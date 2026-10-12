import AVKit
import OSLog
import SwiftUI

enum PlaybackResumePosition {
    static func target(requested: Double, duration: Double?) -> Double {
        guard requested.isFinite, requested > 1 else { return 0 }
        guard let duration, duration.isFinite, duration > 1 else { return requested }
        return min(requested, max(0, duration - 1))
    }
}

struct IOSNativePlayerView: View {
    let videoID: String
    let title: String
    let startPosition: Double
    let reloadID: UUID
    let source: NativePlaybackSource
    let listenOnly: Bool
    @ObservedObject var controller: PlayerController
    let onTimeUpdate: (Double) -> Void
    let onDurationReady: (Double) -> Void
    let onPlayStateChange: (Bool) -> Void
    let onFailure: () -> Void

    @State private var player: AVPlayer?
    private let logger = Logger(subsystem: "com.tangenix.podtrackio", category: "iOSPlayback")

    var body: some View {
        ZStack {
            Color.black
            if let player {
                IOSAVPlayerController(
                    player: player,
                    onTimeUpdate: onTimeUpdate,
                    onPlayStateChange: onPlayStateChange,
                    onFailure: onFailure
                )
            } else {
                IOSLoadingStatus(
                    title: source == .local ? "Opening download" : "Preparing stream",
                    detail: source == .local ? "Loading your offline copy…" : "Connecting to the original media…",
                    onDarkBackground: true
                )
                .padding(24)
            }
        }
        .task(id: reloadID) { await loadPlayer() }
        .onDisappear { player?.pause() }
    }

    private func loadPlayer() async {
        let previous = player
        player = nil
        previous?.pause()
        do {
            configureAudioSession()
            let item = try await YouTubeStreamResolver.playableItem(
                videoId: videoID,
                source: source,
                listenOnly: listenOnly
            )
            item.externalMetadata = nowPlayingMetadata
            guard !Task.isCancelled else { return }
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            newPlayer.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            newPlayer.preventsDisplaySleepDuringVideoPlayback = !listenOnly
            controller.attach(player: newPlayer)
            player = newPlayer

            let time = try? await item.asset.load(.duration)
            let duration = time.flatMap { $0.isValid && !$0.isIndefinite && $0.seconds > 0 ? $0.seconds : nil }
            if let duration { onDurationReady(duration) }
            let resume = PlaybackResumePosition.target(requested: startPosition, duration: duration)
            if resume > 0 {
                await newPlayer.seek(
                    to: CMTime(seconds: resume, preferredTimescale: 600),
                    toleranceBefore: CMTime(seconds: 1, preferredTimescale: 600),
                    toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)
                )
            }
            guard !Task.isCancelled else { newPlayer.pause(); return }
            controller.playerDidBecomeReady()
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Player preparation failed: \(error.localizedDescription, privacy: .public)")
            onFailure()
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: listenOnly ? .spokenAudio : .moviePlayback)
            try session.setActive(true)
        } catch {
            logger.error("Audio session setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var nowPlayingMetadata: [AVMetadataItem] {
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = title as NSString
        titleItem.extendedLanguageTag = "und"

        let artistItem = AVMutableMetadataItem()
        artistItem.identifier = .commonIdentifierArtist
        artistItem.value = "PodTrackio" as NSString
        artistItem.extendedLanguageTag = "und"
        return [titleItem, artistItem]
    }
}

private struct IOSAVPlayerController: UIViewControllerRepresentable {
    let player: AVPlayer
    let onTimeUpdate: (Double) -> Void
    let onPlayStateChange: (Bool) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTimeUpdate: onTimeUpdate, onPlayStateChange: onPlayStateChange, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = true
        controller.videoGravity = .resizeAspect
        context.coordinator.startObserving(player)
        return controller
    }

    func updateUIViewController(_ viewController: AVPlayerViewController, context: Context) {
        guard viewController.player !== player else { return }
        context.coordinator.stopObserving()
        viewController.player = player
        context.coordinator.startObserving(player)
    }

    static func dismantleUIViewController(_ viewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.stopObserving()
        viewController.player = nil
    }

    @MainActor
    final class Coordinator {
        private let onTimeUpdate: (Double) -> Void
        private let onPlayStateChange: (Bool) -> Void
        private let onFailure: () -> Void
        private var timeObserver: Any?
        private var rateObservation: NSKeyValueObservation?
        private var statusObservation: NSKeyValueObservation?
        private var endObserver: NSObjectProtocol?
        private var failureObserver: NSObjectProtocol?
        private weak var observedPlayer: AVPlayer?

        init(
            onTimeUpdate: @escaping (Double) -> Void,
            onPlayStateChange: @escaping (Bool) -> Void,
            onFailure: @escaping () -> Void
        ) {
            self.onTimeUpdate = onTimeUpdate
            self.onPlayStateChange = onPlayStateChange
            self.onFailure = onFailure
        }

        func startObserving(_ player: AVPlayer) {
            observedPlayer = player
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1, preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                MainActor.assumeIsolated { self?.onTimeUpdate(time.seconds) }
            }
            rateObservation = player.observe(\.rate, options: [.initial, .new]) { [weak self] player, _ in
                Task { @MainActor [weak self] in self?.onPlayStateChange(player.rate != 0) }
            }
            statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor [weak self] in self?.onFailure() }
            }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.onPlayStateChange(false) } }
            failureObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.onFailure() } }
        }

        func stopObserving() {
            if let timeObserver, let observedPlayer { observedPlayer.removeTimeObserver(timeObserver) }
            rateObservation?.invalidate()
            statusObservation?.invalidate()
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
            timeObserver = nil
            rateObservation = nil
            statusObservation = nil
            endObserver = nil
            failureObserver = nil
            observedPlayer = nil
        }
    }
}
