# Bidirectional MQTT, REST API Server & Native TTS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement bidirectional MQTT command controls with Home Assistant auto-discovery, a full REST API server (`0.0.0.0:8080`), Darwin notification IPC, and native iOS 12 Text-to-Speech / audio chimes on the jailbroken iPad Kiosk.

**Architecture:** The root `kioskd` daemon handles the MQTT SUBSCRIBE loop (BSD sockets), listens for incoming LAN REST API requests on `0.0.0.0:8080`, directly controls BackBoardServices (brightness) and AVSystemController (volume), and dispatches UI/audio commands (TTS, beep, reload, URL, screensaver) to `HASmartboard.app` via Darwin notification IPC (`com.hasmartboard.command`) with a shared JSON payload.

**Tech Stack:** C (MQTT 3.1.1 parser, BSD sockets), Objective-C / UIKit (`AVSpeechSynthesizer`, `AudioServices`, `WKWebView`), Darwin notifications (`notify.h`), Theos build system for iOS 12.4 SDK.

**Spec:** [docs/superpowers/specs/2026-09-01-bidirectional-mqtt-rest-tts-design.md](file:///c:/Users/sedol/Documents/ipadOSKiosk/docs/superpowers/specs/2026-09-01-bidirectional-mqtt-rest-tts-design.md)

## Global Constraints
- Target architecture: arm64, iOS 12.5.8 (iPad Mini 2).
- Theos SDK: `iPhoneOS12.4.sdk` (pin `TARGET = iphone:clang:12.4:12.0`).
- No external heavy dependencies in daemon (preserve lightweight C/POSIX/BSD sockets).
- Private frameworks (`BackBoardServices`, `AVSystemController`, `MobileWiFi`) dynamically looked up via `dlsym` / `objc_getClass`.
- App-daemon IPC uses Darwin notifications (`com.hasmartboard.command`) and `/var/mobile/Library/hasmartboard-cmd.json` with `chmod 666`.

---

### Task 1: MQTT Client `SUBSCRIBE` Packet Builder & `PUBLISH` Parser

**Files:**
- Modify: `Daemon/MQTTClient.h`
- Modify: `Daemon/MQTTClient.c`
- Create: `Daemon/tests/test_mqtt_client.c`

**Interfaces:**
- Consumes: `MQTTClient` struct
- Produces:
  - `int mqttBuildSubscribe(uint8_t *out, size_t cap, uint16_t packetId, const char *topicFilter);`
  - `int mqttParsePublish(const uint8_t *pkt, size_t len, char *topicOut, size_t topicCap, char *payloadOut, size_t payloadCap);`

- [ ] **Step 1: Write unit tests for MQTT SUBSCRIBE and PUBLISH parsing**

Create `Daemon/tests/test_mqtt_client.c`:
```c
#include "../MQTTClient.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>

int main(void) {
    uint8_t buf[256];
    int len = mqttBuildSubscribe(buf, sizeof(buf), 1, "kiosk/set/#");
    assert(len > 0);
    assert(buf[0] == 0x82); // SUBSCRIBE QoS 1 fixed header

    // Test PUBLISH packet parsing (QoS 0)
    // Build a publish packet: topic = "kiosk/set/brightness", payload = "0.75"
    MQTTClient dummy;
    memset(&dummy, 0, sizeof(dummy));
    uint8_t pubPkt[256];
    int pubLen = mqttBuildPublish(pubPkt, sizeof(pubPkt), &dummy, "kiosk/set/brightness", "0.75", 0);
    assert(pubLen > 0);

    char topic[128] = {0};
    char payload[128] = {0};
    int rc = mqttParsePublish(pubPkt, pubLen, topic, sizeof(topic), payload, sizeof(payload));
    assert(rc == 0);
    assert(strcmp(topic, "kiosk/set/brightness") == 0);
    assert(strcmp(payload, "0.75") == 0);

    printf("MQTT SUBSCRIBE and PUBLISH parse tests passed!\n");
    return 0;
}
```

- [ ] **Step 2: Add functions to `Daemon/MQTTClient.h` and implement in `Daemon/MQTTClient.c`**

Add signatures to `Daemon/MQTTClient.h`:
```c
int mqttBuildSubscribe(uint8_t *out, size_t cap, uint16_t packetId, const char *topicFilter);
int mqttParsePublish(const uint8_t *pkt, size_t len, char *topicOut, size_t topicCap, char *payloadOut, size_t payloadCap);
```

Implement in `Daemon/MQTTClient.c`:
```c
int mqttBuildSubscribe(uint8_t *out, size_t cap, uint16_t packetId, const char *topicFilter) {
    uint8_t vh[4];
    vh[0] = (uint8_t)((packetId >> 8) & 0xFF);
    vh[1] = (uint8_t)(packetId & 0xFF);

    uint8_t payload[256];
    size_t pn = 0;
    pn += mqttEncodeString(payload + pn, topicFilter);
    payload[pn++] = 0x00; // Requested QoS 0

    size_t rem = 2 + pn;
    uint8_t rl[4];
    int rln = mqttEncodeRemainingLength(rl, (int)rem);
    size_t total = 1 + (size_t)rln + 2 + pn;
    if (total > cap) return -1;

    out[0] = 0x82; // SUBSCRIBE fixed header
    memcpy(out + 1, rl, (size_t)rln);
    memcpy(out + 1 + rln, vh, 2);
    memcpy(out + 1 + rln + 2, payload, pn);
    return (int)total;
}

int mqttParsePublish(const uint8_t *pkt, size_t len, char *topicOut, size_t topicCap, char *payloadOut, size_t payloadCap) {
    if (len < 4) return -1;
    if ((pkt[0] & 0xF0) != 0x30) return -1; // Not PUBLISH

    size_t idx = 1;
    // Decode remaining length
    int remLen = 0;
    int mult = 1;
    while (idx < len) {
        uint8_t digit = pkt[idx++];
        remLen += (digit & 0x7F) * mult;
        mult *= 128;
        if ((digit & 0x80) == 0) break;
    }
    if (idx + 2 > len) return -1;

    size_t topicLen = (size_t)((pkt[idx] << 8) | pkt[idx + 1]);
    idx += 2;
    if (idx + topicLen > len || topicLen >= topicCap) return -1;

    memcpy(topicOut, pkt + idx, topicLen);
    topicOut[topicLen] = '\0';
    idx += topicLen;

    size_t payloadLen = len - idx;
    if (payloadLen >= payloadCap) payloadLen = payloadCap - 1;
    if (payloadLen > 0) {
        memcpy(payloadOut, pkt + idx, payloadLen);
    }
    payloadOut[payloadLen] = '\0';
    return 0;
}
```

- [ ] **Step 3: Compile and run test**

Run: `gcc -I. Daemon/MQTTClient.c Daemon/tests/test_mqtt_client.c -o test_mqtt && ./test_mqtt`
Expected: Output "MQTT SUBSCRIBE and PUBLISH parse tests passed!"

- [ ] **Step 4: Commit**

```bash
git add Daemon/MQTTClient.h Daemon/MQTTClient.c Daemon/tests/test_mqtt_client.c
git commit -m "feat: add MQTT SUBSCRIBE builder and PUBLISH parser"
```

---

### Task 2: Expanded Home Assistant MQTT Auto-Discovery & State Payloads

**Files:**
- Modify: `Daemon/MQTTTelemetry.h`
- Modify: `Daemon/MQTTTelemetry.m`

**Interfaces:**
- Produces:
  - Extended entity list with switches, numbers, buttons, and text entities
  - `int mqttDiscoveryTopic(...)`
  - `int mqttDiscoveryJSON(...)`
  - `int mqttCommandTopic(...)`

- [ ] **Step 1: Extend entity definitions in `Daemon/MQTTTelemetry.m`**

Add entity enum values:
- `ENT_SW_SCREEN`, `ENT_SW_SCREENSAVER`, `ENT_SW_DND`
- `ENT_NUM_BRIGHTNESS`, `ENT_NUM_VOLUME`
- `ENT_BTN_RELOAD`, `ENT_BTN_WAKE`, `ENT_BTN_BEEP`, `ENT_BTN_CLEAR_CACHE`, `ENT_BTN_REBOOT`, `ENT_BTN_RELAUNCH`
- `ENT_TXT_TTS`, `ENT_TXT_URL`

- [ ] **Step 2: Generate Home Assistant Discovery JSON for each component type**

Implement type-specific discovery JSON generator (`switch`, `number`, `button`, `text`, `sensor`) in `mqttDiscoveryJSON`.
Ensure proper `command_topic`, `state_topic`, `device` block, and `unique_id`.

- [ ] **Step 3: Commit**

```bash
git add Daemon/MQTTTelemetry.h Daemon/MQTTTelemetry.m
git commit -m "feat: expand MQTT discovery for switches, numbers, buttons and text"
```

---

### Task 3: Non-Blocking MQTT Event Loop with Command Dispatch

**Files:**
- Modify: `Daemon/main.m`
- Modify: `Daemon/DeviceControl.h`
- Modify: `Daemon/DeviceControl.m`

**Interfaces:**
- Consumes: `mqttBuildSubscribe`, `mqttParsePublish`, `DeviceControlExecute`

- [ ] **Step 1: Subscribe on MQTT connect**

In `Daemon/main.m`, right after publishing discovery configs and birth status:
```c
char subTopic[128];
snprintf(subTopic, sizeof(subTopic), "%s/set/#", cfg->prefix);
uint8_t subPkt[256];
int subLen = mqttBuildSubscribe(subPkt, sizeof(subPkt), 1, subTopic);
if (subLen > 0) {
    send(client.sockfd, subPkt, (size_t)subLen, 0);
    syslog(LOG_NOTICE, "kioskd: subscribed to %s", subTopic);
}
```

- [ ] **Step 2: Use `poll()` loop to read incoming commands**

Replace sleep loop with `poll()` on `client.sockfd` (timeout 1000ms). When `POLLIN` is signaled:
1. Read packet via `recv()`.
2. Parse topic and payload with `mqttParsePublish`.
3. Extract command target from topic suffix (e.g. `kiosk/set/brightness` -> action `setBrightness`, value `0.75`).
4. Invoke `DeviceControlExecute(action, value, context)`.

- [ ] **Step 3: Commit**

```bash
git add Daemon/main.m Daemon/DeviceControl.h Daemon/DeviceControl.m
git commit -m "feat: implement non-blocking MQTT command loop and dispatch"
```

---

### Task 4: REST API Server Expansion

**Files:**
- Modify: `Daemon/HTTPServer.h`
- Modify: `Daemon/HTTPServer.m`

**Interfaces:**
- Consumes: `DeviceControlExecute`, `TelemetrySnapshot`

- [ ] **Step 1: Update bind address to `0.0.0.0` and add route handlers**

In `HTTPServer.m`:
- Change `addr.sin_addr.s_addr = htonl(INADDR_ANY);`
- Update `handleClient` to parse `/api/status`, `/api/health`, `/api/brightness`, `/api/volume`, `/api/tts`, `/api/audio/beep`, `/api/reload`, `/api/url`, `/api/screen/on`, `/api/screen/off`, `/api/screensaver/on`, `/api/screensaver/off`, `/api/clearCache`, `/api/reboot`, `/api/restart-ui`.
- Parse JSON body `{"value": ...}`, `{"text": ...}`, `{"url": ...}` for POST endpoints and forward to `g_config.commandHandler`.

- [ ] **Step 2: Commit**

```bash
git add Daemon/HTTPServer.h Daemon/HTTPServer.m
git commit -m "feat: expand REST API server routes on 0.0.0.0:8080"
```

---

### Task 5: Darwin Notification App IPC & Native Audio/TTS Engine

**Files:**
- Modify: `Daemon/DeviceControl.m`
- Modify: `App/KioskViewController.h`
- Modify: `App/KioskViewController.m`

**Interfaces:**
- Consumes: `notify_post`, `CFNotificationCenterAddObserver`, `AVSpeechSynthesizer`, `AudioServicesPlaySystemSound`

- [ ] **Step 1: Implement IPC dispatch in `Daemon/DeviceControl.m`**

For UI actions (`tts`, `beep`, `reload`, `url`, `wake`, `screensaver_on`, `screensaver_off`, `clear_cache`):
```objc
static void dispatchAppCommand(NSString *action, id payload) {
    NSDictionary *cmd = @{@"action": action, @"payload": payload ?: @""};
    NSData *data = [NSJSONSerialization dataWithJSONObject:cmd options:0 error:nil];
    NSString *path = @"/var/mobile/Library/hasmartboard-cmd.json";
    [data writeToFile:path atomically:YES];
    chmod([path UTF8String], 0666);
    notify_post("com.hasmartboard.command");
}
```

- [ ] **Step 2: Add Darwin notification observer and handlers in `App/KioskViewController.m`**

1. In `viewDidLoad`:
```objc
CFNotificationCenterAddObserver(
    CFNotificationCenterGetDarwinNotifyCenter(),
    (__bridge const void *)(self),
    onDarwinCommand,
    CFSTR("com.hasmartboard.command"),
    NULL,
    CFNotificationSuspensionBehaviorDeliverImmediately);
```
2. Implement `handleAppCommand`:
- `tts`: Use `_speechSynthesizer speakUtterance:[AVSpeechUtterance speechUtteranceWithString:text]`.
- `beep`: `AudioServicesPlaySystemSound(1005)`.
- `reload`: `[_webView reload]`.
- `url`: `[_webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]]]`.
- `wake` / `screensaver_off`: `[self dismissScreensaver]`.
- `screensaver_on`: `[self showScreensaver]`.
- `clear_cache`: `[[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:[WKWebsiteDataStore allWebsiteDataTypes] modifiedSince:[NSDate distantPast] completionHandler:^{ [self reloadDashboard]; }];`.

- [ ] **Step 3: Commit**

```bash
git add Daemon/DeviceControl.m App/KioskViewController.h App/KioskViewController.m
git commit -m "feat: implement Darwin IPC command bridge, native TTS and audio chime"
```

---

### Task 6: On-Device Build, Deployment & End-to-End Verification

**Files:**
- Target Device: `root@192.168.50.53` (iPad Mini 2)

- [ ] **Step 1: Sync codebase to iPad**
- [ ] **Step 2: Build, package, and install on device**
  - Run `make clean && make && make package && make install`
  - Re-sign daemon: `ldid -SDaemon/kioskd.entitlements /Library/LaunchDaemons/../kioskd` (or binary in install dir)
  - Set permissions on launchd plist: `chown root:wheel /Library/LaunchDaemons/com.hasmartboard.daemon.plist && chmod 644 /Library/LaunchDaemons/com.hasmartboard.daemon.plist`
  - Reload launchd job and run `uicache -p /Applications/HASmartboard.app`
- [ ] **Step 3: Verify REST endpoints via curl from Windows host**
  - `curl -sf http://192.168.50.53:8080/api/status`
  - `curl -X POST http://192.168.50.53:8080/api/audio/beep` (listen for iPad chime)
  - `curl -X POST http://192.168.50.53:8080/api/tts -d '{"text":"Home Assistant smartboard connected"}'` (listen for speech)
  - `curl -X POST http://192.168.50.53:8080/api/brightness -d '{"value":0.8}'`
- [ ] **Step 4: Verify Home Assistant MQTT entity discovery & interactive controls**
  - Verify switches (`switch.kiosk_screensaver`, `switch.kiosk_screen`), numbers (`number.kiosk_brightness`, `number.kiosk_volume`), buttons (`button.kiosk_reload`, `button.kiosk_beep`, `button.kiosk_wake`), and text (`text.kiosk_tts`).
