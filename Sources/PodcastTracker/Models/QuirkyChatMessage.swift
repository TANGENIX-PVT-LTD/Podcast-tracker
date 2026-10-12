import Foundation

struct QuirkyChatMessage: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case user, quirky }

    let id: UUID
    let role: Role
    let text: String
    let model: QuirkyModel?
    let answerStyle: QuirkyAnswerStyle?

    init(id: UUID = UUID(), role: Role, text: String, model: QuirkyModel?, answerStyle: QuirkyAnswerStyle? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.model = model
        self.answerStyle = answerStyle
    }
}
