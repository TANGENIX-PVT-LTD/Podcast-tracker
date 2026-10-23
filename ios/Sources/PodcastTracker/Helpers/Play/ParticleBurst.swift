import SwiftUI

/// Physics-based particles drawn in one Canvas: confetti rain, radial sparks, or gem bursts.
/// Restart by changing `trigger`. Draws nothing under Reduce Motion.
struct ParticleBurst: View {
    enum Style { case confetti, cannons, sparks, gems, ice }

    var style: Style = .confetti
    var trigger: Int = 0
    var count = 70
    var colors: [Color] = [Play.Palette.flame, Play.Palette.gold, Play.Palette.success, Play.Palette.gem, Color(hex: 0xCE82FF), Play.Palette.error]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var particles: [Particle] = []

    struct Particle {
        var origin: CGPoint      // unit space
        var velocity: CGVector   // unit/sec
        var gravity: Double
        var spin: Double
        var angle: Double
        var size: CGFloat
        var colorIndex: Int
        var shape: Int
        var life: Double
        var wobble: Double
    }

    var body: some View {
        TimelineView(.animation(paused: start == nil || reduceMotion)) { context in
            Canvas { gc, size in
                guard let start else { return }
                let t = context.date.timeIntervalSince(start)
                for p in particles where t < p.life {
                    let x = (p.origin.x + p.velocity.dx * t + sin(t * p.wobble) * 0.012) * size.width
                    let y = (p.origin.y + p.velocity.dy * t + 0.5 * p.gravity * t * t) * size.height
                    let fade = min(1, max(0, (p.life - t) / (p.life * 0.35)))
                    var layer = gc
                    layer.opacity = fade
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .radians(p.angle + p.spin * t))
                    let color = colors[p.colorIndex % colors.count]
                    let s = p.size
                    switch (style, p.shape) {
                    case (.gems, _):
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: -s)); path.addLine(to: CGPoint(x: s * 0.75, y: -s * 0.2))
                        path.addLine(to: CGPoint(x: 0, y: s)); path.addLine(to: CGPoint(x: -s * 0.75, y: -s * 0.2)); path.closeSubpath()
                        layer.fill(path, with: .color(Play.Palette.gem))
                        layer.fill(Path(ellipseIn: CGRect(x: -s * 0.25, y: -s * 0.55, width: s * 0.3, height: s * 0.3)), with: .color(.white.opacity(0.8)))
                    case (.ice, _):
                        var path = Path()
                        path.move(to: CGPoint(x: -s * 0.5, y: -s * 0.6)); path.addLine(to: CGPoint(x: s * 0.6, y: -s * 0.3))
                        path.addLine(to: CGPoint(x: s * 0.2, y: s * 0.7)); path.closeSubpath()
                        layer.fill(path, with: .color(p.shape == 0 ? Play.Palette.ice : .white))
                    case (.sparks, _):
                        let length = s * (1.2 + 2.2 * fade)
                        layer.fill(Path(roundedRect: CGRect(x: -s * 0.18, y: -length / 2, width: s * 0.36, height: length), cornerRadius: s * 0.18),
                                   with: .color(color))
                    case (_, 0):
                        // A flipping ribbon: scale the width by cos to fake a 3D tumble.
                        let flip = abs(cos(t * p.wobble))
                        layer.fill(Path(roundedRect: CGRect(x: -s * 0.5 * flip, y: -s * 0.3, width: s * flip, height: s * 0.6), cornerRadius: 1.5), with: .color(color))
                    case (_, 1):
                        layer.fill(Path(ellipseIn: CGRect(x: -s * 0.35, y: -s * 0.35, width: s * 0.7, height: s * 0.7)), with: .color(color))
                    default:
                        layer.fill(Self.star(s * 0.55), with: .color(color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { fire() }
        .onAppear { if trigger > 0 { fire() } }
    }

    private func fire() {
        guard !reduceMotion else { return }
        var generator = SystemRandomNumberGenerator()
        particles = (0..<count).map { index in
            let r = { (range: ClosedRange<Double>) in Double.random(in: range, using: &generator) }
            switch style {
            case .cannons:
                // Two party cannons in the bottom corners firing up and inward.
                let left = index.isMultiple(of: 2)
                let angle = left ? r(-.pi * 0.42 ... -.pi * 0.28) : r(-.pi * 0.72 ... -.pi * 0.58)
                let speed = r(1.3...2.1)
                return Particle(origin: CGPoint(x: left ? 0.02 : 0.98, y: 1.0), velocity: CGVector(dx: cos(angle) * speed * 0.55, dy: sin(angle) * speed),
                                gravity: 1.9, spin: r(-10...10), angle: r(0...6.28), size: CGFloat(r(9...15)), colorIndex: index,
                                shape: Int.random(in: 0...2), life: r(1.8...2.6), wobble: r(5...11))
            case .confetti:
                let angle = r(-.pi * 0.85 ... -.pi * 0.15)
                let speed = r(0.6...1.35)
                return Particle(origin: CGPoint(x: 0.5 + r(-0.08...0.08), y: 0.55), velocity: CGVector(dx: cos(angle) * speed * 0.6, dy: sin(angle) * speed),
                                gravity: 1.5, spin: r(-8...8), angle: r(0...6.28), size: CGFloat(r(8...14)), colorIndex: index,
                                shape: Int.random(in: 0...2), life: r(1.6...2.4), wobble: r(4...10))
            case .sparks, .gems, .ice:
                let angle = r(0...(2 * .pi))
                let speed = style == .gems ? r(0.35...0.7) : r(0.45...0.9)
                return Particle(origin: CGPoint(x: 0.5, y: 0.5), velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                                gravity: style == .sparks ? 0.25 : 0.9, spin: style == .sparks ? 0 : r(-6...6),
                                angle: style == .sparks ? angle + .pi / 2 : r(0...6.28), size: CGFloat(style == .gems ? r(9...15) : r(6...11)),
                                colorIndex: index, shape: Int.random(in: 0...1), life: r(0.7...1.2), wobble: 0)
            }
        }
        let fired = Date()
        start = fired
        let longest = particles.map(\.life).max() ?? 0
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(longest + 0.1))
            if start == fired { start = nil }   // stop the timeline once every particle is gone
        }
    }

    private static func star(_ radius: CGFloat) -> Path {
        var path = Path()
        for i in 0..<10 {
            let r = i.isMultiple(of: 2) ? radius : radius * 0.45
            let a = Double(i) * .pi / 5 - .pi / 2
            let point = CGPoint(x: cos(a) * r, y: sin(a) * r)
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
