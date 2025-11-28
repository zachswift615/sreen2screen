# Screen2Screen Design Document

**Date:** 2025-11-27
**Status:** Approved
**Scope:** Local network remote desktop (iOS client → macOS host)

## Overview

Screen2Screen is a TeamViewer-like remote desktop application allowing an iOS device to view and control a macOS computer. Phase 1 targets local network connectivity with a clear architectural path to cross-network support.

## Requirements

### Functional Requirements
- View macOS screen from iOS device in real-time
- Control macOS cursor via touch gestures (relative movement)
- Full gesture support: drag, tap, two-finger tap, pinch zoom
- Special keyboard with modifiers (Cmd/Ctrl/Alt/Shift), F-keys, arrows, navigation keys
- Auto-discovery of hosts on local network via Bonjour

### Non-Functional Requirements
- **Performance first** - Low latency streaming (target <50ms)
- Hardware-accelerated encoding/decoding
- Minimal CPU usage on both devices

### Constraints
- macOS host only (no Windows/Linux)
- Local network only for Phase 1
- Requires Screen Recording permission on macOS

## Architecture

### High-Level Overview

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
│  │                      │          │                      │     │
│  │ ┌──────────────────┐ │ Bonjour  │ ┌──────────────────┐ │     │
│  │ │ Service Advertise│◄┼──────────┼─│ Service Discovery│ │     │
│  │ └──────────────────┘ │          │ └──────────────────┘ │     │
│  └──────────────────────┘          └──────────────────────┘     │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Signaling (WebSocket on Host)                │   │
│  │         For WebRTC offer/answer/ICE exchange              │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Technology Choices

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Streaming | WebRTC (libwebrtc) | Battle-tested, hardware encoding, NAT traversal for future |
| Video Codec | H.264 via VideoToolbox | Hardware accelerated on both platforms |
| Screen Capture | ScreenCaptureKit | Modern macOS API, efficient, privacy-aware |
| Input Injection | CGEvent | Low-level, works system-wide, all key combos |
| Video Rendering | Metal (MTKView) | Lowest latency display on iOS |
| Discovery | Bonjour/mDNS | Native Apple, zero-config networking |
| Signaling | WebSocket (local) | Simple, no external server needed |

## macOS Host Application

### Components

```
┌─────────────────────────────────────────────────────────────────┐
│                     macOS Host App                               │
├─────────────────────────────────────────────────────────────────┤
│  Menu Bar App (NSStatusItem)                                     │
│  - Background operation                                          │
│  - Connection status indicator                                   │
│  - Preferences access                                            │
├─────────────────────────────────────────────────────────────────┤
│  Core Services:                                                  │
│  - BonjourAdvertiser: Publishes _screencast._tcp service        │
│  - SignalingServer: WebSocket on :8080 for SDP/ICE exchange     │
│  - ScreenCaptureService: SCStream → CMSampleBuffer at 30-60 FPS │
│  - WebRTCManager: RTCPeerConnection, video track, data channel  │
│  - InputController: Translates messages → CGEvent posting       │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow
1. ScreenCaptureKit delivers CMSampleBuffer at 30-60 FPS
2. WebRTC encodes to H.264 using VideoToolbox (hardware)
3. Streams to iOS client over peer connection
4. Input commands arrive via DataChannel as JSON messages
5. InputController translates to CGEvents and posts them

## iOS Client Application

### Components

```
┌─────────────────────────────────────────────────────────────────┐
│                      iOS Client App                              │
├─────────────────────────────────────────────────────────────────┤
│  UI Layer (SwiftUI):                                             │
│  - HostListView: Bonjour discovery, host selection              │
│  - ConnectingView: Connection progress                          │
│  - RemoteSessionView: Main experience, full screen              │
├─────────────────────────────────────────────────────────────────┤
│  RemoteSessionView Components:                                   │
│  - VideoRenderView (MTKView): Metal rendering, zoom/pan         │
│  - GestureController (UIKit): Pan, tap, pinch recognizers       │
│  - SpecialKeyboardView: Modifiers, F-keys, arrows, navigation   │
├─────────────────────────────────────────────────────────────────┤
│  Core Services:                                                  │
│  - BonjourBrowser: NWBrowser for _screencast._tcp discovery     │
│  - SignalingClient: WebSocket client for SDP/ICE                │
│  - WebRTCClient: RTCPeerConnection, receives video, sends input │
│  - InputMessageEncoder: Gestures → JSON messages                │
└─────────────────────────────────────────────────────────────────┘
```

### Gesture Mapping

| Gesture | Remote Action |
|---------|---------------|
| 1-finger drag | Move cursor (relative) |
| 1-finger tap | Left click |
| 1-finger double-tap | Double click |
| 2-finger tap | Right click |
| 2-finger drag | Scroll |
| Pinch | Zoom view (client-side only) |
| 2-finger double-tap | Reset zoom |

### Special Keyboard Layout

```
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
│ Esc │ F1  │ F2  │ ... │ F11 │ F12 │     │     │
├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│ ⌘   │ ⌥   │ ⌃   │ ⇧   │ ←   │ →   │ ↑   │ ↓   │
├─────┼─────┼─────┼─────┼─────┼─────┴─────┴─────┤
│ Tab │ Del │Home │ End │PgUp │PgDn │           │
└─────┴─────┴─────┴─────┴─────┴─────┴───────────┘
```
- Modifier keys toggle (stay active until clicked again)
- Slides up from bottom on keyboard button tap

## Communication Protocol

### Connection Flow

1. **Discovery:** macOS advertises `_screencast._tcp` via Bonjour
2. **Signaling:** iOS connects to `ws://{host}:8080/signaling`
3. **WebRTC Handshake:**
   - iOS sends SDP offer
   - macOS sends SDP answer
   - Both exchange ICE candidates
4. **Streaming:** Video flows Mac→iOS, input flows iOS→Mac

### DataChannel Message Schema

```swift
// Input messages (iOS → macOS)

// Mouse movement (relative)
{ "type": "mouseMove", "dx": 10, "dy": -5 }

// Mouse clicks
{ "type": "mouseDown", "button": "left" | "right" }
{ "type": "mouseUp", "button": "left" | "right" }
{ "type": "click", "button": "left" | "right", "count": 1 | 2 }

// Scrolling
{ "type": "scroll", "dx": 0, "dy": -120 }

// Keyboard
{ "type": "keyDown", "keyCode": 53, "modifiers": ["cmd", "shift"] }
{ "type": "keyUp", "keyCode": 53, "modifiers": [] }
{ "type": "keyPress", "keyCode": 53, "modifiers": ["cmd"] }

// Text input (for regular typing)
{ "type": "text", "characters": "hello" }

// Control messages (macOS → iOS)

// Screen info (sent on connect)
{ "type": "screenInfo", "width": 2560, "height": 1440, "scale": 2.0 }

// Cursor position (optional)
{ "type": "cursorPos", "x": 500, "y": 300 }
```

## Project Structure

```
screen2screen/
├── ScreenToScreenHost/                 # macOS App
│   ├── ScreenToScreenHost.xcodeproj
│   ├── Sources/
│   │   ├── App/
│   │   │   ├── AppDelegate.swift
│   │   │   ├── StatusBarController.swift
│   │   │   └── PreferencesWindow.swift
│   │   ├── Services/
│   │   │   ├── BonjourAdvertiser.swift
│   │   │   ├── SignalingServer.swift
│   │   │   ├── ScreenCaptureService.swift
│   │   │   ├── WebRTCManager.swift
│   │   │   └── InputController.swift
│   │   ├── Models/
│   │   │   └── InputMessage.swift
│   │   └── Utilities/
│   │       └── Logger.swift
│   └── Resources/
│       └── Assets.xcassets
│
├── ScreenToScreenClient/               # iOS App
│   ├── ScreenToScreenClient.xcodeproj
│   ├── Sources/
│   │   ├── App/
│   │   │   └── ScreenToScreenApp.swift
│   │   ├── Views/
│   │   │   ├── HostListView.swift
│   │   │   ├── ConnectingView.swift
│   │   │   ├── RemoteSessionView.swift
│   │   │   ├── VideoRenderView.swift
│   │   │   └── SpecialKeyboardView.swift
│   │   ├── Services/
│   │   │   ├── BonjourBrowser.swift
│   │   │   ├── SignalingClient.swift
│   │   │   ├── WebRTCClient.swift
│   │   │   └── InputMessageEncoder.swift
│   │   ├── Gestures/
│   │   │   ├── GestureController.swift
│   │   │   └── CursorState.swift
│   │   └── Models/
│   │       ├── InputMessage.swift
│   │       └── HostInfo.swift
│   └── Resources/
│       └── Assets.xcassets
│
├── Shared/                             # Shared SPM package
│   ├── Package.swift
│   └── Sources/Shared/
│       ├── InputMessage.swift
│       ├── SignalingMessage.swift
│       └── Constants.swift
│
├── WebRTC/                             # Prebuilt framework
│   └── WebRTC.xcframework
│
└── docs/plans/
```

## Future: Cross-Network Support

### What Changes

| Aspect | Local (Phase 1) | Remote (Phase 2) |
|--------|-----------------|------------------|
| Signaling | WebSocket on host | External signaling server |
| NAT Traversal | Direct connection | STUN discovery, TURN relay |
| Discovery | Bonjour mDNS | Account system + device registration |
| Security | Network isolation | TLS, device auth, E2E encryption |

### Architecture Decisions Enabling Future

- **WebRTC chosen** - Has STUN/TURN/ICE built in
- **Signaling abstracted** - Can swap local WS for remote server
- **DataChannel for input** - Works over TURN relay
- **Protocol is transport-agnostic**

### Implementation Path

1. **Abstract SignalingService protocol**
   - LocalSignalingService (current WebSocket)
   - RemoteSignalingService (future, same interface)

2. **Add ICE server configuration**
   - Currently: empty (direct connection)
   - Future: STUN/TURN server URLs

3. **Build/deploy relay infrastructure**
   - Signaling server (Node.js/Go)
   - TURN server (coturn)
   - Optional: account system

4. **Add pairing flow**
   - Generate pairing code on Mac
   - Enter code on iOS to link devices

## Dependencies

### macOS Host
- macOS 12.3+ (ScreenCaptureKit requirement)
- WebRTC.xcframework (prebuilt)
- Network.framework (system)
- ScreenCaptureKit.framework (system)

### iOS Client
- iOS 15.0+
- WebRTC.xcframework (prebuilt)
- Network.framework (system)
- MetalKit.framework (system)

### WebRTC Framework
Recommend using prebuilt binaries from:
- https://github.com/nicothin/nicothin-webrtc-build (community builds)
- Or build from source via Google's depot_tools

## Security Considerations (Phase 1)

- Local network provides implicit isolation
- No authentication required (trusted network assumption)
- WebRTC DTLS-SRTP provides encryption of media streams
- DataChannel encrypted via DTLS

## Decisions

1. **Frame rate** - Adaptive based on content/performance
2. **Multi-monitor** - Monitor selector UI (user chooses which display)
3. **Audio** - Phase 1 video-only; audio in future phase (see below)

## Future: Audio Streaming

### Architecture for Audio (Phase 2+)

WebRTC supports audio tracks natively. Adding audio requires:

1. **macOS Host Changes:**
   - Add audio capture via ScreenCaptureKit (SCStreamConfiguration.capturesAudio)
   - Or use CoreAudio tap for system audio
   - Create RTCAudioTrack from captured samples
   - Add audio track to existing peer connection

2. **iOS Client Changes:**
   - Receive audio track (WebRTC handles decoding)
   - Route to device speaker via AVAudioSession
   - Add mute/volume controls to UI

3. **Protocol Addition:**
   ```swift
   // Audio control messages
   { "type": "audioEnabled", "enabled": true }
   { "type": "audioVolume", "level": 0.8 }
   ```

**Why this is straightforward:**
- WebRTC already handles audio codec negotiation (Opus)
- ScreenCaptureKit can capture audio alongside video
- Same peer connection, just add another track
- No signaling changes needed (renegotiation is automatic)
