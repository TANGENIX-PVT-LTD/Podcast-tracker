import SwiftUI

/// Echo, drawn and animated procedurally: breathing, blinking, glancing, hopping and talking.
struct EchoView: View {
    var mood: EchoMood = .idle
    var size: CGFloat = 120
    var tint: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.self) private var environment

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { gc, canvasSize in
                draw(in: &gc, size: canvasSize, t: t)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Echo, your learning buddy")
        .accessibilityValue(mood.rawValue)
    }

    // Design space is 200×200; the viewport adds room for hops, sound arcs and thought bubbles.
    private static let viewport = CGRect(x: -16, y: -14, width: 232, height: 232)

    private func draw(in gc: inout GraphicsContext, size: CGSize, t: Double) {
        let scale = min(size.width, size.height) / Self.viewport.width
        gc.scaleBy(x: scale, y: scale)
        gc.translateBy(x: -Self.viewport.minX, y: -Self.viewport.minY)

        let baseTint = mood == .frozen ? Play.Palette.ice : (tint ?? Play.themeTint)
        let top = baseTint.lightened(0.25, in: environment)
        let shade = baseTint.shaded(0.25, in: environment)

        // Whole-body motion.
        let breathe = sin(t * 2 * .pi / 2.4)
        var hop = 0.0, squashX = 1.0, squashY = 1.0
        switch mood {
        case .cheer:
            let p = (t / 0.62).truncatingRemainder(dividingBy: 1)
            hop = sin(.pi * p)
            let ground = p < 0.1 || p > 0.9
            squashX = ground ? 1.07 : 0.97; squashY = ground ? 0.92 : 1.04
        case .proud: squashX = 1.02; squashY = 1.03
        default: break
        }
        let shiver = mood == .frozen ? sin(t * 47) * 1.1 : mood == .worried ? sin(t * 31) * 0.5 : 0
        let tilt: Double = mood == .proud ? -4 : mood == .thinking ? 5 : mood == .talking ? sin(t * 2.1) * 2.5 : 0

        var figure = gc
        figure.translateBy(x: shiver, y: -hop * 18)
        figure.translateBy(x: 100, y: 180)
        figure.rotate(by: .degrees(tilt))
        figure.scaleBy(x: squashX * (1 - 0.012 * breathe), y: squashY * (1 + 0.025 * breathe))
        figure.translateBy(x: -100, y: -180)

        // Shadow stays on the ground and shrinks while airborne.
        let shadowWidth = 110 * (1 - hop * 0.35)
        gc.fill(Path(ellipseIn: CGRect(x: 100 - shadowWidth / 2, y: 183, width: shadowWidth, height: 12)), with: .color(.black.opacity(0.10 * (1 - hop * 0.5))))

        // Feet, body, belly, shine.
        for foot in EchoSpec.feet { figure.fill(Path(ellipseIn: foot.rect), with: .color(shade)) }
        let body = EchoShapes.body
        figure.fill(body, with: .linearGradient(Gradient(colors: [top, baseTint]), startPoint: CGPoint(x: 100, y: 34), endPoint: CGPoint(x: 100, y: 180)))
        var bellyLayer = figure
        bellyLayer.clip(to: body)
        bellyLayer.fill(Path(ellipseIn: EchoSpec.belly.rect), with: .color(.white.opacity(0.10)))
        bellyLayer.fill(Path(ellipseIn: EchoSpec.shine.rect), with: .color(.white.opacity(0.35)))

        // Headphones bob a beat behind the breath.
        var phones = figure
        phones.translateBy(x: 0, y: sin(t * 2 * .pi / 2.4 - 0.6) * 1.4)
        phones.stroke(EchoShapes.band, with: .color(EchoSpec.ink), style: StrokeStyle(lineWidth: EchoSpec.bandWidth, lineCap: .round))
        phones.stroke(EchoShapes.band, with: .color(.white.opacity(0.15)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        for pad in EchoSpec.pads { phones.fill(Path(roundedRect: pad, cornerRadius: 6), with: .color(EchoSpec.ink)) }
        for cup in EchoSpec.cups {
            phones.fill(Path(roundedRect: cup.offsetBy(dx: 0, dy: 4), cornerRadius: EchoSpec.cupRadius), with: .color(EchoSpec.cupLip))
            phones.fill(Path(roundedRect: cup, cornerRadius: EchoSpec.cupRadius), with: .color(EchoSpec.cupColor))
            phones.fill(Path(roundedRect: CGRect(x: cup.midX - 4, y: cup.minY + 8, width: 8, height: 14), cornerRadius: 4), with: .color(.white.opacity(0.35)))
        }

        // Sound arcs radiate while Echo is talking, cheering or happily listening.
        if [.talking, .cheer, .happy].contains(mood) {
            for (index, arc) in EchoShapes.soundArcs.enumerated() {
                let phase = (t * 1.6 - Double(index % 2) * 0.35).truncatingRemainder(dividingBy: 1)
                phones.stroke(arc, with: .color(EchoSpec.cupColor.opacity(0.75 * (1 - phase))), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            }
        }

        drawFace(in: &figure, t: t)

        if mood == .thinking {
            for (index, dot) in EchoSpec.thoughtDots.enumerated() {
                let pulse = 1 + 0.08 * sin(t * 4 - Double(index))
                let rect = dot.rect.insetBy(dx: dot.rx * (1 - pulse), dy: dot.ry * (1 - pulse))
                gc.fill(Path(ellipseIn: rect), with: .color(.white))
                gc.stroke(Path(ellipseIn: rect), with: .color(EchoSpec.ink.opacity(0.7)), lineWidth: 2.5)
            }
        }
    }

    private func drawFace(in gc: inout GraphicsContext, t: Double) {
        let ink = EchoSpec.ink
        // Cheeks
        let blush = mood == .worried || mood == .frozen ? 0.2 : 0.5
        for cheek in EchoSpec.cheeks { gc.fill(Path(ellipseIn: cheek.rect), with: .color(EchoSpec.cheekColor.opacity(blush))) }

        // Eyes
        switch mood {
        case .cheer:
            for eye in EchoShapes.happyEyes { gc.stroke(eye, with: .color(ink), style: StrokeStyle(lineWidth: 7, lineCap: .round)) }
        case .sleepy:
            for eye in EchoShapes.closedEyes { gc.stroke(eye, with: .color(ink), style: StrokeStyle(lineWidth: 6, lineCap: .round)) }
        default:
            let lid = blinkAmount(t)
            let look = lookOffset(t)
            for eye in EchoSpec.eyes {
                var layer = gc
                layer.translateBy(x: eye.cx, y: eye.cy)
                layer.scaleBy(x: 1, y: max(0.08, 1 - lid))
                layer.translateBy(x: -eye.cx, y: -eye.cy)
                layer.fill(Path(ellipseIn: eye.rect), with: .color(.white))
                layer.stroke(Path(ellipseIn: eye.rect), with: .color(ink.opacity(0.12)), lineWidth: 1.5)
                let pupil = CGPoint(x: eye.cx + look.width, y: eye.cy + look.height + (mood == .proud ? -2 : 0))
                let r = EchoSpec.pupilRadius * (mood == .worried || mood == .frozen ? 0.8 : 1)
                layer.fill(Path(ellipseIn: CGRect(x: pupil.x - r, y: pupil.y - r, width: r * 2, height: r * 2)), with: .color(ink))
                layer.fill(Path(ellipseIn: CGRect(x: pupil.x - 7, y: pupil.y - 8, width: 7, height: 7)), with: .color(.white))
                layer.fill(Path(ellipseIn: CGRect(x: pupil.x + 2.5, y: pupil.y + 3, width: 3.2, height: 3.2)), with: .color(.white.opacity(0.85)))
            }
        }

        // Brows
        let browTilt: Double, browLift: CGFloat
        switch mood {
        case .worried, .frozen: browTilt = -14; browLift = -2
        case .proud: browTilt = 9; browLift = 2
        case .cheer, .happy: browTilt = 0; browLift = -5
        case .thinking: browTilt = -6; browLift = -3
        case .sleepy: browTilt = 0; browLift = 3
        default: browTilt = 0; browLift = 0
        }
        for (index, brow) in EchoShapes.brows.enumerated() {
            var layer = gc
            let pivot = EchoSpec.browPivots[index]
            let direction: Double = index == 0 ? 1 : -1
            let lift = browLift + (mood == .thinking && index == 1 ? -4 : 0)
            layer.translateBy(x: pivot.x, y: pivot.y + lift)
            layer.rotate(by: .degrees(browTilt * direction))
            layer.translateBy(x: -pivot.x, y: -pivot.y)
            layer.stroke(brow, with: .color(ink), style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
        }

        // Mouth
        let mouth: EchoSpec.Mouth
        switch mood {
        case .idle: mouth = EchoSpec.mouthSmile
        case .happy, .cheer: mouth = EchoSpec.mouthGrin
        case .proud: mouth = EchoSpec.mouthSmirk
        case .worried: mouth = EchoSpec.mouthWorried
        case .sleepy: mouth = EchoSpec.mouthSleepy
        case .frozen: mouth = EchoSpec.mouthFrozen
        case .thinking: mouth = EchoSpec.mouthFlat
        case .talking:
            let beat = Int(t * 9) % 4
            mouth = beat == 0 ? EchoSpec.mouthOh : beat == 2 ? EchoSpec.mouthTalk : EchoSpec.mouthSmile
        }
        let (path, filled) = EchoShapes.mouth(mouth)
        if filled {
            gc.fill(path, with: .color(ink))
            if case .fill = mouth {
                var tongue = gc
                tongue.clip(to: path)
                tongue.fill(Path(ellipseIn: EchoSpec.tongue.rect), with: .color(EchoSpec.tongueColor))
            }
        } else {
            gc.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
        }
    }

    /// Natural blinking: one blink in each ~3.7s window at a pseudo-random offset.
    private func blinkAmount(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        let window = 3.7
        let cycle = floor(t / window)
        let offset = (sin(cycle * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
        let phase = t - cycle * window - abs(offset) * 2.8
        guard phase > 0, phase < 0.16 else { return 0 }
        return sin(.pi * phase / 0.16) * 0.95
    }

    private func lookOffset(_ t: Double) -> CGSize {
        let range = EchoSpec.lookRange
        switch mood {
        case .thinking: return CGSize(width: range.width * 0.8, height: -range.height * 0.9)
        case .worried, .frozen: return CGSize(width: sin(t * 3) * 1.5, height: range.height * 0.4)
        case .sleepy: return .zero
        default:
            // Slow wander plus an occasional quick glance.
            let glance = sin(t * 0.37) > 0.92 ? range.width * 0.9 : 0
            return CGSize(width: sin(t * 0.6) * range.width * 0.45 + glance, height: cos(t * 0.45) * range.height * 0.3)
        }
    }
}

/// Echo with a chunky speech bubble that pops in when the line changes.
struct EchoSays: View {
    var mood: EchoMood
    var text: String
    var size: CGFloat = 86
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownText = ""
    @State private var bubbleScale: CGFloat = 0.6

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            EchoView(mood: mood, size: size)
            Text(shownText)
                .font(Play.rounded(16, .bold))
                .foregroundStyle(scheme == .dark ? .white : Play.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .chunkyCard(cornerRadius: 16, lip: 3)
                .overlay(alignment: .leading) {
                    BubbleTail().fill(scheme == .dark ? Color(hex: 0x1D2230) : .white)
                        .overlay(BubbleTail().stroke(scheme == .dark ? Color.white.opacity(0.10) : Color(hex: 0xE5E5E5), lineWidth: 2))
                        .frame(width: 10, height: 16).offset(x: -8, y: -2)
                }
                .scaleEffect(bubbleScale, anchor: .leading)
                .accessibilityLabel("Echo says: \(text)")
        }
        .onAppear { reveal() }
        .onChange(of: text) { reveal() }
    }

    private func reveal() {
        shownText = text
        guard !reduceMotion else { bubbleScale = 1; return }
        bubbleScale = 0.6
        withAnimation(Play.Motion.bouncy) { bubbleScale = 1 }
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}
