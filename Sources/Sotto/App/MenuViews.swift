import AppKit
import SwiftUI

/// Custom rows for the menu bar menu, drawn to match the design canvas.
/// Plain rows (Copy, Settings, Quit) stay native so they highlight and
/// handle keyboard navigation like any macOS menu.
@MainActor
enum MenuViews {
    static let width: CGFloat = 300

    static func item(_ view: some View) -> NSMenuItem {
        let hosting = NSHostingView(rootView: view.frame(width: width, alignment: .leading))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let item = NSMenuItem()
        item.view = hosting
        return item
    }

    /// A native row with a secondary value aligned to the right: "Model     Parakeet v3".
    static func valueItem(_ title: String, value: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: width - 64)]
        let font = NSFont.menuFont(ofSize: 0)
        let text = NSMutableAttributedString(string: "\(title)\t", attributes: [.font: font, .paragraphStyle: style])
        text.append(NSAttributedString(
            string: value,
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style]
        ))
        item.attributedTitle = text
        return item
    }
}

struct MenuHeaderView: View {
    let status: String
    let dot: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sotto").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(status).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }
}

struct LastDictationView: View {
    let text: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last dictation").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text("“\(text)”")
                .font(.system(size: 13))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
