import Foundation

/// Applies spoken self-corrections with rules, not an AI model: "at 2,
/// actually 3" → "at 3".
///
/// It only fires when the corrected and the correcting value are the same
/// kind (a number or time, a day or month, or a name), joined by a
/// correction phrase. Anything else is left exactly as spoken, so the rule
/// can't change the meaning of a sentence it doesn't understand.
public enum SelfCorrection {
    private static let numberWords = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
        "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred",
    ]
    private static let dayWords = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december", "today", "tomorrow", "tonight",
    ]
    /// "no" and "sorry" only correct numbers and days; with names they too
    /// often start a new thought ("Tell Ali, sorry Mehmet, …").
    private static let strongMarkers = "actually|no wait|i mean|or rather|make that"
    private static let allMarkers = strongMarkers + "|no|sorry"

    private static let unit = "(?:\\s?(?:%|percent|am|pm|a\\.m\\.|p\\.m\\.|o'clock))"
    private static let number = "(?:\\d+(?:[.:]\\d+)?|(?:" + numberWords.joined(separator: "|") + "))" + unit + "?"
    private static let day = "(?:" + dayWords.joined(separator: "|") + ")"
    private static let name = "(?-i:\\p{Lu}[\\p{Ll}'’-]+)"

    private static func pattern(_ value: String, markers: String) -> NSRegularExpression? {
        // value, an optional comma or period, the marker, an optional comma, value.
        try? NSRegularExpression(
            pattern: "(?i)(?<![\\p{L}\\p{N}])(" + value + ")[,.]?\\s+(?:" + markers + ")[,]?\\s+(" + value + ")(?![\\p{L}\\p{N}])"
        )
    }

    private static let numberPattern = pattern(number, markers: allMarkers)
    private static let dayPattern = pattern(day, markers: allMarkers)
    private static let namePattern = pattern(name, markers: strongMarkers)

    public static func apply(_ text: String) -> String {
        var output = text
        // Repeat for chains: "2, actually 3, no 4" → "3, no 4" → "4".
        for _ in 0..<5 {
            let next = correct(output)
            if next == output { break }
            output = next
        }
        return output
    }

    private static func correct(_ text: String) -> String {
        if let result = replaceFirst(numberPattern, in: text, keepUnit: true) { return result }
        if let result = replaceFirst(dayPattern, in: text, keepUnit: false) { return result }
        if let result = replaceFirst(namePattern, in: text, keepUnit: false, isName: true) { return result }
        return text
    }

    /// Replaces the first valid match with its correcting value. Returns
    /// nil when nothing changed.
    private static func replaceFirst(_ pattern: NSRegularExpression?, in text: String, keepUnit: Bool, isName: Bool = false) -> String? {
        guard let pattern else { return nil }
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text),
                  let first = Range(match.range(at: 1), in: text),
                  let second = Range(match.range(at: 2), in: text)
            else { continue }
            let wrong = String(text[first])
            var right = String(text[second])
            if isName {
                // A capital at a sentence start isn't evidence of a name.
                if opensSentence(text[..<whole.lowerBound]) { continue }
                let lowered = [wrong.lowercased(), right.lowercased()]
                if lowered.contains(where: { dayWords.contains($0) || $0 == "i" }) { continue }
            }
            if keepUnit, let unit = unitSuffix(of: wrong), unitSuffix(of: right) == nil {
                // "3 pm, actually 4" means 4 pm.
                right += unit
            }
            var result = String(text[..<whole.lowerBound]) + right + text[whole.upperBound...]
            // "tomorrow. No wait, Friday." leaves the sentence break behind the old value.
            if text[first.upperBound..<second.lowerBound].hasPrefix("."), result.hasSuffix("..") {
                result.removeLast()
            }
            return result
        }
        return nil
    }

    private static func opensSentence(_ before: Substring) -> Bool {
        guard let last = before.last(where: { !$0.isWhitespace }) else { return true }
        return ".!?".contains(last)
    }

    private static let unitPattern = try? NSRegularExpression(pattern: "(?i)" + unit + "$")

    private static func unitSuffix(of value: String) -> String? {
        guard let unitPattern,
              let match = unitPattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range, in: value)
        else { return nil }
        return String(value[range])
    }
}
