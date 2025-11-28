import Foundation
import ScreenCaptureKit
import CoreMedia
import Shared

protocol ScreenCaptureServiceDelegate: AnyObject {
    func screenCaptureService(_ service: ScreenCaptureService, didOutputSampleBuffer sampleBuffer: CMSampleBuffer)
    func screenCaptureService(_ service: ScreenCaptureService, didFailWithError error: Error)
}

final class ScreenCaptureService: NSObject {
    weak var delegate: ScreenCaptureServiceDelegate?

    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var selectedDisplay: SCDisplay?

    private(set) var isCapturing = false
    private(set) var availableDisplays: [SCDisplay] = []

    override init() {
        super.init()
    }

    func requestPermissionAndLoadDisplays() async throws {
        // This triggers the permission prompt if needed
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        availableDisplays = content.displays

        // Default to main display
        selectedDisplay = availableDisplays.first { $0.displayID == CGMainDisplayID() }
            ?? availableDisplays.first
    }

    func selectDisplay(_ display: SCDisplay) {
        selectedDisplay = display
    }

    func startCapture(frameRate: Int = Constants.defaultFrameRate) async throws {
        guard let display = selectedDisplay else {
            throw ScreenCaptureError.noDisplaySelected
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        // Get actual scale factor (not all displays are Retina)
        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        config.width = Int(Double(display.width) * scaleFactor)
        config.height = Int(Double(display.height) * scaleFactor)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        stream = SCStream(filter: filter, configuration: config, delegate: self)

        streamOutput = StreamOutput { [weak self] sampleBuffer in
            guard let self = self else { return }
            self.delegate?.screenCaptureService(self, didOutputSampleBuffer: sampleBuffer)
        }

        try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: .main)
        try await stream?.startCapture()

        isCapturing = true
        print("Screen capture started for display: \(display.displayID)")
    }

    func stopCapture() async throws {
        try await stream?.stopCapture()
        stream = nil
        streamOutput = nil
        isCapturing = false
        print("Screen capture stopped")
    }

    var currentDisplayInfo: (width: Int, height: Int, scale: Double)? {
        guard let display = selectedDisplay else { return nil }
        let scaleFactor = Double(NSScreen.main?.backingScaleFactor ?? 2.0)
        return (
            width: display.width,
            height: display.height,
            scale: scaleFactor
        )
    }
}

extension ScreenCaptureService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isCapturing = false
        delegate?.screenCaptureService(self, didFailWithError: error)
    }
}

private class StreamOutput: NSObject, SCStreamOutput {
    private let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        handler(sampleBuffer)
    }
}

enum ScreenCaptureError: Error {
    case noDisplaySelected
    case permissionDenied
}
