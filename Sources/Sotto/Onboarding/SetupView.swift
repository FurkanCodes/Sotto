import SottoCore
import SwiftUI

/// The first-run window: three permissions and the model download, with a
/// box to try dictation before finishing. Permission status is re-read once
/// a second while this window is open, and never otherwise.
struct SetupView: View {
    let controller: DictationController
    let close: () -> Void
    @State private var tryText = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            content
        }
    }

    private var modelDone: Bool { controller.isModelDownloaded && !controller.isPreparing }
    private var allDone: Bool { Permission.missing.isEmpty && modelDone }
    /// The first permission still missing. Only its button is blue, as in the design.
    private var currentPermission: Permission? { Permission.allCases.first { !$0.isGranted } }

    private var content: some View {
        let key = controller.store.settings.dictationKey
        return VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Sotto").font(.system(size: 34, weight: .semibold))
                Text("Three permissions and one download, then you're dictating. Nothing you say leaves this Mac.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 0) {
                permissionRow(1, .microphone, "So Sotto can hear you. Used only while you dictate.")
                Divider()
                permissionRow(2, .accessibility, "So Sotto can type the text into the app you're using.")
                Divider()
                permissionRow(3, .inputMonitoring, "So Sotto can tell when you hold \(key.title). It reads no other keys.")
                Divider()
                modelRow
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))

            VStack(alignment: .leading, spacing: 8) {
                Text("Try it").font(.headline)
                TextField("Click here, hold \(key.symbol) and say something", text: $tryText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .lineLimit(2...4)
            }

            HStack {
                Spacer()
                Button("Set Up Later", action: close)
                Button("Finish Setup") {
                    controller.store.settings.completedSetup = true
                    close()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!allDone)
            }
        }
        .padding(32)
        .frame(width: 640)
    }

    private func permissionRow(_ number: Int, _ permission: Permission, _ detail: String) -> some View {
        StepRow(number: number, title: permission.title, detail: detail, done: permission.isGranted) {
            if permission.isGranted {
                Text("Allowed").font(.callout.weight(.semibold)).foregroundStyle(.green)
            } else if permission == currentPermission {
                Button("Open System Settings") { open(permission) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Open System Settings") { open(permission) }
            }
        }
    }

    private func open(_ permission: Permission) {
        Task { await permission.request() }
        controller.retrySetup()
    }

    private var modelRow: some View {
        StepRow(number: 4, title: "Speech model", detail: "Parakeet v3. Downloads once, then works offline.", done: modelDone) {
            switch controller.status {
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 120)
                Text("\(Int(fraction * 100))%").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            case .failed:
                Text("Download failed").font(.callout).foregroundStyle(.orange)
            default:
                if controller.isPreparing {
                    ProgressView().controlSize(.small)
                    Text("Preparing").font(.callout).foregroundStyle(.secondary)
                } else if modelDone {
                    Text("Ready").font(.callout.weight(.semibold)).foregroundStyle(.green)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }
}

private struct StepRow<Trailing: View>: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().strokeBorder(done ? Color.green : Color.secondary.opacity(0.5), lineWidth: 1.5)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.green)
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) { trailing }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not done")
    }
}
