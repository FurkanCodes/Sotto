import AppKit
import ApplicationServices
import SottoCore

/// Watches the text field Sotto just pasted into, for a short while, to
/// notice a word the user fixes by hand. Event-driven: macOS calls back when
/// the field's value changes. The field's text is only held in memory while
/// watching, and is never stored.
@MainActor
final class FieldWatcher {
    var onLearned: ((String) -> Void)?

    private static let watchFor: Duration = .seconds(20)
    private static let settleAfter: Duration = .milliseconds(1500)
    /// Very large documents aren't worth reading on every keystroke.
    private static let maxLength = 100_000

    private var observer: AXObserver?
    private var element: AXUIElement?
    private var baseline = ""
    private var inserted = ""
    private var known: [String] = []
    private var settleTask: Task<Void, Never>?
    private var endTask: Task<Void, Never>?

    /// Starts watching the focused field. Call once the inserted text has landed.
    func watch(inserted: String, knownWords: [String]) {
        stop()
        guard let element = Self.focusedElement(), !Self.isSecure(element),
              let value = Self.value(of: element), value.count <= Self.maxLength,
              // If the field doesn't show the dictated text, it can't be read reliably.
              value.contains(inserted.trimmingCharacters(in: .whitespaces).prefix(40))
        else { return }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, fieldChangedCallback, &created) == .success, let observer = created else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, context) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        self.observer = observer
        self.element = element
        self.baseline = value
        self.inserted = inserted
        self.known = knownWords
        endTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.watchFor)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        settleTask?.cancel()
        endTask?.cancel()
        if let observer, let element {
            AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        element = nil
        baseline = ""
    }

    fileprivate func valueChanged() {
        // Wait until the user stops typing, then compare once.
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.settleAfter)
            guard !Task.isCancelled, let self, let element = self.element,
                  let current = Self.value(of: element), current.count <= Self.maxLength
            else { return }
            if let word = CorrectionLearning.learnedWord(
                before: self.baseline, after: current, inserted: self.inserted, known: self.known
            ) {
                self.stop()
                self.onLearned?(word)
            }
        }
    }

    // MARK: - Accessibility

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        return (focused as! AXUIElement)
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        return (subrole as? String) == (kAXSecureTextFieldSubrole as String) || (role as? String) == "AXSecureTextField"
    }

    private static func value(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

private func fieldChangedCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let watcher = Unmanaged<FieldWatcher>.fromOpaque(context).takeUnretainedValue()
    // The observer's run loop source is on the main run loop.
    MainActor.assumeIsolated { watcher.valueChanged() }
}
