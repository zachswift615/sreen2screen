import Foundation
import Network
import Shared

protocol SignalingClientDelegate: AnyObject {
    func signalingClientDidConnect()
    func signalingClientDidDisconnect()
    func signalingClient(_ client: SignalingClient, didReceiveAnswer sdp: String)
    func signalingClient(_ client: SignalingClient, didReceiveIceCandidate candidate: String, sdpMLineIndex: Int32, sdpMid: String?)
    func signalingClient(_ client: SignalingClient, didReceiveScreenInfo width: Int, height: Int, scale: Double)
}

final class SignalingClient {
    weak var delegate: SignalingClientDelegate?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.screen2screen.signaling.client")

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func connect(to host: HostInfo) {
        let hostEndpoint = NWEndpoint.Host(host.host)
        let port = NWEndpoint.Port(rawValue: host.port)!

        connection = NWConnection(host: hostEndpoint, port: port, using: .tcp)

        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Connected to signaling server")
                DispatchQueue.main.async {
                    self?.delegate?.signalingClientDidConnect()
                }
                self?.receiveMessage()
            case .failed(let error):
                print("Connection failed: \(error)")
                DispatchQueue.main.async {
                    self?.delegate?.signalingClientDidDisconnect()
                }
            case .cancelled:
                print("Connection cancelled")
                DispatchQueue.main.async {
                    self?.delegate?.signalingClientDidDisconnect()
                }
            default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func send(_ message: SignalingMessage) {
        guard let connection = connection else { return }

        do {
            let data = try encoder.encode(message)
            let framedData = frameMessage(data)

            connection.send(content: framedData, completion: .contentProcessed { error in
                if let error = error {
                    print("Failed to send: \(error)")
                }
            })
        } catch {
            print("Failed to encode message: \(error)")
        }
    }

    private func receiveMessage() {
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("Receive error: \(error)")
                return
            }

            if isComplete {
                DispatchQueue.main.async {
                    self.delegate?.signalingClientDidDisconnect()
                }
                return
            }

            guard let lengthData = data, lengthData.count == 4 else {
                self.receiveMessage()
                return
            }

            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            self.connection?.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] data, _, _, error in
                guard let self = self else { return }

                if let error = error {
                    print("Receive body error: \(error)")
                    return
                }

                if let messageData = data {
                    self.handleMessage(messageData)
                }

                self.receiveMessage()
            }
        }
    }

    private func handleMessage(_ data: Data) {
        do {
            let message = try decoder.decode(SignalingMessage.self, from: data)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                switch message {
                case .answer(let sdp):
                    self.delegate?.signalingClient(self, didReceiveAnswer: sdp)
                case .ice(let candidate, let sdpMLineIndex, let sdpMid):
                    self.delegate?.signalingClient(self, didReceiveIceCandidate: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
                case .screenInfo(let width, let height, let scale):
                    self.delegate?.signalingClient(self, didReceiveScreenInfo: width, height: height, scale: scale)
                case .cursorPos:
                    // Cursor position is now received via WebRTC data channel for lower latency
                    break
                default:
                    break
                }
            }
        } catch {
            print("Failed to decode message: \(error)")
        }
    }

    private func frameMessage(_ data: Data) -> Data {
        var framedData = Data()
        var length = UInt32(data.count).bigEndian
        framedData.append(Data(bytes: &length, count: 4))
        framedData.append(data)
        return framedData
    }
}
