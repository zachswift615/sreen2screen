import Foundation

/// Messages sent from Host to Client over the WebRTC data channel
public enum HostMessage: Codable {
    case cursorPosition(x: Double, y: Double)

    private enum CodingKeys: String, CodingKey {
        case type
        case x, y
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "cursorPosition":
            let x = try container.decode(Double.self, forKey: .x)
            let y = try container.decode(Double.self, forKey: .y)
            self = .cursorPosition(x: x, y: y)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .cursorPosition(let x, let y):
            try container.encode("cursorPosition", forKey: .type)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        }
    }
}
