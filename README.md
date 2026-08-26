# HA Smartboard

Home Assistant kiosk dashboard for jailbroken iPadOS 12.5.8 (iPad Mini 2).

## What It Does

- Displays HA Lovelace dashboard full-screen via WKWebView
- Collects system telemetry (battery, WiFi, storage, memory) via root daemon
- Reports telemetry as HA sensor entities
- Configurable screensaver (clock, photo carousel, dimmed display)
- Network resilience with auto-reconnect
- HA can control brightness, volume, WiFi, Bluetooth, DND

## Requirements

- iPad Mini 2 (A7, arm64) running iPadOS 12.5.8
- Jailbroken via checkra1n or Amethyst
- OpenSSH installed on iPad
- Theos build system on Linux/WSL/Mac
- Home Assistant instance on local network

## Quick Start

1. Clone this repo
2. Edit `Daemon/main.m` — set `HA_URL` and `HA_TOKEN`
3. Edit `App/KioskViewController.m` — set `HA_BASE_URL` and `HA_TOKEN`
4. Build: `make clean && make`
5. Package: `make package`
6. Deploy: `make package install`

## Manual Deploy

```bash
# Transfer
scp packages/*.deb root@192.168.50.53:/tmp/

# Install
ssh root@192.168.50.53 "dpkg -i /tmp/com.hasmartboard_*.deb"

# Load services
ssh root@192.168.50.53 "launchctl load /Library/LaunchDaemons/com.hasmartboard.daemon.plist"
ssh root@192.168.50.53 "launchctl load /Library/LaunchDaemons/com.hasmartboard.app.plist"
```

## Security

Change the default root password:
```bash
ssh root@192.168.50.53 "passwd"
```

## Architecture

- `kioskd` — Root daemon: telemetry collection, localhost HTTP server, HA reporter
- `HASmartboard` — UIKit app: WKWebView dashboard, screensaver, network monitor
- IPC via HTTP on `127.0.0.1:9090` (localhost only)

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
