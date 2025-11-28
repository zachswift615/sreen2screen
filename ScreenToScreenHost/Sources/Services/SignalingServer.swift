import Foundation
import Network
import Shared

protocol SignalingServerDelegate: AnyObject {
    func signalingServerDidReceiveOffer(sdp: String)
    func signalingServerDidReceiveIceCandidate(candidate: String, sdpMLineIndex: Int32, sdpMid: String?)
    func signalingServerClientConnected()
    func signalingServerClientDisconnected()
}

final class SignalingServer {
    weak var delegate: SignalingServerDelegate?

    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "com.screen2screen.signaling")

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(port: UInt16 = Constants.signalingPort) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        listener = try NWListener(using: parameters, on: port)

        // Set up Bonjour advertising on the same listener (avoids port conflict)
        let serviceName = Host.current().localizedName ?? "Mac"
        listener?.service = NWListener.Service(
            name: serviceName,
            type: Constants.bonjourServiceType,
            domain: Constants.bonjourServiceDomain
        )

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Signaling server listening on port \(self?.port.rawValue ?? 0)")
                print("Bonjour advertising started: \(serviceName)")
            case .failed(let error):
                print("Signaling server failed: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
    }

    func send(_ message: SignalingMessage) {
        guard let connection = activeConnection else {
            print("No active connection to send message")
            return
        }

        do {
            let data = try encoder.encode(message)
            let framedData = frameMessage(data)

            connection.send(content: framedData, completion: .contentProcessed { error in
                if let error = error {
                    print("Failed to send signaling message: \(error)")
                }
            })
        } catch {
            print("Failed to encode signaling message: \(error)")
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        // Only allow one connection at a time
        activeConnection?.cancel()
        activeConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Client connected")
                self?.delegate?.signalingServerClientConnected()
                self?.receiveMessage(on: connection)
            case .failed(let error):
                print("Connection failed: \(error)")
                self?.delegate?.signalingServerClientDisconnected()
            case .cancelled:
                print("Connection cancelled")
                self?.delegate?.signalingServerClientDisconnected()
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveMessage(on connection: NWConnection) {
        // Read 4-byte length prefix
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("Receive error: \(error)")
                return
            }

            if isComplete {
                self.delegate?.signalingServerClientDisconnected()
                return
            }

            guard let lengthData = data, lengthData.count == 4 else {
                self.receiveMessage(on: connection)
                return
            }

            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            // Read message body
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] data, _, _, error in
                guard let self = self else { return }

                if let error = error {
                    print("Receive body error: \(error)")
                    return
                }

                if let messageData = data {
                    self.handleMessage(messageData)
                }

                self.receiveMessage(on: connection)
            }
        }
    }

    private func handleMessage(_ data: Data) {
        do {
            let message = try decoder.decode(SignalingMessage.self, from: data)

            DispatchQueue.main.async { [weak self] in
                switch message {
                case .offer(let sdp):
                    self?.delegate?.signalingServerDidReceiveOffer(sdp: sdp)
                case .ice(let candidate, let sdpMLineIndex, let sdpMid):
                    self?.delegate?.signalingServerDidReceiveIceCandidate(
                        candidate: candidate,
                        sdpMLineIndex: sdpMLineIndex,
                        sdpMid: sdpMid
                    )
                default:
                    print("Unexpected message type from client")
                }
            }
        } catch {
            print("Failed to decode signaling message: \(error)")
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
