# Sub-Project 1 Design: Bidirectional MQTT, REST API Server & Native TTS Engine

## Overview
This specification details the architecture and implementation of **Sub-Project 1** for the jailbroken iOS 12.5.8 iPad Mini 2 Kiosk (`HASmartboard.app` + `kioskd`). It adds bidirectional MQTT control (Switches, Numbers, Buttons, Text entities) with Home Assistant auto-discovery, an expanded REST API server (`0.0.0.0:8080`), Darwin notification IPC between daemon and app, and native iOS 12 Text-to-Speech (`AVSpeechSynthesizer`) / audio chimes.

---

## 1. System Architecture & IPC Flow

```
                                  ┌────────────────────────────────────────┐
                                  │      Home Assistant (MQTT / REST)      │
                                  └───────────────┬────────────────────────┘
                                                  │
                       Discovery & Telemetry (TX) │ Commands (RX)
                       via MQTT QoS 0             │ via MQTT (kiosk/set/#) or REST (0.0.0.0:8080)
                                                  │
                                  ┌───────────────▼────────────────────────┐
                                  │            kioskd (Daemon)             │
                                  │  • Listens on 0.0.0.0:8080             │
                                  │  • Subscribes to kiosk/set/#           │
                                  │  • Controls BackBoard / AVSystem       │
                                  │  • Dispatches UI/Audio commands via IPC│
                                  └───────────────┬────────────────────────┘
                                                  │
                                   Darwin Notification (com.hasmartboard.command)
                                   + Shared Payload (/var/mobile/Library/hasmartboard-cmd.json)
                                                  │
                                  ┌───────────────▼────────────────────────┐
                                  │        HASmartboard.app (UIKit)        │
                                  │  • AVSpeechSynthesizer (TTS)           │
                                  │  • AudioServices (Beep Chime)          │
                                  │  • WKWebView (Reload / Navigate / Wake)│
                                  │  • ScreensaverView (On / Off)          │
                                  └────────────────────────────────────────┘
```

---

## 2. MQTT Client & Discovery (`MQTTClient.c`, `MQTTTelemetry.m`)

### 2.1 MQTT 3.1.1 `SUBSCRIBE` Packet & Packet Parser
* **Packet Structure (`mqttBuildSubscribe`)**:
  * Fixed header: `0x82` (SUBSCRIBE, QoS 1 header byte required by spec).
  * Remaining length: variable-length int.
  * Variable header: Packet Identifier (16-bit, e.g. `0x0001`).
  * Payload: Length-prefixed topic string (`<prefix>/set/#`), QoS byte (`0x00`).
* **Incoming `PUBLISH` (`0x30`) Parsing**:
  * Extract topic name (2-byte length + string).
  * Extract payload bytes.
  * Route command to `DeviceControlExecute` or IPC bridge.

### 2.2 Home Assistant MQTT Auto-Discovery Entities
Config topics: `homeassistant/<component>/kiosk_<name>/config`

1. **Sensors** (Existing 13 sensors retained):
   * Battery Level, Current, Temp, Health, Cycles, WiFi RSSI, SSID, Link Speed, Storage Free, Memory Free, Uptime, RX Bytes, TX Bytes.
2. **Switches**:
   * `switch.kiosk_screen` — Screen backlight power / blank state.
   * `switch.kiosk_screensaver` — Force screensaver active / inactive.
   * `switch.kiosk_dnd` — Do Not Disturb toggle.
3. **Numbers (Sliders)**:
   * `number.kiosk_brightness` — Backlight brightness `0–100` (mapped to `0.0–1.0`).
   * `number.kiosk_volume` — System media volume `0–100` (mapped to `0.0–1.0`).
4. **Buttons**:
   * `button.kiosk_reload` — Reload dashboard.
   * `button.kiosk_wake` — Wake screensaver.
   * `button.kiosk_beep` — Play chime sound.
   * `button.kiosk_clear_cache` — Purge web cache.
   * `button.kiosk_relaunch` — Relaunch app.
   * `button.kiosk_reboot` — Reboot iPad.
5. **Text Entities**:
   * `text.kiosk_tts` — Text to speech message.
   * `text.kiosk_navigate_url` — Navigate to URL.

---

## 3. REST API Server (`HTTPServer.m`)

### 3.1 Network Configuration
* Binds to `0.0.0.0` (all interfaces) on port `8080` (configurable in plist `http.port`).
* Enables Cross-Origin Resource Sharing (`Access-Control-Allow-Origin: *`).

### 3.2 Endpoints

| Method | Route | Description |
|---|---|---|
| `GET` | `/api/status` | Complete JSON status snapshot. |
| `GET` | `/api/health` | Simple health check `{"status":"ok"}`. |
| `POST` | `/api/brightness` | Sets backlight level `{"value": 0.8}`. |
| `POST` | `/api/volume` | Sets system media volume `{"value": 0.5}`. |
| `POST` | `/api/tts` | Speaks text utterance `{"text": "Front door open", "lang": "en-US"}`. |
| `POST` | `/api/audio/beep` | Plays notification chime. |
| `POST` | `/api/reload` | Reloads WKWebView dashboard. |
| `POST` | `/api/url` | Loads URL `{"url": "http://..."}`. |
| `POST` | `/api/screensaver/on` | Activates screensaver. |
| `POST` | `/api/screensaver/off` | Dismisses screensaver / wakes display. |
| `POST` | `/api/screen/on` | Turns screen on. |
| `POST` | `/api/screen/off` | Turns screen off / dims. |
| `POST` | `/api/clearCache` | Purges web cache and storage. |
| `POST` | `/api/reboot` | Reboots device. |
| `POST` | `/api/restart-ui` | Relaunches `HASmartboard.app`. |

---

## 4. App-Daemon IPC & Native Audio/TTS Engine

### 4.1 IPC Bridge (`DeviceControl.m` -> `KioskViewController.m`)
* When `kioskd` receives a command affecting UI/Audio:
  1. Writes atomic JSON payload to `/var/mobile/Library/hasmartboard-cmd.json` (chmod 666 so both root and mobile can read/write).
  2. Calls `notify_post("com.hasmartboard.command")`.
* `KioskViewController.m` registers a Darwin notification observer on startup:
  1. Catches `"com.hasmartboard.command"`.
  2. Reads `/var/mobile/Library/hasmartboard-cmd.json`.
  3. Dispatches to `handleCommand:payload:` on main queue.
  4. Deletes/clears command file.

### 4.2 Native TTS & Audio Engine
* `AVSpeechSynthesizer`: Handles speech synthesis using iOS 12 voices with configurable rate, pitch, and language.
* `AudioServicesPlaySystemSound(1005)`: Plays instant hardware notification chime.
* `WKWebView` reload & URL navigation: Executes on main thread.
* `ScreensaverView` show/dismiss: Executes smoothly on main thread.

---

## 5. Verification & Testing Plan
* **Build Verification**: Run `make` and `make package` via Theos.
* **On-Device MQTT Verification**:
  * Connect to Home Assistant broker.
  * Verify 13 sensors + 3 switches + 2 numbers + 6 buttons + 2 text entities appear in Home Assistant under device `iPad Kiosk`.
  * Trigger `button.kiosk_reload` -> verify page reloads.
  * Set `number.kiosk_brightness` -> verify backlight changes.
  * Send string to `text.kiosk_tts` -> verify iPad speaks text out loud.
* **REST API Verification**:
  * `curl -X POST http://192.168.50.53:8080/api/audio/beep` -> verify chime sound.
  * `curl -X POST http://192.168.50.53:8080/api/tts -d '{"text":"Testing iPad Kiosk"}'` -> verify speech.
  * `curl http://192.168.50.53:8080/api/status` -> verify JSON telemetry snapshot.
