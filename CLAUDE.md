# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

HA Smartboard — Home Assistant kiosk dashboard for a jailbroken iPad Mini 2 (arm64, iPadOS 12.5.8), built with Theos. Two binaries ship in one `.deb` package (`com.hasmartboard`, version in `control`):

- **HASmartboard** — UIKit app (`App/`). Full-screen WKWebView loading the HA Lovelace dashboard, plus ScreensaverView, NetworkMonitor, and telemetry relay.
- **kioskd** — root launchd daemon (`Daemon/`). Collects telemetry (battery, WiFi, storage, memory), serves it over localhost HTTP, and applies device-control commands.

## Build (on the iPad — the only supported method)

Everything must be built on the iPad with Theos. Cross-compiling elsewhere and copying the binary into `/Applications` pins the app to portrait (SpringBoard registers anything not installed via `make install` as non-rotatable — the rotation request never reaches the app, and `uicache` alone can't fix a pre-built binary). An on-device `make install` + `uicache` build registers the app cleanly so it rotates like a stock app.

```bash
# from the project checkout on the device (e.g. /var/mobile/ipadOSKiosk)
export THEOS="$HOME/theos"; export PATH="$THEOS/bin:$PATH"
make clean && make         # builds app + daemon tool
make package               # .deb → packages/ (optional)
make install               # installs HASmartboard.app → /Applications, kioskd → /Library/Application Support/HASmartboard
uicache -p /Applications/HASmartboard.app   # (or `uicache -a`) refresh SpringBoard registration
launchctl load /Library/LaunchDaemons/com.hasmartboard.daemon.plist
```

- Only the daemon is a launchd job (`Layout/Library/LaunchDaemons/com.hasmartboard.daemon.plist`). The app is launched from the home screen by SpringBoard; there is no `com.hasmartboard.app.plist`.
- Device: `root@192.168.50.53` (default password `alpine`); HA at `192.168.50.150:8123`.
- No test suite or linter. Validation is on-device: `curl -sf http://127.0.0.1:9090/health`, `launchctl list | grep hasmartboard`, `/var/log/kioskd.log`.

## Architecture / IPC

- kioskd (`Daemon/main.m`) reads config in `HTTPServerConfig` (`HTTP_PORT 9090`, telemetry every 30s), collects a `TelemetrySnapshot`, and serves:
  - `GET 127.0.0.1:9090/telemetry` — battery, WiFi, storage, memory, uptime, network bytes
  - `GET 127.0.0.1:9090/health`
  - `POST /command` — JSON body `{"action": "...", "value": "..."}`. Actions in `Daemon/DeviceControl.m`: `setBrightness`, `setVolume`, `muteVolume`, `toggleWiFi`, `toggleBluetooth`, `setDND`, `lockOrientation`, `reboot`, `relaunchApp` (mostly `popen`-scripted / launchctl).
  - `POST /wake` — screensaver wake
- App → daemon IPC is `App/DaemonBridge.m` (NSURLSession → `127.0.0.1:9090`); `NetworkMonitor`/`TelemetryRelay` consume it. `TelemetryRelay` converts daemon telemetry into `sensor.kiosk_*` HA entities.
- Logs: `/var/log/kioskd.log`, `/var/log/hasmartboard.log`.

## Configuration

- HA URL, token, dashboard path are **hardcoded `#define`s** at the top of `App/KioskViewController.m` (`HA_BASE_URL`, `HA_TOKEN`, `DASHBOARD_PATH`). Never commit real tokens — placeholders only.
- Screensaver mode/timeout/dim/photo URLs live on-device in `/var/mobile/Library/Preferences/com.hasmartboard.plist` (schema: `config.plist.example`).

## Conventions

- Daemon is framework-light: BSD sockets/POSIX for HTTP and process control; no Foundation networking in `kioskd`.
- Keep telemetry in the flat C `TelemetrySnapshot` struct (`Daemon/TelemetryCollector.h`). If metrics change, update `TelemetrySnapshotToJSON`, `App/TelemetryRelay.m`, and the README sensor table together.
- Preserve the localhost-only bind and the endpoint shapes; telemetry refreshes every 30s and the app polls on the same interval.
- Private iOS 12 APIs (MobileWiFi, BackBoardServices) are used via explicit `extern` or runtime lookup. Don't invent private symbols, signatures, or entitlements — verify against the iOS 12 SDK headers or existing declarations before adding.
- If the daemon gets SIGKILLed (exit 137): the jailbreak `base_hook.dylib` kills binaries under `/Library/Application Support/` unless they carry `com.apple.private.security.no-sandbox`. Re-sign on-device with `ldid` using `Daemon/kioskd.entitlements` and reload the launchd job.