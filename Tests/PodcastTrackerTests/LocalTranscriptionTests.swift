import Foundation
import Testing
@testable import PodcastTracker

@Suite("On-device transcription")
struct LocalTranscriptionTests {
    @Test func localTranscriptPreservesTimestampsAndSurvivesPersistence() throws {
        let id = UUID()
        let document = try OnDeviceTranscriber.document(segments: [
            .init(text: "First idea.", startSeconds: 0.5, durationSeconds: 2),
            .init(text: "  ", startSeconds: 2.5),
            .init(text: "Second idea.", startSeconds: 4.25, durationSeconds: 1.75)
        ], podcastID: id)
        #expect(document.source == .appleSpeech)
        #expect(document.text == "First idea.\nSecond idea.")
        let restored = try JSONDecoder().decode(TranscriptDocument.self, from: JSONEncoder().encode(document))
        #expect(restored.podcastID == id)
        #expect(restored.segments.count == 2)
        #expect(restored.segments[1].startSeconds == 4.25)
        #expect(restored.segments[1].durationSeconds == 1.75)
    }

    @Test func silentAudioCannotBecomeAnEmptySavedTranscript() {
        #expect(throws: SummaryPipelineError.self) {
            try OnDeviceTranscriber.document(segments: [.init(text: "\n ", startSeconds: 0)], podcastID: UUID())
        }
    }

    @Test func localWorkBlocksDuplicateRequests() {
        #expect(!SummaryGenerationState.preparingLocalTranscription.isIdle)
        #expect(!SummaryGenerationState.transcribingOnDevice.isIdle)
    }

    /// Opt-in real Apple engine test. No API keys, network providers, or production persistence.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PODTRACKIO_LOCAL_AUDIO"] != nil))
    func transcribesARealEpisodeOnDevice() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["PODTRACKIO_LOCAL_AUDIO"])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PodTrackio-SpeechTest-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = try await OnDeviceTranscriber.transcribe(fileURL: URL(fileURLWithPath: path),
            podcastID: UUID(), workingDirectory: root, progress: { state in print("Local speech:", state) })
        #expect(document.source == .appleSpeech)
        #expect(document.text.split(whereSeparator: \.isWhitespace).count > 100)
        #expect(document.segments.count > 5)
        #expect(document.segments.allSatisfy { $0.startSeconds.isFinite && $0.startSeconds >= 0 })
        #expect(document.segments.last!.startSeconds > 60)
        try JSONEncoder().encode(document).write(to: URL(fileURLWithPath: "/tmp/podtrackio-verified-local-transcript.json"))
        print("Verified on-device words:", document.text.split(whereSeparator: \.isWhitespace).count,
              "segments:", document.segments.count)
    }
}
