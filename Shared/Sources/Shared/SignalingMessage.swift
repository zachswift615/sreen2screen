import Foundation

public enum SignalingMessage: Codable {
    case offer(sdp: String)
    case answer(sdp: String)
    case ice(candidate: String, sdpMLineIndex: Int32, sdpMid: String?)
    case screenInfo(width: Int, height: Int, scale: Double)
    case cursorPos(x: Double, y: Double)

    private enum CodingKeys: String, CodingKey {
        case type
        case sdp
        case candidate
        case sdpMLineIndex
        case sdpMid
        case width, height, scale
        case x, y
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "offer":
            let sdp = try container.decode(String.self, forKey: .sdp)
            self = .offer(sdp: sdp)
        case "answer":
            let sdp = try container.decode(String.self, forKey: .sdp)
            self = .answer(sdp: sdp)
        case "ice":
            let candidate = try container.decode(String.self, forKey: .candidate)
            let sdpMLineIndex = try container.decode(Int32.self, forKey: .sdpMLineIndex)
            let sdpMid = try container.decodeIfPresent(String.self, forKey: .sdpMid)
            self = .ice(candidate: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        case "screenInfo":
            let width = try container.decode(Int.self, forKey: .width)
            let height = try container.decode(Int.self, forKey: .height)
            let scale = try container.decode(Double.self, forKey: .scale)
            self = .screenInfo(width: width, height: height, scale: scale)
        case "cursorPos":
            let x = try container.decode(Double.self, forKey: .x)
            let y = try container.decode(Double.self, forKey: .y)
            self = .cursorPos(x: x, y: y)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .offer(let sdp):
            try container.encode("offer", forKey: .type)
            try container.encode(sdp, forKey: .sdp)
        case .answer(let sdp):
            try container.encode("answer", forKey: .type)
            try container.encode(sdp, forKey: .sdp)
        case .ice(let candidate, let sdpMLineIndex, let sdpMid):
            try container.encode("ice", forKey: .type)
            try container.encode(candidate, forKey: .candidate)
            try container.encode(sdpMLineIndex, forKey: .sdpMLineIndex)
            try container.encodeIfPresent(sdpMid, forKey: .sdpMid)
        case .screenInfo(let width, let height, let scale):
            try container.encode("screenInfo", forKey: .type)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
            try container.encode(scale, forKey: .scale)
        case .cursorPos(let x, let y):
            try container.encode("cursorPos", forKey: .type)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        }
    }
}
