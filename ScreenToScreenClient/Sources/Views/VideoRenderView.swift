import SwiftUI
import WebRTC

struct VideoRenderView: UIViewRepresentable {
    let videoTrack: RTCVideoTrack?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFit
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
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

    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
        // Remove track when view is dismantled
        coordinator.currentTrack?.remove(uiView)
        coordinator.currentTrack = nil
    }

    class Coordinator {
        var currentTrack: RTCVideoTrack?
    }
}
