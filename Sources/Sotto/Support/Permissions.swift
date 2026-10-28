import AppKit
import ApplicationServices
import AVFoundation

/// The three permissions dictation needs. The listen-only event tap that
/// watches the dictation key needs Input Monitoring.
@MainActor
enum Permission: CaseIterable {
    case microphone, accessibility, inputMonitoring

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    var isGranted: Bool {
        switch self {
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility: AXIsProcessTrusted()
        case .inputMonitoring: CGPreflightListenEventAccess()
        }
    }

    static var missing: [Permission] { allCases.filter { !$0.isGranted } }

    /// The first-launch prompts, all at once. Doesn't open System Settings;
    /// the menu offers that for anything still missing.
    static func promptMissing() async {
        if !Permission.inputMonitoring.isGranted { _ = CGRequestListenEventAccess() }
        if !Permission.accessibility.isGranted {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
    }

    /// Shows the system prompt the first time; after that macOS won't prompt
    /// again, so this opens the right System Settings pane instead.
    func request() async {
        switch self {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            } else {
                openSettings()
            }
        case .accessibility:
            // The literal key avoids the non-Sendable global kAXTrustedCheckOptionPrompt.
            if !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
                openSettings()
            }
        case .inputMonitoring:
            if !CGRequestListenEventAccess() {
                openSettings()
            }
        }
    }

    func openSettings() {
        let anchor = switch self {
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
