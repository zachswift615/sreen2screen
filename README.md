# Screen2Screen

A TeamViewer-like remote desktop application for macOS and iOS. Control your Mac from your iPhone or iPad over local network.

## Features

- **Real-time Screen Streaming** - Low-latency H.264 video via WebRTC
- **Full Mouse Control** - Drag to move cursor, tap to click, two-finger tap for right-click
- **Keyboard Input** - Special keyboard with modifiers, F-keys, arrows, and navigation keys
- **Auto-Discovery** - Finds Macs automatically via Bonjour (no IP configuration needed)
- **Multi-Monitor Support** - Select which display to share
- **Pinch to Zoom** - Zoom in on remote screen for precision work

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      LOCAL NETWORK                               │
│                                                                  │
│  ┌──────────────────────┐          ┌──────────────────────┐     │
│  │   macOS Host App     │          │    iOS Client App    │     │
│  │   (Swift/AppKit)     │◄────────►│   (Swift/SwiftUI)    │     │
│  │                      │  WebRTC  │                      │     │
│  │ ┌──────────────────┐ │          │ ┌──────────────────┐ │     │
│  │ │ ScreenCaptureKit │ │  Video   │ │  WebRTC Decoder  │ │     │
│  │ │ → H.264 Encoder  │─┼─────────►│ │  → Metal Render  │ │     │
│  │ └──────────────────┘ │          │ └──────────────────┘ │     │
│  │                      │          │                      │     │
│  │ ┌──────────────────┐ │  Data    │ ┌──────────────────┐ │     │
│  │ │  Input Receiver  │◄┼──────────┼─│  Gesture Engine  │ │     │
│  │ │ (mouse/keyboard) │ │ Channel  │ │  + Virtual KB    │ │     │
│  │ └──────────────────┘ │          │ └──────────────────┘ │     │
│  └──────────────────────┘          └──────────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

## Requirements

- **macOS Host:** macOS 12.3+ (Monterey)
- **iOS Client:** iOS 15.0+
- **Xcode:** 15.0+
- **Network:** Both devices on same local network

## Project Structure

```
screen2screen/
├── Shared/                         # Shared Swift Package
│   └── Sources/Shared/
│       ├── Constants.swift         # Service config
│       ├── InputMessage.swift      # Mouse/keyboard messages
│       └── SignalingMessage.swift  # WebRTC signaling
│
├── ScreenToScreenHost/             # macOS Menu Bar App
│   └── Sources/
│       ├── App/
│       │   └── AppDelegate.swift   # App entry, service wiring
│       └── Services/
│           ├── SignalingServer.swift    # TCP + Bonjour
│           ├── ScreenCaptureService.swift
│           ├── WebRTCManager.swift
│           └── InputController.swift
│
├── ScreenToScreenClient/           # iOS App
│   └── Sources/
│       ├── App/
│       │   └── ScreenToScreenApp.swift
│       ├── Views/
│       │   ├── HostListView.swift
│       │   ├── RemoteSessionView.swift
│       │   ├── VideoRenderView.swift
│       │   ├── SpecialKeyboardView.swift
│       │   └── GestureOverlayView.swift
│       ├── Services/
│       │   ├── BonjourBrowser.swift
│       │   ├── SignalingClient.swift
│       │   └── WebRTCClient.swift
│       └── Gestures/
│           ├── GestureController.swift
│           └── CursorState.swift
│
├── WebRTC/                         # Prebuilt WebRTC.xcframework
└── docs/plans/                     # Design & implementation docs
```

## Setup

### 1. Clone the Repository

```bash
git clone git@github.com:zachswift615/sreen2screen.git
cd sreen2screen
```

### 2. Open in Xcode

Open both Xcode projects:
- `ScreenToScreenHost/ScreenToScreenHost.xcodeproj` (macOS)
- `ScreenToScreenClient/ScreenToScreenClient.xcodeproj` (iOS)

### 3. Add Dependencies

For **both** projects:

1. **Add Shared Package:**
   - File → Add Package Dependencies → Add Local
   - Select the `Shared/` directory

2. **Add WebRTC Framework:**
   - Drag `WebRTC/WebRTC.xcframework` into the project
   - Ensure "Embed & Sign" is selected

3. **Set Development Team:**
   - Select your team in Signing & Capabilities

### 4. Build & Run

**macOS Host:**
1. Build and run `ScreenToScreenHost`
2. Grant Screen Recording permission when prompted
3. Look for the display icon in your menu bar

**iOS Client:**
1. Build and run `ScreenToScreenClient` on a physical device
2. Grant Local Network permission when prompted
3. Your Mac should appear in the host list

## Usage

### Gestures

| Gesture | Action |
|---------|--------|
| 1-finger drag | Move cursor |
| 1-finger tap | Left click |
| 1-finger double-tap | Double click |
| 2-finger tap | Right click |
| 2-finger drag | Scroll |
| Pinch | Zoom (client-side) |

### Special Keyboard

Tap the keyboard icon to access:
- **Modifier Keys:** ⌘ ⌥ ⌃ ⇧ (toggle, stay active until next key)
- **Function Keys:** F1-F12
- **Arrow Keys:** ← → ↑ ↓
- **Navigation:** Tab, Delete, Home, End, Page Up, Page Down
- **Text Input:** Tap keyboard button for full text entry

### Multi-Monitor

If your Mac has multiple displays:
1. Click the Screen2Screen menu bar icon
2. Select "Select Display"
3. Choose the display to share

## Technology Stack

| Component | Technology |
|-----------|------------|
| Video Streaming | WebRTC with H.264 (VideoToolbox) |
| Screen Capture | ScreenCaptureKit |
| Video Rendering | Metal (RTCMTLVideoView) |
| Input Injection | CGEvent |
| Discovery | Bonjour/mDNS |
| Signaling | Length-prefixed TCP (port 8080) |
| Input Transport | WebRTC DataChannel |

## Future Roadmap

### Phase 2: Cross-Network Support
- STUN/TURN server integration
- External signaling server
- Device pairing with codes
- End-to-end encryption

### Phase 3: Audio Streaming
- System audio capture via ScreenCaptureKit
- WebRTC audio track
- Volume controls

## Troubleshooting

### Mac not appearing in host list
- Ensure both devices are on the same network
- Check that Screen2Screen Host is running (menu bar icon visible)
- Try refreshing the host list in the iOS app

### Video not displaying
- Verify Screen Recording permission is granted
- Check Console.app for WebRTC errors
- Ensure WebRTC.xcframework is properly embedded

### Cursor movement feels wrong
- Adjust sensitivity in GestureController (default: 1.5x)
- Ensure you're using relative movement (drag), not absolute

### Permission prompts not appearing
- Reset permissions: `tccutil reset ScreenCapture com.screen2screen.host`
- Rebuild and run the app

## License

MIT

## Acknowledgments

- [WebRTC](https://webrtc.org/) - Real-time communication
- [stasel/WebRTC](https://github.com/stasel/WebRTC) - Prebuilt iOS/macOS frameworks
- Inspired by TeamViewer's gesture-based remote control
