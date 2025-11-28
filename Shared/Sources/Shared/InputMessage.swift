import Foundation

public enum MouseButton: String, Codable {
    case left
    case right
}

public enum InputMessage: Codable {
    case mouseMove(dx: Double, dy: Double)
    case mouseDown(button: MouseButton)
    case mouseUp(button: MouseButton)
    case click(button: MouseButton, count: Int)
    case scroll(dx: Double, dy: Double)
    case keyDown(keyCode: UInt16, modifiers: [String])
    case keyUp(keyCode: UInt16, modifiers: [String])
    case keyPress(keyCode: UInt16, modifiers: [String])
    case text(characters: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case dx, dy
        case button
        case count
        case keyCode
        case modifiers
        case characters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "mouseMove":
            let dx = try container.decode(Double.self, forKey: .dx)
            let dy = try container.decode(Double.self, forKey: .dy)
            self = .mouseMove(dx: dx, dy: dy)
        case "mouseDown":
            let button = try container.decode(MouseButton.self, forKey: .button)
            self = .mouseDown(button: button)
        case "mouseUp":
            let button = try container.decode(MouseButton.self, forKey: .button)
            self = .mouseUp(button: button)
        case "click":
            let button = try container.decode(MouseButton.self, forKey: .button)
            let count = try container.decode(Int.self, forKey: .count)
            self = .click(button: button, count: count)
        case "scroll":
            let dx = try container.decode(Double.self, forKey: .dx)
            let dy = try container.decode(Double.self, forKey: .dy)
            self = .scroll(dx: dx, dy: dy)
        case "keyDown":
            let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
            let modifiers = try container.decode([String].self, forKey: .modifiers)
            self = .keyDown(keyCode: keyCode, modifiers: modifiers)
        case "keyUp":
            let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
            let modifiers = try container.decode([String].self, forKey: .modifiers)
            self = .keyUp(keyCode: keyCode, modifiers: modifiers)
        case "keyPress":
            let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
            let modifiers = try container.decode([String].self, forKey: .modifiers)
            self = .keyPress(keyCode: keyCode, modifiers: modifiers)
        case "text":
            let characters = try container.decode(String.self, forKey: .characters)
            self = .text(characters: characters)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .mouseMove(let dx, let dy):
            try container.encode("mouseMove", forKey: .type)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)
        case .mouseDown(let button):
            try container.encode("mouseDown", forKey: .type)
            try container.encode(button, forKey: .button)
        case .mouseUp(let button):
            try container.encode("mouseUp", forKey: .type)
            try container.encode(button, forKey: .button)
        case .click(let button, let count):
            try container.encode("click", forKey: .type)
            try container.encode(button, forKey: .button)
            try container.encode(count, forKey: .count)
        case .scroll(let dx, let dy):
            try container.encode("scroll", forKey: .type)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)
        case .keyDown(let keyCode, let modifiers):
            try container.encode("keyDown", forKey: .type)
            try container.encode(keyCode, forKey: .keyCode)
            try container.encode(modifiers, forKey: .modifiers)
        case .keyUp(let keyCode, let modifiers):
            try container.encode("keyUp", forKey: .type)
            try container.encode(keyCode, forKey: .keyCode)
            try container.encode(modifiers, forKey: .modifiers)
        case .keyPress(let keyCode, let modifiers):
            try container.encode("keyPress", forKey: .type)
            try container.encode(keyCode, forKey: .keyCode)
            try container.encode(modifiers, forKey: .modifiers)
        case .text(let characters):
            try container.encode("text", forKey: .type)
            try container.encode(characters, forKey: .characters)
        }
    }
}
