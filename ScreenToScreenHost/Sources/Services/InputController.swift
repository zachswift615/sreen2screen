import Foundation
import CoreGraphics
import AppKit
import Shared

final class InputController {
    private var currentMouseLocation: CGPoint

    // The display bounds in global screen coordinates (CGEvent coordinate system: top-left origin)
    private var displayBounds: CGRect

    init() {
        currentMouseLocation = NSEvent.mouseLocation
        // Default to main display
        if let mainScreen = NSScreen.main {
            displayBounds = InputController.cgEventBounds(for: mainScreen)
        } else {
            displayBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        }
    }

    /// Set the target display for mouse input. Pass the NSScreen corresponding to the captured display.
    func setTargetDisplay(_ screen: NSScreen) {
        displayBounds = InputController.cgEventBounds(for: screen)
        print("InputController: Target display set to \(displayBounds)")
    }

    /// Convert NSScreen frame (bottom-left origin) to CGEvent bounds (top-left origin)
    private static func cgEventBounds(for screen: NSScreen) -> CGRect {
        // NSScreen uses bottom-left origin, CGEvent uses top-left origin
        // We need to find the global top-left coordinate for this screen

        // Get the primary screen's height for coordinate conversion
        guard let primaryScreen = NSScreen.screens.first else {
            return screen.frame
        }

        let primaryHeight = primaryScreen.frame.height

        // Convert: In CGEvent coords, y=0 is at top of primary screen
        // NSScreen's frame.origin.y is distance from bottom of primary screen
        let cgEventY = primaryHeight - screen.frame.origin.y - screen.frame.height

        return CGRect(
            x: screen.frame.origin.x,
            y: cgEventY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }

    /// Convert global CGEvent coordinates to display-local coordinates (for sending to client)
    func globalToLocal(_ point: CGPoint) -> CGPoint {
        return CGPoint(
            x: point.x - displayBounds.minX,
            y: point.y - displayBounds.minY
        )
    }

    /// Returns the current cursor position after handling input (in display-local coordinates, top-left origin)
    @discardableResult
    func handleInput(_ message: InputMessage) -> CGPoint? {
        switch message {
        case .mouseMove(let dx, let dy):
            moveMouseRelative(dx: dx, dy: dy)
            return globalToLocal(currentMouseLocation)

        case .mouseDown(let button):
            postMouseEvent(type: button == .left ? .leftMouseDown : .rightMouseDown, button: button)
            return globalToLocal(currentMouseLocation)

        case .mouseUp(let button):
            postMouseEvent(type: button == .left ? .leftMouseUp : .rightMouseUp, button: button)
            return globalToLocal(currentMouseLocation)

        case .click(let button, let count):
            for _ in 0..<count {
                postMouseEvent(type: button == .left ? .leftMouseDown : .rightMouseDown, button: button)
                postMouseEvent(type: button == .left ? .leftMouseUp : .rightMouseUp, button: button)
            }
            return globalToLocal(currentMouseLocation)

        case .scroll(let dx, let dy):
            postScrollEvent(dx: dx, dy: dy)
            return nil

        case .keyDown(let keyCode, let modifiers):
            postKeyEvent(keyCode: keyCode, modifiers: modifiers, isDown: true)
            return nil

        case .keyUp(let keyCode, let modifiers):
            postKeyEvent(keyCode: keyCode, modifiers: modifiers, isDown: false)
            return nil

        case .keyPress(let keyCode, let modifiers):
            postKeyEvent(keyCode: keyCode, modifiers: modifiers, isDown: true)
            postKeyEvent(keyCode: keyCode, modifiers: modifiers, isDown: false)
            return nil

        case .text(let characters):
            typeText(characters)
            return nil
        }
    }

    private func moveMouseRelative(dx: Double, dy: Double) {
        // Get current cursor position using CGEvent (consistent coordinate system)
        guard let currentEvent = CGEvent(source: nil) else { return }
        var location = currentEvent.location

        // Apply relative movement
        location.x += CGFloat(dx)
        location.y += CGFloat(dy)

        // Clamp to target display bounds (in global CGEvent coordinates)
        location.x = max(displayBounds.minX, min(location.x, displayBounds.maxX - 1))
        location.y = max(displayBounds.minY, min(location.y, displayBounds.maxY - 1))

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
