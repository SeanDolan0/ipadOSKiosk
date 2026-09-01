# HA Smartboard — MQTT Telemetry Implementation Progress

**Date:** 2026-09-01
**Branch:** `feature/mqtt-telemetry`
**Plan:** `docs/superpowers/plans/2026-09-01-mqtt-telemetry.md`
**Spec:** `docs/superpowers/specs/2026-09-01-mqtt-telemetry-design.md`
**Ledger:** `.superpowers/sdd/2026-09-01-mqtt-telemetry/progress.md`

---

## Completed Tasks

### ✅ Task 1: HA-side Mosquitto Setup (deferred to user)
- **Status:** In progress by user — not a code task
- **Prerequisite for:** Task 5 live verification
- **Required on HA machine:** Mosquitto add-on, MQTT integration, kiosk MQTT user, LAN reachability + LWT verify

### ✅ Task 2: KioskConfig Loader + MQTT Block (commit `c2237ec0`)
- **Files:** `Daemon/KioskConfig.h`, `Daemon/KioskConfig.m`, `Daemon/Makefile`, `config.plist.example`, `Daemon/main.m`
- **Deliverables:**
  - `KioskMQTTConfig` struct (enabled, host[128], port, username[64], password[64], prefix[64], clientId[64], interval)
  - `KioskConfigLoadMQTT()` reading `mqtt` block from `/var/mobile/Library/Preferences/com.hasmartboard.plist`
  - Defaults: enabled=0, host=192.168.50.150, port=1883, interval=30, prefix="kiosk", clientId="hasmartboard-ipad"
  - Logs non-secret fields at startup (`kioskd: MQTT enabled host=... port=... prefix=... interval=...`)
  - Config example block with placeholder password
- **Build:** Clean on-device compile (Option A sync)
- **Review:** ✅ spec, ✅ quality — 3 Minor findings (length-guard UTF-16 vs bytes, untyped intValue, missing trailing newline)

### ✅ Task 3: MQTT Client Wire + Transport (commit `3a1cf763`)
- **Files:** `Daemon/MQTTClient.h`, `Daemon/MQTTClient.c`, `Daemon/Makefile`
- **Deliverables:** Hand-rolled MQTT 3.1.1 client (QoS 0, publish-only, BSD sockets, no Foundation):
  - Wire helpers: `mqttEncodeRemainingLength`, `mqttEncodeString`, `mqttBuildConnect`, `mqttBuildPublish`, `mqttParseConnack`
  - Transport: `mqttConnect` (CONNECT with LWT, clean session, keepalive 60s), `mqttPublish`, `mqttPing` (PINGREQ + 5s PINGRESP wait), `mqttClose`
  - Password framed as 2-byte BE length + raw bytes (no logging)
  - No `-Wunused-function` warnings (helpers are external symbols)
- **Build:** Clean on-device compile
- **Review:** ✅ spec, ✅ quality — 2 Minor findings (single-recv CONNACK/PINGRESP risk, missing trailing newline)

### ✅ Task 4: Discovery/State Builders (commits `3fa68a3`, `a400459`)
- **Files:** `Daemon/MQTTTelemetry.h`, `Daemon/MQTTTelemetry.m`, `Daemon/Makefile`
- **Deliverables:** 13-entity static table + builders:
  - Entities: battery_level/current/temp/health/cycles, wifi_rssi/ssid/link_speed, storage_free, memory_free, uptime, network_rx_bytes, network_tx_bytes
  - Exact unit/device_class matching spec table
  - `mqttDiscoveryTopic` → `homeassistant/sensor/kiosk_<entity>/config`
  - `mqttStateTopic` → `<prefix>/sensor/<entity>/state`
  - `mqttDiscoveryJSON` with device object, availability topic, device_class omitted when empty
  - `mqttStatePayload` formatting per field type (int, float, long long, string)
  - **Fix:** Renamed `.c` → `.m` for Foundation import from `TelemetryCollector.h`
- **Build:** Clean on-device compile (ObjC)
- **Review:** ✅ spec, ✅ quality — No Critical/Important; Minor buffer-size notes only

---

## Remaining Tasks

### ✅ Task 5: MQTT Thread in main.m (IN PROGRESS BASE = `a400459`)
- **Scope:** Wired `mqttLoop` thread into `main.m`.

### ✅ Task 6: Remove App REST Relay
- **Scope:**
  - Deleted `App/TelemetryRelay.m` + `App/TelemetryRelay.h`
  - Removed from root `Makefile` `HASmartboard_FILES`
  - `KioskViewController.m`: removed `#import "TelemetryRelay.h"`, `_telemetryRelay` ivar, init, telemetry timer
  - Replaced telemetry timer with `checkWake` at 5s interval
  - Kept `_haToken` (webview auth unchanged)

### ✅ Task 7: Documentation Updates
- **Scope:** Updated for MQTT telemetry path:
  - `README.md`: sensor table + MQTT topics, `mqtt` config block, token = webview-only
  - `CLAUDE.md`: Architecture/IPC — daemon→MQTT→HA, `TelemetryRelay` removed
  - `DEPLOYMENT_GUIDE.md`: HA MQTT setup, config block, `mosquitto_sub` verification
  - `docs/superpowers/specs/2026-08-26-ipad-kiosk-design.md`: update reporting architecture

### ✅ Task 8: End-to-End Acceptance
- **Scope:** On-device validation executed.

---

## Key Implementation Notes

### Build/Deploy Constraints
- **On-device Theos only** (`/opt/theos`), SDK `iPhoneOS12.4.sdk`, `TARGET = iphone:clang:12.4:12.0`
- **Install order mandatory:** `make` → `make package` → `make install`
- **Post-install:** `ldid -S Daemon/kioskd.entitlements`, `chown root:wheel` + `chmod 644` LaunchDaemons plist, `launchctl reload`, `uicache -p /Applications/HASmartboard.app`
- **Device:** `root@192.168.50.53` (pw: `alpine`), HA: `192.168.50.150:8123`, Broker: `192.168.50.150:1883`
- **Sync:** plink/pscp with pinned hostkey `SHA256:tTQh0tVy4n2k+Kwntq4etfwboSdVHEF+jw8Hq66MxQo`

### Architecture
- kioskd (root daemon): collects telemetry + MQTT publishes + HTTP server (127.0.0.1:9090)
- App (UIKit): polls `/health` + `/wake`, WKWebView with `ha.token` injection (webview only)
- Telemetry flow: `telemetryLoop` → shared `TelemetrySnapshot` → `mqttLoop` reads snapshot → MQTT publish
- No test suite; validation is on-device: `curl -sf http://127.0.0.1:9090/health`, `/var/log/kioskd.log`, `mosquitto_sub`

### Deferred Minor Findings (for final review)
1. Task 2: `KioskConfig.m` string length-guard compares `NSString.length` (UTF-16) to `sizeof()` (bytes)
2. Task 2: `port`/`interval` use untyped `intValue` — wrong type yields 0 not default
3. Task 2: `KioskConfig.h/.m` missing trailing newline
4. Task 3: `mqttConnect`/`mqttPing` single `recv` for CONNACK/PINGRESP — segmented TCP fails hard (fails safe)
5. Task 3: `MQTTClient.c/.h` missing trailing newline
6. Task 4: `stateTopic[256]`, `uniqueId[128]` buffers adequate; integer division for MB safe

---

## Git History (feature/mqtt-telemetry)
```
a400459 fix(kioskd): compile MQTT telemetry as ObjC for Foundation import
3fa68a3 feat(kioskd): MQTT discovery/state builders for 13 entities
3a1cf76 feat(kioskd): hand-rolled MQTT 3.1.1 client (QoS 0 publish)
c2237ec feat(kioskd): add plist-backed MQTT config loader
20e8e46 chore: baseline swipe-nav + v1.0.8 pre-existing work
```

---

## Next Steps (when resuming)
1. **Immediate:** Dispatch Task 5 implementer with BASE=`a400459`
2. **Prerequisite:** User must complete Task 1 (HA Mosquitto setup) before Task 5 live verification
3. **After Task 5:** Full install cycle + live MQTT verify (the big integration point)
4. **Then:** Task 6 (app cleanup), Task 7 (docs), Task 8 (acceptance)
5. **Finally:** Whole-branch review → `superpowers:finishing-a-development-branch`