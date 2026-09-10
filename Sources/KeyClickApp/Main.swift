import AppKit

@main
@MainActor
struct KeyClickMain {
    static func main() {
        guard SingleInstance.acquire() else {
            DistributedNotificationCenter.default().post(name: keyClickShowSettingsNotification, object: nil)
            return
        }
        let app = NSApplication.shared
        // The Dock/Desktop icon must reliably reopen the settings window.
        app.setActivationPolicy(.regular)
        let delegate = KeyClickAppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class KeyClickAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.launch()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Clicking KeyClick in the Dock is deliberately a control-panel action,
        // never a way to leave an armed overlay behind another application.
        controller.hostApplicationBecameActive()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.openSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
