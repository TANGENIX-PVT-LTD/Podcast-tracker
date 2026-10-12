import SwiftUI
import UIKit
import WebKit

struct IOSYouTubeWebView: UIViewRepresentable {
    let videoID: String
    let startPosition: Double
    @ObservedObject var controller: PlayerController
    let onTimeUpdate: (Double) -> Void
    let onDurationReady: (Double) -> Void
    let onPlayStateChange: (Bool) -> Void
    let onError: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            videoID: videoID,
            controller: controller,
            onTimeUpdate: onTimeUpdate,
            onDurationReady: onDurationReady,
            onPlayStateChange: onPlayStateChange,
            onError: onError
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        for name in Coordinator.messageNames {
            configuration.userContentController.add(context.coordinator, name: name)
        }
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        controller.attach(webView: webView)
        load(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.currentVideoID != videoID else { return }
        context.coordinator.currentVideoID = videoID
        controller.attach(webView: webView)
        load(in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        for name in Coordinator.messageNames {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    private func load(in webView: WKWebView) {
        var components = URLComponents(string: "https://www.youtube.com/embed/\(videoID)")!
        components.queryItems = [
            .init(name: "enablejsapi", value: "1"),
            .init(name: "origin", value: "https://www.youtube.com"),
            .init(name: "start", value: String(max(0, Int(startPosition)))),
            .init(name: "controls", value: "1"),
            .init(name: "playsinline", value: "1"),
            .init(name: "rel", value: "0"),
            .init(name: "fs", value: "1")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        webView.load(request)
    }

    private static let bridgeScript = #"""
    (function() {
      if (window.__podTrackioBridgeInstalled) return;
      window.__podTrackioBridgeInstalled = true;
      var observedVideo = null, reportedReady = false, lastPlaying = null, reportedError = false;
      function post(name, value) {
        try { var h = window.webkit && window.webkit.messageHandlers[name]; if (h) h.postMessage(value); } catch (_) {}
      }
      function reportError() { if (!reportedError) { reportedError = true; post('playerError', 'failed'); } }
      function report(video) {
        if (!video) return;
        if (!reportedReady && video.readyState >= 1) { reportedReady = true; post('playerReady', 'ready'); }
        if (Number.isFinite(video.duration) && video.duration > 0) post('durationReady', video.duration);
        if (Number.isFinite(video.currentTime)) post('timeUpdate', video.currentTime);
        var playing = !video.paused && !video.ended;
        if (playing !== lastPlaying) { lastPlaying = playing; post('playStateChange', playing ? 'playing' : 'paused'); }
      }
      function attach(video) {
        if (!video || observedVideo === video) return;
        observedVideo = video; reportedReady = false; lastPlaying = null;
        ['loadedmetadata','durationchange','play','pause','ended'].forEach(function(e) { video.addEventListener(e, function() { report(video); }); });
        video.addEventListener('error', reportError); report(video);
      }
      window.podTrackioSeek = function(seconds) { var v = observedVideo || document.querySelector('video'); if (v && Number.isFinite(seconds)) v.currentTime = Math.max(0, seconds); };
      window.podTrackioPlay = function() { var v = observedVideo || document.querySelector('video'); if (v) v.play().catch(function() {}); };
      function poll() {
        var v = document.querySelector('video'); attach(v); report(v);
        var text = document.body ? (document.body.innerText || '') : '';
        if (text.indexOf('Error code:') !== -1 || text.indexOf('This video is unavailable') !== -1 || text.indexOf('Playback on other websites has been disabled') !== -1) reportError();
      }
      setInterval(poll, 750); document.addEventListener('DOMContentLoaded', poll); poll();
    })();
    """#

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let messageNames = ["timeUpdate", "durationReady", "playStateChange", "playerReady", "playerError"]
        var currentVideoID: String
        weak var controller: PlayerController?
        let onTimeUpdate: (Double) -> Void
        let onDurationReady: (Double) -> Void
        let onPlayStateChange: (Bool) -> Void
        let onError: () -> Void

        init(
            videoID: String,
            controller: PlayerController,
            onTimeUpdate: @escaping (Double) -> Void,
            onDurationReady: @escaping (Double) -> Void,
            onPlayStateChange: @escaping (Bool) -> Void,
            onError: @escaping () -> Void
        ) {
            currentVideoID = videoID
            self.controller = controller
            self.onTimeUpdate = onTimeUpdate
            self.onDurationReady = onDurationReady
            self.onPlayStateChange = onPlayStateChange
            self.onError = onError
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            Task { @MainActor in
                switch message.name {
                case "timeUpdate": if let value = message.body as? Double { onTimeUpdate(value) }
                case "durationReady": if let value = message.body as? Double { onDurationReady(value) }
                case "playStateChange": onPlayStateChange((message.body as? String) == "playing")
                case "playerReady": controller?.playerDidBecomeReady()
                case "playerError": onError()
                default: break
                }
            }
        }

        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                await UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in onError() }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in onError() }
        }
    }
}
