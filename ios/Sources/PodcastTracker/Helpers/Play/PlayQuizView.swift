import SwiftUI

/// One question at a time: pick a tile, Check, then a green or red sheet slides up with the source.
struct PlayQuizView: View {
    var title: String
    var questions: [RecallQuestion]
    var onFinish: (_ correct: Int) -> Void
    var onClose: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var selected: Int?
    @State private var checked = false
    @State private var correctCount = 0
    @State private var combo = 0
    @State private var shake: CGFloat = 0
    @State private var finished = false
    @State private var sparks = 0
    @State private var tilePop = 0
    @State private var echoHop = 0

    private var question: RecallQuestion? { questions.indices.contains(index) ? questions[index] : nil }
    private var isCorrect: Bool { selected == question?.answer }

    var body: some View {
        ZStack {
            (scheme == .dark ? Color(hex: 0x131722) : Color.white).ignoresSafeArea()
            if finished { results } else if let question { questionView(question) }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 680)
        #endif
    }

    private func questionView(_ question: RecallQuestion) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 20, weight: .bold)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Close quiz").keyboardShortcut(.cancelAction)
                PlayProgressBar(value: Double(index + (checked ? 1 : 0)) / Double(max(1, questions.count)), tint: Play.Palette.success)
                if combo >= 2 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill").foregroundStyle(Play.Palette.flame.gradient)
                        Text("\(combo)").font(Play.rounded(16, .black)).foregroundStyle(Play.Palette.flame)
                    }
                    .slam(combo, from: 1.8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20).padding(.top, 16)
            .animation(Play.Motion.bouncy, value: combo)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(title.uppercased()).font(Play.rounded(13, .heavy)).tracking(0.8).foregroundStyle(Play.themeTint)
                    HStack(alignment: .top, spacing: 10) {
                        EchoView(mood: checked ? (isCorrect ? .cheer : .worried) : .thinking, size: 74)
                            .hop(echoHop, height: 16)
                        Text(question.question).font(Play.rounded(21, .heavy)).fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                    VStack(spacing: 10) {
                        ForEach(Array(question.choices.enumerated()), id: \.offset) { choiceIndex, choice in
                            Button {
                                guard !checked else { return }
                                selected = choiceIndex
                                PlayFeedback.play(.select)
                            } label: {
                                HStack(spacing: 12) {
                                    Text("\(choiceIndex + 1)").font(Play.rounded(14, .heavy)).foregroundStyle(.secondary)
                                        .frame(width: 28, height: 28)
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.4), lineWidth: 2))
                                    Text(choice).font(Play.rounded(17, .semibold)).multilineTextAlignment(.leading)
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                }
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(ChunkyTileStyle(selected: tileSelected(choiceIndex, question), tint: tileTint(choiceIndex, question), cornerRadius: 16))
                            .slam(choiceIndex == question.answer ? tilePop : 0, from: 1.1)
                            .overlay {
                                if choiceIndex == question.answer {
                                    ParticleBurst(style: .sparks, trigger: tilePop, count: 16, colors: [Play.Palette.success, Play.Palette.gold, .white])
                                        .frame(width: 260, height: 160)
                                }
                            }
                            .keyboardShortcut(KeyEquivalent(Character("\(choiceIndex + 1)")), modifiers: [])
                            .disabled(checked)
                        }
                    }
                    .offset(x: shake)
                }
                .padding(20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }

            if checked { feedbackSheet(question).transition(.move(edge: .bottom)) }
            else {
                Button("Check", action: check)
                    .buttonStyle(.chunky(.success))
                    .disabled(selected == nil)
                    .keyboardShortcut(.defaultAction)
                    .padding(20).frame(maxWidth: 620)
            }
        }
        .animation(Play.Motion.or(.spring(response: 0.42, dampingFraction: 0.68), reduceMotion: reduceMotion), value: checked)
    }

    private func tileSelected(_ choice: Int, _ question: RecallQuestion) -> Bool {
        if checked { return choice == question.answer || choice == selected }
        return choice == selected
    }

    private func tileTint(_ choice: Int, _ question: RecallQuestion) -> Color? {
        guard checked else { return nil }
        if choice == question.answer { return Play.Palette.success }
        if choice == selected { return Play.Palette.error }
        return nil
    }

    private func feedbackSheet(_ question: RecallQuestion) -> some View {
        let tint = isCorrect ? Play.Palette.success : Play.Palette.error
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill").font(.system(size: 30, weight: .bold))
                Text(EchoLines.quizFeedback(correct: isCorrect, combo: combo)).font(Play.rounded(22, .black))
            }
            .foregroundStyle(isCorrect ? Play.Palette.successLip : Play.Palette.errorLip)
            if !isCorrect {
                Text("Answer: \(question.choices[question.answer])").font(Play.rounded(16, .bold)).foregroundStyle(Play.Palette.errorLip)
            }
            Text(question.explanation).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Text("“\(question.evidence)”").font(.caption).italic().foregroundStyle(.secondary).lineLimit(4)
            Button(index + 1 < questions.count ? "Continue" : "See results", action: next)
                .buttonStyle(.chunky(isCorrect ? .success : .danger))
                .keyboardShortcut(.defaultAction)
                .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(scheme == .dark ? 0.18 : 0.14).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { ParticleBurst(style: .sparks, trigger: sparks, count: 18, colors: [Play.Palette.success, Play.Palette.gold]).frame(height: 160).offset(y: -60) }
        .accessibilityElement(children: .contain)
    }

    private func check() {
        guard let selected, let question else { return }
        if selected == question.answer {
            correctCount += 1; combo += 1
            Task {
                await Choreo.run([
                    .at(0, .correct) { checked = true; tilePop += 1; echoHop += 1 },
                    .at(0.12, nil) { sparks += 1 },
                    .at(0.3, combo >= 2 ? .pop : nil, sound: combo >= 3) {}
                ], reduceMotion: reduceMotion)
            }
        } else {
            combo = 0
            // Each swing of the shake lands its own haptic, decaying with the motion.
            let swings: [(Double, CGFloat, Float)] = [(0, -14, 1), (0.07, 12, 0.85), (0.14, -9, 0.7), (0.21, 6, 0.5), (0.28, -3, 0.3), (0.35, 0, 0)]
            var beats: [Beat] = [.at(0, .wrong) { checked = true }]
            for (time, offset, power) in swings {
                beats.append(.at(time, power > 0 ? .swing : nil, sound: false, intensity: power) {
                    withAnimation(.easeOut(duration: 0.06)) { shake = offset }
                })
            }
            Task { await Choreo.run(beats, reduceMotion: reduceMotion) }
        }
    }

    private func next() {
        if index + 1 < questions.count {
            withAnimation(Play.Motion.gentle) { index += 1; selected = nil; checked = false }
        } else {
            withAnimation(Play.Motion.gentle) { finished = true }
        }
    }

    private var results: some View {
        let accuracy = Int((Double(correctCount) / Double(max(1, questions.count)) * 100).rounded())
        return MomentScaffold(glow: Play.Palette.success, showsButton: true, onContinue: { onFinish(correctCount) }) {
            VStack(spacing: 18) {
                EchoView(mood: accuracy >= 66 ? .cheer : .happy, size: 140)
                Text(accuracy == 100 ? "Perfect recall!" : accuracy >= 66 ? "Nicely remembered!" : "Practice makes permanent").font(Play.rounded(30, .black)).multilineTextAlignment(.center)
                HStack(spacing: 30) {
                    VStack { CountUpText(value: accuracy, font: Play.rounded(40, .black), suffix: "%").foregroundStyle(Play.Palette.success); Text("ACCURACY").font(Play.rounded(12, .heavy)).foregroundStyle(.secondary) }
                    VStack { CountUpText(value: correctCount, font: Play.rounded(40, .black), suffix: "/\(questions.count)").foregroundStyle(Play.Palette.gold); Text("CORRECT").font(Play.rounded(12, .heavy)).foregroundStyle(.secondary) }
                }
            }
            .overlay { ParticleBurst(style: .confetti, trigger: accuracy >= 66 ? 1 : 0, count: 70).offset(y: -60) }
        }
        .task { PlayFeedback.sound("complete"); PlayFeedback.play(.success, sound: false) }
    }
}
