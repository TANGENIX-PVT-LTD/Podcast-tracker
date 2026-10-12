import Foundation
import Testing
@testable import PodcastTracker

@Suite("Brain retrieval and memory safety")
struct BrainTests {
    @Test func findsEvidenceBeyondTranscriptPrefixAndPreservesOrigin() {
        let id = UUID()
        let text = Array(repeating: "ordinary introduction filler", count: 2000).joined(separator: " ") + " spaced repetition improves long term retention"
        let passages = BrainIndex.passages(id: "episode", podcastID: id, title: "Learning", kind: "Transcript", text: text)
        let result = BrainIndex(sources: passages).retrieve("spaced repetition retention")
        #expect(result.first?.text.contains("spaced repetition") == true)
        #expect(result.first?.podcastID == id)
        #expect(result.first?.kind == "Transcript")
    }

    @Test func unrelatedQueryDoesNotManufactureEvidence() {
        let source = BrainSource(id: "a", podcastID: UUID(), title: "Gardening", kind: "Summary", text: "Plants require sunlight")
        #expect(BrainIndex(sources: [source]).retrieve("quantum computing").isEmpty)
    }

    @Test func boundsContextAndDiversifiesEpisodes() {
        let a = UUID(), b = UUID()
        let sources = (0..<12).map { BrainSource(id: "\($0)", podcastID: $0 < 10 ? a : b, title: "Memory", kind: "Transcript", text: "memory practice retrieval") }
        let result = BrainIndex(sources: sources).retrieve("memory", budget: 300)
        #expect(result.filter { $0.podcastID == a }.count <= 3)
        #expect(Set(result.map(\.podcastID)).count == 2)
        #expect(result.map { $0.text.count }.reduce(0, +) <= 300)
    }

    @Test func promptDistinguishesEvidenceAndDisablesLearning() {
        let prompt = BrainPrompt.system(goal: "Learn design", memories: [], sources: [], learn: false)
        #expect(prompt.contains("Memory extraction enabled: false"))
        #expect(prompt.contains("No relevant passages found"))
        #expect(prompt.contains("untrusted data"))
    }

    @Test func graphKeepsProvenanceButBoundsKeywordEdges() {
        let episode = UUID()
        let nodes = (0..<10).map { BrainSource(id: "\($0)", podcastID: $0 < 2 ? episode : UUID(), title: "Episode \($0)", kind: $0 == 0 ? "Summary" : "Transcript", text: "shared vocabulary topic evidence \($0)") }
        let edges = BrainGraph.edges(nodes)
        #expect(edges.contains { $0.from == 0 && $0.to == 1 && $0.sharedEpisode })
        for index in nodes.indices {
            #expect(edges.filter { !$0.sharedEpisode && ($0.from == index || $0.to == index) }.count <= 2)
        }
    }

    @Test func broadOverviewUsesMultipleEpisodeSummaries() {
        let nodes = (0..<3).map { BrainSource(id: "\($0)", podcastID: UUID(), title: "Episode", kind: "Summary", text: "Specific learning \($0)") }
        #expect(BrainIndex(sources: nodes).retrieve("What have I learned?").count == 3)
    }

    @Test func composerSelectionsControlProviderRequest() throws {
        for model in QuirkyModel.allCases {
            for style in QuirkyAnswerStyle.allCases {
                let body = BrainRequest.body(system: "Evidence policy", question: "Explain this", history: [], model: model, answerStyle: style)
                #expect(body["model"] as? String == model.modelID)
                #expect(body["reasoning_effort"] as? String == model.reasoningEffort)
                #expect(body["max_completion_tokens"] as? Int == model.maximumCompletionTokens(for: style))
                let messages = try #require(body["messages"] as? [[String: String]])
                #expect(messages.first?["content"]?.contains(style.writingInstruction) == true)
                #expect(model == .balanced ? body["reasoning_format"] as? String == "hidden" : body["include_reasoning"] as? Bool == false)
            }
        }
    }

    @Test func canvasConnectsDocumentsToRealEpisodeAnchors() {
        let id = UUID()
        let documents = [BrainSource(id: "summary", podcastID: id, title: "Learning", kind: "Summary", text: "retention practice"), BrainSource(id: "transcript", podcastID: id, title: "Learning", kind: "Transcript", text: "evidence")]
        let canvas = BrainCanvasPayload(documents: documents, dark: true, reduceMotion: true)
        #expect(canvas.nodes.filter { $0.kind == "Episode" }.count == 1)
        #expect(canvas.links.filter { $0.type == "document" }.count == 2)
        let ids = Set(canvas.nodes.map(\.id))
        #expect(canvas.links.allSatisfy { ids.contains($0.source) && ids.contains($0.target) })
    }

    @Test @MainActor func unreadableMemoryFileIsNeverOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("brain.json")
        let original = Data("broken existing data".utf8)
        try original.write(to: url)
        let store = BrainStore(url: url)
        store.state.goal = "new goal"; store.save()
        #expect(try Data(contentsOf: url) == original)
        #expect(store.error != nil)
    }

    @Test @MainActor func memoriesAndCitedConversationSurviveRelaunch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("brain.json")
        let first = BrainStore(url: url)
        first.state.memories = [PersonalMemory(text: "Prefer examples", evidence: "I prefer examples")]
        first.state.messages = [BrainMessage(role: "assistant", text: "Evidence [S1]", sources: [BrainSource(id: "a", podcastID: UUID(), title: "Episode", kind: "Transcript", text: "Original passage")])]
        first.save()
        let second = BrainStore(url: url)
        #expect(second.state.memories.first?.text == "Prefer examples")
        #expect(second.state.messages.first?.sources.first?.text == "Original passage")
    }
}
