import AppKit
import SwiftUI

/// Opens the Settings and first-run windows. Each window is built when it
/// opens and released when it closes, so neither costs memory while hidden.
@MainActor
final class Windows {
    private let controller: DictationController
    private var settings: NSWindow?
    private var setup: NSWindow?
    private var history: NSWindow?
    private var fileTranscription: NSWindow?

    init(controller: DictationController) {
        self.controller = controller
    }

    func showSettings() {
        if settings == nil {
            settings = makeWindow(
                title: "Sotto Settings",
                root: SettingsView(controller: controller),
                style: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            ) { [weak self] in self?.settings = nil }
            settings?.setContentSize(NSSize(width: 820, height: 580))
        }
        present(settings)
    }

    func showSetup() {
        if setup == nil {
            setup = makeWindow(
                title: "Set Up Sotto",
                root: SetupView(controller: controller) { [weak self] in self?.setup?.close() },
                style: [.titled, .closable, .fullSizeContentView]
            ) { [weak self] in self?.setup = nil }
            setup?.titlebarAppearsTransparent = true
        }
        present(setup)
    }

    func showHistory() {
        if history == nil {
            history = makeWindow(
                title: "Sotto History",
                root: HistoryView(history: controller.history, retentionDays: controller.store.settings.historyRetentionDays),
                style: [.titled, .closable, .miniaturizable, .resizable]
            ) { [weak self] in self?.history = nil }
            history?.setContentSize(NSSize(width: 640, height: 600))
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
    }
}
