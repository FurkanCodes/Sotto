import AppKit
import SottoCore
import SwiftUI

/// "Add Furkan to your dictionary?" A small glass prompt where the pill
/// sits. It takes clicks without taking focus from the app you're typing
/// in, and goes away on its own after 10 seconds.
@MainActor
final class SuggestionPanel {
    private let panel: NSPanel
    private var dismissTask: Task<Void, Never>?
    private static let size = NSSize(width: 460, height: 70)

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
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
    }

    func offer(_ word: String, position: PillPosition, add: @escaping () -> Void) {
        let view = SuggestionView(word: word) { [weak self] accepted in
            if accepted { add() }
            self?.hide()
        }
        panel.contentView = FirstClickHostingView(rootView: view)
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            let y = position == .bottom ? frame.minY + 20 : frame.maxY - Self.size.height - 12
            panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: y))
        }
        panel.orderFrontRegardless()
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        dismissTask?.cancel()
        panel.orderOut(nil)
        panel.contentView = nil
    }
}

/// Buttons respond to the first click, without the window having to be
/// activated first.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct SuggestionView: View {
    let word: String
    let answer: (Bool) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed").foregroundStyle(.secondary)
            Text("Add \(Text(word).bold()) to your dictionary?")
                .font(.system(size: 13))
                .lineLimit(1)
            Button("Add") { answer(true) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button {
                answer(false)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Not now")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background {
            if reduceTransparency {
                Capsule().fill(Color(nsColor: .windowBackgroundColor))
            }
        }
        .modifier(GlassIfAllowed(enabled: !reduceTransparency))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GlassIfAllowed: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
        }
    }
}
