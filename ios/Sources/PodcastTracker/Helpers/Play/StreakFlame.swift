import SwiftUI

/// The streak flame: three layered SVG shapes with noise-driven flicker and small eyes.
/// Shapes are mirrored in Android's `StreakFlame.kt`.
enum FlameSpec {
    // 100×120 design space, base at y=116.
    static let outer = "M50 4 C60 24 90 40 92 72 C94 100 74 117 50 117 C26 117 6 100 8 72 C9 52 20 40 28 26 C32 38 38 45 44 47 C42 32 44 16 50 4 Z"
    static let inner = "M52 40 C60 56 75 66 75 87 C75 103 64 112 50 112 C36 112 25 103 25 88 C25 74 34 66 39 56 C42 64 46 67 49 67 C47 58 48 48 52 40 Z"
    static let core = "M50 72 C56 82 64 88 64 98 C64 106 58 110 50 110 C42 110 36 106 36 98 C36 90 44 84 50 72 Z"
}

struct StreakFlame: View {
    enum State { case lit, dim, ash, frozen }

    var state: State = .lit
    var size: CGFloat = 64
    var showsFace = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let outer = SVGPath.parse(FlameSpec.outer)
    private static let inner = SVGPath.parse(FlameSpec.inner)
    private static let core = SVGPath.parse(FlameSpec.core)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || state == .ash || state == .frozen)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { gc, canvas in
                let scale = canvas.height / 122
                gc.translateBy(x: (canvas.width - 100 * scale) / 2, y: 0)
                gc.scaleBy(x: scale, y: scale)
                draw(&gc, t: t)
            }
        }
        .frame(width: size * 100 / 122, height: size)
        .accessibilityHidden(true)
    }

    private var palette: (outer: [Color], inner: [Color], core: Color) {
        switch state {
        case .lit: ([Play.Palette.flameDeep, Play.Palette.flame], [Play.Palette.flame, Play.Palette.gold], Play.Palette.flameCore)
        case .dim: ([Color(hex: 0xC9733A), Color(hex: 0xE3A15F)], [Color(hex: 0xE3A15F), Color(hex: 0xF0C987)], Color(hex: 0xF6E3B5))
        case .ash: ([Color(hex: 0x9A9A9A), Play.Palette.ash], [Play.Palette.ash, Color(hex: 0xCFCFCF)], Color(hex: 0xE5E5E5))
        case .frozen: ([Play.Palette.iceDeep, Play.Palette.ice], [Play.Palette.ice, Color(hex: 0xD3F1FF)], .white)
        }
    }

    private func draw(_ gc: inout GraphicsContext, t: Double) {
        let energy: Double = state == .lit ? 1 : state == .dim ? 0.45 : 0
        // Layered flicker: each layer sways and stretches at its own frequency from the base.
        func flick(_ layer: inout GraphicsContext, speed: Double, amount: Double) {
            let sway = (sin(t * speed) * 0.6 + sin(t * speed * 2.3 + 1.7) * 0.4) * amount * energy
            let stretch = 1 + (sin(t * speed * 1.7 + 0.4) * 0.5 + 0.5) * 0.07 * amount * energy
            layer.translateBy(x: 50, y: 117)
            layer.concatenate(CGAffineTransform(a: 1, b: 0, c: sway * 0.18, d: stretch, tx: 0, ty: 0))
            layer.translateBy(x: -50, y: -117)
        }
        let colors = palette
        var outer = gc; flick(&outer, speed: 5.1, amount: 1)
        outer.fill(Self.outer, with: .linearGradient(Gradient(colors: colors.outer), startPoint: CGPoint(x: 50, y: 117), endPoint: CGPoint(x: 50, y: 4)))
        var inner = gc; flick(&inner, speed: 6.7, amount: 1.4)
        inner.fill(Self.inner, with: .linearGradient(Gradient(colors: colors.inner), startPoint: CGPoint(x: 50, y: 112), endPoint: CGPoint(x: 50, y: 40)))
        var core = gc; flick(&core, speed: 8.3, amount: 1.8)
        core.fill(Self.core, with: .color(colors.core.opacity(state == .ash ? 0.5 : 0.95)))

        guard showsFace else { return }
        let ink = Play.Palette.ink
        let blink = sin(t * 0.9) > 0.985 ? 0.15 : 1.0
        for x in [41.0, 59.0] {
            let eye = CGRect(x: x - 4, y: 84 - 5.5 * blink, width: 8, height: 11 * blink)
            switch state {
            case .ash:
                gc.stroke(Path { $0.move(to: CGPoint(x: x - 4, y: 86)); $0.addLine(to: CGPoint(x: x + 4, y: 86)) }, with: .color(ink.opacity(0.6)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            case .frozen:
                gc.stroke(Path { $0.move(to: CGPoint(x: x - 4, y: 82)); $0.addLine(to: CGPoint(x: x + 4, y: 88)); $0.move(to: CGPoint(x: x + 4, y: 82)); $0.addLine(to: CGPoint(x: x - 4, y: 88)) },
                          with: .color(Play.Palette.iceDeep), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            default:
                gc.fill(Path(ellipseIn: eye), with: .color(ink))
                gc.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: 81, width: 3, height: 3)), with: .color(.white.opacity(blink)))
            }
        }
        if state == .dim {
            // Worried brows when the streak is at risk.
            gc.stroke(Path { $0.move(to: CGPoint(x: 35, y: 74)); $0.addLine(to: CGPoint(x: 44, y: 76)) }, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            gc.stroke(Path { $0.move(to: CGPoint(x: 65, y: 74)); $0.addLine(to: CGPoint(x: 56, y: 76)) }, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
    }
}

/// One cell of the Monday-first week strip.
struct StreakDay: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable { case done, frozen, missed, today, todayDone, future }
    var id: String
    var letter: String
    var state: State
}

extension HabitLoop {
    /// The current Monday-first week, each day marked learned, frozen, missed, today or future.
    func weekStrip(activities: [DailyLearningActivity], now: Date = Date(), calendar: Calendar = .current) -> [StreakDay] {
        var monday = calendar
        monday.firstWeekday = 2; monday.minimumDaysInFirstWeek = 4
        let start = monday.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let learned = learningDays(activities: activities)
        let frozen = streak(activities: activities, now: now, calendar: calendar).frozenDays
        let today = LearningCalendar.dateKey(for: now, calendar: calendar)
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = LearningCalendar.dateKey(for: date, calendar: calendar)
            let state: StreakDay.State
            if key == today { state = learned.contains(key) ? .todayDone : .today }
            else if key > today { state = .future }
            else if learned.contains(key) { state = .done }
            else if frozen.contains(key) { state = .frozen }
            else { state = .missed }
            return StreakDay(id: key, letter: letters[offset], state: state)
        }
    }
}

enum StreakMilestones {
    static let all = [3, 7, 14, 30, 50, 100, 365]
    static func next(after count: Int) -> Int { all.first { $0 > count } ?? ((count / 100) + 1) * 100 }
    static func previous(before count: Int) -> Int { all.last { $0 <= count } ?? 0 }
}
