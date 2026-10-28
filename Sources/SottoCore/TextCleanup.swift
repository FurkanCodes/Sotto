import Foundation

/// Rule-based cleanup of transcripts, ported from Handy
/// (`src-tauri/src/audio_toolkit/text.rs`, MIT).
///
/// Every step is a pure text-to-text function. A step that would turn
/// non-empty text into empty text is skipped, so a cleanup bug can never
/// swallow a dictation.
public enum TextCleanup {
    /// Tokens that are not words in any language Parakeet outputs.
    public static let universalFillers = ["uh", "uhm", "umm", "uhh", "uhhh", "ehh", "ehm", "ahm", "hmm", "hm", "mmm"]
    /// Safe to remove only when the output is English ("um" is a real word in
    /// Portuguese and German). Parakeet v3 can output 25 languages, so these
    /// are applied only when the caller says the text is English.
    public static let englishFillers = ["um", "ah", "eh"]

    public static func clean(_ text: String, removeFillers: Bool = true, english: Bool = true) -> String {
        var steps: [(String) -> String] = []
        if removeFillers {
            let pattern = english ? englishPattern : universalPattern
            steps.append { removeFillerWords($0, pattern: pattern) }
        }
        steps.append(collapseStutters)
        steps.append(collapseWhitespace)

        return steps.reduce(text) { current, step in
            let next = step(current)
            let lostEverything = next.isEmpty && !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return lostEverything ? current : next
        }
    }

    // MARK: - Filler words

    private static let universalPattern = fillerPattern(universalFillers)
    private static let englishPattern = fillerPattern(universalFillers + englishFillers)

    private static func fillerPattern(_ words: [String]) -> NSRegularExpression? {
        let alternatives = words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return try? NSRegularExpression(pattern: "(?i)\\b(?:\(alternatives))\\b[,.]?")
    }

    /// Deletes filler words. A capitalized filler that opened a sentence hands
    /// its capital to the next word: "Um, so I think" becomes "So I think".
    static func removeFillerWords(_ text: String, pattern: NSRegularExpression?) -> String {
        guard let pattern else { return text }
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var kept = ""
        var resume = text.startIndex
        var capitalOwed = false

        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            appendRestoringCapital(&kept, text[resume..<range.lowerBound], &capitalOwed)
            if text[range].first?.isUppercase == true && opensSentence(kept) {
                capitalOwed = true
            }
            resume = range.upperBound
        }
        appendRestoringCapital(&kept, text[resume...], &capitalOwed)
        return kept
    }

    private static func opensSentence(_ kept: String) -> Bool {
        guard let last = kept.last(where: { !$0.isWhitespace }) else { return true }
        return ".!?…".contains(last)
    }

    private static func appendRestoringCapital(_ kept: inout String, _ segment: Substring, _ capitalOwed: inout Bool) {
        guard capitalOwed, let index = segment.firstIndex(where: { $0.isLetter || $0.isNumber }) else {
            kept += segment
            return
        }
        capitalOwed = false
        kept += segment[..<index]
        kept += segment[index].uppercased()
        kept += segment[segment.index(after: index)...]
    }

    // MARK: - Stutters and whitespace

    /// Collapses a word repeated three or more times in a row to one instance:
    /// "I I I I think" becomes "I think". Two repetitions are kept, since
    /// "that that" is often intended.
    public static func collapseStutters(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return text }

        var result: [Substring] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            var run = 1
            if word.allSatisfy(\.isLetter) {
                let lower = word.lowercased()
                while index + run < words.count, words[index + run].lowercased() == lower {
                    run += 1
                }
            }
            result.append(word)
            index += run >= 3 ? run : 1
        }
        return result.joined(separator: " ")
    }

    public static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
