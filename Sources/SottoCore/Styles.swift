import Foundation

/// How dictated text is shaped for the app it goes into. Rule-based: only
/// capitalization, the final period and the trailing space change, never
/// the words.
public enum TextStyle: String, Codable, CaseIterable, Sendable {
    /// Proper sentences, as transcribed, with the final period added when
    /// the model left it off.
    case standard
    /// Chat: no capital at the start, no period at the end.
    case casual
    /// Code editors and terminals: like casual, and no trailing space.
    case plain

    public var appendsSpace: Bool { self != .plain }
}

/// The user's choice for one app, overriding the built-in default.
public struct StyleRule: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var app: AppRef
    public var style: TextStyle
    public var id: String { app.bundleID }
    public init(app: AppRef, style: TextStyle) {
        self.app = app
        self.style = style
    }
}

public enum Styles {
    /// Built-in defaults by bundle identifier. Everything else is standard.
    static let casualApps: Set<String> = [
        "com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "net.whatsapp.WhatsApp",
        "com.hnc.Discord", "ru.keepcoder.Telegram", "org.telegram.desktop",
        "org.whispersystems.signal-desktop", "com.microsoft.teams2", "com.facebook.archon",
    ]
    static let plainApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode", "dev.zed.Zed",
        "com.sublimetext.4", "com.exafunction.windsurf",
    ]

    /// The user's rule for this app, else the built-in default.
    public static func style(forBundleID bundleID: String?, rules: [StyleRule]) -> TextStyle {
        guard let bundleID else { return .standard }
        if let rule = rules.first(where: { $0.app.bundleID == bundleID }) { return rule.style }
        return defaultStyle(forBundleID: bundleID)
    }

    public static func defaultStyle(forBundleID bundleID: String) -> TextStyle {
        if casualApps.contains(bundleID) { return .casual }
        if plainApps.contains(bundleID) || bundleID.hasPrefix("com.jetbrains.") { return .plain }
        return .standard
    }

    /// Shapes `text` for `style`. `keepCapitalized` lists words whose
    /// capital stays even at the start, such as the user's custom words.
    public static func apply(_ text: String, style: TextStyle, keepCapitalized: [String] = []) -> String {
        guard !text.isEmpty else { return text }
        if style == .standard { return endingSentence(text) }
        var output = lowercasingFirstWord(text, keepCapitalized: keepCapitalized)
        // Questions and exclamations keep their mark; only a final period goes.
        if output.hasSuffix("."), !output.hasSuffix("..") {
            output.removeLast()
        }
        return output
    }

    /// "So I think we should ship it on Friday" gets its period. Streaming
    /// models often leave it off. Only text that reads as a full sentence
    /// (a capital first letter, three or more words, ending in a letter or
    /// digit) gets one, so "Yes" and "ok see you" stay as they are.
    static func endingSentence(_ text: String) -> String {
        guard let last = text.last, last.isLetter || last.isNumber,
              text.first(where: \.isLetter)?.isUppercase == true,
              text.split(whereSeparator: \.isWhitespace).count >= 3
        else { return text }
        return text + "."
    }

    /// "Sounds good" → "sounds good", but "I", "NASA", "iPhone" and the
    /// user's custom words keep their capitals.
    static func lowercasingFirstWord(_ text: String, keepCapitalized: [String]) -> String {
        guard let start = text.firstIndex(where: \.isLetter) else { return text }
        let end = text[start...].firstIndex(where: { !$0.isLetter && $0 != "'" && $0 != "’" }) ?? text.endIndex
        let word = text[start..<end]
        let letters = Array(word.filter(\.isLetter))
        let restIsLower = letters.dropFirst().allSatisfy { !$0.isUppercase }
        guard letters.first?.isUppercase == true, restIsLower, letters.count > 1 || word.lowercased() != "i" else { return text }
        let base = word.split(whereSeparator: { $0 == "'" || $0 == "’" }).first.map(String.init) ?? String(word)
        if base == "I" { return text }
        if keepCapitalized.contains(where: { $0.caseInsensitiveCompare(base) == .orderedSame && $0.first?.isUppercase == true }) {
            return text
        }
        return String(text[..<start]) + word.prefix(1).lowercased() + word.dropFirst() + text[end...]
    }
}
