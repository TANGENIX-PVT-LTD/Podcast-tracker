import AVFoundation
import Foundation
import WebKit

@MainActor
final class PlayerController: ObservableObject {
    enum Backend {
        case native
        case embed
    }

    @Published private(set) var isPlaybackStartPending = false
    @Published private(set) var isEmbedPlayerReady = false
    @Published private(set) var isPlaying = false
    @Published private(set) var sleepTimerDeadline: Date?
    private(set) var backend: Backend = .native

    private weak var webView: WKWebView?
    private weak var player: AVPlayer?
    private var playbackStartRequested = false
    private var pendingIndicatorTask: Task<Void, Never>?
    private var sleepTimerObserver: Any?

    func seek(to seconds: Double) {
        AppViewModel.shared.resetPlaybackCredit()
        let clamped = max(0, seconds)
        switch backend {
        case .native:
            player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        case .embed:
            webView?.evaluateJavaScript("window.podTrackioSeek(\(clamped));", completionHandler: nil)
        }
    }

    func skip(by seconds: Double) {
        guard case .native = backend, let player else { return }
        let current = player.currentTime().seconds
        guard current.isFinite else { return }
        player.seek(to: CMTime(seconds: max(0, current + seconds), preferredTimescale: 600))
    }

    func togglePlayback() {
        guard case .native = backend, let player else { return }
        if player.rate == 0 {
            player.play()
        } else {
            player.pause()
        }
    }

    func startSleepTimer(minutes: Int) {
        guard minutes > 0 else { cancelSleepTimer(); return }
        sleepTimerDeadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        scheduleSleepTimerIfPossible()
    }

    func cancelSleepTimer() {
        sleepTimerDeadline = nil
        removeSleepTimerObserver()
    }

    var sleepTimerRemaining: TimeInterval? {
        guard let sleepTimerDeadline else { return nil }
        return max(0, sleepTimerDeadline.timeIntervalSinceNow)
    }

    func requestPlaybackStart() {
        playbackStartRequested = true
        isPlaybackStartPending = true
        issuePlaybackStartIfReady()
        pendingIndicatorTask?.cancel()
        pendingIndicatorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.isPlaybackStartPending = false
        }
    }

    func playerStateDidChange(isPlaying: Bool) {
        self.isPlaying = isPlaying
        guard isPlaying else { return }
        playbackStartRequested = false
        isPlaybackStartPending = false
        pendingIndicatorTask?.cancel()
    }

    func attach(player: AVPlayer) {
        removeSleepTimerObserver()
        backend = .native
        self.player = player
        webView = nil
        scheduleSleepTimerIfPossible()
    }

    func attach(webView: WKWebView) {
        removeSleepTimerObserver()
        backend = .embed
        self.webView = webView
        player = nil
        isEmbedPlayerReady = false
    }

    func playerDidBecomeReady() {
        isEmbedPlayerReady = true
        issuePlaybackStartIfReady()
    }

    private func issuePlaybackStartIfReady() {
        guard playbackStartRequested else { return }
        switch backend {
        case .native:
            player?.play()
        case .embed:
            guard isEmbedPlayerReady else { return }
            webView?.evaluateJavaScript("window.podTrackioPlay();", completionHandler: nil)
        }
    }

    private func scheduleSleepTimerIfPossible() {
        removeSleepTimerObserver()
        guard let player, let sleepTimerDeadline else { return }
        let remaining = sleepTimerDeadline.timeIntervalSinceNow
        guard remaining > 0 else {
            expireSleepTimer()
            return
        }
        let current = player.currentTime().seconds
        let target = (current.isFinite ? current : 0) + remaining
        sleepTimerObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: CMTime(seconds: target, preferredTimescale: 600))],
            queue: .main
        ) { [weak self] in
            MainActor.assumeIsolated { self?.expireSleepTimer() }
        }
    }

    private func expireSleepTimer() {
        player?.pause()
        sleepTimerDeadline = nil
        removeSleepTimerObserver()
    }

    private func removeSleepTimerObserver() {
        guard let sleepTimerObserver else { return }
        player?.removeTimeObserver(sleepTimerObserver)
        self.sleepTimerObserver = nil
    }
}
