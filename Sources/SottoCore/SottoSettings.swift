import Foundation

public enum DictationKey: String, Codable, CaseIterable, Sendable {
    case rightOption, rightCommand, fn
}

public enum PillPosition: String, Codable, CaseIterable, Sendable {
    case bottom, top
}

/// An app picked by the user, remembered by bundle identifier.
public struct AppRef: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID }
    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// Press Return (or ⌘Return) after inserting text into this app.
public struct AutoSendRule: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var app: AppRef
    public var withCommand: Bool
    public var id: String { app.bundleID }
    public init(app: AppRef, withCommand: Bool = false) {
        self.app = app
        self.withCommand = withCommand
    }
}

/// Everything the user can change. Stored as JSON and read once at launch.
///
/// Decoding never fails as a whole: a missing, renamed or damaged field falls
/// back to its default, so one bad value can't reset everything (Handy
/// #1619). New fields are only ever added, never renamed or removed.
public struct SottoSettings: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version = SottoSettings.currentVersion
    public var dictationKey = DictationKey.rightOption
    /// A tap shorter than 300 ms keeps listening until the next press.
    public var tapToKeepListening = true
    public var removeFillerWords = true
    public var showPill = true
    public var pillPosition = PillPosition.bottom
    public var playSounds = false
    /// CoreAudio device UID; nil follows the system default input.
    public var microphoneUID: String?
    /// 0 keeps the model loaded.
    public var unloadAfterMinutes = 5
    public var customWords: [String] = []
    public var completedSetup = false
    /// Days of history to keep: 0 keeps none, -1 keeps everything.
    public var historyRetentionDays = 7
    /// Ending a dictation with "send it" presses Return after inserting.
    public var sayToSend = true
    public var autoSendApps: [AutoSendRule] = []
    public var replacements: [Replacement] = []
    public var snippets: [Snippet] = []
    /// Lowers other apps' audio while recording.
    public var lowerOtherAudio = false
    /// A mouse button that works like the dictation key (CGEvent button
    /// number: 2 middle, 3 back, 4 forward); nil for none.
    public var mouseButton: Int?
    /// Apps where the dictation key does nothing.
    public var skipApps: [AppRef] = []
    /// Shows the transcribed text in the pill while dictating.
    public var showLiveText = true
    /// Shapes capitalization and punctuation for the app the text goes into.
    public var matchStyleToApp = true
    /// The user's per-app styles, overriding the built-in defaults.
    public var styleRules: [StyleRule] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SottoSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        version = value(.version, defaults.version)
        dictationKey = value(.dictationKey, defaults.dictationKey)
        tapToKeepListening = value(.tapToKeepListening, defaults.tapToKeepListening)
        removeFillerWords = value(.removeFillerWords, defaults.removeFillerWords)
        showPill = value(.showPill, defaults.showPill)
        pillPosition = value(.pillPosition, defaults.pillPosition)
        playSounds = value(.playSounds, defaults.playSounds)
        microphoneUID = value(.microphoneUID, defaults.microphoneUID)
        unloadAfterMinutes = max(0, value(.unloadAfterMinutes, defaults.unloadAfterMinutes))
        customWords = value(.customWords, defaults.customWords)
        completedSetup = value(.completedSetup, defaults.completedSetup)
        historyRetentionDays = value(.historyRetentionDays, defaults.historyRetentionDays)
        sayToSend = value(.sayToSend, defaults.sayToSend)
        autoSendApps = value(.autoSendApps, defaults.autoSendApps)
        replacements = value(.replacements, defaults.replacements)
        snippets = value(.snippets, defaults.snippets)
        lowerOtherAudio = value(.lowerOtherAudio, defaults.lowerOtherAudio)
        mouseButton = value(.mouseButton, defaults.mouseButton)
        skipApps = value(.skipApps, defaults.skipApps)
        showLiveText = value(.showLiveText, defaults.showLiveText)
        matchStyleToApp = value(.matchStyleToApp, defaults.matchStyleToApp)
        styleRules = value(.styleRules, defaults.styleRules)
    }

    /// Decodes settings, falling back to defaults if the data isn't JSON at all.
    public static func decode(_ data: Data) -> SottoSettings {
        (try? JSONDecoder().decode(SottoSettings.self, from: data)) ?? SottoSettings()
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
