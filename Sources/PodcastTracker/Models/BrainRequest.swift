import Foundation

/// The composer selections drive the actual provider request, including model, reasoning and output budget.
enum BrainRequest {
    static func body(system: String, question: String, history: [BrainMessage], modelID: String, effort: String,
                     temperature: Double, maxTokens: Int, answerStyle: QuirkyAnswerStyle) -> [String: Any] {
        var messages = [["role": "system", "content": system + "\nANSWER STRUCTURE:\n" + answerStyle.writingInstruction]]
        messages += history.suffix(4).filter { !$0.text.isEmpty }.map { ["role": $0.role, "content": String($0.text.prefix(700))] }
        messages.append(["role": "user", "content": question])
        var body: [String: Any] = ["model": modelID, "messages": messages, "temperature": temperature, "max_completion_tokens": maxTokens]
        body.merge(GroqReasoning.parameters(modelID: modelID, effort: effort)) { $1 }
        return body
    }
}
