# Screen2Screen Handoff Document

**Date:** 2025-11-28
**Repository:** /Users/zachswift/projects/screen2screen
**Branch:** main

---

<original_task>
Continue setting up the Screen2Screen remote desktop application in Xcode and test it. The implementation was already complete from a previous session - this session focused on:
1. Adding source files to Xcode projects (they existed on disk but weren't in build phases)
2. Fixing WebRTC framework issues for both macOS and iOS
3. Getting both apps to build and run
4. Testing end-to-end functionality
</original_task>

<work_completed>
## Xcode Project Setup

### Source Files Added to Projects
Used xcodeproj Ruby gem to add missing source files:

**Host App (macOS):**
- `ScreenToScreenHost/Sources/Services/InputController.swift`
- `ScreenToScreenHost/Sources/Services/ScreenCaptureService.swift`
- `ScreenToScreenHost/Sources/Services/SignalingServer.swift`
- `ScreenToScreenHost/Sources/Services/WebRTCManager.swift`
- `ScreenToScreenHost/Sources/App/main.swift` (created new - needed for app launch)

**Client App (iOS):**
- `ScreenToScreenClient/Sources/Services/BonjourBrowser.swift`
- `ScreenToScreenClient/Sources/Services/SignalingClient.swift`
- `ScreenToScreenClient/Sources/Services/WebRTCClient.swift`
- `ScreenToScreenClient/Sources/Views/HostListView.swift`
- `ScreenToScreenClient/Sources/Views/RemoteSessionView.swift`
- `ScreenToScreenClient/Sources/Views/SpecialKeyboardView.swift`
- `ScreenToScreenClient/Sources/Views/VideoRenderView.swift`
- `ScreenToScreenClient/Sources/Views/GestureOverlayView.swift`
- `ScreenToScreenClient/Sources/Models/HostInfo.swift`
- `ScreenToScreenClient/Sources/Gestures/CursorState.swift`
- `ScreenToScreenClient/Sources/Gestures/GestureController.swift`

### Workspace Created
- Created `Screen2Screen.xcworkspace` at `/Users/zachswift/projects/screen2screen/Screen2Screen.xcworkspace/contents.xcworkspacedata`
- Contains both projects and the Shared package to avoid "already opened" conflicts

### macOS Host App Fixes
1. **Entry Point Fix:** Created `main.swift` with explicit `NSApplication` setup - the `@main` attribute on AppDelegate wasn't launching the app
2. **Info.plist:** Added `NSPrincipalClass` = `NSApplication`
3. **Framework Search Paths:** Added `$(PROJECT_DIR)/../WebRTC` to Debug configuration (was only in Release)
4. **Imports:** Added missing `import WebRTC` to AppDelegate.swift, `import AppKit` to InputController.swift
5. **Type Fix:** Cast `CGFloat` to `Double` in ScreenCaptureService.swift line 82

### iOS Client App Fixes
1. **Deployment Target:** Changed from iOS 15.0 to iOS 16.0 (NavigationStack requires iOS 16)
2. **Info.plist:** Added `CFBundleExecutable` = `$(EXECUTABLE_NAME)`
3. **Info.plist:** Fixed Resources build phase (removed Info.plist from Resources - was causing duplicate)
4. **Project File Paths:** Fixed doubled-up paths in project.pbxproj (e.g., `Sources/Views/Sources/Views/` → just filename)
5. **Bonjour Service Type:** Fixed mismatch - Constants.swift had `_screencast._tcp`, now `_screen2screen._tcp`

### WebRTC Framework Issues
**Problem:** The stasel/WebRTC M141 xcframework has broken macOS headers - only 1 header file in macOS slice vs 93 in iOS.

**Attempts Made:**
1. Copied iOS headers to macOS slice - failed (iOS-only APIs like AVAudioSession, UIView)
2. Copied Mac Catalyst headers - failed (wrong import paths `sdk/objc/base/`)
3. Fixed import paths with sed - headers still had issues
4. Tried SPM package - same broken macOS slice
5. Downloaded tmthecoder/WebRTC-macOS (2021 build) - works for macOS but crashes at runtime

**Current Working Setup:**
- **macOS Host:** Uses `WebRTC.framework` from tmthecoder/WebRTC-macOS (April 2021, version 8324)
  - Location: `/Users/zachswift/projects/screen2screen/WebRTC/WebRTC.framework`
  - Added via Framework Search Paths, not xcframework
- **iOS Client:** Uses `WebRTC.xcframework` from stasel/WebRTC M141
  - Location: `/Users/zachswift/projects/screen2screen/WebRTC/WebRTC.xcframework`
  - iOS headers fixed with: `sed -i '' 's/#import "sdk\/objc\/base\/\([^"]*\)"/#import <WebRTC\/\1>/g' *.h`
  - Applied to both `ios-arm64` and `ios-x86_64_arm64-simulator` slices

### Code Changes for Older macOS WebRTC API
In `WebRTCManager.swift`:
1. Removed completion handler from `peerConnection?.add(iceCandidate)` - older API doesn't have it
2. Created `ScreenCapturer` class extending `RTCVideoCapturer` to inject frames
3. Changed video frame injection to use custom capturer instead of `videoSource.delegate`
4. Added frame throttling and pixel buffer locking (didn't fix crash)

### VideoRenderView.swift Fix (iOS)
Added Coordinator pattern to prevent adding video track multiple times:
- Tracks current track in coordinator
- Only adds track if not already added
- Properly removes track on dismantle

## Testing Results
**SUCCESS:** Both apps build and run. Connection established. Video streaming works initially - saw Mac screen on iPhone!

**CRASH:** After a few seconds of streaming, the macOS Host app crashes in WebRTC's video encoder:
- Thread: EncoderQueue (serial)
- Location: `CVPixelBufferPoolGetPixelBufferAttributes` → `CF_IS_OBJC` → `objc_msgSend`
- Error: `EXC_BREAKPOINT` or `EXC_BAD_ACCESS`
- Root Cause: The 2021 macOS WebRTC framework is incompatible with modern ScreenCaptureKit pixel buffer formats
</work_completed>

<work_remaining>
## Primary Task: Switch to LiveKit's WebRTC XCFramework

The tmthecoder/WebRTC-macOS framework (2021) crashes when encoding ScreenCaptureKit pixel buffers. Need to switch to LiveKit's actively maintained WebRTC build.

### Step 1: Download LiveKit WebRTC
```bash
cd /Users/zachswift/projects/screen2screen/WebRTC
# Remove old frameworks
rm -rf WebRTC.framework WebRTC.xcframework
# Download LiveKit's build (check releases for latest)
curl -L -o LiveKitWebRTC.xcframework.zip "https://github.com/livekit/webrtc-xcframework/releases/download/VERSION/LiveKitWebRTC.xcframework.zip"
unzip LiveKitWebRTC.xcframework.zip
```

### Step 2: Update All Code References
LiveKit prefixes all symbols with `LK`. Find and replace in ALL Swift files:

**Host App files to update:**
- `ScreenToScreenHost/Sources/Services/WebRTCManager.swift`
- `ScreenToScreenHost/Sources/App/AppDelegate.swift`

**Client App files to update:**
- `ScreenToScreenClient/Sources/Services/WebRTCClient.swift`
- `ScreenToScreenClient/Sources/Views/VideoRenderView.swift`

**Symbol replacements needed:**
| Old Symbol | New Symbol |
|------------|------------|
| `import WebRTC` | `import LiveKitWebRTC` |
| `RTCPeerConnection` | `LKRTCPeerConnection` |
| `RTCPeerConnectionFactory` | `LKRTCPeerConnectionFactory` |
| `RTCPeerConnectionDelegate` | `LKRTCPeerConnectionDelegate` |
| `RTCSessionDescription` | `LKRTCSessionDescription` |
| `RTCIceCandidate` | `LKRTCIceCandidate` |
| `RTCIceServer` | `LKRTCIceServer` |
| `RTCConfiguration` | `LKRTCConfiguration` |
| `RTCMediaConstraints` | `LKRTCMediaConstraints` |
| `RTCVideoTrack` | `LKRTCVideoTrack` |
| `RTCVideoSource` | `LKRTCVideoSource` |
| `RTCVideoCapturer` | `LKRTCVideoCapturer` |
| `RTCVideoFrame` | `LKRTCVideoFrame` |
| `RTCCVPixelBuffer` | `LKRTCCVPixelBuffer` |
| `RTCDataChannel` | `LKRTCDataChannel` |
| `RTCDataChannelDelegate` | `LKRTCDataChannelDelegate` |
| `RTCDataBuffer` | `LKRTCDataBuffer` |
| `RTCDataChannelConfiguration` | `LKRTCDataChannelConfiguration` |
| `RTCDefaultVideoEncoderFactory` | `LKRTCDefaultVideoEncoderFactory` |
| `RTCDefaultVideoDecoderFactory` | `LKRTCDefaultVideoDecoderFactory` |
| `RTCMTLVideoView` | `LKRTCMTLVideoView` |
| `RTCSignalingState` | `LKRTCSignalingState` |
| `RTCIceConnectionState` | `LKRTCIceConnectionState` |
| `RTCIceGatheringState` | `LKRTCIceGatheringState` |
| `RTCMediaStream` | `LKRTCMediaStream` |
| `RTCInitializeSSL()` | `LKRTCInitializeSSL()` |
| `RTCCleanupSSL()` | `LKRTCCleanupSSL()` |

### Step 3: Update Xcode Projects
1. Remove old WebRTC framework references from both projects
2. Add `LiveKitWebRTC.xcframework` to both projects (Embed & Sign)
3. May need to update Framework Search Paths

### Step 4: Test End-to-End
1. Build and run Host app
2. Build and run Client app on physical iOS device
3. Test video streaming stability
4. Test gesture input (tap, drag, pinch)
5. Test keyboard input

### Step 5: Fix Any API Differences
LiveKit's build may have slightly different APIs. Watch for:
- Completion handler differences
- Method signature changes
- Property name changes
</work_remaining>

<attempted_approaches>
## WebRTC Framework Attempts (All Failed for macOS)

### 1. stasel/WebRTC M141 XCFramework (SPM and Manual)
- **Problem:** macOS slice has only 1 header file (WebRTC.h) that references 93 other headers that don't exist
- **Error:** `'WebRTC/RTCAudioSource.h' file not found`

### 2. Copying iOS Headers to macOS Slice
- **Problem:** iOS headers reference iOS-only APIs
- **Error:** `'AVAudioSession' is unavailable: not available on macOS`, `Cannot find interface declaration for 'UIView'`

### 3. Copying Mac Catalyst Headers to macOS Slice
- **Problem:** Headers use wrong import paths
- **Error:** `'sdk/objc/base/RTCMacros.h' file not found`

### 4. Fixing Import Paths with sed
- **Command:** `sed -i '' 's/#import "sdk\/objc\/base\/\([^"]*\)"/#import <WebRTC\/\1>/g' *.h`
- **Problem:** First attempt corrupted headers (missing closing `>`), second attempt worked but headers still had issues
- **Note:** This DID work for iOS slices

### 5. tmthecoder/WebRTC-macOS (2021 Build)
- **Status:** BUILDS AND RUNS but crashes during video encoding
- **Crash:** `EXC_BREAKPOINT` in `CVPixelBufferPoolGetPixelBufferAttributes` → `CF_IS_OBJC`
- **Root Cause:** 2021 framework incompatible with modern ScreenCaptureKit CVPixelBuffer formats
- **Attempts to fix crash:**
  - Added frame throttling (~30fps) - didn't help
  - Added CVPixelBuffer locking - didn't help
  - Tried async dispatch - couldn't use (CVPixelBufferRetain unavailable in Swift)

### 6. nicothin/nicothin-webrtc-build
- **Status:** Repository doesn't exist (404)
- **Note:** Was in original implementation plan
</attempted_approaches>

<critical_context>
## Architecture Overview
- **macOS Host App:** Menu bar app using ScreenCaptureKit for capture, WebRTC for streaming
- **iOS Client App:** SwiftUI app using Bonjour for discovery, WebRTC for receiving video
- **Signaling:** Custom length-prefixed JSON over TCP (not WebSocket)
- **Input:** JSON over WebRTC DataChannel

## Key Files
| File | Purpose |
|------|---------|
| `ScreenToScreenHost/Sources/Services/WebRTCManager.swift` | WebRTC setup, video frame injection |
| `ScreenToScreenHost/Sources/Services/ScreenCaptureService.swift` | ScreenCaptureKit wrapper |
| `ScreenToScreenHost/Sources/App/main.swift` | App entry point (required!) |
| `ScreenToScreenClient/Sources/Services/WebRTCClient.swift` | WebRTC client setup |
| `ScreenToScreenClient/Sources/Views/VideoRenderView.swift` | RTCMTLVideoView wrapper |
| `Shared/Sources/Shared/Constants.swift` | Bonjour service type, port |

## Important Details
1. **Bonjour Service Type:** `_screen2screen._tcp` (must match in Constants.swift and both Info.plist files)
2. **Port:** 8080 for signaling
3. **macOS Host uses main.swift:** The `@main` attribute on AppDelegate didn't work - needed explicit NSApplication setup
4. **iOS Deployment Target:** iOS 16.0 (NavigationStack requirement)
5. **Video Frame Injection:** Uses custom `ScreenCapturer` class that extends `RTCVideoCapturer`

## LiveKit WebRTC Notes
- GitHub: https://github.com/livekit/webrtc-xcframework
- All symbols prefixed with `LK` (e.g., `LKRTCPeerConnection`)
- Supports: iOS 13+, macOS 10.15+, Mac Catalyst 14.0+, visionOS 2.2+, tvOS 17.0+
- Actively maintained with recent releases

## Environment
- macOS 23.6.0 (Sonoma)
- Xcode 16.2
- iOS target device required (not simulator) for full testing
- Both devices must be on same WiFi network
</critical_context>

<current_state>
## Build Status
- **macOS Host App:** BUILDS AND RUNS (but crashes during video streaming)
- **iOS Client App:** BUILDS AND RUNS SUCCESSFULLY
- **Workspace:** `Screen2Screen.xcworkspace` - use this to open both projects

## What Works
- Both apps launch successfully
- Bonjour discovery works (iOS finds Mac)
- TCP signaling connection establishes
- WebRTC connection negotiates successfully
- Video track is received on iOS
- Initial video frames display on iOS (saw Mac screen!)
- Data channel opens for input

## What's Broken
- Video streaming crashes after a few seconds
- Crash is in macOS Host app's WebRTC encoder
- Root cause: Old WebRTC framework incompatible with ScreenCaptureKit pixel buffers

## Uncommitted Changes
Multiple files have been modified during debugging. Key changes:
- `WebRTCManager.swift`: Frame throttling, pixel buffer locking, ScreenCapturer class
- `VideoRenderView.swift`: Coordinator pattern for track management
- Various Info.plist and project.pbxproj fixes

## Next Action
Switch to LiveKit's WebRTC xcframework and update all symbol references from `RTC*` to `LKRTC*`
</current_state>
