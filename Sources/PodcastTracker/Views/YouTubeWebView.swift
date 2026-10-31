import AppKit
import SwiftUI
import WebKit

struct YouTubeWebView: NSViewRepresentable {
    let videoId: String
    let startPosition: Double
    @ObservedObject var controller: PlayerController
    let onTimeUpdate: (Double) -> Void
    let onDurationReady: (Double) -> Void
    let onPlayStateChange: (Bool) -> Void
    let onError: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()

        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = pagePreferences

        let preferences = WKPreferences()
        preferences.isElementFullscreenEnabled = true
        configuration.preferences = preferences

        let contentController = WKUserContentController()
        for name in Coordinator.messageNames {
            contentController.add(context.coordinator, name: name)
        }
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        controller.attach(webView: webView)
        loadVideo(in: webView, videoId: videoId, start: startPosition)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.currentVideoId != videoId else { return }
        context.coordinator.currentVideoId = videoId
        controller.attach(webView: webView)
        loadVideo(in: webView, videoId: videoId, start: startPosition)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        for name in Coordinator.messageNames {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            videoId: videoId,
            controller: controller,
            onTimeUpdate: onTimeUpdate,
            onDurationReady: onDurationReady,
            onPlayStateChange: onPlayStateChange,
            onError: onError
        )
    }

    private func loadVideo(in webView: WKWebView, videoId: String, start: Double) {
        guard let html = Self.playerDocument(videoID: videoId, startPosition: start) else {
            onError()
            return
        }
        webView.loadHTMLString(html, baseURL: Self.playerOrigin)
    }

    static var playerOrigin: URL {
        URL(string: "https://\((Bundle.main.bundleIdentifier ?? "com.tangenix.podtrackio").lowercased())/")!
    }

    static func playerDocument(videoID: String, startPosition: Double) -> String? {
        guard videoID.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else { return nil }
        let start = startPosition.isFinite ? Int(min(604_800, max(0, startPosition))) : 0
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body,#player{width:100%;height:100%;margin:0;background:#000;overflow:hidden}</style></head>
        <body><div id="player"></div><script>
        var player, wantPlay=false;
        function post(name,value){window.webkit.messageHandlers[name].postMessage(value);}
        window.podTrackioPlay=function(){wantPlay=true;if(player&&player.playVideo)player.playVideo();};
        window.podTrackioSeek=function(seconds){if(player&&player.seekTo)player.seekTo(seconds,true);};
        function report(){if(player&&player.getCurrentTime&&player.getPlayerState){
            var time=player.getCurrentTime(), duration=player.getDuration();
            if(Number.isFinite(time))post('timeUpdate',time);
            if(Number.isFinite(duration)&&duration>0)post('durationReady',duration);
            post('playStateChange',player.getPlayerState()===1?'playing':'paused');}}
        function onYouTubeIframeAPIReady(){player=new YT.Player('player',{videoId:'\(videoID)',width:'100%',height:'100%',
            playerVars:{start:\(start),playsinline:1,origin:'\(playerOrigin.absoluteString)',rel:0},events:{
            onReady:function(){post('playerReady','ready');if(wantPlay)player.playVideo();report();},
            onStateChange:report,onError:function(e){post('playerError',String(e.data));}}});}
        setInterval(report,1000);
        </script><script src="https://www.youtube.com/iframe_api" onerror="post('playerError','network')"></script></body></html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let messageNames = [
            "timeUpdate", "durationReady", "playStateChange", "playerReady", "playerError"
        ]

        var currentVideoId: String
        weak var controller: PlayerController?
        let onTimeUpdate: (Double) -> Void
        let onDurationReady: (Double) -> Void
        let onPlayStateChange: (Bool) -> Void
        let onError: () -> Void

        init(
            videoId: String,
            controller: PlayerController,
            onTimeUpdate: @escaping (Double) -> Void,
            onDurationReady: @escaping (Double) -> Void,
            onPlayStateChange: @escaping (Bool) -> Void,
            onError: @escaping () -> Void
        ) {
            currentVideoId = videoId
            self.controller = controller
            self.onTimeUpdate = onTimeUpdate
            self.onDurationReady = onDurationReady
            self.onPlayStateChange = onPlayStateChange
            self.onError = onError
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            Task { @MainActor in
                switch message.name {
                case "timeUpdate":
                    if let value = message.body as? Double { onTimeUpdate(value) }
                case "durationReady":
                    if let value = message.body as? Double { onDurationReady(value) }
                case "playStateChange":
                    onPlayStateChange((message.body as? String) == "playing")
                case "playerReady":
                    controller?.playerDidBecomeReady()
                case "playerError":
                    onError()
                default:
                    break
                }
            }
        }

        @MainActor
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    NSWorkspace.shared.open(url)
                }
                return .cancel
            }
            return .allow
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor in onError() }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor in onError() }
        }
    }
}
