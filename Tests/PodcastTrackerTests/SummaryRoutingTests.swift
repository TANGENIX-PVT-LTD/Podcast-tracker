import Foundation
import Testing
@testable import PodcastTracker

@Suite("Automatic summary routing")
struct SummaryRoutingTests {
    @Test func databaseJobAndCompletedResultDecodeWithPostgrestKeys() throws {
        let fixture = #"{"id":"fc020000-0000-4000-8000-000000000001","user_id":"fc010000-0000-4000-8000-000000000001","requester_device":"phone","executor_id":"mac","status":"completed","progress":"Summary ready","error_message":null,"input_transcript":null,"created_at":"2026-10-29T06:00:00.123+00:00","episode":{"id":"fc030000-0000-4000-8000-000000000001","title":"Episode","url":"https://youtu.be/_FBivfgOvuE","video_id":"_FBivfgOvuE"},"result":{"podcast_id":"fc030000-0000-4000-8000-000000000001","brief":"A saved guide","key_topics":[],"major_takeaways":[],"action_plan":[],"dynamic_sections":[],"generated_at":"2026-10-29T06:00:00Z","transcript_source":"appleSpeech","model":"Apple Intelligence · on device","action_plan_xp_granted":false}}"#
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; decoder.dateDecodingStrategy = .iso8601
        let job = try decoder.decode(SummaryJob.self, from: Data(fixture.utf8))
        #expect(job.status == .completed)
        #expect(job.executorID == "mac")
        #expect(job.episode.podcast.youtubeVideoId == "_FBivfgOvuE")
        #expect(job.result?.summary.podcastID == job.episode.id)
        #expect(job.result?.summary.transcriptSource == .appleSpeech)
    }

    @MainActor @Test func relayedTranscriptPreservesSourceTimestampsAndLanguageText() throws {
        let original = TranscriptDocument(podcastID: UUID(), source: .imported, text: "Learning · सीखना",
            segments: [.init(text: "Learning · सीखना", startSeconds: 12.5, durationSeconds: 3)], createdAt: Date(timeIntervalSince1970: 1_000))
        let encoded = try SummaryRouting.transcriptString(original)
        let restored = try SummaryRouting.transcript(from: encoded)
        let decoded = try #require(restored)
        #expect(decoded == original)
        #expect(try SummaryRouting.transcript(from: nil) == nil)
    }

    @Test func routingStatesBlockDuplicateButtonRequests() {
        for state in [SummaryGenerationState.contactingMac, .waitingForMac("Passage 1 of 4"), .cloudFallback, .retryingOnDevice] {
            #expect(!state.isIdle)
        }
    }

    @Test func episodeSnapshotUsesWireCompatibleKeysWithoutCopyingTheLibrary() throws {
        let podcast = Podcast(title: "Episode", url: "https://youtu.be/_FBivfgOvuE", youtubeVideoId: "_FBivfgOvuE", notes: "Private notes stay on the device")
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let value = try #require(try JSONSerialization.jsonObject(with: encoder.encode(SummaryEpisode(podcast))) as? [String: Any])
        #expect(value["video_id"] as? String == podcast.youtubeVideoId)
        #expect(value["notes"] == nil)
        #expect(Set(value.keys) == Set(["id", "title", "url", "video_id"]))
    }

    private enum AttemptError: Error { case local, cloud }

    @MainActor @Test(arguments: [0, 1, 2])
    func retriesLocallyBeforeCloud(failures: Int) async throws {
        var calls: [String] = []
        let expected = PodcastSummary(podcastID: UUID(), brief: "Guide", keyTopics: [], majorTakeaways: [],
            actionPlan: [], generatedAt: Date(), transcriptSource: .appleSpeech, model: "test")
        let result = try await SummaryCoordinator.runWithLocalRetry(local: { attempt in
            calls.append("local\(attempt)")
            if attempt <= failures { throw AttemptError.local }
            return expected
        }, fallback: { _ in
            calls.append("cloud")
            return expected
        })
        #expect(result == expected)
        let expectedCalls = failures == 0 ? ["local1"] : failures == 1 ? ["local1", "local2"] : ["local1", "local2", "cloud"]
        #expect(calls == expectedCalls)
    }

    @MainActor @Test func cancellationDoesNotRetryOrCallCloud() async throws {
        var calls: [String] = []
        do {
            let _: PodcastSummary = try await SummaryCoordinator.runWithLocalRetry(local: { attempt in
                calls.append("local\(attempt)")
                throw CancellationError()
            }, fallback: { _ in
                calls.append("cloud")
                throw AttemptError.cloud
            })
            Issue.record("Cancellation was swallowed")
        } catch is CancellationError {}
        #expect(calls == ["local1"])
    }

    @MainActor @Test func cloudFailureIsReturnedAfterExactlyTwoLocalAttempts() async throws {
        var calls: [String] = []
        do {
            let _: PodcastSummary = try await SummaryCoordinator.runWithLocalRetry(local: { attempt in
                calls.append("local\(attempt)")
                throw AttemptError.local
            }, fallback: { error in
                #expect(error is AttemptError)
                calls.append("cloud")
                throw AttemptError.cloud
            })
            Issue.record("Cloud failure was swallowed")
        } catch AttemptError.cloud {}
        #expect(calls == ["local1", "local2", "cloud"])
    }

}
