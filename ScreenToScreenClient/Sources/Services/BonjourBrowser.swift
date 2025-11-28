import Foundation
import Network
import Shared

@MainActor
final class BonjourBrowser: ObservableObject {
    @Published var discoveredHosts: [HostInfo] = []
    @Published var isSearching = false

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.screen2screen.browser")

    func startBrowsing() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: Constants.bonjourServiceType, domain: Constants.bonjourServiceDomain), using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isSearching = true
                case .failed, .cancelled:
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleResults(results)
            }
        }

        browser?.start(queue: queue)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        var hosts: [HostInfo] = []

        for result in results {
            switch result.endpoint {
            case .service(let name, let type, let domain, _):
                // Resolve the service to get IP and port
                resolveService(name: name, type: type, domain: domain) { [weak self] hostInfo in
                    Task { @MainActor in
                        guard let self = self, let info = hostInfo else { return }
                        if !self.discoveredHosts.contains(where: { $0.id == info.id }) {
                            self.discoveredHosts.append(info)
                        }
                    }
                }
            default:
                break
            }
        }
    }

    private func resolveService(name: String, type: String, domain: String, completion: @escaping (HostInfo?) -> Void) {
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)

        let parameters = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: parameters)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = innerEndpoint {
                    let hostString: String
                    switch host {
                    case .ipv4(let addr):
                        hostString = "\(addr)"
                    case .ipv6(let addr):
                        hostString = "\(addr)"
                    case .name(let name, _):
                        hostString = name
                    @unknown default:
                        hostString = "unknown"
                    }

                    let info = HostInfo(
                        id: "\(name).\(type)\(domain)",
                        name: name,
                        host: hostString,
                        port: port.rawValue
                    )
                    completion(info)
                }
                connection.cancel()
            case .failed, .cancelled:
                completion(nil)
            default:
                break
            }
        }

        connection.start(queue: queue)

        // Timeout
        queue.asyncAfter(deadline: .now() + 5) {
            if connection.state != .ready {
                connection.cancel()
                completion(nil)
            }
        }
    }
}
