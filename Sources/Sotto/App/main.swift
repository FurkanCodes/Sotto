import AppKit

HeadlessCheck.runIfRequested()

// LSUIElement in Info.plist makes Sotto a menu bar app before the run loop
// starts. Switching the activation policy at runtime leaves a Dock icon on
// macOS 26 (Handy #1787).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
