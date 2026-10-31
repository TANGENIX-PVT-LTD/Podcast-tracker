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
        guard let html = Self.playerDocument(videoID: videoID, startPosition: startPosition) else {
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
