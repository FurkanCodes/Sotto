import AppKit
import Carbon.HIToolbox
import SottoCore

/// Watches the dictation key with a listen-only event tap on the main run
/// loop. It wakes only when a key event arrives; nothing polls.
///
/// The key is a single modifier (right Option, right Command or Fn).
/// Modifier changes still reach event taps while Secure Input is on
/// (password fields), so a modifier-only key keeps working there, unlike key
/// combos (Handy #1578).
@MainActor
final class HotkeyMonitor {
    enum Signal: Sendable {
        case down, up
        /// Another key was pressed while the dictation key was held.
        case chord
        case escape
    }

    var onSignal: ((Signal, TimeInterval) -> Void)?
    var isRunning: Bool { tap != nil }

    var key = DictationKey.rightOption {
        didSet { isHeld = false }
    }
    /// A mouse button that acts like the dictation key (CGEvent numbering:
    /// 2 middle, 3 back, 4 forward), or nil.
    var mouseButton: Int?

    private var tap: CFMachPort?
    private(set) var isHeld = false {
        didSet {
            if !isHeld {
                for waiter in releaseWaiters { waiter.resume() }
                releaseWaiters = []
            }
        }
    }
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    /// Returns once the dictation key is up, or after `limit`. Pasting
    /// while it's still down would add its modifier to Cmd+V.
    func waitForRelease(limit: Duration = .seconds(1)) async {
        guard isHeld else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: limit)
                guard let self else { return }
                for waiter in self.releaseWaiters { waiter.resume() }
                self.releaseWaiters = []
            }
        }
    }

    private var keyCode: Int64 {
        switch key {
        case .rightOption: Int64(kVK_RightOption)
        case .rightCommand: Int64(kVK_RightCommand)
        case .fn: Int64(kVK_Function)
        }
    }

    /// The flag bit that is set while this particular key is down.
    private var downBit: UInt64 {
        switch key {
        case .rightOption: 0x40 // NX_DEVICERALTKEYMASK
        case .rightCommand: 0x10 // NX_DEVICERCMDKEYMASK
        case .fn: CGEventFlags.maskSecondaryFn.rawValue
        }
    }

    /// Fails until Input Monitoring is granted.
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    fileprivate func handle(type: CGEventType, keyCode: Int64, flags: UInt64, mouseButton: Int64) {
        let now = ProcessInfo.processInfo.systemUptime
        switch type {
        case .otherMouseDown, .otherMouseUp:
            guard let button = self.mouseButton, Int64(button) == mouseButton else { return }
            let down = type == .otherMouseDown
            guard down != isHeld else { return }
            isHeld = down
            onSignal?(down ? .down : .up, now)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            guard keyCode == self.keyCode else { return }
            let down = flags & downBit != 0
            guard down != isHeld else { return }
            isHeld = down
            onSignal?(down ? .down : .up, now)
        case .keyDown:
            if keyCode == Int64(kVK_Escape) {
                onSignal?(.escape, now)
            } else if isHeld {
                onSignal?(.chord, now)
            }
        default:
            break
        }
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags.rawValue
    let mouseButton = event.getIntegerValueField(.mouseEventButtonNumber)
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    // The tap's run loop source is on the main run loop.
    MainActor.assumeIsolated {
        monitor.handle(type: type, keyCode: keyCode, flags: flags, mouseButton: mouseButton)
    }
    return Unmanaged.passUnretained(event)
}
