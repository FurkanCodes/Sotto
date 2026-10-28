import AppKit
import SottoCore
import UniformTypeIdentifiers

@MainActor
enum AppPicker {
    /// Asks the user to pick an app from /Applications.
    static func choose() -> AppRef? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return AppRef(bundleID: bundleID, name: name)
    }
}

/// Reads custom words from Handy's settings, if Handy is installed.
enum HandyImport {
    static func customWords() -> [String]? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let file = support.appendingPathComponent("com.pais.handy/settings_store.json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = json["settings"] as? [String: Any],
              let words = settings["custom_words"] as? [String]
        else { return nil }
        return words
    }
}
