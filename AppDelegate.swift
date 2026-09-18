import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    var previewView: PreviewView!
    private var keyBindingsWindowController: KeyBindingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 1200)
        let windowWidth: CGFloat = 390
        let windowHeight: CGFloat = 844

        window = NSWindow(
            contentRect: NSRect(
                x: screenFrame.midX - windowWidth / 2,
                y: screenFrame.midY - windowHeight / 2,
                width: windowWidth,
                height: windowHeight
            ),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "iPhone Mirror"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 200, height: 400)
        window.contentMinSize = NSSize(width: 200, height: 400)
        window.contentAspectRatio = NSSize(width: 9, height: 19.5)

        previewView = PreviewView(frame: window.contentView!.bounds)
        previewView.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(previewView)

        NotificationCenter.default.addObserver(
            forName: .init("com.iphonemirror.rotation"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleRotation(note)
        }

        NotificationCenter.default.addObserver(
            forName: .init("com.iphonemirror.reloadBindings"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.previewView.reloadKeyBindings()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        previewView.startCapture()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About iPhone Mirror", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit iPhone Mirror", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Key Bindings...", action: #selector(showKeyBindings), keyEquivalent: "k")
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showKeyBindings() {
        if keyBindingsWindowController == nil {
            keyBindingsWindowController = KeyBindingsWindowController()
        }
        keyBindingsWindowController?.showWindow(nil)
        keyBindingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func showPreferences() {
        showKeyBindings()
    }

    private func handleRotation(_ notification: Notification) {
        guard let isLandscape = notification.userInfo?["landscape"] as? Bool else { return }
        let ratio: NSSize = isLandscape ? NSSize(width: 19.5, height: 9) : NSSize(width: 9, height: 19.5)

        let frame = window.frame
        let contentHeight = frame.height - (frame.height - window.contentView!.frame.height)
        let newWidth: CGFloat
        let newHeight: CGFloat
        if isLandscape {
            newHeight = max(400, contentHeight * 0.55)
            newWidth = newHeight * (19.5 / 9.0)
        } else {
            newWidth = max(300, frame.width)
            newHeight = newWidth * (19.5 / 9.0)
        }
        let newFrame = NSRect(
            x: frame.midX - newWidth / 2,
            y: frame.maxY - newHeight,
            width: newWidth,
            height: newHeight
        )
        window.contentAspectRatio = ratio
        window.setFrame(newFrame, display: true, animate: true)
        window.title = isLandscape ? "iPhone Mirror (Landscape)" : "iPhone Mirror"
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
