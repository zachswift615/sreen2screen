import Foundation
import CoreGraphics
import AppKit
import Shared

final class InputController {
    private var currentMouseLocation: CGPoint
    private let displayBounds: CGRect

    init() {
        currentMouseLocation = NSEvent.mouseLocation
        displayBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    func handleInput(_ message: InputMessage) {
        switch message {
        case .mouseMove(let dx, let dy):
            moveMouseRelative(dx: dx, dy: dy)

        case .mouseDown(let button):
            postMouseEvent(type: button == .left ? .leftMouseDown : .rightMouseDown, button: button)

        case .mouseUp(let button):
            postMouseEvent(type: button == .left ? .leftMouseUp : .rightMouseUp, button: button)

        case .click(let button, let count):
            for _ in 0..<count {
                postMouseEvent(type: button == .left ? .leftMouseDown : .rightMouseDown, button: button)
                postMouseEvent(type: button == .left ? .leftMouseUp : .rightMouseUp, button: button)
            }

        case .scroll(let dx, let dy):
            postScrollEvent(dx: dx, dy: dy)

        case .keyDown(let keyCode, let modifiers):
            postKeyEvent(keyCode: keyCode, modifiers: modifiers, isDown: true)

        case .keyUp(let keyCode, let modifiers):
            postKeyEvent(keyCode: keyCode, modifiers: modifiers, isDown: false)

        case .keyPress(let keyCode, let modifiers):
            postKeyEvent(keyCode: keyCode, modifiers: modifiers, isDown: true)
            postKeyEvent(keyCode: keyCode, modifiers: modifiers, isDown: false)

        case .text(let characters):
            typeText(characters)
        }
    }

    private func moveMouseRelative(dx: Double, dy: Double) {
        // Get current cursor position using CGEvent (consistent coordinate system)
        guard let currentEvent = CGEvent(source: nil) else { return }
        var location = currentEvent.location

        // Apply relative movement
        location.x += CGFloat(dx)
        location.y += CGFloat(dy)

        // Clamp to screen bounds (CGEvent uses top-left origin)
        location.x = max(0, min(location.x, displayBounds.width))
        location.y = max(0, min(location.y, displayBounds.height))

        if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }

        currentMouseLocation = location
    }

    private func postMouseEvent(type: CGEventType, button: MouseButton) {
        let cgButton: CGMouseButton = button == .left ? .left : .right
        let location = CGEvent(source: nil)?.location ?? currentMouseLocation

        if let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: cgButton) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func postScrollEvent(dx: Double, dy: Double) {
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func postKeyEvent(keyCode: UInt16, modifiers: [String], isDown: Bool) {
        let eventType: CGEventType = isDown ? .keyDown : .keyUp

        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isDown) else {
            return
        }

        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier.lowercased() {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "ctrl", "control":
                flags.insert(.maskControl)
            case "alt", "option":
                flags.insert(.maskAlternate)
            case "shift":
                flags.insert(.maskShift)
            default:
                break
            }
        }

        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func typeText(_ text: String) {
        for char in text {
            let string = String(char)
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                event.keyboardSetUnicodeString(stringLength: string.count, unicodeString: Array(string.utf16))
                event.post(tap: .cghidEventTap)
            }
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                event.post(tap: .cghidEventTap)
            }
        }
    }
}
