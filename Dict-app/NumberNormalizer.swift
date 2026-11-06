import Foundation

/// Writes spoken numbers as digits: "twenty five" becomes "25", "three
/// point five" becomes "3.5", "two thousand twenty six" and "nineteen
/// eighty four" become years, "twenty first" becomes "21st", and "at three
/// thirty" becomes "at 3:30". The transcription engines spell most numbers
/// out, and digits are almost always what was meant, so this runs on every
/// dictation whatever the style.
///
/// It is deliberately conservative about the words that are usually not
/// numbers at all: a lone "one" ("this one", "one of them") and a lone
/// ordinal up to "ninth" ("the first thing", "a second") stay words. A
/// lone "one" does become "1" next to another number ("one or two",
/// "one, two, three").
enum NumberNormalizer {
    static func apply(_ text: String) -> String {
        let pieces = tokenize(text)
        guard pieces.contains(where: { numberWords.contains($0.word) }) else { return text }
        var groups = parseGroups(in: pieces)
        guard !groups.isEmpty else { return text }
        mergeNeighbors(&groups, pieces: pieces)
        convertLonelyOnes(&groups, pieces: pieces)
        return render(pieces: pieces, groups: groups.filter(\.converts))
    }

    // MARK: - Tokens

    /// One word of the text with the punctuation and spacing around it, so
    /// the text can be put back together exactly where nothing changed.
    /// Hyphenated tokens are split into pieces joined by "-", so
    /// "twenty-one-year-old" can become "21-year-old".
    struct Piece {
        /// The whitespace or "-" before this piece ("" for the first).
        var separator: String
        /// Opening punctuation, like a quote or a parenthesis.
        var leading: String
        var core: String
        /// Closing punctuation. Ends any number phrase.
        var trailing: String

        var word: String { core.lowercased() }
        var endsPhrase: Bool { !trailing.isEmpty }
        var original: String { separator + leading + core + trailing }
    }

    static func tokenize(_ text: String) -> [Piece] {
        var pieces: [Piece] = []
        var separator = ""
        var token = ""
        func flush() {
            guard !token.isEmpty else { return }
            // Keep hyphens inside the token only when they sit between
            // letters; "twenty-five" splits, "--" or "-5" don't matter.
            let parts = token.split(separator: "-", omittingEmptySubsequences: false)
            for (index, part) in parts.enumerated() {
                let (leading, core, trailing) = splitPunctuation(String(part))
                pieces.append(Piece(separator: index == 0 ? separator : "-", leading: leading, core: core, trailing: trailing))
            }
            token = ""
            separator = ""
        }
        for character in text {
            if character.isWhitespace {
                flush()
                separator.append(character)
            } else {
                token.append(character)
            }
        }
        flush()
        if !separator.isEmpty {
            pieces.append(Piece(separator: separator, leading: "", core: "", trailing: ""))
        }
        return pieces
    }

    private static func splitPunctuation(_ token: String) -> (String, String, String) {
        var core = Substring(token)
        var leading = ""
        var trailing = ""
        while let first = core.first, isPunctuation(first) {
            leading.append(first)
            core = core.dropFirst()
        }
        while let last = core.last, isPunctuation(last) {
            trailing.insert(last, at: trailing.startIndex)
            core = core.dropLast()
        }
        return (leading, String(core), trailing)
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        // Apostrophes are part of words ("o'clock"); everything else that
        // isn't a letter or digit wraps the word.
        !(character.isLetter || character.isNumber || character == "'" || character == "\u{2019}")
    }

    // MARK: - Number words

    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    ]
    private static let teens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    private static let scales: [String: Int] = [
        "thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000, "trillion": 1_000_000_000_000,
    ]
    private static let ordinalUnits: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9,
    ]
    private static let ordinalTeens: [String: Int] = [
        "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14, "fifteenth": 15,
        "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19,
    ]
    private static let ordinalTens: [String: Int] = [
        "twentieth": 20, "thirtieth": 30, "fortieth": 40, "fiftieth": 50, "sixtieth": 60,
        "seventieth": 70, "eightieth": 80, "ninetieth": 90,
    ]
    private static let ordinalScales: [String: Int] = [
        "hundredth": 100, "thousandth": 1_000, "millionth": 1_000_000, "billionth": 1_000_000_000,
    ]
    /// Every word that can start a number phrase. Used as a quick exit.
    private static let numberWords: Set<String> = {
        var words = Set(units.keys).union(teens.keys).union(tens.keys)
        words.formUnion(ordinalUnits.keys)
        words.formUnion(ordinalTeens.keys)
        words.formUnion(ordinalTens.keys)
        words.insert("a")
        return words
    }()
    /// Words before "three thirty" that make it a time rather than two numbers.
    private static let timeCues: Set<String> = ["at", "around", "about", "by", "until", "till", "from", "before", "after", "since", "to"]
    private static let meridiems: Set<String> = ["am", "pm", "a.m", "p.m", "a.m.", "p.m."]
    /// A lone "one" next to one of these and another number is a number too.
    private static let connectors: Set<String> = ["or", "to", "and", "through"]

    // MARK: - Groups

    struct Group {
        var range: Range<Int>
        var value: Value
        /// The scale word the phrase ended on, when the value is a round
        /// multiple of it, so "three million" renders as "3 million".
        var scaleWord: String?
        /// Whether the phrase used "hundred" or a scale word. Those never
        /// merge into years or times.
        var hasMagnitude: Bool
        /// Whether to write this group as digits.
        var converts: Bool

        enum Value: Equatable {
            case cardinal(Int)
            case ordinal(Int)
            /// Digits already laid out, like "3.5", "3:30" or "5551212".
            case literal(String)
        }

        var wordCount: Int { range.count }
        var cardinal: Int? { if case .cardinal(let n) = value { n } else { nil } }
        var isLoneOne: Bool { wordCount == 1 && cardinal == 1 }
        var isSingleDigitWord: Bool { wordCount == 1 && !hasMagnitude && (cardinal.map { $0 < 10 } ?? false) }
    }

    static func parseGroups(in pieces: [Piece]) -> [Group] {
        var groups: [Group] = []
        var index = 0
        while index < pieces.count {
            if let group = parseGroup(in: pieces, from: index) {
                groups.append(group)
                index = group.range.upperBound
            } else {
                index += 1
            }
        }
        return groups
    }

    private enum Slot { case start, afterA, unit, teen, tens, hundred, and, scale }

    /// Whether the phrase can run from piece `index - 1` into piece `index`.
    private static func continues(_ pieces: [Piece], into index: Int) -> Bool {
        guard index < pieces.count, index > 0 else { return false }
        let piece = pieces[index]
        guard !pieces[index - 1].endsPhrase, piece.leading.isEmpty, !piece.core.isEmpty else { return false }
        return piece.separator == "-" || (!piece.separator.isEmpty && !piece.separator.contains(where: \.isNewline))
    }

    /// The longest number phrase starting at `start`, if the word there
    /// begins one.
    static func parseGroup(in pieces: [Piece], from start: Int) -> Group? {
        var total = 0
        var current = 0
        var slot = Slot.start
        var lastScale = Int.max
        var hasMagnitude = false
        var scaleWord: String?
        var index = start

        func finish(_ value: Group.Value, end: Int) -> Group? {
            guard end > start else { return nil }
            var group = Group(range: start..<end, value: value, scaleWord: scaleWord, hasMagnitude: hasMagnitude, converts: true)
            if group.isLoneOne { group.converts = false }
            if case .ordinal(let n) = value, group.wordCount == 1, n < 10 { group.converts = false }
            return group
        }

        while index < pieces.count, index == start || continues(pieces, into: index) {
            let word = pieces[index].word
            if let unit = units[word] {
                guard ([.start, .tens, .hundred, .and, .scale] as [Slot]).contains(slot) else { break }
                guard slot != .tens || unit > 0 else { break }
                current += unit
                slot = .unit
            } else if let teen = teens[word] {
                guard ([.start, .hundred, .and, .scale] as [Slot]).contains(slot) else { break }
                current += teen
                slot = .teen
            } else if let ten = tens[word] {
                guard ([.start, .hundred, .and, .scale] as [Slot]).contains(slot) else { break }
                current += ten
                slot = .tens
            } else if word == "hundred" {
                guard ([.unit, .teen, .tens, .afterA] as [Slot]).contains(slot), current > 0 else { break }
                current *= 100
                hasMagnitude = true
                scaleWord = nil
                slot = .hundred
            } else if let scale = scales[word] {
                guard current > 0, scale < lastScale, ([.unit, .teen, .tens, .hundred, .afterA] as [Slot]).contains(slot) else { break }
                total += current * scale
                current = 0
                lastScale = scale
                hasMagnitude = true
                scaleWord = scale >= 1_000_000 ? word : nil
                slot = .scale
            } else if word == "and" {
                guard ([.hundred, .scale] as [Slot]).contains(slot), continues(pieces, into: index + 1) else { break }
                let next = pieces[index + 1].word
                guard units[next] != nil || teens[next] != nil || tens[next] != nil else { break }
                slot = .and
            } else if word == "a" {
                guard slot == .start, continues(pieces, into: index + 1) else { break }
                let next = pieces[index + 1].word
                guard next == "hundred" || scales[next] != nil else { break }
                current = 1
                slot = .afterA
            } else if word == "point" {
                guard !([.start, .afterA, .and] as [Slot]).contains(slot), continues(pieces, into: index + 1), units[pieces[index + 1].word] != nil else { break }
                var digits = ""
                var end = index + 1
                while continues(pieces, into: end), let digit = units[pieces[end].word] {
                    digits.append(String(digit))
                    end += 1
                }
                scaleWord = nil
                return finish(.literal("\(total + current).\(digits)"), end: end)
            } else if let ordinal = ordinalUnits[word] {
                guard ([.start, .tens, .hundred, .and, .scale] as [Slot]).contains(slot) else { break }
                return finish(.ordinal(total + current + ordinal), end: index + 1)
            } else if let ordinal = ordinalTeens[word] ?? ordinalTens[word] {
                guard ([.start, .hundred, .and, .scale] as [Slot]).contains(slot) else { break }
                return finish(.ordinal(total + current + ordinal), end: index + 1)
            } else if let ordinal = ordinalScales[word] {
                guard current > 0, ([.unit, .teen, .tens, .afterA] as [Slot]).contains(slot) else { break }
                guard ordinal == 100 || ordinal < lastScale else { break }
                hasMagnitude = true
                return finish(.ordinal(total + current * ordinal), end: index + 1)
            } else {
                break
            }
            index += 1
        }
        // A phrase can't end on a connective.
        if slot == .and || slot == .afterA || slot == .start { return nil }
        return finish(.cardinal(total + current), end: index)
    }

    // MARK: - Merging

    /// Joins neighboring groups that read as one number: "nineteen
    /// eighty four" (a year), "at three thirty" (a time), and "five five
    /// five one two one two" (digits read one at a time).
    static func mergeNeighbors(_ groups: inout [Group], pieces: [Piece]) {
        var merged: [Group] = []
        var index = 0
        while index < groups.count {
            var group = groups[index]
            // Digits read one at a time: three or more in a row.
            var runEnd = index
            while runEnd + 1 < groups.count, groups[runEnd + 1].isSingleDigitWord, groups[runEnd].isSingleDigitWord,
                  adjacent(groups[runEnd], groups[runEnd + 1], in: pieces) {
                runEnd += 1
            }
            if runEnd - index >= 2 {
                let digits = groups[index...runEnd].map { String($0.cardinal ?? 0) }.joined()
                merged.append(Group(range: group.range.lowerBound..<groups[runEnd].range.upperBound, value: .literal(digits), scaleWord: nil, hasMagnitude: false, converts: true))
                index = runEnd + 1
                continue
            }
            if index + 1 < groups.count {
                let next = groups[index + 1]
                if adjacent(group, next, in: pieces), let value = merge(group, next, pieces: pieces) {
                    group = Group(range: group.range.lowerBound..<next.range.upperBound, value: value, scaleWord: nil, hasMagnitude: false, converts: true)
                    merged.append(group)
                    index += 2
                    continue
                }
            }
            merged.append(group)
            index += 1
        }
        groups = merged
    }

    private static func adjacent(_ a: Group, _ b: Group, in pieces: [Piece]) -> Bool {
        a.range.upperBound == b.range.lowerBound && continues(pieces, into: b.range.lowerBound) && pieces[b.range.lowerBound].separator != "-"
    }

    private static func merge(_ a: Group, _ b: Group, pieces: [Piece]) -> Group.Value? {
        guard let first = a.cardinal, let second = b.cardinal, !a.hasMagnitude, !b.hasMagnitude, a.wordCount == 1 else { return nil }
        // "at three thirty", "twelve fifteen pm"
        if (1...12).contains(first), (10...59).contains(second) {
            let before = a.range.lowerBound > 0 ? pieces[a.range.lowerBound - 1] : nil
            let after = b.range.upperBound < pieces.count ? pieces[b.range.upperBound] : nil
            let cued = (before.map { !$0.endsPhrase && timeCues.contains($0.word) } ?? false)
                || (after.map { !pieces[b.range.upperBound - 1].endsPhrase && meridiems.contains($0.word) } ?? false)
            if cued { return .literal("\(first):\(String(format: "%02d", second))") }
        }
        // "nineteen eighty four", "twenty twenty six"
        let yearStart = (11...19).contains(first) || (first % 10 == 0 && (20...90).contains(first))
        if yearStart, (10...99).contains(second), b.wordCount <= 2 {
            return .cardinal(first * 100 + second)
        }
        return nil
    }

    /// "one or two", "one, two, three", "between one and five": a lone
    /// "one" beside another number is a number.
    static func convertLonelyOnes(_ groups: inout [Group], pieces: [Piece]) {
        var changed = true
        while changed {
            changed = false
            for index in groups.indices where !groups[index].converts && groups[index].isLoneOne {
                let group = groups[index]
                let previous = index > 0 ? groups[index - 1] : nil
                let next = index + 1 < groups.count ? groups[index + 1] : nil
                let afterCounts = next.map { isCountingNeighbor($0) && neighbors(group, $0, in: pieces) } ?? false
                let beforeCounts = previous.map { isCountingNeighbor($0) && neighbors($0, group, in: pieces) } ?? false
                if afterCounts || beforeCounts {
                    groups[index].converts = true
                    changed = true
                }
            }
        }
    }

    /// A converted cardinal. "the tenth one" keeps its "one": an ordinal
    /// before it doesn't make it a count.
    private static func isCountingNeighbor(_ group: Group) -> Bool {
        if case .ordinal = group.value { return false }
        return group.converts
    }

    /// Whether `b` follows `a` directly, or with one connector word or a
    /// comma between them.
    private static func neighbors(_ a: Group, _ b: Group, in pieces: [Piece]) -> Bool {
        let gap = a.range.upperBound..<b.range.lowerBound
        let last = pieces[a.range.upperBound - 1]
        guard last.trailing.isEmpty || last.trailing == "," else { return false }
        switch gap.count {
        case 0: return true
        case 1:
            let between = pieces[gap.lowerBound]
            return connectors.contains(between.word) && !between.endsPhrase
        default: return false
        }
    }

    // MARK: - Rendering

    static func render(pieces: [Piece], groups: [Group]) -> String {
        var output = ""
        var index = 0
        var nextGroup = 0
        while index < pieces.count {
            if nextGroup < groups.count, groups[nextGroup].range.lowerBound == index {
                let group = groups[nextGroup]
                let first = pieces[group.range.lowerBound]
                let last = pieces[group.range.upperBound - 1]
                output += first.separator + first.leading + text(for: group) + last.trailing
                index = group.range.upperBound
                nextGroup += 1
            } else {
                output += pieces[index].original
                index += 1
            }
        }
        return output
    }

    static func text(for group: Group) -> String {
        switch group.value {
        case .literal(let digits):
            return digits
        case .ordinal(let n):
            return grouped(n) + ordinalSuffix(n)
        case .cardinal(let n):
            if let scaleWord = group.scaleWord, let scale = scales[scaleWord], n % scale == 0 {
                return "\(n / scale) \(scaleWord)"
            }
            return grouped(n)
        }
    }

    /// Thousands separators from 10,000 up; four-digit numbers are often
    /// years, so they stay plain.
    static func grouped(_ n: Int) -> String {
        guard n >= 10_000 else { return String(n) }
        var digits = Array(String(n))
        var position = digits.count - 3
        while position > 0 {
            digits.insert(",", at: position)
            position -= 3
        }
        return String(digits)
    }

    static func ordinalSuffix(_ n: Int) -> String {
        switch (n % 100, n % 10) {
        case (11...13, _): "th"
        case (_, 1): "st"
        case (_, 2): "nd"
        case (_, 3): "rd"
        default: "th"
        }
    }
}
