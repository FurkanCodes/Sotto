import AppKit
import SwiftUI

/// Opens the Settings and first-run windows. Each window is built when it
/// opens and released when it closes, so neither costs memory while hidden.
@MainActor
final class Windows {
    private let controller: DictationController
    private var settings: NSWindow?
    /// Kept outside the window so the menu can open Settings on a given pane.
    private let settingsNavigation = SettingsNavigation()
    private var setup: NSWindow?
    private var history: NSWindow?
    private var fileTranscription: NSWindow?

    init(controller: DictationController) {
        self.controller = controller
    }

    func showSettings(pane: SettingsView.Pane? = nil) {
        if let pane { settingsNavigation.pane = pane }
        if settings == nil {
            settings = makeWindow(
                title: "Sotto Settings",
                root: SettingsView(controller: controller, navigation: settingsNavigation),
                style: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            ) { [weak self] in self?.settings = nil }
            settings?.setContentSize(NSSize(width: 820, height: 580))
        }
        present(settings)
    }

    var isSettingUp: Bool { setup != nil }

    func showSetup() {
        if setup == nil {
            var view = SetupView(controller: controller) { [weak self] in self?.setup?.close() }
            view.bringToFront = { [weak self] in self?.present(self?.setup) }
            setup = makeWindow(
                title: "Set Up Sotto",
                root: view,
                style: [.titled, .closable, .fullSizeContentView]
            ) { [weak self] in
                self?.setup = nil
                // Back to a menu bar app with no Dock icon.
                NSApp.setActivationPolicy(.accessory)
            }
            setup?.titlebarAppearsTransparent = true
        }
        // A Dock icon while setting up, so the window can always be found again
        // behind System Settings (a menu bar app has none, and isn't in ⌘-Tab).
        NSApp.setActivationPolicy(.regular)
        present(setup)
    }

    func showHistory() {
        if history == nil {
            history = makeWindow(
                title: "Sotto History",
                root: HistoryView(history: controller.history, retentionDays: controller.store.settings.historyRetentionDays),
                style: [.titled, .closable, .miniaturizable, .resizable]
            ) { [weak self] in self?.history = nil }
            history?.setContentSize(NSSize(width: 620, height: 640))
        }
        present(history)
    }

    func showFileTranscription() {
        if fileTranscription == nil {
            fileTranscription = makeWindow(
                title: "Transcribe a File",
                root: FileTranscriptionView(controller: controller),
                style: [.titled, .closable, .miniaturizable, .resizable]
            ) { [weak self] in self?.fileTranscription = nil }
        }
        present(fileTranscription)
    }

    private func makeWindow(title: String, root: some View, style: NSWindow.StyleMask, onClose: @escaping @MainActor () -> Void) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = title
        window.styleMask = style
        window.isReleasedWhenClosed = false
        window.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { onClose() }
        }
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // A menu bar app opened from Terminal or a script isn't always made
        // active, so bring the window to the front on its own as well.
        window.orderFrontRegardless()
    }
}
