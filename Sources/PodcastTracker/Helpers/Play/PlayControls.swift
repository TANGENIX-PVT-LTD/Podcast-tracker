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
            .animation(reduceMotion ? nil : (pressed ? .easeOut(duration: 0.06) : .smooth(duration: 0.18, extraBounce: 0)), value: pressed)
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
            .animation(reduceMotion ? nil : (pressed ? .easeOut(duration: 0.06) : .smooth(duration: 0.18, extraBounce: 0)), value: pressed)
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
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08))
                Capsule().fill(tint)
                    .frame(width: proxy.size.width)
                    .scaleEffect(x: min(1, max(0, value)), y: 1, anchor: .leading)
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25, extraBounce: 0), value: value)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(min(1, max(0, value)) * 100)) percent")
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
        .onAppear { shown = value }
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
    var body: some View {
        Text("\(prefix)\(value)\(suffix)")
            .font(font).monospacedDigit()
            .contentTransition(.numericText(value: Double(value)))
            .animation(reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0), value: value)
            .accessibilityLabel("\(prefix)\(value)\(suffix)")
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
