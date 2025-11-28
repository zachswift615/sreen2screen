# Screen2Screen Handoff Document

**Date:** 2025-11-27
**Repository:** git@github.com:zachswift615/sreen2screen.git
**Branch:** main
**Latest Commit:** 26a7505 (feat(client): add UIKit gesture overlay for proper touch handling)

---

<original_task>
Build a TeamViewer-like remote desktop application with:
- **macOS Host App** (Swift/AppKit): Menu bar app that captures screen via ScreenCaptureKit, streams H.264 over WebRTC, receives input commands via DataChannel
- **iOS Client App** (Swift/SwiftUI): Discovers hosts via Bonjour, renders video with Metal, sends gestures/keyboard input over WebRTC DataChannel

Key features requested:
- Relative cursor movement (drag to move cursor like TeamViewer)
- Tap to click, two-finger tap for right-click
- Pinch to zoom (client-side)
- Special keyboard with modifiers (Cmd/Ctrl/Alt/Shift), F-keys, arrows, navigation keys
- Auto-discovery via Bonjour on local network
- Clear path for future cross-network support (TURN/STUN)
- Monitor selector for multi-display support
- Audio streaming deferred to future phase
</original_task>

<work_completed>
## Design Phase (Complete)
- **Design Document:** `docs/plans/2025-11-27-screen2screen-design.md`
  - Full architecture diagrams
  - Technology choices documented (WebRTC, ScreenCaptureKit, Metal, CGEvent)
  - Communication protocol defined (length-prefixed JSON over TCP for signaling, WebRTC DataChannel for input)
  - Future cross-network path documented

- **Implementation Plan:** `docs/plans/2025-11-27-screen2screen-implementation.md`
  - 20 bite-sized tasks
  - Code reviewed and fixes applied before execution

## Implementation Phase (Tasks 1-19 Complete)

### Shared Package (Task 1)
- `Shared/Package.swift` - Swift Package for shared code
- `Shared/Sources/Shared/Constants.swift` - Service type, port, frame rate
- `Shared/Sources/Shared/InputMessage.swift` - Mouse/keyboard message types
- `Shared/Sources/Shared/SignalingMessage.swift` - WebRTC signaling messages

### WebRTC Framework (Task 2)
- `WebRTC/WebRTC.xcframework/` - M141 prebuilt from stasel/WebRTC
- Supports: iOS arm64, iOS Simulator (x86_64 + arm64), macOS (x86_64 + arm64), Mac Catalyst

### macOS Host App (Tasks 3-9)
- `ScreenToScreenHost/ScreenToScreenHost.xcodeproj/` - Created via xcodeproj gem
- `ScreenToScreenHost/Sources/App/AppDelegate.swift` - Menu bar app, wires all services
- `ScreenToScreenHost/Sources/App/ScreenToScreenHost.entitlements` - Network permissions, sandbox disabled
- `ScreenToScreenHost/Resources/Info.plist` - LSUIElement=YES, screen capture description
- `ScreenToScreenHost/Sources/Services/SignalingServer.swift` - TCP server with integrated Bonjour advertising
- `ScreenToScreenHost/Sources/Services/ScreenCaptureService.swift` - SCStream capture with display selector
- `ScreenToScreenHost/Sources/Services/InputController.swift` - CGEvent injection for mouse/keyboard
- `ScreenToScreenHost/Sources/Services/WebRTCManager.swift` - Video streaming, DataChannel reception

### iOS Client App (Tasks 10-19)
- `ScreenToScreenClient/ScreenToScreenClient.xcodeproj/` - Created via xcodeproj gem
- `ScreenToScreenClient/Sources/App/ScreenToScreenApp.swift` - SwiftUI entry point
- `ScreenToScreenClient/Resources/Info.plist` - Bonjour services, local network permission
- `ScreenToScreenClient/Sources/Models/HostInfo.swift` - Discovered host model
- `ScreenToScreenClient/Sources/Services/BonjourBrowser.swift` - NWBrowser-based discovery
- `ScreenToScreenClient/Sources/Services/SignalingClient.swift` - TCP client for signaling
- `ScreenToScreenClient/Sources/Services/WebRTCClient.swift` - Video receiving, input sending
- `ScreenToScreenClient/Sources/Views/VideoRenderView.swift` - RTCMTLVideoView wrapper
- `ScreenToScreenClient/Sources/Views/HostListView.swift` - Discovery UI with host list
- `ScreenToScreenClient/Sources/Views/RemoteSessionView.swift` - Main session view + ViewModel
- `ScreenToScreenClient/Sources/Views/SpecialKeyboardView.swift` - F-keys, modifiers, arrows
- `ScreenToScreenClient/Sources/Views/GestureOverlayView.swift` - UIKit gesture integration
- `ScreenToScreenClient/Sources/Gestures/CursorState.swift` - Modifier key state
- `ScreenToScreenClient/Sources/Gestures/GestureController.swift` - Pan, tap, pinch handlers

## Git History (18 commits)
```
26a7505 feat(client): add UIKit gesture overlay for proper touch handling
9569c7b feat(client): add remote session view with video, gestures, and keyboard
8295c11 feat(client): add host list view with Bonjour discovery
3b99c9a feat(client): add special keyboard view with modifiers and F-keys
15bd638 feat(client): add gesture controller for mouse and keyboard input
d472e8d feat(client): add Metal-backed video render view
1e321e8 feat(client): add WebRTC client for video receiving and input sending
c87107d feat(client): add signaling client for WebRTC negotiation
047930b feat(client): add Bonjour browser for host discovery
ad70385 feat: create iOS client Xcode project skeleton
69136a0 feat(host): wire up all services in AppDelegate
ed5965f feat(host): add WebRTC manager for video streaming and data channel
e816a32 feat(host): add CGEvent-based input controller
156819d feat(host): add ScreenCaptureKit service with display selection
80dac8c feat: implement SignalingServer with integrated Bonjour advertising
e29aff6 feat: create macOS host Xcode project skeleton
ec4dacc Add WebRTC M141 xcframework
188fc3c feat: add shared Swift package with message types
```

All changes pushed to GitHub.
</work_completed>

<work_remaining>
## Task 20: End-to-End Testing (NOT STARTED)

### Pre-requisites (User must do in Xcode)
1. **Open both Xcode projects** and configure:
   - Add `Shared` package as local dependency to both projects
   - Add `WebRTC.xcframework` to both projects (embed & sign)
   - Set development team for signing
   - For macOS: May need to enable "Hardened Runtime" or adjust entitlements

2. **macOS Host Setup:**
   - Build and run `ScreenToScreenHost`
   - Grant Screen Recording permission when prompted (System Preferences > Privacy > Screen Recording)
   - Verify menu bar icon appears with "Ready - Waiting for connection" status

3. **iOS Client Setup:**
   - Build and run `ScreenToScreenClient` on physical device (same network as Mac)
   - Grant Local Network permission when prompted

### Testing Steps
1. **Discovery Test:**
   - Verify iOS app shows Mac in host list
   - Tap to connect

2. **Video Streaming Test:**
   - Verify video stream appears on iOS
   - Check latency is acceptable

3. **Gesture Tests:**
   - Drag finger → cursor moves on Mac (relative movement)
   - Single tap → left click
   - Double tap → double click
   - Two-finger tap → right click
   - Two-finger drag → scroll
   - Pinch → zoom (client-side only)

4. **Keyboard Tests:**
   - Tap keyboard icon to show special keyboard
   - Test modifier toggles (Cmd, Ctrl, Alt, Shift)
   - Test F-keys (F1-F12)
   - Test arrow keys
   - Test navigation keys (Home, End, PgUp, PgDn)
   - Test text input via keyboard button

5. **Multi-Monitor Test:**
   - If multiple displays, test display selector in menu bar

### Known Issues to Watch For
- WebRTC video source delegate pattern may need adjustment if video doesn't display
- Coordinate system differences if cursor movement seems inverted
- Screen scale factor issues on non-Retina displays

### After Testing
- Document any bugs found
- Create GitHub issues for fixes needed
- If all tests pass, project is ready for use
</work_remaining>

<attempted_approaches>
## Code Review Fixes Applied
The implementation plan was reviewed before execution and these issues were identified and fixed:

1. **WebRTC Video Source (FIXED):** Original code created new `RTCVideoCapturer()` on every frame. Fixed to use `videoSource.delegate?.capturer?()` pattern.

2. **Coordinate System (FIXED):** Original InputController flipped Y coordinates incorrectly. Fixed to use CGEvent consistently without coordinate transformation.

3. **Port Conflict (FIXED):** Original design had separate BonjourAdvertiser and SignalingServer both trying to listen on port 8080. Fixed by integrating Bonjour advertising into SignalingServer via `listener.service`.

4. **GestureOverlayView (FIXED):** Was missing from RemoteSessionView. Added to ZStack with proper hit testing.

5. **Display Scale (FIXED):** Was hardcoded as 2.0. Fixed to use `NSScreen.main?.backingScaleFactor`.

6. **Force Unwrap (FIXED):** BonjourBrowser had `self!` - fixed to `guard let self = self`.

7. **Import Location (FIXED):** ScreenCaptureKit import was at end of file - moved to top.

## WebRTC Source Selection
- Original plan referenced `nicothin/nicothin-webrtc-build` - repo not found (404)
- Successfully used `stasel/WebRTC` M141 release instead
</attempted_approaches>

<critical_context>
## Architecture Decisions

1. **WebRTC for Streaming:** Chosen over simpler MJPEG for performance and future cross-network support. Hardware H.264 encoding via VideoToolbox.

2. **Length-Prefixed TCP for Signaling:** Not actual WebSocket - simpler custom protocol with 4-byte big-endian length prefix + JSON body.

3. **Bonjour Service Type:** `_screencast._tcp` on port 8080

4. **Input Protocol:** JSON over WebRTC DataChannel:
   - `mouseMove` with dx/dy (relative, not absolute)
   - `click` with button and count
   - `keyPress`/`keyDown`/`keyUp` with keyCode and modifiers array
   - `text` for bulk text input

5. **macOS Key Codes:** F-keys use non-sequential codes (F1=122, F2=120, etc.)

## Important Files
- **Design Doc:** `docs/plans/2025-11-27-screen2screen-design.md`
- **Implementation Plan:** `docs/plans/2025-11-27-screen2screen-implementation.md`
- Both contain complete architecture details and future roadmap

## Future Phases (Documented in Design)
- **Cross-Network:** Add STUN/TURN servers, external signaling server, device pairing
- **Audio:** Add audio track via ScreenCaptureKit's `capturesAudio` + RTCAudioTrack

## Requirements
- macOS 12.3+ (ScreenCaptureKit requirement)
- iOS 15.0+
- Xcode 15+
- Same local network for host and client
</critical_context>

<current_state>
## Completion Status
- **Tasks 1-19:** COMPLETE (all code written and committed)
- **Task 20 (E2E Testing):** NOT STARTED

## What's Finalized
- All source code files written per implementation plan
- All commits pushed to GitHub remote
- Design and implementation documentation complete

## What Needs User Intervention
1. **Xcode Project Configuration:**
   - Both projects were created via xcodeproj gem
   - User needs to open in Xcode and:
     - Add Shared package dependency
     - Add WebRTC.xcframework (embed & sign)
     - Set development team
     - Potentially adjust build settings

2. **Testing:**
   - Run macOS host app
   - Grant screen recording permission
   - Run iOS client on physical device
   - Test all features per Task 20

## Open Questions
- Will the xcodeproj-generated projects build correctly, or need manual Xcode adjustments?
- Does WebRTC M141 work correctly with the delegate pattern used for video frames?
- Any Swift 6 concurrency issues with the nonisolated delegate methods?

## Repository State
- Clean working tree
- All changes committed and pushed
- Ready for Xcode build and testing
</current_state>
