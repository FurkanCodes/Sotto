import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: DictationController?
    private var statusMenu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = DictationController()
        let statusMenu = StatusMenu(controller: controller)
        controller.onChange = { [weak statusMenu] in statusMenu?.refresh() }
        self.controller = controller
        self.statusMenu = statusMenu
        controller.start()
    }
}
