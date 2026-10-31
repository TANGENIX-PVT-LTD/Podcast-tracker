import Foundation
#if os(macOS)
import AppKit
#endif

struct SummaryEpisode: Codable, Sendable {
    var id: UUID
    var title: String
    var url: String
    var videoID: String
    enum CodingKeys: String, CodingKey { case id, title, url; case videoID = "videoId" }
    init(_ podcast: Podcast) { id = podcast.id; title = podcast.title; url = podcast.url; videoID = podcast.youtubeVideoId }
    var podcast: Podcast { Podcast(id: id, title: title, url: url, youtubeVideoId: videoID) }
}

struct SummaryJob: Decodable, Sendable {
    enum Status: String, Decodable, Sendable { case queued, processing, cloud, completed, failed, cancelled }
    var id: UUID
    var episode: SummaryEpisode
    var requesterDevice: String
    var executorID: String?
    var inputTranscript: String?
    var status: Status
    var progress: String
    var errorMessage: String?
    var result: SummaryDTO?
    var quirkyRequest: QuirkyRequest?
    var quirkyReply: QuirkyReply?
    enum CodingKeys: String, CodingKey {
        case id, episode, requesterDevice, inputTranscript, status, progress, errorMessage, result, quirkyRequest, quirkyReply
        case executorID = "executorId"
    }
}

enum SummaryRoutingError: LocalizedError {
    case unavailable, lostLease, cancelled, failed(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "Summary routing is unavailable. Reconnect and try again."
        case .lostLease: "This summary request is no longer active. Try again."
        case .cancelled: "Summary request cancelled."
        case .failed(let message): message
        }
    }
}

/// All routing decisions and leases are made by the database clock, never the phone's clock.
@MainActor
enum SummaryRouting {
    struct Pending: Codable {
        var id: UUID
        var episode: SummaryEpisode
        var owner: UUID
    }
    static var deviceID: String {
        let key = "summary.routing.deviceID"
        if let value = UserDefaults.standard.string(forKey: key) { return value }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
    private static func pendingKey(_ owner: UUID) -> String { "summary.routing.pending.\(owner)" }
    static func pending(for owner: UUID) -> Pending? {
        guard let data = UserDefaults.standard.data(forKey: pendingKey(owner)) else { return nil }
        return try? JSONDecoder().decode(Pending.self, from: data)
    }
    private static func clear(_ request: Pending) {
        guard pending(for: request.owner)?.id == request.id else { return }
        UserDefaults.standard.removeObject(forKey: pendingKey(request.owner))
    }
    static func transcriptString(_ document: TranscriptDocument?) throws -> String? {
        guard let document else { return nil }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(document), as: UTF8.self)
    }
    static func transcript(from value: String?) throws -> TranscriptDocument? {
        guard let value else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TranscriptDocument.self, from: Data(value.utf8))
    }

    static func generate(for podcast: Podcast, transcript: TranscriptDocument?,
                         progress: @escaping @Sendable (SummaryGenerationState) -> Void) async throws -> PodcastSummary {
        guard let owner = AuthManager.shared.userId else { throw SummaryRoutingError.unavailable }
        let existing = pending(for: owner)
        let request = existing?.episode.id == podcast.id ? existing! : Pending(id: UUID(), episode: SummaryEpisode(podcast), owner: owner)
        progress(.contactingMac)
        UserDefaults.standard.set(try JSONEncoder().encode(request), forKey: pendingKey(owner))
        let requester = deviceID
        if let transcript { DataManager.shared.saveTranscript(transcript) }
        let input = transcript ?? DataManager.shared.loadTranscript(for: podcast.id)
        return try await withTaskCancellationHandler {
            // Enqueue is idempotent, including a retry after a lost HTTP response or app restart.
            var job = try await SupabaseClient.shared.enqueueSummary(id: request.id, requester: requester,
                episode: request.episode, transcript: try transcriptString(input))
            if existing?.id == request.id {
                // Reclaim an expired phone lease after iOS suspends or restarts the app.
                job = try await SupabaseClient.shared.advanceSummary(request.id, requester: requester)
            }
            while true {
                try Task.checkCancellation()
                guard AuthManager.shared.userId == owner else { throw CancellationError() }
                switch job.status {
                case .completed:
                    guard let summary = job.result?.summary else { throw SummaryRoutingError.unavailable }
                    clear(request)
                    return summary
                case .queued, .processing:
                    progress(.waitingForMac(job.progress.isEmpty ? "Waiting for your Mac" : job.progress))
                    try await Task.sleep(for: .seconds(3))
                    job = try await SupabaseClient.shared.advanceSummary(request.id, requester: requester)
                case .cloud:
                    progress(.cloudFallback)
                    let lease = Task { @MainActor in
                        while !Task.isCancelled {
                            do { try await Task.sleep(for: .seconds(8)) } catch { return }
                            guard AuthManager.shared.userId == owner else { SummaryCoordinator.shared.cancel(); return }
                            do {
                                if try await !SupabaseClient.shared.renewSummary(request.id, executor: requester, progress: "Generating with Groq") {
                                    SummaryCoordinator.shared.cancel(); return
                                }
                            } catch { /* The server lease expires if connectivity cannot recover. */ }
                        }
                    }
                    defer { lease.cancel() }
                    do {
                        let summary = try await SummaryCoordinator.shared.generate(for: podcast,
                            importedTranscript: try Self.transcript(from: job.inputTranscript) ?? transcript,
                            engine: .cloud, progress: progress)
                        try Task.checkCancellation()
                        let published = try await SupabaseClient.shared.completeSummary(request.id, executor: requester, summary: summary)
                        guard let result = published.result?.summary else { throw SummaryRoutingError.lostLease }
                        clear(request)
                        return result
                    } catch {
                        if !Task.isCancelled, AuthManager.shared.userId == owner {
                            try? await SupabaseClient.shared.failSummary(request.id, executor: requester, reason: error.localizedDescription)
                            clear(request)
                        }
                        throw error
                    }
                case .failed:
                    clear(request)
                    throw SummaryRoutingError.failed(job.errorMessage ?? "Summary generation failed. Try again.")
                case .cancelled:
                    clear(request)
                    throw SummaryRoutingError.cancelled
                }
            }
        } onCancel: {
            Task { @MainActor in
                guard AuthManager.shared.userId == owner else { return }
                try? await SupabaseClient.shared.cancelSummary(request.id, requester: requester)
                clear(request)
            }
        }
    }
}

#if os(macOS)
/// The open, signed-in Mac app advertises readiness and services only its account's jobs.
@MainActor
final class SummaryMacWorker {
    static let shared = SummaryMacWorker()
    private weak var viewModel: AppViewModel?
    private var pollTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?
    private var job: SummaryJob?
    private var owner: UUID?
    private var progress = "Preparing the episode on your Mac"
    private let coordinator = SummaryCoordinator()

    func start(viewModel: AppViewModel) {
        self.viewModel = viewModel
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
            }
        }
    }

    private func tick() async {
        guard let viewModel else { return }
        let signedIn = AuthManager.shared.userId
        if owner != signedIn {
            workTask?.cancel(); coordinator.cancel(); workTask = nil; job = nil
            viewModel.remoteSummaryStatus = nil
            owner = signedIn
        }
        guard let signedIn, AuthManager.shared.isAuthenticated else { return }
        do {
            let ready = job == nil && viewModel.summaryState.isIdle && OnDeviceStudyGuide.availabilityMessage == nil && !QuirkyCoordinator.isAnsweringLocally
            try await SupabaseClient.shared.summaryHeartbeat(device: SummaryRouting.deviceID,
                name: Host.current().localizedName ?? "Your Mac", ready: ready)
            guard owner == signedIn else { return }
            if let current = job {
                let kept = try await SupabaseClient.shared.renewSummary(current.id, executor: SummaryRouting.deviceID, progress: progress)
                if !kept {
                    workTask?.cancel(); coordinator.cancel(); workTask = nil; job = nil
                    viewModel.remoteSummaryStatus = nil
                }
            } else if ready, let next = try await SupabaseClient.shared.claimSummary(worker: SummaryRouting.deviceID) {
                job = next
                viewModel.remoteSummaryStatus = next.quirkyRequest == nil ? "Generating an iPhone summary…" : "Answering an iPhone Quirky question…"
                workTask = Task { [weak self] in await self?.process(next, owner: signedIn) }
            }
        } catch {
            // Readiness is deliberately short-lived. Phones fail over if this Mac loses its connection.
        }
    }

    private func process(_ request: SummaryJob, owner: UUID) async {
        defer {
            if job?.id == request.id { job = nil; workTask = nil; viewModel?.remoteSummaryStatus = nil }
        }
        do {
            if let chat = request.quirkyRequest {
                let reply = try await QuirkyCoordinator.localAnswer(for: request.episode.podcast, request: chat,
                    imported: try SummaryRouting.transcript(from: request.inputTranscript), progress: { [weak self] detail in
                        guard let self, self.job?.id == request.id else { return }
                        self.progress = detail
                    })
                try Task.checkCancellation()
                guard AuthManager.shared.userId == owner else { throw CancellationError() }
                _ = try await SupabaseClient.shared.completeQuirky(request.id, executor: SummaryRouting.deviceID, reply: reply,
                    transcript: try SummaryRouting.transcriptString(DataManager.shared.loadTranscript(for: request.episode.id)))
                return
            }
            let summary: PodcastSummary
            if request.inputTranscript == nil, let cached = viewModel?.summary(for: request.episode.id) {
                summary = cached
            } else {
                let imported = try SummaryRouting.transcript(from: request.inputTranscript)
                summary = try await coordinator.generate(for: request.episode.podcast, importedTranscript: imported,
                    engine: .local, progress: { [weak self] state in
                        Task { @MainActor in
                            guard let self, self.job?.id == request.id else { return }
                            self.progress = state.macWorkerProgress
                        }
                    })
            }
            try Task.checkCancellation()
            guard AuthManager.shared.userId == owner else { throw CancellationError() }
            let published = try await SupabaseClient.shared.completeSummary(request.id, executor: SummaryRouting.deviceID, summary: summary)
            guard let result = published.result?.summary else { throw SummaryRoutingError.lostLease }
            viewModel?.storeSummary(result)
        } catch {
            if !Task.isCancelled, AuthManager.shared.userId == owner {
                print("Mac summary handoff failed: \(error.localizedDescription)")
                if request.quirkyRequest != nil {
                    try? await SupabaseClient.shared.releaseQuirky(request.id, worker: SummaryRouting.deviceID,
                        reason: error.localizedDescription,
                        transcript: try? SummaryRouting.transcriptString(DataManager.shared.loadTranscript(for: request.episode.id)))
                } else {
                    try? await SupabaseClient.shared.releaseSummary(request.id, worker: SummaryRouting.deviceID, reason: error.localizedDescription)
                }
            }
        }
    }
}
#endif

extension SummaryGenerationState {
    var macWorkerProgress: String {
        switch self {
        case .fetchingTranscript, .fetchingCaptions: "Fetching the episode transcript on your Mac"
        case .downloadingAudio: "Downloading episode audio on your Mac"
        case .retryingOnDevice: "Retrying on your Mac · attempt 2 of 2"
        case .preparingLocalTranscription, .transcribingOnDevice: "Transcribing the episode on your Mac"
        case .summarizingOnDevice(let current, let total): "Generating on your Mac · passage \(current) of \(total)"
        case .synthesizing: "Combining the lessons on your Mac"
        default: "Generating your summary on the Mac"
        }
    }
}

@MainActor
enum QuirkyRouting {
    private struct Pending: Codable {
        var owner: UUID
        var episode: SummaryEpisode
        var request: QuirkyRequest
    }
    private static func key(_ owner: UUID) -> String { "quirky.routing.pending.\(owner)" }

    static func answer(for podcast: Podcast, request: QuirkyRequest,
                       progress: @escaping @MainActor (String) -> Void) async throws -> QuirkyReply {
        guard let owner = AuthManager.shared.userId else { throw SummaryRoutingError.unavailable }
        let previous = UserDefaults.standard.data(forKey: key(owner)).flatMap { try? JSONDecoder().decode(Pending.self, from: $0) }
        let pending = previous?.episode.id == podcast.id && previous?.request.question == request.question
            && previous?.request.model == request.model && previous?.request.style == request.style
            ? previous! : Pending(owner: owner, episode: SummaryEpisode(podcast), request: request)
        UserDefaults.standard.set(try JSONEncoder().encode(pending), forKey: key(owner))
        let requester = SummaryRouting.deviceID
        let id = pending.request.id
        func clear() {
            let current = UserDefaults.standard.data(forKey: key(owner)).flatMap { try? JSONDecoder().decode(Pending.self, from: $0) }
            if current?.request.id == id { UserDefaults.standard.removeObject(forKey: key(owner)) }
        }
        progress("Checking your Mac…")
        return try await withTaskCancellationHandler {
            var job = try await SupabaseClient.shared.enqueueQuirky(id: id, requester: requester, episode: pending.episode,
                chat: pending.request, transcript: try SummaryRouting.transcriptString(DataManager.shared.loadTranscript(for: podcast.id)))
            if previous?.request.id == id { job = try await SupabaseClient.shared.advanceSummary(id, requester: requester) }
            while true {
                try Task.checkCancellation()
                guard AuthManager.shared.userId == owner else { throw CancellationError() }
                switch job.status {
                case .completed:
                    guard let reply = job.quirkyReply else { throw SummaryRoutingError.unavailable }
                    if let document = try SummaryRouting.transcript(from: job.inputTranscript), document.podcastID == podcast.id {
                        DataManager.shared.saveTranscript(document)
                    }
                    clear(); return reply
                case .queued, .processing:
                    progress(job.progress.isEmpty ? "Waiting for Apple Intelligence on your Mac…" : job.progress)
                    try await Task.sleep(for: .seconds(2))
                    job = try await SupabaseClient.shared.advanceSummary(id, requester: requester)
                case .cloud:
                    progress("Mac unavailable. Asking Groq…")
                    let lease = Task { @MainActor in
                        while !Task.isCancelled {
                            do { try await Task.sleep(for: .seconds(8)) } catch { return }
                            guard AuthManager.shared.userId == owner else { return }
                            _ = try? await SupabaseClient.shared.renewSummary(id, executor: requester, progress: "Answering with Groq")
                        }
                    }
                    defer { lease.cancel() }
                    do {
                        let reply = try await QuirkyCoordinator.cloudAnswer(for: podcast, request: pending.request,
                            imported: try SummaryRouting.transcript(from: job.inputTranscript))
                        try Task.checkCancellation()
                        guard AuthManager.shared.userId == owner else { throw CancellationError() }
                        let completed = try await SupabaseClient.shared.completeQuirky(id, executor: requester, reply: reply)
                        guard let result = completed.quirkyReply else { throw SummaryRoutingError.lostLease }
                        clear(); return result
                    } catch {
                        if !Task.isCancelled, AuthManager.shared.userId == owner {
                            try? await SupabaseClient.shared.failSummary(id, executor: requester, reason: error.localizedDescription)
                            clear()
                        }
                        throw error
                    }
                case .failed:
                    clear(); throw SummaryRoutingError.failed(job.errorMessage ?? "Quirky could not answer. Try again.")
                case .cancelled:
                    clear(); throw CancellationError()
                }
            }
        } onCancel: {
            Task { @MainActor in
                guard AuthManager.shared.userId == owner else { return }
                try? await SupabaseClient.shared.cancelSummary(id, requester: requester)
                clear()
            }
        }
    }
}
