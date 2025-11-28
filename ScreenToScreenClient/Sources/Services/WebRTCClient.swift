import Foundation
import LiveKitWebRTC
import Shared

protocol WebRTCClientDelegate: AnyObject {
    func webRTCClient(_ client: WebRTCClient, didGenerateOffer sdp: String)
    func webRTCClient(_ client: WebRTCClient, didGenerateIceCandidate candidate: LKRTCIceCandidate)
    func webRTCClient(_ client: WebRTCClient, didReceiveVideoTrack track: LKRTCVideoTrack)
    func webRTCClient(_ client: WebRTCClient, didReceiveCursorPosition x: Double, y: Double)
    func webRTCClientDidConnect(_ client: WebRTCClient)
    func webRTCClientDidDisconnect(_ client: WebRTCClient)
}

final class WebRTCClient: NSObject {
    weak var delegate: WebRTCClientDelegate?

    private let factory: LKRTCPeerConnectionFactory
    private var peerConnection: LKRTCPeerConnection?
    private var dataChannel: LKRTCDataChannel?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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
        config.iceServers = []  // Local network, no STUN/TURN needed

        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)

        // Create data channel for input
        let dataChannelConfig = LKRTCDataChannelConfiguration()
        dataChannelConfig.isOrdered = true
        dataChannelConfig.isNegotiated = false

        dataChannel = peerConnection?.dataChannel(forLabel: "input", configuration: dataChannelConfig)
        dataChannel?.delegate = self

        // Add transceiver for receiving video
        let transceiverInit = LKRTCRtpTransceiverInit()
        transceiverInit.direction = .recvOnly
        peerConnection?.addTransceiver(of: .video, init: transceiverInit)
    }

    func createOffer() {
        let constraints = LKRTCMediaConstraints(
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
        let sessionDescription = LKRTCSessionDescription(type: .answer, sdp: sdp)

        peerConnection?.setRemoteDescription(sessionDescription) { error in
            if let error = error {
                print("Failed to set remote description: \(error)")
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

    func sendInput(_ message: InputMessage) {
        guard let dataChannel = dataChannel else {
            print("Data channel is nil, cannot send input")
            return
        }

        guard dataChannel.readyState == .open else {
            print("Data channel not open, state: \(dataChannel.readyState.rawValue)")
            return
        }

        do {
            let data = try encoder.encode(message)
            let buffer = LKRTCDataBuffer(data: data, isBinary: false)
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

extension WebRTCClient: LKRTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange stateChanged: LKRTCSignalingState) {
        print("Signaling state: \(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {
        print("Stream added with \(stream.videoTracks.count) video tracks")
        if let videoTrack = stream.videoTracks.first {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.webRTCClient(self, didReceiveVideoTrack: videoTrack)
            }
        }
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove stream: LKRTCMediaStream) {
        print("Stream removed")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: LKRTCPeerConnection) {
        print("Negotiation needed")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceConnectionState) {
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

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceGatheringState) {
        print("ICE gathering state: \(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {
        delegate?.webRTCClient(self, didGenerateIceCandidate: candidate)
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove candidates: [LKRTCIceCandidate]) {}

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didOpen dataChannel: LKRTCDataChannel) {
        print("Data channel opened by remote: \(dataChannel.label)")
        // Use the data channel opened by the remote peer
        if dataChannel.label == "input" {
            self.dataChannel = dataChannel
            dataChannel.delegate = self
        }
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd rtpReceiver: LKRTCRtpReceiver, streams mediaStreams: [LKRTCMediaStream]) {
        if let videoTrack = rtpReceiver.track as? LKRTCVideoTrack {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.webRTCClient(self, didReceiveVideoTrack: videoTrack)
            }
        }
    }
}

extension WebRTCClient: LKRTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: LKRTCDataChannel) {
        let stateNames = ["connecting", "open", "closing", "closed"]
        let stateName = dataChannel.readyState.rawValue < stateNames.count ? stateNames[Int(dataChannel.readyState.rawValue)] : "unknown"
        print("Data channel '\(dataChannel.label)' state changed to: \(stateName) (\(dataChannel.readyState.rawValue))")
    }

    func dataChannel(_ dataChannel: LKRTCDataChannel, didReceiveMessageWith buffer: LKRTCDataBuffer) {
        guard let data = buffer.data as Data? else { return }

        do {
            let message = try decoder.decode(HostMessage.self, from: data)
            switch message {
            case .cursorPosition(let x, let y):
                // Call delegate directly - it's marked nonisolated and will handle main thread dispatch
                self.delegate?.webRTCClient(self, didReceiveCursorPosition: x, y: y)
            }
        } catch {
            print("Failed to decode host message: \(error)")
        }
    }
}
