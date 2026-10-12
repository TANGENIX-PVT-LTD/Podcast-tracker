import Combine
import Foundation

@MainActor
final class BrainStore: ObservableObject {
    static let shared = BrainStore()
    @Published var state = BrainState()
    @Published var error: String?
    @Published var busy = false
    @Published var sources: [BrainSource] = []
    private var readable = true
    private var index = BrainIndex(sources: [])
    private let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PodcastTracker/brain_v1.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            do { state = try JSONDecoder().decode(BrainState.self, from: Data(contentsOf: self.url)) }
            catch { readable = false; self.error = "Brain storage could not be read. Original data is preserved. \(error.localizedDescription)" }
        }
    }

    func save() {
        guard readable else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        } catch { self.error = "Could not save Brain: \(error.localizedDescription)" }
    }

    func rebuild(podcasts: [Podcast], summaries: [PodcastSummary], conversations: [UUID: [QuirkyChatMessage]]) async {
        let messages = state.messages
        let built = await Task.detached(priority: .utility) {
            var sources: [BrainSource] = []
            for podcast in podcasts {
                let summary = summaries.first { $0.podcastID == podcast.id }
                let transcript = DataManager.shared.loadTranscript(for: podcast.id)
                guard summary != nil || transcript != nil else { continue }
                func add(_ kind: String, _ text: String) {
                    sources += BrainIndex.passages(id: "\(podcast.id):\(kind)", podcastID: podcast.id, title: podcast.title, kind: kind, text: text)
                }
                if let summary {
                    var parts = [summary.brief]
                    parts += summary.keyTopics.map { $0.title + ": " + $0.explanation }
                    parts += summary.majorTakeaways.map { $0.title + ": " + $0.explanation }
                    for section in summary.sections {
                        parts.append(section.title)
                        parts.append(section.introduction ?? "")
                        parts += section.points.map { $0.title + ": " + $0.explanation }
                    }
                    parts += summary.actionPlan.map { $0.title + ": " + $0.detail }
                    add("Summary", parts.joined(separator: "\n"))
                }
                if let transcript {
                    add("Transcript", transcript.segments.isEmpty ? transcript.text : transcript.segments.map { "[\(Int($0.startSeconds))s] \($0.text)" }.joined(separator: "\n"))
                }
                let chat = conversations[podcast.id, default: []]
                if !chat.isEmpty { add("Chat", chat.map { "\($0.role.rawValue): \($0.text)" }.joined(separator: "\n")) }
            }
            for message in messages where message.role == "assistant" && !message.sources.isEmpty {
                guard let origin = message.sources.first, podcasts.contains(where: { $0.id == origin.podcastID }) else { continue }
                sources += BrainIndex.passages(id: "brain:\(message.id)", podcastID: origin.podcastID, title: "Brain conversation · " + origin.title, kind: "Chat", text: message.text)
            }
            return BrainIndex(sources: sources)
        }.value
        index = built; sources = built.sources
    }

    func ask(_ question: String, model: QuirkyModel = .deep, answerStyle: QuirkyAnswerStyle = .medium) async {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, readable, !question.isEmpty else { return }
        guard question.count <= 2000 else { error = "Keep your question under 2,000 characters."; return }
        busy = true; error = nil
        defer { busy = false }
        let prior = state.messages.suffix(4)
        let contextQuery = question + " " + prior.filter { $0.role == "user" }.map(\.text).joined(separator: " ")
        let selected = index.retrieve(contextQuery)
        state.messages.append(BrainMessage(role: "user", text: question)); save()
        do {
            guard let key = KeychainStore.groqAPIKey() else { throw GroqError.missingKey }
            let reply = try await GroqClient.shared.brainReply(
                system: BrainPrompt.system(goal: state.goal, memories: state.personalization ? state.memories : [], sources: selected, learn: state.rememberPreferences),
                question: question, history: Array(prior), model: model, answerStyle: answerStyle, apiKey: key)
            let allowed = Set((1...max(1, selected.count)).map { "[S\($0)]" })
            let regex = try NSRegularExpression(pattern: "\\[S[0-9]+\\]")
            for match in regex.matches(in: reply.answer, range: NSRange(reply.answer.startIndex..., in: reply.answer)) {
                let label = (reply.answer as NSString).substring(with: match.range)
                guard !selected.isEmpty, allowed.contains(label) else { throw GroqError.server("Brain returned an invalid source citation. Please retry.") }
            }
            state.messages.append(BrainMessage(role: "assistant", text: reply.answer, sources: selected))
            if state.rememberPreferences {
                for candidate in reply.memories.prefix(3) where !candidate.evidence.isEmpty && question.contains(candidate.evidence) && candidate.evidence.count <= 300 {
                    guard !state.memories.contains(where: { $0.text.lowercased() == candidate.evidence.lowercased() }), state.memories.count < 100 else { continue }
                    state.memories.append(PersonalMemory(text: candidate.evidence, evidence: candidate.evidence))
                }
            }
            save()
        } catch { self.error = error.localizedDescription }
    }
}
