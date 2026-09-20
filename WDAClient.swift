import Foundation

enum SwipeDirection {
    case up, down, left, right
}

class WDAClient {

    private(set) var baseURL: String
    private var sessionId: String?
    private let session: URLSession
    private var cachedActionsURL: URL?
    private var cachedHomeURL: URL?
    private var sessionCreationDate: Date?

    init(baseURL: String = "http://localhost:8100") {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        config.httpShouldUsePipelining = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)

        preCreateSession()
    }

    func setBaseURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        baseURL = trimmed
        invalidateSession()
        print("[WDA] Base URL set to \(baseURL)")
        preCreateSession()
    }

    // MARK: - Session Management

    private func preCreateSession() {
        ensureSession { success in
            if success {
                print("[WDA] Pre-created session")
            } else {
                print("[WDA] Pre-create failed, will retry on first tap")
            }
        }
    }

    func ensureSession(completion: ((Bool) -> Void)? = nil) {
        if let sid = sessionId, let date = sessionCreationDate,
           Date().timeIntervalSince(date) < 30 {
            completion?(true)
            return
        }

        sessionId = nil
        let url = URL(string: "\(baseURL)/session")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["capabilities": ["alwaysMatch": [:]]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                completion?(false)
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let value = json["value"] as? [String: Any],
               let sid = value["sessionId"] as? String {
                self?.sessionId = sid
                self?.sessionCreationDate = Date()
                self?.cachedActionsURL = URL(string: "\(self?.baseURL ?? "")/session/\(sid)/actions")
                self?.cachedHomeURL = URL(string: "\(self?.baseURL ?? "")/session/\(sid)/wda/homescreen")
                completion?(true)
            } else {
                completion?(false)
            }
        }.resume()
    }

    private func invalidateSession() {
        sessionId = nil
        cachedActionsURL = nil
        cachedHomeURL = nil
    }

    private func getActionsURL() -> URL? {
        cachedActionsURL ?? URL(string: "\(baseURL)/session/\(sessionId ?? "")/actions")
    }

    private func getHomeURL() -> URL? {
        cachedHomeURL ?? URL(string: "\(baseURL)/session/\(sessionId ?? "")/wda/homescreen")
    }

    // MARK: - Tap (optimized: pre-built JSON)

    func tap(at point: CGPoint) {
        ensureSession { [weak self] success in
            guard success, let self = self, let url = self.getActionsURL() else { return }

            let x = Int(point.x)
            let y = Int(point.y)
            let json = "{\"actions\":[{\"type\":\"pointer\",\"id\":\"finger1\",\"parameters\":{\"pointerType\":\"touch\"},\"actions\":[{\"type\":\"pointerMove\",\"duration\":0,\"x\":\(x),\"y\":\(y),\"origin\":\"viewport\"},{\"type\":\"pointerDown\",\"button\":0},{\"type\":\"pause\",\"duration\":30},{\"type\":\"pointerUp\",\"button\":0}]}]}"
            let body = json.data(using: .utf8)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            self.sendAction(request: request, label: "Tap")
        }
    }

    // MARK: - Long Press

    func longPress(at point: CGPoint, duration: TimeInterval = 1.0) {
        ensureSession { [weak self] success in
            guard success, let self = self, let url = self.getActionsURL() else { return }

            let x = Int(point.x)
            let y = Int(point.y)
            let holdMs = Int(min(duration, 5.0) * 1000)
            let json = "{\"actions\":[{\"type\":\"pointer\",\"id\":\"finger1\",\"parameters\":{\"pointerType\":\"touch\"},\"actions\":[{\"type\":\"pointerMove\",\"duration\":0,\"x\":\(x),\"y\":\(y),\"origin\":\"viewport\"},{\"type\":\"pointerDown\",\"button\":0},{\"type\":\"pause\",\"duration\":\(holdMs)},{\"type\":\"pointerUp\",\"button\":0}]}]}"
            let body = json.data(using: .utf8)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            self.sendAction(request: request, label: "LongPress")
        }
    }

    // MARK: - Swipe (arbitrary from→to)

    func swipe(from: CGPoint, to: CGPoint, duration: TimeInterval = 0.4) {
        ensureSession { [weak self] success in
            guard success, let self = self, let url = self.getActionsURL() else { return }

            let fx = Int(from.x), fy = Int(from.y)
            let tx = Int(to.x), ty = Int(to.y)
            let moveMs = Int(duration * 1000)
            let json = "{\"actions\":[{\"type\":\"pointer\",\"id\":\"finger1\",\"parameters\":{\"pointerType\":\"touch\"},\"actions\":[{\"type\":\"pointerMove\",\"duration\":0,\"x\":\(fx),\"y\":\(fy),\"origin\":\"viewport\"},{\"type\":\"pointerDown\",\"button\":0},{\"type\":\"pointerMove\",\"duration\":\(moveMs),\"x\":\(tx),\"y\":\(ty),\"origin\":\"viewport\"},{\"type\":\"pointerUp\",\"button\":0}]}]}"
            let body = json.data(using: .utf8)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            self.sendAction(request: request, label: "Swipe")
        }
    }

    // MARK: - Swipe by direction

    func swipe(direction: SwipeDirection, screenSize: CGSize) {
        let margin: CGFloat = 20
        let from: CGPoint
        let to: CGPoint

        switch direction {
        case .up:
            from = CGPoint(x: screenSize.width / 2, y: screenSize.height - margin)
            to = CGPoint(x: screenSize.width / 2, y: margin)
        case .down:
            from = CGPoint(x: screenSize.width / 2, y: margin)
            to = CGPoint(x: screenSize.width / 2, y: screenSize.height - margin)
        case .left:
            from = CGPoint(x: screenSize.width - margin, y: screenSize.height / 2)
            to = CGPoint(x: margin, y: screenSize.height / 2)
        case .right:
            from = CGPoint(x: margin, y: screenSize.height / 2)
            to = CGPoint(x: screenSize.width - margin, y: screenSize.height / 2)
        }

        swipe(from: from, to: to, duration: 0.4)
    }

    // MARK: - Home Button

    func pressHome() {
        ensureSession { [weak self] success in
            guard success, let self = self, let url = self.getHomeURL() else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = "{}".data(using: .utf8)

            self.sendAction(request: request, label: "Home")
        }
    }

    // MARK: - Send helper (with retry)

    private func sendAction(request: URLRequest, label: String, retryCount: Int = 1) {
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                if retryCount > 0 {
                    self.invalidateSession()
                    self.ensureSession { success in
                        if success {
                            self.sendAction(request: request, label: label, retryCount: 0)
                        }
                    }
                }
                return
            }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let value = json["value"] as? [String: Any],
               let err = value["error"] as? String {
                if retryCount > 0 && (err.contains("stale") || err.contains("not found") || err.contains("invalid")) {
                    self.invalidateSession()
                    self.ensureSession { success in
                        if success {
                            self.sendAction(request: request, label: label, retryCount: 0)
                        }
                    }
                }
            }
        }.resume()
    }
}
