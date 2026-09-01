# HA Smartboard — Feature 2: In-App Settings Page (Design Spec)

**Date:** 2026-09-01
**Status:** Approved for implementation
**Related:** [2026-08-26-ipad-kiosk-design.md](./2026-08-26-ipad-kiosk-design.md), [2026-09-01-mqtt-telemetry-design.md](./2026-09-01-mqtt-telemetry-design.md)

---

## 1. Goal

Provide an in-app native Settings modal to view and modify kiosk configuration stored in `/var/mobile/Library/Preferences/com.hasmartboard.plist`. Edits persist atomically to the plist and take effect immediately at runtime (updating dashboard URL/path/auth token and screensaver parameters without requiring an app relaunch or SSH).

To ensure a solid foundation, Phase 1 focuses on the core settings (`ha` and `screensaver`) and connectivity diagnostics before expanding to additional fields.

---

## 2. Decisions (Confirmed)

| Decision | Choice |
|---|---|
| **Entry Trigger** | 4 quick taps within 2.0s in the top-right corner (`60x60` pt hotspot) on dashboard and screensaver |
| **Form Style** | Standard grouped `UITableView` wrapped in `UINavigationController` (Cancel / Save navbar items) |
| **Scoped Fields (Phase 1)** | `ha.url`, `ha.dashboardPath`, `ha.token` (masked), `screensaver.idleTimeout`, `screensaver.mode` |
| **Diagnostics** | "Test Connection" button testing `GET <ha.url>/api/` (with Bearer token) and `GET 127.0.0.1:9090/health` |
| **Persistence** | Atomic plist write (`writeToFile:atomically:YES`) preserving all other keys (e.g. `mqtt`, `daemon`) |
| **Live Reload** | Delegate callback to `KioskViewController` updates auth scripts, reloads webview, and resets idle timer |

---

## 3. Architecture & Components

```
                    ┌─────────────────────────┐
                    │   KioskViewController   │
                    └───────────┬─────────────┘
                                │ (4-tap top-right hotspot)
                                ▼
         ┌───────────────────────────────────────────────┐
         │ UINavigationController (Modal Presentation)   │
         │                                               │
         │  ┌─────────────────────────────────────────┐  │
         │  │         SettingsViewController          │  │
         │  │   (Grouped UITableView on iOS 12)       │  │
         │  └──────────────────┬──────────────────────┘  │
         └─────────────────────┼─────────────────────────┘
                               │
               ┌───────────────┴───────────────┐
               ▼                               ▼
    [ Test Connection ]               [ Save Button ]
    - GET <ha.url>/api/               - Validate URL & Timeout
    - GET 127.0.0.1:9090/health       - Write com.hasmartboard.plist (atomic)
    - Inline status / spinner         - Notify KioskViewControllerDelegate
                                      - Re-inject WKUserScript token & reload webview
                                      - Update screensaver idle timer / mode
```

### Component Roles

1. **`SettingsViewController` (`App/SettingsViewController.h/.m`)**:
   - `UITableViewController` subclass presenting the grouped settings form.
   - Manages text field lifecycle, secure text entry for tokens, segmented control for screensaver mode, and the connection test action.
   - Reads existing `/var/mobile/Library/Preferences/com.hasmartboard.plist` on `viewDidLoad`.
   - Validates inputs before saving (non-empty URL starting with `http://` or `https://`, positive integer for idle timeout).

2. **`SettingsViewControllerDelegate` (`App/SettingsViewController.h`)**:
   - `- (void)settingsViewController:(SettingsViewController *)controller didSaveConfig:(NSDictionary *)config;`
   - `- (void)settingsViewControllerDidCancel:(SettingsViewController *)controller;`

3. **`KioskViewController` (`App/KioskViewController.m`)**:
   - Hosts a `60x60` pt invisible hotspot view in the top-right corner with a 4-tap `UITapGestureRecognizer`.
   - Conforms to `SettingsViewControllerDelegate`.
   - On save: updates internal config ivars (`_haBaseURL`, `_dashboardPath`, `_haToken`), reconfigures WKWebView user scripts, reloads the dashboard request, and updates the idle timer.

4. **`ScreensaverView` (`App/ScreensaverView.m`)**:
   - Handles the 4-tap gesture in the top-right corner when screensaver is active without triggering standard touch-wake dismissal, allowing settings access from screensaver mode.

---

## 4. UI Specification (Phase 1 Baseline)

### Navigation Bar
- **Title**: "Kiosk Settings"
- **Left Button**: "Cancel" (dismisses without changes)
- **Right Button**: "Save" (validates, saves plist, notifies delegate, dismisses)

### Section 0: Home Assistant
- **Header**: "HOME ASSISTANT"
- **Row 0 (Server URL)**:
  - Label: "URL"
  - Field: `UITextField` (placeholder `http://192.168.50.150:8123`, keyboard `UIKeyboardTypeURL`, `autocapitalizationTypeNone`, `autocorrectionTypeNo`)
- **Row 1 (Dashboard Path)**:
  - Label: "Path"
  - Field: `UITextField` (placeholder `/bedroom-kiosk/0`, `autocapitalizationTypeNone`, `autocorrectionTypeNo`)
- **Row 2 (Access Token)**:
  - Label: "Token"
  - Field: `UITextField` (masked with `secureTextEntry = YES`, placeholder `Long-lived access token`)
- **Footer**: "Token is injected into the webview for dashboard authorization."

### Section 1: Screensaver
- **Header**: "SCREENSAVER"
- **Row 0 (Idle Timeout)**:
  - Label: "Timeout (sec)"
  - Field: `UITextField` (placeholder `300`, keyboard `UIKeyboardTypeNumberPad`)
- **Row 1 (Mode)**:
  - Label: "Mode"
  - Control: `UISegmentedControl` with items `["Clock", "Photo"]`
- **Footer**: "Idle timeout in seconds before the screensaver appears."

### Section 2: Diagnostics
- **Header**: "DIAGNOSTICS"
- **Row 0 (Test Connection)**:
  - Title: "Test Connection" (centered blue action text)
  - Accessory: `UIActivityIndicatorView` (hidden when idle)
- **Row 1 (Status)**:
  - Multiline detail / status label displaying result (e.g., "HA: Connected (200 OK) • kioskd: Running").

---

## 5. Persistence & Data Flow

### Plist Structure
Path: `/var/mobile/Library/Preferences/com.hasmartboard.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>ha</key>
    <dict>
        <key>url</key>
        <string>http://192.168.50.150:8123</string>
        <key>token</key>
        <string>...</string>
        <key>dashboardPath</key>
        <string>/bedroom-kiosk/0</string>
    </dict>
    <key>screensaver</key>
    <dict>
        <key>enabled</key>
        <true/>
        <key>idleTimeout</key>
        <integer>300</integer>
        <key>mode</key>
        <string>clock</string>
        <key>clockFormat</key>
        <string>HH:mm</string>
        <key>photoURLs</key>
        <array>
            <string>http://192.168.50.150:8123/api/camera_proxy/camera.living_room</string>
        </array>
        <key>dimBrightness</key>
        <real>0.1</real>
    </dict>
    <key>mqtt</key>
    <dict>...</dict>
    <key>daemon</key>
    <dict>...</dict>
</dict>
</plist>
```

### Save Procedure:
1. Load current plist into `NSMutableDictionary *root = [NSMutableDictionary dictionaryWithContentsOfFile:PREFS_PATH] ?: [NSMutableDictionary dictionary]`.
2. Extract or create `NSMutableDictionary *ha = [root[@"ha"] mutableCopy] ?: [NSMutableDictionary dictionary]`.
   - Update `ha[@"url"]`, `ha[@"dashboardPath"]`, `ha[@"token"]`.
   - Set `root[@"ha"] = ha`.
3. Extract or create `NSMutableDictionary *screensaver = [root[@"screensaver"] mutableCopy] ?: [NSMutableDictionary dictionary]`.
   - Update `screensaver[@"idleTimeout"] = @([timeoutField.text integerValue])`.
   - Update `screensaver[@"mode"] = selectedModeString`.
   - Set `root[@"screensaver"] = screensaver`.
4. Call `[root writeToFile:PREFS_PATH atomically:YES]`.
5. If write succeeds, invoke `[delegate settingsViewController:self didSaveConfig:root]` and `dismissViewControllerAnimated:YES completion:nil`.

---

## 6. Live Reload & Runtime Updates

When `settingsViewController:didSaveConfig:` is invoked on `KioskViewController`:
1. Update `_haBaseURL`, `_dashboardPath`, and `_haToken`.
2. Re-create `WKUserScript` instances for `window._kioskToken` and fetch/XHR interception with the updated token.
3. Call `[self loadDashboard]` to navigate WKWebView to the updated `_haBaseURL` + `_dashboardPath`.
4. Read updated `screensaver.idleTimeout` and call `[self resetIdleTimer]`.
5. If screensaver is currently visible, re-configure `ScreensaverView` with updated mode.

---

## 7. Build Integration

In `Makefile`:
```makefile
HASmartboard_FILES = \
    App/main.m \
    App/AppDelegate.m \
    App/KioskViewController.m \
    App/SettingsViewController.m \
    App/ScreensaverView.m \
    App/NetworkMonitor.m \
    App/DaemonBridge.m
```

---

## 8. Acceptance Criteria

- [ ] 4 quick taps on top-right corner reliably opens `SettingsViewController` from both the dashboard and screensaver.
- [ ] Single tap on screensaver still wakes the display normally (no accidental settings modal).
- [ ] Plist file is read accurately on modal open, pre-populating all form fields.
- [ ] Tapping "Test Connection" executes asynchronous calls to HA REST API and local `kioskd`, displaying success/failure status.
- [ ] Tapping "Save" writes back to `/var/mobile/Library/Preferences/com.hasmartboard.plist` without corrupting other keys (`mqtt`, `daemon`).
- [ ] Changing HA URL or Dashboard Path in settings reloads the WKWebView with the new destination without app relaunch.
- [ ] Changing idle timeout applies immediately to the idle timer.
- [ ] Passwords / tokens are masked and never logged to console/logs.
