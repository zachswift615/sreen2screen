import Cocoa
import Shared
import CoreMedia
import ScreenCaptureKit
import LiveKitWebRTC

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!

    override init() {
        super.init()
        print("AppDelegate: init called")
    }

    // Note: BonjourAdvertiser removed - SignalingServer handles Bonjour advertising
    private var signalingServer: SignalingServer?
    private var screenCaptureService: ScreenCaptureService?
    private var webRTCManager: WebRTCManager?
    private var inputController: InputController?

    private var isConnected = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("AppDelegate: applicationDidFinishLaunching called")
        setupStatusBar()
        Task {
            await startServices()
        }
    }

    private func setupStatusBar() {
        print("AppDelegate: Setting up status bar")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        print("AppDelegate: Status item created: \(statusItem != nil)")

        if let button = statusItem.button {
            // Try system symbol first, fall back to title if unavailable
            if let image = NSImage(systemSymbolName: "display", accessibilityDescription: "Screen2Screen") {
                button.image = image
                print("AppDelegate: Button image set")
            } else {
                button.title = "S2S"
                print("AppDelegate: Using text fallback")
            }
        } else {
            print("AppDelegate: WARNING - statusItem.button is nil!")
        }

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Status: Starting...", action: nil, keyEquivalent: "")
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())

        // Display selector submenu
        let displayMenu = NSMenu()
        let displayMenuItem = NSMenuItem(title: "Select Display", action: nil, keyEquivalent: "")
        displayMenuItem.submenu = displayMenu
        menu.addItem(displayMenuItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func startServices() async {
        // Initialize services
        inputController = InputController()
        screenCaptureService = ScreenCaptureService()
        screenCaptureService?.delegate = self

        // Request screen capture permission and load displays
        do {
            try await screenCaptureService?.requestPermissionAndLoadDisplays()
            updateDisplayMenu()

            // Set initial target display for InputController (defaults to main display)
            if let mainScreen = NSScreen.main {
                inputController?.setTargetDisplay(mainScreen)
            }
        } catch {
            updateStatus("Permission denied")
            print("Screen capture permission error: \(error)")
            return
        }

        // Start signaling server
        signalingServer = SignalingServer()
        signalingServer?.delegate = self
        do {
            try signalingServer?.start()
        } catch {
            updateStatus("Server failed")
            print("Signaling server error: \(error)")
            return
        }

        // Note: Bonjour advertising is handled by SignalingServer's listener.service

        // WebRTC manager
        webRTCManager = WebRTCManager()
        webRTCManager?.delegate = self

        updateStatus("Ready - Waiting for connection")
    }

    private func updateDisplayMenu() {
        guard let menu = statusItem.menu,
              let displayMenuItem = menu.items.first(where: { $0.title == "Select Display" }),
              let displayMenu = displayMenuItem.submenu else { return }

        displayMenu.removeAllItems()

        for display in screenCaptureService?.availableDisplays ?? [] {
            let item = NSMenuItem(
                title: "Display \(display.displayID) (\(display.width)x\(display.height))",
                action: #selector(selectDisplay(_:)),
                keyEquivalent: ""
            )
            item.representedObject = display
            item.target = self
            displayMenu.addItem(item)
        }
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        guard let display = sender.representedObject as? SCDisplay else { return }
        screenCaptureService?.selectDisplay(display)

        // Find the NSScreen corresponding to this display and update InputController
        if let screen = NSScreen.screens.first(where: { screen in
            // NSScreen's deviceDescription contains the display ID
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return false
            }
            return screenNumber == display.displayID
        }) {
            inputController?.setTargetDisplay(screen)
        }

        print("Selected display: \(display.displayID)")
    }

    private func updateStatus(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMenuItem?.title = "Status: \(status)"
        }
    }

    @objc private func quit() {
        Task {
            try? await screenCaptureService?.stopCapture()
        }
        signalingServer?.stop()
        // Note: Bonjour advertising stops when signalingServer stops
        webRTCManager?.disconnect()
        NSApplication.shared.terminate(nil)
    }
}

// Note: BonjourAdvertiserDelegate removed - SignalingServer handles Bonjour

// MARK: - SignalingServerDelegate
extension AppDelegate: SignalingServerDelegate {
    func signalingServerClientConnected() {
        updateStatus("Client connected - Negotiating")
        webRTCManager?.setupPeerConnection()
    }

    func signalingServerClientDisconnected() {
        updateStatus("Ready - Waiting for connection")
        isConnected = false
        Task {
            try? await screenCaptureService?.stopCapture()
        }
        webRTCManager?.disconnect()
    }

    func signalingServerDidReceiveOffer(sdp: String) {
        webRTCManager?.handleOffer(sdp: sdp)
    }

    func signalingServerDidReceiveIceCandidate(candidate: String, sdpMLineIndex: Int32, sdpMid: String?) {
        webRTCManager?.handleIceCandidate(candidate: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
    }
}

// MARK: - WebRTCManagerDelegate
extension AppDelegate: WebRTCManagerDelegate {
    func webRTCManager(_ manager: WebRTCManager, didGenerateAnswer sdp: String) {
        signalingServer?.send(.answer(sdp: sdp))

        // Send screen info
        if let info = screenCaptureService?.currentDisplayInfo {
            signalingServer?.send(.screenInfo(width: info.width, height: info.height, scale: info.scale))
        }
    }

    func webRTCManager(_ manager: WebRTCManager, didGenerateIceCandidate candidate: LKRTCIceCandidate) {
        signalingServer?.send(.ice(candidate: candidate.sdp, sdpMLineIndex: candidate.sdpMLineIndex, sdpMid: candidate.sdpMid))
    }

    func webRTCManager(_ manager: WebRTCManager, didReceiveInputMessage message: InputMessage) {
        if let cursorPos = inputController?.handleInput(message) {
            // Send cursor position back to client via data channel (lower latency than signaling)
            manager.sendCursorPosition(x: Double(cursorPos.x), y: Double(cursorPos.y))
        }
    }

    func webRTCManagerDidConnect(_ manager: WebRTCManager) {
        updateStatus("Connected - Streaming")
        isConnected = true

        Task {
            try? await screenCaptureService?.startCapture()
        }
    }

    func webRTCManagerDidDisconnect(_ manager: WebRTCManager) {
        updateStatus("Ready - Waiting for connection")
        isConnected = false
        Task {
            try? await screenCaptureService?.stopCapture()
        }
    }
}

// MARK: - ScreenCaptureServiceDelegate
extension AppDelegate: ScreenCaptureServiceDelegate {
    func screenCaptureService(_ service: ScreenCaptureService, didOutputSampleBuffer sampleBuffer: CMSampleBuffer) {
        guard isConnected,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        webRTCManager?.sendVideoFrame(pixelBuffer, timestamp: timestamp)
    }

    func screenCaptureService(_ service: ScreenCaptureService, didFailWithError error: Error) {
        updateStatus("Capture failed")
        print("Screen capture error: \(error)")
    }
}
