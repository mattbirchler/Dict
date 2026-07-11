import Foundation
import SwiftData

@MainActor
@Observable
final class HistoryStore {
    private let container: ModelContainer

    /// Retention policy, pushed in from SettingsStore. Lowering the limit
    /// prunes immediately; .off stops saving but keeps existing entries.
    var limit: HistoryLimit = .fifty {
        didSet {
            guard limit != oldValue else { return }
            pruneOldEntries(context: container.mainContext)
            try? container.mainContext.save()
            fetchEntries()
        }
    }

    var recentEntries: [TranscriptionEntry] = []

    init(inMemory: Bool = false) {
        let schema = Schema([TranscriptionEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            self.container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        fetchEntries()
    }

    func save(cleanedText: String, timestamp: Date = Date()) {
        guard limit.savesHistory else { return }
        let context = container.mainContext
        let entry = TranscriptionEntry(cleanedText: cleanedText, timestamp: timestamp)
        context.insert(entry)
        pruneOldEntries(context: context)
        try? context.save()
        fetchEntries()
    }

    func clearAll() {
        let context = container.mainContext
        try? context.delete(model: TranscriptionEntry.self)
        try? context.save()
        fetchEntries()
    }

    func fetchEntries() {
        let context = container.mainContext
        let descriptor = FetchDescriptor<TranscriptionEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        recentEntries = (try? context.fetch(descriptor)) ?? []
    }

    private func pruneOldEntries(context: ModelContext) {
        guard let maxEntries = limit.maxEntries, maxEntries > 0 else { return }
        let descriptor = FetchDescriptor<TranscriptionEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor), all.count > maxEntries else { return }
        for entry in all.dropFirst(maxEntries) {
            context.delete(entry)
        }
    }
}
