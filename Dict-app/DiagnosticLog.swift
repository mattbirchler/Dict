import Foundation
import OSLog
import os

/// Reads Dict's own recent log entries back out of the unified log so a
/// person can paste them into a bug report.
enum DiagnosticLog {
    typealias Entry = (date: Date, category: String, level: String, message: String)

    /// Dict's entries from the last `interval` seconds of this process,
    /// formatted with `format`.
    static func recent(since interval: TimeInterval = 3600, now: Date = .now) throws -> String {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: now.addingTimeInterval(-interval))
        let predicate = NSPredicate(format: "subsystem == %@", Log.subsystem)
        let entries: [Entry] = try store.getEntries(at: position, matching: predicate)
            .compactMap { $0 as? OSLogEntryLog }
            .map { (date: $0.date, category: $0.category, level: levelName($0.level), message: $0.composedMessage) }
        return format(entries)
    }

    /// A header naming the app and OS version, then one line per entry,
    /// oldest first: `HH:mm:ss.SSS [category] level: message`.
    static func format(_ entries: [Entry]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let lines = entries
            .sorted { $0.date < $1.date }
            .map { "\(formatter.string(from: $0.date)) [\($0.category)] \($0.level): \($0.message)" }
        return ([header] + lines).joined(separator: "\n")
    }

    private static var header: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Dict \(version) (\(build)) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }

    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "log"
        }
    }
}
