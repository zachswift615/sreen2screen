import SwiftUI
import WebRTC

struct VideoRenderView: UIViewRepresentable {
    let videoTrack: RTCVideoTrack?

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFit
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        if let track = videoTrack {
            track.add(uiView)
        }
    }

    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: ()) {
        // Track will be removed when view is deallocated
    }
}
