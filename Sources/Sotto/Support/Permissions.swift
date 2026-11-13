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
        // Accessibility also lets an app watch keys, and once it's on macOS
        // doesn't list the app under Input Monitoring at all; that preflight
        // only turns true after a relaunch, so setup would get stuck on it.
        case .inputMonitoring: CGPreflightListenEventAccess() || AXIsProcessTrusted()
        }
    }

    static var missing: [Permission] { allCases.filter { !$0.isGranted } }

    /// Accessibility was just allowed, but macOS only delivers key events to
    /// this process after it restarts, so the dictation key wouldn't work yet.
    static var keyAccessNeedsRelaunch: Bool { AXIsProcessTrusted() && !CGPreflightListenEventAccess() }

    /// Restarts Sotto and reopens the setup window, so "Try it" works right away.
    static func relaunchToContinueSetup() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this copy to quit, then open the same app again.
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\" --args --continue-setup", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
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
