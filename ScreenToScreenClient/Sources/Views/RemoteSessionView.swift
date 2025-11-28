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
