import AppKit

/// The menu bar icon and its menu. The menu is rebuilt when it opens, so
/// nothing updates it in the background.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let controller: DictationController
    private let menu = NSMenu()

    init(controller: DictationController) {
        self.controller = controller
        super.init()
        menu.delegate = self
        item.menu = menu
        refresh()
    }

    func refresh() {
        guard let button = item.button else { return }
        let (symbol, tint): (String, NSColor?) = switch controller.status {
        case .listening: ("waveform", .systemRed)
        case .needsSetup, .failed: ("waveform.badge.exclamationmark", nil)
        case .downloading, .starting: ("arrow.down.circle", nil)
        case .ready: ("waveform", nil)
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Sotto")
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = tint
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(disabled(controller.statusText))

        if let last = controller.lastTranscript {
            menu.addItem(.separator())
            menu.addItem(disabled("Last dictation"))
            let preview = last.count > 60 ? String(last.prefix(60)) + "…" : last
            menu.addItem(disabled("“\(preview)”"))
            if let timing = controller.lastTimingText {
                menu.addItem(disabled(timing))
            }
            menu.addItem(action("Copy Last Transcript", key: "c", #selector(copyLast)))
        }

        let missing = Permission.missing
        if !missing.isEmpty {
            menu.addItem(.separator())
            for permission in missing {
                let entry = action("Allow \(permission.title)…", key: "", #selector(requestPermission(_:)))
                entry.representedObject = permission.title
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        menu.addItem(action("Quit Sotto", key: "q", #selector(quit)))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    private func action(_ title: String, key: String, _ selector: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        entry.target = self
        return entry
    }

    @objc private func copyLast() {
        guard let last = controller.lastTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(last, forType: .string)
    }

    @objc private func requestPermission(_ sender: NSMenuItem) {
        guard let title = sender.representedObject as? String,
              let permission = Permission.allCases.first(where: { $0.title == title })
        else { return }
        Task { await permission.request() }
        controller.retrySetup()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
