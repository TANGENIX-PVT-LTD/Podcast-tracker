import SwiftUI
import WidgetKit

/// Colours mirrored from the app's Play palette.
enum WPalette {
    static let flame = Color(red: 1.0, green: 0.588, blue: 0.0)
    static let flameDeep = Color(red: 1.0, green: 0.294, blue: 0.0)
    static let gold = Color(red: 1.0, green: 0.784, blue: 0.0)
    static let goldLip = Color(red: 0.898, green: 0.643, blue: 0.0)
    static let success = Color(red: 0.345, green: 0.8, blue: 0.008)
    static let gem = Color(red: 0.11, green: 0.69, blue: 0.965)
    static let ice = Color(red: 0.518, green: 0.847, blue: 1.0)
    static let ink = Color(red: 0.169, green: 0.184, blue: 0.227)
    static let echo = Color(red: 0.13, green: 0.52, blue: 0.96)
    static let nightTop = Color(red: 0.11, green: 0.12, blue: 0.26)
    static let nightBottom = Color(red: 0.24, green: 0.15, blue: 0.36)
}

/// A path authored in a fixed design space, scaled to fit whatever frame it is given.
struct DesignShape: Shape {
    var path: Path
    var space: CGRect

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / space.width, rect.height / space.height)
        let x = rect.midX - space.width * scale / 2, y = rect.midY - space.height * scale / 2
        return path.applying(CGAffineTransform(translationX: -space.minX, y: -space.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: x, y: y)))
    }
}

// MARK: - Echo

enum WidgetEchoMood { case happy, cheer, proud, worried, sleepy }

/// Echo for widgets, drawn from the same SVG geometry as the app (EchoSpec.swift) using plain shapes.
struct WidgetEcho: View {
    var mood: WidgetEchoMood
    var size: CGFloat
    var tint: Color = WPalette.echo

    private static let space = CGRect(x: -16, y: -14, width: 232, height: 232)
    private func shape(_ d: String) -> DesignShape { DesignShape(path: SVGPath.parse(d), space: Self.space) }
    private func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> DesignShape {
        DesignShape(path: Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)), space: Self.space)
    }
    private func rect(_ r: CGRect, _ radius: CGFloat) -> DesignShape {
        DesignShape(path: Path(roundedRect: r, cornerRadius: radius), space: Self.space)
    }

    var body: some View {
        let s = size / 232
        let ink = WPalette.ink
        ZStack {
            oval(100, 189, 55, 6).fill(.black.opacity(0.12))
            oval(78, 180, 17, 8).fill(tint.mix(with: .black, by: 0.25))
            oval(122, 180, 17, 8).fill(tint.mix(with: .black, by: 0.25))
            shape("M100 34 C146 34 170 66 172 110 C174 152 144 180 100 180 C56 180 26 152 28 110 C30 66 54 34 100 34 Z")
                .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.25), tint], startPoint: .top, endPoint: .bottom))
            oval(70, 62, 15, 8).fill(.white.opacity(0.35))
            shape("M30 104 C30 -6 170 -6 170 104").stroke(ink, style: StrokeStyle(lineWidth: 13 * s, lineCap: .round))
            rect(CGRect(x: 36, y: 90, width: 14, height: 40), 6).fill(ink)
            rect(CGRect(x: 150, y: 90, width: 14, height: 40), 6).fill(ink)
            rect(CGRect(x: 12, y: 86, width: 34, height: 56), 15).fill(WPalette.flameDeep)
            rect(CGRect(x: 154, y: 86, width: 34, height: 56), 15).fill(WPalette.flameDeep)
            rect(CGRect(x: 12, y: 82, width: 34, height: 56), 15).fill(WPalette.flame)
            rect(CGRect(x: 154, y: 82, width: 34, height: 56), 15).fill(WPalette.flame)
            oval(62, 127, 10, 6).fill(Color(red: 1, green: 0.56, blue: 0.67).opacity(mood == .worried ? 0.2 : 0.5))
            oval(138, 127, 10, 6).fill(Color(red: 1, green: 0.56, blue: 0.67).opacity(mood == .worried ? 0.2 : 0.5))
            eyes(ink: ink, s: s)
            brows(ink: ink, s: s)
            mouth(ink: ink, s: s)
            if mood == .sleepy {
                Text("z").font(.system(size: 34 * s, weight: .heavy, design: .rounded)).foregroundStyle(ink.opacity(0.6))
                    .offset(x: 72 * s, y: -88 * s)
                Text("z").font(.system(size: 24 * s, weight: .heavy, design: .rounded)).foregroundStyle(ink.opacity(0.45))
                    .offset(x: 96 * s, y: -110 * s)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func eyes(ink: Color, s: CGFloat) -> some View {
        switch mood {
        case .cheer:
            shape("M64 104 Q80 86 96 104").stroke(ink, style: StrokeStyle(lineWidth: 7 * s, lineCap: .round))
            shape("M104 104 Q120 86 136 104").stroke(ink, style: StrokeStyle(lineWidth: 7 * s, lineCap: .round))
        case .sleepy:
            shape("M64 102 Q80 110 96 102").stroke(ink, style: StrokeStyle(lineWidth: 6 * s, lineCap: .round))
            shape("M104 102 Q120 110 136 102").stroke(ink, style: StrokeStyle(lineWidth: 6 * s, lineCap: .round))
        default:
            let dy: CGFloat = mood == .worried ? 3 : mood == .proud ? -2 : 0
            let r: CGFloat = mood == .worried ? 8 : 10
            ForEach([80.0, 120.0], id: \.self) { cx in
                oval(cx, 100, 18, 21).fill(.white)
                oval(cx + 2, 100 + dy, r, r).fill(ink)
                oval(cx - 1.5, 95.5 + dy, 3.5, 3.5).fill(.white)
            }
        }
    }

    @ViewBuilder private func brows(ink: Color, s: CGFloat) -> some View {
        switch mood {
        case .worried:
            shape("M66 70 Q80 62 94 66").stroke(ink, style: StrokeStyle(lineWidth: 5.5 * s, lineCap: .round))
            shape("M106 66 Q120 62 134 70").stroke(ink, style: StrokeStyle(lineWidth: 5.5 * s, lineCap: .round))
        case .proud:
            shape("M66 70 Q80 66 94 74").stroke(ink, style: StrokeStyle(lineWidth: 5.5 * s, lineCap: .round))
            shape("M106 74 Q120 66 134 70").stroke(ink, style: StrokeStyle(lineWidth: 5.5 * s, lineCap: .round))
        default:
            shape("M66 67 Q80 60 94 67").stroke(ink, style: StrokeStyle(lineWidth: 5.5 * s, lineCap: .round))
            shape("M106 67 Q120 60 134 67").stroke(ink, style: StrokeStyle(lineWidth: 5.5 * s, lineCap: .round))
        }
    }

    @ViewBuilder private func mouth(ink: Color, s: CGFloat) -> some View {
        switch mood {
        case .happy, .cheer:
            shape("M82 128 Q100 162 118 128 Q100 136 82 128 Z").fill(ink)
        case .proud:
            shape("M87 133 Q104 145 117 127").stroke(ink, style: StrokeStyle(lineWidth: 5.5 * s, lineCap: .round))
        case .worried:
            shape("M87 141 Q100 129 113 141").stroke(ink, style: StrokeStyle(lineWidth: 5.5 * s, lineCap: .round))
        case .sleepy:
            shape("M93 138 Q100 142 107 138").stroke(ink, style: StrokeStyle(lineWidth: 5.5 * s, lineCap: .round))
        }
    }
}

// MARK: - Flame

enum WidgetFlameState { case lit, dim, ash }

/// The streak flame (FlameSpec in StreakFlame.swift) as layered shapes.
struct WidgetFlame: View {
    var state: WidgetFlameState
    var size: CGFloat

    private static let space = CGRect(x: 0, y: 0, width: 100, height: 122)
    private func shape(_ d: String) -> DesignShape { DesignShape(path: SVGPath.parse(d), space: Self.space) }

    var body: some View {
        let colors: ([Color], [Color], Color) = switch state {
        case .lit: ([WPalette.flameDeep, WPalette.flame], [WPalette.flame, WPalette.gold], Color(red: 1, green: 0.835, blue: 0.29))
        case .dim: ([Color(red: 0.79, green: 0.45, blue: 0.23), Color(red: 0.89, green: 0.63, blue: 0.37)], [Color(red: 0.89, green: 0.63, blue: 0.37), Color(red: 0.94, green: 0.79, blue: 0.53)], Color(red: 0.96, green: 0.89, blue: 0.71))
        case .ash: ([Color(white: 0.6), Color(white: 0.69)], [Color(white: 0.69), Color(white: 0.81)], Color(white: 0.9))
        }
        ZStack {
            shape("M50 4 C60 24 90 40 92 72 C94 100 74 117 50 117 C26 117 6 100 8 72 C9 52 20 40 28 26 C32 38 38 45 44 47 C42 32 44 16 50 4 Z")
                .fill(LinearGradient(colors: colors.0, startPoint: .bottom, endPoint: .top))
            shape("M52 40 C60 56 75 66 75 87 C75 103 64 112 50 112 C36 112 25 103 25 88 C25 74 34 66 39 56 C42 64 46 67 49 67 C47 58 48 48 52 40 Z")
                .fill(LinearGradient(colors: colors.1, startPoint: .bottom, endPoint: .top))
            shape("M50 72 C56 82 64 88 64 98 C64 106 58 110 50 110 C42 110 36 106 36 98 C36 90 44 84 50 72 Z").fill(colors.2)
            if state != .ash {
                DesignShape(path: Path(ellipseIn: CGRect(x: 37, y: 78.5, width: 8, height: 11)), space: Self.space).fill(WPalette.ink)
                DesignShape(path: Path(ellipseIn: CGRect(x: 55, y: 78.5, width: 8, height: 11)), space: Self.space).fill(WPalette.ink)
            }
        }
        .frame(width: size * 100 / 122, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Pieces

/// Seven day dots, Monday first.
struct WidgetWeekStrip: View {
    var states: [String]
    var dot: CGFloat = 22
    var dark = false
    /// On a coloured background, done days turn white and their checks take this colour.
    var ink: Color = WPalette.flame

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(zip(["M", "T", "W", "T", "F", "S", "S"], states).enumerated()), id: \.offset) { _, pair in
                VStack(spacing: 4) {
                    Text(pair.0).font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(pair.1.hasPrefix("today") ? (dark ? Color.white : WPalette.flame) : (dark ? Color.white.opacity(0.7) : Color.secondary))
                    cell(pair.1).frame(width: dot, height: dot)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private func cell(_ state: String) -> some View {
        switch state {
        case "done", "todayDone":
            Circle().fill(dark ? Color.white : WPalette.flame).overlay(Image(systemName: "checkmark").font(.system(size: dot * 0.42, weight: .black)).foregroundStyle(dark ? ink : .white))
                .widgetAccentable()
        case "frozen":
            Circle().fill(WPalette.ice).overlay(Image(systemName: "snowflake").font(.system(size: dot * 0.42, weight: .bold)).foregroundStyle(.white))
        case "today":
            Circle().strokeBorder(dark ? Color.white : WPalette.flame, style: StrokeStyle(lineWidth: 2, dash: [3, 2.5]))
        default:
            Circle().fill(dark ? Color.white.opacity(0.14) : Color.primary.opacity(0.1))
        }
    }
}

/// Rounded bar with the value written inside, like the app's quest bars.
struct WidgetBar: View {
    var value: Double
    var label: String? = nil
    var tint: Color = WPalette.flame
    var height: CGFloat = 14
    var dark = false
    /// Label colour once the fill passes it.
    var labelOnFill: Color = .white

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(dark ? Color.white.opacity(0.16) : Color.primary.opacity(0.1))
                Capsule().fill(tint).frame(width: value > 0 ? max(height, proxy.size.width * min(1, value)) : 0)
                    .overlay(alignment: .top) { Capsule().fill(.white.opacity(0.3)).frame(height: 2.5).padding(.horizontal, 6).padding(.top, 2.5) }
                    .widgetAccentable()
                if let label {
                    Text(label).font(.system(size: height * 0.62, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(value > 0.5 ? labelOnFill : (dark ? Color.white.opacity(0.85) : Color.secondary))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: height)
    }
}

/// The 3D "Continue" pill: a face on a darker lip, as on the app's primary buttons.
struct WidgetPill: View {
    var title: String
    var symbol: String = "play.fill"
    var tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(tint))
            .background(Capsule().fill(tint.mix(with: .black, by: 0.25)).offset(y: 3))
            .padding(.bottom, 3)
            .widgetAccentable()
    }
}
