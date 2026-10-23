import SwiftUI

struct SessionSummary: Equatable {
    var seconds: Double
    var xp: Int
    var quests: Int
    var goalProgress: Double
}

/// Queues the full-screen reward moments so they play one at a time, in a sensible order.
@MainActor
final class PlayMoments: ObservableObject {
    static let shared = PlayMoments()
    @Published var chestGems: Int?
    @Published var session: SessionSummary?
    @Published var freezeSavedStreak: Int?
    private var sessionStartXP: Int?
    private var sessionSeconds: Double = 0

    /// Reads reconcile wins (e.g. "Daily chest · 10 gems · …") for moments that need their own screen.
    func noteWins(_ wins: [String]) {
        for win in wins where win.hasPrefix("Daily chest") {
            chestGems = win.split(separator: "·").dropFirst().first
                .flatMap { Int($0.trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? "") } ?? 5
        }
    }

    func trackingStarted(xp: Int) { if sessionStartXP == nil { sessionStartXP = xp; sessionSeconds = 0 } }
    func trackingStopped(seconds: Double) { sessionSeconds += seconds }

    /// Called when the player closes. Only real sessions (5+ minutes) earn a results screen.
    func playerClosed(viewModel: AppViewModel) {
        defer { sessionStartXP = nil; sessionSeconds = 0 }
        let seconds = sessionSeconds + (viewModel.isTracking ? viewModel.currentSessionSeconds : 0)
        guard let start = sessionStartXP, seconds >= 300 else { return }
        session = SessionSummary(seconds: seconds, xp: max(0, viewModel.stats.totalXP - start),
                                 quests: viewModel.habitLoop.questCount(on: LearningCalendar.dateKey(for: Date())),
                                 goalProgress: viewModel.dailyGoalProgress)
    }

    /// Shows the "freeze saved you" moment once, the first time the app opens after a frozen day.
    func checkFreeze(viewModel: AppViewModel) {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return }
        let key = LearningCalendar.dateKey(for: yesterday)
        let ack = "play.freezeAck.\(key)"
        guard viewModel.habitStreakStatus.frozenDays.contains(key), !UserDefaults.standard.bool(forKey: ack) else { return }
        UserDefaults.standard.set(true, forKey: ack)
        freezeSavedStreak = viewModel.stats.currentStreak
    }
}

/// Place once over the app (and over the iOS player cover). Shows the next pending moment.
struct PlayMomentsOverlay: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var moments = PlayMoments.shared
    var active = true

    var body: some View {
        ZStack {
            if active {
                if viewModel.showDailyCelebration {
                    StreakCelebration { viewModel.showDailyCelebration = false }.transition(.opacity)
                } else if let session = moments.session {
                    SessionCompleteView(summary: session) { moments.session = nil }.transition(.opacity)
                } else if let gems = moments.chestGems {
                    ChestRevealView(gems: gems) { moments.chestGems = nil }.transition(.opacity)
                } else if viewModel.showLevelUpAlert {
                    LevelUpView { viewModel.showLevelUpAlert = false }.transition(.opacity)
                } else if let streak = moments.freezeSavedStreak {
                    FreezeSavedView(streak: streak) { moments.freezeSavedStreak = nil }.transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: viewModel.showDailyCelebration)
        .animation(.easeOut(duration: 0.18), value: moments.session)
        .animation(.easeOut(duration: 0.18), value: moments.chestGems)
        .animation(.easeOut(duration: 0.18), value: viewModel.showLevelUpAlert)
        .animation(.easeOut(duration: 0.18), value: moments.freezeSavedStreak)
        .onAppear { PlayFeedback.prewarm() }
    }
}

/// Shared full-screen stage: themed background, camera shake, flash, and a Continue button that lands last.
struct MomentScaffold<Content: View>: View {
    var glow: Color = Play.Palette.flame
    var buttonTitle = "Continue"
    var buttonKind: ChunkyButtonStyle.Kind = .primary
    var showsButton: Bool
    var shake = 0
    var flash = 0
    var flashColor: Color = .white
    var onContinue: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    @State private var buttonHop = 0

    var body: some View {
        ZStack {
            (scheme == .dark ? Color(hex: 0x131722) : Color.white).ignoresSafeArea()
            RadialGradient(colors: [glow.opacity(scheme == .dark ? 0.34 : 0.24), .clear], center: .center, startRadius: 10, endRadius: 380)
                .offset(y: -120).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 16)
                content
                Spacer(minLength: 16)
                Button(buttonTitle) { PlayFeedback.play(.release, sound: false); onContinue() }
                    .buttonStyle(.chunky(buttonKind))
                    .keyboardShortcut(.defaultAction)
                    .opacity(showsButton ? 1 : 0)
                    .offset(y: showsButton ? 0 : 40)
                    .animation(.spring(response: 0.42, dampingFraction: 0.58), value: showsButton)
                    .disabled(!showsButton)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .impactShake(shake)
            ImpactFlash(trigger: flash, color: flashColor)
        }
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Streak extended

/// Beat sheet (s): 0 grey ember swells + ignite rumble · 0.45 IGNITION (flash, shockwave, shake) ·
/// 0.8 digits roll and slam + confetti cannons · 1.05 "day streak!" lands · 1.3… week fills day by day
/// with rising ticks · today's cell pops · Echo hops in · milestone badge · Continue.
struct StreakCelebration: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onDone: () -> Void
    @State private var lit = false
    @State private var flameScale: CGFloat = 0.15
    @State private var flameTilt: Double = 0
    @State private var shownCount = 0
    @State private var numberSlam = 0
    @State private var textIn = false
    @State private var stripIn = false
    @State private var litDays: Set<String> = []
    @State private var echoIn = false
    @State private var echoHop = 0
    @State private var flameHop = 0
    @State private var badgeIn = 0
    @State private var buttonIn = false
    @State private var shock = 0
    @State private var shake = 0
    @State private var flash = 0
    @State private var confetti = 0
    @State private var sparks = 0

    private var count: Int { viewModel.stats.currentStreak }
    private var milestone: Bool { StreakMilestones.all.contains(count) }
    private var days: [StreakDay] { viewModel.weekStrip }

    var body: some View {
        MomentScaffold(showsButton: buttonIn, shake: shake, flash: flash, onContinue: onDone) {
            VStack(spacing: 14) {
                ZStack {
                    if lit { FlameRays().frame(width: 360, height: 360).transition(.scale(scale: 0.2).combined(with: .opacity)) }
                    EmberField(active: lit, count: 22).frame(width: 220, height: 260).offset(y: -40)
                    ShockwaveRing(trigger: shock, color: Play.Palette.flame, size: 200)
                    StreakFlame(state: lit ? .lit : .ash, size: 150)
                        .scaleEffect(flameScale)
                        .rotationEffect(.degrees(flameTilt), anchor: .bottom)
                        .hop(flameHop, height: 18)
                    ParticleBurst(style: .sparks, trigger: sparks, count: 30, colors: [Play.Palette.flame, Play.Palette.gold, .white])
                        .frame(width: 340, height: 340)
                }
                .frame(height: 200)

                RollingNumber(value: shownCount, color: lit ? Play.Palette.flame : Play.Palette.ash)
                    .slam(numberSlam, from: 1.9)
                    .frame(height: 104)
                Text("day streak!").font(Play.rounded(30, .black)).foregroundStyle(Play.Palette.flame)
                    .opacity(textIn ? 1 : 0).slam(textIn ? 1 : 0, from: 1.6)

                HStack(spacing: 8) {
                    ForEach(days) { day in
                        VStack(spacing: 6) {
                            Text(day.letter).font(Play.rounded(13, .heavy))
                                .foregroundStyle(day.state == .today || day.state == .todayDone ? Play.Palette.flame : .secondary)
                            if day.state == .frozen {
                                RoundedRectangle(cornerRadius: 9).fill(Play.Palette.ice.gradient).frame(width: 34, height: 34)
                                    .overlay(Image(systemName: "snowflake").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                            } else {
                                PoppingDayCell(lit: litDays.contains(day.id))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(14).chunkyCard()
                .opacity(stripIn ? 1 : 0).offset(y: stripIn ? 0 : 30)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: stripIn)

                ZStack {
                    if milestone && badgeIn > 0 {
                        Label("\(count)-day milestone!", systemImage: "rosette")
                            .font(Play.rounded(17, .black)).foregroundStyle(Play.Palette.ink)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Capsule().fill(Play.Palette.gold.gradient))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 2))
                            .slam(badgeIn, from: 2.2)
                    }
                }
                if echoIn {
                    EchoSays(mood: .cheer, text: EchoLines.celebration(streak: count), size: 78)
                        .hop(echoHop, height: 30)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay { ParticleBurst(style: .cannons, trigger: confetti, count: 110).frame(maxWidth: .infinity, maxHeight: .infinity).padding(-30) }
        }
        .task { await run() }
    }

    private func run() async {
        shownCount = max(0, count - 1)
        // Days already earned this week (excluding today) light first; today lands last.
        let earlier = days.filter { $0.state == .done }.map(\.id)
        let todayID = days.first { $0.state == .todayDone || $0.state == .today }?.id
        if reduceMotion {
            lit = true; flameScale = 1; shownCount = count; textIn = true; stripIn = true
            litDays = Set(earlier + [todayID].compactMap { $0 }); echoIn = true; badgeIn = 1; buttonIn = true
            PlayFeedback.play(.streakFlip)
            return
        }
        var beats: [Beat] = [
            .at(0.0, .ignite) {
                withAnimation(.easeIn(duration: 0.45)) { flameScale = 1.3 }
                withAnimation(.easeInOut(duration: 0.08).repeatCount(5, autoreverses: true)) { flameTilt = 4 }
            },
            .at(0.45, .impact, sound: false) {
                lit = true; flash += 1; shock += 1; shake += 1; sparks += 1; flameTilt = 0
                withAnimation(.spring(response: 0.5, dampingFraction: 0.42)) { flameScale = 1 }
            },
            .at(0.8, .streakFlip) {
                shownCount = count; numberSlam += 1; confetti += 1; shock += 1; flameHop += 1
            },
            .at(1.05, .land, sound: false) { textIn = true },
            .at(1.25, .tap, sound: false) { stripIn = true },
        ]
        var t = 1.45
        for (index, id) in earlier.enumerated() {
            beats.append(.at(t, .tick, sound: false) {
                litDays.insert(id)
                PlayFeedback.sound("tick", rate: 1 + Float(index) * 0.1)
            })
            t += 0.09
        }
        if let todayID {
            t += 0.12
            beats.append(.at(t, .pop) { litDays.insert(todayID); flameHop += 1; sparks += 1 })
        }
        t += 0.3
        beats.append(.at(t, .land, sound: false) { withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { echoIn = true } })
        beats.append(.at(t + 0.05, nil) { echoHop += 1 })
        if milestone {
            t += 0.55
            beats.append(.at(t, .levelUp) { badgeIn += 1; shake += 1; confetti += 1 })
        }
        beats.append(.at(t + 0.4, .release, sound: false) { buttonIn = true })
        await Choreo.run(beats)
    }
}

/// Slowly turning sunburst behind the flame.
struct FlameRays: View {
    var color: Color = Play.Palette.flame
    var body: some View { RaysView(color: color) }
}

// MARK: - Chest

/// Beat sheet (s): 0 chest drops in · 0.32 lands (thud + shake) · 0.8/1.15/1.5 escalating rattles, light leaking ·
/// 1.8 BURST (flash, shockwave, lid flies, rays) · 2.0… gems fly into the counter, one tick per gem · boost chip slams.
struct ChestRevealView: View {
    var gems: Int
    var onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropped = false
    @State private var wobble: Double = 0
    @State private var squash: CGFloat = 1
    @State private var glow: Double = 0
    @State private var open = false
    @State private var burst = 0
    @State private var counted = 0
    @State private var counterSlam = 0
    @State private var flight = 0
    @State private var boostIn = 0
    @State private var buttonIn = false
    @State private var shock = 0
    @State private var shake = 0
    @State private var flash = 0

    private var visibleGems: Int { min(max(gems, 3), 10) }

    var body: some View {
        MomentScaffold(glow: Play.Palette.gold, showsButton: buttonIn, shake: shake, flash: flash, flashColor: Play.Palette.gold.opacity(0.9), onContinue: onDone) {
            VStack(spacing: 18) {
                Text(open ? "Daily chest unlocked!" : "You earned a chest!").font(Play.rounded(28, .black)).multilineTextAlignment(.center)
                    .contentTransition(.opacity).animation(.easeOut(duration: 0.2), value: open)
                ZStack {
                    if open { RaysView(color: Play.Palette.gold).frame(width: 320, height: 320).transition(.scale(scale: 0.1).combined(with: .opacity)) }
                    Circle().fill(Play.Palette.gold).frame(width: 150, height: 150).blur(radius: 40).opacity(glow)
                    ShockwaveRing(trigger: shock, color: Play.Palette.gold, size: 180)
                    ChestShape(open: open).frame(width: 150, height: 130)
                        .scaleEffect(x: 2 - squash, y: squash, anchor: .bottom)
                        .rotationEffect(.degrees(wobble), anchor: .bottom)
                        .offset(y: dropped ? 0 : -520)
                    ParticleBurst(style: .gems, trigger: burst, count: 26).frame(width: 360, height: 360)
                }
                .frame(height: 230)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        GemShape().fill(Play.Palette.gem.gradient).frame(width: 30, height: 34)
                        Text("\(counted)").font(Play.rounded(52, .black)).foregroundStyle(Play.Palette.gem).monospacedDigit()
                            .contentTransition(.numericText(value: Double(counted)))
                    }
                    .slam(counterSlam, from: 1.25)
                    .opacity(open ? 1 : 0)
                    if boostIn > 0 {
                        Label("15-minute double XP boost", systemImage: "bolt.fill").font(Play.rounded(16, .black)).foregroundStyle(Play.Palette.ink)
                            .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(Play.Palette.gold.gradient))
                            .slam(boostIn, from: 2)
                    }
                }
                .frame(height: 110)
            }
            .overlay {
                // Gems arc out of the chest (top) into the counter (bottom).
                GeometryReader { proxy in
                    GemFlight(count: visibleGems, from: CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.42),
                              to: CGPoint(x: proxy.size.width / 2 - 20, y: proxy.size.height * 0.80), trigger: flight) { index in
                        counted = index == visibleGems - 1 ? gems : min(gems, Int((Double(gems) * Double(index + 1) / Double(visibleGems)).rounded()))
                        counterSlam += 1
                        PlayFeedback.play(.tick, sound: false, intensity: 0.6 + Float(index) * 0.04)
                        PlayFeedback.sound("tick", rate: 1 + Float(index) * 0.09)
                    }
                }
            }
        }
        .task { await run() }
    }

    private func run() async {
        if reduceMotion { dropped = true; open = true; counted = gems; boostIn = 1; buttonIn = true; PlayFeedback.play(.success); return }
        func rattle(_ angle: Double, _ intensity: Float) -> @MainActor () -> Void {
            {
                withAnimation(.easeOut(duration: 0.05)) { wobble = angle; squash = 0.9 }
                withAnimation(.easeOut(duration: 0.25)) { glow = Double(intensity) * 0.6 }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.06))
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.25)) { wobble = 0; squash = 1 }
                }
            }
        }
        await Choreo.run([
            .at(0, nil) { withAnimation(.easeIn(duration: 0.32)) { dropped = true } },
            .at(0.32, .thud) { shake += 1; withAnimation(.spring(response: 0.25, dampingFraction: 0.35)) { squash = 0.82 }; },
            .at(0.42, nil) { withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { squash = 1 } },
            .at(0.8, .swing, sound: false, intensity: 0.55, rattle(-9, 0.4)),
            .at(0.8, nil) { PlayFeedback.sound("chest") },
            .at(1.15, .swing, sound: false, intensity: 0.8, rattle(12, 0.7)),
            .at(1.5, .swing, sound: false, intensity: 1, rattle(-15, 1)),
            .at(1.8, .impact, sound: false) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { open = true }
                glow = 1; burst += 1; shock += 1; shake += 1; flash += 1
            },
            .at(2.05, nil) { flight += 1 },
            .at(2.05 + Double(visibleGems) * 0.09 + 0.75, .levelUp, sound: false) { boostIn += 1 },
            .at(2.05 + Double(visibleGems) * 0.09 + 1.1, nil) { buttonIn = true }
        ])
    }
}

private struct ChestShape: View {
    var open: Bool
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack(alignment: .bottom) {
                // Base
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0xA0612B))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: 0x6E3F17), lineWidth: 4))
                    .overlay(Rectangle().fill(Play.Palette.gold).frame(width: 16))
                    .frame(width: w, height: h * 0.55)
                    .offset(y: 0)
                if open {
                    Circle().fill(Play.Palette.gold.opacity(0.8)).frame(width: w * 0.7, height: w * 0.3).blur(radius: 12).offset(y: -h * 0.48)
                }
                // Lid
                UnevenRoundedRectangle(topLeadingRadius: w * 0.3, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: w * 0.3, style: .continuous)
                    .fill(Color(hex: 0xB8733A))
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: w * 0.3, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: w * 0.3, style: .continuous).strokeBorder(Color(hex: 0x6E3F17), lineWidth: 4))
                    .overlay(Rectangle().fill(Play.Palette.gold).frame(width: 16))
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 5).fill(Play.Palette.gold).frame(width: 30, height: 26)
                            .overlay(Circle().fill(Color(hex: 0x6E3F17)).frame(width: 8)).offset(y: 13)
                    }
                    .frame(width: w * 1.04, height: h * 0.45)
                    .rotationEffect(.degrees(open ? -28 : 0), anchor: .bottomLeading)
                    .offset(x: open ? -8 : 0, y: open ? -h * 0.62 : -h * 0.55)
            }
            .frame(width: w, height: h, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

private struct RaysView: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            rays.rotationEffect(.degrees(reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 20) * 18))
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private var rays: some View {
        Canvas { gc, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            for i in 0..<12 {
                let a = Double(i) / 12 * 2 * .pi, spread = 0.13
                var path = Path()
                path.move(to: center)
                path.addLine(to: CGPoint(x: center.x + cos(a - spread) * radius, y: center.y + sin(a - spread) * radius))
                path.addLine(to: CGPoint(x: center.x + cos(a + spread) * radius, y: center.y + sin(a + spread) * radius))
                path.closeSubpath()
                gc.fill(path, with: .radialGradient(Gradient(colors: [color.opacity(0.45), color.opacity(0)]), center: center, startRadius: 0, endRadius: radius))
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

// MARK: - Level up

/// Beat sheet (s): 0 badge spins in on a swelling rumble · 0.62 lands (flash, shockwave, shake, cannons) ·
/// 0.95 "Level N!" slams · 1.2 title slams · 1.5 Echo hops in · Continue.
struct LevelUpView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    var onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var badgeIn = false
    @State private var spin: Double = 0
    @State private var landed = 0
    @State private var titleSlam = 0
    @State private var nameSlam = 0
    @State private var echoIn = false
    @State private var echoHop = 0
    @State private var buttonIn = false
    @State private var confetti = 0
    @State private var shock = 0
    @State private var shake = 0
    @State private var flash = 0

    var body: some View {
        let level = viewModel.stats.currentLevel
        MomentScaffold(glow: Play.Palette.gold, showsButton: buttonIn, shake: shake, flash: flash, onContinue: onDone) {
            VStack(spacing: 18) {
                ZStack {
                    if landed > 0 { RaysView(color: Play.Palette.gold).frame(width: 340, height: 340).transition(.scale(scale: 0.1).combined(with: .opacity)) }
                    ShockwaveRing(trigger: shock, color: Play.Palette.gold, size: 190)
                    ZStack {
                        Circle().fill(Play.Palette.goldLip).frame(width: 150, height: 150).offset(y: 7)
                        Circle().fill(Play.Palette.gold.gradient).frame(width: 150, height: 150)
                            .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 5).padding(10))
                            .overlay(Image(systemName: level.iconName).font(.system(size: 58, weight: .black)).foregroundStyle(.white))
                    }
                    .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                    .scaleEffect(badgeIn ? 1 : 0.15)
                    .slam(landed, from: 1.3)
                    ParticleBurst(style: .sparks, trigger: landed, count: 36, colors: [Play.Palette.gold, .white, Play.Palette.flame]).frame(width: 360, height: 360)
                }
                .frame(height: 250)
                Text("Level \(level.number)!").font(Play.rounded(44, .black)).foregroundStyle(Play.Palette.gold.gradient)
                    .shadow(color: Play.Palette.goldLip, radius: 0, y: 4)
                    .opacity(titleSlam > 0 ? 1 : 0).slam(titleSlam, from: 2.2)
                Text("New title: \(level.title)").font(Play.rounded(22, .heavy))
                    .opacity(nameSlam > 0 ? 1 : 0).slam(nameSlam, from: 1.6)
                if echoIn {
                    EchoSays(mood: .proud, text: "Level \(level.number)! I knew you had it in you.", size: 74)
                        .hop(echoHop).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay { ParticleBurst(style: .cannons, trigger: confetti, count: 110).padding(-30) }
        }
        .task {
            if reduceMotion { badgeIn = true; landed = 1; titleSlam = 1; nameSlam = 1; echoIn = true; buttonIn = true; PlayFeedback.play(.levelUp); return }
            await Choreo.run([
                .at(0, .levelUp) {
                    withAnimation(.easeOut(duration: 0.62)) { badgeIn = true; spin = 720 }
                },
                .at(0.62, .impact, sound: false) { landed += 1; shock += 1; shake += 1; flash += 1; confetti += 1 },
                .at(0.95, .land, sound: false) { titleSlam += 1 },
                .at(1.2, .tap, sound: false) { nameSlam += 1 },
                .at(1.5, .land, sound: false) { withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { echoIn = true } },
                .at(1.55, nil) { echoHop += 1 },
                .at(1.9, nil) { buttonIn = true }
            ])
        }
    }
}

// MARK: - Freeze saved

/// Beat sheet (s): 0 frozen flame in an ice block · 0.4/0.7 cracks (swing haptics) · 1.0 SHATTER (impact,
/// ice burst, cold flash) · 1.15 flame reignites and hops · 1.5 Echo thaws · Continue.
struct FreezeSavedView: View {
    var streak: Int
    var onDone: () -> Void
    @State private var thawed = false
    @State private var crack = 0
    @State private var iceShake: Double = 0
    @State private var shatter = 0
    @State private var flameHop = 0
    @State private var echoHop = 0
    @State private var buttonIn = false
    @State private var shake = 0
    @State private var flash = 0

    var body: some View {
        MomentScaffold(glow: Play.Palette.ice, buttonKind: .gem, showsButton: buttonIn, shake: shake, flash: flash, flashColor: Play.Palette.ice, onContinue: onDone) {
            VStack(spacing: 20) {
                ZStack {
                    EmberField(active: thawed).frame(width: 200, height: 240).offset(y: -30)
                    StreakFlame(state: thawed ? .lit : .frozen, size: 140).hop(flameHop, height: 22)
                    if !thawed {
                        RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Play.Palette.ice.opacity(0.5))
                            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.85), lineWidth: 3))
                            .overlay(IceCracks(stage: crack).stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)))
                            .frame(width: 160, height: 172)
                            .rotationEffect(.degrees(iceShake))
                            .transition(.scale(scale: 1.4).combined(with: .opacity))
                    }
                    ParticleBurst(style: .ice, trigger: shatter, count: 44).frame(width: 360, height: 360)
                }
                .frame(height: 210)
                Text("Streak freeze used").font(Play.rounded(30, .black)).foregroundStyle(Play.Palette.iceDeep)
                Text("A freeze covered yesterday, so your \(streak)-day streak is still alive.").font(Play.rounded(18, .bold))
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                EchoSays(mood: thawed ? .happy : .frozen, text: thawed ? "Phew! Let's keep it burning today." : "Brrr…", size: 74)
                    .hop(echoHop)
            }
        }
        .task {
            func shiver(_ angle: Double) -> @MainActor () -> Void {
                {
                    crack += 1
                    withAnimation(.easeOut(duration: 0.04)) { iceShake = angle }
                    Task { @MainActor in try? await Task.sleep(for: .seconds(0.05)); withAnimation(.spring(response: 0.2, dampingFraction: 0.2)) { iceShake = 0 } }
                }
            }
            await Choreo.run([
                .at(0.4, .swing, sound: false, intensity: 0.6, shiver(-5)),
                .at(0.7, .swing, sound: false, intensity: 0.9, shiver(6)),
                .at(1.0, .freeze) { withAnimation(.easeOut(duration: 0.15)) { thawed = true }; shatter += 1; shake += 1; flash += 1 },
                .at(1.15, .ignite, intensity: 0.7) { flameHop += 1 },
                .at(1.6, .land, sound: false) { echoHop += 1 },
                .at(2.0, nil) { buttonIn = true }
            ])
        }
    }
}

private struct IceCracks: Shape {
    var stage: Int
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard stage > 0 else { return p }
        let c = CGPoint(x: rect.midX + 8, y: rect.midY - 10)
        let arms: [(CGFloat, CGFloat)] = [(-0.45, -0.4), (0.4, -0.3), (0.35, 0.42), (-0.38, 0.35), (0.05, 0.48)]
        for (i, arm) in arms.prefix(stage == 1 ? 2 : 5).enumerated() {
            p.move(to: c)
            let mid = CGPoint(x: c.x + rect.width * arm.0 * 0.5 + (i.isMultiple(of: 2) ? 6 : -6), y: c.y + rect.height * arm.1 * 0.5)
            p.addLine(to: mid)
            p.addLine(to: CGPoint(x: c.x + rect.width * arm.0, y: c.y + rect.height * arm.1))
        }
        return p
    }
}

// MARK: - Session complete

/// Beat sheet (s): 0 Echo hops in + cannons · 0.35 title slams · 0.75/1.05/1.35 stat cards flip in (thud each),
/// numbers count with rising-pitch ticks · quests bar · Continue.
struct SessionCompleteView: View {
    var summary: SessionSummary
    var onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var titleSlam = 0
    @State private var echoHop = 0
    @State private var confetti = 0
    @State private var shake = 0

    var body: some View {
        MomentScaffold(glow: Play.Palette.success, showsButton: step >= 5, shake: shake, onContinue: onDone) {
            VStack(spacing: 22) {
                EchoView(mood: .cheer, size: 140).hop(echoHop, height: 34)
                Text("Session complete!").font(Play.rounded(34, .black)).foregroundStyle(Play.Palette.gold)
                    .shadow(color: Play.Palette.goldLip, radius: 0, y: 3)
                    .opacity(titleSlam > 0 ? 1 : 0).slam(titleSlam, from: 2)
                HStack(spacing: 12) {
                    statTile("TOTAL XP", color: Play.Palette.gold, symbol: "bolt.fill", index: 1) {
                        CountUpText(value: summary.xp, font: Play.rounded(24, .black))
                    }
                    statTile("TIME", color: Play.Palette.gem, symbol: "clock.fill", index: 2) {
                        CountUpText(value: Int(summary.seconds / 60), font: Play.rounded(24, .black), suffix: "m")
                    }
                    statTile("GOAL", color: Play.Palette.success, symbol: "target", index: 3) {
                        CountUpText(value: Int(summary.goalProgress * 100), font: Play.rounded(24, .black), suffix: "%")
                    }
                }
                if step >= 4 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DAILY QUESTS \(summary.quests)/3").font(Play.rounded(13, .heavy)).foregroundStyle(.secondary)
                        PlayProgressBar(value: Double(summary.quests) / 3, tint: Play.Palette.gold)
                    }
                    .padding(14).chunkyCard()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay { ParticleBurst(style: .cannons, trigger: confetti, count: 110).padding(-30) }
        }
        .task {
            if reduceMotion { step = 5; titleSlam = 1; PlayFeedback.play(.success); return }
            await Choreo.run([
                .at(0, .success, sound: false) { echoHop += 1; confetti += 1; PlayFeedback.sound("complete") },
                .at(0.35, .land, sound: false) { titleSlam += 1 },
                .at(0.75, .thud) { withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) { step = 1 }; shake += 1 },
                .at(1.05, .thud, intensity: 0.85) { withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) { step = 2 } },
                .at(1.35, .thud, intensity: 0.7) { withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) { step = 3 } },
                .at(2.1, .tap, sound: false) { withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { step = 4 } },
                .at(2.6, nil) { step = 5 }
            ])
        }
    }

    private func statTile<V: View>(_ title: String, color: Color, symbol: String, index: Int, @ViewBuilder value: () -> V) -> some View {
        let visible = step >= index
        return VStack(spacing: 0) {
            Text(title).font(Play.rounded(12, .heavy)).foregroundStyle(.white).padding(.vertical, 5)
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 16, weight: .black))
                if visible { value() } else { Text("–").font(Play.rounded(24, .black)) }
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(2)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color))
        .rotation3DEffect(.degrees(visible ? 0 : 90), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.5)
        .opacity(visible ? 1 : 0)
    }
}
