# iPhone Mirror

Mirror your iPhone screen to your Mac with full touch control via mouse and keyboard. Built with Swift/AppKit, AVFoundation, and CoreMediaIO.

## Features

- **Real-time screen mirroring** at 60 FPS via USB
- **Touch control** — click, long press, swipe, scroll via mouse
- **Keyboard shortcuts** — configurable key bindings mapped to screen zones
- **GUI key binding editor** — set up shortcuts by clicking on the screen
- **Auto-rotation** — window adjusts when iPhone orientation changes
- **WebDriverAgent integration** — low-latency touch input

## Requirements

- macOS 13.0+
- Xcode 15+ (for building WDA)
- iPhone connected via USB
- iPhone trusted on this Mac
- [libimobiledevice](https://libimobiledevice.org/)

## Installation

### 1. Install dependencies

```bash
brew install libimobiledevice
```

### 2. Clone the repository

```bash
git clone https://github.com/jasonlcsdev/iPhoneMirror.git
cd iPhoneMirror
```

### 3. Install WebDriverAgent (WDA)

WDA is needed to send touch inputs to your iPhone. It runs as an XCTest on the device.

#### Download WDA

```bash
cd ..
git clone https://github.com/appium/WebDriverAgent.git
cd WebDriverAgent
```

#### Configure Bundle IDs

Replace the default `com.facebook.*` bundle IDs with your own:

```bash
# Open in Xcode and change bundle IDs:
open WebDriverAgent.xcodeproj
```

In Xcode:
1. Select **WebDriverAgentLib** target → change bundle ID to `com.yourname.WebDriverAgentLib`
2. Select **WebDriverAgentRunner** target → change bundle ID to `com.yourname.WebDriverAgentRunner`
3. Select **IntegrationTests** target → change bundle ID to `com.yourname.IntegrationTests`
4. Make sure "Automatically manage signing" is enabled
5. Select your Apple Development Team

#### Build and install WDA on device

```bash
xcodebuild test \
    -project WebDriverAgent.xcodeproj \
    -scheme WebDriverAgentRunner \
    -destination "id=$(idevice_id -l)" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic
```

#### Trust the developer certificate on iPhone

1. Go to **Settings > General > VPN & Device Management**
2. Tap on your developer certificate
3. Tap **Trust**

#### Verify WDA is running

```bash
iproxy -u $(idevice_id -l) 8100 8100 &
curl http://localhost:8100/status
# Should return: {"value":{"ready":true,...}}
```

### 4. Build iPhoneMirror

```bash
cd iPhoneMirror
xcodebuild -project iPhoneMirror.xcodeproj \
    -scheme iPhoneMirror \
    -configuration Release build
```

### 5. Run

Use the startup script (recommended):

```bash
chmod +x start.sh
./start.sh
```

Or manually:
1. Start iproxy: `iproxy -u <DEVICE_UDID> 8100 8100`
2. Start WDA (see step 3)
3. Open `build/Build/Products/Release/iPhoneMirror.app`

## Usage

### Mouse Control

| Action | Effect |
|--------|--------|
| Click | Tap on iPhone |
| Click & hold > 0.5s | Long press |
| Drag | Swipe from start to end |
| Scroll wheel | Vertical/horizontal swipe |

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `1`-`9` | Tap at zone (3x3 grid) |
| `Space` | Tap center |
| `Return` / `Escape` | Home button |
| `↑↓←→` | Swipe direction |

### Key Binding Editor

Press **Cmd+K** or go to **File > Key Bindings**:

1. Click **+ Touche**
2. Press the key you want to assign
3. Choose **Tap (click on screen)**
4. Click on the mirror screen to pick coordinates
5. Click **Save**

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

**Format:**
- `tap:x,y` — tap at normalized coordinates (0-1)
- `swipe:direction` — swipe in direction (up/down/left/right)
- `home` — press home button

**Supported keys:** a-z, 0-9, space, tab, return, escape, up, down, left, right, f1-f12

## Architecture

```
iPhoneMirror/
├── main.swift                          # Entry point, enables CMIO
├── AppDelegate.swift                   # Window management, menu bar
├── PreviewView.swift                   # Screen capture + input handling
├── WDAClient.swift                     # WDA HTTP client
├── KeyBindingManager.swift             # Keyboard shortcut management
├── KeyBindingsWindowController.swift   # GUI key binding editor
├── start.sh                            # Startup script
├── keybindings.json                    # User key bindings
└── iPhoneMirror.xcodeproj/             # Xcode project
```

### How It Works

1. **Screen Capture**: Uses CoreMediaIO's muxed device (`CMIOExtensionAllowScreenCaptureDevices`) to capture the iPhone screen as a video stream via AVFoundation
2. **Touch Input**: Mouse events are mapped to iOS screen coordinates and sent to WebDriverAgent via HTTP API
3. **WDA Protocol**: Uses Appium's `/session/{id}/actions` endpoint with pointer actions
4. **Coordinate Mapping**: Maps macOS view coordinates to iOS points (428x926 for iPhone 13 Pro Max), handling Y-axis inversion

### Key Technical Details

- **Device Format**: `muxx/isr` (muxed screen recording)
- **Rotation Detection**: Monitors sample buffer pixel dimensions (1284x2778 portrait ↔ 2778x1284 landscape)
- **WDA Session**: Pre-created on startup with `{"capabilities": {"alwaysMatch": {}}}` format
- **Input Optimization**: Cached URLs, pre-built JSON bodies, HTTP pipelining, auto-retry on stale sessions

## Troubleshooting

### WDA keeps crashing

WDA runs via `xcodebuild test` which may exit. The `start.sh` script auto-restarts it. If WDA loses authorization:

1. Go to **Settings > General > VPN & Device Management**
2. Trust the developer certificate
3. Restart the script

### No muxed device found

1. Ensure iPhone is connected via USB
2. Trust the computer on your iPhone
3. Check: `system_profiler SPAudioDataType | grep -A5 "iPhone"`

### Touch coordinates are wrong

The app auto-detects screen resolution. If incorrect, check the logs:

```bash
# Watch app logs
tail -f /tmp/mirror.log
```

## Dependencies

| Dependency | Purpose |
|------------|---------|
| AVFoundation / CoreMediaIO | Screen capture |
| WebDriverAgent | Touch input (HTTP API) |
| libimobiledevice | USB device communication (iproxy) |
| Xcode CLI Tools | Building WDA |

## License

MIT
