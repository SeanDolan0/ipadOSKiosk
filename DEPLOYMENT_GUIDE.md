# Deployment Guide — HA Smartboard (Windows → iPad)

How to upload a new version of this project to the iPad and install it. Written so an AI agent (or a human) can do the whole thing end-to-end. Last verified: 2026-08-30, against iPadOS 12.5.8 (iPad Mini 2, arm64, jailbroken).

## Environment facts (do not "discover" these again)

| Thing | Value |
|---|---|
| iPad address | `root@192.168.50.53` (SSH port 22) |
| iPad root password | `alpine` (default from README — it may be changed; README advises changing it) |
| Home Assistant | `http://192.168.50.150:8123` |
| Theos on device | `/opt/theos` — **NOT** `$HOME/theos` and not `/var/theos`. |
| Build SDK | `iPhoneOS12.4.sdk` — `TARGET = iphone:clang:12.4:12.0` (root `Makefile:10` and `Daemon/Makefile:1`). Do not override on the command line; it is already pinned. |
| Project checkout on device | `/var/mobile/Apps/ipadOSKiosk` |
| PuTTY tools (SSH from Windows) | `C:\Program Files\PuTTY\plink.exe` and `pscp.exe`. **sshpass-win32 is broken** with this SSH server (rejects a correct password); always use plink/pscp. |
| SSH host key (must be pinned) | `SHA256:tTQh0tVy4n2k+Kwntq4etfwboSdVHEF+jw8Hq66MxQo` |
| App install path | `/Applications/HASmartboard.app` |
| Daemon install path | `/Library/Application Support/HASmartboard/kioskd` |
| Daemon launchd job | `/Library/LaunchDaemons/com.hasmartboard.daemon.plist` (the only launchd job; the app is NOT one) |
| Logs | `/var/log/kioskd.log` (daemon, syslog), `/var/log/hasmartboard.log` (app, NSLog) |

The device filesystem is **case-sensitive**. `layout/` (lowercase) is the Theos layout dir — the LaunchDaemons plist only ships in the `.deb` if it is `layout/Library/LaunchDaemons/com.hasmartboard.daemon.plist`.

## The two ways to get code onto the device

The device's Theos builds from source *on the device*. There is no non-jailbroken install path; the app MUST be installed via an on-device `make install` + `uicache` or SpringBoard registers it as portrait-pinned (non-rotatable). So every update is: **edit here → copy source to iPad → build+install on iPad**.

### Option A — full source sync (always safe, and required if any source changed)

From Windows (Git Bash), from the repo root:

```bash
tar -czf /c/Users/sedol/AppData/Local/Temp/ipadOSKiosk-src.tar.gz \
  Makefile control layout App Daemon HASmartboard      # the `layout/` dir is lowercase — do not rename

"/c/Program Files/PuTTY/pscp.exe" -hostkey "SHA256:tTQh0tVy4n2k+Kwntq4etfwboSdVHEF+jw8Hq66MxQo" \
  -pw alpine -batch /c/Users/sedol/AppData/Local/Temp/ipadOSKiosk-src.tar.gz \
  root@192.168.50.53:/var/mobile/Apps/ipadOSKiosk-src.tar.gz

"/c/Program Files/PuTTY/plink.exe" -hostkey "SHA256:tTQh0tVy4n2k+Kwntq4etfwboSdVHEF+jw8Hq66MxQo" \
  -pw alpine -batch root@192.168.50.53 \
  "cd /var/mobile/Apps/ipadOSKiosk && tar -xzf ../ipadOSKiosk-src.tar.gz && echo EXTRACT_OK"
```

(the `-hostkey` value must stay pinned — using `-batch` alone refuses the host key instead of accepting it.)

### Option B — edit in place on the device

```bash
plink ... root@192.168.50.53 "cd /var/mobile/Apps/ipadOSKiosk && vi App/KioskViewController.m"
```
Only for tiny edits you don't need preserved in git.

## Build + install (on the device)

```bash
plink ... root@192.168.50.53 "cd /var/mobile/Apps/ipadOSKiosk && \
  export THEOS=/opt/theos && export PATH=\$THEOS/bin:\$PATH && \
  killall HASmartboard 2>/dev/null; killall kioskd 2>/dev/null; \
  make clean >/dev/null 2>&1; make && \
  make package && \
  make install"
```

Order is **mandatory**:
1. `make` — compile (both the app and the `kioskd` tool via `SUBPROJECTS`).
2. `make package` — build the `.deb`. **Required before `make install`** — Theos errors out otherwise ("install and show require that you build a package first").
3. `make install` — dpkg-installs the `.deb`.

`fcntl(): Bad file descriptor` lines during the build are harmless noise.

## Post-install (every time — silent killers if skipped)

```bash
plink ... root@192.168.50.53 "cd /var/mobile/Apps/ipadOSKiosk && \
  ldid -SDaemon/kioskd.entitlements '/Library/Application Support/HASmartboard/kioskd' && \
  chown root:wheel /Library/LaunchDaemons/com.hasmartboard.daemon.plist && \
  chmod 644 /Library/LaunchDaemons/com.hasmartboard.daemon.plist && \
  launchctl unload /Library/LaunchDaemons/com.hasmartboard.daemon.plist 2>/dev/null; \
  launchctl load /Library/LaunchDaemons/com.hasmartboard.daemon.plist && \
  uicache -p /Applications/HASmartboard.app"
```

Why each step exists:
- **`ldid` re-sign**: the jailbreak's `base_hook.dylib` SIGKILLs binaries under `/Library/Application Support/` unless they carry `com.apple.private.security.no-sandbox`. A fresh dpkg install strips the signature. Without this the daemon dies with exit 137 right after load.
- **`chown root:wheel` the plist**: dpkg installs the LaunchDaemons plist owned by `197609` → launchd refuses to load it ("Path had bad ownership/permissions").
- **Reload the daemon job**: `make install` replaces the running daemon binary; the old process must be unloaded/loaded again.
- **`uicache`**: re-registers the app with SpringBoard. Absent a correct `uicache`, even a correct install leaves the icon stale.

## Launch the app

The app is intentionally **not** a launchd job (SpringBoard owns it, which is what makes it rotate). After `uicache`, tap the HASmartboard icon on the home screen. There is no remote `launch` command for it. It reads its config from the plist once at startup — a config change requires killing and relaunching the app.

## Verify

On the device (`plink ... 'curl -sf http://127.0.0.1:9090/health && echo && curl -sf http://127.0.0.1:9090/telemetry'`):

```bash
curl -sf http://127.0.0.1:9090/health      # {"status":"ok","pid":...,"uptime":...}
curl -sf http://127.0.0.1:9090/telemetry    # battery/wifi/storage/memory/network/uptime JSON
launchctl list | grep hasmartboard          # "PID 0 com.hasmartboard.daemon"
tail -f /var/log/kioskd.log /var/log/hasmartboard.log
```

Then confirm HA is receiving the telemetry (from anywhere on the LAN — states should refresh every ~30s; check `uptime` value changes between reads):

```bash
TOKEN="<long-lived-access-token>"
curl -s -H "Authorization: Bearer $TOKEN" http://192.168.50.150:8123/api/states/sensor.kiosk_uptime
```

## Home Assistant integration (configuring, not installing)

The app reads its HA config from `/var/mobile/Library/Preferences/com.hasmartboard.plist` **first**, and falls back to code defaults in `App/KioskViewController.m` (`loadHAConfig`). Current code defaults: URL `http://192.168.50.150:8123`, dashboard path `/bedroom-kiosk/0`, empty token.

Full plist schema (`config.plist.example` in the repo):

```xml
<dict>
  <key>ha</key>
  <dict>
    <key>url</key>
    <string>http://192.168.50.150:8123</string>
    <key>token</key>            <!-- long-lived access token, from HA profile → Security -->
    <string>...JWT...</string>
    <key>dashboardPath</key>
    <string>/bedroom-kiosk/0</string>
  </dict>
  <key>screensaver</key>
  <dict>
    <key>mode</key><string>clock</string>      <!-- clock | photo -->
    <key>idleTimeout</key><integer>300</integer>
    <key>dimBrightness</key><real>0.1</real>
    <key>photoURLs</key><array><string>http://...</string></array>
  </dict>
</dict>
```

Write it with `plutil -create` / `plutil -insert` on the device, or `pscp` a complete XML plist from Windows and `chmod 644`. Save a copy in a safe place — the plist is the only copy of the HA token.

The daemon **never talks to HA REST API**. The app used to relay telemetry via REST but this is now removed (so `/var/log/hasmartboard.log` no longer shows relay errors).

## MQTT Telemetry

Telemetry is published directly by `kioskd` over MQTT to a Mosquitto broker on the HA instance.

1. **HA Setup**: Install Mosquitto add-on in HA, create a `kiosk` user, and add the MQTT integration.
2. **Device Config**: Write the `mqtt` block to the plist:
```bash
plutil -insert mqtt -xml '<dict/>' /var/mobile/Library/Preferences/com.hasmartboard.plist; \
plutil -insert mqtt.enabled -bool YES /var/mobile/Library/Preferences/com.hasmartboard.plist; \
plutil -insert mqtt.host -string 192.168.50.150 /var/mobile/Library/Preferences/com.hasmartboard.plist; \
plutil -insert mqtt.port -integer 1883 /var/mobile/Library/Preferences/com.hasmartboard.plist; \
plutil -insert mqtt.username -string kiosk /var/mobile/Library/Preferences/com.hasmartboard.plist; \
plutil -insert mqtt.password -string YOUR_PASSWORD /var/mobile/Library/Preferences/com.hasmartboard.plist
```
3. **Verification**: 
```bash
mosquitto_sub -h 192.168.50.150 -t 'kiosk/#' -u kiosk -P YOUR_PASSWORD -v
```

## Known limitations (have been hit; don't burn time re-investigating)

1. **WiFi telemetry is empty/0** on this device. `MobileWiFi.framework` is a stub; the current-chain symbols don't exist. `Daemon/TelemetryCollector.m` resolves `WiFiManagerClientCopyDevices` + `WiFiDeviceClientCopyProperty` at runtime (`dlsym`) and degrades gracefully. SSID/RSSI/speed resolve to empty/0 → the values really aren't there.
2. **Battery current/temp/voltage/cycles stay 0.** iOS 12's IOPowerSources on this device only exposes Current Capacity / Max Capacity. The extra key reads exist but always miss.
3. **`/wake` is stubbed.** `App/DaemonBridge.m:checkWakeWithCompletion:` polls `/health` and always calls back `NO`. HA cannot currently wake the screensaver; wiring it is new code.
4. **Screensaver wake on touch only.** Not configurable from HA.
5. **No test suite / linter.** Validation is on-device (see Verify).

## Rules for AI agents

- **Never commit a real HA token** (or the on-device password) — `App/KioskViewController.m` is hardcoded-config; the token lives in the device plist, not in git.
- **Never hard-link unverified private symbols.** Private iOS 12 APIs must be `dlsym`'d at runtime (see `TelemetryCollector.m`/`DeviceControl.m`); a hard `extern` + `-Wl,-undefined,dynamic_lookup` compiles but aborts at call time (SIGABRT) when the symbol is absent.
- **Keep daemon endpoints + localhost bind stable.** The app polls the same JSON keys the daemon emits (`TelemetrySnapshotToJSON` ↔ `App/TelemetryRelay.m` ↔ README sensor table — update all three together).
- **Do not rename `layout/` to uppercase** and do not add backslashes to `kioskd_INSTALL_PATH` in `Daemon/Makefile` — both have silently broken the `.deb` before.