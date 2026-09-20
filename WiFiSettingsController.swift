import Cocoa

class WiFiSettingsController: NSWindowController {

    private var urlField: NSTextField!
    private var statusLabel: NSTextField!
    private var onConfirm: ((String) -> Void)?

    convenience init(currentURL: String, onConfirm: @escaping (String) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WiFi WDA Settings"
        window.center()

        self.init(window: window)
        self.onConfirm = onConfirm
        setupUI(currentURL: currentURL)
    }

    private func setupUI(currentURL: String) {
        guard let contentView = window?.contentView else { return }

        let infoLabel = NSTextField(labelWithString: "Enter the WDA URL on your iPhone's WiFi network.")
        infoLabel.font = NSFont.systemFont(ofSize: 12)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.frame = NSRect(x: 20, y: 160, width: 380, height: 30)
        infoLabel.maximumNumberOfLines = 2
        contentView.addSubview(infoLabel)

        let ipLabel = NSTextField(labelWithString: "WDA URL:")
        ipLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        ipLabel.frame = NSRect(x: 20, y: 130, width: 80, height: 20)
        contentView.addSubview(ipLabel)

        urlField = NSTextField(frame: NSRect(x: 100, y: 127, width: 280, height: 24))
        urlField.stringValue = currentURL
        urlField.placeholderString = "http://192.168.x.x:8100"
        contentView.addSubview(urlField)

        let helpLabel = NSTextField(labelWithString: "On iPhone: start WDA, then use 'iproxy -u <UDID> 8100 8100' over WiFi or enter the IP directly if WDA listens on all interfaces.")
        helpLabel.font = NSFont.systemFont(ofSize: 10)
        helpLabel.textColor = .tertiaryLabelColor
        helpLabel.frame = NSRect(x: 20, y: 80, width: 380, height: 40)
        helpLabel.maximumNumberOfLines = 3
        contentView.addSubview(helpLabel)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .systemGreen
        statusLabel.frame = NSRect(x: 20, y: 60, width: 380, height: 16)
        contentView.addSubview(statusLabel)

        let connectButton = NSButton(title: "Connect", target: self, action: #selector(connect))
        connectButton.frame = NSRect(x: 200, y: 20, width: 100, height: 28)
        connectButton.keyEquivalent = "\r"
        contentView.addSubview(connectButton)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.frame = NSRect(x: 310, y: 20, width: 80, height: 28)
        contentView.addSubview(cancelButton)
    }

    @objc private func connect() {
        let url = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            statusLabel.stringValue = "Please enter a URL"
            statusLabel.textColor = .systemRed
            return
        }

        statusLabel.stringValue = "Connecting..."
        statusLabel.textColor = .systemBlue

        let testURL = URL(string: "\(url)/status")!
        let task = URLSession.shared.dataTask(with: testURL) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.statusLabel.stringValue = "Failed: \(error.localizedDescription)"
                    self?.statusLabel.textColor = .systemRed
                } else if let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let value = json["value"] as? [String: Any],
                          let ready = value["ready"] as? Bool, ready {
                    self?.statusLabel.stringValue = "Connected!"
                    self?.statusLabel.textColor = .systemGreen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.onConfirm?(url)
                        self?.window?.close()
                    }
                } else {
                    self?.statusLabel.stringValue = "WDA not responding"
                    self?.statusLabel.textColor = .systemOrange
                }
            }
        }
        task.resume()
    }

    @objc private func cancel() {
        window?.close()
    }
}
