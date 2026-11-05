import os

/// One Logger per area of the app. Messages land in the unified log under
/// the `birchtree.Dict-app` subsystem, which is what DiagnosticLog reads back
/// for bug reports. Mark transcripts and pasted text `.private`; everything
/// else can be `.public` so it shows up in a copied log.
nonisolated enum Log {
    static let subsystem = "birchtree.Dict-app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let formatter = Logger(subsystem: subsystem, category: "formatter")
    static let keys = Logger(subsystem: subsystem, category: "keys")
    static let insertion = Logger(subsystem: subsystem, category: "insertion")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let hud = Logger(subsystem: subsystem, category: "hud")
    static let updates = Logger(subsystem: subsystem, category: "updates")
}
