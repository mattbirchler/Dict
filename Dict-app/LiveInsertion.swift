import Foundation

/// The arithmetic behind typing words into the focused field while the
/// user is still talking: what to add as confirmed words arrive, and how
/// to turn what was typed into the final text with the fewest edits.
enum LiveInsertionPlan {
    /// Keys to press to get from `typed` to `target`: delete that many
    /// characters off the end, then type `append`.
    struct Edit: Equatable {
        var deleteCount: Int
        var append: String

        static let none = Edit(deleteCount: 0, append: "")
    }

    static func edit(from typed: String, to target: String) -> Edit {
        let common = zip(typed, target).prefix { $0 == $1 }.count
        return Edit(
            deleteCount: typed.count - common,
            append: String(target.dropFirst(common))
        )
    }
}

/// Types confirmed words into the focused field as they arrive, remembers
/// exactly what it typed, and reconciles that with the final text when the
/// dictation ends. One instance per dictation.
@MainActor
final class LiveInserter {
    private let insertion: TextInsertionService
    private let smartLeadingSpace: Bool
    /// Everything this dictation has put into the field so far.
    private(set) var typed = ""
    private var decidedLeadingSpace = false
    private var leadingSpace = ""

    init(insertion: TextInsertionService, smartLeadingSpace: Bool) {
        self.insertion = insertion
        self.smartLeadingSpace = smartLeadingSpace
    }

    /// Brings the field up to date with the words the engine has settled on.
    func update(confirmed: String) {
        let words = confirmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        if !decidedLeadingSpace {
            decidedLeadingSpace = true
            if smartLeadingSpace,
               SmartSpacing.needsLeadingSpace(preceding: insertion.characterBeforeCursor(), text: words) {
                leadingSpace = " "
            }
        }
        apply(LiveInsertionPlan.edit(from: typed, to: leadingSpace + words))
    }

    /// Replaces what was typed with the final text. `finalText` is the
    /// complete insertion (spacing included) the pipeline would otherwise
    /// paste. Returns what it actually typed.
    @discardableResult
    func finish(with finalText: String) -> String {
        apply(LiveInsertionPlan.edit(from: typed, to: finalText))
        return typed
    }

    /// Removes everything this dictation typed, for Escape.
    func cancel() {
        apply(LiveInsertionPlan.edit(from: typed, to: ""))
    }

    /// Whether the final text needs a leading space, given what the
    /// inserter already decided when the first words went in.
    var insertedLeadingSpace: Bool { leadingSpace == " " }

    private func apply(_ edit: LiveInsertionPlan.Edit) {
        guard edit != .none else { return }
        if edit.deleteCount > 0 {
            insertion.deleteBackward(count: edit.deleteCount)
            typed = String(typed.dropLast(edit.deleteCount))
        }
        if !edit.append.isEmpty {
            insertion.typeText(edit.append)
            typed += edit.append
        }
    }
}
