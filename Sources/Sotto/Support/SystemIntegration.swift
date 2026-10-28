import AppKit
import ServiceManagement
import SottoCore

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Short system sounds for start and stop, loaded once.
@MainActor
enum Sounds {
    private static let start = NSSound(named: "Tink")
    private static let stop = NSSound(named: "Pop")

    static func playStart() { play(start) }
    static func playStop() { play(stop) }

    private static func play(_ sound: NSSound?) {
        sound?.stop()
        sound?.play()
    }
}

extension DictationKey {
    var title: String {
        switch self {
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        case .fn: "Fn (Globe)"
        }
    }

    /// How the key appears on its keycap in Settings.
    var keycapLabel: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .rightCommand: "Right ⌘"
        case .fn: "fn 🌐"
        }
    }

    var symbol: String {
        switch self {
        case .rightOption: "⌥"
        case .rightCommand: "⌘"
        case .fn: "fn"
        }
    }
}
