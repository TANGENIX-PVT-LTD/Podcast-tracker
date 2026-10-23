import CryptoKit
import Foundation

enum RecallEvidence {
    static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
}

struct HabitSyncResponse: Codable, Sendable {
    var legacyXP: Int
    var startedDay: String
    var events: [HabitEvent]
}
