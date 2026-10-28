import AppKit
import SottoCore
import SwiftUI

/// The menu bar icon and its menu. The menu is rebuilt when it opens, so
/// nothing updates it in the background.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let controller: DictationController
    private let menu = NSMenu()
    var openSettings: (() -> Void)?
    var openSetup: (() -> Void)?
    var openHistory: (() -> Void)?
    var openFileTranscription: (() -> Void)?

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
        menu.addItem(MenuViews.item(MenuHeaderView(status: controller.statusText, dot: statusDot)))
        menu.addItem(.separator())

        if let last = controller.last {
            let lastItem = MenuViews.item(LastDictationView(text: last.text, detail: detail(for: last)))
            lastItem.toolTip = last.breakdown
            menu.addItem(lastItem)
            menu.addItem(action("Copy Last Transcript", key: "c", #selector(copyLast)))
            menu.addItem(.separator())
        }

        menu.addItem(microphoneMenu())
        let model = MenuViews.valueItem("Model", value: "Parakeet v3")
        let models = NSMenu()
        let parakeet = NSMenuItem(title: "Parakeet TDT 0.6B v3", action: nil, keyEquivalent: "")
        parakeet.state = .on
        models.addItem(parakeet)
        model.submenu = models
        menu.addItem(model)
        menu.addItem(pauseMenu())

        let missing = Permission.missing
        if !missing.isEmpty || !controller.isModelDownloaded {
            menu.addItem(.separator())
            menu.addItem(action("Finish Setting Up…", key: "", #selector(showSetup)))
        }

        menu.addItem(.separator())
        menu.addItem(action("History…", key: "y", #selector(showHistory)))
        menu.addItem(action("Transcribe a File…", key: "", #selector(showFileTranscription)))
        menu.addItem(action("Settings…", key: ",", #selector(showSettings)))
        menu.addItem(action("Quit Sotto", key: "q", #selector(quit)))
    }

    private var statusDot: Color {
        if controller.isPaused { return .gray }
        switch controller.status {
        case .listening: return .red
        case .needsSetup, .failed: return .orange
        case .starting, .downloading: return .gray
        case .ready: return controller.isPreparing ? .gray : .green
        }
    }

    /// "Inserted into Notes · 0:07 · just now"
    private func detail(for last: DictationController.LastDictation) -> String {
        var parts = [last.appName.map { "Inserted into \($0)" } ?? "Not pasted"]
        parts.append(String(format: "%d:%02d", Int(last.duration) / 60, Int(last.duration) % 60))
        let age = Date().timeIntervalSince(last.at)
        parts.append(age < 60 ? "just now" : RelativeDateTimeFormatter().localizedString(for: last.at, relativeTo: Date()))
        return parts.joined(separator: " · ")
    }

    private func microphoneMenu() -> NSMenuItem {
        let inputs = AudioDevices.inputs()
        let selected = controller.store.settings.microphoneUID
        let currentName = inputs.first { $0.id == selected }?.name ?? AudioDevices.defaultInputName() ?? "System Default"
        let entry = MenuViews.valueItem("Microphone", value: Self.shortName(currentName))
        let submenu = NSMenu()
        let systemTitle = AudioDevices.defaultInputName().map { "System Default (\($0))" } ?? "System Default"
        let system = action(systemTitle, key: "", #selector(chooseMicrophone(_:)))
        system.state = selected == nil ? .on : .off
        submenu.addItem(system)
        submenu.addItem(.separator())
        for input in inputs {
            let device = action(input.name, key: "", #selector(chooseMicrophone(_:)))
            device.representedObject = input.id
            device.state = selected == input.id ? .on : .off
            submenu.addItem(device)
        }
        entry.submenu = submenu
        return entry
    }

    /// "MacBook Pro Microphone" → "MacBook Pro", to fit the menu row.
    private static func shortName(_ name: String) -> String {
        name.hasSuffix(" Microphone") ? String(name.dropLast(" Microphone".count)) : name
    }

    private func pauseMenu() -> NSMenuItem {
        if controller.isPaused {
            return action("Resume Dictation", key: "", #selector(resume))
        }
        let entry = NSMenuItem(title: "Pause Dictation", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (title, minutes) in [("For 15 Minutes", 15), ("For 1 Hour", 60), ("Until I Resume", 0)] {
            let option = action(title, key: "", #selector(pause(_:)))
            option.tag = minutes
            submenu.addItem(option)
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

    @objc private func pause(_ sender: NSMenuItem) {
        controller.pause(minutes: sender.tag == 0 ? nil : sender.tag)
    }

    @objc private func resume() {
        controller.resume()
    }

    @objc private func showSettings() { openSettings?() }
    @objc private func showHistory() { openHistory?() }
    @objc private func showFileTranscription() { openFileTranscription?() }
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
