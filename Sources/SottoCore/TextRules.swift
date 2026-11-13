import Foundation

/// "gee mail" → "Gmail": exact phrase swaps, applied after cleanup.
public struct Replacement: Codable, Equatable, Hashable, Sendable {
    public var from: String
    public var to: String
    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// Say the trigger, get the text: "my address" → the full address.
/// `text` may hold {date}, {time} and {clipboard}.
public struct Snippet: Codable, Equatable, Hashable, Sendable {
    public var trigger: String
    public var text: String
    public init(trigger: String, text: String) {
        self.trigger = trigger
        self.text = text
    }
}

/// The text steps that run after cleanup, in this order: replacements, then
/// snippets, then the spoken "send it" ending. All pure, so every Sotto
/// implementation can pass the same fixtures.
public enum TextRules {
    public struct Result: Equatable, Sendable {
        public var text: String
        /// The user ended with "send it": press Return after inserting.
        public var send: Bool
    }

    public static func apply(
        _ text: String,
        replacements: [Replacement],
        snippets: [Snippet],
        sayToSend: Bool,
        date: Date = Date(),
        clipboard: String? = nil
    ) -> Result {
        var output = applyReplacements(text, replacements)
        output = expandSnippets(output, snippets, date: date, clipboard: clipboard)
        guard sayToSend else { return Result(text: output, send: false) }
        return stripSendPhrase(output)
    }

    // MARK: - Replacements

    public static func applyReplacements(_ text: String, _ rules: [Replacement]) -> String {
        rules.reduce(text) { current, rule in
            replacePhrase(rule.from, with: { _ in rule.to }, in: current)
        }
    }

    // MARK: - Snippets

    /// A trigger is replaced wherever it's said as whole words. If the
    /// trigger is the entire dictation, its trailing period goes too, so
    /// "My address." becomes just the address.
    public static func expandSnippets(_ text: String, _ snippets: [Snippet], date: Date, clipboard: String?) -> String {
        snippets.reduce(text) { current, snippet in
            let expanded = fill(snippet.text, date: date, clipboard: clipboard)
            if normalized(current) == normalized(snippet.trigger) {
                return expanded
            }
            return replacePhrase(snippet.trigger, with: { _ in expanded }, in: current)
        }
    }

    static func fill(_ template: String, date: Date, clipboard: String?) -> String {
        let day = DateFormatter()
        day.dateStyle = .long
        day.timeStyle = .none
        let time = DateFormatter()
        time.dateStyle = .none
        time.timeStyle = .short
        return template
            .replacingOccurrences(of: "{date}", with: day.string(from: date))
            .replacingOccurrences(of: "{time}", with: time.string(from: date))
            .replacingOccurrences(of: "{clipboard}", with: clipboard ?? "")
    }

    // MARK: - "send it"

    private static let sendPattern = try? NSRegularExpression(
        // Leading spaces and commas go with the phrase; a period ending the
        // previous sentence stays.
        pattern: "(?i)(?:^|[\\s,;:]+)send it[\\s.!?]*$"
    )

    /// Removes a final "send it" (with any punctuation around it) and
    /// reports that Return should be pressed. "See you soon. Send it." →
    /// "See you soon." plus send. Only the very end counts, so a sentence
    /// that merely contains the words keeps them.
    public static func stripSendPhrase(_ text: String) -> Result {
        guard let pattern = sendPattern,
              let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return Result(text: text, send: false) }
        var kept = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        // "…tomorrow, send it" leaves a dangling comma.
        while let last = kept.last, ",;:".contains(last) { kept.removeLast() }
        return Result(text: kept, send: true)
    }

    // MARK: - Helpers

    /// Lowercased, without punctuation or extra spaces, for comparing phrases.
    static func normalized(_ text: String) -> String {
        text.lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Replaces each whole-word, case-insensitive occurrence of `phrase`.
    /// Spaces in the phrase match any run of spaces.
    static func replacePhrase(_ phrase: String, with replacement: (String) -> String, in text: String) -> String {
        let words = phrase.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !words.isEmpty,
              let regex = try? NSRegularExpression(pattern: "(?i)(?<![\\p{L}\\p{N}])" + words.joined(separator: "\\s+") + "(?![\\p{L}\\p{N}])")
        else { return text }
        var result = ""
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            result += text[cursor..<range.lowerBound]
            result += replacement(String(text[range]))
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }
}
