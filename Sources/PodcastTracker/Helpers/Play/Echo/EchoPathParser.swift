import SwiftUI

/// Minimal SVG path-data parser (M L H V C S Q Z, absolute and relative). Echo and the flame are
/// authored as SVG strings so the exact same geometry renders on Android via Compose's PathParser.
enum SVGPath {
    static func parse(_ data: String) -> Path {
        var path = Path()
        var tokens = tokenize(data)[...]
        var current = CGPoint.zero, start = CGPoint.zero, lastControl: CGPoint?
        var command: Character = "M"

        func number() -> CGFloat {
            guard case .number(let value)? = tokens.first else { return 0 }
            tokens = tokens.dropFirst()
            return CGFloat(value)
        }
        func point(relative: Bool) -> CGPoint {
            let x = number(), y = number()
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while let token = tokens.first {
            if case .command(let c) = token { command = c; tokens = tokens.dropFirst() }
            let relative = command.isLowercase
            switch command.uppercased().first {
            case "M":
                current = point(relative: relative); start = current; path.move(to: current)
                command = relative ? "l" : "L"   // implicit lineto after the first pair
                lastControl = nil
            case "L":
                current = point(relative: relative); path.addLine(to: current); lastControl = nil
            case "H":
                let x = number(); current.x = relative ? current.x + x : x; path.addLine(to: current); lastControl = nil
            case "V":
                let y = number(); current.y = relative ? current.y + y : y; path.addLine(to: current); lastControl = nil
            case "C":
                let c1 = point(relative: relative), c2 = point(relative: relative), end = point(relative: relative)
                path.addCurve(to: end, control1: c1, control2: c2); current = end; lastControl = c2
            case "S":
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = point(relative: relative), end = point(relative: relative)
                path.addCurve(to: end, control1: c1, control2: c2); current = end; lastControl = c2
            case "Q":
                let c = point(relative: relative), end = point(relative: relative)
                path.addQuadCurve(to: end, control: c); current = end; lastControl = c
            case "Z":
                path.closeSubpath(); current = start; lastControl = nil
                if case .command? = tokens.first {} else if tokens.first != nil { command = "L" }
            default:
                tokens = tokens.dropFirst()
            }
        }
        return path
    }

    enum Token: Equatable { case command(Character), number(Double) }

    static func tokenize(_ data: String) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        func flush() { if let value = Double(buffer) { tokens.append(.number(value)) }; buffer = "" }
        for char in data {
            if char.isLetter && char != "e" && char != "E" {
                flush(); tokens.append(.command(char))
            } else if char == "-" && !buffer.isEmpty && buffer.last != "e" && buffer.last != "E" {
                flush(); buffer = "-"
            } else if char == "." && buffer.contains(".") {
                flush(); buffer = "."
            } else if char == "," || char.isWhitespace {
                flush()
            } else {
                buffer.append(char)
            }
        }
        flush()
        return tokens
    }
}
