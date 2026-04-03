import Foundation
import SwiftData

@Observable
final class HistoryStore {
    private let container: ModelContainer
    private let maxEntries = 50

    var recentEntries: [TranscriptionEntry] = []

    init() {
        let schema = Schema([TranscriptionEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            self.container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        fetchEntries()
    }

    @MainActor
    func save(cleanedText: String) {
        let context = container.mainContext
        let entry = TranscriptionEntry(cleanedText: cleanedText)
        context.insert(entry)
        pruneOldEntries(context: context)
        try? context.save()
        fetchEntries()
    }

    @MainActor
    func fetchEntries() {
        let context = container.mainContext
        let descriptor = FetchDescriptor<TranscriptionEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        recentEntries = (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    private func pruneOldEntries(context: ModelContext) {
        let descriptor = FetchDescriptor<TranscriptionEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor), all.count > maxEntries else { return }
        for entry in all.dropFirst(maxEntries) {
            context.delete(entry)
        }
    }
}
