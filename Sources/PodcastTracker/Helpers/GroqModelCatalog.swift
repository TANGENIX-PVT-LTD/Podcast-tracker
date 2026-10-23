import Foundation

/// Groq retires and renames models often. Resolve each tier against the key's live `/models` list
/// (cached for a day) instead of trusting a hard-coded ID.
actor GroqModelCatalog {
    static let shared = GroqModelCatalog()
    private var cached: (keyHash: Int, ids: Set<String>, fetched: Date)?

    func invalidate() { cached = nil }

    func available(apiKey: String, session: URLSession, baseURL: URL) async -> Set<String>? {
        if let cached, cached.keyHash == apiKey.hashValue, Date().timeIntervalSince(cached.fetched) < 86_400 { return cached.ids }
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let ids = Self.modelIDs(from: data), !ids.isEmpty else { return nil }
        cached = (apiKey.hashValue, ids, Date())
        return ids
    }

    func resolve(_ tier: QuirkyModel, apiKey: String, session: URLSession, baseURL: URL, excluding: String? = nil) async -> String {
        guard let ids = await available(apiKey: apiKey, session: session, baseURL: baseURL) else { return tier.modelID }
        return Self.pick(tier, from: ids, excluding: excluding)
    }

    static func pick(_ tier: QuirkyModel, from ids: Set<String>, excluding: String? = nil) -> String {
        let fallbacks = QuirkyModel.allCases.flatMap(\.preferredModelIDs)
        return (tier.preferredModelIDs + fallbacks).first { ids.contains($0) && $0 != excluding }
            ?? ids.sorted().first { $0 != excluding && !$0.contains("whisper") && !$0.contains("guard") && !$0.contains("tts") }
            ?? tier.modelID
    }

    static func modelIDs(from data: Data) -> Set<String>? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["data"] as? [[String: Any]] else { return nil }
        return Set(list.filter { ($0["active"] as? Bool) != false }.compactMap { $0["id"] as? String })
    }
}

/// Reasoning knobs differ per model family; sending the wrong one gets the whole request rejected.
enum GroqReasoning {
    static func parameters(modelID: String, effort: String) -> [String: Any] {
        if modelID.hasPrefix("openai/gpt-oss") {
            let level = ["low", "medium", "high"].contains(effort) ? effort : "low"
            return ["reasoning_effort": level, "include_reasoning": false]
        }
        if modelID.hasPrefix("qwen/") {
            // Qwen only understands "none" or "default".
            return ["reasoning_effort": effort == "none" ? "none" : "default", "reasoning_format": "hidden"]
        }
        return [:]
    }
}

/// Tolerant parsing for model output that should be JSON but may arrive fenced or wrapped in prose.
enum BrainReplyParser {
    static func jsonObject(in text: String) -> String? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") {
            body = body.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if let fence = body.range(of: "```", options: .backwards) { body = String(body[..<fence.lowerBound]) }
        }
        guard let start = body.firstIndex(of: "{"), let end = body.lastIndex(of: "}"), start < end else { return nil }
        return String(body[start...end])
    }

    static func memories(from text: String) -> [BrainReply.Memory] {
        guard let json = jsonObject(in: text), let data = json.data(using: .utf8),
              let reply = try? JSONDecoder().decode(BrainReply.self, from: data) else { return [] }
        return reply.memories
    }

    /// Accepts `{"answer": …}` JSON, fenced JSON, or plain Markdown.
    static func answer(from text: String) -> String {
        if let json = jsonObject(in: text), let data = json.data(using: .utf8),
           let reply = try? JSONDecoder().decode(BrainReply.self, from: data), !reply.answer.isEmpty { return reply.answer }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum BrainCitations {
    /// Removes citations that don't point at a retrieved source instead of discarding the whole answer.
    static func sanitize(_ text: String, sourceCount: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\s?\\[S([0-9]+)\\]") else { return text }
        let ns = text as NSString
        var result = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let number = Int(ns.substring(with: match.range(at: 1))) ?? 0
            if number < 1 || number > sourceCount, let range = Range(match.range, in: result) { result.removeSubrange(range) }
        }
        return result
    }

    /// Citation numbers in order of first appearance.
    static func cited(in text: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: "\\[S([0-9]+)\\]") else { return [] }
        let ns = text as NSString
        var seen: [Int] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if let n = Int(ns.substring(with: match.range(at: 1))), !seen.contains(n) { seen.append(n) }
        }
        return seen
    }

    /// The first "[123s]" transcript timestamp inside a passage, if any.
    static func timestamp(in passage: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: "\\[([0-9]+)s\\]"),
              let match = regex.firstMatch(in: passage, range: NSRange(location: 0, length: (passage as NSString).length)) else { return nil }
        return Double((passage as NSString).substring(with: match.range(at: 1)))
    }
}
