# iPhone Mirror

Mirror your iPhone screen to your Mac with full touch control via mouse and keyboard. Built with Swift/AppKit, AVFoundation, and CoreMediaIO.

## Features

- **Real-time screen mirroring** at 60 FPS via USB (CoreMediaIO muxed device)
- **Touch control** — click, long press, swipe, scroll via mouse/keyboard
- **Keyboard shortcuts** — configurable key bindings that map to screen zones
- **Auto-rotation** — window adjusts aspect ratio when iPhone orientation changes
- **WebDriverAgent integration** — touch input via WDA HTTP API
- **GUI key binding editor** — set up shortcuts by clicking on the screen (Cmd+K)

## Requirements

- macOS 13.0+
- Xcode 15+ (for building WDA)
- iPhone connected via USB
- iPhone trusted on this Mac
- [libimobiledevice](https://libimobiledevice.org/) (`brew install libimobiledevice`)
- [WebDriverAgent](https://github.com/appium/WebDriverAgent) (built & installed on device)

## Quick Start

```bash
# Install dependencies
brew install libimobiledevice

# Clone & build
git clone https://github.com/yourusername/iPhoneMirror.git
cd iPhoneMirror
chmod +x start.sh
./start.sh
```

The script will:
1. Detect your iPhone
2. Start `iproxy` (USB → localhost:8100)
3. Launch WebDriverAgent
4. Build & open iPhoneMirror app

## Manual Build

```bash
# Build the app
xcodebuild -project iPhoneMirror.xcodeproj \
    -scheme iPhoneMirror \
    -configuration Release build

# Start iproxy (in a separate terminal)
iproxy -u <DEVICE_UDID> 8100 8100

# Start WDA (in a separate terminal)
cd ../WebDriverAgent
xcodebuild test \
    -project WebDriverAgent.xcodeproj \
    -scheme WebDriverAgentRunner \
    -destination "id=<DEVICE_UDID>" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    -test-timeouts-enabled NO
```

## Usage

### Mouse Control
- **Click** → Tap on iPhone at the corresponding position
- **Click & hold > 0.5s** → Long press
- **Drag** → Swipe from start to end position
- **Scroll wheel** → Vertical/horizontal swipe

### Keyboard Shortcuts
Default bindings (edit `keybindings.json` to customize):

| Key | Action |
|-----|--------|
| `1`-`9` | Tap at zone (3x3 grid) |
| `Space` | Tap center |
| `Return` / `Escape` | Home button |
| `↑↓←→` | Swipe direction |

### Key Binding Editor
Press **Cmd+K** or go to **File > Key Bindings** to open the GUI editor:

1. Click **+ Touche**
2. Press the key you want to assign
3. Choose **Tap (cliquer sur l'écran)**
4. Click on the mirror screen to pick coordinates
5. Click **Enregistrer**

### Custom Key Bindings
Edit `~/Documents/Dofus/iPhoneMirror/keybindings.json`:

```json
{
  "bindings": {
    "a": "tap:0.5,0.5",
    "z": "tap:0.3,0.8",
    "e": "swipe:up",
    "space": "tap:0.5,0.5",
    "return": "home",
    "escape": "home"
  }
}
```

Format:
- `tap:x,y` — tap at normalized coordinates (0-1)
- `swipe:direction` — swipe in direction (up/down/left/right)
- `home` — press home button

Supported key names: a-z, 0-9, space, tab, return, escape, up, down, left, right, f1-f12

## Architecture

```
iPhoneMirror/
├── main.swift                          # Entry point, enables CMIO
├── AppDelegate.swift                   # Window management, menu bar
├── PreviewView.swift                   # AVCaptureVideoPreviewLayer, input handling
├── WDAClient.swift                     # WDA HTTP client (tap, swipe, home)
├── KeyBindingManager.swift             # Keyboard shortcut management
├── KeyBindingsWindowController.swift   # GUI for key binding configuration
├── start.sh                            # Startup script (iproxy + WDA + app)
├── keybindings.json                    # User key bindings
├── Info.plist                          # App configuration
└── iPhoneMirror.xcodeproj/             # Xcode project
```

### How It Works

1. **Screen Capture**: Uses CoreMediaIO's muxed device (`CMIOExtensionAllowScreenCaptureDevices`) to capture the iPhone screen as a video stream via AVFoundation
2. **Touch Input**: Mouse events are mapped to iOS screen coordinates and sent to WebDriverAgent via HTTP API
3. **WDA Protocol**: Uses Appium's `/session/{id}/actions` endpoint with pointer actions for tap, long press, and swipe
4. **Coordinate System**: Maps macOS view coordinates to iOS points (428x926 for iPhone 13 Pro Max), handling Y-axis inversion (macOS bottom-up vs iOS top-down)

### Key Technical Details

- **Device Format**: `muxx/isr` (muxed screen recording) — reports 0x0 dimensions, defaults to device-specific resolution
- **Rotation Detection**: Monitors sample buffer pixel dimensions (1284x2778 portrait ↔ 2778x1284 landscape)
- **WDA Session**: Created on startup with `{"capabilities": {"alwaysMatch": {}}}` format
- **Input Optimization**: Pre-created WDA session, cached URLs, pre-built JSON bodies, HTTP pipelining

## Troubleshooting

### WDA keeps crashing
WDA runs via `xcodebuild test` which may exit. The `start.sh` script auto-restarts it. If WDA loses authorization:
1. Go to iPhone Settings > General > VPN & Device Management
2. Trust the developer certificate
3. Restart the script

### No muxed device found
1. Ensure iPhone is connected via USB
2. Trust the computer on your iPhone
3. Check: `system_profiler SPAudioDataType | grep -A5 "iPhone"`

### Touch coordinates are wrong
The app auto-detects screen resolution. If incorrect:
1. Check `iosScreenSize` in the logs
2. Verify with: `curl http://localhost:8100/session/<id>/wda/screen`

## Dependencies

- **AVFoundation / CoreMediaIO** — screen capture
- **WebDriverAgent** — touch input (HTTP API)
- **libimobiledevice** — USB device communication (iproxy)
- **Xcode Command Line Tools** — building WDA

## License

MIT
