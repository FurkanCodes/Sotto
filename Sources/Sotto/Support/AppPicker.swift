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
