# TODO — Next features (not started)

Two planned changes. **Order matters:** do **Feature 1 (MQTT)** before **Feature 2 (settings page)** — the settings form is simpler once telemetry moves to MQTT, because the token field is then replaced by MQTT credentials and the "test connection" button targets the broker instead of the REST API.

Status: `[ ]` = not started, `[x]` = done. Do not remove items; check them off.

---

## Feature 1 — Replace long-lived access token with MQTT

**Today:** kioskd → localhost:9090 → app (`App/DaemonBridge.m`, every 30s) → `App/TelemetryRelay.m` POSTs 13 `sensor.kiosk_*` entities to `POST /api/states/...` on HA with a `Bearer` long-lived token from the device plist. Token also injected into the WKWebView for the Lovelace frontend.

**Goal:** telemetry published by the device over MQTT (HA MQTT integration + discovery); the REST token no longer used for telemetry.

### HA side
- [ ] Set up / configure an MQTT broker for HA (Mosquitto add-on or existing broker).
- [ ] Create an MQTT user account for the kiosk (not the same as the HA user).
- [ ] Add the MQTT integration in HA and verify the broker is reachable.
- [ ] Decide discovery strategy: **MQTT discovery** (device publishes `homeassistant/sensor/.../config` topics) vs manual YAML. Prefer discovery — entities auto-appear like the old `POST /api/states` created them.
- [ ] Map all 13 current entities (README table) to MQTT topics + discovery payloads (device_class: battery, temperature; unit_of_measurement).

### Device side
- [ ] **Add config loading to kioskd** — today `Daemon/main.m` reads nothing (hardcoded `HTTP_PORT`/`TELEMETRY_INTERVAL`). Define where MQTT settings come from (plist path match the app's `com.hasmartboard.plist`, or argv) and when they're read (startup; optional SIGHUP reload).
- [ ] Extend `config.plist.example` with an `mqtt:` block: `{host, port, user, pass, prefix}`. Schema must match what the settings page (Feature 2) will write.
- [ ] Implement an MQTT 3.1.1 client in kioskd. Two options — pick one and note the decision in a ponytail-style comment:
  - Hand-rolled minimal client (CONNECT/CONNACK/PUBLISH, QoS 0, keepalive) on BSD sockets — fits the framework-light daemon convention (`Daemon/HTTPServer.m` style).
  - Vendor mosquitto (client only). Note: no package manager on the jailbreak; a static build for arm64 iOS 12.5.8 is a big lift — hand-rolled is probably the keeper.
- [ ] Publish each telemetry value (QoS 0) on the discovery-configured `.../state` topics every 30s, from a new thread (mirror `telemetryLoop` in `Daemon/main.m`).
- [ ] Publish LWT (online/offline) birth/last-will so HA shows the device offline when it dies/boots.
- [ ] Reconnect/backoff when the broker is unreachable; do not lose the 30s cadence, do not block the HTTP server.
- [ ] **Decide frontend auth in the WKWebView** — the Lovelace dashboard is loaded in the app's webview and still needs *some* auth once the REST token is gone (HA frontend login via username/password session, or retain a token only for frontend injection). Document the choice.
- [ ] Remove/supersede the REST push path in `App/TelemetryRelay.m` (and the per-entity `POST /api/states` calls). Keep `DaemonBridge` HTTP for `/command`, `/health`, `/wake` — those aren't going away.
- [ ] Update docs: README sensor table + "Configuration" section, CLAUDE.md, DEPLOYMENT_GUIDE.md (token rules change; device plist gains MQTT creds).

### Feature 1 acceptance
- [ ] `mosquitto_sub -h <broker>` shows all 13 topics updating every ~30s.
- [ ] No `homeassistant.components.http.ban` entries (no more REST pushes at all).
- [ ] HA entities appear/disappear from MQTT discovery (and go offline via LWT on device reboot).

---

## Feature 2 — Settings page in the app

**Today:** all config lives in `/var/mobile/Library/Preferences/com.hasmartboard.plist`, edited by hand over SSH (`plutil` / pscp). The app reads it once in `App/KioskViewController.m:loadHAConfig` and in `showScreensaver`.

**Goal:** an in-app page to view/edit these settings, persisting back to the same plist (app runs as `mobile`, path is writable — no daemon involvement needed).

### Open questions (decide before building)
- [x] Entry gesture: the kiosk UI is a full-screen webview with no chrome. Pick one — hidden corner hotspots (N taps in N seconds), a Settings gear shown only in screensaver mode, or a start-of-day gesture (e.g. also used as way to reach it). Document the trigger; must not conflict with the screensaver touch-wake.
- [x] Form style: plain `UITableView` form vs lightweight custom labels/fields controller (no third-party UI libs).

### Build
- [x] Create `SettingsViewController` (`App/SettingsViewController.m/h`) presented modally over the webview.
- [x] Sections: HA (URL, dashboard path, token-or-MQTT fields per Feature 1 outcome), Screensaver (mode: clock/photo, idleTimeout, dimBrightness, photoURLs).
- [x] Password field: masked entry for token / MQTT password, never `NSLog`'d.
- [x] Persist to plist with `writeToFile:atomically:` — schema identical to `config.plist.example` so SSH and in-app edits are interchangeable.
- [x] On-save: reload the dashboard with the new URL/path, rebuild `TelemetryRelay` (new token), apply screensaver settings immediately (respect existing keys the app already reads).
- [x] Validation/feedback: "Test connection" button (fetch daemon `/health`, broker ping, or HA reachability) + inline save status. Fail on bad URL rather than silently saving.

### Feature 2 acceptance
- [x] Change HA URL + dashboard path in-app → app loads the new dashboard without relaunch.
- [x] Change screensaver mode/timeout in-app → takes effect on next screensaver without SSH.
- [x] Mason: plist content after edits matches what hand-editing would produce; no extra keys.

---

## Shared cleanup (do when either lands)
- [ ] `App/App.entitlements` (untracked) — decide tracked vs gitignored.
- [ ] Sweep `.gitignore`/scratch dirs on the device (`img/`, `*_local/`, …) once QA loops for these features are done.
- [ ] Update `docs/superpowers/` design spec if features change the architecture section.