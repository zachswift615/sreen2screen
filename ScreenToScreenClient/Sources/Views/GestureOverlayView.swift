import SwiftUI
import UIKit
import Shared

struct GestureOverlayView: UIViewRepresentable {
    let gestureController: GestureController

    func makeUIView(context: Context) -> GestureOverlayUIView {
        let view = GestureOverlayUIView()
        gestureController.setupGestures(on: view)
        return view
    }

    func updateUIView(_ uiView: GestureOverlayUIView, context: Context) {}
}

class GestureOverlayUIView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
