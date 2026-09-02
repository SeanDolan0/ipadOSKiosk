# Feature 1 — MQTT Telemetry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the app's REST telemetry push with kioskd publishing all 13 sensor entities over MQTT 3.1.1 (QoS 0, HA MQTT discovery, LWT availability) using a hand-rolled BSD-socket client, then delete the now-dead `App/TelemetryRelay`.

**Architecture:** kioskd reads a new `mqtt` block from the shared device plist, runs a dedicated MQTT thread that connects to the HA Mosquitto broker with a retained LWT, publishes 13 retained discovery configs + `online` birth on each (re)connect, then publishes state every `interval` seconds; reconnect uses exponential backoff capped at 30s. The app stops relaying telemetry to HA REST entirely (keeps the `/health`/`/wake` localhost bridge and webview token injection).

**Tech Stack:** C/ObjC daemon (Theos, arm64, iOS 12.5.8, `iphone:clang:12.4:12.0`), BSD sockets + POSIX (`poll`/`send`/`recv`/`getaddrinfo`), Foundation only for plist parsing (no Foundation networking), MQTT 3.1.1, Mosquitto broker on HA, HA MQTT discovery.

**Spec:** [`docs/superpowers/specs/2026-09-01-mqtt-telemetry-design.md`](../specs/2026-09-01-mqtt-telemetry-design.md)

## Global Constraints

- **Build on the iPad only.** Every code step ends with an on-device build. Follow [`DEPLOYMENT_GUIDE.md`](../../DEPLOYMENT_GUIDE.md): pscp a source tarball → plink `make`/`make package`/`make install` on `/var/mobile/Apps/ipadOSKiosk`, `THEOS=/opt/theos`. Do not cross-compile elsewhere.
- After every `make install`: `ldid -S Daemon/kioskd.entitlements`, `chown root:wheel` + `chmod 644` the LaunchDaemons plist, reload the daemon job, `uicache -p /Applications/HASmartboard.app`. See DEPLOYMENT_GUIDE for the exact one-liner.
- Device plist: `/var/mobile/Library/Preferences/com.hasmartboard.plist`. Daemon runs as root and can read it.
- **No test suite / linter exists in this repo** (per CLAUDE.md). "Test" steps below are on-device verification: build (compile), install, `curl -sf http://127.0.0.1:9090/health`, `/var/log/kioskd.log`, `mosquitto_sub`, HA MQTT entity check. Do not introduce a test framework.
- Never commit a real HA token or MQTT password. `config.plist.example` gets placeholders only. Never `NSLog`/`syslog` the MQTT password (or any field derived from it).
- Private iOS 12 APIs stay `dlsym`'d. The MQTT work here uses only public POSIX sockets — no private APIs.
- Keep daemon endpoints + localhost bind stable; `TelemetrySnapshot` struct and `TelemetrySnapshotToJSON` unchanged.
- Topic prefix default: `kiosk`. State topics `kiosk/sensor/<id>/state`, availability `kiosk/status`, discovery `homeassistant/sensor/kiosk_<id>/config`.
- Commit in small chunks; message format `<type>: <subject>`. (Per global `~/.claude/rules/ecc/common/git-workflow.md`, attribution is disabled — no `Co-Authored-By` trailer in commit bodies.)
- **Git hygiene:** the working tree already contains unrelated edits (e.g. `HASmartboard/Info.plist`). Stage only the files each task touches. Work on a dedicated branch (`git checkout -b feature/mqtt-telemetry`) before Task 2; do not `git add -A`.

---

### Task 1: HA-side MQTT setup (user does on the HA machine)

**Files:** none in this repo.

**Interfaces:**
- Produces: a reachable MQTT broker at `192.168.50.150:1883`, an MQTT user for the kiosk, the HA MQTT integration enabled (discovery on). Later tasks' device-side verify steps depend on this being done.

- [ ] **Step 1: Install the Mosquitto add-on**
  In HA → Settings → Add-ons → Add-on Store → **Mosquitto broker** → Install, then Start. Confirm the log shows it listening on 1883.

- [ ] **Step 2: Create a kiosk MQTT user**
  HA → Settings → People (or Users) → Add User → name `kiosk`, e.g. password `KIOSK_MQTT_PASSWORD` (record it — it goes into the device plist in a later task; never into git).

- [ ] **Step 3: Enable the MQTT integration**
  HA → Settings → Devices & Services → Add Integration → **MQTT**. It auto-detects the add-on's credentials. Enable discovery (default). Confirm the MQTT integration shows as configured.

- [ ] **Step 4: Verify broker reachable from the LAN**
  From a machine with mosquitto clients: `mosquitto_sub -h 192.168.50.150 -t 'kiosk/#' -u kiosk -P <pass> -v` runs without error (it will print the retained `kiosk/status` message once the daemon connects in Task 5; an empty waiting prompt is fine). If mosquitto clients aren't installed, defer hard verification to Task 5 and check via the HA MQTT integration instead.

- [ ] **Step 5: Commit marker**
  Nothing code-wise to commit. Note in your progress log that Task 1 is done.

> If the broker isn't reachable from the iPad yet, Tasks 2–4 still build and install fine (MQTT is off until `mqtt.enabled` is set). Only Task 5's live verification needs the broker.

---

### Task 2: Config schema + `KioskConfig` loader

**Files:**
- Create: `Daemon/KioskConfig.h`, `Daemon/KioskConfig.m`
- Modify: `Daemon/Makefile` (add the two files to `kioskd_FILES`)
- Modify: `config.plist.example` (add `mqtt` block)
- Modify: `Daemon/main.m` (call the loader, log non-secret fields)

**Interfaces:**
- Produces: `KioskMQTTConfig` struct and `void KioskConfigLoadMQTT(KioskMQTTConfig *out)` in `KioskConfig.h`. Consumed by Task 5 (`main.m` MQTT thread).

- [ ] **Step 1: Write the header**

`Daemon/KioskConfig.h`:
```c
#ifndef KioskConfig_h
#define KioskConfig_h

// Plist-derived MQTT config for kioskd. Mirror of the `mqtt` block in
// /var/mobile/Library/Preferences/com.hasmartboard.plist (see config.plist.example).
typedef struct {
    int  enabled;         // 0 = MQTT off (no thread started)
    char host[128];       // broker host, default 192.168.50.150
    int  port;            // broker port, default 1883
    char username[64];    // MQTT user (ex: "kiosk")
    char password[64];    // MQTT password — NEVER log
    char prefix[64];      // topic base, default "kiosk"
    char clientId[64];    // default "hasmartboard-ipad"
    int  interval;        // state publish cadence seconds, default 30
} KioskMQTTConfig;

// Reads the mqtt block from the device plist. If absent, leaves defaults with
// enabled=0. Safe to call at startup only (not thread-safe).
void KioskConfigLoadMQTT(KioskMQTTConfig *out);

#endif
```

- [ ] **Step 2: Write the implementation**

`Daemon/KioskConfig.m`:
```objc
#import "KioskConfig.h"
#import <Foundation/Foundation.h>
#include <string.h>

#define PREFS_PATH @"/var/mobile/Library/Preferences/com.hasmartboard.plist"

void KioskConfigLoadMQTT(KioskMQTTConfig *out) {
    memset(out, 0, sizeof(*out));
    out->enabled = 0;
    out->port = 1883;
    out->interval = 30;
    snprintf(out->host, sizeof(out->host), "%s", "192.168.50.150");
    snprintf(out->clientId, sizeof(out->clientId), "%s", "hasmartboard-ipad");
    snprintf(out->prefix, sizeof(out->prefix), "%s", "kiosk");

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    NSDictionary *mqtt = prefs[@"mqtt"];
    if (![mqtt isKindOfClass:[NSDictionary class]]) return;

    if ([mqtt objectForKey:@"enabled"])
        out->enabled = [mqtt[@"enabled"] boolValue];
    else
        out->enabled = 1; // block present without explicit flag => on

    if ([mqtt objectForKey:@"host"]) {
        NSString *v = mqtt[@"host"];
        if ([v isKindOfClass:[NSString class]] && v.length < sizeof(out->host))
            snprintf(out->host, sizeof(out->host), "%s", v.UTF8String);
    }
    if ([mqtt objectForKey:@"port"])
        out->port = [mqtt[@"port"] intValue];
    if ([mqtt objectForKey:@"user"]) {
        NSString *v = mqtt[@"user"];
        if ([v isKindOfClass:[NSString class]] && v.length < sizeof(out->username))
            snprintf(out->username, sizeof(out->username), "%s", v.UTF8String);
    }
    if ([mqtt objectForKey:@"pass"]) {
        NSString *v = mqtt[@"pass"];
        if ([v isKindOfClass:[NSString class]] && v.length < sizeof(out->password))
            snprintf(out->password, sizeof(out->password), "%s", v.UTF8String);
    }
    if ([mqtt objectForKey:@"prefix"]) {
        NSString *v = mqtt[@"prefix"];
        if ([v isKindOfClass:[NSString class]] && v.length < sizeof(out->prefix))
            snprintf(out->prefix, sizeof(out->prefix), "%s", v.UTF8String);
    }
    if ([mqtt objectForKey:@"clientId"]) {
        NSString *v = mqtt[@"clientId"];
        if ([v isKindOfClass:[NSString class]] && v.length < sizeof(out->clientId))
            snprintf(out->clientId, sizeof(out->clientId), "%s", v.UTF8String);
    }
    if ([mqtt objectForKey:@"interval"])
        out->interval = [mqtt[@"interval"] intValue];
```

- [ ] **Step 3: Add the files to the daemon build**

`Daemon/Makefile` — add to `kioskd_FILES`:
```makefile
    KioskConfig.m \
    MQTTClient.c \
    MQTTTelemetry.c \
```
(`MQTTClient.c`/`MQTTTelemetry.c` are built in Tasks 3–4; the build will fail until they exist — build the branch only after Task 4, or add all three lines at Task 4. **Recommended:** add only `KioskConfig.m` here, then the other two lines in Task 3/4.)

- [ ] **Step 4: Add the `mqtt` block to `config.plist.example`**

Append inside the top-level `<dict>` (alphabetical before the `<key>screensaver` entry):
```xml
    <key>mqtt</key>
    <dict>
        <key>enabled</key>
        <true/>
        <key>host</key>
        <string>192.168.50.150</string>
        <key>port</key>
        <integer>1883</integer>
        <key>user</key>
        <string>kiosk</string>
        <key>pass</key>
        <string>YOUR_MQTT_PASSWORD_HERE</string>
        <key>prefix</key>
        <string>kiosk</string>
        <key>clientId</key>
        <string>hasmartboard-ipad</string>
        <key>interval</key>
        <integer>30</integer>
    </dict>
```

- [ ] **Step 5: Wire the loader into `main.m` and log non-secret fields**

`Daemon/main.m`:
```c
#import "KioskConfig.h"
```
Add inside `main` before `HTTPServerStart`:
```c
    KioskMQTTConfig mqttCfg;
    KioskConfigLoadMQTT(&mqttCfg);
    if (mqttCfg.enabled) {
        syslog(LOG_NOTICE, "kioskd: MQTT enabled host=%s port=%d prefix=%s interval=%d",
               mqttCfg.host, mqttCfg.port, mqttCfg.prefix, mqttCfg.interval);
    } else {
        syslog(LOG_NOTICE, "kioskd: MQTT disabled (no mqtt block or enabled=false)");
    }
```
(Password is deliberately absent from the log line.)

- [ ] **Step 6: Build (compile check)**

Follow DEPLOYMENT_GUIDE Option A: tar `Makefile control layout App Daemon HASmartboard`, pscp to the iPad, plink `make`. Expected: clean compile, no errors/warnings for `KioskConfig.m`.

- [ ] **Step 7: Commit**

```bash
git add Daemon/KioskConfig.h Daemon/KioskConfig.m Daemon/Makefile config.plist.example Daemon/main.m
git commit -m "feat(kioskd): add plist-backed MQTT config loader

Adds KioskConfigLoadMQTT reading the mqtt block from the device plist
and logs non-secret settings at startup. Schema matches config.plist.example.

"
```

---

### Task 3: Hand-rolled MQTT client — wire format + transport

**Files:**
- Create: `Daemon/MQTTClient.c`, `Daemon/MQTTClient.h`
- Modify: `Daemon/Makefile` (add `MQTTClient.c` to `kioskd_FILES`)

**Interfaces:**
- Consumes: nothing (self-contained; takes a `MQTTClient` struct filled by the caller).
- Produces (used by Task 5): `MQTTClient` struct, `mqttConnect(...)`, `mqttPublish(...)`, `mqttPing(...)`, `mqttClose(...)`, plus pure wire helpers `mqttEncodeRemainingLength`, `mqttEncodeString`, `mqttBuildConnect`, `mqttBuildPublish`, `mqttParseConnack`.

- [ ] **Step 1: Write the header**

`Daemon/MQTTClient.h`:
```c
#ifndef MQTTClient_h
#define MQTTClient_h

#include <stddef.h>
#include <stdint.h>

// Minimal MQTT 3.1.1 client (QoS 0, publish-only) on BSD sockets. Mirrors
// HTTPServer.m: no Foundation, no third-party libs. Not thread-safe — all
// calls from the single MQTT thread.

typedef struct {
    int  sockfd;          // -1 when disconnected
    char host[128];
    int  port;
    char username[64];
    char password[64];
    char clientId[64];
    int  keepalive;       // seconds; 0 disables pings
    char willTopic[128];  // LWT topic ("" = none); will payload fixed "offline"
} MQTTClient;

// Wire helpers (pure C, sized output buffers; capacity is the array size):

// Encodes an MQTT variable-length integer (max 4 bytes). Returns bytes written.
int mqttEncodeRemainingLength(uint8_t *out, int value);

// Encodes a UTF-8 string: 2-byte big-endian length prefix + bytes. Returns bytes written.
int mqttEncodeString(uint8_t *out, const char *s);

// Builds a CONNECT packet (with LWT if willTopic non-empty, username/password if set,
// clean session, keepalive). Returns total packet length or -1 if it doesn't fit.
int mqttBuildConnect(uint8_t *out, size_t cap, const MQTTClient *c);

// Builds a PUBLISH (QoS 0) packet. retain = 1 sets the retain flag. Returns length or -1.
int mqttBuildPublish(uint8_t *out, size_t cap, const MQTTClient *c,
                     const char *topic, const char *payload, int retain);

// Parses a CONNACK (must be >= 4 bytes). Stores return code (0 = accepted).
// Returns 0 on parse success (even if returnCode != 0).
int mqttParseConnack(const uint8_t *pkt, size_t len, int *returnCode);

// Transport: TCP connect + MQTT CONNECT handshake. Returns 0 on success,
// nonzero otherwise. On success c->sockfd is a connected socket.
int mqttConnect(MQTTClient *c);

// Publishes topic/payload (QoS 0). Returns 0 on success. On failure the
// caller should treat the connection as dead and reconnect.
int mqttPublish(MQTTClient *c, const char *topic, const char *payload, int retain);

// Sends PINGREQ and waits (5s) for PINGRESP. 0 on success.
int mqttPing(MQTTClient *c);

// Closes the socket and sets sockfd = -1.
void mqttClose(MQTTClient *c);

#endif
```

- [ ] **Step 2: Write the implementation**

`Daemon/MQTTClient.c`:
```c
#include "MQTTClient.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <unistd.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>

int mqttEncodeRemainingLength(uint8_t *out, int value) {
    int n = 0;
    do {
        uint8_t digit = (uint8_t)(value % 128);
        value /= 128;
        if (value > 0) digit |= 0x80;
        out[n++] = digit;
    } while (value > 0);
    return n;
}

int mqttEncodeString(uint8_t *out, const char *s) {
    size_t len = strlen(s);
    out[0] = (uint8_t)((len >> 8) & 0xFF);
    out[1] = (uint8_t)(len & 0xFF);
    memcpy(out + 2, s, len);
    return (int)len + 2;
}

int mqttBuildConnect(uint8_t *out, size_t cap, const MQTTClient *c) {
    uint8_t vh[64];
    size_t vn = 0;
    vn += mqttEncodeString(vh + vn, "MQTT");
    vh[vn++] = 0x04;                          // protocol level 3.1.1
    uint8_t flags = 0x02;                     // clean session
    int hasUser = c->username[0] != '\0';
    int hasPass = c->password[0] != '\0';
    int hasWill = c->willTopic[0] != '\0';
    if (hasUser) flags |= 0x80;
    if (hasPass) flags |= 0x40;
    if (hasWill) flags |= 0x04 | 0x20;        // will flag + will retain
    vh[vn++] = flags;
    vh[vn++] = (uint8_t)((c->keepalive >> 8) & 0xFF);
    vh[vn++] = (uint8_t)(c->keepalive & 0xFF);

    uint8_t payload[512];
    size_t pn = 0;
    pn += mqttEncodeString(payload + pn, c->clientId);
    if (hasWill) {
        pn += mqttEncodeString(payload + pn, c->willTopic);
        pn += mqttEncodeString(payload + pn, "offline");
    }
    if (hasUser) pn += mqttEncodeString(payload + pn, c->username);
    if (hasPass) {
        size_t pl = strlen(c->password);
        if (pl > 0xFFFF) return -1;
        payload[pn++] = (uint8_t)((pl >> 8) & 0xFF);
        payload[pn++] = (uint8_t)(pl & 0xFF);
        memcpy(payload + pn, c->password, pl);
        pn += pl;
    }

    size_t rem = vn + pn;
    uint8_t rl[4];
    int rln = mqttEncodeRemainingLength(rl, (int)rem);
    size_t total = 1 + (size_t)rln + vn + pn;
    if (total > cap) return -1;
    out[0] = 0x10;                           // CONNECT
    memcpy(out + 1, rl, (size_t)rln);
    if (vn) memcpy(out + 1 + rln, vh, vn);
    if (pn) memcpy(out + 1 + rln + vn, payload, pn);
    return (int)total;
}

int mqttBuildPublish(uint8_t *out, size_t cap, const MQTTClient *c,
                     const char *topic, const char *payload, int retain) {
    (void)c;
    uint8_t vh[300];
    size_t vn = mqttEncodeString(vh, topic);
    size_t plen = strlen(payload);
    size_t rem = vn + plen;
    uint8_t rl[4];
    int rln = mqttEncodeRemainingLength(rl, (int)rem);
    size_t total = 1 + (size_t)rln + vn + plen;
    if (total > cap) return -1;
    out[0] = (uint8_t)(0x30 | (retain ? 0x01 : 0x00));  // PUBLISH QoS 0 [+retain]
    memcpy(out + 1, rl, (size_t)rln);
    if (vn) memcpy(out + 1 + rln, vh, vn);
    if (plen) memcpy(out + 1 + rln + vn, payload, plen);
    return (int)total;
}

int mqttParseConnack(const uint8_t *pkt, size_t len, int *returnCode) {
    if (len < 4) return -1;
    if (pkt[0] != 0x20) return -1;           // CONNACK
    *returnCode = pkt[3];
    return 0;
}

static int sendAll(int fd, const uint8_t *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t n = send(fd, buf + off, len - off, 0);
        if (n <= 0) return -1;
        off += (size_t)n;
    }
    return 0;
}

int mqttConnect(MQTTClient *c) {
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    char portStr[16];
    snprintf(portStr, sizeof(portStr), "%d", c->port);
    if (getaddrinfo(c->host, portStr, &hints, &res) != 0) return -1;

    int fd = -1;
    for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) continue;
        if (connect(fd, ai->ai_addr, ai->ai_addrlen) == 0) break;
        close(fd);
        fd = -1;
    }
    freeaddrinfo(res);
    if (fd < 0) return -2;

    uint8_t pkt[512];
    int len = mqttBuildConnect(pkt, sizeof(pkt), c);
    if (len < 0) { close(fd); return -3; }
    if (sendAll(fd, pkt, (size_t)len) != 0) { close(fd); return -4; }

    uint8_t ack[4];
    ssize_t got = recv(fd, ack, sizeof(ack), 0);
    if (got != 4) { close(fd); return -5; }
    int rc = -1;
    if (mqttParseConnack(ack, 4, &rc) != 0 || rc != 0) { close(fd); return -6; }

    c->sockfd = fd;
    return 0;
}

int mqttPublish(MQTTClient *c, const char *topic, const char *payload, int retain) {
    uint8_t pkt[1024];
    int len = mqttBuildPublish(pkt, sizeof(pkt), c, topic, payload, retain);
    if (len < 0) return -1;
    return sendAll(c->sockfd, pkt, (size_t)len);
}

int mqttPing(MQTTClient *c) {
    static const uint8_t pingreq[2] = {0xC0, 0x00};
    if (sendAll(c->sockfd, pingreq, 2) != 0) return -1;
    struct pollfd pf;
    pf.fd = c->sockfd;
    pf.events = POLLIN;
    if (poll(&pf, 1, 5000) != 1) return -1;
    uint8_t resp[2];
    ssize_t n = recv(c->sockfd, resp, 2, 0);
    if (n != 2 || resp[0] != 0xD0) return -1;
    return 0;
}

void mqttClose(MQTTClient *c) {
    if (c->sockfd >= 0) close(c->sockfd);
    c->sockfd = -1;
}
```

- [ ] **Step 3: Add to the daemon build**

`Daemon/Makefile` — add `MQTTClient.c` to `kioskd_FILES`:
```makefile
    MQTTClient.c \
```

- [ ] **Step 4: Build (compile check)**

DEPLOYMENT_GUIDE Option A sync + `make`. Expected: clean compile of `MQTTClient.c` (a `-Wunused-function`-free build; if the toolchain emits one for `mqttBuildConnect`/`mqttBuildPublish` because nothing calls them yet, note it — they get called in Task 5).

- [ ] **Step 5: Commit**

```bash
git add Daemon/MQTTClient.c Daemon/MQTTClient.h Daemon/Makefile
git commit -m "feat(kioskd): hand-rolled MQTT 3.1.1 client (QoS 0 publish)

BSD-socket transport, CONNECT/CONNACK/PUBLISH/PINGREQ, LWT and
clean-session support. No Foundation networking, mirrors HTTPServer.m.

"
```

---

### Task 4: Entity table + discovery/state payload builders

**Files:**
- Create: `Daemon/MQTTTelemetry.c`, `Daemon/MQTTTelemetry.h`
- Modify: `Daemon/Makefile` (add `MQTTTelemetry.c` to `kioskd_FILES`)

**Interfaces:**
- Consumes: `TelemetrySnapshot` (`TelemetryCollector.h`).
- Produces (used by Task 5): `mqttEntityCount()`, `mqttDiscoveryTopic(prefix, i, buf, cap)`, `mqttStateTopic(prefix, i, buf, cap)`, `mqttDiscoveryJSON(prefix, i, buf, cap)`, `mqttStatePayload(snapshot, i, buf, cap)`.

- [ ] **Step 1: Write the header**

`Daemon/MQTTTelemetry.h`:
```c
#ifndef MQTTTelemetry_h
#define MQTTTelemetry_h

#include "TelemetryCollector.h"
#include <stddef.h>

// Maps TelemetrySnapshot to HA MQTT discovery + state topics/payloads.
// 13 entities, matching the README sensor table and the entity list in the
// MQTT design spec.

int mqttEntityCount(void);

// homeassistant/sensor/kiosk_<id>/config  (uses the *discovery* object id)
int mqttDiscoveryTopic(const char *prefix, int index, char *out, size_t cap);

// <prefix>/sensor/<id>/state
int mqttStateTopic(const char *prefix, int index, char *out, size_t cap);

// Discovery config JSON (device_class omitted when empty; availability topic set).
// 0 on success, -1 on bad index / buffer too small.
int mqttDiscoveryJSON(const char *prefix, int index, char *out, size_t cap);

// String form of the value for one entity (0 on success, -1 on bad index).
int mqttStatePayload(const TelemetrySnapshot *snap, int index, char *out, size_t cap);

#endif
```

- [ ] **Step 2: Write the implementation**

`Daemon/MQTTTelemetry.c`:
```c
#include "MQTTTelemetry.h"
#include <stdio.h>
#include <string.h>

typedef enum {
    ENT_BATTERY_LEVEL = 0,
    ENT_BATTERY_CURRENT,
    ENT_BATTERY_TEMP,
    ENT_BATTERY_HEALTH,
    ENT_BATTERY_CYCLES,
    ENT_WIFI_RSSI,
    ENT_WIFI_SSID,
    ENT_WIFI_LINK_SPEED,
    ENT_STORAGE_FREE,
    ENT_MEMORY_FREE,
    ENT_UPTIME,
    ENT_NETWORK_RX_BYTES,
    ENT_NETWORK_TX_BYTES,
    ENT_COUNT
} KioskEntityIndex;

typedef struct {
    const char *entity;       // short id appended to sensor topic
    const char *friendly;     // HA friendly name
    const char *unit;         // unit_of_measurement ("" = omit)
    const char *deviceClass;  // device_class ("" = omit)
} KioskEntity;

static const KioskEntity kEntities[ENT_COUNT] = {
    [ENT_BATTERY_LEVEL]      = {"battery_level",       "Kiosk Battery Level",     "%",  "battery"},
    [ENT_BATTERY_CURRENT]    = {"battery_current",     "Kiosk Battery Current",   "mA", ""},
    [ENT_BATTERY_TEMP]       = {"battery_temp",        "Kiosk Battery Temp",      "°C", "temperature"},
    [ENT_BATTERY_HEALTH]     = {"battery_health",      "Kiosk Battery Health",    "%",  "battery"},
    [ENT_BATTERY_CYCLES]     = {"battery_cycles",      "Kiosk Battery Cycles",    "count", ""},
    [ENT_WIFI_RSSI]          = {"wifi_rssi",           "Kiosk WiFi RSSI",         "dBm","signal_strength"},
    [ENT_WIFI_SSID]          = {"wifi_ssid",           "Kiosk WiFi SSID",         "",   ""},
    [ENT_WIFI_LINK_SPEED]    = {"wifi_link_speed",     "Kiosk WiFi Link Speed",   "Mbps",""},
    [ENT_STORAGE_FREE]       = {"storage_free",        "Kiosk Storage Free",      "MB", "data_size"},
    [ENT_MEMORY_FREE]        = {"memory_free",         "Kiosk Memory Free",       "MB", "data_size"},
    [ENT_UPTIME]             = {"uptime",              "Kiosk Uptime",            "s",  "duration"},
    [ENT_NETWORK_RX_BYTES]   = {"network_rx_bytes",    "Kiosk Network RX",        "bytes", "data_size"},
    [ENT_NETWORK_TX_BYTES]   = {"network_tx_bytes",    "Kiosk Network TX",        "bytes", "data_size"},
};

int mqttEntityCount(void) {
    return ENT_COUNT;
}

int mqttDiscoveryTopic(const char *prefix, int index, char *out, size_t cap) {
    if (index < 0 || index >= ENT_COUNT) return -1;
    int n = snprintf(out, cap, "homeassistant/sensor/kiosk_%s/config", kEntities[index].entity);
    return (n > 0 && (size_t)n < cap) ? 0 : -1;
}

int mqttStateTopic(const char *prefix, int index, char *out, size_t cap) {
    if (index < 0 || index >= ENT_COUNT) return -1;
    int n = snprintf(out, cap, "%s/sensor/%s/state", prefix, kEntities[index].entity);
    return (n > 0 && (size_t)n < cap) ? 0 : -1;
}

int mqttDiscoveryJSON(const char *prefix, int index, char *out, size_t cap) {
    if (index < 0 || index >= ENT_COUNT) return -1;
    const KioskEntity *e = &kEntities[index];
    char stateTopic[256];
    if (mqttStateTopic(prefix, index, stateTopic, sizeof(stateTopic)) != 0) return -1;
    char uniqueId[128];
    snprintf(uniqueId, sizeof(uniqueId), "kiosk_%s", e->entity);
    int n;
    if (e->deviceClass[0]) {
        n = snprintf(out, cap,
            "{\"name\":\"%s\",\"unique_id\":\"%s\",\"state_topic\":\"%s\","
            "\"unit_of_measurement\":\"%s\",\"device_class\":\"%s\","
            "\"availability_topic\":\"%s/status\","
            "\"device\":{\"identifiers\":[\"hasmartboard_kiosk\"],\"name\":\"iPad Kiosk\",\"model\":\"iPad Mini 2\"}}",
            e->friendly, uniqueId, stateTopic, e->unit, e->deviceClass, prefix);
    } else {
        n = snprintf(out, cap,
            "{\"name\":\"%s\",\"unique_id\":\"%s\",\"state_topic\":\"%s\","
            "\"unit_of_measurement\":\"%s\","
            "\"availability_topic\":\"%s/status\","
            "\"device\":{\"identifiers\":[\"hasmartboard_kiosk\"],\"name\":\"iPad Kiosk\",\"model\":\"iPad Mini 2\"}}",
            e->friendly, uniqueId, stateTopic, e->unit, prefix);
    }
    return (n > 0 && (size_t)n < cap) ? 0 : -1;
}

int mqttStatePayload(const TelemetrySnapshot *s, int index, char *out, size_t cap) {
    if (!s) return -1;
    int n = -1;
    switch (index) {
        case ENT_BATTERY_LEVEL:    n = snprintf(out, cap, "%d", s->batteryLevel); break;
        case ENT_BATTERY_CURRENT:  n = snprintf(out, cap, "%d", s->batteryCurrentMA); break;
        case ENT_BATTERY_TEMP:     n = snprintf(out, cap, "%.1f", s->batteryTempDeciC / 10.0); break;
        case ENT_BATTERY_HEALTH:   n = snprintf(out, cap, "%d", s->batteryHealthPct); break;
        case ENT_BATTERY_CYCLES:   n = snprintf(out, cap, "%d", s->batteryCycles); break;
        case ENT_WIFI_RSSI:        n = snprintf(out, cap, "%d", s->wifiRSSI); break;
        case ENT_WIFI_SSID:        n = snprintf(out, cap, "%s", s->wifiSSID[0] ? s->wifiSSID : ""); break;
        case ENT_WIFI_LINK_SPEED:  n = snprintf(out, cap, "%d", s->wifiLinkSpeed); break;
        case ENT_STORAGE_FREE:     n = snprintf(out, cap, "%lld", s->storageFreeBytes / (1024 * 1024)); break;
        case ENT_MEMORY_FREE:      n = snprintf(out, cap, "%lld", s->memoryFreeBytes / (1024 * 1024)); break;
        case ENT_UPTIME:           n = snprintf(out, cap, "%d", s->uptimeSeconds); break;
        case ENT_NETWORK_RX_BYTES: n = snprintf(out, cap, "%lld", s->netRxBytes); break;
        case ENT_NETWORK_TX_BYTES: n = snprintf(out, cap, "%lld", s->netTxBytes); break;
        default: return -1;
    }
    return (n > 0 && (size_t)n < cap) ? 0 : -1;
}
```

- [ ] **Step 3: Add to the daemon build**

`Daemon/Makefile` — add `MQTTTelemetry.c` to `kioskd_FILES`:
```makefile
    MQTTTelemetry.c \
```

- [ ] **Step 4: Build (compile check)**

DEPLOYMENT_GUIDE Option A sync + `make`. Expected: clean compile. If the toolchain warns about a now-unused helper, note it for Task 5.

- [ ] **Step 5: Commit**

```bash
git add Daemon/MQTTTelemetry.c Daemon/MQTTTelemetry.h Daemon/Makefile
git commit -m "feat(kioskd): MQTT discovery/state builders for 13 entities

Static entity table maps TelemetrySnapshot fields to HA MQTT discovery
configs and state topics/payloads, matching the README sensor table.

"
```

---

### Task 5: MQTT thread in main.m — connect, publish, backoff, LWT

**Files:**
- Modify: `Daemon/main.m` (start/stop MQTT thread, publish discovery + birth + state).

**Interfaces:**
- Consumes: `KioskMQTTConfig` (Task 2), `MQTTClient` + helpers (Task 3), `MQTTTelemetry` builders (Task 4).

Let `KioskConfigLoadMQTT(&mqttCfg)` stay where Task 2 put it; move nothing.

- [ ] **Step 1: Include headers and add loop args struct**

`Daemon/main.m`:
```c
#include "MQTTClient.h"
#include "MQTTTelemetry.h"
#include <time.h>
```

- [ ] **Step 2: Add the MQTT thread function (before `main`)**

```c
typedef struct {
    KioskMQTTConfig *cfg;
    TelemetrySnapshot *snapshot;
} MQTTLoopArgs;

static void *mqttLoop(void *arg) {
    MQTTLoopArgs *args = (MQTTLoopArgs *)arg;
    KioskMQTTConfig *cfg = args->cfg;
    TelemetrySnapshot *snapshot = args->snapshot;

    MQTTClient client;
    memset(&client, 0, sizeof(client));
    client.sockfd = -1;
    snprintf(client.host, sizeof(client.host), "%s", cfg->host);
    client.port = cfg->port;
    snprintf(client.username, sizeof(client.username), "%s", cfg->username);
    snprintf(client.password, sizeof(client.password), "%s", cfg->password);
    snprintf(client.clientId, sizeof(client.clientId), "%s", cfg->clientId);
    client.keepalive = 60;
    snprintf(client.willTopic, sizeof(client.willTopic), "%s/status", cfg->prefix);

    char statusTopic[256];
    snprintf(statusTopic, sizeof(statusTopic), "%s/status", cfg->prefix);

    int backoff = 1;
    while (g_running) {
        if (mqttConnect(&client) != 0) {
            syslog(LOG_WARNING, "kioskd: MQTT connect to %s:%d failed, retry in %ds",
                   client.host, client.port, backoff);
            for (int i = 0; i < backoff && g_running; i++) sleep(1);
            if (backoff < 30) backoff *= 2;
            continue;
        }
        backoff = 1;
        syslog(LOG_NOTICE, "kioskd: MQTT connected to %s:%d", client.host, client.port);

        for (int i = 0; i < mqttEntityCount(); i++) {
            char topic[256], payload[1024];
            if (mqttDiscoveryTopic(cfg->prefix, i, topic, sizeof(topic)) != 0) continue;
            if (mqttDiscoveryJSON(cfg->prefix, i, payload, sizeof(payload)) != 0) continue;
            mqttPublish(&client, topic, payload, 1);   // retained discovery
        }
        mqttPublish(&client, statusTopic, "online", 1); // retained birth

        // ponytail: snapshot is read directly, shared with telemetryLoop; a
        // ragged read of a few bytes is harmless for sensor values.
        time_t lastState = 0;
        time_t lastSend = time(NULL);
        while (g_running) {
            time_t now = time(NULL);
            if (now - lastState >= cfg->interval) {
                int ok = 1;
                for (int i = 0; i < mqttEntityCount(); i++) {
                    char topic[256], value[128];
                    if (mqttStateTopic(cfg->prefix, i, topic, sizeof(topic)) != 0) { ok = 0; break; }
                    if (mqttStatePayload(snapshot, i, value, sizeof(value)) != 0) { ok = 0; break; }
                    if (mqttPublish(&client, topic, value, 0) != 0) { ok = 0; break; }
                }
                if (!ok) break;                 // link broken
                lastState = now;
                lastSend = now;
            } else if (client.keepalive > 0 && now - lastSend >= client.keepalive) {
                if (mqttPing(&client) != 0) break;
                lastSend = now;
            }
            sleep(1);
        }
        syslog(LOG_WARNING, "kioskd: MQTT link lost, reconnecting");
        mqttClose(&client);
    }
    return NULL;
}
```

- [ ] **Step 3: Start the MQTT thread in `main`**

Immediately after the `KioskConfigLoadMQTT` call from Task 2:
```c
    pthread_t mqttTid;
    if (mqttCfg.enabled) {
        MQTTLoopArgs mqttArgs;
        mqttArgs.cfg = &mqttCfg;
        mqttArgs.snapshot = &snapshot;
        pthread_create(&mqttTid, NULL, mqttLoop, &mqttArgs);
    }
```
> `mqttTid` must be in scope at shutdown; declare it with the other locals at the top of `main` (`pthread_t mqttTid = 0;`). Since `snapshot` is declared later in `main`, either move its declaration earlier or declare `mqttTid` after `snapshot` and only then branch on `mqttCfg.enabled`.

- [ ] **Step 4: Stop the thread on shutdown**

At the end of `main` (before `HTTPServerStop` or after, alongside the existing `pthread_join(tid, NULL)`):
```c
    if (mqttCfg.enabled) pthread_join(mqttTid, NULL);
```
> The inner `mqttLoop` inner `while` only exits on `g_running` → 0 between `sleep(1)` ticks, and the reconnect backoff sleeps in 1s slices, so join returns within ~1s of a signal.

- [ ] **Step 5: Set the device plist MQTT block**

On the iPad (root shell):
```bash
plutil -create /var/mobile/Library/Preferences/com.hasmartboard.plist 2>/dev/null; \
plutil -insert mqtt -xml '<dict/>' /var/mobile/Library/Preferences/com.hasmartboard.plist 2>/dev/null; \
plutil -insert mqtt.enabled -bool YES /var/mobile/Library/Preferences/com.hasmartboard.plist; \
plutil -insert mqtt.host -string 192.168.50.150 /var/mobile/Library/Preferences/com.hasmartboard.plist; \
plutil -insert mqtt.port -integer 1883 /var/mobile/Library/Preferences/com.hasmartboard.plist; \
plutil -insert mqtt.username -string kiosk /var/mobile/Library/Preferences/com.hasmartboard.plist; \
plutil -insert mqtt.password -string <REAL_PASSWORD> /var/mobile/Library/Preferences/com.hasmartboard.plist; \
plutil -insert mqtt.prefix -string kiosk /var/mobile/Library/Preferences/com.hasmartboard.plist; \
plutil -insert mqtt.clientId -string hasmartboard-ipad /var/mobile/Library/Preferences/com.hasmartboard.plist; \
plutil -insert mqtt.interval -integer 30 /var/mobile/Library/Preferences/com.hasmartboard.plist; \
chmod 644 /var/mobile/Library/Preferences/com.hasmartboard.plist
```
(Double-check `plutil -insert` path syntax on iOS 12 if desired; writing a complete XML plist via pscp is the reliable fallback — see DEPLOYMENT_GUIDE.)

- [ ] **Step 6: Build, package, install, reload, verify (the big one)**

Full DEPLOYMENT_GUIDE install cycle:
```bash
# Windows side: tar + pscp source
# Device side: make && make package && make install
# then (mandatory, in order):
ldid -S Daemon/kioskd.entitlements
chown root:wheel /Library/LaunchDaemons/com.hasmartboard.daemon.plist
chmod 644 /Library/LaunchDaemons/com.hasmartboard.daemon.plist
launchctl unload /Library/LaunchDaemons/com.hasmartboard.daemon.plist 2>/dev/null; \
launchctl load /Library/LaunchDaemons/com.hasmartboard.daemon.plist
uicache -p /Applications/HASmartboard.app
```

Verify on device:
```bash
tail -n 20 /var/log/kioskd.log
# Expected (new lines):
#   kioskd: MQTT enabled host=192.168.50.150 port=1883 prefix=kiosk interval=30
#   kioskd: MQTT connected to 192.168.50.150:1883
launchctl list | grep hasmartboard        # PID != 0
curl -sf http://127.0.0.1:9090/health     # {"status":"ok",...}
curl -sf http://127.0.0.1:9090/telemetry  # still serves (unchanged endpoint)
```

Verify MQTT from the LAN (mosquitto clients machine):
```bash
mosquitto_sub -h 192.168.50.150 -t 'kiosk/#' -u kiosk -P <pass> -v
# Expected: kiosk/status "online", then one retained discovery config per
# entity (homeassistant/sensor/kiosk_*/config), then every ~30s each
# kiosk/sensor/*/state line updates.
```

Verify HA side:
- HA → Settings → Devices & Services → MQTT → the "iPad Kiosk" device appears with 13 sensors, all showing state (many stay 0/empty per known device limitations — that's expected).
- Kill the daemon (`killall kioskd`): within a keepalive window the 13 sensors go **Unavailable** (LWT). Relaunch via launchd (`launchctl load`), sensors return.

- [ ] **Step 7: Handle the pre-existing commit or amend, then commit main.m**

```bash
git add Daemon/main.m
git commit -m "feat(kioskd): run MQTT thread publishing discovery and state

Connects with LWT, publishes 13 retained discovery configs + online
birth per connect, publishes all states every interval, reconnects with
1s..30s backoff. Non-fatal: HTTP server and telemetry collection keep
running while MQTT is down.

"
```

> If `make package`/`install` succeeded but the log shows a CONNACK reject (look for a reconnect loop before "MQTT connected"), the broker rejected credentials: verify the MQTT user/password in the plist, and that the add-on accepts LOGIN/plain auth.

---

### Task 6: Remove the app's REST telemetry relay

**Files:**
- Delete: `App/TelemetryRelay.m`, `App/TelemetryRelay.h`
- Modify: `Makefile` (root) — remove `App/TelemetryRelay.m` from `HASmartboard_FILES`
- Modify: `App/KioskViewController.m` — drop the relay ivar/init/telemetry timer; keep wake + webview token.

**Interfaces:**
- Consumes: nothing new.
- Preserves: `App/DaemonBridge.m` `checkWakeWithCompletion:` (and the unused-then-now-unused `fetchTelemetryWithCompletion:`), webview `ha.token` injection, screensaver logic.

> Note: `DaemonBridge`'s `fetchTelemetryWithCompletion:` is no longer called after this task. Leave the method in place (it is the localhost client and may be used by the future settings page); update CLAUDE.md in Task 7 to say the app no longer polls `/telemetry`.

- [ ] **Step 1: Delete the files**

```bash
git rm App/TelemetryRelay.m App/TelemetryRelay.h
```

- [ ] **Step 2: Remove from the root Makefile**

`Makefile` — delete the line `App/TelemetryRelay.m \` from `HASmartboard_FILES`.

- [ ] **Step 3: Remove relay wiring from `KioskViewController.m`**

- Remove the `#import "TelemetryRelay.h"` line.
- Remove `#import "DaemonBridge.h"` only if no longer used (it is still used — keep it).
- Remove the ivar `TelemetryRelay *_telemetryRelay;`.
- Remove the line `_telemetryRelay = [[TelemetryRelay alloc] initWithBaseURL:_haBaseURL token:_haToken];` and the `initWithBaseURL:` call (the `_haToken` ivar stays — webview injection uses it).
- Replace the telemetry timer. The old code did both fetchTelemetry→relay AND checkWake. New behavior: keep a timer that *only* checks wake. Change the timer creation block from:
```objc
    _telemetryTimer = [NSTimer scheduledTimerWithTimeInterval:TELEMETRY_INTERVAL
                                                      target:self
                                                    selector:@selector(fetchAndRelayTelemetry)
                                                    userInfo:nil
                                                     repeats:YES];
```
to:
```objc
    _telemetryTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                      target:self
                                                    selector:@selector(checkWake)
                                                    userInfo:nil
                                                     repeats:YES];
```
- Replace the `fetchAndRelayTelemetry` method body with a `- (void)checkWake` method:
```objc
- (void)checkWake {
    [_daemonBridge checkWakeWithCompletion:^(BOOL shouldWake) {
        if (shouldWake && self->_screensaverActive) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self dismissScreensaver];
            });
        }
    }];
}
```
> Keep `TELEMETRY_INTERVAL` define if still referenced (it no longer is after this change — remove it if unused; the screensaver timeout 300 remains a literal as today).

- [ ] **Step 4: Build + install + uicache (app change)**

Full install cycle as in Task 5 Step 6 (only the app changed, but `make install` reinstalls both). Then tap the app icon; confirm:
- Dashboard loads as before (webview token still injected — `/bedroom-kiosk/0` renders).
- `/var/log/hasmartboard.log` shows no `TelemetryRelay:` errors (the class is gone).
- Daemon still publishes MQTT (mosquitto_sub keeps showing the 13 states — unchanged).

- [ ] **Step 5: Commit**

```bash
git add -u Makefile App/KioskViewController.m
git add -A App/ 2>/dev/null || true
git commit -m "refactor(app): drop REST telemetry relay, telemetry now via MQTT

Deletes TelemetryRelay.m/h and the app's 30s fetchTelemetry->REST push.
App keeps the /health-/wake localhost poll (5s) for screensaver wake and
the webview token injection; the daemon now owns telemetry publishing.

"
```
> Review `git status` before committing — you want only `Makefile`, `App/KioskViewController.m`, and the two deleted `App/TelemetryRelay.*` files staged, not unrelated tree edits.

---

### Task 7: Documentation + spec alignment

**Files:**
- Modify: `README.md`, `CLAUDE.md`, `DEPLOYMENT_GUIDE.md`, `docs/superpowers/specs/2026-08-26-ipad-kiosk-design.md`, `config.plist.example` (schema section if needed).

**Interfaces:**
- Consumes: everything from Tasks 2–6.

- [ ] **Step 1: README** — in the sensor table / telemetry section, replace the "app POSTs to /api/states with Bearer token" description with: telemetry is published by `kioskd` over MQTT (QoS 0, discovery), broker `host:port`, topic map `kiosk/sensor/<id>/state`, availability `kiosk/status`, discovery `homeassistant/sensor/kiosk_<id>/config`. Note the token is now used only for the dashboard webview login. Point MQTT config to the `mqtt` block in `config.plist.example`.

- [ ] **Step 2: CLAUDE.md** — in "Architecture / IPC": telemetry path becomes `kioskd → MQTT → HA`; `App/TelemetryRelay.m` is **removed** (was the live HA bridge); add a line under Conventions: "MQTT client is hand-rolled in `Daemon/MQTTClient.c` (BSD sockets, QoS 0 publish-only). Keep it dependency-free; telemetry publishes every 30s (config `mqtt.interval`), reconnect backoff 1–30s, LWT on `kiosk/status`." Update the "Never commit a real HA token" rule to also cover the MQTT password.

- [ ] **Step 3: DEPLOYMENT_GUIDE.md** — add a short "MQTT telemetry" subsection: broker setup pointer (Mosquitto add-on + MQTT user + integration), the device-plist `mqtt` block (`plutil` commands from Task 5 Step 5), verification with `mosquitto_sub -h <host> -t 'kiosk/#'`, and note that app-side telemetry relay was removed so `/var/log/hasmartboard.log` no longer shows relay errors.

- [ ] **Step 4: Design spec** — in `docs/superpowers/specs/2026-08-26-ipad-kiosk-design.md`, update section 2 (daemon): the "HA Telemetry Reporter" block now describes MQTT publishing (or points to the new MQTT design spec rather than duplicating); section 3 (app): note telemetry relay removed.

- [ ] **Step 5: Commit**

```bash
git add README.md CLAUDE.md DEPLOYMENT_GUIDE.md docs/superpowers/specs/2026-08-26-ipad-kiosk-design.md config.plist.example
git commit -m "docs: MQTT telemetry migration (README, CLAUDE, deployment guide)

Describes kioskd MQTT publishing + discovery, the mqtt plist block, and
that the app no longer relays telemetry over REST.

"
```

---

### Task 8: End-to-end acceptance (from the spec)

**Files:** none — verification only.

- [ ] **Step 1: MQTT topics visible**

```bash
mosquitto_sub -h 192.168.50.150 -t 'kiosk/sensor/+/state' -u kiosk -P <pass> -v
# prints 13 kiosk/sensor/*/state lines that update every ~30s
```

- [ ] **Step 2: Discovery + HA entities**

- HA MQTT integration shows device "iPad Kiosk" with 13 sensors (entity ids `sensor.kiosk_battery_level` … `sensor.kiosk_network_tx_bytes`).
- Any HA dashboard tile referencing the old `sensor.kiosk_*` entities still resolves (same entity ids preserved).

- [ ] **Step 3: LWT**

- `killall kioskd` (root): within 60s the 13 sensors show Unavailable in HA.
- Reload the daemon (`launchctl unload`/`load`): sensors return to a state value.

- [ ] **Step 4: No REST pushes / no bans**

- `curl -s -H "Authorization: Bearer $TOKEN" http://192.168.50.150:8123/api/states/sensor.kiosk_uptime` still works (entity exists via discovery).
- HA log shows no new `homeassistant.components.http.ban` entries.
- `/var/log/hasmartboard.log` shows no `TelemetryRelay:` lines.

- [ ] **Step 5: daemon resilience**

- Stop broker (`ha addons stop mosquitto`): kioskd keeps serving `curl /health`, log shows `MQTT connect ... failed, retry in ...`, then `reconnecting`. Start broker again: within ~30s "MQTT connected", discovery re-published, states resume.

- [ ] **Step 6: Commit marker** (nothing to commit; mark task done in progress log.)