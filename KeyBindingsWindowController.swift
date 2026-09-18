import Cocoa

class KeyBindingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private var bindings: [(key: String, action: String)] = []
    private var tableView: NSTableView!
    private var recordingKey: Bool = false
    private var pickingCoords: Bool = false
    private var pendingKeyCode: UInt16 = 0
    private var pendingKeyName: String = ""
    private var addButton: NSButton!
    private var deleteButton: NSButton!
    private var saveButton: NSButton!
    private var statusLabel: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Key Bindings"
        window.center()

        self.init(window: window)
        setupUI()
        loadBindings()

        NotificationCenter.default.addObserver(
            forName: .init("com.iphonemirror.coordsPicked"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleCoordsPicked(note)
        }
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "Press a key, then choose an action")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.frame = NSRect(x: 20, y: 365, width: 480, height: 20)
        contentView.addSubview(titleLabel)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .systemBlue
        statusLabel.frame = NSRect(x: 20, y: 345, width: 480, height: 16)
        contentView.addSubview(statusLabel)

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 60, width: 480, height: 280))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 32

        let keyCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("key"))
        keyCol.title = "Key"
        keyCol.width = 80
        tableView.addTableColumn(keyCol)

        let actionCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionCol.title = "Action"
        actionCol.width = 200
        tableView.addTableColumn(actionCol)

        let coordsCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("coords"))
        coordsCol.title = "Coordinates"
        coordsCol.width = 120
        tableView.addTableColumn(coordsCol)

        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        addButton = NSButton(title: "+ Key", target: self, action: #selector(addBinding))
        addButton.frame = NSRect(x: 20, y: 20, width: 100, height: 28)
        contentView.addSubview(addButton)

        deleteButton = NSButton(title: "Delete", target: self, action: #selector(deleteBinding))
        deleteButton.frame = NSRect(x: 130, y: 20, width: 100, height: 28)
        contentView.addSubview(deleteButton)

        saveButton = NSButton(title: "Save", target: self, action: #selector(saveBindings))
        saveButton.frame = NSRect(x: 400, y: 20, width: 100, height: 28)
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        return bindings.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < bindings.count else { return nil }
        let binding = bindings[row]

        let id = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cellID = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = cellID
            let tf = NSTextField()
            tf.isBordered = false
            tf.isEditable = false
            tf.drawsBackground = false
            tf.frame = cell.bounds
            tf.autoresizingMask = [.width, .height]
            cell.addSubview(tf)
            cell.textField = tf
            return cell
        }()

        switch id.rawValue {
        case "key":
            cell.textField?.stringValue = binding.key
        case "action":
            cell.textField?.stringValue = binding.action
        case "coords":
            let parts = binding.action.split(separator: ":").map(String.init)
            if parts.first == "tap" && parts.count == 3 {
                cell.textField?.stringValue = "(\(parts[1]), \(parts[2]))"
            } else {
                cell.textField?.stringValue = ""
            }
        default:
            cell.textField?.stringValue = ""
        }

        return cell
    }

    // MARK: - Actions

    @objc private func addBinding() {
        recordingKey = true
        addButton.title = "Press..."
        statusLabel.stringValue = ""
    }

    @objc private func deleteBinding() {
        let row = tableView.selectedRow
        guard row >= 0, row < bindings.count else { return }
        bindings.remove(at: row)
        tableView.reloadData()
    }

    @objc private func saveBindings() {
        let configFile = configPath()
        var json: [String: Any] = [:]

        var bindingsDict: [String: String] = [:]
        for b in bindings {
            bindingsDict[b.key] = b.action
        }
        json["bindings"] = bindingsDict

        if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            try? data.write(to: URL(fileURLWithPath: configFile))
        }

        NotificationCenter.default.post(name: .init("com.iphonemirror.reloadBindings"), object: nil)
        print("[KeyBindings] Saved to \(configFile)")
        window?.close()
    }

    override func keyDown(with event: NSEvent) {
        if recordingKey {
            recordingKey = false
            addButton.title = "+ Key"
            pendingKeyCode = event.keyCode
            pendingKeyName = Self.keyCodeToString(event.keyCode)
            showActionPicker()
            return
        }
        super.keyDown(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
    }

    private func showActionPicker() {
        let alert = NSAlert()
        alert.messageText = "Key: \(pendingKeyName)"
        alert.informativeText = "Choose an action for this key"
        alert.addButton(withTitle: "Tap (click on screen)")
        alert.addButton(withTitle: "Swipe")
        alert.addButton(withTitle: "Home")
        alert.addButton(withTitle: "Cancel")

        let result = alert.runModal()

        switch result {
        case NSApplication.ModalResponse.alertFirstButtonReturn:
            startPickingCoords()
        case NSApplication.ModalResponse.alertSecondButtonReturn:
            showSwipePicker()
        case NSApplication.ModalResponse.alertThirdButtonReturn:
            addBindingEntry(key: pendingKeyName, action: "home")
        default:
            break
        }
    }

    private func startPickingCoords() {
        pickingCoords = true
        statusLabel.stringValue = "→ Click on the mirror screen to place the tap"

        window?.orderOut(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
                name: .init("com.iphonemirror.startPicking"),
                object: nil
            )
        }
    }

    private func handleCoordsPicked(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let normalizedX = userInfo["x"] as? CGFloat,
              let normalizedY = userInfo["y"] as? CGFloat else { return }

        pickingCoords = false
        let x = String(format: "%.3f", normalizedX)
        let y = String(format: "%.3f", normalizedY)
        addBindingEntry(key: pendingKeyName, action: "tap:\(x),\(y)")
        statusLabel.stringValue = "Tap \(pendingKeyName) → (\(x), \(y))"

        window?.makeKeyAndOrderFront(nil)
    }

    private func showSwipePicker() {
        let alert = NSAlert()
        alert.messageText = "Swipe - Direction"
        alert.addButton(withTitle: "Up")
        alert.addButton(withTitle: "Down")
        alert.addButton(withTitle: "Left")
        alert.addButton(withTitle: "Right")
        alert.addButton(withTitle: "Cancel")

        let result = alert.runModal()
        let dir: String
        switch result {
        case .alertFirstButtonReturn:  dir = "up"
        case .alertSecondButtonReturn: dir = "down"
        case .alertThirdButtonReturn:  dir = "left"
        case NSApplication.ModalResponse(1002): dir = "right"
        default: return
        }
        addBindingEntry(key: pendingKeyName, action: "swipe:\(dir)")
    }

    private func addBindingEntry(key: String, action: String) {
        bindings.removeAll { $0.key == key }
        bindings.append((key: key, action: action))
        bindings.sort { $0.key < $1.key }
        tableView.reloadData()
    }

    // MARK: - Load/Save

    private func configPath() -> String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Documents/Dofus/iPhoneMirror/keybindings.json"
    }

    private func loadBindings() {
        let path = configPath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dict = json["bindings"] as? [String: String] else { return }

        for (key, action) in dict.sorted(by: { $0.key < $1.key }) {
            bindings.append((key: key, action: action))
        }
        tableView.reloadData()
    }

    // MARK: - Key code → string

    static func keyCodeToString(_ code: UInt16) -> String {
        let map: [UInt16: String] = [
            0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f",
            0x04: "h", 0x05: "g", 0x06: "z", 0x07: "x",
            0x08: "c", 0x09: "v", 0x0B: "b", 0x0C: "q",
            0x0D: "w", 0x0E: "e", 0x0F: "r", 0x10: "y",
            0x11: "t", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x19: "9",
            0x1A: "7", 0x1C: "8", 0x1D: "0",
            0x2D: "n", 0x2E: "m",
            0x31: "space", 0x30: "tab",
            0x24: "return", 0x35: "escape",
            0x7E: "up", 0x7D: "down",
            0x7B: "left", 0x7C: "right",
            0x7A: "f1", 0x78: "f2", 0x63: "f3",
            0x76: "f4", 0x60: "f5", 0x61: "f6",
            0x62: "f7", 0x64: "f8", 0x65: "f9",
            0x6D: "f10", 0x67: "f11", 0x6F: "f12",
        ]
        return map[code] ?? "key_\(code)"
    }
}
