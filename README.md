# HA Smartboard

Home Assistant kiosk dashboard for jailbroken iPadOS 12.5.8 (iPad Mini 2).

## What It Does

- Displays HA Lovelace dashboard full-screen via WKWebView
- Collects system telemetry (battery, WiFi, storage, memory) via root daemon
- Reports telemetry as HA sensor entities over MQTT
- Configurable screensaver (clock, photo carousel, dimmed display)
- Network resilience with auto-reconnect
- HA can control brightness, volume, WiFi, Bluetooth, DND

## Requirements

- iPad Mini 2 (A7, arm64) running iPadOS 12.5.8
- Jailbroken via checkra1n or Amethyst
- OpenSSH (for reaching the device)
- **Theos installed on the iPad** with an arm64 iOS 12 SDK — all builds run on-device
- Home Assistant instance on local network with Mosquitto MQTT broker

## Build on the iPad (the only supported method)

Everything is built on the iPad with Theos. On-device builds (`make install` + `uicache`) are the only way the app registers with SpringBoard as rotatable. A binary cross-compiled elsewhere and dropped into `/Applications` stays pinned in portrait — the rotation request never reaches the app, and `uicache` alone cannot fix a pre-built binary.

```bash
# in a terminal on the iPad (or over SSH)
cd <project checkout on device>
export THEOS="$HOME/theos"
export PATH="$THEOS/bin:$PATH"

make clean            # optional
make                  # builds HASmartboard + kioskd
make package          # .deb in packages/ — REQUIRED before make install
make install          # installs app → /Applications, daemon → /Library/Application Support/HASmartboard
uicache -a            # or: uicache -p /Applications/HASmartboard.app — refresh SpringBoard registration

# only the daemon is a launchd job
launchctl load /Library/LaunchDaemons/com.hasmartboard.daemon.plist
```

> **Full Windows→iPad procedure is in [`DEPLOYMENT_GUIDE.md`](DEPLOYMENT_GUIDE.md)** — sync, build, the post-install steps Theos doesn't do for you (`ldid` re-sign, plist `chown`, `launchctl reload`, `uicache`), verification, and config. Read it before deploying. Note: on this device Theos lives at `/opt/theos` (not `$HOME/theos`) and `TARGET = iphone:clang:12.4:12.0` is already pinned in the Makefiles — don't override it.
The app is opened from the home screen by SpringBoard. It is intentionally **not** a launchd job, so there is no `com.hasmartboard.app.plist`.

## Configuration

- Home Assistant URL/dashboard: read from `/var/mobile/Library/Preferences/com.hasmartboard.plist`
  (`ha.url`, `ha.dashboardPath`) when the app starts. The `ha.token` is injected into the WKWebView for dashboard login, but telemetry no longer uses it.
- MQTT config for telemetry: read from the `mqtt` block in the same plist by `kioskd`. Broker defaults to `192.168.50.150:1883`. The daemon publishes MQTT discovery and state every `interval` (30s) on topic `kiosk/sensor/<id>/state`.
- Screensaver settings (same plist):

```xml
<key>mqtt</key>
<dict>
    <key>enabled</key><true/>
    <key>host</key><string>192.168.50.150</string>
    <key>port</key><integer>1883</integer>
    <key>user</key><string>kiosk</string>
    <key>pass</key><string>YOUR_MQTT_PASSWORD_HERE</string>
    <key>prefix</key><string>kiosk</string>
    <key>clientId</key><string>hasmartboard-ipad</string>
    <key>interval</key><integer>30</integer>
</dict>
<key>screensaver</key>
<dict>
    <key>mode</key><string>clock</string>  <!-- clock, photo -->
    <key>idleTimeout</key><integer>300</integer>  <!-- seconds -->
    <key>dimBrightness</key><real>0.1</real>
    <key>photoURLs</key><array><string>http://...</string></array>
</dict>
```

Full schema in `config.plist.example`.

## Verification & logs (on the iPad)

```bash
ps aux | grep -E 'kioskd|HASmartboard' | grep -v grep
curl http://127.0.0.1:9090/health
curl http://127.0.0.1:9090/telemetry
launchctl list | grep hasmartboard
tail -f /var/log/kioskd.log
tail -f /var/log/hasmartboard.log
```

## Troubleshooting

- **Daemon killed (`Killed: 9`, exit 137)** — the jailbreak hook
  `/usr/lib/base_hook.dylib` SIGKILLs binaries under `/Library/Application Support/`
  unless they carry `com.apple.private.security.no-sandbox`. Re-sign on-device with
  `ldid` using `Daemon/kioskd.entitlements`:

  ```bash
  ldid -S<path>/kioskd.entitlements '/Library/Application Support/HASmartboard/kioskd'
  launchctl unload /Library/LaunchDaemons/com.hasmartboard.daemon.plist
  launchctl load   /Library/LaunchDaemons/com.hasmartboard.daemon.plist
  ```

- **App pinned in portrait** — it wasn't installed via an on-device `make install` + `uicache`.
  Rebuild on the iPad as above. (Running `uicache` after manually copying a pre-built binary is not sufficient.)
- **HA URL change** — hardcoded in `App/KioskViewController.m`; edit and rebuild.

## Security

Change the default root password:

```bash
ssh root@192.168.50.53 "passwd"
```

## Architecture

- `kioskd` — Root daemon: telemetry collection, localhost HTTP server (`127.0.0.1:9090`), device control
- `HASmartboard` — UIKit app: WKWebView dashboard, screensaver, network monitor
- Endpoints: `GET /telemetry`, `GET /health`, `POST /command` (`{"action","value"}`), `POST /wake`
- App ↔ daemon IPC is HTTP on `127.0.0.1:9090` only

## HA Sensor Entities

| Entity | Unit | Description |
|---|---|---|
| `sensor.kiosk_battery_level` | % | Battery charge level |
| `sensor.kiosk_battery_current` | mA | Battery current draw |
| `sensor.kiosk_battery_temp` | °C | Battery temperature |
| `sensor.kiosk_battery_health` | % | Battery health |
| `sensor.kiosk_battery_cycles` | — | Charge cycle count |
| `sensor.kiosk_wifi_rssi` | dBm | WiFi signal strength |
| `sensor.kiosk_wifi_ssid` | — | WiFi network name |
| `sensor.kiosk_wifi_link_speed` | Mbps | WiFi link speed |
| `sensor.kiosk_storage_free` | MB | Free storage |
| `sensor.kiosk_memory_free` | MB | Free memory |
| `sensor.kiosk_uptime` | s | Device uptime |
| `sensor.kiosk_network_rx_bytes` | B | Network bytes received |
| `sensor.kiosk_network_tx_bytes` | B | Network bytes transmitted |