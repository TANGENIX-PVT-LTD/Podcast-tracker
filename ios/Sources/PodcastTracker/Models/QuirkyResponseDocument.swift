import Foundation

struct QuirkyResponseDocument: Sendable, Equatable {
    enum Block: Sendable, Equatable {
        case heading(String)
        case paragraph(String)
        case bullet(String)
        case numbered(Int, String)

        var text: String {
            switch self {
            case .heading(let text), .paragraph(let text), .bullet(let text):
                text
            case .numbered(_, let text):
                text
            }
        }

        var wordCount: Int {
            text.split(whereSeparator: \.isWhitespace).count
        }
    }

    let blocks: [Block]

    init(markdown: String) {
        let normalized = Self.normalize(markdown)
        var parsed: [Block] = []

        for rawLine in normalized.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let numbered = Self.numberedLine(line) {
                parsed.append(.numbered(numbered.number, numbered.text))
            } else if let bullet = Self.bulletLine(line) {
                parsed.append(.bullet(bullet))
            } else if let heading = Self.markdownHeading(line) {
                parsed.append(.heading(heading))
            } else if let lead = Self.boldLead(line) {
                parsed.append(.heading(lead.title))
                if !lead.remainder.isEmpty {
                    parsed.append(.paragraph(lead.remainder))
                }
            } else {
                parsed.append(.paragraph(line))
            }
        }

        blocks = parsed.isEmpty ? [.paragraph(markdown)] : parsed
    }

    /// A defensive UI limit. The provider is still asked for a genuinely
    /// concise answer, but an overlong response cannot become another wall of
    /// text: the remainder stays available behind an explicit reveal control.
    var concisePreviewBlockCount: Int {
        guard blocks.count > 4 else { return blocks.count }

        var words = 0
        var count = 0
        for block in blocks {
            let nextWords = words + block.wordCount
            if count >= 3 && nextWords > 180 { break }
            words = nextWords
            count += 1
            if count == 7 { break }
        }
        return min(max(count, 3), blocks.count)
    }

    private static func normalize(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(
                of: #"(?<=[.!?])(?=\*\*[A-Z])"#,
                with: "\n\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?<=:)(?=\*\*["“])"#,
                with: "\n\n",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func markdownHeading(_ line: String) -> String? {
        let markerCount = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(markerCount) else { return nil }
        let index = line.index(line.startIndex, offsetBy: markerCount)
        guard index < line.endIndex, line[index].isWhitespace else { return nil }
        return String(line[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func bulletLine(_ line: String) -> String? {
        for prefix in ["- ", "• ", "* "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numberedLine(_ line: String) -> (number: Int, text: String)? {
        guard let period = line.firstIndex(of: "."),
              let number = Int(line[..<period]) else { return nil }
        let contentStart = line.index(after: period)
        guard contentStart < line.endIndex, line[contentStart].isWhitespace else { return nil }
        let text = String(line[contentStart...]).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (number, text)
    }

    private static func boldLead(_ line: String) -> (title: String, remainder: String)? {
        guard line.hasPrefix("**") else { return nil }
        let contentStart = line.index(line.startIndex, offsetBy: 2)
        guard let closing = line.range(of: "**", range: contentStart..<line.endIndex) else { return nil }

        let title = String(line[contentStart..<closing.lowerBound])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: ":")))
        guard !title.isEmpty else { return nil }
        let remainder = String(line[closing.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, remainder)
    }
}

enum QuirkyAnswerFormatter {
    static func format(_ markdown: String, style: QuirkyAnswerStyle) -> String {
        let document = QuirkyResponseDocument(markdown: markdown)
        switch style {
        case .concise:
            return concise(document)
        case .medium:
            return render(document.blocks, maximumWords: 600)
        case .detailed:
            return render(document.blocks, maximumWords: nil)
        }
    }

    private static func concise(_ document: QuirkyResponseDocument) -> String {
        let blocks = document.blocks
        let answerIndex = blocks.firstIndex {
            if case .paragraph = $0 { return true }
            return false
        }
        let answer = answerIndex.map { clipped(blocks[$0].text, maximumWords: 58) }
            ?? clipped(blocks.first?.text ?? "", maximumWords: 58)

        var points: [String] = []
        for block in blocks {
            switch block {
            case .bullet(let text), .numbered(_, let text):
                points.append(clipped(text, maximumWords: 22))
            default:
                continue
            }
            if points.count == 3 { break }
        }

        if points.isEmpty {
            for (index, block) in blocks.enumerated() where index != answerIndex {
                switch block {
                case .paragraph(let text):
                    points.append(clipped(text, maximumWords: 22))
                case .heading(let title):
                    guard !isGenericHeading(title), !isNextMove(title) else { continue }
                    if blocks.indices.contains(index + 1) {
                        points.append("**\(title):** \(clipped(blocks[index + 1].text, maximumWords: 17))")
                    }
                default:
                    continue
                }
                if points.count == 3 { break }
            }
        }

        var result = "## Answer\n\n\(answer)"
        if !points.isEmpty {
            result += "\n\n## Key points\n\n" + points.map { "- \($0)" }.joined(separator: "\n")
        }

        if let nextHeading = blocks.firstIndex(where: {
            if case .heading(let title) = $0 { return isNextMove(title) }
            return false
        }), blocks.indices.contains(nextHeading + 1) {
            result += "\n\n## Next move\n\n\(clipped(blocks[nextHeading + 1].text, maximumWords: 20))"
        }
        return result
    }

    private static func render(_ blocks: [QuirkyResponseDocument.Block], maximumWords: Int?) -> String {
        var rendered: [String] = []
        var words = 0

        for block in blocks {
            let remaining = maximumWords.map { $0 - words }
            guard remaining == nil || remaining! > 0 else { break }
            let text = remaining.map { clipped(block.text, maximumWords: $0) } ?? block.text
            guard !text.isEmpty else { continue }

            switch block {
            case .heading:
                rendered.append("## \(text)")
            case .paragraph:
                rendered.append(text)
            case .bullet:
                rendered.append("- \(text)")
            case .numbered(let number, _):
                rendered.append("\(number). \(text)")
            }
            words += text.split(whereSeparator: \.isWhitespace).count
        }

        return rendered.joined(separator: "\n\n")
    }

    private static func clipped(_ text: String, maximumWords: Int) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count > maximumWords else { return text }
        let prefix = words.prefix(maximumWords).joined(separator: " ")
        if let sentenceEnd = prefix.lastIndex(where: { ".!?".contains($0) }),
           prefix.distance(from: prefix.startIndex, to: sentenceEnd) > prefix.count / 2 {
            return String(prefix[...sentenceEnd])
        }
        return prefix + "…"
    }

    private static func isGenericHeading(_ title: String) -> Bool {
        let value = title.lowercased()
        return value == "answer" || value == "key points" || value == "key takeaways"
    }

    private static func isNextMove(_ title: String) -> Bool {
        let value = title.lowercased()
        return value.contains("next move") || value.contains("first move")
    }
}
