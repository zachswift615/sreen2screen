# Screen2Screen Handoff Document

**Date:** 2025-11-28
**Repository:** /Users/zachswift/projects/screen2screen
**Branch:** main
**Latest Commit:** `fdc8acf` - feat: major improvements to remote control experience

---

<original_task>
Continue development of the Screen2Screen remote desktop application by:
1. Swapping out the old WebRTC framework (which was crashing during video encoding) with the LiveKit WebRTC framework
2. Implementing pinch-to-zoom with pan-to-follow-cursor behavior
3. Adding low-latency cursor position feedback from host to client
4. Adding multi-monitor support so mouse is constrained to the captured display
</original_task>

<work_completed>
## 1. WebRTC Framework Migration

**Replaced old WebRTC framework with LiveKit WebRTC v137.7151.10:**

- Downloaded `LiveKitWebRTC.xcframework` from `livekit/webrtc-xcframework` releases
- Located at: `/WebRTC/LiveKitWebRTC.xcframework/`
- Removed old `WebRTC.framework` and `WebRTC.xcframework`
- Updated Xcode project references in both Host and Client projects via Ruby script

**Updated all Swift files to use LKRTC-prefixed symbols:**

Files modified:
- `ScreenToScreenHost/Sources/Services/WebRTCManager.swift` - Changed `import WebRTC` to `import LiveKitWebRTC`, all `RTC*` types to `LKRTC*`
- `ScreenToScreenHost/Sources/App/AppDelegate.swift` - Updated import and `RTCIceCandidate` to `LKRTCIceCandidate`
- `ScreenToScreenClient/Sources/Services/WebRTCClient.swift` - Full symbol migration, added decoder for HostMessage
- `ScreenToScreenClient/Sources/Views/VideoRenderView.swift` - `RTCVideoTrack` to `LKRTCVideoTrack`, `RTCMTLVideoView` to `LKRTCMTLVideoView`
- `ScreenToScreenClient/Sources/Views/RemoteSessionView.swift` - Updated all WebRTC types, added display link coalescing

## 2. Pinch-to-Zoom Implementation

**Added UIKit pinch gesture handling in `GestureController.swift`:**

- Added `GestureControllerDelegate` methods for scale updates:
  - `gestureController(_:didUpdateScale:)`
  - `gestureControllerDidEndPinch(_:)`
  - `gestureController(_:didMoveCursorBy:in:)`
- Implemented `handlePinch()` with scale tracking (1.0 to 5.0 range)
- Added `initialPinchScale` and `currentScale` tracking
- Added `setCurrentScale(_:)` method for syncing with SwiftUI
- Reset-to-1x animation when releasing below 1.1x scale

**Updated `RemoteSessionView.swift` ViewModel:**

- Added `@Published var scale: CGFloat = 1.0`
- Added `@Published var panOffset: CGSize = .zero`
- Added `@Published var shouldResetZoom = false`
- Connected gesture controller scale to SwiftUI view via delegate methods
- View uses `viewModel.scale` and `viewModel.panOffset` for transforms

## 3. Cursor Position Feedback (Low-Latency via WebRTC Data Channel)

**Created `Shared/Sources/Shared/HostMessage.swift`:**

```swift
public enum HostMessage: Codable {
    case cursorPosition(x: Double, y: Double)
}
```

**Host-side changes (`WebRTCManager.swift`):**

- Added `encoder = JSONEncoder()` for encoding HostMessage
- Added `lastCursorSendTime` and `cursorSendInterval = 16_000_000` (16ms = ~60fps)
- Added `sendCursorPosition(x:y:)` method with throttling:
  ```swift
  func sendCursorPosition(x: Double, y: Double) {
      guard let dataChannel = dataChannel, dataChannel.readyState == .open else { return }
      let now = DispatchTime.now().uptimeNanoseconds
      guard now - lastCursorSendTime >= cursorSendInterval else { return }
      lastCursorSendTime = now
      // encode and send HostMessage.cursorPosition
  }
  ```

**Host-side changes (`AppDelegate.swift`):**

- Modified `webRTCManager(_:didReceiveInputMessage:)` to call `manager.sendCursorPosition()` after handling input

**Client-side changes (`WebRTCClient.swift`):**

- Added `decoder = JSONDecoder()` for decoding HostMessage
- Added `WebRTCClientDelegate` method: `webRTCClient(_:didReceiveCursorPosition:y:)`
- Updated `dataChannel(_:didReceiveMessageWith:)` to decode HostMessage and call delegate

**Client-side display link coalescing (`RemoteSessionView.swift`):**

- Added pending cursor variables with NSLock:
  ```swift
  private var pendingCursorX: Double?
  private var pendingCursorY: Double?
  private let cursorLock = NSLock()
  private var displayLink: CADisplayLink?
  ```
- `startDisplayLink()` creates CADisplayLink at 30-60fps
- `displayLinkFired()` processes pending cursor position once per frame
- `enqueueCursorPosition(x:y:)` stores position thread-safely
- Prevents Task queue buildup that was causing lag

## 4. Edge-Based Panning

**Implemented in `RemoteSessionView.swift` `updateCursorPosition(x:y:)`:**

Key logic:
- Only pans when `scale > 1.0`
- Calculates visible area in remote screen coordinates: `visibleWidth = remoteScreenWidth / scale`
- Uses 15% edge margin: `edgeMarginPercent: CGFloat = 0.15`
- Checks if cursor is in margin zone of visible area
- If near edge, calculates new center to bring cursor inside safe zone
- Clamps to screen edges: `max(minCenterX, min(newCenterX, maxCenterX))`
- Converts back to view offset

## 5. Multi-Monitor Support

**Updated `InputController.swift`:**

- Added `setTargetDisplay(_ screen: NSScreen)` method
- Added static `cgEventBounds(for:)` to convert NSScreen (bottom-left origin) to CGEvent (top-left origin) coordinates:
  ```swift
  let cgEventY = primaryHeight - screen.frame.origin.y - screen.frame.height
  return CGRect(x: screen.frame.origin.x, y: cgEventY, width: screen.frame.width, height: screen.frame.height)
  ```
- Added `globalToLocal(_ point:)` to convert global cursor position to display-local coordinates
- `moveMouseRelative()` now clamps to `displayBounds.minX/maxX/minY/maxY` (global coordinates)
- `handleInput()` now returns display-local coordinates via `globalToLocal()`

**Updated `AppDelegate.swift`:**

- `selectDisplay(_:)` now finds corresponding `NSScreen` via `deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]`
- Calls `inputController?.setTargetDisplay(screen)`
- Initial target display set to `NSScreen.main` on startup in `startServices()`

## 6. Git Commit

**Committed and pushed as `fdc8acf`:**

```
feat: major improvements to remote control experience

- Switch to LiveKit WebRTC framework (v137.7151.10) for better stability
- Add pinch-to-zoom with edge-based panning that follows cursor
- Send cursor position via WebRTC data channel for lower latency
- Add display link coalescing to prevent cursor update queue buildup
- Throttle cursor updates to 60fps on host
- Add multi-monitor support - mouse constrained to captured display
- Convert cursor coordinates to display-local for correct panning
```

974 files changed (mostly WebRTC framework swap)
</work_completed>

<work_remaining>
## All Requested Tasks Complete

The primary tasks are done. Potential future improvements:

### Optional Enhancements

1. **Manual pan when zoomed** - Two-finger drag to manually pan the zoomed view independent of cursor

2. **Scroll gesture** - Two-finger scroll to send scroll wheel events to remote Mac

3. **Right-click gesture** - Long-press or two-finger tap for right-click context menu

4. **Better keyboard** - Physical keyboard support, improved special key handling

5. **Connection reliability** - Reconnection logic if connection drops, error recovery

6. **Adaptive quality** - Adjust video encoding bitrate based on network conditions

7. **Audio streaming** - Add audio track alongside video for complete remote experience

8. **Latency display** - Show round-trip time for diagnostics
</work_remaining>

<attempted_approaches>
## Cursor Position via TCP Signaling (Replaced)

- Initially sent cursor position via `SignalingServer` TCP channel using existing `SignalingMessage.cursorPos`
- Added delegate method `signalingClient(_:didReceiveCursorPosition:y:)`
- **Problem:** TCP signaling queued up messages causing lag when cursor updates arrived faster than TCP could deliver
- **Solution:** Moved to WebRTC data channel (UDP-based, same path as video) for lower latency

## Center-Following Pan (Replaced)

- First implementation always centered the view on the cursor position
- Calculated normalized position (-0.5 to 0.5) and set offset to center on it
- **User feedback:** "I'd like it better where we start panning if the cursor gets to within a percentage of the edge"
- **Solution:** Implemented 15% edge margin - only pan when cursor approaches visible edge

## Local Cursor Position Tracking (Not Used)

- Considered accumulating deltas locally to track cursor position on client
- Would add `cursorX += delta.x` after each mouse move
- **Problems identified:**
  - Drift from floating point errors over time
  - Doesn't account for cursor movement on Mac itself
  - Doesn't know starting position when connecting
- **Solution:** Host sends actual cursor position back to client

## Task Queue Buildup (Fixed)

- Initial cursor update implementation used `Task { @MainActor in }` for every update
- Each cursor position created new Task that queued up
- **Problem:** Queue buildup caused lag - cursor updates arrived faster than processing
- **Solution:** Display link coalescing
  - Store pending position in variables with NSLock
  - Process only once per display frame (60fps)
  - Only latest position matters, previous ones discarded
</attempted_approaches>

<critical_context>
## Coordinate Systems (Important!)

1. **NSScreen** (macOS): Bottom-left origin, y increases upward
2. **CGEvent** (macOS): Top-left origin, y increases downward
3. **Remote screen coordinates**: Top-left origin (0,0), what's sent to client
4. **View coordinates** (iOS): SwiftUI offset applied to scaled view

## Key Conversions

- `InputController.cgEventBounds(for:)` - NSScreen → CGEvent coordinates
- `InputController.globalToLocal()` - Global CGEvent → display-local (what client sees)
- `RemoteSessionViewModel.updateCursorPosition()` - Remote coords → pan offset

## WebRTC Data Channel

- Client creates data channel with label "input", `isOrdered = true`
- Bidirectional:
  - Client → Host: `InputMessage` (mouse moves, clicks, keys)
  - Host → Client: `HostMessage` (cursor position)
- Both use JSON encoding

## LiveKit WebRTC Symbol Prefix

- All Objective-C types have `LKRTC` prefix
- Examples: `LKRTCPeerConnection`, `LKRTCVideoTrack`, `LKRTCDataChannel`
- Framework module: `import LiveKitWebRTC`
- Global functions: `LKRTCInitializeSSL()`, `LKRTCCleanupSSL()`

## Throttling/Timing Configuration

```swift
// Host: cursor position throttle
cursorSendInterval: UInt64 = 16_000_000  // 16ms = ~60fps

// Client: display link
displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
```

## Edge-Based Panning Config

```swift
let edgeMarginPercent: CGFloat = 0.15  // 15% margin
let scaleRange = 1.0...5.0  // Zoom range
```

## Key Files Modified This Session

| File | Changes |
|------|---------|
| `WebRTCManager.swift` | LKRTC symbols, `sendCursorPosition()`, throttling |
| `InputController.swift` | `setTargetDisplay()`, coordinate conversion |
| `AppDelegate.swift` | Display selection, cursor position forwarding |
| `WebRTCClient.swift` | LKRTC symbols, HostMessage decoding |
| `RemoteSessionView.swift` | Display link, edge panning, scale/offset |
| `GestureController.swift` | Pinch handling, delegate methods |
| `VideoRenderView.swift` | LKRTC symbols |
| `HostMessage.swift` | New file for host→client messages |
</critical_context>

<current_state>
## Status: All Tasks Complete ✓

| Feature | Status |
|---------|--------|
| LiveKit WebRTC framework | ✓ Integrated and working |
| Pinch-to-zoom | ✓ Working (1x-5x range) |
| Edge-based panning | ✓ Working (15% margin) |
| Cursor position feedback | ✓ Working via data channel |
| Multi-monitor support | ✓ Working |
| Git commit/push | ✓ Pushed as `fdc8acf` |

## Build Status

Both apps build successfully with only minor warnings:
- `InputController.swift:142` - unused variable `eventType`
- `ScreenCaptureService.swift:44` - unused variable `content`
- `BonjourBrowser.swift:48` - unused variable `hosts`

## Tested Functionality

User confirmed working:
- Video streaming (no more crashes!)
- Mouse control
- Pinch-to-zoom
- Edge-based panning follows cursor
- Multi-monitor support (cursor constrained to selected display)

## Repository State

- Branch: `main`
- Latest commit: `fdc8acf`
- Pushed to: `github.com:zachswift615/sreen2screen.git`
- No uncommitted changes

## Files Summary

**New files:**
- `Shared/Sources/Shared/HostMessage.swift`
- `WebRTC/LiveKitWebRTC.xcframework/` (entire framework)

**Deleted:**
- `WebRTC/WebRTC.framework/`
- `WebRTC/WebRTC.xcframework/`

**Modified:**
- All WebRTC-using files (symbol prefix changes)
- Project files (framework references)
- `InputController.swift` (multi-monitor)
- `RemoteSessionView.swift` (zoom, pan, display link)
- `GestureController.swift` (pinch handling)
</current_state>
