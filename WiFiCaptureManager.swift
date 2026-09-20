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
    private let ciContext = CIContext()

    var onFrame: ((CGImage) -> Void)?

    func startCapture() {
        guard !isCapturing else { return }

        SCShareableContent.getWithCompletionHandler { [weak self] content, error in
            guard let self = self else { return }

            if let error = error {
                print("[WiFi] Failed to get shareable content: \(error)")
                self.delegate?.wifiCaptureDidError(error.localizedDescription)
                return
            }

            guard let content = content else {
                self.delegate?.wifiCaptureDidError("No screens available")
                return
            }

            guard let display = content.displays.first else {
                self.delegate?.wifiCaptureDidError("No display found")
                return
            }

            self.logWindows(content.windows)

            let filter: SCContentFilter
            if let airplayWindow = self.findAirPlayWindow(content.windows) {
                print("[WiFi] Capturing AirPlay window: \(airplayWindow.title ?? "?") frame=\(airplayWindow.frame)")
                filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            } else {
                print("[WiFi] No AirPlay window found, capturing full display")
                filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            }

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
                print("[WiFi] Failed to start capture: \(error)")
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

    private func logWindows(_ windows: [SCWindow]) {
        print("[WiFi] --- Available Windows ---")
        for w in windows {
            let title = w.title ?? "(nil)"
            let app = w.owningApplication?.bundleIdentifier ?? "(nil)"
            let frame = w.frame
            let isOnScreen = w.isOnScreen
            print("[WiFi]   title=\"\(title)\" app=\"\(app)\" frame=\(frame) onScreen=\(isOnScreen)")
        }
        print("[WiFi] --- End Windows ---")
    }

    func findAirPlayWindow(_ windows: [SCWindow]? = nil) -> SCWindow? {
        var wins: [SCWindow] = []
        if let provided = windows {
            wins = provided
        } else {
            let group = DispatchGroup()
            group.enter()
            SCShareableContent.getWithCompletionHandler { content, _ in
                wins = content?.windows ?? []
                group.leave()
            }
            group.wait()
        }

        for w in wins {
            let title = (w.title ?? "").lowercased()
            let app = (w.owningApplication?.bundleIdentifier ?? "").lowercased()
            let bundleName = (w.owningApplication?.applicationName ?? "").lowercased()
            let combined = "\(title) \(app) \(bundleName)"

            if combined.contains("airplay") ||
               combined.contains("mirroring") ||
               combined.contains("iphone") ||
               combined.contains("apple wireless display") ||
               (app.contains("airplay") && w.frame.width > 100) {
                return w
            }
        }

        for w in wins {
            let app = (w.owningApplication?.bundleIdentifier ?? "").lowercased()
            if app.contains("controlcenter") || app.contains("system") {
                let title = (w.title ?? "").lowercased()
                if title.contains("display") || title.contains("screen") {
                    return w
                }
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
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        DispatchQueue.main.async {
            self.onFrame?(cgImage)
        }
    }
}
