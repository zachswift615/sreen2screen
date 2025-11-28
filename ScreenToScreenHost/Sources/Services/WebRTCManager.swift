import Foundation
import LiveKitWebRTC
import Shared
import CoreMedia

protocol WebRTCManagerDelegate: AnyObject {
    func webRTCManager(_ manager: WebRTCManager, didGenerateAnswer sdp: String)
    func webRTCManager(_ manager: WebRTCManager, didGenerateIceCandidate candidate: LKRTCIceCandidate)
    func webRTCManager(_ manager: WebRTCManager, didReceiveInputMessage message: InputMessage)
    func webRTCManagerDidConnect(_ manager: WebRTCManager)
    func webRTCManagerDidDisconnect(_ manager: WebRTCManager)
}

// Custom video capturer to inject frames into WebRTC
final class ScreenCapturer: LKRTCVideoCapturer {
    func captureFrame(_ frame: LKRTCVideoFrame) {
        self.delegate?.capturer(self, didCapture: frame)
    }
}

final class WebRTCManager: NSObject {
    weak var delegate: WebRTCManagerDelegate?

    private let factory: LKRTCPeerConnectionFactory
    private var peerConnection: LKRTCPeerConnection?
    private var dataChannel: LKRTCDataChannel?
    private var videoSource: LKRTCVideoSource?
    private var videoTrack: LKRTCVideoTrack?
    private var videoCapturer: ScreenCapturer?

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // Throttle cursor position updates to ~60fps max
    private var lastCursorSendTime: UInt64 = 0
    private let cursorSendInterval: UInt64 = 16_000_000 // 16ms in nanoseconds (~60fps)

    override init() {
        LKRTCInitializeSSL()

        let encoderFactory = LKRTCDefaultVideoEncoderFactory()
        let decoderFactory = LKRTCDefaultVideoDecoderFactory()
        factory = LKRTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)

        super.init()
    }

    deinit {
        LKRTCCleanupSSL()
    }

    func setupPeerConnection() {
        let config = LKRTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        // Empty ICE servers for local network (direct connection)
        config.iceServers = []

        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)

        setupVideoTrack()
    }

    private func setupVideoTrack() {
        videoSource = factory.videoSource()
        videoCapturer = ScreenCapturer(delegate: videoSource!)
        videoSource?.adaptOutputFormat(toWidth: 1920, height: 1080, fps: 30)
        videoTrack = factory.videoTrack(with: videoSource!, trackId: "screen0")

        if let track = videoTrack {
            peerConnection?.add(track, streamIds: ["screen"])
        }
    }

    func handleOffer(sdp: String) {
        let sessionDescription = LKRTCSessionDescription(type: .offer, sdp: sdp)

        peerConnection?.setRemoteDescription(sessionDescription) { [weak self] error in
            if let error = error {
                print("Failed to set remote description: \(error)")
                return
            }
            self?.createAnswer()
        }
    }

    private func createAnswer() {
        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

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
        let iceCandidate = LKRTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        peerConnection?.add(iceCandidate) { error in
            if let error = error {
                print("Failed to add ICE candidate: \(error)")
            }
        }
    }

    private var lastFrameTime: Int64 = 0

    func sendVideoFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let videoSource = videoSource, let capturer = videoCapturer else { return }

        // Throttle to ~30fps to reduce encoder pressure
        let timestampNs = Int64(CMTimeGetSeconds(timestamp) * 1_000_000_000)
        let minFrameInterval: Int64 = 33_000_000 // ~30fps in nanoseconds
        if timestampNs - lastFrameTime < minFrameInterval {
            return
        }
        lastFrameTime = timestampNs

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Update output format to match actual frame dimensions
        videoSource.adaptOutputFormat(toWidth: Int32(width), height: Int32(height), fps: 30)

        // Lock the pixel buffer for reading
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        // Create RTC pixel buffer wrapper
        let rtcPixelBuffer = LKRTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let videoFrame = LKRTCVideoFrame(buffer: rtcPixelBuffer, rotation: ._0, timeStampNs: timestampNs)

        // Push frame through our custom capturer
        capturer.captureFrame(videoFrame)
    }

    func disconnect() {
        dataChannel?.close()
        dataChannel = nil
        peerConnection?.close()
        peerConnection = nil
    }

    func sendCursorPosition(x: Double, y: Double) {
        guard let dataChannel = dataChannel, dataChannel.readyState == .open else { return }

        // Throttle updates to avoid flooding the data channel
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastCursorSendTime >= cursorSendInterval else { return }
        lastCursorSendTime = now

        let message = HostMessage.cursorPosition(x: x, y: y)
        do {
            let data = try encoder.encode(message)
            let buffer = LKRTCDataBuffer(data: data, isBinary: false)
            dataChannel.sendData(buffer)
        } catch {
            print("Failed to encode cursor position: \(error)")
        }
    }
}

extension WebRTCManager: LKRTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange stateChanged: LKRTCSignalingState) {
        print("Signaling state changed: \(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {
        print("Stream added")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove stream: LKRTCMediaStream) {
        print("Stream removed")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: LKRTCPeerConnection) {
        print("Negotiation needed")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceConnectionState) {
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

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceGatheringState) {
        print("ICE gathering state changed: \(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {
        delegate?.webRTCManager(self, didGenerateIceCandidate: candidate)
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove candidates: [LKRTCIceCandidate]) {
        print("ICE candidates removed")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didOpen dataChannel: LKRTCDataChannel) {
        print("Data channel opened: \(dataChannel.label)")
        self.dataChannel = dataChannel
        dataChannel.delegate = self
    }
}

extension WebRTCManager: LKRTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: LKRTCDataChannel) {
        print("Data channel state changed: \(dataChannel.readyState.rawValue)")
    }

    func dataChannel(_ dataChannel: LKRTCDataChannel, didReceiveMessageWith buffer: LKRTCDataBuffer) {
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
