import SwiftUI

// MARK: - Chunky button

/// Duolingo-style 3D button: the face sits on a darker lip and drops onto it when pressed.
struct ChunkyButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, success, danger, gem, flame, gold }
    enum Size { case regular, small }

    var kind: Kind = .primary
    var size: Size = .regular
    var fullWidth = true
    var cornerRadius: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        ChunkyButtonBody(configuration: configuration, kind: kind, size: size, fullWidth: fullWidth, cornerRadius: cornerRadius)
    }
}

private struct ChunkyButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: ChunkyButtonStyle.Kind
    let size: ChunkyButtonStyle.Size
    let fullWidth: Bool
    let cornerRadius: CGFloat?
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var depth: CGFloat { size == .small ? 3 : 5 }
    private var radius: CGFloat { cornerRadius ?? (size == .small ? 12 : 16) }

    private var face: Color {
        guard enabled else { return scheme == .dark ? Color(hex: 0x37464F) : Color(hex: 0xE5E5E5) }
        switch kind {
        case .primary: return Play.themeTint
        case .secondary: return scheme == .dark ? Color(hex: 0x1D2230) : .white
        case .success: return Play.Palette.success
        case .danger: return Play.Palette.error
        case .gem: return Play.Palette.gem
        case .flame: return Play.Palette.flame
        case .gold: return Play.Palette.gold
        }
    }

    private var lip: Color {
        guard enabled else { return scheme == .dark ? Color(hex: 0x2A363D) : Color(hex: 0xCECECE) }
        switch kind {
        case .secondary: return scheme == .dark ? Color.black.opacity(0.5) : Color(hex: 0xE5E5E5)
        case .success: return Play.Palette.successLip
        case .danger: return Play.Palette.errorLip
        case .gem: return Play.Palette.gemLip
        case .flame: return Play.Palette.flameDeep
        case .gold: return Play.Palette.goldLip
        case .primary: return Play.themeTint.shaded(in: environment)
        }
    }

    private var foreground: Color {
        guard enabled else { return Play.Palette.ash }
        switch kind {
        case .secondary: return scheme == .dark ? .white : Play.themeTint
        case .gold: return Play.Palette.ink
        default: return .white
        }
    }

    var body: some View {
        let pressed = configuration.isPressed && enabled
        configuration.label
            .font(size == .small ? Play.rounded(14, .bold) : Play.rounded(17, .heavy))
            .textCase(size == .regular ? .uppercase : nil)
            .tracking(size == .regular ? 0.6 : 0)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, size == .small ? 14 : 20)
            .padding(.vertical, size == .small ? 9 : 15)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(face)
                    if kind == .secondary {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(lip, lineWidth: 2)
                    } else {
                        // Glossy top highlight, the detail that makes the face read as a solid object.
                        Capsule().fill(.white.opacity(enabled ? 0.22 : 0)).frame(height: 4).padding(.horizontal, radius * 0.7).padding(.top, 5)
                    }
                }
            }
            .scaleEffect(pressed ? 0.97 : 1)
            .offset(y: pressed ? depth : 0)
            .background { RoundedRectangle(cornerRadius: radius, style: .continuous).fill(lip).offset(y: depth) }
            .padding(.bottom, depth)
            .contentShape(Rectangle())
            // Press is instant and firm; release springs back up past rest, like a real key.
            .animation(reduceMotion ? nil : (pressed ? .easeOut(duration: 0.06) : .spring(response: 0.32, dampingFraction: 0.45)), value: pressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                guard enabled else { return }
                PlayFeedback.play(isPressed ? .press : .release, sound: false)
            }
    }
}

extension ButtonStyle where Self == ChunkyButtonStyle {
    static var chunky: ChunkyButtonStyle { ChunkyButtonStyle() }
    static func chunky(_ kind: ChunkyButtonStyle.Kind, size: ChunkyButtonStyle.Size = .regular, fullWidth: Bool = true) -> ChunkyButtonStyle {
        ChunkyButtonStyle(kind: kind, size: size, fullWidth: fullWidth)
    }
}

/// A pressable card that sinks into its lip, for tappable tiles (episodes, answers, quests).
struct ChunkyTileStyle: ButtonStyle {
    var selected = false
    var tint: Color?
    var cornerRadius: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        ChunkyTileBody(configuration: configuration, selected: selected, tint: tint, cornerRadius: cornerRadius)
    }
}

private struct ChunkyTileBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let tint: Color?
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let accent = tint ?? Play.themeTint
        let pressed = configuration.isPressed
        let surface: Color = selected ? accent.lightened(scheme == .dark ? 0.0 : 0.82, in: environment).opacity(scheme == .dark ? 0.22 : 1)
            : (scheme == .dark ? Color(hex: 0x1D2230) : .white)
        let edge: Color = selected ? accent : (scheme == .dark ? Color.white.opacity(0.12) : Color(hex: 0xE5E5E5))
        let lip: Color = selected ? accent.shaded(in: environment) : (scheme == .dark ? Color.black.opacity(0.45) : Color(hex: 0xE5E5E5))
        configuration.label
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(surface)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(edge, lineWidth: 2)
                }
            }
            .offset(y: pressed ? 4 : 0)
            .background { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(lip).offset(y: 4) }
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : (pressed ? .easeOut(duration: 0.06) : .spring(response: 0.32, dampingFraction: 0.5)), value: pressed)
            .animation(reduceMotion ? nil : Play.Motion.snappy, value: selected)
            .onChange(of: configuration.isPressed) { _, isPressed in if isPressed { PlayFeedback.play(.tap, sound: false) } }
    }
}

// MARK: - Progress bar

/// Rounded bar with a highlight stripe, a glowing head and a shine sweep whenever it grows.
struct PlayProgressBar: View {
    var value: Double
    var tint: Color = Play.Palette.success
    var height: CGFloat = 16
    var showsGlow = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0
    @State private var shine: CGFloat = -0.3
    @State private var bulge = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fill = max(shown > 0 ? height : 0, width * min(1, max(0, shown)))
            ZStack(alignment: .leading) {
                Capsule().fill(scheme == .dark ? Color.white.opacity(0.10) : Color(hex: 0xE5E5E5))
                Capsule().fill(tint.gradient)
                    .frame(width: fill)
                    .overlay(alignment: .top) {
                        Capsule().fill(.white.opacity(0.3)).frame(height: max(2, height * 0.22))
                            .padding(.horizontal, height * 0.45).padding(.top, height * 0.2)
                    }
                    .overlay {
                        LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: max(24, fill * 0.35))
                            .offset(x: (shine - 0.5) * fill)
                            .blendMode(.plusLighter)
                    }
                    .clipShape(Capsule())
                    .shadow(color: showsGlow && shown > 0 ? tint.opacity(0.45) : .clear, radius: 6)
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: bulge) { content, y in
                        content.scaleEffect(x: 1, y: y, anchor: .center)
                    } keyframes: { _ in
                        KeyframeTrack { CubicKeyframe(1.35, duration: 0.1); SpringKeyframe(1, duration: 0.35, spring: .bouncy) }
                    }
                ParticleBurst(style: .sparks, trigger: bulge, count: 10, colors: [.white, tint])
                    .frame(width: height * 4, height: height * 4)
                    .position(x: fill, y: height / 2)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(min(1, max(0, value)) * 100)) percent")
        .onAppear {
            withAnimation(Play.Motion.or(.spring(response: 0.7, dampingFraction: 0.8), reduceMotion: reduceMotion).delay(0.15)) { shown = value }
        }
        .onChange(of: value) { old, new in
            withAnimation(Play.Motion.or(.spring(response: 0.55, dampingFraction: 0.7), reduceMotion: reduceMotion)) { shown = new }
            guard new > old, !reduceMotion else { return }
            bulge += 1
            shine = -0.3
            withAnimation(.easeInOut(duration: 0.7).delay(0.1)) { shine = 1.3 }
        }
    }
}

/// Circular goal ring with the same fill language as the bar.
struct PlayRing<Center: View>: View {
    var value: Double
    var tint: Color = Play.Palette.success
    var lineWidth: CGFloat = 8
    @ViewBuilder var center: Center
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(scheme == .dark ? Color.white.opacity(0.10) : Color(hex: 0xE5E5E5), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(1, max(0.0001, shown)))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.35), radius: 4)
            center
        }
        .onAppear { withAnimation(Play.Motion.or(.spring(response: 0.8, dampingFraction: 0.8), reduceMotion: reduceMotion)) { shown = value } }
        .onChange(of: value) { _, new in withAnimation(Play.Motion.or(Play.Motion.bouncy, reduceMotion: reduceMotion)) { shown = new } }
    }
}

// MARK: - Numbers

/// Counts from `from` to `value` with an ease-out curve and a tick haptic every few steps.
struct CountUpText: View {
    var value: Int
    var from: Int = 0
    var duration: Double = 0.9
    var font: Font = Play.rounded(34)
    var prefix = ""
    var suffix = ""
    var ticks = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Int?

    var body: some View {
        Text("\(prefix)\(shown ?? from)\(suffix)")
            .font(font).monospacedDigit()
            .contentTransition(.numericText(value: Double(shown ?? from)))
            .slam(shown == value && value != from ? 1 : 0, from: 1.25)
            .accessibilityLabel("\(prefix)\(value)\(suffix)")
            .task(id: value) {
                guard !reduceMotion, value != from else { shown = value; return }
                let steps = min(abs(value - from), 24)
                let start = shown ?? from
                for step in 1...max(1, steps) {
                    let progress = Double(step) / Double(max(1, steps))
                    let eased = 1 - pow(1 - progress, 3)
                    withAnimation(.snappy(duration: 0.12)) { shown = start + Int((Double(value - start) * eased).rounded()) }
                    if ticks && (step % 2 == 0 || step == steps) {
                        PlayFeedback.play(.tick, sound: false, intensity: 0.5 + Float(progress) * 0.5)
                        PlayFeedback.sound("tick", rate: 0.9 + Float(progress) * 0.6, volume: 0.35)
                    }
                    try? await Task.sleep(for: .seconds(duration / Double(max(1, steps)) * (0.6 + progress)))
                    if Task.isCancelled { return }
                }
                shown = value
            }
    }
}

/// A big number that rolls between values (the streak counter).
struct OdometerText: View {
    var value: Int
    var font: Font = Play.rounded(56, .black)
    var color: Color = Play.Palette.flame

    var body: some View {
        Text("\(value)")
            .font(font).monospacedDigit()
            .foregroundStyle(color.gradient)
            .contentTransition(.numericText(value: Double(value)))
            .playPop(on: value, scale: 1.25)
    }
}
