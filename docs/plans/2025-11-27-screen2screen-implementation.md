# Screen2Screen Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a TeamViewer-like remote desktop app with iOS client controlling macOS host over local network via WebRTC.

**Architecture:** macOS menu bar app captures screen via ScreenCaptureKit, streams H.264 over WebRTC. iOS app discovers hosts via Bonjour, renders video with Metal, sends input commands over DataChannel.

**Tech Stack:** Swift, SwiftUI, AppKit, WebRTC (libwebrtc), ScreenCaptureKit, Metal, Network.framework, Bonjour/mDNS

---

## Phase 1: Project Setup & Shared Code

### Task 1: Create Project Directory Structure

**Files:**
- Create: `Shared/Package.swift`
- Create: `Shared/Sources/Shared/Constants.swift`
- Create: `Shared/Sources/Shared/InputMessage.swift`
- Create: `Shared/Sources/Shared/SignalingMessage.swift`

**Step 1: Create directory structure**

```bash
mkdir -p Shared/Sources/Shared
mkdir -p Shared/Tests/SharedTests
```

**Step 2: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Shared",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(name: "Shared", targets: ["Shared"])
    ],
    targets: [
        .target(name: "Shared"),
        .testTarget(name: "SharedTests", dependencies: ["Shared"])
    ]
)
```

**Step 3: Create Constants.swift**

```swift
import Foundation

public enum Constants {
    public static let bonjourServiceType = "_screencast._tcp"
    public static let bonjourServiceDomain = "local."
    public static let signalingPort: UInt16 = 8080
    public static let defaultFrameRate = 30
}
```

**Step 4: Create InputMessage.swift**

```swift
import Foundation

public enum MouseButton: String, Codable {
    case left
    case right
}

public enum InputMessage: Codable {
    case mouseMove(dx: Double, dy: Double)
    case mouseDown(button: MouseButton)
    case mouseUp(button: MouseButton)
    case click(button: MouseButton, count: Int)
    case scroll(dx: Double, dy: Double)
    case keyDown(keyCode: UInt16, modifiers: [String])
    case keyUp(keyCode: UInt16, modifiers: [String])
    case keyPress(keyCode: UInt16, modifiers: [String])
    case text(characters: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case dx, dy
        case button
        case count
        case keyCode
        case modifiers
        case characters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "mouseMove":
            let dx = try container.decode(Double.self, forKey: .dx)
            let dy = try container.decode(Double.self, forKey: .dy)
            self = .mouseMove(dx: dx, dy: dy)
        case "mouseDown":
            let button = try container.decode(MouseButton.self, forKey: .button)
            self = .mouseDown(button: button)
        case "mouseUp":
            let button = try container.decode(MouseButton.self, forKey: .button)
            self = .mouseUp(button: button)
        case "click":
            let button = try container.decode(MouseButton.self, forKey: .button)
            let count = try container.decode(Int.self, forKey: .count)
            self = .click(button: button, count: count)
        case "scroll":
            let dx = try container.decode(Double.self, forKey: .dx)
            let dy = try container.decode(Double.self, forKey: .dy)
            self = .scroll(dx: dx, dy: dy)
        case "keyDown":
            let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
            let modifiers = try container.decode([String].self, forKey: .modifiers)
            self = .keyDown(keyCode: keyCode, modifiers: modifiers)
        case "keyUp":
            let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
            let modifiers = try container.decode([String].self, forKey: .modifiers)
            self = .keyUp(keyCode: keyCode, modifiers: modifiers)
        case "keyPress":
            let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
            let modifiers = try container.decode([String].self, forKey: .modifiers)
            self = .keyPress(keyCode: keyCode, modifiers: modifiers)
        case "text":
            let characters = try container.decode(String.self, forKey: .characters)
            self = .text(characters: characters)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .mouseMove(let dx, let dy):
            try container.encode("mouseMove", forKey: .type)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)
        case .mouseDown(let button):
            try container.encode("mouseDown", forKey: .type)
            try container.encode(button, forKey: .button)
        case .mouseUp(let button):
            try container.encode("mouseUp", forKey: .type)
            try container.encode(button, forKey: .button)
        case .click(let button, let count):
            try container.encode("click", forKey: .type)
            try container.encode(button, forKey: .button)
            try container.encode(count, forKey: .count)
        case .scroll(let dx, let dy):
            try container.encode("scroll", forKey: .type)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)
        case .keyDown(let keyCode, let modifiers):
            try container.encode("keyDown", forKey: .type)
            try container.encode(keyCode, forKey: .keyCode)
            try container.encode(modifiers, forKey: .modifiers)
        case .keyUp(let keyCode, let modifiers):
            try container.encode("keyUp", forKey: .type)
            try container.encode(keyCode, forKey: .keyCode)
            try container.encode(modifiers, forKey: .modifiers)
        case .keyPress(let keyCode, let modifiers):
            try container.encode("keyPress", forKey: .type)
            try container.encode(keyCode, forKey: .keyCode)
            try container.encode(modifiers, forKey: .modifiers)
        case .text(let characters):
            try container.encode("text", forKey: .type)
            try container.encode(characters, forKey: .characters)
        }
    }
}
```

**Step 5: Create SignalingMessage.swift**

```swift
import Foundation

public enum SignalingMessage: Codable {
    case offer(sdp: String)
    case answer(sdp: String)
    case ice(candidate: String, sdpMLineIndex: Int32, sdpMid: String?)
    case screenInfo(width: Int, height: Int, scale: Double)
    case cursorPos(x: Double, y: Double)

    private enum CodingKeys: String, CodingKey {
        case type
        case sdp
        case candidate
        case sdpMLineIndex
        case sdpMid
        case width, height, scale
        case x, y
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "offer":
            let sdp = try container.decode(String.self, forKey: .sdp)
            self = .offer(sdp: sdp)
        case "answer":
            let sdp = try container.decode(String.self, forKey: .sdp)
            self = .answer(sdp: sdp)
        case "ice":
            let candidate = try container.decode(String.self, forKey: .candidate)
            let sdpMLineIndex = try container.decode(Int32.self, forKey: .sdpMLineIndex)
            let sdpMid = try container.decodeIfPresent(String.self, forKey: .sdpMid)
            self = .ice(candidate: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        case "screenInfo":
            let width = try container.decode(Int.self, forKey: .width)
            let height = try container.decode(Int.self, forKey: .height)
            let scale = try container.decode(Double.self, forKey: .scale)
            self = .screenInfo(width: width, height: height, scale: scale)
        case "cursorPos":
            let x = try container.decode(Double.self, forKey: .x)
            let y = try container.decode(Double.self, forKey: .y)
            self = .cursorPos(x: x, y: y)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .offer(let sdp):
            try container.encode("offer", forKey: .type)
            try container.encode(sdp, forKey: .sdp)
        case .answer(let sdp):
            try container.encode("answer", forKey: .type)
            try container.encode(sdp, forKey: .sdp)
        case .ice(let candidate, let sdpMLineIndex, let sdpMid):
            try container.encode("ice", forKey: .type)
            try container.encode(candidate, forKey: .candidate)
            try container.encode(sdpMLineIndex, forKey: .sdpMLineIndex)
            try container.encodeIfPresent(sdpMid, forKey: .sdpMid)
        case .screenInfo(let width, let height, let scale):
            try container.encode("screenInfo", forKey: .type)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
            try container.encode(scale, forKey: .scale)
        case .cursorPos(let x, let y):
            try container.encode("cursorPos", forKey: .type)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        }
    }
}
```

**Step 6: Verify package builds**

Run: `cd Shared && swift build`
Expected: Build Succeeded

**Step 7: Commit**

```bash
git init
git add .
git commit -m "feat: add shared Swift package with message types"
```

---

### Task 2: Download and Set Up WebRTC Framework

**Files:**
- Create: `WebRTC/` directory with xcframework

**Step 1: Create WebRTC directory**

```bash
mkdir -p WebRTC
```

**Step 2: Download prebuilt WebRTC.xcframework**

Option A - Use stasel's prebuilt (recommended):
```bash
cd WebRTC
curl -L -o webrtc.zip "https://github.com/nicothin/nicothin-webrtc-build/releases/download/m131/WebRTC-M131.xcframework.zip"
unzip webrtc.zip
rm webrtc.zip
```

Option B - If Option A fails, use CocoaPods source:
```bash
# Alternative: check https://cocoapods.org/pods/GoogleWebRTC for latest
```

**Step 3: Verify framework structure**

```bash
ls WebRTC/WebRTC.xcframework/
```
Expected: Should see `ios-arm64/`, `macos-arm64_x86_64/` or similar slices

**Step 4: Commit**

```bash
git add WebRTC/
git commit -m "feat: add prebuilt WebRTC.xcframework"
```

---

## Phase 2: macOS Host Application

### Task 3: Create macOS Xcode Project

**Files:**
- Create: `ScreenToScreenHost/ScreenToScreenHost.xcodeproj`
- Create: `ScreenToScreenHost/Sources/App/AppDelegate.swift`
- Create: `ScreenToScreenHost/Sources/App/ScreenToScreenHost.entitlements`

**Step 1: Create Xcode project via command line**

```bash
mkdir -p ScreenToScreenHost/Sources/App
mkdir -p ScreenToScreenHost/Sources/Services
mkdir -p ScreenToScreenHost/Sources/Models
mkdir -p ScreenToScreenHost/Resources
```

**Step 2: Create AppDelegate.swift**

```swift
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
```

**Step 3: Create entitlements file**

Create `ScreenToScreenHost/Sources/App/ScreenToScreenHost.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

**Step 4: Create Info.plist**

Create `ScreenToScreenHost/Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ScreenToScreenHost</string>
    <key>CFBundleIdentifier</key>
    <string>com.screen2screen.host</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.3</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Screen2Screen needs screen recording permission to share your screen with connected devices.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_screencast._tcp</string>
    </array>
</dict>
</plist>
```

**Step 5: Create Xcode project file**

This step requires Xcode. Open Xcode and:
1. File → New → Project → macOS → App
2. Product Name: ScreenToScreenHost
3. Team: Your team
4. Bundle ID: com.screen2screen.host
5. Language: Swift
6. User Interface: None (we're a menu bar app)
7. Save to: `screen2screen/ScreenToScreenHost/`

Then configure:
- Add Shared package: File → Add Package Dependencies → Add Local → select `Shared/`
- Add WebRTC.xcframework: Drag into project, embed & sign
- Set deployment target: macOS 12.3
- Add entitlements file to target
- Set LSUIElement = YES in Info.plist (menu bar app)

**Step 6: Verify project builds**

Run: Open Xcode, build (Cmd+B)
Expected: Build Succeeded

**Step 7: Commit**

```bash
git add ScreenToScreenHost/
git commit -m "feat: create macOS host Xcode project skeleton"
```

---

### Task 4: Bonjour Advertising (Integrated into SignalingServer)

**NOTE:** Bonjour advertising is now handled directly by SignalingServer (Task 5) to avoid port conflicts. Having two NWListeners on the same port would cause "address already in use" errors.

**No separate BonjourAdvertiser class needed.** The SignalingServer sets its `listener?.service` property to advertise via Bonjour while also handling connections.

**Skip this task** - proceed directly to Task 5.

**Commit** (nothing to commit for this task - skip to Task 5)

---

### Task 5: Implement SignalingServer (WebSocket)

**Files:**
- Create: `ScreenToScreenHost/Sources/Services/SignalingServer.swift`

**Step 1: Create SignalingServer.swift**

```swift
import Foundation
import Network
import Shared

protocol SignalingServerDelegate: AnyObject {
    func signalingServerDidReceiveOffer(sdp: String)
    func signalingServerDidReceiveIceCandidate(candidate: String, sdpMLineIndex: Int32, sdpMid: String?)
    func signalingServerClientConnected()
    func signalingServerClientDisconnected()
}

final class SignalingServer {
    weak var delegate: SignalingServerDelegate?

    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "com.screen2screen.signaling")

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(port: UInt16 = Constants.signalingPort) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        listener = try NWListener(using: parameters, on: port)

        // Set up Bonjour advertising on the same listener (avoids port conflict)
        let serviceName = Host.current().localizedName ?? "Mac"
        listener?.service = NWListener.Service(
            name: serviceName,
            type: Constants.bonjourServiceType,
            domain: Constants.bonjourServiceDomain
        )

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Signaling server listening on port \(self?.port.rawValue ?? 0)")
                print("Bonjour advertising started: \(serviceName)")
            case .failed(let error):
                print("Signaling server failed: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
    }

    func send(_ message: SignalingMessage) {
        guard let connection = activeConnection else {
            print("No active connection to send message")
            return
        }

        do {
            let data = try encoder.encode(message)
            let framedData = frameMessage(data)

            connection.send(content: framedData, completion: .contentProcessed { error in
                if let error = error {
                    print("Failed to send signaling message: \(error)")
                }
            })
        } catch {
            print("Failed to encode signaling message: \(error)")
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        // Only allow one connection at a time
        activeConnection?.cancel()
        activeConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Client connected")
                self?.delegate?.signalingServerClientConnected()
                self?.receiveMessage(on: connection)
            case .failed(let error):
                print("Connection failed: \(error)")
                self?.delegate?.signalingServerClientDisconnected()
            case .cancelled:
                print("Connection cancelled")
                self?.delegate?.signalingServerClientDisconnected()
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveMessage(on connection: NWConnection) {
        // Read 4-byte length prefix
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("Receive error: \(error)")
                return
            }

            if isComplete {
                self.delegate?.signalingServerClientDisconnected()
                return
            }

            guard let lengthData = data, lengthData.count == 4 else {
                self.receiveMessage(on: connection)
                return
            }

            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            // Read message body
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] data, _, _, error in
                guard let self = self else { return }

                if let error = error {
                    print("Receive body error: \(error)")
                    return
                }

                if let messageData = data {
                    self.handleMessage(messageData)
                }

                self.receiveMessage(on: connection)
            }
        }
    }

    private func handleMessage(_ data: Data) {
        do {
            let message = try decoder.decode(SignalingMessage.self, from: data)

            DispatchQueue.main.async { [weak self] in
                switch message {
                case .offer(let sdp):
                    self?.delegate?.signalingServerDidReceiveOffer(sdp: sdp)
                case .ice(let candidate, let sdpMLineIndex, let sdpMid):
                    self?.delegate?.signalingServerDidReceiveIceCandidate(
                        candidate: candidate,
                        sdpMLineIndex: sdpMLineIndex,
                        sdpMid: sdpMid
                    )
                default:
                    print("Unexpected message type from client")
                }
            }
        } catch {
            print("Failed to decode signaling message: \(error)")
        }
    }

    private func frameMessage(_ data: Data) -> Data {
        var framedData = Data()
        var length = UInt32(data.count).bigEndian
        framedData.append(Data(bytes: &length, count: 4))
        framedData.append(data)
        return framedData
    }
}
```

**Step 2: Verify it compiles**

Open Xcode, build (Cmd+B)
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add ScreenToScreenHost/Sources/Services/SignalingServer.swift
git commit -m "feat(host): add WebSocket-style signaling server"
```

---

### Task 6: Implement ScreenCaptureService

**Files:**
- Create: `ScreenToScreenHost/Sources/Services/ScreenCaptureService.swift`

**Step 1: Create ScreenCaptureService.swift**

```swift
import Foundation
import ScreenCaptureKit
import CoreMedia
import Shared

protocol ScreenCaptureServiceDelegate: AnyObject {
    func screenCaptureService(_ service: ScreenCaptureService, didOutputSampleBuffer sampleBuffer: CMSampleBuffer)
    func screenCaptureService(_ service: ScreenCaptureService, didFailWithError error: Error)
}

final class ScreenCaptureService: NSObject {
    weak var delegate: ScreenCaptureServiceDelegate?

    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var selectedDisplay: SCDisplay?

    private(set) var isCapturing = false
    private(set) var availableDisplays: [SCDisplay] = []

    override init() {
        super.init()
    }

    func requestPermissionAndLoadDisplays() async throws {
        // This triggers the permission prompt if needed
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        availableDisplays = content.displays

        // Default to main display
        selectedDisplay = availableDisplays.first { $0.displayID == CGMainDisplayID() }
            ?? availableDisplays.first
    }

    func selectDisplay(_ display: SCDisplay) {
        selectedDisplay = display
    }

    func startCapture(frameRate: Int = Constants.defaultFrameRate) async throws {
        guard let display = selectedDisplay else {
            throw ScreenCaptureError.noDisplaySelected
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        // Get actual scale factor (not all displays are Retina)
        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        config.width = Int(Double(display.width) * scaleFactor)
        config.height = Int(Double(display.height) * scaleFactor)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        stream = SCStream(filter: filter, configuration: config, delegate: self)

        streamOutput = StreamOutput { [weak self] sampleBuffer in
            guard let self = self else { return }
            self.delegate?.screenCaptureService(self, didOutputSampleBuffer: sampleBuffer)
        }

        try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: .main)
        try await stream?.startCapture()

        isCapturing = true
        print("Screen capture started for display: \(display.displayID)")
    }

    func stopCapture() async throws {
        try await stream?.stopCapture()
        stream = nil
        streamOutput = nil
        isCapturing = false
        print("Screen capture stopped")
    }

    var currentDisplayInfo: (width: Int, height: Int, scale: Double)? {
        guard let display = selectedDisplay else { return nil }
        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        return (
            width: display.width,
            height: display.height,
            scale: scaleFactor
        )
    }
}

extension ScreenCaptureService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isCapturing = false
        delegate?.screenCaptureService(self, didFailWithError: error)
    }
}

private class StreamOutput: NSObject, SCStreamOutput {
    private let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        handler(sampleBuffer)
    }
}

enum ScreenCaptureError: Error {
    case noDisplaySelected
    case permissionDenied
}
```

**Step 2: Verify it compiles**

Open Xcode, build (Cmd+B)
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add ScreenToScreenHost/Sources/Services/ScreenCaptureService.swift
git commit -m "feat(host): add ScreenCaptureKit service with display selection"
```

---

### Task 7: Implement InputController

**Files:**
- Create: `ScreenToScreenHost/Sources/Services/InputController.swift`

**Step 1: Create InputController.swift**

```swift
import Foundation
import CoreGraphics
import Shared

final class InputController {
    private var currentMouseLocation: CGPoint
    private let displayBounds: CGRect

    init() {
        currentMouseLocation = NSEvent.mouseLocation
        displayBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    func handleInput(_ message: InputMessage) {
        switch message {
        case .mouseMove(let dx, let dy):
            moveMouseRelative(dx: dx, dy: dy)

        case .mouseDown(let button):
            postMouseEvent(type: button == .left ? .leftMouseDown : .rightMouseDown, button: button)

        case .mouseUp(let button):
            postMouseEvent(type: button == .left ? .leftMouseUp : .rightMouseUp, button: button)

        case .click(let button, let count):
            for _ in 0..<count {
                postMouseEvent(type: button == .left ? .leftMouseDown : .rightMouseDown, button: button)
                postMouseEvent(type: button == .left ? .leftMouseUp : .rightMouseUp, button: button)
            }

        case .scroll(let dx, let dy):
            postScrollEvent(dx: dx, dy: dy)

        case .keyDown(let keyCode, let modifiers):
            postKeyEvent(keyCode: keyCode, modifiers: modifiers, isDown: true)

        case .keyUp(let keyCode, let modifiers):
            postKeyEvent(keyCode: keyCode, modifiers: modifiers, isDown: false)

        case .keyPress(let keyCode, let modifiers):
            postKeyEvent(keyCode: keyCode, modifiers: modifiers, isDown: true)
            postKeyEvent(keyCode: keyCode, modifiers: modifiers, isDown: false)

        case .text(let characters):
            typeText(characters)
        }
    }

    private func moveMouseRelative(dx: Double, dy: Double) {
        // Get current cursor position using CGEvent (consistent coordinate system)
        guard let currentEvent = CGEvent(source: nil) else { return }
        var location = currentEvent.location

        // Apply relative movement
        location.x += CGFloat(dx)
        location.y += CGFloat(dy)

        // Clamp to screen bounds (CGEvent uses top-left origin)
        location.x = max(0, min(location.x, displayBounds.width))
        location.y = max(0, min(location.y, displayBounds.height))

        if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }

        currentMouseLocation = location
    }

    private func postMouseEvent(type: CGEventType, button: MouseButton) {
        let cgButton: CGMouseButton = button == .left ? .left : .right
        let location = CGEvent(source: nil)?.location ?? currentMouseLocation

        if let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: cgButton) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func postScrollEvent(dx: Double, dy: Double) {
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func postKeyEvent(keyCode: UInt16, modifiers: [String], isDown: Bool) {
        let eventType: CGEventType = isDown ? .keyDown : .keyUp

        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isDown) else {
            return
        }

        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier.lowercased() {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "ctrl", "control":
                flags.insert(.maskControl)
            case "alt", "option":
                flags.insert(.maskAlternate)
            case "shift":
                flags.insert(.maskShift)
            default:
                break
            }
        }

        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func typeText(_ text: String) {
        for char in text {
            let string = String(char)
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                event.keyboardSetUnicodeString(stringLength: string.count, unicodeString: Array(string.utf16))
                event.post(tap: .cghidEventTap)
            }
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                event.post(tap: .cghidEventTap)
            }
        }
    }
}
```

**Step 2: Verify it compiles**

Open Xcode, build (Cmd+B)
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add ScreenToScreenHost/Sources/Services/InputController.swift
git commit -m "feat(host): add CGEvent-based input controller"
```

---

### Task 8: Implement WebRTCManager (Host)

**Files:**
- Create: `ScreenToScreenHost/Sources/Services/WebRTCManager.swift`

**Step 1: Create WebRTCManager.swift**

```swift
import Foundation
import WebRTC
import Shared

protocol WebRTCManagerDelegate: AnyObject {
    func webRTCManager(_ manager: WebRTCManager, didGenerateAnswer sdp: String)
    func webRTCManager(_ manager: WebRTCManager, didGenerateIceCandidate candidate: RTCIceCandidate)
    func webRTCManager(_ manager: WebRTCManager, didReceiveInputMessage message: InputMessage)
    func webRTCManagerDidConnect(_ manager: WebRTCManager)
    func webRTCManagerDidDisconnect(_ manager: WebRTCManager)
}

final class WebRTCManager: NSObject {
    weak var delegate: WebRTCManagerDelegate?

    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var videoSource: RTCVideoSource?
    private var videoTrack: RTCVideoTrack?

    private let decoder = JSONDecoder()

    override init() {
        RTCInitializeSSL()

        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)

        super.init()
    }

    deinit {
        RTCCleanupSSL()
    }

    func setupPeerConnection() {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        // Empty ICE servers for local network (direct connection)
        config.iceServers = []

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)

        setupVideoTrack()
    }

    private func setupVideoTrack() {
        videoSource = factory.videoSource()
        videoSource?.adaptOutputFormat(toWidth: 1920, height: 1080, fps: 30)
        videoTrack = factory.videoTrack(with: videoSource!, trackId: "screen0")

        if let track = videoTrack {
            peerConnection?.add(track, streamIds: ["screen"])
        }
    }

    func handleOffer(sdp: String) {
        let sessionDescription = RTCSessionDescription(type: .offer, sdp: sdp)

        peerConnection?.setRemoteDescription(sessionDescription) { [weak self] error in
            if let error = error {
                print("Failed to set remote description: \(error)")
                return
            }
            self?.createAnswer()
        }
    }

    private func createAnswer() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        peerConnection?.answer(for: constraints) { [weak self] sessionDescription, error in
            guard let self = self, let sdp = sessionDescription else {
                print("Failed to create answer: \(error?.localizedDescription ?? "unknown")")
                return
            }

            self.peerConnection?.setLocalDescription(sdp) { error in
                if let error = error {
                    print("Failed to set local description: \(error)")
                    return
                }

                self.delegate?.webRTCManager(self, didGenerateAnswer: sdp.sdp)
            }
        }
    }

    func handleIceCandidate(candidate: String, sdpMLineIndex: Int32, sdpMid: String?) {
        let iceCandidate = RTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        peerConnection?.add(iceCandidate) { error in
            if let error = error {
                print("Failed to add ICE candidate: \(error)")
            }
        }
    }

    func sendVideoFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let videoSource = videoSource else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Update output format to match actual frame dimensions
        videoSource.adaptOutputFormat(toWidth: Int32(width), height: Int32(height), fps: 30)

        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let timestampNs = Int64(CMTimeGetSeconds(timestamp) * 1_000_000_000)
        let videoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: ._0, timeStampNs: timestampNs)

        // Push frame directly to the video source delegate
        videoSource.delegate?.capturer?(RTCVideoCapturer(), didCapture: videoFrame)
    }

    func disconnect() {
        dataChannel?.close()
        dataChannel = nil
        peerConnection?.close()
        peerConnection = nil
    }
}

extension WebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("Signaling state changed: \(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("Stream added")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("Stream removed")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("Negotiation needed")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("ICE connection state changed: \(newState.rawValue)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch newState {
            case .connected, .completed:
                self.delegate?.webRTCManagerDidConnect(self)
            case .disconnected, .failed, .closed:
                self.delegate?.webRTCManagerDidDisconnect(self)
            default:
                break
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("ICE gathering state changed: \(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        delegate?.webRTCManager(self, didGenerateIceCandidate: candidate)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("ICE candidates removed")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("Data channel opened: \(dataChannel.label)")
        self.dataChannel = dataChannel
        dataChannel.delegate = self
    }
}

extension WebRTCManager: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("Data channel state changed: \(dataChannel.readyState.rawValue)")
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let data = buffer.data as Data? else { return }

        do {
            let message = try decoder.decode(InputMessage.self, from: data)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.webRTCManager(self, didReceiveInputMessage: message)
            }
        } catch {
            print("Failed to decode input message: \(error)")
        }
    }
}
```

**Step 2: Verify it compiles**

Open Xcode, build (Cmd+B)
Expected: Build Succeeded (may have warnings about WebRTC import - verify framework is linked)

**Step 3: Commit**

```bash
git add ScreenToScreenHost/Sources/Services/WebRTCManager.swift
git commit -m "feat(host): add WebRTC manager for video streaming and data channel"
```

---

### Task 9: Wire Up Host Services in AppDelegate

**Files:**
- Modify: `ScreenToScreenHost/Sources/App/AppDelegate.swift`

**Step 1: Update AppDelegate to wire all services**

```swift
import Cocoa
import Shared
import CoreMedia
import ScreenCaptureKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!

    // Note: BonjourAdvertiser removed - SignalingServer handles Bonjour advertising
    private var signalingServer: SignalingServer?
    private var screenCaptureService: ScreenCaptureService?
    private var webRTCManager: WebRTCManager?
    private var inputController: InputController?

    private var isConnected = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        Task {
            await startServices()
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Screen2Screen")
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

    func webRTCManager(_ manager: WebRTCManager, didGenerateIceCandidate candidate: RTCIceCandidate) {
        signalingServer?.send(.ice(candidate: candidate.sdp, sdpMLineIndex: candidate.sdpMLineIndex, sdpMid: candidate.sdpMid))
    }

    func webRTCManager(_ manager: WebRTCManager, didReceiveInputMessage message: InputMessage) {
        inputController?.handleInput(message)
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
```

**Step 2: Verify it compiles**

Open Xcode, build (Cmd+B)
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add ScreenToScreenHost/Sources/App/AppDelegate.swift
git commit -m "feat(host): wire up all services in AppDelegate"
```

---

## Phase 3: iOS Client Application

### Task 10: Create iOS Xcode Project

**Files:**
- Create: `ScreenToScreenClient/ScreenToScreenClient.xcodeproj`
- Create: `ScreenToScreenClient/Sources/App/ScreenToScreenApp.swift`

**Step 1: Create directory structure**

```bash
mkdir -p ScreenToScreenClient/Sources/App
mkdir -p ScreenToScreenClient/Sources/Views
mkdir -p ScreenToScreenClient/Sources/Services
mkdir -p ScreenToScreenClient/Sources/Gestures
mkdir -p ScreenToScreenClient/Sources/Models
mkdir -p ScreenToScreenClient/Resources
```

**Step 2: Create ScreenToScreenApp.swift**

```swift
import SwiftUI

@main
struct ScreenToScreenApp: App {
    var body: some Scene {
        WindowGroup {
            HostListView()
        }
    }
}
```

**Step 3: Create Info.plist**

Create `ScreenToScreenClient/Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Screen2Screen</string>
    <key>CFBundleIdentifier</key>
    <string>com.screen2screen.client</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>MinimumOSVersion</key>
    <string>15.0</string>
    <key>UILaunchScreen</key>
    <dict/>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
        <string>UIInterfaceOrientationPortrait</string>
    </array>
    <key>NSBonjourServices</key>
    <array>
        <string>_screencast._tcp</string>
    </array>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Screen2Screen needs local network access to discover and connect to your Mac.</string>
</dict>
</plist>
```

**Step 4: Create Xcode project**

Open Xcode:
1. File → New → Project → iOS → App
2. Product Name: ScreenToScreenClient
3. Team: Your team
4. Bundle ID: com.screen2screen.client
5. Interface: SwiftUI
6. Language: Swift
7. Save to: `screen2screen/ScreenToScreenClient/`

Configure:
- Add Shared package dependency
- Add WebRTC.xcframework (embed & sign)
- Set deployment target: iOS 15.0
- Configure Info.plist with Bonjour and local network usage

**Step 5: Verify project builds**

Open Xcode, build (Cmd+B)
Expected: Build Succeeded

**Step 6: Commit**

```bash
git add ScreenToScreenClient/
git commit -m "feat: create iOS client Xcode project skeleton"
```

---

### Task 11: Implement BonjourBrowser

**Files:**
- Create: `ScreenToScreenClient/Sources/Services/BonjourBrowser.swift`
- Create: `ScreenToScreenClient/Sources/Models/HostInfo.swift`

**Step 1: Create HostInfo.swift**

```swift
import Foundation

struct HostInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: UInt16

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: HostInfo, rhs: HostInfo) -> Bool {
        lhs.id == rhs.id
    }
}
```

**Step 2: Create BonjourBrowser.swift**

```swift
import Foundation
import Network
import Shared

@MainActor
final class BonjourBrowser: ObservableObject {
    @Published var discoveredHosts: [HostInfo] = []
    @Published var isSearching = false

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.screen2screen.browser")

    func startBrowsing() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: Constants.bonjourServiceType, domain: Constants.bonjourServiceDomain), using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isSearching = true
                case .failed, .cancelled:
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleResults(results)
            }
        }

        browser?.start(queue: queue)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        var hosts: [HostInfo] = []

        for result in results {
            switch result.endpoint {
            case .service(let name, let type, let domain, _):
                // Resolve the service to get IP and port
                resolveService(name: name, type: type, domain: domain) { [weak self] hostInfo in
                    Task { @MainActor in
                        guard let self = self, let info = hostInfo else { return }
                        if !self.discoveredHosts.contains(where: { $0.id == info.id }) {
                            self.discoveredHosts.append(info)
                        }
                    }
                }
            default:
                break
            }
        }
    }

    private func resolveService(name: String, type: String, domain: String, completion: @escaping (HostInfo?) -> Void) {
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)

        let parameters = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: parameters)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = innerEndpoint {
                    let hostString: String
                    switch host {
                    case .ipv4(let addr):
                        hostString = "\(addr)"
                    case .ipv6(let addr):
                        hostString = "\(addr)"
                    case .name(let name, _):
                        hostString = name
                    @unknown default:
                        hostString = "unknown"
                    }

                    let info = HostInfo(
                        id: "\(name).\(type)\(domain)",
                        name: name,
                        host: hostString,
                        port: port.rawValue
                    )
                    completion(info)
                }
                connection.cancel()
            case .failed, .cancelled:
                completion(nil)
            default:
                break
            }
        }

        connection.start(queue: queue)

        // Timeout
        queue.asyncAfter(deadline: .now() + 5) {
            if connection.state != .ready {
                connection.cancel()
                completion(nil)
            }
        }
    }
}
```

**Step 3: Verify it compiles**

Open Xcode, build (Cmd+B)
Expected: Build Succeeded

**Step 4: Commit**

```bash
git add ScreenToScreenClient/Sources/Services/BonjourBrowser.swift
git add ScreenToScreenClient/Sources/Models/HostInfo.swift
git commit -m "feat(client): add Bonjour browser for host discovery"
```

---

### Task 12: Implement SignalingClient

**Files:**
- Create: `ScreenToScreenClient/Sources/Services/SignalingClient.swift`

**Step 1: Create SignalingClient.swift**

```swift
import Foundation
import Network
import Shared

protocol SignalingClientDelegate: AnyObject {
    func signalingClientDidConnect()
    func signalingClientDidDisconnect()
    func signalingClient(_ client: SignalingClient, didReceiveAnswer sdp: String)
    func signalingClient(_ client: SignalingClient, didReceiveIceCandidate candidate: String, sdpMLineIndex: Int32, sdpMid: String?)
    func signalingClient(_ client: SignalingClient, didReceiveScreenInfo width: Int, height: Int, scale: Double)
}

final class SignalingClient {
    weak var delegate: SignalingClientDelegate?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.screen2screen.signaling.client")

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func connect(to host: HostInfo) {
        let hostEndpoint = NWEndpoint.Host(host.host)
        let port = NWEndpoint.Port(rawValue: host.port)!

        connection = NWConnection(host: hostEndpoint, port: port, using: .tcp)

        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Connected to signaling server")
                DispatchQueue.main.async {
                    self?.delegate?.signalingClientDidConnect()
                }
                self?.receiveMessage()
            case .failed(let error):
                print("Connection failed: \(error)")
                DispatchQueue.main.async {
                    self?.delegate?.signalingClientDidDisconnect()
                }
            case .cancelled:
                print("Connection cancelled")
                DispatchQueue.main.async {
                    self?.delegate?.signalingClientDidDisconnect()
                }
            default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func send(_ message: SignalingMessage) {
        guard let connection = connection else { return }

        do {
            let data = try encoder.encode(message)
            let framedData = frameMessage(data)

            connection.send(content: framedData, completion: .contentProcessed { error in
                if let error = error {
                    print("Failed to send: \(error)")
                }
            })
        } catch {
            print("Failed to encode message: \(error)")
        }
    }

    private func receiveMessage() {
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("Receive error: \(error)")
                return
            }

            if isComplete {
                DispatchQueue.main.async {
                    self.delegate?.signalingClientDidDisconnect()
                }
                return
            }

            guard let lengthData = data, lengthData.count == 4 else {
                self.receiveMessage()
                return
            }

            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            self.connection?.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] data, _, _, error in
                guard let self = self else { return }

                if let error = error {
                    print("Receive body error: \(error)")
                    return
                }

                if let messageData = data {
                    self.handleMessage(messageData)
                }

                self.receiveMessage()
            }
        }
    }

    private func handleMessage(_ data: Data) {
        do {
            let message = try decoder.decode(SignalingMessage.self, from: data)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                switch message {
                case .answer(let sdp):
                    self.delegate?.signalingClient(self, didReceiveAnswer: sdp)
                case .ice(let candidate, let sdpMLineIndex, let sdpMid):
                    self.delegate?.signalingClient(self, didReceiveIceCandidate: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
                case .screenInfo(let width, let height, let scale):
                    self.delegate?.signalingClient(self, didReceiveScreenInfo: width, height: height, scale: scale)
                default:
                    break
                }
            }
        } catch {
            print("Failed to decode message: \(error)")
        }
    }

    private func frameMessage(_ data: Data) -> Data {
        var framedData = Data()
        var length = UInt32(data.count).bigEndian
        framedData.append(Data(bytes: &length, count: 4))
        framedData.append(data)
        return framedData
    }
}
```

**Step 2: Verify it compiles**

Open Xcode, build (Cmd+B)
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add ScreenToScreenClient/Sources/Services/SignalingClient.swift
git commit -m "feat(client): add signaling client for WebRTC negotiation"
```

---

### Task 13: Implement WebRTCClient

**Files:**
- Create: `ScreenToScreenClient/Sources/Services/WebRTCClient.swift`

**Step 1: Create WebRTCClient.swift**

```swift
import Foundation
import WebRTC
import Shared

protocol WebRTCClientDelegate: AnyObject {
    func webRTCClient(_ client: WebRTCClient, didGenerateOffer sdp: String)
    func webRTCClient(_ client: WebRTCClient, didGenerateIceCandidate candidate: RTCIceCandidate)
    func webRTCClient(_ client: WebRTCClient, didReceiveVideoTrack track: RTCVideoTrack)
    func webRTCClientDidConnect(_ client: WebRTCClient)
    func webRTCClientDidDisconnect(_ client: WebRTCClient)
}

final class WebRTCClient: NSObject {
    weak var delegate: WebRTCClientDelegate?

    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?

    private let encoder = JSONEncoder()

    override init() {
        RTCInitializeSSL()

        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)

        super.init()
    }

    deinit {
        RTCCleanupSSL()
    }

    func setupPeerConnection() {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.iceServers = []  // Local network, no STUN/TURN needed

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)

        // Create data channel for input
        let dataChannelConfig = RTCDataChannelConfiguration()
        dataChannelConfig.isOrdered = true
        dataChannelConfig.isNegotiated = false

        dataChannel = peerConnection?.dataChannel(forLabel: "input", configuration: dataChannelConfig)
        dataChannel?.delegate = self

        // Add transceiver for receiving video
        let transceiverInit = RTCRtpTransceiverInit()
        transceiverInit.direction = .recvOnly
        peerConnection?.addTransceiver(of: .video, init: transceiverInit)
    }

    func createOffer() {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveVideo": "true",
                "OfferToReceiveAudio": "false"
            ],
            optionalConstraints: nil
        )

        peerConnection?.offer(for: constraints) { [weak self] sessionDescription, error in
            guard let self = self, let sdp = sessionDescription else {
                print("Failed to create offer: \(error?.localizedDescription ?? "unknown")")
                return
            }

            self.peerConnection?.setLocalDescription(sdp) { error in
                if let error = error {
                    print("Failed to set local description: \(error)")
                    return
                }

                self.delegate?.webRTCClient(self, didGenerateOffer: sdp.sdp)
            }
        }
    }

    func handleAnswer(sdp: String) {
        let sessionDescription = RTCSessionDescription(type: .answer, sdp: sdp)

        peerConnection?.setRemoteDescription(sessionDescription) { error in
            if let error = error {
                print("Failed to set remote description: \(error)")
            }
        }
    }

    func handleIceCandidate(candidate: String, sdpMLineIndex: Int32, sdpMid: String?) {
        let iceCandidate = RTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        peerConnection?.add(iceCandidate) { error in
            if let error = error {
                print("Failed to add ICE candidate: \(error)")
            }
        }
    }

    func sendInput(_ message: InputMessage) {
        guard let dataChannel = dataChannel, dataChannel.readyState == .open else {
            return
        }

        do {
            let data = try encoder.encode(message)
            let buffer = RTCDataBuffer(data: data, isBinary: false)
            dataChannel.sendData(buffer)
        } catch {
            print("Failed to encode input message: \(error)")
        }
    }

    func disconnect() {
        dataChannel?.close()
        dataChannel = nil
        peerConnection?.close()
        peerConnection = nil
    }
}

extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("Signaling state: \(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("Stream added with \(stream.videoTracks.count) video tracks")
        if let videoTrack = stream.videoTracks.first {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.webRTCClient(self, didReceiveVideoTrack: videoTrack)
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("Stream removed")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("Negotiation needed")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("ICE connection state: \(newState.rawValue)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch newState {
            case .connected, .completed:
                self.delegate?.webRTCClientDidConnect(self)
            case .disconnected, .failed, .closed:
                self.delegate?.webRTCClientDidDisconnect(self)
            default:
                break
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("ICE gathering state: \(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        delegate?.webRTCClient(self, didGenerateIceCandidate: candidate)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("Data channel opened: \(dataChannel.label)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        if let videoTrack = rtpReceiver.track as? RTCVideoTrack {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.webRTCClient(self, didReceiveVideoTrack: videoTrack)
            }
        }
    }
}

extension WebRTCClient: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("Data channel state: \(dataChannel.readyState.rawValue)")
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        // Host doesn't send data to client via data channel in this design
    }
}
```

**Step 2: Verify it compiles**

Open Xcode, build (Cmd+B)
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add ScreenToScreenClient/Sources/Services/WebRTCClient.swift
git commit -m "feat(client): add WebRTC client for video receiving and input sending"
```

---

### Task 14: Implement VideoRenderView (Metal)

**Files:**
- Create: `ScreenToScreenClient/Sources/Views/VideoRenderView.swift`

**Step 1: Create VideoRenderView.swift**

```swift
import SwiftUI
import WebRTC

struct VideoRenderView: UIViewRepresentable {
    let videoTrack: RTCVideoTrack?

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFit
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        if let track = videoTrack {
            track.add(uiView)
        }
    }

    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: ()) {
        // Track will be removed when view is deallocated
    }
}
```

**Step 2: Verify it compiles**

Open Xcode, build (Cmd+B)
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add ScreenToScreenClient/Sources/Views/VideoRenderView.swift
git commit -m "feat(client): add Metal-backed video render view"
```

---

### Task 15: Implement GestureController

**Files:**
- Create: `ScreenToScreenClient/Sources/Gestures/GestureController.swift`
- Create: `ScreenToScreenClient/Sources/Gestures/CursorState.swift`

**Step 1: Create CursorState.swift**

```swift
import Foundation

final class CursorState: ObservableObject {
    @Published var activeModifiers: Set<String> = []

    func toggleModifier(_ modifier: String) {
        if activeModifiers.contains(modifier) {
            activeModifiers.remove(modifier)
        } else {
            activeModifiers.insert(modifier)
        }
    }

    func clearModifiers() {
        activeModifiers.removeAll()
    }

    var modifierArray: [String] {
        Array(activeModifiers)
    }
}
```

**Step 2: Create GestureController.swift**

```swift
import UIKit
import Shared

protocol GestureControllerDelegate: AnyObject {
    func gestureController(_ controller: GestureController, didGenerateInput message: InputMessage)
}

final class GestureController: NSObject {
    weak var delegate: GestureControllerDelegate?

    private let cursorState: CursorState
    private var lastPanLocation: CGPoint?

    init(cursorState: CursorState) {
        self.cursorState = cursorState
        super.init()
    }

    func setupGestures(on view: UIView) {
        // Pan gesture for cursor movement
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        view.addGestureRecognizer(panGesture)

        // Tap for left click
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.numberOfTouchesRequired = 1
        view.addGestureRecognizer(tapGesture)

        // Double tap for double click
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.numberOfTouchesRequired = 1
        view.addGestureRecognizer(doubleTapGesture)
        tapGesture.require(toFail: doubleTapGesture)

        // Two-finger tap for right click
        let twoFingerTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTapGesture.numberOfTapsRequired = 1
        twoFingerTapGesture.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoFingerTapGesture)

        // Two-finger pan for scroll
        let scrollGesture = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scrollGesture.minimumNumberOfTouches = 2
        scrollGesture.maximumNumberOfTouches = 2
        view.addGestureRecognizer(scrollGesture)

        // Pinch for zoom (client-side only, handled separately)
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: gesture.view)

        switch gesture.state {
        case .began:
            lastPanLocation = location
        case .changed:
            guard let last = lastPanLocation else { return }

            let dx = location.x - last.x
            let dy = location.y - last.y

            // Scale movement (adjust sensitivity)
            let sensitivity: CGFloat = 1.5
            let message = InputMessage.mouseMove(dx: Double(dx * sensitivity), dy: Double(dy * sensitivity))
            delegate?.gestureController(self, didGenerateInput: message)

            lastPanLocation = location
        case .ended, .cancelled:
            lastPanLocation = nil
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let message = InputMessage.click(button: .left, count: 1)
        delegate?.gestureController(self, didGenerateInput: message)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let message = InputMessage.click(button: .left, count: 2)
        delegate?.gestureController(self, didGenerateInput: message)
    }

    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        let message = InputMessage.click(button: .right, count: 1)
        delegate?.gestureController(self, didGenerateInput: message)
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed else { return }

        let velocity = gesture.velocity(in: gesture.view)

        // Scale scroll amount
        let dx = -velocity.x / 50
        let dy = -velocity.y / 50

        let message = InputMessage.scroll(dx: Double(dx), dy: Double(dy))
        delegate?.gestureController(self, didGenerateInput: message)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        // Pinch zoom is handled client-side only (view transform)
        // This placeholder allows the gesture to be recognized
    }

    // Called from keyboard view
    func sendKeyPress(keyCode: UInt16) {
        let message = InputMessage.keyPress(keyCode: keyCode, modifiers: cursorState.modifierArray)
        delegate?.gestureController(self, didGenerateInput: message)

        // Clear modifiers after key press (like TeamViewer)
        cursorState.clearModifiers()
    }

    func sendText(_ text: String) {
        let message = InputMessage.text(characters: text)
        delegate?.gestureController(self, didGenerateInput: message)
    }
}
```

**Step 3: Verify it compiles**

Open Xcode, build (Cmd+B)
Expected: Build Succeeded

**Step 4: Commit**

```bash
git add ScreenToScreenClient/Sources/Gestures/
git commit -m "feat(client): add gesture controller for mouse and keyboard input"
```

---

### Task 16: Implement SpecialKeyboardView

**Files:**
- Create: `ScreenToScreenClient/Sources/Views/SpecialKeyboardView.swift`

**Step 1: Create SpecialKeyboardView.swift**

```swift
import SwiftUI

struct SpecialKeyboardView: View {
    @ObservedObject var cursorState: CursorState
    let onKeyPress: (UInt16) -> Void
    let onTextInput: (String) -> Void

    @State private var showingTextInput = false

    // macOS key codes
    private let escKeyCode: UInt16 = 53
    private let tabKeyCode: UInt16 = 48
    private let deleteKeyCode: UInt16 = 51
    private let homeKeyCode: UInt16 = 115
    private let endKeyCode: UInt16 = 119
    private let pageUpKeyCode: UInt16 = 116
    private let pageDownKeyCode: UInt16 = 121
    private let leftArrowKeyCode: UInt16 = 123
    private let rightArrowKeyCode: UInt16 = 124
    private let upArrowKeyCode: UInt16 = 126
    private let downArrowKeyCode: UInt16 = 125

    // F-key codes (F1 = 122, F2 = 120, etc. - macOS uses non-sequential codes)
    private let fKeyCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    var body: some View {
        VStack(spacing: 8) {
            // Row 1: Esc + F-keys
            HStack(spacing: 4) {
                KeyButton(label: "Esc", isActive: false) {
                    onKeyPress(escKeyCode)
                }

                ForEach(1...12, id: \.self) { i in
                    KeyButton(label: "F\(i)", isActive: false) {
                        onKeyPress(fKeyCodes[i - 1])
                    }
                }
            }

            // Row 2: Modifiers + Arrows
            HStack(spacing: 4) {
                ModifierButton(label: "⌘", modifier: "cmd", cursorState: cursorState)
                ModifierButton(label: "⌥", modifier: "alt", cursorState: cursorState)
                ModifierButton(label: "⌃", modifier: "ctrl", cursorState: cursorState)
                ModifierButton(label: "⇧", modifier: "shift", cursorState: cursorState)

                Spacer().frame(width: 20)

                KeyButton(label: "←", isActive: false) {
                    onKeyPress(leftArrowKeyCode)
                }
                KeyButton(label: "→", isActive: false) {
                    onKeyPress(rightArrowKeyCode)
                }
                KeyButton(label: "↑", isActive: false) {
                    onKeyPress(upArrowKeyCode)
                }
                KeyButton(label: "↓", isActive: false) {
                    onKeyPress(downArrowKeyCode)
                }
            }

            // Row 3: Navigation keys + keyboard toggle
            HStack(spacing: 4) {
                KeyButton(label: "Tab", isActive: false) {
                    onKeyPress(tabKeyCode)
                }
                KeyButton(label: "Del", isActive: false) {
                    onKeyPress(deleteKeyCode)
                }
                KeyButton(label: "Home", isActive: false) {
                    onKeyPress(homeKeyCode)
                }
                KeyButton(label: "End", isActive: false) {
                    onKeyPress(endKeyCode)
                }
                KeyButton(label: "PgUp", isActive: false) {
                    onKeyPress(pageUpKeyCode)
                }
                KeyButton(label: "PgDn", isActive: false) {
                    onKeyPress(pageDownKeyCode)
                }

                Spacer()

                Button(action: { showingTextInput = true }) {
                    Image(systemName: "keyboard")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 40)
                        .background(Color.blue)
                        .cornerRadius(6)
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .sheet(isPresented: $showingTextInput) {
            TextInputView(onSubmit: { text in
                onTextInput(text)
                showingTextInput = false
            })
        }
    }
}

struct KeyButton: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(minWidth: 35, minHeight: 35)
                .background(isActive ? Color.blue : Color.gray.opacity(0.6))
                .cornerRadius(6)
        }
    }
}

struct ModifierButton: View {
    let label: String
    let modifier: String
    @ObservedObject var cursorState: CursorState

    var isActive: Bool {
        cursorState.activeModifiers.contains(modifier)
    }

    var body: some View {
        Button(action: { cursorState.toggleModifier(modifier) }) {
            Text(label)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 45, height: 40)
                .background(isActive ? Color.blue : Color.gray.opacity(0.6))
                .cornerRadius(6)
        }
    }
}

struct TextInputView: View {
    @State private var text = ""
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack {
                TextField("Type text to send...", text: $text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                Button("Send") {
                    if !text.isEmpty {
                        onSubmit(text)
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .navigationTitle("Text Input")
            .navigationBarItems(trailing: Button("Cancel") { dismiss() })
        }
    }
}
```

**Step 2: Verify it compiles**

Open Xcode, build (Cmd+B)
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add ScreenToScreenClient/Sources/Views/SpecialKeyboardView.swift
git commit -m "feat(client): add special keyboard view with modifiers and F-keys"
```

---

### Task 17: Implement HostListView

**Files:**
- Create: `ScreenToScreenClient/Sources/Views/HostListView.swift`

**Step 1: Create HostListView.swift**

```swift
import SwiftUI

struct HostListView: View {
    @StateObject private var browser = BonjourBrowser()
    @State private var selectedHost: HostInfo?
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            Group {
                if browser.discoveredHosts.isEmpty {
                    VStack(spacing: 20) {
                        if browser.isSearching {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Searching for Macs...")
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "display.trianglebadge.exclamationmark")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No Macs found")
                                .font(.headline)
                            Text("Make sure Screen2Screen Host is running on your Mac")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                } else {
                    List(browser.discoveredHosts) { host in
                        Button(action: { selectedHost = host }) {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                    .font(.title2)
                                    .foregroundColor(.blue)

                                VStack(alignment: .leading) {
                                    Text(host.name)
                                        .font(.headline)
                                    Text(host.host)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle("Screen2Screen")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .fullScreenCover(item: $selectedHost) { host in
                RemoteSessionView(host: host, onDisconnect: {
                    selectedHost = nil
                })
            }
        }
        .onAppear {
            browser.startBrowsing()
        }
        .onDisappear {
            browser.stopBrowsing()
        }
    }

    private func refresh() {
        browser.discoveredHosts.removeAll()
        browser.stopBrowsing()
        browser.startBrowsing()
    }
}
```

**Step 2: Verify it compiles**

Open Xcode, build (Cmd+B)
Expected: Build Succeeded (will have error until RemoteSessionView is created)

**Step 3: Commit**

```bash
git add ScreenToScreenClient/Sources/Views/HostListView.swift
git commit -m "feat(client): add host list view with Bonjour discovery"
```

---

### Task 18: Implement RemoteSessionView

**Files:**
- Create: `ScreenToScreenClient/Sources/Views/RemoteSessionView.swift`

**Step 1: Create RemoteSessionView.swift**

```swift
import SwiftUI
import WebRTC
import Shared

struct RemoteSessionView: View {
    let host: HostInfo
    let onDisconnect: () -> Void

    @StateObject private var viewModel: RemoteSessionViewModel
    @State private var showKeyboard = false
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    init(host: HostInfo, onDisconnect: @escaping () -> Void) {
        self.host = host
        self.onDisconnect = onDisconnect
        _viewModel = StateObject(wrappedValue: RemoteSessionViewModel(host: host))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video view with gestures
            GeometryReader { geometry in
                ZStack {
                    if let videoTrack = viewModel.videoTrack {
                        VideoRenderView(videoTrack: videoTrack)
                            .scaleEffect(scale)
                            .offset(offset)

                        // Gesture overlay for UIKit gesture handling
                        GestureOverlayView(gestureController: viewModel.gestureController)
                            .allowsHitTesting(!showKeyboard) // Disable when keyboard shown
                    } else {
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text(viewModel.connectionStatus)
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1.0, min(value, 5.0))
                        }
                        .onEnded { _ in
                            if scale < 1.1 {
                                withAnimation {
                                    scale = 1.0
                                    offset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    scale > 1.0 ?
                    DragGesture()
                        .onChanged { value in
                            offset = value.translation
                        }
                    : nil
                )
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 12) {
                        Button(action: { showKeyboard.toggle() }) {
                            Image(systemName: showKeyboard ? "keyboard.fill" : "keyboard")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }

                        Button(action: disconnect) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    .padding()
                }
                .overlay(alignment: .bottom) {
                    if showKeyboard {
                        SpecialKeyboardView(
                            cursorState: viewModel.cursorState,
                            onKeyPress: { keyCode in
                                viewModel.gestureController.sendKeyPress(keyCode: keyCode)
                            },
                            onTextInput: { text in
                                viewModel.gestureController.sendText(text)
                            }
                        )
                        .padding()
                        .transition(.move(edge: .bottom))
                    }
                }
            }
            .onAppear {
                setupGestureView()
            }
        }
        .statusBar(hidden: true)
        .persistentSystemOverlays(.hidden)
    }

    private func setupGestureView() {
        // Gestures are set up via UIViewRepresentable in a real implementation
        // For this SwiftUI version, we use native gestures
        viewModel.connect()
    }

    private func disconnect() {
        viewModel.disconnect()
        onDisconnect()
    }
}

@MainActor
final class RemoteSessionViewModel: ObservableObject {
    @Published var videoTrack: RTCVideoTrack?
    @Published var connectionStatus = "Connecting..."

    let cursorState = CursorState()
    let gestureController: GestureController

    private let host: HostInfo
    private let signalingClient: SignalingClient
    private let webRTCClient: WebRTCClient

    init(host: HostInfo) {
        self.host = host
        self.signalingClient = SignalingClient()
        self.webRTCClient = WebRTCClient()
        self.gestureController = GestureController(cursorState: cursorState)

        signalingClient.delegate = self
        webRTCClient.delegate = self
        gestureController.delegate = self
    }

    func connect() {
        connectionStatus = "Connecting to \(host.name)..."
        signalingClient.connect(to: host)
    }

    func disconnect() {
        webRTCClient.disconnect()
        signalingClient.disconnect()
    }
}

extension RemoteSessionViewModel: SignalingClientDelegate {
    nonisolated func signalingClientDidConnect() {
        Task { @MainActor in
            connectionStatus = "Negotiating WebRTC..."
            webRTCClient.setupPeerConnection()
            webRTCClient.createOffer()
        }
    }

    nonisolated func signalingClientDidDisconnect() {
        Task { @MainActor in
            connectionStatus = "Disconnected"
            videoTrack = nil
        }
    }

    nonisolated func signalingClient(_ client: SignalingClient, didReceiveAnswer sdp: String) {
        Task { @MainActor in
            webRTCClient.handleAnswer(sdp: sdp)
        }
    }

    nonisolated func signalingClient(_ client: SignalingClient, didReceiveIceCandidate candidate: String, sdpMLineIndex: Int32, sdpMid: String?) {
        Task { @MainActor in
            webRTCClient.handleIceCandidate(candidate: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        }
    }

    nonisolated func signalingClient(_ client: SignalingClient, didReceiveScreenInfo width: Int, height: Int, scale: Double) {
        Task { @MainActor in
            print("Remote screen: \(width)x\(height) @\(scale)x")
        }
    }
}

extension RemoteSessionViewModel: WebRTCClientDelegate {
    nonisolated func webRTCClient(_ client: WebRTCClient, didGenerateOffer sdp: String) {
        Task { @MainActor in
            signalingClient.send(.offer(sdp: sdp))
        }
    }

    nonisolated func webRTCClient(_ client: WebRTCClient, didGenerateIceCandidate candidate: RTCIceCandidate) {
        Task { @MainActor in
            signalingClient.send(.ice(candidate: candidate.sdp, sdpMLineIndex: candidate.sdpMLineIndex, sdpMid: candidate.sdpMid))
        }
    }

    nonisolated func webRTCClient(_ client: WebRTCClient, didReceiveVideoTrack track: RTCVideoTrack) {
        Task { @MainActor in
            videoTrack = track
            connectionStatus = "Connected"
        }
    }

    nonisolated func webRTCClientDidConnect(_ client: WebRTCClient) {
        Task { @MainActor in
            connectionStatus = "Connected"
        }
    }

    nonisolated func webRTCClientDidDisconnect(_ client: WebRTCClient) {
        Task { @MainActor in
            connectionStatus = "Disconnected"
            videoTrack = nil
        }
    }
}

extension RemoteSessionViewModel: GestureControllerDelegate {
    nonisolated func gestureController(_ controller: GestureController, didGenerateInput message: InputMessage) {
        Task { @MainActor in
            webRTCClient.sendInput(message)
        }
    }
}
```

**Step 2: Verify it compiles**

Open Xcode, build (Cmd+B)
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add ScreenToScreenClient/Sources/Views/RemoteSessionView.swift
git commit -m "feat(client): add remote session view with video, gestures, and keyboard"
```

---

### Task 19: Add UIKit Gesture Integration

**Files:**
- Create: `ScreenToScreenClient/Sources/Views/GestureOverlayView.swift`

**Step 1: Create GestureOverlayView.swift**

This UIViewRepresentable provides proper UIKit gesture handling:

```swift
import SwiftUI
import UIKit
import Shared

struct GestureOverlayView: UIViewRepresentable {
    let gestureController: GestureController

    func makeUIView(context: Context) -> GestureOverlayUIView {
        let view = GestureOverlayUIView()
        gestureController.setupGestures(on: view)
        return view
    }

    func updateUIView(_ uiView: GestureOverlayUIView, context: Context) {}
}

class GestureOverlayUIView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

**Step 2: Verify it compiles**

Open Xcode, build (Cmd+B)
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add ScreenToScreenClient/Sources/Views/GestureOverlayView.swift
git commit -m "feat(client): add UIKit gesture overlay for proper touch handling"
```

---

## Phase 4: Testing & Refinement

### Task 20: End-to-End Testing

**Step 1: Build both applications**

```bash
# In Xcode, build ScreenToScreenHost for macOS
# In Xcode, build ScreenToScreenClient for iOS simulator or device
```

**Step 2: Run macOS host**

1. Launch ScreenToScreenHost
2. Grant Screen Recording permission when prompted
3. Verify menu bar icon appears
4. Verify status shows "Ready - Waiting for connection"

**Step 3: Run iOS client**

1. Launch ScreenToScreenClient on device (same network)
2. Verify host appears in list
3. Tap to connect
4. Verify video stream appears
5. Test gestures:
   - Drag to move cursor
   - Tap to click
   - Two-finger tap for right click
   - Pinch to zoom

**Step 4: Test keyboard**

1. Tap keyboard icon
2. Test modifier keys (toggle behavior)
3. Test F-keys
4. Test arrow keys
5. Test text input

**Step 5: Document any issues**

Create issues for bugs found during testing.

**Step 6: Commit any fixes**

```bash
git add -A
git commit -m "fix: address issues found during e2e testing"
```

---

## Summary

### Total Tasks: 20

### Phase 1: Project Setup (Tasks 1-2)
- Shared Swift package with message types
- WebRTC framework setup

### Phase 2: macOS Host (Tasks 3-9)
- Xcode project
- BonjourAdvertiser
- SignalingServer
- ScreenCaptureService
- InputController
- WebRTCManager
- AppDelegate wiring

### Phase 3: iOS Client (Tasks 10-19)
- Xcode project
- BonjourBrowser
- SignalingClient
- WebRTCClient
- VideoRenderView
- GestureController
- SpecialKeyboardView
- HostListView
- RemoteSessionView
- Gesture integration

### Phase 4: Testing (Task 20)
- End-to-end testing
- Bug fixes

### Dependencies
- WebRTC.xcframework (prebuilt, M131 or later)
- macOS 12.3+ (ScreenCaptureKit)
- iOS 15.0+
- Xcode 15+

### Future Phases (documented in design)
- Cross-network support (STUN/TURN)
- Audio streaming
- Authentication/pairing
