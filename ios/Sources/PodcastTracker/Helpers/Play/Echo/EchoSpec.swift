import SwiftUI

/// Echo, PodTrackio's mascot: a soft sound-blob in over-ear headphones.
/// Geometry lives in a 200×200 design space as SVG path data, mirrored 1:1 in `EchoSpec.kt` on Android.
/// Keep the two files in sync when editing a shape.
enum EchoSpec {
    struct Ellipse { let cx, cy, rx, ry: CGFloat
        var rect: CGRect { CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2) }
    }

    static let body = "M100 34 C146 34 170 66 172 110 C174 152 144 180 100 180 C56 180 26 152 28 110 C30 66 54 34 100 34 Z"
    static let belly = Ellipse(cx: 100, cy: 156, rx: 50, ry: 34)
    static let shine = Ellipse(cx: 70, cy: 62, rx: 15, ry: 8)
    static let feet = [Ellipse(cx: 78, cy: 180, rx: 17, ry: 8), Ellipse(cx: 122, cy: 180, rx: 17, ry: 8)]

    static let band = "M30 104 C30 -6 170 -6 170 104"
    static let bandWidth: CGFloat = 13
    static let pads = [CGRect(x: 36, y: 90, width: 14, height: 40), CGRect(x: 150, y: 90, width: 14, height: 40)]
    static let cups = [CGRect(x: 12, y: 82, width: 34, height: 56), CGRect(x: 154, y: 82, width: 34, height: 56)]
    static let cupRadius: CGFloat = 15

    static let eyes = [Ellipse(cx: 80, cy: 100, rx: 18, ry: 21), Ellipse(cx: 120, cy: 100, rx: 18, ry: 21)]
    static let pupilRadius: CGFloat = 10
    static let lookRange = CGSize(width: 6, height: 7)
    static let happyEyes = ["M64 104 Q80 86 96 104", "M104 104 Q120 86 136 104"]
    static let closedEyes = ["M64 102 Q80 110 96 102", "M104 102 Q120 110 136 102"]
    static let brows = ["M66 72 Q80 65 94 72", "M106 72 Q120 65 134 72"]
    static let browPivots = [CGPoint(x: 80, y: 70), CGPoint(x: 120, y: 70)]
    static let cheeks = [Ellipse(cx: 62, cy: 127, rx: 10, ry: 6), Ellipse(cx: 138, cy: 127, rx: 10, ry: 6)]

    enum Mouth { case stroke(String), fill(String), oval(Ellipse) }
    static let mouthSmile = Mouth.stroke("M86 130 Q100 145 114 130")
    static let mouthGrin = Mouth.fill("M82 128 Q100 162 118 128 Q100 136 82 128 Z")
    static let mouthFlat = Mouth.stroke("M90 137 L110 137")
    static let mouthWorried = Mouth.stroke("M87 141 Q100 129 113 141")
    static let mouthOh = Mouth.oval(Ellipse(cx: 100, cy: 138, rx: 7, ry: 9))
    static let mouthTalk = Mouth.oval(Ellipse(cx: 100, cy: 137, rx: 9, ry: 5.5))
    static let mouthSmirk = Mouth.stroke("M87 133 Q104 145 117 127")
    static let mouthFrozen = Mouth.stroke("M85 136 L92.5 131 L100 136 L107.5 131 L115 136")
    static let mouthSleepy = Mouth.stroke("M93 138 Q100 142 107 138")
    static let tongue = Ellipse(cx: 100, cy: 147, rx: 9, ry: 5)

    static let soundArcs = ["M192 92 Q200 110 192 128", "M200 82 Q212 110 200 138", "M8 92 Q0 110 8 128", "M0 82 Q-12 110 0 138"]
    static let thoughtDots = [Ellipse(cx: 156, cy: 30, rx: 4, ry: 4), Ellipse(cx: 168, cy: 17, rx: 6, ry: 6), Ellipse(cx: 185, cy: 4, rx: 9, ry: 8)]

    static let cupColor = Play.Palette.flame
    static let cupLip = Play.Palette.flameDeep
    static let ink = Play.Palette.ink
    static let cheekColor = Color(hex: 0xFF8FAB)
    static let tongueColor = Color(hex: 0xFF6B8A)
}

enum EchoMood: String, CaseIterable {
    case idle, happy, cheer, proud, worried, sleepy, frozen, thinking, talking
}

/// Pre-parsed shapes; parsing once keeps per-frame drawing cheap.
enum EchoShapes {
    static let body = SVGPath.parse(EchoSpec.body)
    static let band = SVGPath.parse(EchoSpec.band)
    static let happyEyes = EchoSpec.happyEyes.map(SVGPath.parse)
    static let closedEyes = EchoSpec.closedEyes.map(SVGPath.parse)
    static let brows = EchoSpec.brows.map(SVGPath.parse)
    static let soundArcs = EchoSpec.soundArcs.map(SVGPath.parse)
    static func mouth(_ mouth: EchoSpec.Mouth) -> (Path, Bool) {
        switch mouth {
        case .stroke(let d): (SVGPath.parse(d), false)
        case .fill(let d): (SVGPath.parse(d), true)
        case .oval(let e): (Path(ellipseIn: e.rect), true)
        }
    }
}
