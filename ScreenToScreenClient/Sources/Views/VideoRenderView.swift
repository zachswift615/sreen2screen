import SwiftUI
import LiveKitWebRTC

struct VideoRenderView: UIViewRepresentable {
    let videoTrack: LKRTCVideoTrack?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> LKRTCMTLVideoView {
        let view = LKRTCMTLVideoView()
        view.videoContentMode = .scaleAspectFit
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: LKRTCMTLVideoView, context: Context) {
        // Remove old track if different
        if let oldTrack = context.coordinator.currentTrack, oldTrack != videoTrack {
            oldTrack.remove(uiView)
            context.coordinator.currentTrack = nil
        }

        // Add new track if not already added
        if let track = videoTrack, context.coordinator.currentTrack == nil {
            track.add(uiView)
            context.coordinator.currentTrack = track
        }
    }

    static func dismantleUIView(_ uiView: LKRTCMTLVideoView, coordinator: Coordinator) {
        // Remove track when view is dismantled
        coordinator.currentTrack?.remove(uiView)
        coordinator.currentTrack = nil
    }

    class Coordinator {
        var currentTrack: LKRTCVideoTrack?
    }
}
