import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var signalingServer: SignalingServer?
    private var screenCaptureService: ScreenCaptureService?
    private var webRTCManager: WebRTCManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        startServices()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Screen2Screen")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Status: Ready", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func startServices() {
        // Services will be initialized in subsequent tasks
        print("Screen2Screen Host starting...")
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
