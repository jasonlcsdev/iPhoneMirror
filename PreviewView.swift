import Cocoa
import AVFoundation
import CoreMediaIO

class PreviewView: NSView, AVCaptureVideoDataOutputSampleBufferDelegate {

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let wdaClient = WDAClient()
    private let keyBindingManager = KeyBindingManager()

    private var iosScreenSize: CGSize = CGSize(width: 428, height: 926)
    private var deviceVideoSize: CGSize = .zero
    private var lastBufferWidth: Int = 0
    private var lastBufferHeight: Int = 0

    // Gesture state
    private var gestureStartViewPoint: NSPoint = .zero
    private var gestureStartTime: TimeInterval = 0
    private var isDragging = false
    private let longPressThreshold: TimeInterval = 0.5
    private let dragThreshold: CGFloat = 3.0

    // Coordinate picking mode
    private var isPickingCoords = false
    private var crosshairView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
        keyBindingManager.onAction = { [weak self] action in
            self?.handleKeyAction(action)
        }
        NotificationCenter.default.addObserver(
            forName: .init("com.iphonemirror.startPicking"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startCoordinatePicking()
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        keyBindingManager.onAction = { [weak self] action in
            self?.handleKeyAction(action)
        }
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.videoGravity = .resizeAspect
        previewLayer.masksToBounds = true
        layer?.addSublayer(previewLayer)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }

    override var acceptsFirstResponder: Bool { true }

    func reloadKeyBindings() {
        keyBindingManager.loadBindings()
        print("[iPhoneMirror] Key bindings reloaded")
    }

    func startCapture() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high

        let _ = AVCaptureDevice.devices()

        if let device = findScreenCaptureDevice() {
            setupCapture(with: device)
            return
        }

        print("[iPhoneMirror] Waiting for iOS device connection...")
        showStatusMessage("Waiting for iOS device...\nConnect iPhone via USB and trust this computer.")

        NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let device = notification.object as? AVCaptureDevice else { return }
            print("[iPhoneMirror] Device connected: \(device.localizedName) [\(device.uniqueID)] model=\(device.modelID)")
            guard self?.captureSession?.inputs.isEmpty ?? true else { return }
            self?.setupCapture(with: device)
        }
    }

    private func setupCapture(with device: AVCaptureDevice) {
        print("[iPhoneMirror] Using device: \(device.localizedName) [\(device.uniqueID)] model=\(device.modelID)")

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession!.canAddInput(input) {
                captureSession!.addInput(input)
                print("[iPhoneMirror] Input added successfully")
            } else {
                showStatusMessage("Cannot use device: \(device.localizedName)")
                return
            }

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            let videoQueue = DispatchQueue(label: "mirror.video")
            output.setSampleBufferDelegate(self, queue: videoQueue)
            if captureSession!.canAddOutput(output) {
                captureSession!.addOutput(output)
            }

            updateDeviceResolution(device)
            previewLayer.session = captureSession

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }

            print("[iPhoneMirror] Capture started: \(device.localizedName) @ \(Int(deviceVideoSize.width))x\(Int(deviceVideoSize.height))")
            removeStatusMessage()

        } catch {
            print("[iPhoneMirror] Failed to create input: \(error)")
            showStatusMessage("Failed to access device:\n\(error.localizedDescription)")
        }
    }

    // MARK: - Rotation Detection via Sample Buffer

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard width > 0 && height > 0 else { return }

        if width != lastBufferWidth || height != lastBufferHeight {
            lastBufferWidth = width
            lastBufferHeight = height

            let isLandscape = width > height
            let basePortrait = CGSize(width: 428, height: 926)
            let newSize = isLandscape ? CGSize(width: basePortrait.height, height: basePortrait.width) : basePortrait

            if newSize != iosScreenSize {
                iosScreenSize = newSize
                print("[iPhoneMirror] Orientation: \(isLandscape ? "landscape" : "portrait") -> iOS \(Int(newSize.width))x\(Int(newSize.height))")

                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .init("com.iphonemirror.rotation"),
                        object: nil,
                        userInfo: ["landscape": isLandscape]
                    )
                }
            }
        }
    }

    private func findScreenCaptureDevice() -> AVCaptureDevice? {
        var discoverySession: AVCaptureDevice.DiscoverySession!

        if #available(macOS 14.0, *) {
            discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external],
                mediaType: .muxed,
                position: .unspecified
            )
        } else {
            discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.externalUnknown],
                mediaType: .muxed,
                position: .unspecified
            )
        }

        print("[iPhoneMirror] Found \(discoverySession.devices.count) muxed device(s):")
        for device in discoverySession.devices {
            print("  - \(device.localizedName) [\(device.uniqueID)] model=\(device.modelID) transport=\(device.transportType)")
        }

        for device in discoverySession.devices {
            let model = device.modelID
            let name = device.localizedName
            if model.lowercased().contains("iphone") || model.lowercased().contains("ios") ||
               name.lowercased().contains("iphone") || name.lowercased().contains("ios") ||
               model == "iOS Device" {
                return device
            }
        }

        return nil
    }

    private func updateDeviceResolution(_ device: AVCaptureDevice) {
        let format = device.activeFormat
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)

        if dims.width > 0 && dims.height > 0 {
            deviceVideoSize = CGSize(width: CGFloat(dims.width), height: CGFloat(dims.height))
        } else {
            let model = device.modelID
            if model.contains("iPhone14,3") || model.contains("iPhone15,3") {
                iosScreenSize = CGSize(width: 430, height: 932)
            } else if model.contains("iPhone14,2") || model.contains("iPhone15,2") {
                iosScreenSize = CGSize(width: 393, height: 852)
            } else if model.contains("iPhone14,4") || model.contains("iPhone15,4") {
                iosScreenSize = CGSize(width: 390, height: 844)
            } else {
                iosScreenSize = CGSize(width: 428, height: 926)
            }
            print("[iPhoneMirror] Format reports 0x0, using default: \(Int(iosScreenSize.width))x\(Int(iosScreenSize.height)) for \(model)")
        }

        print("[iPhoneMirror] iOS point resolution: \(Int(iosScreenSize.width))x\(Int(iosScreenSize.height))")
    }

    // MARK: - Coordinate Mapping

    private func mapToIOSCoords(viewPoint: NSPoint) -> CGPoint {
        let layerFrame = previewLayer.frame

        guard iosScreenSize.width > 0, iosScreenSize.height > 0,
              layerFrame.width > 0, layerFrame.height > 0 else {
            return CGPoint(x: iosScreenSize.width / 2, y: iosScreenSize.height / 2)
        }

        let videoAspect = iosScreenSize.width / iosScreenSize.height
        let layerAspect = layerFrame.width / layerFrame.height

        var displayWidth: CGFloat
        var displayHeight: CGFloat
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0

        if videoAspect > layerAspect {
            displayWidth = layerFrame.width
            displayHeight = layerFrame.width / videoAspect
            offsetY = (layerFrame.height - displayHeight) / 2.0
        } else {
            displayHeight = layerFrame.height
            displayWidth = layerFrame.height * videoAspect
            offsetX = (layerFrame.width - displayWidth) / 2.0
        }

        let localX = viewPoint.x - layerFrame.origin.x - offsetX
        let localY = viewPoint.y - layerFrame.origin.y - offsetY

        let normalizedX = max(0, min(1, localX / displayWidth))
        let normalizedY = max(0, min(1, localY / displayHeight))

        return CGPoint(
            x: normalizedX * iosScreenSize.width,
            y: (1 - normalizedY) * iosScreenSize.height
        )
    }

    // MARK: - Coordinate Picking Mode

    private func startCoordinatePicking() {
        isPickingCoords = true
        showCrosshair()
        window?.makeKeyAndOrderFront(nil)
    }

    private func showCrosshair() {
        crosshairView?.removeFromSuperview()

        let size: CGFloat = 40
        let container = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        container.wantsLayer = true

        let hLine = NSView(frame: NSRect(x: 0, y: size/2 - 1, width: size, height: 2))
        hLine.wantsLayer = true
        hLine.layer?.backgroundColor = NSColor.red.cgColor
        container.addSubview(hLine)

        let vLine = NSView(frame: NSRect(x: size/2 - 1, y: 0, width: 2, height: size))
        vLine.wantsLayer = true
        vLine.layer?.backgroundColor = NSColor.red.cgColor
        container.addSubview(vLine)

        let circle = NSView(frame: NSRect(x: size/2 - 8, y: size/2 - 8, width: 16, height: 16))
        circle.wantsLayer = true
        circle.layer?.borderColor = NSColor.red.cgColor
        circle.layer?.borderWidth = 2
        circle.layer?.cornerRadius = 8
        container.addSubview(circle)

        addSubview(container)
        crosshairView = container

        updateCrosshairPosition(NSPoint(x: bounds.midX, y: bounds.midY))
    }

    private func updateCrosshairPosition(_ viewPoint: NSPoint) {
        guard let crosshair = crosshairView else { return }
        crosshair.frame.origin = NSPoint(
            x: viewPoint.x - crosshair.frame.width / 2,
            y: viewPoint.y - crosshair.frame.height / 2
        )
    }

    private func hideCrosshair() {
        crosshairView?.removeFromSuperview()
        crosshairView = nil
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        if isPickingCoords {
            isPickingCoords = false
            hideCrosshair()

            let iosPoint = mapToIOSCoords(viewPoint: location)
            let maxX = iosScreenSize.width
            let maxY = iosScreenSize.height
            NotificationCenter.default.post(
                name: .init("com.iphonemirror.coordsPicked"),
                object: nil,
                userInfo: [
                    "x": iosPoint.x / maxX,
                    "y": iosPoint.y / maxY
                ]
            )
            return
        }

        gestureStartViewPoint = location
        gestureStartTime = ProcessInfo.processInfo.systemUptime
        isDragging = false
    }

    override func mouseMoved(with event: NSEvent) {
        if isPickingCoords {
            let location = convert(event.locationInWindow, from: nil)
            updateCrosshairPosition(location)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let dx = location.x - gestureStartViewPoint.x
        let dy = location.y - gestureStartViewPoint.y
        let dist = sqrt(dx * dx + dy * dy)
        let elapsed = ProcessInfo.processInfo.systemUptime - gestureStartTime

        if isDragging {
            let fromIOS = mapToIOSCoords(viewPoint: gestureStartViewPoint)
            let toIOS = mapToIOSCoords(viewPoint: location)
            let swipeDist = sqrt(
                pow(toIOS.x - fromIOS.x, 2) + pow(toIOS.y - fromIOS.y, 2)
            )
            if swipeDist > 30 {
                wdaClient.swipe(from: fromIOS, to: toIOS, duration: max(0.2, min(0.6, elapsed)))
            }
        } else if elapsed >= longPressThreshold {
            let iosPoint = mapToIOSCoords(viewPoint: location)
            wdaClient.longPress(at: iosPoint, duration: elapsed)
        } else {
            let iosPoint = mapToIOSCoords(viewPoint: location)
            wdaClient.tap(at: iosPoint)
        }

        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let dx = location.x - gestureStartViewPoint.x
        let dy = location.y - gestureStartViewPoint.y
        let dist = sqrt(dx * dx + dy * dy)

        if dist > dragThreshold {
            isDragging = true
        }
    }

    // MARK: - Scroll / Swipe via Trackpad/Mouse wheel

    override func scrollWheel(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let iosPoint = mapToIOSCoords(viewPoint: location)

        let scrollX = event.scrollingDeltaX
        let scrollY = event.scrollingDeltaY

        if abs(scrollY) > abs(scrollX) && abs(scrollY) > 0.5 {
            let fromIOS = CGPoint(x: iosPoint.x, y: iosPoint.y - scrollY * 50)
            let toIOS = CGPoint(x: iosPoint.x, y: iosPoint.y + scrollY * 50)
            wdaClient.swipe(from: fromIOS, to: toIOS, duration: 0.15)
        } else if abs(scrollX) > 0.5 {
            let fromIOS = CGPoint(x: iosPoint.x - scrollX * 50, y: iosPoint.y)
            let toIOS = CGPoint(x: iosPoint.x + scrollX * 50, y: iosPoint.y)
            wdaClient.swipe(from: fromIOS, to: toIOS, duration: 0.15)
        }
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        keyBindingManager.handleKeyPress(event)
    }

    override func keyUp(with event: NSEvent) {
    }

    // MARK: - Key Actions

    private func handleKeyAction(_ action: KeyAction) {
        switch action {
        case .tapAt(let normalizedPoint):
            let iosPoint = CGPoint(
                x: normalizedPoint.x * iosScreenSize.width,
                y: normalizedPoint.y * iosScreenSize.height
            )
            wdaClient.tap(at: iosPoint)

        case .home:
            wdaClient.pressHome()

        case .swipe(let direction):
            wdaClient.swipe(direction: direction, screenSize: iosScreenSize)
        }
    }

    // MARK: - Status Overlay

    private var statusLabel: NSTextField?

    private func showStatusMessage(_ message: String) {
        removeStatusMessage()
        let label = NSTextField(labelWithString: message)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        label.frame = bounds.insetBy(dx: 20, dy: 0)
        label.autoresizingMask = [.width, .height]
        label.tag = 999
        addSubview(label)
        statusLabel = label
    }

    private func removeStatusMessage() {
        statusLabel?.removeFromSuperview()
        statusLabel = nil
    }
}
