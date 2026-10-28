import Foundation

/// Spots a word the user fixed by hand right after dictating, so it can be
/// offered for the dictionary: "Furcan" typed over as "Furkan".
///
/// It compares the text field before and after the edit, and only accepts
/// one or two dictated words replaced by a single word that looks or
/// sounds alike and has a capital or a digit (names and product terms).
/// Rewordings and everyday spelling fixes ("their" → "there") are ignored.
public enum CorrectionLearning {
    public static func learnedWord(before: String, after: String, inserted: String, known: [String]) -> String? {
        let old = tokens(before)
        let new = tokens(after)
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }

        let removed = Array(old[prefix..<(old.count - suffix)])
        let added = Array(new[prefix..<(new.count - suffix)])
        guard (1...2).contains(removed.count), added.count == 1, let word = added.first else { return nil }

        // The replaced words must come from the dictation, not from text
        // that was already in the field.
        let dictated = Set(tokens(inserted).map { $0.lowercased() })
        guard removed.allSatisfy({ dictated.contains($0.lowercased()) }) else { return nil }

        guard word.count >= 2, word.contains(where: \.isLetter),
              word.contains(where: { $0.isUppercase || $0.isNumber })
        else { return nil }
        guard !known.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return nil }

        let wrongKey = CustomWords.matchKey(removed.joined())
        let rightKey = CustomWords.matchKey(word)
        guard !wrongKey.isEmpty, !rightKey.isEmpty, wrongKey != rightKey else { return nil }
        let distance = Double(CustomWords.levenshtein(wrongKey, rightKey)) / Double(max(wrongKey.count, rightKey.count))
        let soundsAlike = CustomWords.soundex(wrongKey) == CustomWords.soundex(rightKey)
        guard distance <= 0.5 || soundsAlike else { return nil }
        return word
    }

    /// Words with their inner apostrophes and hyphens; punctuation around
    /// them is dropped.
    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "’" || $0 == "-") })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'’-")) }
            .filter { !$0.isEmpty }
    }
}
