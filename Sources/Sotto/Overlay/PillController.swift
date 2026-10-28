import AppKit
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
    private let panel: NSPanel
    private let model = PillModel()
    private var messageGeneration = 0
    private static let size = NSSize(width: 280, height: 64)

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
        if case .listening = state {} else if case .gettingReady = state {} else {
            model.levels = Array(repeating: 0, count: PillModel.barCount)
        }
        if !panel.isVisible {
            position()
            panel.orderFrontRegardless()
        }
    }

    /// Shows a message, then hides after a moment unless something newer is shown.
    func flash(_ text: String, isError: Bool) {
        show(.message(text, isError: isError))
        let generation = messageGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(isError ? 2.5 : 1.2))
            guard let self, self.messageGeneration == generation else { return }
            self.hide()
        }
    }

    func hide() {
        messageGeneration += 1
        model.state = .hidden
        panel.orderOut(nil)
    }

    var isShowingMessage: Bool {
        if case .message = model.state { return true }
        return false
    }

    func push(level: Float) {
        model.push(level: level)
    }

    private func position() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 24))
    }
}
