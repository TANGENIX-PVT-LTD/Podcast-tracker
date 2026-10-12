import Foundation

/// The composer selections drive the actual provider request, including model, reasoning and output budget.
enum BrainRequest {
    static func body(system: String, question: String, history: [BrainMessage], model: QuirkyModel, answerStyle: QuirkyAnswerStyle) -> [String: Any] {
        var messages = [["role": "system", "content": system + "\nANSWER STRUCTURE:\n" + answerStyle.writingInstruction]]
        messages += history.suffix(4).map { ["role": $0.role, "content": String($0.text.prefix(700))] }
        messages.append(["role": "user", "content": question])
        var body: [String: Any] = ["model": model.modelID, "messages": messages,
            "temperature": model.temperature, "reasoning_effort": model.reasoningEffort,
            "max_completion_tokens": model.maximumCompletionTokens(for: answerStyle), "response_format": ["type": "json_object"]]
        if model == .balanced { body["reasoning_format"] = "hidden" } else { body["include_reasoning"] = false }
        return body
    }
}
