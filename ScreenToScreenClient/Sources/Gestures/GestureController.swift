import UIKit
import Shared

protocol GestureControllerDelegate: AnyObject {
    func gestureController(_ controller: GestureController, didGenerateInput message: InputMessage)
}

final class GestureController: NSObject {
    weak var delegate: GestureControllerDelegate?

    private let cursorState: CursorState
    private var lastPanLocation: CGPoint?

    init(cursorState: CursorState) {
        self.cursorState = cursorState
        super.init()
    }

    func setupGestures(on view: UIView) {
        // Pan gesture for cursor movement
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        view.addGestureRecognizer(panGesture)

        // Tap for left click
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.numberOfTouchesRequired = 1
        view.addGestureRecognizer(tapGesture)

        // Double tap for double click
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.numberOfTouchesRequired = 1
        view.addGestureRecognizer(doubleTapGesture)
        tapGesture.require(toFail: doubleTapGesture)

        // Two-finger tap for right click
        let twoFingerTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTapGesture.numberOfTapsRequired = 1
        twoFingerTapGesture.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoFingerTapGesture)

        // Two-finger pan for scroll
        let scrollGesture = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scrollGesture.minimumNumberOfTouches = 2
        scrollGesture.maximumNumberOfTouches = 2
        view.addGestureRecognizer(scrollGesture)

        // Pinch for zoom (client-side only, handled separately)
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: gesture.view)

        switch gesture.state {
        case .began:
            lastPanLocation = location
        case .changed:
            guard let last = lastPanLocation else { return }

            let dx = location.x - last.x
            let dy = location.y - last.y

            // Scale movement (adjust sensitivity)
            let sensitivity: CGFloat = 1.5
            let message = InputMessage.mouseMove(dx: Double(dx * sensitivity), dy: Double(dy * sensitivity))
            delegate?.gestureController(self, didGenerateInput: message)

            lastPanLocation = location
        case .ended, .cancelled:
            lastPanLocation = nil
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let message = InputMessage.click(button: .left, count: 1)
        delegate?.gestureController(self, didGenerateInput: message)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let message = InputMessage.click(button: .left, count: 2)
        delegate?.gestureController(self, didGenerateInput: message)
    }

    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        let message = InputMessage.click(button: .right, count: 1)
        delegate?.gestureController(self, didGenerateInput: message)
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed else { return }

        let velocity = gesture.velocity(in: gesture.view)

        // Scale scroll amount
        let dx = -velocity.x / 50
        let dy = -velocity.y / 50

        let message = InputMessage.scroll(dx: Double(dx), dy: Double(dy))
        delegate?.gestureController(self, didGenerateInput: message)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        // Pinch zoom is handled client-side only (view transform)
        // This placeholder allows the gesture to be recognized
    }

    // Called from keyboard view
    func sendKeyPress(keyCode: UInt16) {
        let message = InputMessage.keyPress(keyCode: keyCode, modifiers: cursorState.modifierArray)
        delegate?.gestureController(self, didGenerateInput: message)

        // Clear modifiers after key press (like TeamViewer)
        cursorState.clearModifiers()
    }

    func sendText(_ text: String) {
        let message = InputMessage.text(characters: text)
        delegate?.gestureController(self, didGenerateInput: message)
    }
}
