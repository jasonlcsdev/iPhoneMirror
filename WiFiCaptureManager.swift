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
                print("[WiFi] Failed to get shareable content: \(error.localizedDescription)")
                self.delegate?.wifiCaptureDidError(error.localizedDescription)
                return
            }

            guard let content = content else {
                print("[WiFi] No shareable content")
                self.delegate?.wifiCaptureDidError("No screens available")
                return
            }

            guard let display = content.displays.first else {
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

    private func cropToAirPlayWindow(_ image: CGImage) -> CGImage? {
        guard let window = findAirPlayWindow() else {
            return nil
        }

        let wf = window.frame
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)

        guard wf.width > 0, wf.height > 0, imgW > 0, imgH > 0 else {
            return nil
        }

        let scaleX = imgW / wf.width
        let scaleY = imgH / wf.height

        let cropX = wf.origin.x * scaleX
        let cropH = wf.height * scaleY
        let cropY = (wf.height - wf.origin.y - wf.height) * scaleY
        let cropW = wf.width * scaleX

        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)

        guard cropRect.width > 0, cropRect.height > 0,
              cropRect.minX >= 0, cropRect.minY >= 0,
              cropRect.maxX <= imgW, cropRect.maxY <= imgH,
              let cropped = image.cropping(to: cropRect) else {
            return nil
        }
        return cropped
    }
}

extension WiFiCaptureManager: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        if let cropped = cropToAirPlayWindow(cgImage) {
            DispatchQueue.main.async {
                self.onFrame?(cropped)
            }
        } else {
            DispatchQueue.main.async {
                self.onFrame?(cgImage)
            }
        }
    }
}
