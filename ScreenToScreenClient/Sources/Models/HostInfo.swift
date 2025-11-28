import Foundation

struct HostInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: UInt16

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: HostInfo, rhs: HostInfo) -> Bool {
        lhs.id == rhs.id
    }
}
