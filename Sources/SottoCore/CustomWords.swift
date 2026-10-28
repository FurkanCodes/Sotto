import Foundation

/// Corrects misheard custom words (names, product terms) by fuzzy matching,
/// ported from Handy (`src-tauri/src/audio_toolkit/text.rs`, MIT).
///
/// Each run of one to three words is compared with every custom word, using
/// edit distance plus a Soundex sound-alike bonus, so "Charge B" becomes
/// "ChargeBee"; four-word runs count only on an exact match. The closest
/// match wins, and on a tie the shorter run wins. Handy lets the longer run
/// win a tie and stops at three words, so it turns "CHARGE B is great" into
/// "CHARGEBEE great" and "Chat G P T" into "ChatGPT T". Only ASCII words take part;
/// Soundex and whitespace splitting don't suit other scripts.
public enum CustomWords {
    /// Handy's default. Lower is stricter: 0 accepts only exact matches.
    public static let defaultThreshold = 0.18

    public static func apply(_ text: String, words customWords: [String], threshold: Double = defaultThreshold) -> String {
        guard !customWords.isEmpty else { return text }
        let keys = customWords.enumerated().flatMap { index, word in matchKeys(for: word, index: index) }
        guard !keys.isEmpty else { return text }

        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var result: [String] = []
        var index = 0
        while index < words.count {
            var best: (length: Int, replacement: String, score: Double)?
            for length in 1...4 where index + length <= words.count {
                let run = words[index..<(index + length)]
                // Never match across punctuation: in "Charge B, che" the comma ends the run at "B,".
                if run.dropLast().contains(where: { !punctuation(of: $0).suffix.isEmpty }) { continue }
                let candidate = run.map(matchKey).joined()
                // Four-word runs must match exactly ("Chat G P T"); fuzzy
                // matching that wide swallows neighbors ("use Chat G P").
                // So must runs with a common short word: fuzzily, "so the"
                // sounds like "Sotto" and "R and D" like many things.
                let exactOnly = length == 4 || (length > 1 && run.contains { commonWords.contains(matchKey($0)) })
                if let match = bestMatch(for: candidate, among: keys, words: customWords, threshold: threshold),
                   !exactOnly || match.score == 0,
                   match.score < (best?.score ?? .infinity) {
                    best = (length, match.word, match.score)
                }
            }
            if let best {
                let prefix = punctuation(of: words[index]).prefix
                let suffix = punctuation(of: words[index + best.length - 1]).suffix
                result.append(prefix + preservingCase(of: words[index], best.replacement) + suffix)
                index += best.length
            } else {
                result.append(words[index])
                index += 1
            }
        }
        return result.joined(separator: " ")
    }

    // MARK: - Matching

    /// Short English words that are almost never part of a misheard name.
    private static let commonWords: Set<String> = [
        "a", "an", "the", "to", "of", "in", "on", "at", "by", "for", "from", "with", "as", "so", "and", "or", "but",
        "if", "is", "it", "be", "do", "no", "not", "up", "out", "i", "me", "my", "we", "us", "our", "you", "he",
        "she", "they", "that", "this",
    ]

    private struct Key {
        let wordIndex: Int
        let key: String
    }

    private static func matchKeys(for word: String, index: Int) -> [Key] {
        var keys: [Key] = []
        let primary = matchKey(word)
        if isSupported(primary) { keys.append(Key(wordIndex: index, key: primary)) }
        if word.contains("&") {
            let expanded = matchKey(word.replacingOccurrences(of: "&", with: " and "))
            if isSupported(expanded), expanded != primary { keys.append(Key(wordIndex: index, key: expanded)) }
        }
        return keys
    }

    /// Letters and digits only, lowercased: "Charge" + "B," → "chargeb".
    static func matchKey(_ word: String) -> String {
        String(word.filter { $0.isLetter || $0.isNumber }).lowercased()
    }

    private static func isSupported(_ key: String) -> Bool {
        !key.isEmpty && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func bestMatch(for candidate: String, among keys: [Key], words: [String], threshold: Double) -> (word: String, score: Double)? {
        guard isSupported(candidate), candidate.count <= 50 else { return nil }
        var best: (word: String, score: Double)?
        for key in keys {
            let maxLength = Double(max(candidate.count, key.key.count))
            // Lengths may differ by 25% (at least 2 characters), so "openaigpt" can't match "openai".
            let lengthDifference = Double(abs(candidate.count - key.key.count))
            if lengthDifference > max(maxLength * 0.25, 2) { continue }

            var score = Double(levenshtein(candidate, key.key)) / maxLength
            if isAlphabetic(candidate), isAlphabetic(key.key), soundex(candidate) == soundex(key.key) {
                score *= 0.3
            }
            if score < threshold, score < (best?.score ?? .infinity) {
                best = (words[key.wordIndex], score)
            }
        }
        return best
    }

    private static func isAlphabetic(_ key: String) -> Bool {
        !key.isEmpty && key.allSatisfy { $0.isASCII && $0.isLetter }
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// American Soundex: the first letter plus three digits ("Robert" → "R163").
    static func soundex(_ word: String) -> String {
        let letters = word.uppercased().filter { $0.isASCII && $0.isLetter }
        guard let first = letters.first else { return "" }
        func code(_ letter: Character) -> Character? {
            switch letter {
            case "B", "F", "P", "V": "1"
            case "C", "G", "J", "K", "Q", "S", "X", "Z": "2"
            case "D", "T": "3"
            case "L": "4"
            case "M", "N": "5"
            case "R": "6"
            default: nil
            }
        }
        var result = String(first)
        var last = code(first)
        for letter in letters.dropFirst() {
            let digit = code(letter)
            if let digit, digit != last {
                result.append(digit)
                if result.count == 4 { break }
            }
            // H and W don't separate letters with the same code; vowels do.
            if letter != "H", letter != "W" { last = digit }
        }
        return result.padding(toLength: 4, withPad: "0", startingAt: 0)
    }

    // MARK: - Case and punctuation

    private static func preservingCase(of original: String, _ replacement: String) -> String {
        let letters = original.filter(\.isLetter)
        if !letters.isEmpty, letters.allSatisfy(\.isUppercase) {
            return replacement.uppercased()
        }
        if original.first?.isUppercase == true, let first = replacement.first {
            return first.uppercased() + replacement.dropFirst()
        }
        return replacement
    }

    /// The non-alphanumeric characters before and after a word: "「Handee。」" → ("「", "。」").
    static func punctuation(of word: String) -> (prefix: String, suffix: String) {
        guard let first = word.firstIndex(where: { $0.isLetter || $0.isNumber }),
              let last = word.lastIndex(where: { $0.isLetter || $0.isNumber })
        else { return (word, "") }
        return (String(word[..<first]), String(word[word.index(after: last)...]))
    }
}
