import Foundation

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var date: Date
    /// The app the text went into; nil when it couldn't be inserted.
    public var appName: String?
    public var seconds: Double
    public var starred: Bool

    public init(id: UUID = UUID(), text: String, date: Date, appName: String?, seconds: Double, starred: Bool = false) {
        self.id = id
        self.text = text
        self.date = date
        self.appName = appName
        self.seconds = seconds
        self.starred = starred
    }

    public var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
}

public enum History {
    /// Drops entries older than `retentionDays`. Starred entries are kept
    /// regardless; 0 keeps nothing unstarred, and a negative value keeps
    /// everything.
    public static func pruned(_ entries: [HistoryEntry], now: Date, retentionDays: Int) -> [HistoryEntry] {
        guard retentionDays >= 0 else { return entries }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        return entries.filter { $0.starred || (retentionDays > 0 && $0.date >= cutoff) }
    }
}

/// Words dictated and time saved, counted per day. Kept separately from
/// history, so turning history off doesn't erase the totals.
public struct UsageStats: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable {
        public var words = 0
        public var dictations = 0
        public var seconds = 0.0
    }

    /// Typing speed used to estimate time saved: a typical 40 words a minute.
    public static let typingWordsPerMinute = 40.0

    /// Keyed by "yyyy-MM-dd" in the user's time zone.
    public var days: [String: Day] = [:]

    public init() {}

    public mutating func record(words: Int, seconds: Double, on date: Date, calendar: Calendar = .current) {
        let key = Self.key(for: date, calendar: calendar)
        var day = days[key, default: Day()]
        day.words += words
        day.dictations += 1
        day.seconds += seconds
        days[key] = day
    }

    /// Totals for the seven days ending on `date`.
    public func week(endingOn date: Date, calendar: Calendar = .current) -> Day {
        (0..<7).reduce(into: Day()) { total, offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date),
                  let entry = days[Self.key(for: day, calendar: calendar)]
            else { return }
            total.words += entry.words
            total.dictations += entry.dictations
            total.seconds += entry.seconds
        }
    }

    public var allTime: Day {
        days.values.reduce(into: Day()) { total, day in
            total.words += day.words
            total.dictations += day.dictations
            total.seconds += day.seconds
        }
    }

    /// Typing time for those words minus the time spent talking.
    public static func minutesSaved(_ day: Day) -> Double {
        max(0, Double(day.words) / typingWordsPerMinute - day.seconds / 60)
    }

    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
