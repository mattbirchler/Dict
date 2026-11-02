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

    /// Where history lives on disk. SwiftData's default for a non-sandboxed
    /// app is a shared `Application Support/default.store`, which other apps
    /// use too, so Dict keeps its own folder.
    static func storeURL(applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent("Dict", isDirectory: true)
            .appendingPathComponent("History.store")
    }

    init(inMemory: Bool = false) {
        let schema = Schema([TranscriptionEntry.self])
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let url = Self.storeURL(applicationSupport: support)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            config = ModelConfiguration(schema: schema, url: url)
        }
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
