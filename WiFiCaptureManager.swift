import Cocoa
import ScreenCaptureKit

protocol WiFiCaptureDelegate: AnyObject {
    func wifiCaptureDidStart()
    func wifiCaptureDidStop()
    func wifiCaptureDidError(_ error: String)
}

class WiFiCaptureManager: NSObject, SCStreamDelegate {

    weak var delegate: WiFiCaptureDelegate?
    private var stream: SCStream?
    private var isCapturing = false

    var onFrame: ((CGImage) -> Void)?

    func startCapture() {
        guard !isCapturing else { return }

        SCShareableContent.getWithCompletionHandler { [weak self] content, error in
            guard let self = self else { return }

            if let error = error {
                print("[WiFi] Failed to get shareable content: \(error.localizedDescription)")
                self.delegate?.wifiCaptureDidError(error.localizedDescription)
                return
            }

            guard let content = content else {
                print("[WiFi] No shareable content")
                self.delegate?.wifiCaptureDidError("No screens available")
                return
            }

            let displays = content.displays
            guard let display = displays.first else {
                print("[WiFi] No display found")
                self.delegate?.wifiCaptureDidError("No display found")
                return
            }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

            let config = SCStreamConfiguration()
            config.width = Int(display.width) * 2
            config.height = Int(display.height) * 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false

            let stream = SCStream(filter: filter, configuration: config, delegate: self)

            do {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "wifi.capture"))
                try stream.startCapture()
                self.stream = stream
                self.isCapturing = true
                print("[WiFi] Screen capture started")
                self.delegate?.wifiCaptureDidStart()
            } catch {
                print("[WiFi] Failed to start capture: \(error.localizedDescription)")
                self.delegate?.wifiCaptureDidError(error.localizedDescription)
            }
        }
    }

    func stopCapture() {
        stream?.stopCapture()
        stream = nil
        isCapturing = false
        print("[WiFi] Screen capture stopped")
        delegate?.wifiCaptureDidStop()
    }

    func getWindows() -> [SCWindow] {
        var windows: [SCWindow] = []
        let group = DispatchGroup()
        group.enter()
        SCShareableContent.getWithCompletionHandler { content, _ in
            windows = content?.windows ?? []
            group.leave()
        }
        group.wait()
        return windows
    }

    func findAirPlayWindow() -> SCWindow? {
        let windows = getWindows()
        for window in windows {
            let title = window.title ?? ""
            let app = window.owningApplication?.bundleIdentifier ?? ""
            let combined = "\(title) \(app)".lowercased()
            if combined.contains("airplay") || combined.contains("iphone") || combined.contains("mirror") {
                return window
            }
        }
        return nil
    }
}

extension WiFiCaptureManager: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        DispatchQueue.main.async {
            self.onFrame?(cgImage)
        }
    }
}
