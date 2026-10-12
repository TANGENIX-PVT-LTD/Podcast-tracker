import SwiftUI
import WebKit

struct BrainCanvasPayload: Encodable {
    struct Node: Encodable { let id: String; let sourceID: String; let title: String; let kind: String }
    struct Link: Encodable { let source: String; let target: String; let type: String }
    let nodes: [Node]
    let links: [Link]
    let dark: Bool
    let reduceMotion: Bool

    init(documents: [BrainSource], dark: Bool, reduceMotion: Bool) {
        self.dark = dark; self.reduceMotion = reduceMotion
        var nodes: [Node] = [], links: [Link] = [], seen = Set<UUID>()
        for source in documents {
            let episodeID = "episode:" + source.podcastID.uuidString
            if seen.insert(source.podcastID).inserted {
                nodes.append(Node(id: episodeID, sourceID: source.id, title: source.title, kind: "Episode"))
            }
            nodes.append(Node(id: source.id, sourceID: source.id, title: source.kind, kind: source.kind))
            links.append(Link(source: episodeID, target: source.id, type: "document"))
        }
        var pairs = Set<String>()
        for edge in BrainGraph.edges(documents) where !edge.sharedEpisode {
            let ids = ["episode:" + documents[edge.from].podcastID.uuidString, "episode:" + documents[edge.to].podcastID.uuidString].sorted()
            if pairs.insert(ids.joined()).inserted { links.append(Link(source: ids[0], target: ids[1], type: "topic")) }
        }
        self.nodes = nodes; self.links = links
    }
}

struct BrainCanvasView: View {
    let documents: [BrainSource]
    var onSelect: (BrainSource) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BrainCanvasWebView(payload: BrainCanvasPayload(documents: documents, dark: scheme == .dark, reduceMotion: reduceMotion)) { id in
            if let source = documents.first(where: { $0.id == id }) { onSelect(source) }
        }
        .accessibilityLabel("Learning canvas")
    }
}

@MainActor
private struct BrainCanvasWebView {
    let payload: BrainCanvasPayload
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    @MainActor func makeWebView(coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(coordinator, name: "brainCanvas")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = coordinator
        #if os(macOS)
        web.setValue(false, forKey: "drawsBackground")
        #else
        web.isOpaque = false; web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        #endif
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        if let url = bundle.url(forResource: "index", withExtension: "html", subdirectory: "BrainCanvas") ?? bundle.url(forResource: "index", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        update(web, coordinator: coordinator)
        return web
    }

    @MainActor func update(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.onSelect = onSelect
        guard let data = try? JSONEncoder().encode(payload), let json = String(data: data, encoding: .utf8) else { return }
        coordinator.script = "window.brainGraph?.setData(\(json));"
        if coordinator.loaded { web.evaluateJavaScript(coordinator.script, completionHandler: nil) }
    }

    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onSelect: (String) -> Void
        var script = ""
        var loaded = false
        init(onSelect: @escaping (String) -> Void) { self.onSelect = onSelect }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: String], let id = body["id"] else { return }
            onSelect(id)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true; webView.evaluateJavaScript(script, completionHandler: nil)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }
    }
}

#if os(macOS)
extension BrainCanvasWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateNSView(_ nsView: WKWebView, context: Context) { update(nsView, coordinator: context.coordinator) }
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.evaluateJavaScript("window.brainGraph?.dispose();", completionHandler: nil)
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "brainCanvas")
        nsView.stopLoading()
    }
}
#else
extension BrainCanvasWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateUIView(_ uiView: WKWebView, context: Context) { update(uiView, coordinator: context.coordinator) }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.evaluateJavaScript("window.brainGraph?.dispose();", completionHandler: nil)
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "brainCanvas")
        uiView.stopLoading()
    }
}
#endif
