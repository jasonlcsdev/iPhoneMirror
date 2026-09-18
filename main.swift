import Cocoa
import CoreMediaIO

func enableScreenCaptureDevices() {
    var address = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(0)
    )
    var allow: UInt32 = 1
    CMIOObjectSetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject),
        &address,
        0, nil,
        UInt32(MemoryLayout<UInt32>.size),
        &allow
    )
    print("[iPhoneMirror] CMIOExtensionAllowScreenCaptureDevices enabled")
}

enableScreenCaptureDevices()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
