import Foundation

public enum DictationKey: String, Codable, CaseIterable, Sendable {
    case rightOption, rightCommand, fn
}

public enum PillPosition: String, Codable, CaseIterable, Sendable {
    case bottom, top
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
