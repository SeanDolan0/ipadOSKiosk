# HA Smartboard — Feature 1: MQTT Telemetry (Design Spec)

**Date:** 2026-09-01
**Status:** Approved for implementation
**Related:** [2026-08-26-ipad-kiosk-design.md](./2026-08-26-ipad-kiosk-design.md) (baseline architecture)

## 1. Goal

Replace the app's REST push path (`App/TelemetryRelay.m` → `POST /api/states/...` with Bearer token) with kioskd publishing telemetry over MQTT using Home Assistant MQTT discovery. The daemon becomes the single owner of telemetry outbound; the app keeps its localhost HTTP bridge for `/command`, `/health`, `/wake`.

This is TODO Feature 1 (order matters: do MQTT before the settings page — the settings form is simpler once telemetry moves to MQTT, replacing the REST token field with MQTT credentials).

## 2. Decisions (confirmed)

| Decision | Choice |
|---|---|
| Broker | Mosquitto add-on on HA (`192.168.50.150`) |
| Client | Hand-rolled minimal MQTT 3.1.1 in kioskd (BSD sockets, QoS 0 publish-only) |
| Discovery | MQTT discovery (device publishes `homeassistant/sensor/.../config`) |
| Config source | Same device plist `/var/mobile/Library/Preferences/com.hasmartboard.plist`, new `mqtt` block, read once at startup |
| Webview auth | Keep `ha.token` in the plist, inject into WKWebView only (frontend login); no longer used for telemetry |
| Old REST telemetry path | Delete `App/TelemetryRelay.m/h` and remove app-side telemetry relay polling |

## 3. Architecture

### New data flow

```
kioskd (root, daemon)
  │  reads /var/mobile/Library/Preferences/com.hasmartboard.plist  (new "mqtt" block)
  │
  ├─ telemetryLoop (every 30s)  ─▶ collect snapshot
  │                               ─▶ publish state topics (QoS 0)
  │
  ├─ MQTT client thread ─▶ CONNECT (with LWT "offline")
  │                       ─▶ publish discovery configs
  │                       ─▶ publish LWT birth "online"
  │                       ─▶ keepalive PINGREQ loop
  │                       ─▶ auto-reconnect w/ backoff
  │
  └─ HTTPServer (unchanged: 127.0.0.1:9090 /telemetry /health /command /wake)
        — app still polls telemetry from the daemon (unchanged contract)
```

### What stays in the app
- Poll `/health` on 127.0.0.1:9090 for liveness/wake (keep the `/wake` check).
- JS bridge, WKWebView, screensaver, NetworkMonitor — unchanged.
- Webview auth: `ha.token` injected into WKWebView (unchanged); token not used for telemetry.

### What is removed
- `App/TelemetryRelay.m` + `App/TelemetryRelay.h` — delete from build and repo.
- App-side telemetry relay timer driving `fetchAndRelayTelemetry` over to HA REST (decouple `/wake` poll).

## 4. MQTT protocol (3.1.1, QoS 0)

- **Transport**: TCP to `host:port`; default `host=192.168.50.150`, `port=1883`.
- **Client ID**: stable unique, e.g. `hasmartboard-ipad` (config `clientId`).
- **QoS**: 0 for all publishes (fire-and-forget).
- **Keepalive**: 60s; client sends PINGREQ if no outbound traffic within keepalive interval; broker close/timeout → reconnect.
- **Clean session**: true.
- **Retain**: discovery configs + `status` topic retained; state topics not retained.

## 5. Topic map

Discovery base: `homeassistant/sensor/<object_id>/config` (retained, QoS 0).

State topics: `<prefix>/sensor/<entity_id>/state` (not retained).
Availability topic: `<prefix>/status` (retained, `online`/`offline`).

Discovery config JSON (per sensor):
```json
{
  "name": "<friendly name>",
  "unique_id": "kiosk_<entity_id>",
  "state_topic": "<prefix>/sensor/<entity_id>/state",
  "unit_of_measurement": "<unit>",
  "device_class": "<class>",
  "availability_topic": "<prefix>/status",
  "device": {
    "identifiers": ["hasmartboard_kiosk"],
    "name": "iPad Kiosk",
    "model": "iPad Mini 2"
  }
}
```

### Entity table (13)

| Entity id | Friendly | Unit | device_class |
|---|---|---|---|
| battery_level | Kiosk Battery Level | % | battery |
| battery_current | Kiosk Battery Current | mA | — |
| battery_temp | Kiosk Battery Temp | °C | temperature |
| battery_health | Kiosk Battery Health | % | battery |
| battery_cycles | Kiosk Battery Cycles | count | — |
| wifi_rssi | Kiosk WiFi RSSI | dBm | signal_strength |
| wifi_ssid | Kiosk WiFi SSID | — | — |
| wifi_link_speed | Kiosk WiFi Link Speed | Mbps | — |
| storage_free | Kiosk Storage Free | MB | data_size |
| memory_free | Kiosk Memory Free | MB | data_size |
| uptime | Kiosk Uptime | s | duration |
| network_rx_bytes | Kiosk Network RX | bytes | data_size |
| network_tx_bytes | Kiosk Network TX | bytes | data_size |

> Note: WiFi fields stay empty/0 on this device (MobileWiFi stub, per CLAUDE.md); discovery/topics still land so they are ready when MobileWiFi works.

## 6. Config loading in kioskd

New `mqtt` block in `/var/mobile/Library/Preferences/com.hasmartboard.plist` (and `config.plist.example`):
```xml
<key>mqtt</key>
<dict>
    <key>enabled</key>    <true/>
    <key>host</key>       <string>192.168.50.150</string>
    <key>port</key>       <integer>1883</integer>
    <key>user</key>       <string>kiosk</string>
    <key>pass</key>       <string>…</string>
    <key>prefix</key>     <string>kiosk</string>
    <key>clientId</key>   <string>hasmartboard-ipad</string>
    <key>interval</key>   <integer>30</integer>
</dict>
```

- Read once at startup (no SIGHUP reload yet; revisit when settings page lands).
- Daemon runs as root; plist under `/var/mobile/...` is root-readable. Same path the app writes in Feature 2, keeping SSH/in-app edits interchangeable.
- Never log the MQTT password.

## 7. Hand-rolled MQTT client (`Daemon/MQTTClient.m/h`)

Mirrors `Daemon/HTTPServer.m`: BSD sockets + POSIX, no Foundation networking.

- **State machine**: DISCONNECTED → CONNECTING → CONNECTED → (keepalive timeout/closer) → DISCONNECTED + backoff → CONNECTING…
- **Wire**: encode/decode MQTT variable-length integers + UTF-8 strings; build CONNECT/CONNACK/PUBLISH/PINGREQ; read CONNACK return code (0x00 success, else reject/retry).
- **CONNECT**: protocol `MQTT`, level `0x04`, clean session, keepalive 60s, optional username/password, optional LWT (Will topic `<prefix>/status`, QoS 0, retained, payload `offline`).
- **PUBLISH (QoS 0)**: header + topic + payload, fire-and-forget.
- **PINGREQ/PINGRESP**: keepalive frame; no PINGRESP within timeout → treat as dead, drop, reconnect.
- **Reconnect/backoff**: 1s → 2s → 4s → … max 30s. After reconnect, re-publish discovery configs + `online` birth.
- **Scope**: no subscribe, no QoS>0. Publish-only. Fits daemon convention.
- **Threading**: single dedicated MQTT thread owns the socket. `telemetryLoop` hands state to the MQTT thread via a small shared buffer (bounded). HTTP serving never blocks on MQTT.

## 8. Error handling

- MQTT disabled or broker unreachable → daemon keeps serving HTTP + collecting telemetry. MQTT failure is non-fatal (log + backoff, never crash).
- Password never logged.

## 9. App changes

- Delete `App/TelemetryRelay.m` + `.h`; remove from `Makefile` `HASmartboard_FILES`.
- Remove the `_telemetryTimer` that drove `fetchAndRelayTelemetry` REST pushes.
- Keep `/wake` + `/health` localhost polling (wake-from-screensaver and liveness).
- Webview keeps `ha.token` injection (unchanged).

## 10. Documentation updates

- **README.md**: sensor table gains MQTT topics + discovery note; "Configuration" documents the `mqtt` block; token is now webview-only.
- **CLAUDE.md**: Architecture/IPC — telemetry flows daemon→MQTT→HA; `TelemetryRelay` removed; add MQTT client conventions (BSD sockets, QoS 0 publish-only).
- **DEPLOYMENT_GUIDE.md**: HA-side MQTT setup, `mqtt` config block, `mosquitto_sub` verification.
- **docs/superpowers/specs/2026-08-26-ipad-kiosk-design.md**: update reporting architecture section to MQTT.
- **config.plist.example**: add the `mqtt` block.

## 11. Verification / acceptance

```
# HA side (user does on HA machine)
- Mosquitto add-on running, MQTT integration added, kiosk MQTT user created.

# Device side
- mqtt block in /var/mobile/Library/Preferences/com.hasmartboard.plist
- make → make package → make install (on-device Theos); ldid -S, chown, launchctl reload, uicache
- curl -sf http://127.0.0.1:9090/health  → daemon alive

# MQTT / HA
- mosquitto_sub -h 192.168.50.150 -t 'kiosk/sensor/+/state' -v  → 13 topics updating every ~30s
- HA MQTT integration shows kiosk sensors appearing/updating
- LWT: kill kioskd → sensors show "Unavailable" in HA; restart → back to "online"
- No homeassistant.components.http.ban entries (no more REST push)
```

## 12. Implementation shape (for writing-plans)

Phased plan:
1. **HA side setup** (user does on HA machine — broker, MQTT user, integration). Prerequisite/blocker to device verification.
2. **kioskd**: config struct + plist read + `MQTTClient.m/h` (wire, connect, publish, reconnect, backoff) + discovery configs + state publishing + wiring into `main.m`/`telemetryLoop`.
3. **App**: delete `TelemetryRelay`, remove telemetry relay polling, keep `/wake` + `/health`.
4. **Docs + config example**.
5. **Verify on-device** (mosquitto_sub, LWT, http.ban check).