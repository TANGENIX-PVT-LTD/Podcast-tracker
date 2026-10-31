import Foundation
import Testing
@testable import PodcastTracker

@Suite("Local study guides")
struct LocalSummaryTests {
    @Test func longUnbrokenAndMultibyteTranscriptsKeepEveryCharacterWithinBudget() {
        for source in [String(repeating: "A long paragraph without line breaks. ", count: 2_000),
                       String(repeating: "यह एक सीख है। 日本語の音声です。 🎧\n", count: 1_000)] {
            let chunks = OnDeviceStudyGuide.split(source)
            #expect(chunks.count > 1)
            #expect(chunks.joined() == source)
            #expect(chunks.allSatisfy { $0.utf8.count <= OnDeviceStudyGuide.inputByteLimit })
        }
        #expect(OnDeviceStudyGuide.split("").isEmpty)
        #expect(OnDeviceStudyGuide.split("Short source") == ["Short source"])
    }

    @Test func localGenerationBlocksDuplicateRequests() {
        #expect(!SummaryGenerationState.summarizingOnDevice(current: 1, total: 4).isIdle)
    }

    /// Opt-in live Apple model validation, independent of Groq, API keys, and app persistence.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PODTRACKIO_LOCAL_SUMMARY_TRANSCRIPT"] != nil))
    func createsARealStudyGuideEntirelyOnDevice() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["PODTRACKIO_LOCAL_SUMMARY_TRANSCRIPT"])
        let document = try JSONDecoder().decode(TranscriptDocument.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let podcast = Podcast(id: document.podcastID, title: "How to Get Your First 10 Customers",
                              url: "https://youtu.be/_FBivfgOvuE", youtubeVideoId: "_FBivfgOvuE")
        let summary = try await OnDeviceStudyGuide.generate(for: podcast, transcript: document,
            progress: { state in print("Local guide:", state) })
        #expect(summary.model == OnDeviceStudyGuide.modelName)
        #expect(!summary.brief.isEmpty)
        #expect(summary.sections.count == OnDeviceStudyGuide.split(document.text).count)
        #expect(!summary.actionPlan.isEmpty)
        #expect(summary.sections.allSatisfy { !$0.points.isEmpty })
        let restored = try JSONDecoder().decode(PodcastSummary.self, from: JSONEncoder().encode(summary))
        #expect(restored.id == podcast.id)
        try JSONEncoder().encode(summary).write(to: URL(fileURLWithPath: "/tmp/podtrackio-verified-local-summary.json"))
        print("Local guide complete:", summary.sections.count, "sections,", summary.actionPlan.count, "actions")
    }
}
