import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: DictationController?
    private var statusMenu: StatusMenu?
    private var windows: Windows?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = SettingsStore()
        let controller = DictationController(store: store)
        let statusMenu = StatusMenu(controller: controller)
        let windows = Windows(controller: controller)
        controller.onChange = { [weak statusMenu] in statusMenu?.refresh() }
        statusMenu.openSettings = { [weak windows] in windows?.showSettings() }
        statusMenu.openSetup = { [weak windows] in windows?.showSetup() }
        self.controller = controller
        self.statusMenu = statusMenu
        self.windows = windows
        controller.start()
        if !store.settings.completedSetup {
            if Permission.missing.isEmpty, controller.isModelDownloaded {
                // Already set up before the first-run window existed.
                store.settings.completedSetup = true
            } else {
                windows.showSetup()
            }
        }
    }

    /// Opening Sotto again while it runs (from Finder or Spotlight) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        windows?.showSettings()
        return true
    }
}
