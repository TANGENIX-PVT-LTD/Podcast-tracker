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
            .appendingPathComponent(AppViewModel.demoMode ? "PodcastTracker-Demo/brain_v1.json" : "PodcastTracker/brain_v1.json")
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

    /// The assistant message currently being streamed, so the UI can animate Echo talking.
    @Published var streamingID: UUID?
    /// Quiz generated from the library, presented by the Brain view.
    @Published var quiz: BrainQuiz?
    @Published var needsKey = false

    var hasKey: Bool { KeychainStore.groqAPIKey() != nil }

    /// `retry` resends the last question without adding it to the conversation again.
    func ask(_ question: String, mode: BrainMode = .ask, model: QuirkyModel = .balanced, answerStyle: QuirkyAnswerStyle = .medium,
             retry: Bool = false, recentTitles: [String] = []) async {
        var question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if question.isEmpty && mode.allowsEmptyPrompt { question = mode == .recap ? "Recap what I learned this week." : "Connect the big ideas across my episodes." }
        guard !busy, readable, !question.isEmpty else { return }
        guard question.count <= 2000 else { error = "Keep your question under 2,000 characters."; return }
        guard let key = KeychainStore.groqAPIKey() else { needsKey = true; error = nil; return }
        busy = true; error = nil; needsKey = false
        defer { busy = false; streamingID = nil }
        if retry, state.messages.last?.role == "assistant", state.messages.last?.text.isEmpty == true { state.messages.removeLast() }
        let prior = Array(state.messages.suffix(retry ? 5 : 4).dropLast(retry ? 1 : 0))
        let contextQuery: String
        switch mode {
        case .recap: contextQuery = recentTitles.joined(separator: " ") + " " + question
        case .connect: contextQuery = question.count > 40 ? question : "everything across my learning " + question
        default: contextQuery = question + " " + prior.filter { $0.role == "user" }.map(\.text).joined(separator: " ")
        }
        let selected = mode == .recap && !recentTitles.isEmpty
            ? index.retrieve(contextQuery, limit: 10)
            : index.retrieve(contextQuery)
        if !retry || state.messages.last?.role != "user" { state.messages.append(BrainMessage(role: "user", text: question)); save() }

        if mode == .quiz { await makeQuiz(topic: question, sources: selected, key: key); return }

        let answer = BrainMessage(role: "assistant", text: "", sources: selected)
        state.messages.append(answer)
        streamingID = answer.id
        do {
            let system = BrainPrompt.system(goal: state.goal, memories: state.personalization ? state.memories : [], sources: selected, mode: mode)
            let text = try await GroqClient.shared.streamBrainAnswer(
                system: system, question: question, history: prior, model: model, answerStyle: answerStyle, apiKey: key
            ) { [weak self] partial in
                guard let self, let index = self.state.messages.lastIndex(where: { $0.id == answer.id }) else { return }
                self.state.messages[index].text = partial
            }
            let clean = BrainCitations.sanitize(BrainReplyParser.answer(from: text), sourceCount: selected.count)
            if let index = state.messages.lastIndex(where: { $0.id == answer.id }) { state.messages[index].text = clean }
            save()
            if state.rememberPreferences { await learnMemories(from: question, key: key) }
        } catch {
            state.messages.removeAll { $0.id == answer.id && $0.text.isEmpty }
            if case GroqError.missingKey = error { needsKey = true }
            self.error = error.localizedDescription
            save()
        }
    }

    private func learnMemories(from question: String, key: String) async {
        for candidate in await GroqClient.shared.brainMemories(question: question, apiKey: key).prefix(3)
        where !candidate.evidence.isEmpty && question.contains(candidate.evidence) && candidate.evidence.count <= 300 {
            guard !state.memories.contains(where: { $0.text.lowercased() == candidate.evidence.lowercased() }), state.memories.count < 100 else { continue }
            state.memories.append(PersonalMemory(text: candidate.evidence, evidence: candidate.evidence))
        }
        save()
    }

    private func makeQuiz(topic: String, sources: [BrainSource], key: String) async {
        let material = sources.filter { $0.kind != "Chat" }
        guard !material.isEmpty else {
            state.messages.append(BrainMessage(role: "assistant", text: "I couldn't find episode material about that yet. Generate a summary or import a transcript, then ask me to quiz you again."))
            save(); return
        }
        do {
            let text = material.map(\.text).joined(separator: "\n\n")
            let questions = try await GroqClient.shared.recallQuestions(transcript: text, apiKey: key)
            quiz = BrainQuiz(title: topic.count > 40 ? "Quick quiz" : topic, questions: questions)
            state.messages.append(BrainMessage(role: "assistant", text: "Your \(questions.count)-question quiz is ready. Every answer is backed by a quote from your episodes.", sources: material))
            save()
        } catch { self.error = error.localizedDescription }
    }

    func recordQuizResult(correct: Int, total: Int) {
        state.messages.append(BrainMessage(role: "assistant", text: "Quiz finished: **\(correct)/\(total)** correct. \(correct == total ? "Flawless recall." : "Ask me about the ones you missed and I'll explain with sources.")"))
        save()
    }
}

struct BrainQuiz: Identifiable {
    let id = UUID()
    var title: String
    var questions: [RecallQuestion]
}
