import AppKit
import SwiftUI

/// Opens the Settings and first-run windows. Each window is built when it
/// opens and released when it closes, so neither costs memory while hidden.
@MainActor
final class Windows {
    private let controller: DictationController
    private var settings: NSWindow?
    private var setup: NSWindow?

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
