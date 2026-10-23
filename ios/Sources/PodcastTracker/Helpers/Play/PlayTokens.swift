import SwiftUI

/// The "Play" layer: one tactile, game-like vocabulary shared by iOS and macOS.
/// Theme tints stay the brand colour; these semantic colours carry meaning.
enum Play {
    enum Palette {
        static let flame = Color(hex: 0xFF9600)
        static let flameDeep = Color(hex: 0xFF4B00)
        static let flameCore = Color(hex: 0xFFD54A)
        static let success = Color(hex: 0x58CC02)
        static let successLip = Color(hex: 0x46A302)
        static let gem = Color(hex: 0x1CB0F6)
        static let gemLip = Color(hex: 0x1899D6)
        static let gold = Color(hex: 0xFFC800)
        static let goldLip = Color(hex: 0xE5A400)
        static let error = Color(hex: 0xFF4B4B)
        static let errorLip = Color(hex: 0xEA2B2B)
        static let ice = Color(hex: 0x84D8FF)
        static let iceDeep = Color(hex: 0x49C0F8)
        static let ash = Color(hex: 0xAFAFAF)
        static let ink = Color(hex: 0x2B2F3A)
        static let purple = Color(hex: 0xCE82FF)
    }

    enum Motion {
        static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.72)
        static let bouncy = Animation.spring(response: 0.45, dampingFraction: 0.55)
        static let gentle = Animation.spring(response: 0.6, dampingFraction: 0.85)
        static let stagger = 0.06

        static func or(_ animation: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeOut(duration: 0.2) : animation
        }
    }

    static var themeTint: Color {
        (AppTheme(rawValue: UserDefaults.standard.string(forKey: AppTheme.storageKey) ?? "") ?? .system).tint
    }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    /// A darker shade for 3D lips. Resolving keeps this correct for `.accentColor` and dynamic colours.
    /// Mixing in perceptual space keeps `.accentColor` and dynamic colours correct.
    func shaded(_ amount: Double = 0.22, in environment: EnvironmentValues? = nil) -> Color {
        mix(with: .black, by: amount, in: .perceptual)
    }

    func lightened(_ amount: Double, in environment: EnvironmentValues? = nil) -> Color {
        mix(with: .white, by: amount, in: .perceptual)
    }
}

/// Solid card with a 2pt border and a bottom lip: the tactile surface that replaces translucent mush.
struct ChunkyCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat = 20
    var fill: Color?
    var lip: CGFloat = 4
    var borderColor: Color?

    func body(content: Content) -> some View {
        let surface = fill ?? (scheme == .dark ? Color(hex: 0x1D2230) : .white)
        let edge = borderColor ?? (scheme == .dark ? Color.white.opacity(0.10) : Color(hex: 0xE5E5E5))
        let lipColor = borderColor ?? (scheme == .dark ? Color.black.opacity(0.45) : Color(hex: 0xE5E5E5))
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(lipColor).offset(y: lip)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(surface)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(edge, lineWidth: 2)
                }
            }
            .padding(.bottom, lip)
    }
}

extension View {
    func chunkyCard(cornerRadius: CGFloat = 20, fill: Color? = nil, lip: CGFloat = 4, border: Color? = nil) -> some View {
        modifier(ChunkyCardModifier(cornerRadius: cornerRadius, fill: fill, lip: lip, borderColor: border))
    }

    /// A one-shot spring pop when `value` changes (badges, counters, chips).
    func playPop<V: Equatable>(on value: V, scale: CGFloat = 1.18) -> some View {
        modifier(PopModifier(value: value, scale: scale))
    }
}

private struct PopModifier<V: Equatable>: ViewModifier {
    let value: V
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(popped ? scale : 1)
            .onChange(of: value) {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { popped = true }
                withAnimation(Play.Motion.bouncy.delay(0.14)) { popped = false }
            }
    }
}

/// Small rounded stat pill: gems, XP, freezes.
struct PlayStatPill: View {
    let symbol: String
    let value: String
    let color: Color
    var label: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 14, weight: .black)).foregroundStyle(color.gradient)
            Text(value).font(Play.rounded(15)).foregroundStyle(color).monospacedDigit()
                .contentTransition(.numericText())
        }
        .playPop(on: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label ?? "")")
    }
}
