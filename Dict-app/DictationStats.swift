import Foundation

/// Lifetime totals that survive history pruning: words dictated, time
/// spent speaking, and the days with at least one dictation.
struct DictationStats: Codable, Equatable {
    var words = 0
    var dictations = 0
    var secondsSpeaking: Double = 0
    /// Days with a dictation as "yyyy-MM-dd", ascending, unique.
    var activeDays: [String] = []

    /// A fair typing speed to measure savings against.
    static let typingWordsPerMinute = 40.0
    /// Enough days to show a long streak without growing forever.
    static let maxActiveDays = 400

    /// Time typing would have taken, minus the time spent talking.
    var secondsSaved: Double {
        max(0, Double(words) / Self.typingWordsPerMinute * 60 - secondsSpeaking)
    }

    mutating func record(words newWords: Int, seconds: Double, on date: Date = Date(), calendar: Calendar = .current) {
        words += newWords
        dictations += 1
        secondsSpeaking += max(0, seconds)
        let day = Self.dayKey(date, calendar: calendar)
        if activeDays.last != day {
            activeDays.append(day)
            activeDays.sort()
            if activeDays.count > Self.maxActiveDays {
                activeDays.removeFirst(activeDays.count - Self.maxActiveDays)
            }
        }
    }

    /// Consecutive days with a dictation, counting back from today, or
    /// from yesterday if today hasn't had one yet.
    func streak(today: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set(activeDays)
        var cursor = calendar.startOfDay(for: today)
        if !days.contains(Self.dayKey(cursor, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(Self.dayKey(cursor, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

/// Keeps `DictationStats` in UserDefaults and publishes it to the UI.
@MainActor
@Observable
final class StatsStore {
    private(set) var stats: DictationStats
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "dictationStats"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.stats = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(DictationStats.self, from: $0) } ?? DictationStats()
    }

    func record(text: String, seconds: Double) {
        let words = DictationStats.wordCount(text)
        guard words > 0 else { return }
        stats.record(words: words, seconds: seconds)
        if let data = try? JSONEncoder().encode(stats) {
            defaults.set(data, forKey: Self.key)
        }
    }

    func reset() {
        stats = DictationStats()
        defaults.removeObject(forKey: Self.key)
    }
}
