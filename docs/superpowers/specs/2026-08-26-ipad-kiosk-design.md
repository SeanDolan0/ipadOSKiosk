# HA Smartboard — iPadOS 12.5.8 Kiosk Design Spec

**Date:** 2026-08-26
**Target:** iPad Mini 2 (A7, arm64), iPadOS 12.5.8, jailbroken (checkra1n/Amethyst)
**HA Instance:** `http://192.168.50.150:8123` (long-lived access token)
**Deploy Target:** `root@192.168.50.53:22` (password: `alpine`)

## 1. Architecture

### System Overview

Two processes running on the jailbroken iPad:

```
┌─────────────────────────────────────────────────┐
│  iPad Mini 2 — iPadOS 12.5.8                    │
│                                                  │
│  ┌──────────────┐  HTTP  ┌──────────┐           │
│  │ HASmartboard  │◄──────►│  kioskd  │           │
│  │ (App, mobile) │ :9090  │ (Daemon, │           │
│  │ UIKit+WKWebView│       │  root)   │           │
│  └──────┬───────┘        └────┬─────┘           │
│         │ Wi-Fi                │ Wi-Fi            │
│         ▼                     ▼                  │
│  ┌─────────────────────────────────┐            │
│  │  HA: http://192.168.50.150:8123 │            │
│  └─────────────────────────────────┘            │
└─────────────────────────────────────────────────┘
```

### Why Two Processes

- **App** (UID: `mobile`): Runs in `/Applications/HASmartboard.app/`. UI-only — loads HA dashboard in WKWebView. Cannot access hardware-level APIs (IOKit battery internals, MobileWiFi RSSI).
- **Daemon** (UID: `root`): Runs via launchd from `/Library/LaunchDaemons/`. Has full hardware access. Collects telemetry, serves it via localhost HTTP, and reports to HA's REST API.
- **IPC**: Daemon runs HTTP server on `127.0.0.1:9090`. App's JavaScript fetches telemetry. Simple, debuggable (`curl http://127.0.0.1:9090/telemetry`), zero framework dependencies.
- **Independence**: If app crashes, launchd restarts it. Daemon stays alive. They can be restarted independently.

### Deployment Route

Theos builds a single `.deb` package containing both the app binary and the daemon binary plus their launchd plists. Deployed over SSH/SFTP:

```
Theos (Linux/WSM/Mac CLI)
  → make package
  → scp *.deb root@192.168.50.53:/tmp/
  → ssh root@192.168.50.53 "dpkg -i /tmp/hasmartboard.deb"
  → ssh root@192.168.50.53 "launchctl load /Library/LaunchDaemons/com.hasmartboard.*.plist"
```

### Why Not TrollStore/Xcode

- TrollStore requires CoreTrust exploits (iOS 14.0–16.6.1 only) — not available on 12.5.8
- Xcode is not installed on the build machine; Theos provides a CLI-only toolchain
- Theos can cross-compile for arm64 from Linux/WSL/Mac using Apple SDK headers from the `theos/sdks` repo
- On-device compilation via `clang` + `make` is also possible but slower

---

## 2. Daemon Design (`kioskd`)

### Telemetry Collection (every 30s)

| Data Point | API | Framework | Link Flag |
|---|---|---|---|
| Battery level % | `IOPSCopyPowerSourcesInfo()` → `kIOPSCurrentCapacityKey` | IOKit | `-framework IOKit` |
| Battery current (mA) | `IOPSCopyPowerSourcesInfo()` → `kIOPSCurrentCapacityKey` | IOKit | — |
| Battery cycle count | `IOPSCopyPowerSourcesInfo()` | IOKit | — |
| Battery temperature | IORegistry `IOBatteryInfo` → `Temperature` (0.1°C) | IOKit | — |
| Battery voltage (mV) | `IOPSCopyPowerSourcesInfo()` | IOKit | — |
| Battery health % | max capacity / design capacity from IOPowerSources | IOKit | — |
| WiFi RSSI (dBm) | `WiFiNetworkGetRSSI()` | MobileWiFi | `-framework MobileWiFi -framework SystemConfiguration` |
| WiFi SSID | `WiFiNetworkGetSSID()` | MobileWiFi | — |
| WiFi BSSID | `WiFiNetworkGetBSSIDData()` | MobileWiFi | — |
| WiFi channel | `WiFiNetworkGetChannel()` | MobileWiFi | — |
| WiFi link speed (Mbps) | `WiFiNetworkGetLinkSpeed()` | MobileWiFi | — |
| WiFi noise floor (dBm) | `WiFiNetworkGetNoise()` | MobileWiFi | — |
| Network bytes in/out | `getifaddrs()` + `struct if_data.ifi_ibytes/ifi_obytes` | BSD | — |
| Storage free/total | `statvfs("/")` | POSIX | — |
| Free/active memory | `vm_stat()` × page size | Mach | — |
| Device uptime | `sysctl kern.boottime` | POSIX | — |

### Local HTTP Server (`127.0.0.1:9090`)

**Endpoints:**

```
GET /telemetry
  → JSON with all metrics (see above)
  → Cached, refreshed every 30s internally

GET /health
  → {"status":"ok","pid":<pid>,"uptime":<seconds>}

POST /command
  Body: {"action":"<action>","value":<value>}
  Actions:
    setBrightness  value: 0.0-1.0 (float)
    setVolume      value: 0.0-1.0 (float)
    muteVolume     value: true/false
    toggleWiFi     value: true/false
    toggleBluetooth value: true/false
    setDND         value: true/false
    lockOrientation value: true/false
    reboot         (no value)
    relaunchApp    (no value) — kill -9 the app so launchd restarts it
```

**Implementation**: Single-file C/ObjC (`Daemon/main.m`). BSD socket HTTP server, ~400-500 lines. No frameworks beyond POSIX + IOKit + MobileWiFi. Parses HTTP requests manually (no libcurl, no Foundation networking — keeps dependencies minimal for root daemon).

### HA Telemetry Reporter

The daemon publishes telemetry to HA via MQTT (QoS 0) to a Mosquitto broker:

- The daemon connects with a LWT of `offline` on topic `kiosk/status`
- It publishes MQTT discovery configs to `homeassistant/sensor/kiosk_<entity>/config`
- Every 30s, it publishes state payload to `kiosk/sensor/<entity>/state`

See `2026-09-01-mqtt-telemetry-design.md` for full MQTT topic schemas and configuration.

### Device Control (via POST /command from app)

| Action | API | Notes |
|---|---|---|
| Set brightness | `BBSetBrightness(float)` | BackBoardServices.framework, 0.0-1.0 |
| Get brightness | `IOMobileFramebufferGetBacklightBrightness()` | IOKit |
| Set volume | `[AVSystemController setSystemVolume:]` | AudioToolbox private API |
| Get volume | `[AVSystemController getSystemVolume:]` | AudioToolbox private API |
| Mute | `[AVSystemController muteSystemVolume:]` | AudioToolbox private API |
| WiFi toggle | `WiFiManagerClientSetPower(manager, bool)` | MobileWiFi |
| Bluetooth toggle | `[BluetoothManager setEnabled:]` | BluetoothManager private framework |
| DND toggle | Write to `/var/mobile/Library/Preferences/com.apple.donotdisturb.plist` | Most reliable on 12.5.8 |
| Orientation lock | `[SBOrientationLockManager lock/unlock]` | SpringBoard private |
| Reboot | `reboot()` | POSIX |
| Relaunch app | `kill -9 <app_pid>` | launchd restarts it |

---

## 3. App Design (`HASmartboard`)

### Core: WKWebView Dashboard

- Loads `http://192.168.50.150:8123/lovelace/0` (configurable URL)
- Injects `Authorization: Bearer <token>` via `WKWebViewConfiguration.userContentController`
- Hides all system chrome: full-screen, no status bar, no navigation bar
- `UIApplication.shared.idleTimerDisabled = YES` — prevents auto-lock
- `UIStatusBarStyle = UIStatusBarStyleLightContent` — dark status bar if visible

### JavaScript Bridge

Inject JS into WKWebView page via `WKUserScript`:

```javascript
// Bridge: App → HA communication
window.webkit.messageHandlers.kiosk.postMessage({
    type: 'telemetry',
    data: telemetryFromDaemon
});

// Bridge: HA → App commands
// The daemon can trigger actions via the app by POSTing to app's local server
// OR the app polls daemon and forwards HA service calls
```

HA Lovelace can trigger native actions via custom cards that call `window.webkit.messageHandlers.kiosk.postMessage()`.

### Screensaver Mode

**Config plist:** `/var/mobile/Library/Preferences/com.hasmartboard.plist`

```xml
<key>screensaver</key>
<dict>
    <key>enabled</key>
    <true/>
    <key>idleTimeout</key>
    <integer>300</integer>  <!-- 5 minutes in seconds -->
    <key>mode</key>
    <string>clock</string>   <!-- clock | photo | dim -->
    <key>clockFormat</key>
    <string>HH:mm</string>
    <key>photoURLs</key>
    <array>
        <string>http://192.168.50.150:8123/api/camera_proxy/camera.living_room</string>
    </array>
    <key>dimBrightness</key>
    <real>0.1</real>
</dict>
```

**Modes:**
- `clock`: Large digital clock (HH:mm, centered), date below, dimmed to `dimBrightness`
- `photo`: Fetches images from HA camera proxy endpoints, rotates every 30s, fades between
- `dim`: Keeps dashboard visible but dims to `dimBrightness`

**Wake triggers:**
1. Touch anywhere on screensaver view
2. HTTP POST from daemon at `http://127.0.0.1:9090/wake` (triggered by HA automation via motion sensor)
3. WebSocket event from HA (if configured)

### Network Resilience

```
States: CONNECTED → DISCONNECTED → RECONNECTING → CONNECTED

CONNECTED:
  - Normal operation
  - Monitor: GET /health from daemon every 10s
  - Monitor: HEAD http://192.168.50.150:8123/ every 30s

DISCONNECTED (detected when monitor fails):
  - Show overlay: "Connection lost — retrying..."
  - Exponential backoff: 5s → 10s → 30s → 60s (max)
  - Keep daemon connection alive (localhost doesn't go down with WiFi)

RECONNECTING (WiFi back, HA reachable):
  - Show overlay: "Reconnecting..."
  - Reload WKWebView
  - Transition back to CONNECTED
```

### App Lifecycle

1. `application:didFinishLaunchingWithOptions:` → disable idle timer, set full-screen, configure WKWebView, load dashboard
2. `applicationDidBecomeActive:` → resume monitoring
3. `applicationWillResignActive:` → pause active view components
4. `applicationDidEnterBackground:` → `IOPMAssertion` to prevent sleep
5. Crash recovery handled by launchd `KeepAlive` — app restarts within 5s

---

## 4. Theos Project Structure

```
HASmartboard/
├── Makefile                    # Top-level Theos makefile
├── control                     # Debian package metadata
├── Hasmartboard.plist          # App Info.plist
│
├── App/
│   ├── main.m                  # UIKit application entry point
│   ├── AppDelegate.m           # App lifecycle, WKWebView setup
│   ├── AppDelegate.h
│   ├── KioskViewController.m   # Main WKWebView controller
│   ├── KioskViewController.h
│   ├── ScreensaverView.m       # Clock/photo/screensaver overlay
│   ├── ScreensaverView.h
│   ├── NetworkMonitor.m        # Connection state machine
│   ├── NetworkMonitor.h
│   ├── DaemonBridge.m          # HTTP client for localhost:9090
│   ├── DaemonBridge.h
│   ├── TelemetryRelay.m        # Posts telemetry to HA REST API
│   ├── TelemetryRelay.h
│   └── Makefile                # App target makefile
│
├── Daemon/
│   ├── main.m                  # Root daemon entry, HTTP server, telemetry
│   ├── TelemetryCollector.m    # IOKit + MobileWiFi data collection
│   ├── TelemetryCollector.h
│   ├── DeviceControl.m         # Brightness/volume/WiFi/Bluetooth control
│   ├── DeviceControl.h
│   ├── HTTPServer.m            # BSD socket HTTP server on localhost:9090
│   ├── HTTPServer.h
│   ├── HAReporter.m            # Pushes sensor states to HA REST API
│   ├── HAReporter.h
│   └── Makefile                # Daemon target makefile
│
├── Layout/
│   ├── Applications/
│   │   └── HASmartboard.app/   # App gets installed here
│   │       └── (binary, plist, resources)
│   └── Library/
│       └── LaunchDaemons/
│           ├── com.hasmartboard.daemon.plist   # kioskd launchd config
│           └── com.hasmartboard.app.plist      # HASmartboard launchd config
│
└── Resources/
    ├── launch.png              # App icon (57x57 for iOS 12)
    └── Default.png             # Launch image (1024x768 for iPad Mini 2)
```

---

## 5. LaunchDaemon Plists

### `com.hasmartboard.daemon.plist` (root daemon)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.hasmartboard.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/Application Support/HASmartboard/kioskd</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/kioskd.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/kioskd.log</string>
    <key>UserName</key>
    <string>root</string>
</dict>
</plist>
```

### `com.hasmartboard.app.plist` (UI app)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.hasmartboard.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/HASmartboard.app/HASmartboard</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>StandardOutPath</key>
    <string>/var/log/hasmartboard.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/hasmartboard.log</string>
</dict>
</plist>
```

---

## 6. Build & Deploy Pipeline

### Theos Makefile (top-level)

```makefile
THEOS_DEVICE_IP = 192.168.50.53
THEOS_DEVICE_PORT = 22
THEOS_DEVICE_USER = root

INSTALL_TARGET_PROCESSES = HASmartboard
TARGET = iphone:clang:12.2:12.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = HASmartboard
HASmartboard_FILES = App/main.m App/AppDelegate.m App/KioskViewController.m \
    App/ScreensaverView.m App/NetworkMonitor.m App/DaemonBridge.m \
    App/TelemetryRelay.m
HASmartboard_FRAMEWORKS = UIKit Foundation WebKit CoreGraphics
HASmartboard_PRIVATE_FRAMEWORKS = BackBoardServices

include $(THEOS_MAKE_PATH)/application.mk

SUBPROJECTS += Daemon
include $(THEOS_MAKE_PATH)/aggregate.mk
```

### Build Commands

```bash
# From Linux/WSL/Mac with Theos installed:
cd /path/to/HASmartboard

# Build
make

# Package as .deb
make package

# Deploy over SSH (direct)
make package install

# OR manual deploy:
scp packages/com.hasmartboard_1.0_iphoneos-arm64.deb root@192.168.50.53:/tmp/
ssh root@192.168.50.53 "dpkg -i /tmp/com.hasmartboard_1.0_iphoneos-arm64.deb"
ssh root@192.168.50.53 "launchctl load /Library/LaunchDaemons/com.hasmartboard.daemon.plist"
ssh root@192.168.50.53 "launchctl load /Library/LaunchDaemons/com.hasmartboard.app.plist"
```

---

## 7. Feature Parity Table

| Android Companion Feature | This Build | Status | Notes |
|---|---|---|---|
| Full-screen Lovelace dashboard | WKWebView, hidden chrome | ✅ Full | — |
| Auto-launch on boot | launchd KeepAlive | ✅ Full | — |
| Auto-relaunch on crash | launchd KeepAlive + ThrottleInterval | ✅ Full | 5s restart |
| Screen always-on | IOPMAssertion + idleTimerDisabled | ✅ Full | — |
| Screensaver (clock/photos) | Native UIKit | ✅ Full | 3 modes configurable |
| Disable notification shade | SpringBoard hook (Logos tweak) | ✅ Full | Separate Substrate tweak |
| Disable home button | SpringBoard hook or AXGuidedAccessServer | ✅ Full | Two approaches available |
| Disable power button (shutdown) | SpringBoard hook | ⚠️ Partial | Can block dialog, not hardware |
| Motion/presence wake | Daemon HTTP POST from HA | ✅ Full | External sensor → HA → daemon |
| Network resilience | State machine + exponential backoff | ✅ Full | — |
| System telemetry to HA | IOKit + MobileWiFi → HA sensors | ✅ Full | 13+ sensor entities |
| Battery level/health | IOPSCopyPowerSourcesInfo | ✅ Full | — |
| WiFi RSSI | WiFiNetworkGetRSSI | ✅ Full | dBm |
| Brightness control from HA | BBSetBrightness via daemon | ✅ Full | 0.0-1.0 |
| Volume control from HA | AVSystemController via daemon | ✅ Full | 0.0-1.0 |
| Bluetooth toggle | BluetoothManager setEnabled: | ✅ Full | — |
| WiFi toggle | WiFiManagerClientSetPower | ✅ Full | — |
| DND mode | Plist write / DNDSettings | ✅ Full | — |
| Orientation lock | SBOrientationLockManager | ✅ Full | — |
| Camera feeds in dashboard | WKWebView renders HA camera cards | ✅ Full | — |
| Voice assistant | ❌ Not possible | ❌ No | No accessible voice API on iOS 12 |
| NFC triggers | ❌ Hardware absent | ❌ No | iPad Mini 2 has no NFC |
| Push notifications | ⚠️ Limited | ⚠️ Partial | Can read but not display natively |
| Wear OS companion | ❌ N/A | ❌ No | iOS only |

---

## 8. Security Considerations

1. **Update root password**: `ssh root@192.168.50.53 "passwd"` — change from default `alpine`
2. **HA token storage**: Long-lived token stored in daemon binary config (compiled-in) or in `/Library/Application Support/HASmartboard/config.plist` with `chmod 600`
3. **Localhost-only HTTP**: Daemon binds to `127.0.0.1:9090` — not accessible from network
4. **No external dependencies**: Daemon uses only POSIX + Apple private frameworks — no dylibs to trust

---

## 9. Known Limitations & Recommended Tweaks

### Parity Gaps
- **Voice assistant**: No workaround on iOS 12 — hardware mic input cannot be routed to third-party apps in a meaningful way
- **NFC**: iPad Mini 2 lacks NFC hardware entirely
- **Power button**: Can intercept the shutdown dialog via SpringBoard hook but cannot physically block the hardware button press
- **CPU temperature**: A7 chip thermal zone paths are undocumented; may not be reliably available

### Recommended Sileo/Zebra Tweaks
- **KioskMode** (or similar): Programmatic Guided Access activation
- **AntiTweak** / **Springtomize**: Additional SpringBoard lockdown options
- **Activator**: Custom gesture → daemon command (e.g., triple-tap volume → reboot)

### Future Enhancements (out of scope for v1)
- SpringBoard tweak for home button disable (Logos/MobileSubstrate)
- WebSocket connection from daemon to HA for instant wake events
- OTA update mechanism via HA webhook
- Multi-dashboard support with gesture navigation
