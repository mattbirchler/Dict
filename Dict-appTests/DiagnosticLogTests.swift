import Foundation
import Testing
@testable import Dict_app

struct DiagnosticLogTests {
    @Test func formatsEntriesOldestFirstWithHeader() {
        let t0 = Date(timeIntervalSince1970: 0)
        let out = DiagnosticLog.format([
            (date: t0.addingTimeInterval(1), category: "pipeline", level: "info", message: "second"),
            (date: t0, category: "engine", level: "error", message: "first"),
        ])
        let lines = out.split(separator: "\n")
        #expect(lines[0].hasPrefix("Dict "))
        #expect(lines[1].contains("[engine] error: first"))
        #expect(lines[2].contains("[pipeline] info: second"))
    }
}
