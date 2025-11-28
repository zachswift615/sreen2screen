import Foundation
import WebRTC
import Shared
import CoreMedia

protocol WebRTCManagerDelegate: AnyObject {
    func webRTCManager(_ manager: WebRTCManager, didGenerateAnswer sdp: String)
    func webRTCManager(_ manager: WebRTCManager, didGenerateIceCandidate candidate: RTCIceCandidate)
    func webRTCManager(_ manager: WebRTCManager, didReceiveInputMessage message: InputMessage)
    func webRTCManagerDidConnect(_ manager: WebRTCManager)
    func webRTCManagerDidDisconnect(_ manager: WebRTCManager)
}

// Custom video capturer to inject frames into WebRTC
final class ScreenCapturer: RTCVideoCapturer {
    func captureFrame(_ frame: RTCVideoFrame) {
        self.delegate?.capturer(self, didCapture: frame)
    }
}

final class WebRTCManager: NSObject {
    weak var delegate: WebRTCManagerDelegate?

    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var videoSource: RTCVideoSource?
    private var videoTrack: RTCVideoTrack?
    private var videoCapturer: ScreenCapturer?

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
        videoCapturer = ScreenCapturer(delegate: videoSource!)
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
        peerConnection?.add(iceCandidate)
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
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let videoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: ._0, timeStampNs: timestampNs)

        // Push frame through our custom capturer
        capturer.captureFrame(videoFrame)
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
