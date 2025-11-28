import SwiftUI
import LiveKitWebRTC
import Shared
import QuartzCore

struct RemoteSessionView: View {
    let host: HostInfo
    let onDisconnect: () -> Void

    @StateObject private var viewModel: RemoteSessionViewModel
    @State private var showKeyboard = false

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
                            .scaleEffect(viewModel.scale)
                            .offset(viewModel.panOffset)

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
                .onAppear {
                    viewModel.viewSize = geometry.size
                }
                .onChange(of: geometry.size) { newSize in
                    viewModel.viewSize = newSize
                }
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
            .onChange(of: viewModel.scale) { newScale in
                viewModel.gestureController.setCurrentScale(newScale)
            }
            .onChange(of: viewModel.shouldResetZoom) { shouldReset in
                if shouldReset {
                    withAnimation {
                        viewModel.scale = 1.0
                        viewModel.panOffset = .zero
                    }
                    viewModel.shouldResetZoom = false
                    viewModel.gestureController.setCurrentScale(1.0)
                }
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
    @Published var videoTrack: LKRTCVideoTrack?
    @Published var connectionStatus = "Connecting..."
    @Published var scale: CGFloat = 1.0
    @Published var shouldResetZoom = false
    @Published var panOffset: CGSize = .zero

    // Remote screen dimensions (updated when connection established)
    private var remoteScreenWidth: CGFloat = 1920
    private var remoteScreenHeight: CGFloat = 1080

    // Current cursor position from host (in remote screen coordinates, top-left origin)
    private var cursorX: CGFloat = 960
    private var cursorY: CGFloat = 540

    // Pending cursor position update (set from background thread, consumed on main thread)
    private var pendingCursorX: Double?
    private var pendingCursorY: Double?
    private let cursorLock = NSLock()
    private var displayLink: CADisplayLink?

    // View size for pan calculations (set by view)
    var viewSize: CGSize = .zero

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
        startDisplayLink()
    }

    func disconnect() {
        stopDisplayLink()
        webRTCClient.disconnect()
        signalingClient.disconnect()
    }

    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkFired() {
        // Check for pending cursor update
        cursorLock.lock()
        let x = pendingCursorX
        let y = pendingCursorY
        pendingCursorX = nil
        pendingCursorY = nil
        cursorLock.unlock()

        if let x = x, let y = y {
            updateCursorPosition(x: x, y: y)
        }
    }

    /// Called from background thread - stores cursor position for next display link frame
    func enqueueCursorPosition(x: Double, y: Double) {
        cursorLock.lock()
        pendingCursorX = x
        pendingCursorY = y
        cursorLock.unlock()
    }

    func updateCursorPosition(x: Double, y: Double) {
        cursorX = CGFloat(x)
        cursorY = CGFloat(y)

        // Only update pan when zoomed in
        guard scale > 1.0, viewSize.width > 0, viewSize.height > 0 else { return }

        // Calculate the visible area dimensions in remote screen coordinates
        let visibleWidth = remoteScreenWidth / scale
        let visibleHeight = remoteScreenHeight / scale

        // Current center of visible area in remote screen coordinates
        // panOffset is in view coordinates; convert to remote coordinates
        // When panOffset.width is positive, we're showing content to the left of center
        let currentCenterX = remoteScreenWidth / 2 - (panOffset.width / viewSize.width * visibleWidth)
        let currentCenterY = remoteScreenHeight / 2 - (panOffset.height / viewSize.height * visibleHeight)

        // Calculate the visible bounds
        let visibleMinX = currentCenterX - visibleWidth / 2
        let visibleMaxX = currentCenterX + visibleWidth / 2
        let visibleMinY = currentCenterY - visibleHeight / 2
        let visibleMaxY = currentCenterY + visibleHeight / 2

        // Edge margin: start panning when cursor is within this % of the edge
        let edgeMarginPercent: CGFloat = 0.15
        let marginX = visibleWidth * edgeMarginPercent
        let marginY = visibleHeight * edgeMarginPercent

        // Check if cursor is outside the "safe zone" (inner area)
        var needsPan = false
        var newCenterX = currentCenterX
        var newCenterY = currentCenterY

        // If cursor is near/past left edge
        if cursorX < visibleMinX + marginX {
            newCenterX = cursorX - marginX + visibleWidth / 2
            needsPan = true
        }
        // If cursor is near/past right edge
        else if cursorX > visibleMaxX - marginX {
            newCenterX = cursorX + marginX - visibleWidth / 2
            needsPan = true
        }

        // If cursor is near/past top edge
        if cursorY < visibleMinY + marginY {
            newCenterY = cursorY - marginY + visibleHeight / 2
            needsPan = true
        }
        // If cursor is near/past bottom edge
        else if cursorY > visibleMaxY - marginY {
            newCenterY = cursorY + marginY - visibleHeight / 2
            needsPan = true
        }

        if needsPan {
            // Clamp new center so we don't pan beyond the remote screen edges
            let minCenterX = visibleWidth / 2
            let maxCenterX = remoteScreenWidth - visibleWidth / 2
            let minCenterY = visibleHeight / 2
            let maxCenterY = remoteScreenHeight - visibleHeight / 2

            newCenterX = max(minCenterX, min(newCenterX, maxCenterX))
            newCenterY = max(minCenterY, min(newCenterY, maxCenterY))

            // Convert back to pan offset (view coordinates)
            let newOffsetX = (remoteScreenWidth / 2 - newCenterX) / visibleWidth * viewSize.width
            let newOffsetY = (remoteScreenHeight / 2 - newCenterY) / visibleHeight * viewSize.height

            panOffset = CGSize(width: newOffsetX, height: newOffsetY)
        }
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
            self.remoteScreenWidth = CGFloat(width)
            self.remoteScreenHeight = CGFloat(height)
            // Initialize cursor to center of screen
            self.cursorX = CGFloat(width) / 2
            self.cursorY = CGFloat(height) / 2
        }
    }

}

extension RemoteSessionViewModel: WebRTCClientDelegate {
    nonisolated func webRTCClient(_ client: WebRTCClient, didGenerateOffer sdp: String) {
        Task { @MainActor in
            signalingClient.send(.offer(sdp: sdp))
        }
    }

    nonisolated func webRTCClient(_ client: WebRTCClient, didGenerateIceCandidate candidate: LKRTCIceCandidate) {
        Task { @MainActor in
            signalingClient.send(.ice(candidate: candidate.sdp, sdpMLineIndex: candidate.sdpMLineIndex, sdpMid: candidate.sdpMid))
        }
    }

    nonisolated func webRTCClient(_ client: WebRTCClient, didReceiveVideoTrack track: LKRTCVideoTrack) {
        Task { @MainActor in
            videoTrack = track
            connectionStatus = "Connected"
        }
    }

    nonisolated func webRTCClient(_ client: WebRTCClient, didReceiveCursorPosition x: Double, y: Double) {
        // Enqueue for processing on next display frame - avoids Task queue buildup
        Task { @MainActor in
            enqueueCursorPosition(x: x, y: y)
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

    nonisolated func gestureController(_ controller: GestureController, didUpdateScale scale: CGFloat) {
        Task { @MainActor in
            self.scale = scale
        }
    }

    nonisolated func gestureControllerDidEndPinch(_ controller: GestureController) {
        Task { @MainActor in
            if self.scale < 1.1 {
                self.shouldResetZoom = true
            }
        }
    }

    nonisolated func gestureController(_ controller: GestureController, didMoveCursorBy delta: CGPoint, in viewSize: CGSize) {
        // Panning is now handled by cursor position feedback from host
        // This delegate method is no longer used for panning
    }
}
