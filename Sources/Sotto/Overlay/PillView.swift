import SwiftUI

/// The basic Phase 1 pill. The full design (every state, icons, motion) comes
/// in Phase 3 from the design canvas.
struct PillView: View {
    let model: PillModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if model.state != .hidden {
                content
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .modifier(PillBackground(reduceTransparency: reduceTransparency))
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: model.state)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .hidden:
            EmptyView()
        case .gettingReady:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                bars.opacity(0.3)
            }
            .accessibilityLabel("Getting ready")
        case .listening(let latched, let since):
            HStack(spacing: 10) {
                if latched {
                    Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold))
                } else {
                    Circle().fill(.red).frame(width: 8, height: 8)
                }
                bars
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(Self.elapsed(from: since, to: context.date))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(latched ? "Listening hands-free" : "Listening")
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Transcribing").font(.system(size: 13, weight: .medium))
            }
        case .loadingModel:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading model").font(.system(size: 13, weight: .medium))
            }
        case .message(let text, let isError):
            HStack(spacing: 8) {
                if isError {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Text(text).font(.system(size: 13, weight: .medium)).lineLimit(1)
            }
        }
    }

    private var bars: some View {
        HStack(spacing: 3) {
            ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(.primary)
                    .frame(width: 3, height: 6 + 20 * CGFloat(level))
            }
        }
        .frame(height: 26)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: model.levels)
        .accessibilityHidden(true)
    }

    private static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct PillBackground: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
        } else {
            content.glassEffect(.regular, in: Capsule())
        }
    }
}
