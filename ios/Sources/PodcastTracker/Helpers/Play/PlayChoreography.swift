import SwiftUI

// MARK: - Beat clock

/// One clock for motion, sound and touch. Every beat fires its state change, haptic and sound on the
/// same tick, scheduled against an absolute start time so long sequences never drift.
struct Beat {
    var at: Double
    var cue: PlayCue?
    var sound: Bool = true
    var intensity: Float = 1
    var action: @MainActor () -> Void = {}

    static func at(_ time: Double, _ cue: PlayCue? = nil, sound: Bool = true, intensity: Float = 1, _ action: @escaping @MainActor () -> Void = {}) -> Beat {
        Beat(at: time, cue: cue, sound: sound, intensity: intensity, action: action)
    }
}

@MainActor
enum Choreo {
    /// Runs beats in time order. Under Reduce Motion the visuals jump to their end state but feedback still plays.
    static func run(_ beats: [Beat], reduceMotion: Bool = false) async {
        PlayFeedback.prewarm()
        let clock = ContinuousClock()
        let start = clock.now
        for beat in beats.sorted(by: { $0.at < $1.at }) {
            if !reduceMotion {
                try? await clock.sleep(until: start.advanced(by: .milliseconds(Int(beat.at * 1000))), tolerance: .milliseconds(2))
            }
            if Task.isCancelled { return }
            beat.action()
            if let cue = beat.cue { PlayFeedback.play(cue, sound: beat.sound, intensity: beat.intensity) }
        }
    }
}

extension View {
    /// Cards rise in one after another on first appearance.
    func staggered(_ index: Int, _ appeared: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
            .animation(Play.Motion.gentle.delay(Double(index) * Play.Motion.stagger), value: appeared)
    }
}

// MARK: - Impact effects

/// An expanding ring that marks the instant something lands.
struct ShockwaveRing: View {
    var trigger: Int
    var color: Color = .white
    var size: CGFloat = 220

    var body: some View {
        Circle().strokeBorder(color, lineWidth: 1)
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: Ring(), trigger: trigger) { content, ring in
                Circle().strokeBorder(color.opacity(ring.opacity), lineWidth: ring.width)
                    .frame(width: size, height: size)
                    .scaleEffect(ring.scale)
            } keyframes: { _ in
                KeyframeTrack(\.scale) { MoveKeyframe(0.25); CubicKeyframe(1.9, duration: 0.55) }
                KeyframeTrack(\.opacity) { MoveKeyframe(trigger == 0 ? 0 : 0.9); LinearKeyframe(0, duration: 0.55) }
                KeyframeTrack(\.width) { MoveKeyframe(26); CubicKeyframe(1, duration: 0.55) }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }

    struct Ring { var scale: CGFloat = 0.25; var opacity: Double = 0; var width: CGFloat = 26 }
}

extension View {
    /// Camera shake: a fast decaying wobble, `strength` in points.
    func impactShake(_ trigger: Int, strength: CGFloat = 9) -> some View {
        keyframeAnimator(initialValue: CGSize.zero, trigger: trigger) { content, offset in
            content.offset(offset)
        } keyframes: { _ in
            KeyframeTrack(\.width) {
                CubicKeyframe(strength, duration: 0.04); CubicKeyframe(-strength * 0.8, duration: 0.05)
                CubicKeyframe(strength * 0.6, duration: 0.05); CubicKeyframe(-strength * 0.4, duration: 0.05)
                CubicKeyframe(strength * 0.2, duration: 0.05); CubicKeyframe(0, duration: 0.05)
            }
            KeyframeTrack(\.height) {
                CubicKeyframe(-strength * 0.6, duration: 0.05); CubicKeyframe(strength * 0.5, duration: 0.055)
                CubicKeyframe(-strength * 0.3, duration: 0.055); CubicKeyframe(strength * 0.2, duration: 0.055); CubicKeyframe(0, duration: 0.055)
            }
        }
    }

    /// The exaggerated landing every big number and badge gets: overshoot, squash, settle.
    func slam(_ trigger: Int, from: CGFloat = 2.4) -> some View {
        keyframeAnimator(initialValue: SlamState(), trigger: trigger) { content, s in
            content.scaleEffect(x: s.scaleX, y: s.scaleY).opacity(trigger == 0 ? 1 : s.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.scaleX) {
                MoveKeyframe(from); CubicKeyframe(0.86, duration: 0.16); SpringKeyframe(1.08, duration: 0.14, spring: .bouncy); SpringKeyframe(1, duration: 0.3, spring: .smooth)
            }
            KeyframeTrack(\.scaleY) {
                MoveKeyframe(from); CubicKeyframe(1.12, duration: 0.16); SpringKeyframe(0.95, duration: 0.14, spring: .bouncy); SpringKeyframe(1, duration: 0.3, spring: .smooth)
            }
            KeyframeTrack(\.opacity) { MoveKeyframe(0); LinearKeyframe(1, duration: 0.1) }
        }
    }

    /// Squash-and-stretch hop (for Echo, flames and badges reacting to a beat).
    func hop(_ trigger: Int, height: CGFloat = 26) -> some View {
        keyframeAnimator(initialValue: HopState(), trigger: trigger) { content, s in
            content.scaleEffect(x: s.sx, y: s.sy, anchor: .bottom).offset(y: s.y)
        } keyframes: { _ in
            KeyframeTrack(\.y) { CubicKeyframe(4, duration: 0.07); CubicKeyframe(-height, duration: 0.18); CubicKeyframe(0, duration: 0.16); SpringKeyframe(0, duration: 0.2) }
            KeyframeTrack(\.sx) { CubicKeyframe(1.18, duration: 0.07); CubicKeyframe(0.9, duration: 0.18); CubicKeyframe(1.12, duration: 0.16); SpringKeyframe(1, duration: 0.25, spring: .bouncy) }
            KeyframeTrack(\.sy) { CubicKeyframe(0.82, duration: 0.07); CubicKeyframe(1.12, duration: 0.18); CubicKeyframe(0.88, duration: 0.16); SpringKeyframe(1, duration: 0.25, spring: .bouncy) }
        }
    }
}

struct SlamState { var scaleX: CGFloat = 1; var scaleY: CGFloat = 1; var opacity: Double = 1 }
struct HopState { var y: CGFloat = 0; var sx: CGFloat = 1; var sy: CGFloat = 1 }

/// Full-screen white flash for the brightest beats.
struct ImpactFlash: View {
    var trigger: Int
    var color: Color = .white
    var body: some View {
        Rectangle().fill(color).ignoresSafeArea()
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { content, opacity in content.opacity(opacity) } keyframes: { _ in
                KeyframeTrack { MoveKeyframe(trigger == 0 ? 0 : 0.75); LinearKeyframe(0, duration: 0.32) }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

// MARK: - Rolling number

/// Digits roll like a mechanical counter, rightmost first, then the whole number slams.
struct RollingNumber: View {
    var value: Int
    var font: Font = Play.rounded(96, .black)
    var digitHeight: CGFloat = 104
    var color: Color = Play.Palette.flame
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let digits = Array(String(value)).compactMap { $0.wholeNumberValue }
        HStack(spacing: -digitHeight * 0.06) {
            ForEach(Array(digits.enumerated()), id: \.offset) { index, digit in
                VStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { n in
                        Text("\(n)").font(font).monospacedDigit().frame(height: digitHeight)
                    }
                }
                .offset(y: -CGFloat(digit) * digitHeight + digitHeight * 4.5)
                .frame(height: digitHeight)
                .clipped()
                .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.62).delay(Double(digits.count - 1 - index) * 0.06), value: digit)
            }
        }
        .foregroundStyle(color.gradient)
        .shadow(color: color.opacity(0.35), radius: 0, y: 5)
        .accessibilityElement().accessibilityLabel("\(value)")
    }
}

// MARK: - Ambient particles

/// Continuous embers drifting up from a flame. Deterministic per index, so it costs nothing to keep.
struct EmberField: View {
    var active = true
    var count = 18
    var colors: [Color] = [Play.Palette.flame, Play.Palette.gold, Play.Palette.flameDeep]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !active || reduceMotion)) { context in
            Canvas { gc, size in
                guard active, !reduceMotion else { return }
                let t = context.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    let seed = Double(i) * 12.9898
                    let speed = 0.35 + (sin(seed) * 0.5 + 0.5) * 0.45
                    let phase = (t * speed + (sin(seed * 3.1) * 0.5 + 0.5)).truncatingRemainder(dividingBy: 1)
                    let x = size.width * (0.5 + sin(seed * 7.3) * 0.32 + sin(t * 2 + seed) * 0.04 * phase)
                    let y = size.height * (0.95 - phase * 0.95)
                    let r = (2.2 + (sin(seed * 5.7) * 0.5 + 0.5) * 3.2) * (1 - phase * 0.6)
                    var layer = gc
                    layer.opacity = sin(.pi * phase) * 0.9
                    layer.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(colors[i % colors.count]))
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

// MARK: - Drawn checkmark

struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.52))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.74))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.28))
        return p
    }
}

/// A day cell that pops and draws its checkmark when `lit` turns on.
struct PoppingDayCell: View {
    var lit: Bool
    var color: Color = Play.Palette.flame
    var size: CGFloat = 34
    @State private var drawn: CGFloat = 0
    @State private var popTrigger = 0

    var body: some View {
        ZStack {
            Circle().fill(Color.secondary.opacity(0.15))
            Circle().fill(color.gradient).scaleEffect(lit ? 1 : 0.01).opacity(lit ? 1 : 0)
            CheckShape().trim(from: 0, to: drawn).stroke(.white, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round, lineJoin: .round))
                .padding(size * 0.12)
        }
        .frame(width: size, height: size)
        .slam(popTrigger, from: 0.2)
        .onAppear { if lit { drawn = 1 } }
        .onChange(of: lit) { _, now in
            guard now else { return }
            popTrigger += 1
            withAnimation(.easeOut(duration: 0.22).delay(0.08)) { drawn = 1 }
        }
    }
}

// MARK: - Gem flight

/// Gems fly from `from` to `to` along curved paths; `onArrive` fires as each one lands (for ticks).
struct GemFlight: View {
    var count: Int
    var from: CGPoint
    var to: CGPoint
    var trigger: Int
    var onArrive: (Int) -> Void
    @State private var launched: Set<Int> = []
    @State private var arrived: Set<Int> = []

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let spread = CGFloat(index - count / 2) * 28
                GemShape().fill(Play.Palette.gem.gradient)
                    .overlay(GemShape().stroke(.white.opacity(0.6), lineWidth: 1.5))
                    .frame(width: 22, height: 26)
                    .keyframeAnimator(initialValue: CGPoint(x: from.x, y: from.y), trigger: launched.contains(index)) { content, point in
                        content.position(point)
                    } keyframes: { _ in
                        KeyframeTrack(\.x) { CubicKeyframe(from.x + spread, duration: 0.22); CubicKeyframe(to.x, duration: 0.38) }
                        KeyframeTrack(\.y) { CubicKeyframe(from.y - 90 - abs(spread) * 0.5, duration: 0.22); CubicKeyframe(to.y, duration: 0.38) }
                    }
                    .opacity(launched.contains(index) && !arrived.contains(index) ? 1 : 0)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .onChange(of: trigger) {
            Task { @MainActor in
                for index in 0..<count {
                    launched.insert(index)
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.6))
                        arrived.insert(index)
                        onArrive(index)
                    }
                    try? await Task.sleep(for: .seconds(0.09))
                }
            }
        }
    }
}

struct GemShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.38))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.38))
        p.closeSubpath()
        return p
    }
}
