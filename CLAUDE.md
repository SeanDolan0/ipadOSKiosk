# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

HA Smartboard — Home Assistant kiosk dashboard for a jailbroken iPad Mini 2 (arm64, iPadOS 12.5.8), built with Theos. Two binaries ship in one `.deb` package (`com.hasmartboard`, version in `control`):

- **HASmartboard** — UIKit app (`App/`). Full-screen WKWebView loading the HA Lovelace dashboard, plus ScreensaverView, NetworkMonitor, and telemetry relay.
- **kioskd** — root launchd daemon (`Daemon/`). Collects telemetry (battery, WiFi, storage, memory), serves it over localhost HTTP, and applies device-control commands.

## Build & deploy (on the iPad — the only supported method)

Everything must be built on the iPad with Theos. Cross-compiling elsewhere and copying the binary into `/Applications` pins the app to portrait (SpringBoard registers anything not installed via `make install` as non-rotatable — the rotation request never reaches the app, and `uicache` alone can't fix a pre-built binary).

**Read [`DEPLOYMENT_GUIDE.md`](DEPLOYMENT_GUIDE.md) first. It is the authoritative, step-by-step how-to** for the full Windows→iPad cycle (sync, build, package, install, ldid re-sign, chown, launchctl reload, uicache, verify). Key facts that differ from intuition:

- Device `root@192.168.50.53` (password `alpine` unless changed); HA at `192.168.50.150:8123`. Use **PuTTY plink/pscp** with pinned `-hostkey SHA256:tTQh0tVy4n2k+Kwntq4etfwboSdVHEF+jw8Hq66MxQo` — sshpass-win32 is broken here.
- **Theos is at `/opt/theos`** on the device (not `$HOME/theos`), and the project checkout lives at `/var/mobile/Apps/ipadOSKiosk`.
- **SDK is `iPhoneOS12.4.sdk`** — root `Makefile:10` and `Daemon/Makefile:1` already pin `TARGET = iphone:clang:12.4:12.0`. Do not `export TARGET` over it, and do not edit those lines back to 12.2.
- Install order is mandatory: `make` → `make package` (a `.deb`, **required** before install) → `make install`.
- After every install: `ldid -S Daemon/kioskd.entitlements` on the daemon (else `base_hook` SIGKILLs it, exit 137), `chown root:wheel` + `chmod 644` the LaunchDaemons plist (else launchd refuses it), reload the daemon job, then `uicache -p /Applications/HASmartboard.app`.
- Only the daemon is a launchd job (`layout/Library/LaunchDaemons/com.hasmartboard.daemon.plist` — note the **lowercase `layout/`**, the FS is case-sensitive). The app is launched from the home screen by SpringBoard; there is no `com.hasmartboard.app.plist`, and no remote launch command.
- No test suite or linter. Validation is on-device: `curl -sf http://127.0.0.1:9090/health`, `launchctl list | grep hasmartboard`, `/var/log/kioskd.log`, `/var/log/hasmartboard.log`.

## Architecture / IPC

- kioskd (`Daemon/main.m`) reads config in `HTTPServerConfig` (`HTTP_PORT 9090`, telemetry every 30s), collects a `TelemetrySnapshot`, and serves:
  - `GET 127.0.0.1:9090/telemetry` — battery, WiFi, storage, memory, uptime, network bytes
  - `GET 127.0.0.1:9090/health`
  - `POST /command` — JSON body `{"action": "...", "value": "..."}`. Actions in `Daemon/DeviceControl.m`: `setBrightness`, `setVolume`, `muteVolume`, `toggleWiFi`, `toggleBluetooth`, `setDND`, `lockOrientation`, `reboot`, `relaunchApp`.
  - `POST /wake` — stubbed (`DaemonBridge` always returns `NO`; not wired to HA).
- App → daemon IPC is `App/DaemonBridge.m` (NSURLSession → `127.0.0.1:9090`); `NetworkMonitor`/`TelemetryRelay` consume it. The daemon binds localhost only and **never talks to HA directly** — `TelemetryRelay` is the bridge, pushing `sensor.kiosk_*` entities to HA's REST API every 30s.

## Configuration

- App config is read at launch from `/var/mobile/Library/Preferences/com.hasmartboard.plist` (`ha.url`, `ha.token`, `ha.dashboardPath`; screensaver keys) in `App/KioskViewController.m:loadHAConfig`; code defaults in that method are the fallback (URL `http://192.168.50.150:8123`, dashboard `/bedroom-kiosk/0`, empty token). **Never commit a real HA token** — the real one lives only in the device plist (schema: `config.plist.example`).

## Conventions

- Daemon is framework-light: BSD sockets/POSIX for HTTP and process control; no Foundation networking in `kioskd`.
- Keep telemetry in the flat C `TelemetrySnapshot` struct (`Daemon/TelemetryCollector.h`). If metrics change, update `TelemetrySnapshotToJSON`, `App/TelemetryRelay.m`, and the README sensor table together.
- Preserve the localhost-only bind and the endpoint shapes; telemetry refreshes every 30s and the app polls on the same interval.
- Private iOS 12 APIs (MobileWiFi, BackBoardServices) must be resolved at **runtime** (`dlsym`/objc runtime lookup), never hard `extern` — hard refs + `-Wl,-undefined,dynamic_lookup` compile but abort (SIGABRT) when a symbol is absent. Don't invent private symbols, signatures, or entitlements; verify against the iOS 12 SDK or existing declarations first.
- Known device limitations (don't re-investigate): WiFi telemetry stays empty/0 (MobileWiFi stub — see `Daemon/TelemetryCollector.m`), and battery current/temp/cycles/voltage stay 0 (IOPowerSources on iOS 12 exposes only capacity). All documented in `DEPLOYMENT_GUIDE.md`.