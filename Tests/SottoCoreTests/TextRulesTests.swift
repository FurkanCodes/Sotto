import Foundation
import Testing
@testable import SottoCore

struct TextRulesCase: Decodable, CustomTestStringConvertible, Sendable {
    let input: String
    let replacements: [[String]]?
    let snippets: [[String]]?
    let sayToSend: Bool?
    let expected: String
    let send: Bool

    var testDescription: String { input }

    static func load() throws -> [TextRulesCase] {
        struct File: Decodable { let cases: [TextRulesCase] }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/text-rules.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).cases
    }
}

struct TextRulesTests {
    static let date = Date(timeIntervalSince1970: 1_793_145_600) // 2026-10-28

    @Test(arguments: try TextRulesCase.load())
    func sharedFixture(_ fixture: TextRulesCase) {
        let result = TextRules.apply(
            fixture.input,
            replacements: (fixture.replacements ?? []).map { Replacement(from: $0[0], to: $0[1]) },
            snippets: (fixture.snippets ?? []).map { Snippet(trigger: $0[0], text: $0[1]) },
            sayToSend: fixture.sayToSend ?? true,
            date: Self.date,
            clipboard: "https://example.com/call"
        )
        #expect(result == TextRules.Result(text: fixture.expected, send: fixture.send))
    }

    @Test func dateAndTimeVariablesFill() {
        let filled = TextRules.fill("{date} at {time}", date: Self.date, clipboard: nil)
        #expect(!filled.contains("{"))
        #expect(filled.contains("2026"))
    }
}

struct HistoryTests {
    let now = Date(timeIntervalSince1970: 1_793_145_600)

    func entry(daysAgo: Double, starred: Bool = false) -> HistoryEntry {
        HistoryEntry(text: "x", date: now.addingTimeInterval(-daysAgo * 86_400), appName: nil, seconds: 1, starred: starred)
    }

    @Test func keepsOnlyRecentAndStarred() {
        let entries = [entry(daysAgo: 1), entry(daysAgo: 8), entry(daysAgo: 30, starred: true)]
        let kept = History.pruned(entries, now: now, retentionDays: 7)
        #expect(kept.count == 2)
        #expect(kept.contains(entries[0]))
        #expect(kept.contains(entries[2]))
    }

    @Test func offKeepsOnlyStarred() {
        let entries = [entry(daysAgo: 0), entry(daysAgo: 2, starred: true)]
        #expect(History.pruned(entries, now: now, retentionDays: 0) == [entries[1]])
    }

    @Test func foreverKeepsEverything() {
        let entries = [entry(daysAgo: 400)]
        #expect(History.pruned(entries, now: now, retentionDays: -1) == entries)
    }

    @Test func statsCountTheWeekAndTimeSaved() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var stats = UsageStats()
        stats.record(words: 400, seconds: 120, on: now, calendar: calendar)
        stats.record(words: 100, seconds: 30, on: now.addingTimeInterval(-3 * 86_400), calendar: calendar)
        stats.record(words: 999, seconds: 1, on: now.addingTimeInterval(-10 * 86_400), calendar: calendar)
        let week = stats.week(endingOn: now, calendar: calendar)
        #expect(week.words == 500)
        #expect(week.dictations == 2)
        // 500 words typed at 40 wpm is 12.5 min, minus 2.5 min of talking.
        #expect(UsageStats.minutesSaved(week) == 10)
        #expect(stats.allTime.words == 1499)
    }
}
