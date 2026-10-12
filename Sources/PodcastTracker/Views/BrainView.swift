import SwiftUI

private enum BrainWorkspace: String, CaseIterable, Identifiable {
    case canvas = "Canvas", chat = "Chat", sources = "Sources"
    var id: String { rawValue }
}

struct BrainView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var brain = BrainStore.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var question = ""
    @State private var filter = ""
    @State private var workspace = BrainWorkspace.canvas
    @State private var settings = false
    @State private var inspected: BrainSource?
    @State private var selectedSource: BrainSource?
    @State private var newChat = false
    @AppStorage("brain.selectedModel") private var model = QuirkyModel.balanced.rawValue
    @AppStorage("brain.answerStyle") private var answerStyle = QuirkyAnswerStyle.medium.rawValue
    @FocusState private var composerFocused: Bool

    private var currentModel: QuirkyModel { QuirkyModel(rawValue: model) ?? .balanced }
    private var currentStyle: QuirkyAnswerStyle { QuirkyAnswerStyle(rawValue: answerStyle) ?? .medium }
    private var background: Color { scheme == .dark ? Color(red: 0.075, green: 0.078, blue: 0.102) : Color(red: 0.97, green: 0.975, blue: 0.983) }
    private var surface: Color { scheme == .dark ? Color(red: 0.12, green: 0.125, blue: 0.157) : .white }
    private var documents: [BrainSource] {
        var seen = Set<String>()
        return brain.sources.filter { seen.insert("\($0.podcastID):\($0.kind)").inserted }
            .filter { filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter) || $0.text.localizedCaseInsensitiveContains(filter) }
            .sorted { $0.title == $1.title ? $0.kind < $1.kind : $0.title < $1.title }
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
                        Button("Open episode", systemImage: "play.circle") {
                            viewModel.selectedPodcast = viewModel.podcasts.first { $0.id == source.podcastID }; inspected = nil
                        }.buttonStyle(.bordered)
                    }.padding(24).frame(maxWidth: 680, alignment: .leading)
                }.toolbar { Button("Done") { inspected = nil } }
            }.frame(minWidth: 320, minHeight: 400)
        }
        .confirmationDialog("Start a new Brain conversation?", isPresented: $newChat) {
            Button("Clear current conversation", role: .destructive) { brain.state.messages = []; brain.save(); workspace = .chat }
        } message: { Text("Your podcast knowledge and personal memories will stay available.") }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Picker("Workspace", selection: $workspace) {
                    ForEach(BrainWorkspace.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 330)
                Spacer(minLength: 0)
                Button { newChat = true } label: { Image(systemName: "square.and.pencil").frame(width: 36, height: 36) }
                    .buttonStyle(.plain).disabled(brain.busy).accessibilityLabel("New conversation").help("New conversation")
                Button { settings = true } label: { Image(systemName: "person.crop.circle").frame(width: 36, height: 36) }
                    .buttonStyle(.plain).accessibilityLabel("Personal memory, \(brain.state.memories.count) saved").help("Personal memories and goals")
            }
            if workspace != .chat {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search your learning", text: $filter).textFieldStyle(.plain)
                    if !filter.isEmpty { Button { filter = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
                    #if os(macOS)
                    Text("\(Set(brain.sources.map(\.podcastID)).count) episodes").font(.caption).foregroundStyle(.secondary)
                    #endif
                }.padding(.horizontal, 13).padding(.vertical, 11).background(surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.07)))
            }
        }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 10)
    }

    private var canvas: some View {
        ZStack(alignment: .bottomLeading) {
            BrainCanvasView(documents: documents) { source in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { selectedSource = source }
            }
            if let source = selectedSource {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(source.kind, systemImage: symbol(source.kind)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                        Button { selectedSource = nil } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }.buttonStyle(.plain).accessibilityLabel("Close selection")
                    }
                    Text(source.title).font(.callout.weight(.semibold)).lineLimit(2)
                    HStack(spacing: 12) {
                        Button("Read source", systemImage: "doc.text") { inspected = source }.buttonStyle(.bordered)
                        Button("Ask Brain", systemImage: "arrow.up.message") {
                            question = "What are the key lessons from \(source.title)?"; workspace = .chat; composerFocused = true
                        }.buttonStyle(.borderedProminent)
                    }.controlSize(.small)
                }.padding(14).frame(maxWidth: 350, alignment: .leading).background(surface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 6).padding(.leading, 16).padding(.bottom, 82)
                    .transition(.opacity)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 10)
    }

    private var sourceList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(documents) { source in
                    Button { inspected = source } label: {
                        HStack(spacing: 14) {
                            Image(systemName: symbol(source.kind)).font(.title3).foregroundStyle(.tint).frame(width: 40, height: 40).background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 3) { Text(source.title).font(.callout.weight(.medium)); Text(source.kind).font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(12).background(surface, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
            }.padding(18).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if brain.state.messages.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "brain").font(.system(size: 32, weight: .light)).foregroundStyle(.tint)
                            Text("Think with everything you've learned.").font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                            Text("Connect ideas across \(Set(brain.sources.map(\.podcastID)).count) episodes. Follow the evidence. Make your next move.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            VStack(spacing: 8) {
                                suggestion("What themes connect my podcasts?", symbol: "point.3.connected.trianglepath.dotted")
                                suggestion("Turn my learning into a practical plan", symbol: "list.bullet.clipboard")
                                suggestion("Help me design a prompt for my goals", symbol: "text.bubble")
                            }.padding(.top, 14)
                        }.frame(maxWidth: .infinity).padding(.top, 36)
                    }
                    ForEach(brain.state.messages) { message in
                        if message.role == "user" {
                            HStack { Spacer(minLength: 35); Text(message.text).textSelection(.enabled).padding(.horizontal, 18).padding(.vertical, 12).background(surface, in: RoundedRectangle(cornerRadius: 20)).frame(maxWidth: 650, alignment: .trailing) }.id(message.id)
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Brain", systemImage: "brain").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                BrainAnswerText(text: message.text)
                                HStack {
                                    Button { copy(message.text) } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                                    if !message.sources.isEmpty {
                                        Menu {
                                            ForEach(Array(message.sources.enumerated()), id: \.element.id) { index, source in
                                                Button("[S\(index + 1)] \(source.title) · \(source.kind)") { inspected = source }
                                            }
                                        } label: { Label("\(message.sources.count) sources", systemImage: "books.vertical") }.font(.caption)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).id(message.id)
                        }
                    }
                    if brain.busy { HStack(spacing: 10) { ProgressView().controlSize(.small); Text("\(modelTitle(currentModel)) · connecting your sources…").font(.callout).foregroundStyle(.secondary) } }
                    if let error = brain.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.secondary)
                            if let last = brain.state.messages.last, last.role == "user" { Button("Retry") { Task { await brain.ask(last.text, model: currentModel, answerStyle: currentStyle) } }.disabled(brain.busy) }
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
            }.onChange(of: brain.state.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Ask anything about your learning…", text: $question, axis: .vertical)
                .font(.body).textFieldStyle(.plain).lineLimit(1...6).focused($composerFocused)
                .padding(.horizontal, 2).padding(.top, 2).onSubmit { send() }
            HStack(spacing: 14) {
                Menu {
                    Picker("AI mode", selection: $model) { ForEach(QuirkyModel.allCases) { Text(modelTitle($0)).tag($0.rawValue) } }
                } label: { Label(modelTitle(currentModel), systemImage: currentModel.symbol).font(.caption.weight(.medium)) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("AI mode: \(modelTitle(currentModel))")
                Menu {
                    Picker("Answer structure", selection: $answerStyle) { ForEach(QuirkyAnswerStyle.allCases) { Text(styleTitle($0)).tag($0.rawValue) } }
                } label: { Label(styleTitle(currentStyle), systemImage: "text.alignleft").font(.caption.weight(.medium)) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Answer structure: \(styleTitle(currentStyle))")
                Spacer(minLength: 0)
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(scheme == .dark ? .black : .white)
                        .frame(width: 38, height: 38).background(scheme == .dark ? Color.white : Color.primary, in: Circle())
                        .opacity(brain.busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.3 : 1)
                }.buttonStyle(.plain).frame(minWidth: 44, minHeight: 44).disabled(brain.busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Send question")
            }.foregroundStyle(.secondary)
        }.padding(.horizontal, 18).padding(.vertical, 12).frame(maxWidth: 800)
            .background(surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.primary.opacity(0.12)))
            .shadow(color: .black.opacity(scheme == .dark ? 0.14 : 0.04), radius: 16, y: 4)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
            .frame(maxWidth: .infinity)
    }

    private func suggestion(_ text: String, symbol: String) -> some View {
        Button { question = text; composerFocused = true } label: { HStack { Image(systemName: symbol).foregroundStyle(.secondary); Text(text).font(.callout); Spacer(); Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.secondary) }.padding(13).background(surface, in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain)
    }
    private func send() {
        guard !brain.busy, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = question; question = ""; workspace = .chat
        Task { await brain.ask(text, model: currentModel, answerStyle: currentStyle) }
    }
    private func symbol(_ kind: String) -> String { kind == "Transcript" ? "doc.text" : kind == "Summary" ? "sparkles" : "bubble.left.and.bubble.right" }
    private func modelTitle(_ model: QuirkyModel) -> String { model == .deep ? "Deep Reasoning" : model.title }
    private func styleTitle(_ style: QuirkyAnswerStyle) -> String { style == .medium ? "Default" : style.title }
    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

private struct BrainAnswerText: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, block in
                if block.hasPrefix("#") {
                    Text(block.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)).font(.headline).padding(.top, 6)
                } else if block.hasPrefix("```") {
                    Text(block.components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n")).font(.system(.callout, design: .monospaced)).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Text(.init(block)).font(.body).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
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
