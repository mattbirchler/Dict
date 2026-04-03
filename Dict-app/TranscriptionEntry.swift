import Foundation
import SwiftData

@Model
final class TranscriptionEntry {
    var id: UUID
    var cleanedText: String
    var timestamp: Date

    init(cleanedText: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.cleanedText = cleanedText
        self.timestamp = timestamp
    }
}
