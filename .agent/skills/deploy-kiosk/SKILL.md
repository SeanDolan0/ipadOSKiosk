---
name: deploy-kiosk
description: Build, package, and install a new version of the HA Smartboard on the iPad (Windows→iPad sync, on-device Theos build, post-install, verify). Use whenever source in App/ or Daemon/ changes and needs to reach the device.
disable-model-invocation: false
---

# Deploy Kiosk

Push the current source to the iPad Mini 2, build + install, and verify. This is the only supported deploy path (cross-compiling elsewhere pins the app to portrait).

Authoritative reference: `DEPLOYMENT_GUIDE.md`. If anything here conflicts with it, the guide wins — but read that file first for the "why" behind each step.

## Environment (do not re-discover)

| Thing | Value |
|---|---|
| Device | `root@192.168.50.53` (SSH 22) |
| Password | `alpine` (may have been changed — README advises changing it) |
| SSH host key (must pin) | `SHA256:tTQh0tVy4n2k+Kwntq4etfwboSdVHEF+jw8Hq66MxQo` |
| Theos on device | `/opt/theos` (NOT `$HOME/theos`) |
| SDK | `iPhoneOS12.4.sdk`, `TARGET = iphone:clang:12.4:12.0` already pinned in Makefiles — do NOT override |
| Device checkout | `/var/mobile/Apps/ipadOSKiosk` |
| PuTTY | `C:\Program Files\PuTTY\plink.exe` / `pscp.exe` — use plink/pscp, **sshpass-win32 is broken here** |
| App | `/Applications/HASmartboard.app` |
| Daemon | `/Library/Application Support/HASmartboard/kioskd` |
| Daemon launchd job | `/Library/LaunchDaemons/com.hasmartboard.daemon.plist` (only launchd job; app is NOT one) |
| Logs | `/var/log/kioskd.log`, `/var/log/hasmartboard.log` |

File system is **case-sensitive**: the Theos layout dir is lowercase `layout/`. Do not rename it.

## Workflow

Build from a **Git Bash** shell on Windows (this is a Windows→iPad project). Run steps 3→6 as a single chained command so a mid-stream failure is obvious.

### 1. Bump the app version (every deploy, before syncing)

The version shown under the home-screen icon comes from `layout/Applications/HASmartboard.app/Info.plist`. Bump `CFBundleShortVersionString` by one on the minor segment and mirror the new number into `CFBundleDisplayName` so the icon label updates too.

```bash
PLIST="layout/Applications/HASmartboard.app/Info.plist"

CURRENT=$(grep -A1 "CFBundleShortVersionString" "$PLIST" | tail -1 | sed -E 's/.*<string>([^<]*)<\/string>.*/\1/')
MAJOR=$(echo "$CURRENT" | cut -d. -f1)
MINOR=$(echo "$CURRENT" | cut -d. -f2)
NEW_VERSION="${MAJOR}.$((MINOR + 1))"

sed -i -E "/CFBundleShortVersionString/{n;s/<string>[^<]*<\/string>/<string>${NEW_VERSION}<\/string>/}" "$PLIST"
sed -i -E "/CFBundleDisplayName/{n;s/<string>[^<]*<\/string>/<string>HASmartboard v${NEW_VERSION}<\/string>/}" "$PLIST"

echo "Bumped to v${NEW_VERSION}"
grep -A1 -E "CFBundleShortVersionString|CFBundleDisplayName" "$PLIST"
```

The `grep` at the end is a sanity check — confirm both values actually changed before moving on. The sed assumes `<key>` and `<string>` are on adjacent lines (the current layout). If Xcode/Theos ever reformats the plist onto a single line, adjust the pattern instead of skipping the bump.

### 2. Sync source (Option A — required if any source changed)

From the repo root, tar the parts Theos needs and push them:

```bash
tar -czf /c/Users/sedol/AppData/Local/Temp/ipadOSKiosk-src.tar.gz \
  Makefile control layout App Daemon HASmartboard

"/c/Program Files/PuTTY/pscp.exe" -hostkey "SHA256:tTQh0tVy4n2k+Kwntq4etfwboSdVHEF+jw8Hq66MxQo" \
  -pw alpine -batch /c/Users/sedol/AppData/Local/Temp/ipadOSKiosk-src.tar.gz \
  root@192.168.50.53:/var/mobile/Apps/ipadOSKiosk-src.tar.gz

"/c/Program Files/PuTTY/plink.exe" -hostkey "SHA256:tTQh0tVy4n2k+Kwntq4etfwboSdVHEF+jw8Hq66MxQo" \
  -pw alpine -batch root@192.168.50.53 \
  "cd /var/mobile/Apps/ipadOSKiosk && tar -xzf ../ipadOSKiosk-src.tar.gz && echo EXTRACT_OK"
```

`-hostkey` must stay pinned; `-batch` alone refuses the host key.

### 3. Build + package + install (on device) — order is mandatory

`make` → `make package` → `make install`. **`make package` is required before `make install`** (Theos errors out otherwise). Kill the running processes first so files aren't held.

```bash
"/c/Program Files/PuTTY/plink.exe" -hostkey "SHA256:tTQh0tVy4n2k+Kwntq4etfwboSdVHEF+jw8Hq66MxQo" \
  -pw alpine -batch root@192.168.50.53 \
  "cd /var/mobile/Apps/ipadOSKiosk && \
  export THEOS=/opt/theos && export PATH=\$THEOS/bin:\$PATH && \
  killall HASmartboard 2>/dev/null; killall kioskd 2>/dev/null; \
  make clean >/dev/null 2>&1; make && \
  make package && \
  make install"
```

`fcntl(): Bad file descriptor` during the build is harmless noise. The root `Makefile` builds the app AND the `kioskd` tool via `SUBPROJECTS`.

### 4. Post-install (every time — silent killers if skipped)

```bash
"/c/Program Files/PuTTY/plink.exe" -hostkey "SHA256:tTQh0tVy4n2k+Kwntq4etfwboSdVHEF+jw8Hq66MxQo" \
  -pw alpine -batch root@192.168.50.53 \
  "cd /var/mobile/Apps/ipadOSKiosk && \
  ldid -SDaemon/kioskd.entitlements '/Library/Application Support/HASmartboard/kioskd' && \
  chown root:wheel /Library/LaunchDaemons/com.hasmartboard.daemon.plist && \
  chmod 644 /Library/LaunchDaemons/com.hasmartboard.daemon.plist && \
  launchctl unload /Library/LaunchDaemons/com.hasmartboard.daemon.plist 2>/dev/null; \
  launchctl load /Library/LaunchDaemons/com.hasmartboard.daemon.plist && \
  uicache -p /Applications/HASmartboard.app"
```

Why each step exists:
- **`ldid` re-sign**: the jailbreak's `base_hook.dylib` SIGKILLs binaries under `/Library/Application Support/` unless they carry `com.apple.private.security.no-sandbox`. A fresh dpkg install strips the signature → without this the daemon dies exit 137 right after load.
- **`chown root:wheel` + `chmod 644` the plist**: dpkg installs it owned by `197609` → launchd refuses ("Path had bad ownership/permissions").
- **Reload the daemon job**: `make install` replaced the running binary.
- **`uicache`**: re-registers the app with SpringBoard; without it the icon is stale.

### 5. Launch the app

Tap the HASmartboard icon on the home screen. There is **no remote launch command** — the app is intentionally NOT a launchd job. Config is read once at startup, so a config change needs the app killed and relaunched.

### 6. Verify

```bash
"/c/Program Files/PuTTY/plink.exe" -hostkey "SHA256:tTQh0tVy4n2k+Kwntq4etfwboSdVHEF+jw8Hq66MxQo" \
  -pw alpine -batch root@192.168.50.53 \
  "curl -sf http://127.0.0.1:9090/health; echo; \
   curl -sf http://127.0.0.1:9090/telemetry; echo; \
   launchctl list | grep hasmartboard; \
   tail -n 20 /var/log/kioskd.log"
```

Pass criteria:
- `/health` → `{"status":"ok",...}`
- `/telemetry` → the usual battery/wifi/storage/memory/network/uptime JSON (WiFi + battery detail legitimately read 0/empty — see limitations)
- `launchctl list` shows `PID <n> com.hasmartboard.daemon`
- No SIGKILL/exit-137 trace in `kioskd.log`

(Optional, from any LAN host — confirm HA is receiving telemetry, `uptime` should change between ~30s reads:)
```bash
curl -s -H "Authorization: Bearer $TOKEN" http://192.168.50.150:8123/api/states/sensor.kiosk_uptime
```

## Rules that never change

- **Never commit a real HA token or the on-device password.** The token lives only in the device plist (schema `config.plist.example`).
- **Never `export TARGET`** over the pinned 12.4 SDK.
- **Keep daemon endpoints + localhost bind stable** — the app polls the JSON keys `TelemetrySnapshotToJSON` emits (update `TelemetrySnapshotToJSON` ↔ `App/TelemetryRelay.m` ↔ README sensor table together).
- iOS 12 private APIs must be resolved at runtime (`dlsym`), never hard `extern`.

## Known limitations (don't re-investigate)

- WiFi telemetry (SSID/RSSI/speed) reads empty/0 — `MobileWiFi.framework` is a stub on this device.
- Battery current/temp/voltage/cycles stay 0 — iOS 12 IOPowerSources exposes only capacity.
- `/wake` is stubbed (always returns NO; HA cannot wake the screensaver).