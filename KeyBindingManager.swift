import Cocoa

enum KeyAction {
    case tapAt(CGPoint)
    case home
    case swipe(SwipeDirection)
}

class KeyBindingManager {

    var onAction: ((KeyAction) -> Void)?

    private var keyBindings: [UInt16: KeyAction] = [:]

    private static let keyNameMap: [String: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03,
        "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
        "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
        "7": 0x1A, "8": 0x1C, "0": 0x1D,
        "n": 0x2D, "m": 0x2E,
        "space": 0x31, "tab": 0x30,
        "return": 0x24, "enter": 0x24,
        "escape": 0x35, "esc": 0x35,
        "up": 0x7E, "down": 0x7D,
        "left": 0x7B, "right": 0x7C,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63,
        "f4": 0x76, "f5": 0x60, "f6": 0x61,
        "f7": 0x62, "f8": 0x64, "f9": 0x65,
        "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
    ]

    init() {
        loadBindings()
    }

    func loadBindings() {
        keyBindings.removeAll()

        let homeURL = URL(fileURLWithPath: "\(FileManager.default.homeDirectoryForCurrentUser.path)/Documents/Dofus/iPhoneMirror/keybindings.json")
        let bundleURL = Bundle.main.url(forResource: "keybindings", withExtension: "json")
        let fileURL: URL? = FileManager.default.fileExists(atPath: homeURL.path) ? homeURL : bundleURL
        guard let url = fileURL else {
            print("[KeyBinding] No keybindings.json found at \(homeURL.path)")
            setupDefaults()
            return
        }

        print("[KeyBinding] Loading from: \(url.path)")

        guard let data = try? Data(contentsOf: url) else {
            print("[KeyBinding] Cannot read file")
            setupDefaults()
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[KeyBinding] Cannot parse JSON")
            setupDefaults()
            return
        }

        guard let bindingsDict = json["bindings"] as? [String: String] else {
            print("[KeyBinding] 'bindings' key not found or wrong type. Keys: \(Array(json.keys))")
            setupDefaults()
            return
        }

        print("[KeyBinding] Found \(bindingsDict.count) bindings: \(bindingsDict)")
        for (key, value) in bindingsDict {
            parseBinding(key: key, value: value)
        }

        print("[KeyBinding] Loaded \(keyBindings.count) bindings")
    }

    private func parseBinding(key: String, value: String) {
        guard let keyCode = Self.keyNameMap[key.lowercased()] else {
            print("[KeyBinding] Unknown key: '\(key)'")
            return
        }

        let parts = value.split(separator: ":").map(String.init)
        guard let action = parts.first else { return }

        switch action {
        case "home":
            keyBindings[keyCode] = .home

        case "tap":
            let coords = parts.count >= 3 ? "\(parts[1]):\(parts[2])" : (parts.count == 2 ? parts[1] : "")
            let xy = coords.split(separator: ",").map(String.init)
            if xy.count == 2,
               let x = Double(xy[0]),
               let y = Double(xy[1]) {
                keyBindings[keyCode] = .tapAt(CGPoint(x: x, y: y))
            } else if parts.count >= 3,
                      let x = Double(parts[1]),
                      let y = Double(parts[2]) {
                keyBindings[keyCode] = .tapAt(CGPoint(x: x, y: y))
            }

        case "swipe":
            if let dir = parts.dropFirst().first {
                switch dir {
                case "up":    keyBindings[keyCode] = .swipe(.up)
                case "down":  keyBindings[keyCode] = .swipe(.down)
                case "left":  keyBindings[keyCode] = .swipe(.left)
                case "right": keyBindings[keyCode] = .swipe(.right)
                default: break
                }
            }

        default:
            break
        }
    }

    private func setupDefaults() {
        let center = CGPoint(x: 0.5, y: 0.5)
        keyBindings[0x31] = .tapAt(center)
        keyBindings[0x24] = .home
        keyBindings[0x35] = .home
        keyBindings[0x7E] = .swipe(.up)
        keyBindings[0x7D] = .swipe(.down)
        keyBindings[0x7B] = .swipe(.left)
        keyBindings[0x7C] = .swipe(.right)
    }

    func setBinding(keyCode: UInt16, action: KeyAction) {
        keyBindings[keyCode] = action
    }

    func removeBinding(keyCode: UInt16) {
        keyBindings.removeValue(forKey: keyCode)
    }

    func handleKeyPress(_ event: NSEvent) {
        if let action = keyBindings[event.keyCode] {
            onAction?(action)
        }
    }
}
