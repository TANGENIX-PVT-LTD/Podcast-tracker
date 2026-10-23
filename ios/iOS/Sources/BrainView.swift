import SwiftUI

private enum BrainWorkspace: String, CaseIterable, Identifiable {
    case chat = "Chat", canvas = "Canvas", sources = "Sources"
    var id: String { rawValue }
}

struct BrainView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var brain = BrainStore.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var question = ""
    @State private var filter = ""
    @State private var workspace = BrainWorkspace.chat
    @State private var mode = BrainMode.ask
    @State private var settings = false
    @State private var inspected: BrainSource?
    @State private var selectedSource: BrainSource?
    @State private var newChat = false
    @State private var savedNoteID: UUID?
    @AppStorage("brain.selectedModel") private var model = QuirkyModel.balanced.rawValue
    @AppStorage("brain.answerStyle") private var answerStyle = QuirkyAnswerStyle.medium.rawValue
    @FocusState private var composerFocused: Bool

    private var currentModel: QuirkyModel { QuirkyModel(rawValue: model) ?? .balanced }
    private var currentStyle: QuirkyAnswerStyle { QuirkyAnswerStyle(rawValue: answerStyle) ?? .medium }
    private var background: Color { Color(.systemBackground) }
    private var surface: Color { Color(.secondarySystemBackground) }
    private var episodeCount: Int { Set(brain.sources.map(\.podcastID)).count }
    private var documents: [BrainSource] {
        var seen = Set<String>()
        return brain.sources.filter { seen.insert("\($0.podcastID):\($0.kind)").inserted }
            .filter { filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter) || $0.text.localizedCaseInsensitiveContains(filter) }
            .sorted { $0.title == $1.title ? $0.kind < $1.kind : $0.title < $1.title }
    }
    private var recentTitles: [String] {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        return viewModel.podcasts.filter { ($0.lastWatchedDate ?? .distantPast) > weekAgo }.map(\.title)
    }
    private var canSend: Bool {
        !brain.busy && (mode.allowsEmptyPrompt || !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch workspace {
                case .canvas: canvas
                case .chat: conversation
                case .sources: sourceList
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            composer
        }
        .background(background)
        .navigationTitle("Brain")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Personal memory", systemImage: "person.crop.circle") { settings = true }
                    .accessibilityLabel("Personal memory, \(brain.state.memories.count) saved")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("New conversation", systemImage: "square.and.pencil") { newChat = true }.disabled(brain.busy)
            }
        }
        #endif
        .task(id: "\(brain.state.messages.count)-\(viewModel.summaries.hashValue)-\(viewModel.podcasts.count)") {
            await brain.rebuild(podcasts: viewModel.podcasts, summaries: viewModel.summaries, conversations: viewModel.quirkyConversations)
        }
        .sheet(isPresented: $settings) {
            NavigationStack { BrainSettingsView().toolbar { Button("Done") { settings = false } } }.frame(minWidth: 320, minHeight: 420)
        }
        .sheet(item: $inspected) { source in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(source.kind, systemImage: symbol(source.kind)).font(.caption).foregroundStyle(.secondary)
                        Text(source.title).font(.title2.bold())
                        Text(source.text).font(.body).textSelection(.enabled)
                        Button("Open episode", systemImage: "play.fill") { open(source); inspected = nil }
                            .buttonStyle(.borderedProminent)
                    }.padding(24).frame(maxWidth: 680, alignment: .leading)
                }.toolbar { Button("Done") { inspected = nil } }
            }.frame(minWidth: 320, minHeight: 400)
        }
        #if os(iOS)
        .fullScreenCover(item: $brain.quiz) { quiz in quizView(quiz) }
        #else
        .sheet(item: $brain.quiz) { quiz in quizView(quiz) }
        #endif
        .confirmationDialog("Start a new Brain conversation?", isPresented: $newChat) {
            Button("Clear current conversation", role: .destructive) { brain.state.messages = []; brain.save(); workspace = .chat }
        } message: { Text("Your podcast knowledge and personal memories will stay available.") }
    }

    private func quizView(_ quiz: BrainQuiz) -> some View {
        PlayQuizView(title: quiz.title, questions: quiz.questions) { correct in
            brain.recordQuizResult(correct: correct, total: quiz.questions.count)
            // Active recall counts toward today's "recall or capture a takeaway" quest.
            viewModel.habitLoop.reflect(on: LearningCalendar.dateKey(for: Date()))
            viewModel.reconcileHabitLoop()
            viewModel.saveData()
            brain.quiz = nil
        } onClose: { brain.quiz = nil }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            Picker("Workspace", selection: $workspace) {
                ForEach(BrainWorkspace.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if workspace != .chat {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search your learning", text: $filter).textFieldStyle(.plain)
                    if !filter.isEmpty { Button { filter = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
                    Text("\(episodeCount) episodes").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 12).padding(.vertical, 9).background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10, style: .continuous))
            }
        }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 10)
    }

    // MARK: Canvas & sources

    private var canvas: some View {
        ZStack(alignment: .bottomLeading) {
            BrainCanvasView(documents: documents) { source in
                withAnimation(reduceMotion ? nil : Play.Motion.snappy) { selectedSource = source }
            }
            if let source = selectedSource {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(source.kind, systemImage: symbol(source.kind)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                        Button { selectedSource = nil } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }.buttonStyle(.plain).accessibilityLabel("Close selection")
                    }
                    Text(source.title).font(.headline).lineLimit(2)
                    HStack(spacing: 10) {
                        Button("Read") { inspected = source }.buttonStyle(.bordered)
                        Button("Ask Brain") {
                            question = "What are the key lessons from \(source.title)?"; mode = .ask; workspace = .chat; composerFocused = true
                        }.buttonStyle(.borderedProminent)
                    }
                }.padding(14).frame(maxWidth: 350, alignment: .leading).glassEffect(.regular, in: .rect(cornerRadius: 22))
                    .padding(.leading, 16).padding(.bottom, 82)
                    .transition(.scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity))
            }
        }.clipShape(RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 10)
    }

    private var sourceList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(documents) { source in
                    Button { inspected = source } label: {
                        HStack(spacing: 14) {
                            Image(systemName: symbol(source.kind)).font(.title3.bold()).foregroundStyle(.white).frame(width: 42, height: 42)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(kindColor(source.kind)))
                            VStack(alignment: .leading, spacing: 3) { Text(source.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary); Text(source.kind).font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                        }.padding(12)
                    }.buttonStyle(.plain).outlined(16)
                }
            }.padding(18).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if !brain.hasKey || brain.needsKey { BrainKeySetupCard() }
                    if brain.state.messages.isEmpty { emptyState }
                    ForEach(brain.state.messages) { message in
                        if message.role == "user" { userBubble(message) } else { answer(message) }
                    }
                    if brain.busy && brain.streamingID == nil { thinkingRow }
                    if let error = brain.error { errorCard(error) }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(22).frame(maxWidth: 800).frame(maxWidth: .infinity)
            }
            .onChange(of: brain.state.messages.count) { _, _ in withAnimation(Play.Motion.gentle) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: brain.state.messages.last?.text.count ?? 0) { _, _ in
                if brain.streamingID != nil { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if brain.hasKey && !brain.needsKey { EchoView(mood: .happy, size: 96) }
            Text("Think with everything you've learned.").font(.title2.bold()).multilineTextAlignment(.center)
            Text(episodeCount == 0
                 ? "Generate a summary or import a transcript for an episode, and I'll be able to answer from it."
                 : "I've read \(episodeCount) episode\(episodeCount == 1 ? "" : "s"). Ask, get quizzed, connect ideas or turn them into a plan.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(spacing: 0) {
                ForEach(Array(starters.enumerated()), id: \.offset) { index, starter in
                    if index > 0 { Divider().padding(.leading, 52) }
                    Button {
                        mode = starter.1
                        send(starter.0)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: starter.1.symbol).font(.body.weight(.semibold)).foregroundStyle(Play.themeTint).frame(width: 26)
                            Text(starter.0).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(brain.busy || episodeCount == 0)
                }
            }
            .outlined(20)
            .padding(.top, 6)
        }.frame(maxWidth: .infinity).padding(.top, 18)
    }

    /// Starter prompts drawn from what the person is actually listening to.
    private var starters: [(String, BrainMode)] {
        let titles = viewModel.podcasts.filter { p in brain.sources.contains { $0.podcastID == p.id } }
            .sorted { ($0.lastWatchedDate ?? .distantPast) > ($1.lastWatchedDate ?? .distantPast) }.map(\.title)
        var list: [(String, BrainMode)] = []
        if let first = titles.first { list.append(("Quiz me on \(first)", .quiz)); list.append(("What are the key lessons from \(first)?", .ask)) }
        if titles.count > 1 { list.append(("Connect ideas across my episodes", .connect)) }
        if !recentTitles.isEmpty { list.append(("Recap what I learned this week", .recap)) }
        list.append(("Turn my learning into a 7-day plan", .plan))
        return Array(list.prefix(4))
    }

    private func userBubble(_ message: BrainMessage) -> some View {
        HStack {
            Spacer(minLength: 40)
            Text(message.text).font(.body).foregroundStyle(.white).textSelection(.enabled)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Play.themeTint))
                .frame(maxWidth: 620, alignment: .trailing)
        }
        .id(message.id)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func answer(_ message: BrainMessage) -> some View {
        let streaming = brain.streamingID == message.id
        let cited = BrainCitations.cited(in: message.text).filter { $0 >= 1 && $0 <= message.sources.count }
        return HStack(alignment: .top, spacing: 10) {
            EchoView(mood: streaming ? .talking : .idle, size: 34)
            VStack(alignment: .leading, spacing: 12) {
                if message.text.isEmpty && streaming {
                    Text("…").font(.title3.weight(.heavy)).foregroundStyle(.secondary)
                } else {
                    BrainAnswerText(text: message.text)
                }
                if !streaming && !cited.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(cited, id: \.self) { number in
                                let source = message.sources[number - 1]
                                Button { open(source) } label: {
                                    HStack(spacing: 6) {
                                        Text("S\(number)").font(.caption.weight(.heavy)).foregroundStyle(.white)
                                            .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(kindColor(source.kind)))
                                        Text(source.title).font(.footnote.weight(.semibold)).lineLimit(1).frame(maxWidth: 180, alignment: .leading)
                                        if BrainCitations.timestamp(in: source.text) != nil { Image(systemName: "play.fill").font(.caption2) }
                                    }
                                }
                                .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                                .help("Open \(source.title)")
                            }
                        }.padding(.bottom, 2)
                    }
                }
                if !streaming && !message.text.isEmpty {
                    HStack(spacing: 16) {
                        Button { copy(message.text) } label: { Label("Copy", systemImage: "doc.on.doc") }
                        if let first = cited.first.map({ message.sources[$0 - 1] }) ?? message.sources.first {
                            Button { saveNote(message, to: first) } label: {
                                Label(savedNoteID == message.id ? "Saved to notes" : "Save as note", systemImage: savedNoteID == message.id ? "checkmark.circle.fill" : "square.and.arrow.down")
                            }
                            .foregroundStyle(savedNoteID == message.id ? Play.Palette.success : .secondary)
                        }
                        if !message.sources.isEmpty {
                            Menu {
                                ForEach(Array(message.sources.enumerated()), id: \.element.id) { index, source in
                                    Button("[S\(index + 1)] \(source.title) · \(source.kind)") { inspected = source }
                                }
                            } label: { Label("\(message.sources.count) sources", systemImage: "books.vertical") }
                                .menuStyle(.borderlessButton).fixedSize()
                        }
                    }
                    .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(message.id)
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private var thinkingRow: some View {
        HStack(spacing: 12) {
            EchoView(mood: .thinking, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode == .quiz ? "Writing your quiz…" : "Thinking it through…").font(.headline)
                Text("\(currentModel == .deep ? "Deep Reasoning" : currentModel.title) · reading your sources").font(.caption).foregroundStyle(.secondary)
            }
        }
        .transition(.opacity)
    }

    private func errorCard(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            EchoView(mood: .worried, size: 52)
            VStack(alignment: .leading, spacing: 10) {
                Text(error).font(.callout).fixedSize(horizontal: false, vertical: true)
                if let last = brain.state.messages.last, last.role == "user" {
                    Button("Try again") { Task { await brain.ask(last.text, mode: mode, model: currentModel, answerStyle: currentStyle, retry: true, recentTitles: recentTitles) } }
                        .buttonStyle(.bordered).tint(.red).disabled(brain.busy)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: .rect(cornerRadius: 16, style: .continuous))
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BrainMode.allCases) { option in
                        Button {
                            withAnimation(Play.Motion.snappy) { mode = option }
                            PlayFeedback.play(.select, sound: false)
                        } label: {
                            Label(option.title, systemImage: option.symbol).font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .tint(mode == option ? Play.themeTint : .secondary)
                    }
                }.padding(.horizontal, 2).padding(.top, 2)
            }
            TextField(mode.placeholder, text: $question, axis: .vertical)
                .font(.body).textFieldStyle(.plain).lineLimit(1...6).focused($composerFocused)
                .padding(.horizontal, 2).onSubmit { send() }
            HStack(spacing: 14) {
                Menu {
                    Picker("AI mode", selection: $model) { ForEach(QuirkyModel.allCases) { Text(modelTitle($0)).tag($0.rawValue) } }
                } label: { Label(modelTitle(currentModel), systemImage: currentModel.symbol).font(.caption.weight(.semibold)) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("AI mode: \(modelTitle(currentModel))")
                Menu {
                    Picker("Answer structure", selection: $answerStyle) { ForEach(QuirkyAnswerStyle.allCases) { Text(styleTitle($0)).tag($0.rawValue) } }
                } label: { Label(styleTitle(currentStyle), systemImage: "text.alignleft").font(.caption.weight(.semibold)) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Answer structure: \(styleTitle(currentStyle))")
                Spacer(minLength: 0)
                Button { send() } label: {
                    Image(systemName: mode == .quiz ? "checklist" : "arrow.up").font(.body.weight(.bold)).frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel(mode == .quiz ? "Make quiz" : "Send question")
            }.foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: 800)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

    private func send(_ override: String? = nil) {
        let text = override ?? question
        guard !brain.busy, mode.allowsEmptyPrompt || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        question = ""; workspace = .chat
        PlayFeedback.play(.tap, sound: false)
        let chosenMode = mode
        Task { await brain.ask(text, mode: chosenMode, model: currentModel, answerStyle: currentStyle, recentTitles: recentTitles) }
    }

    /// Opens the cited episode, seeking to the passage's transcript timestamp when it has one.
    private func open(_ source: BrainSource) {
        guard let index = viewModel.podcasts.firstIndex(where: { $0.id == source.podcastID }) else { return }
        if let seconds = BrainCitations.timestamp(in: source.text) { viewModel.podcasts[index].lastPlaybackPosition = seconds }
        viewModel.selectPodcast(viewModel.podcasts[index])
    }

    private func saveNote(_ message: BrainMessage, to source: BrainSource) {
        guard let podcast = viewModel.podcasts.first(where: { $0.id == source.podcastID }) else { return }
        let stamp = Date().formatted(date: .abbreviated, time: .omitted)
        let existing = podcast.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.updateNotes(for: podcast.id, notes: (existing.isEmpty ? "" : existing + "\n\n") + "From Brain · \(stamp)\n" + message.text)
        viewModel.reconcileHabitLoop()
        savedNoteID = message.id
        PlayFeedback.play(.success, sound: false); PlayFeedback.sound("pop")
    }

    private func symbol(_ kind: String) -> String { kind == "Transcript" ? "doc.text.fill" : kind == "Summary" ? "sparkles" : "bubble.left.and.bubble.right.fill" }
    private func kindColor(_ kind: String) -> Color { kind == "Transcript" ? Play.Palette.gem : kind == "Summary" ? Color(hex: 0xCE82FF) : Play.Palette.flame }
    private func modelTitle(_ model: QuirkyModel) -> String { model == .deep ? "Deep Reasoning" : model.title }
    private func styleTitle(_ style: QuirkyAnswerStyle) -> String { style == .medium ? "Default" : style.title }
    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        PlayFeedback.play(.tap, sound: false)
    }
}

/// Inline Groq key setup, so Brain is usable without hunting through Settings.
struct BrainKeySetupCard: View {
    @ObservedObject private var brain = BrainStore.shared
    @State private var key = ""
    @State private var status: String?
    @State private var testing = false
    @State private var ok = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                EchoView(mood: ok ? .cheer : .happy, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ok ? "Brain is connected!" : "Connect Brain in 30 seconds").font(.headline)
                    Text("Brain uses your own free Groq API key. It's stored in your Keychain on this device only.")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !ok {
                Link(destination: URL(string: "https://console.groq.com/keys")!) {
                    Label("Get a free key at console.groq.com", systemImage: "arrow.up.right.square").font(.subheadline.weight(.semibold))
                }
                SecureField("Paste your gsk_… key", text: $key)
                    .textFieldStyle(.roundedBorder)
                Button(testing ? "Checking…" : "Save & test") { Task { await save() } }
                    .buttonStyle(.borderedProminent).tint(Play.Palette.success)
                    .disabled(testing || key.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
            }
            if let status { Text(status).font(.caption.weight(.semibold)).foregroundStyle(ok ? Play.Palette.success : Play.Palette.error) }
        }
        .padding(16)
        .outlined(20)
    }

    private func save() async {
        testing = true; defer { testing = false }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await GroqClient.shared.testConnection(apiKey: trimmed)
            try KeychainStore.saveGroqAPIKey(trimmed)
            await GroqModelCatalog.shared.invalidate()
            ok = true; status = "Connected. Ask me anything about your episodes."
            brain.needsKey = false; brain.error = nil
            PlayFeedback.play(.correct); key = ""
        } catch {
            status = error.localizedDescription
            PlayFeedback.play(.wrong)
        }
    }
}

private struct BrainAnswerText: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, block in
                if block.hasPrefix("#") {
                    Text(block.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)).font(.headline).padding(.top, 4)
                } else if block.hasPrefix("```") {
                    Text(block.components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n")).font(.system(.callout, design: .monospaced)).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Text(.init(block))
                        .font(.body).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.textSelection(.enabled)
    }
}

struct BrainSettingsView: View {
    @ObservedObject private var brain = BrainStore.shared
    @State private var newMemory = ""
    @State private var clearChat = false
    var body: some View {
        Form {
            Section("Learning goals") {
                TextField("What do you want to achieve?", text: $brain.state.goal, axis: .vertical).lineLimit(3...6)
                Text("Brain adapts explanations and practical next steps to this goal.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Personalization") {
                Toggle("Use personal memories in answers", isOn: $brain.state.personalization)
                Toggle("Remember explicit preferences from Brain chat", isOn: $brain.state.rememberPreferences)
                Text("Memories and Brain chats are stored on this device. Relevant passages and enabled personal context are sent to your configured AI provider when you ask a question. Listening alone does not establish your beliefs or personality.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Editable memories") {
                ForEach($brain.state.memories) { $memory in
                    VStack(alignment: .leading) {
                        TextField("Memory", text: $memory.text, axis: .vertical)
                        Text("From: \(memory.evidence)").font(.caption).foregroundStyle(.secondary)
                        Button("Forget", role: .destructive) { brain.state.memories.removeAll { $0.id == memory.id }; brain.save() }
                    }
                }
                TextField("Add a preference or goal", text: $newMemory)
                Button("Add memory") {
                    brain.state.memories.append(PersonalMemory(text: String(newMemory.prefix(300)), evidence: "Added in Settings")); newMemory = ""; brain.save()
                }.disabled(newMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || brain.state.memories.count >= 100)
            }
            Section {
                Button("Clear Brain conversation", role: .destructive) { clearChat = true }.disabled(brain.busy)
                Text("Deleting a memory removes it from future personal context. Clear the conversation too if it contains that information.").font(.caption)
                if let error = brain.error { Text(error).foregroundStyle(.red) }
            }
        }.formStyle(.grouped).navigationTitle("Personal memory")
            .onDisappear { brain.save() }
            .onChange(of: brain.state.goal) { _, _ in brain.save() }
            .onChange(of: brain.state.memories) { _, _ in brain.save() }
            .onChange(of: brain.state.personalization) { _, _ in brain.save() }
            .onChange(of: brain.state.rememberPreferences) { _, _ in brain.save() }
            .confirmationDialog("Clear this Brain conversation?", isPresented: $clearChat) {
                Button("Clear conversation", role: .destructive) { brain.state.messages = []; brain.save() }
            }
    }
}
