import Foundation
import Testing
@testable import Dict_app

struct DictationStatsTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ offset: Int) -> Date {
        let base = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 UTC
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    @Test func totalsAccumulate() {
        var stats = DictationStats()
        stats.record(words: 12, seconds: 5, on: day(0), calendar: calendar)
        stats.record(words: 30, seconds: 10, on: day(0), calendar: calendar)
        #expect(stats.words == 42)
        #expect(stats.dictations == 2)
        #expect(stats.secondsSpeaking == 15)
        #expect(stats.activeDays.count == 1)
    }

    @Test func timeSavedIsTypingTimeMinusSpeakingTime() {
        var stats = DictationStats()
        stats.record(words: 40, seconds: 20, on: day(0), calendar: calendar)
        // 40 words at 40 wpm is 60 s of typing, minus 20 s of talking.
        #expect(stats.secondsSaved == 40)
        stats.record(words: 1, seconds: 600, on: day(0), calendar: calendar)
        #expect(stats.secondsSaved == 0, "never negative")
    }

    @Test func streakCountsConsecutiveDaysThroughToday() {
        var stats = DictationStats()
        for offset in [-3, -2, -1, 0] {
            stats.record(words: 1, seconds: 1, on: day(offset), calendar: calendar)
        }
        #expect(stats.streak(today: day(0), calendar: calendar) == 4)
    }

    @Test func streakSurvivesUntilTheDayIsOver() {
        var stats = DictationStats()
        stats.record(words: 1, seconds: 1, on: day(-2), calendar: calendar)
        stats.record(words: 1, seconds: 1, on: day(-1), calendar: calendar)
        #expect(stats.streak(today: day(0), calendar: calendar) == 2, "nothing yet today still counts yesterday's run")
        #expect(stats.streak(today: day(1), calendar: calendar) == 0, "a missed day ends it")
    }

    @Test func streakIgnoresGaps() {
        var stats = DictationStats()
        stats.record(words: 1, seconds: 1, on: day(-5), calendar: calendar)
        stats.record(words: 1, seconds: 1, on: day(-1), calendar: calendar)
        stats.record(words: 1, seconds: 1, on: day(0), calendar: calendar)
        #expect(stats.streak(today: day(0), calendar: calendar) == 2)
    }

    @Test func activeDaysAreCapped() {
        var stats = DictationStats()
        for offset in 0..<(DictationStats.maxActiveDays + 10) {
            stats.record(words: 1, seconds: 1, on: day(offset), calendar: calendar)
        }
        #expect(stats.activeDays.count == DictationStats.maxActiveDays)
        #expect(stats.activeDays.last == DictationStats.dayKey(day(DictationStats.maxActiveDays + 9), calendar: calendar))
    }

    @Test func wordCountSplitsOnWhitespace() {
        #expect(DictationStats.wordCount("hello  there\nfriend") == 3)
        #expect(DictationStats.wordCount("   ") == 0)
    }

    @MainActor
    @Test func storeRoundTripsThroughDefaults() {
        let name = "DictationStatsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = StatsStore(defaults: defaults)
        store.record(text: "one two three", seconds: 2)
        store.record(text: "", seconds: 2)
        #expect(store.stats.words == 3)
        #expect(store.stats.dictations == 1)
        #expect(StatsStore(defaults: defaults).stats == store.stats)
        store.reset()
        #expect(StatsStore(defaults: defaults).stats == DictationStats())
    }
}
