import AppKit
import SottoCore
import SwiftUI

enum PillState: Equatable {
    case hidden
    case gettingReady
    case listening(latched: Bool, since: Date)
    case transcribing
    case loadingModel
    case message(String, isError: Bool)
}

@Observable @MainActor
final class PillModel {
    var state: PillState = .hidden
    var keySymbol = "⌥"
    /// Recent mic levels, oldest first, each 0...1.
    var levels: [Float] = Array(repeating: 0, count: PillModel.barCount)
    static let barCount = 9

    func push(level rms: Float) {
        // Map roughly -50...-12 dBFS onto 0...1.
        let decibels = 20 * log10(max(rms, 1e-6))
        let normalized = min(1, max(0, (decibels + 50) / 38))
        levels.removeFirst()
        levels.append(normalized)
    }
}

/// The floating pill. One non-activating panel, created once and ordered out
/// when hidden, so nothing renders between dictations.
@MainActor
final class PillController {
    var position = PillPosition.bottom
    var keySymbol: String {
        get { model.keySymbol }
        set { model.keySymbol = newValue }
    }

    private let panel: NSPanel
    private let model = PillModel()
    private var messageGeneration = 0
    private static let size = NSSize(width: 360, height: 72)

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PillView(model: model))
    }

    func show(_ state: PillState) {
        guard model.state != state else { return }
        messageGeneration += 1
        model.state = state
        if !Self.isListening(state) {
            model.levels = Array(repeating: 0, count: PillModel.barCount)
        }
        if !panel.isVisible {
            position(on: NSScreen.main ?? NSScreen.screens.first)
            panel.orderFrontRegardless()
        }
    }

    /// Shows a message, then hides after a moment unless something newer is shown.
    func flash(_ text: String, isError: Bool) {
        show(.message(text, isError: isError))
        let generation = messageGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(isError ? 3 : 1.4))
            guard let self, self.messageGeneration == generation else { return }
            self.hide()
        }
    }

    func hide() {
        messageGeneration += 1
        model.state = .hidden
        panel.orderOut(nil)
    }

    func push(level: Float) {
        model.push(level: level)
    }

    private static func isListening(_ state: PillState) -> Bool {
        if case .listening = state { return true }
        return state == .gettingReady
    }

    private func position(on screen: NSScreen?) {
        guard let frame = screen?.visibleFrame else { return }
        let x = frame.midX - Self.size.width / 2
        let y = position == .bottom ? frame.minY + 20 : frame.maxY - Self.size.height - 12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
