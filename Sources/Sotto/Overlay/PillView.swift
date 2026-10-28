import SwiftUI

/// The pill, in the states from the design canvas.
struct PillView: View {
    let model: PillModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if model.state != .hidden {
                content
                    .padding(.leading, 16)
                    .padding(.trailing, 18)
                    .frame(height: 46)
                    .modifier(PillBackground(reduceTransparency: reduceTransparency))
                    .shadow(color: .black.opacity(reduceTransparency ? 0.15 : 0), radius: 8, y: 3)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.85), value: model.state)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .hidden:
            EmptyView()

        case .gettingReady:
            HStack(spacing: 10) {
                Spinner()
                Bars(levels: model.levels, reduceMotion: reduceMotion).opacity(0.3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Getting ready")

        case .listening(let latched, let since):
            HStack(spacing: 11) {
                if latched {
                    Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold))
                } else {
                    Circle().fill(.red).frame(width: 8, height: 8)
                }
                Bars(levels: model.levels, reduceMotion: reduceMotion)
                if latched {
                    Text("\(model.keySymbol) to stop")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                } else {
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        Text(Self.elapsed(from: since, to: context.date))
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(latched ? "Listening hands-free" : "Listening")

        case .transcribing:
            HStack(spacing: 9) {
                Dots(reduceMotion: reduceMotion)
                Text("Transcribing").font(.system(size: 13, weight: .medium))
            }

        case .loadingModel:
            HStack(spacing: 9) {
                Spinner()
                Text("Loading model").font(.system(size: 13, weight: .medium))
            }

        case .message(let text, let isError):
            HStack(spacing: 8) {
                if isError {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(text).font(.system(size: 13, weight: .medium)).lineLimit(1)
            }
        }
    }

    private static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct Bars: View {
    let levels: [Float]
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(.primary)
                    .frame(width: 3, height: 6 + 22 * CGFloat(level))
            }
        }
        .frame(height: 28)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }
}

private struct Dots: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 3
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(.primary)
                        .frame(width: 5, height: 5)
                        .opacity(reduceMotion ? 0.6 : 0.25 + 0.75 * max(0, sin(phase - Double(index) * 0.8)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct Spinner: View {
    var body: some View {
        ProgressView().controlSize(.small).accessibilityHidden(true)
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
