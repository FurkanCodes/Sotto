import AppKit
import SottoCore

/// The menu bar icon and its menu. The menu is rebuilt when it opens, so
/// nothing updates it in the background.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let controller: DictationController
    private let menu = NSMenu()
    var openSettings: (() -> Void)?
    var openSetup: (() -> Void)?

    init(controller: DictationController) {
        self.controller = controller
        super.init()
        menu.delegate = self
        item.menu = menu
        refresh()
    }

    func refresh() {
        guard let button = item.button else { return }
        let state: StatusIcon.State
        if controller.isPaused {
            state = .paused
        } else {
            state = switch controller.status {
            case .listening: .listening
            case .needsSetup, .failed: .attention
            case .starting, .downloading: .busy
            case .ready: controller.isPreparing ? .busy : .ready
            }
        }
        button.image = StatusIcon.image(for: state)
        button.setAccessibilityLabel("Sotto, \(controller.statusText)")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(.sectionHeader(title: "Sotto"))
        menu.addItem(disabled(controller.statusText))

        if let last = controller.last {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Last dictation"))
            let preview = last.text.count > 70 ? String(last.text.prefix(70)) + "…" : last.text
            menu.addItem(disabled("“\(preview)”"))
            var details: [String] = []
            details.append(last.appName.map { "Inserted into \($0)" } ?? "Not pasted")
            details.append(String(format: "%d:%02d", Int(last.duration) / 60, Int(last.duration) % 60))
            if let ms = last.releaseToPasteMs { details.append("\(ms) ms") }
            let detailItem = disabled(details.joined(separator: " · "))
            detailItem.toolTip = last.breakdown
            menu.addItem(detailItem)
            menu.addItem(action("Copy Last Transcript", key: "c", #selector(copyLast)))
        }

        menu.addItem(.separator())
        menu.addItem(microphoneMenu())
        let model = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        let models = NSMenu()
        let parakeet = NSMenuItem(title: "Parakeet v3", action: nil, keyEquivalent: "")
        parakeet.state = .on
        models.addItem(parakeet)
        model.submenu = models
        menu.addItem(model)
        let pause = action("Pause Dictation", key: "", #selector(togglePause))
        pause.state = controller.isPaused ? .on : .off
        menu.addItem(pause)

        let missing = Permission.missing
        if !missing.isEmpty || !controller.isModelDownloaded {
            menu.addItem(.separator())
            menu.addItem(action("Finish Setting Up…", key: "", #selector(showSetup)))
        }

        menu.addItem(.separator())
        menu.addItem(action("Settings…", key: ",", #selector(showSettings)))
        menu.addItem(action("Quit Sotto", key: "q", #selector(quit)))
    }

    private func microphoneMenu() -> NSMenuItem {
        let entry = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let selected = controller.store.settings.microphoneUID
        let systemTitle = AudioDevices.defaultInputName().map { "System Default (\($0))" } ?? "System Default"
        let system = action(systemTitle, key: "", #selector(chooseMicrophone(_:)))
        system.state = selected == nil ? .on : .off
        submenu.addItem(system)
        submenu.addItem(.separator())
        for input in AudioDevices.inputs() {
            let device = action(input.name, key: "", #selector(chooseMicrophone(_:)))
            device.representedObject = input.id
            device.state = selected == input.id ? .on : .off
            submenu.addItem(device)
        }
        entry.submenu = submenu
        return entry
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
        guard let text = controller.last?.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func chooseMicrophone(_ sender: NSMenuItem) {
        controller.store.settings.microphoneUID = sender.representedObject as? String
    }

    @objc private func togglePause() {
        controller.isPaused.toggle()
    }

    @objc private func showSettings() { openSettings?() }
    @objc private func showSetup() { openSetup?() }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// The wavy-line menu bar icon from the design, drawn in code.
@MainActor
enum StatusIcon {
    enum State {
        case ready, listening, paused, attention, busy
    }

    static func image(for state: State) -> NSImage {
        let size = NSSize(width: 18, height: 14)
        let image = NSImage(size: size, flipped: true) { _ in
            let wave = NSBezierPath()
            wave.lineWidth = 1.6
            wave.lineCapStyle = .round
            wave.lineJoinStyle = .round
            switch state {
            case .paused:
                wave.move(to: NSPoint(x: 1.5, y: 7))
                wave.line(to: NSPoint(x: 16.5, y: 7))
            case .listening:
                wave.move(to: NSPoint(x: 1, y: 7))
                wave.curve(to: NSPoint(x: 5, y: 1.5), controlPoint1: NSPoint(x: 2.4, y: 7), controlPoint2: NSPoint(x: 3.2, y: 1.5))
                wave.curve(to: NSPoint(x: 9, y: 12.5), controlPoint1: NSPoint(x: 6.8, y: 1.5), controlPoint2: NSPoint(x: 7.2, y: 12.5))
                wave.curve(to: NSPoint(x: 13, y: 1.5), controlPoint1: NSPoint(x: 10.8, y: 12.5), controlPoint2: NSPoint(x: 11.2, y: 1.5))
                wave.curve(to: NSPoint(x: 17, y: 7), controlPoint1: NSPoint(x: 14.8, y: 1.5), controlPoint2: NSPoint(x: 15.6, y: 7))
            default:
                let width: CGFloat = state == .attention ? 12 : 17
                let scale = width / 16
                wave.move(to: NSPoint(x: 1, y: 7))
                wave.curve(to: NSPoint(x: 1 + 4 * scale, y: 3), controlPoint1: NSPoint(x: 1 + 1.6 * scale, y: 7), controlPoint2: NSPoint(x: 1 + 2.2 * scale, y: 3))
                wave.curve(to: NSPoint(x: 1 + 8 * scale, y: 11), controlPoint1: NSPoint(x: 1 + 5.8 * scale, y: 3), controlPoint2: NSPoint(x: 1 + 6.2 * scale, y: 11))
                wave.curve(to: NSPoint(x: 1 + 12 * scale, y: 3), controlPoint1: NSPoint(x: 1 + 9.8 * scale, y: 11), controlPoint2: NSPoint(x: 1 + 10.2 * scale, y: 3))
                wave.curve(to: NSPoint(x: 1 + 16 * scale, y: 7), controlPoint1: NSPoint(x: 1 + 13.8 * scale, y: 3), controlPoint2: NSPoint(x: 1 + 14.4 * scale, y: 7))
            }
            let ink: NSColor = state == .listening ? .systemRed : .labelColor
            ink.withAlphaComponent(state == .paused || state == .busy ? 0.5 : 1).setStroke()
            wave.stroke()
            if state == .attention {
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12.5, y: 0.5, width: 5, height: 5)).fill()
            }
            return true
        }
        // Plain states follow the menu bar's light or dark look; colored ones keep their color.
        image.isTemplate = state != .listening && state != .attention
        return image
    }
}
