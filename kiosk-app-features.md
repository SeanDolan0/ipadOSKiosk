# FreeKiosk & Fully Kiosk Browser — Full Feature Reference

This document compiles every setting, control, and feature exposed by **FreeKiosk** (open-source, MIT-licensed, `RushB-fr/freekiosk`) and **Fully Kiosk Browser** (closed-source, Free/PLUS, `fully-kiosk.com`), for use as a feature-parity checklist when building a custom Home Assistant kiosk app.

Format: **Feature Name** — description.

---

# PART 1 — FreeKiosk

FreeKiosk is a free, open-source (MIT) Android kiosk app built with React Native + Kotlin native modules. It supports Android 8.0+ and focuses on WebView kiosks, external-app locking, a REST API, and native MQTT/Home Assistant discovery.

## 1.1 Display Modes

- **WebView Mode** — Displays any HTTP/HTTPS website fullscreen (SSL and self-signed certs supported). The primary mode for Home Assistant dashboards, digital signage, and web apps.
- **External App Mode** — Locks the tablet to a specific installed Android app instead of a website (e.g. Steam Link, Netflix, a custom app). Auto-relaunches the app if it exits or crashes.
- **Dashboard Mode** — Shows a configurable multi-URL tile grid so the user can tap between several dashboards/URLs, auto-returning to the grid after inactivity.
- **Media Mode** — Enhanced media playback with multi-app switching, time-based content scheduling, and performance monitoring (in active development).
- **Runtime Mode Switching** — The active display mode (WebView / External App / Media Player) can be changed on the fly via REST (`POST /api/mode`) or MQTT (`set/mode`) without rebooting the device.

## 1.2 Security & Lockdown

- **Lockdown Levels (Basic / Standard / Enterprise)** — Three tiers of protection: Basic (WebView, minimal restriction, for testing), Standard (external app + navigation blocking), and Enterprise (full Device Owner lockdown for production/public kiosks).
- **Device Owner Mode** — Uses Android's official enterprise "Device Owner" API (`dpm set-device-owner`) to gain complete device control (true screen off, reboot, permission auto-grant) without rooting. Requires no active user accounts on the device to enable.
- **Device Admin (fallback)** — A lighter-weight admin mode that still enables `lockNow()` screen locking without needing full Device Owner status.
- **Accessibility Service** — An optional accessibility service used for cross-app remote-control key injection, text typing, and (with Device Owner) automatic re-enablement after reboot so it survives Android auto-disabling it after inactivity.
- **Navigation Blocking** — Disables the Home button, Recent Apps button, and system navigation gestures while in kiosk mode.
- **Overlay Prevention** — Blocks system dialogs and notification overlays from appearing over the kiosk content.
- **Watchdog Service** — Background service that automatically detects and recovers from crashes or unexpected exits, relaunching the kiosk.
- **PIN Protection** — A PIN code (numeric or alphanumeric) required to access FreeKiosk's settings menu, unlocked by a 5-tap gesture.
- **Lock Screen Controls** — Optional PIN-screen quick controls exposed for Wi-Fi, Bluetooth, audio output, flashlight, brightness, emergency dialing, and (where supported) rotation lock.
- **Screen Pinning / Lock Task Mode** — Uses Android's task-locking policies for a stronger kiosk seal (disables status bar, recents, home in lock task mode).
- **Test Mode vs. Production Mode** — `test_mode` controls whether the Android back button leaves you on FreeKiosk (testing) or instantly relaunches the locked app (production/`immediate`), configurable via `back_button_mode` (`test` / `timer` / `immediate`).

## 1.3 Provisioning & Deployment

- **ADB Provisioning** — Full headless configuration via `adb shell am start` intent extras — no on-device UI interaction needed. Supports PIN-gated first-time setup and re-configuration.
- **Mass Deployment via Scripts** — Bash/PowerShell/TypeScript examples for scripting fleet provisioning, including waiting for completion via logcat broadcast markers.
- **Configuration Backup/Restore** — Save and restore the complete settings set (including MQTT credentials) so one device can be cloned to others.
- **Auto-launch on Boot** — Starts FreeKiosk automatically when the device powers on.
- **Keep-alive Monitoring** — Continuously monitors the app/service and restarts it if killed.
- **Broadcast Events for Provisioning** — Emits `ADB_CONFIG_SAVED`, `ADB_CONFIG_RESTARTING`, `SETTINGS_LOADED`, and `EXTERNAL_APP_LAUNCHED` broadcasts so provisioning scripts can detect exactly when configuration has taken effect.
- **Multi-App / Managed Apps JSON** — A JSON array of apps (`packageName`, `displayName`, `showOnHomeScreen`, `launchOnBoot`, `keepAlive`, `allowAccessibility`) for configuring a home-screen grid of multiple locked/managed apps at once.
- **MDM Coexistence** — Designed to coexist with an existing MDM solution that already holds Device Owner status, falling back to Device Admin or Accessibility Service for screen lock.

## 1.4 REST API (default port 8080)

**Setup / Auth**
- **Enable REST API toggle** — Turns the built-in HTTP server on/off from Settings → Advanced (or via ADB `rest_api_enabled`).
- **Configurable Port** — Set the HTTP server's listening port (default 8080).
- **API Key Authentication** — Optional `X-Api-Key` header-based key to secure API calls.
- **JSON Responses** — All endpoints return structured JSON.
- **Screen-off Availability** — The HTTP server stays reachable even when the physical screen is off (v1.2.4+).

**Status / Info (GET)**
- **`GET /api/status`** — One-call snapshot of battery, screen, webview, device, wifi, sensors, auto-brightness, kiosk, audio, storage, and memory state.
- **`GET /api/battery`** — Battery level, charging state, plug type, temperature, voltage, health, and chemistry.
- **`GET /api/brightness`** — Current screen brightness percentage.
- **`GET /api/screen`** — Physical screen on/off state plus whether the screensaver overlay is currently covering content (these are tracked independently).
- **`GET /api/sensors`** — Light, proximity, and accelerometer sensor readings.
- **`GET /api/storage`** — Total/available/used storage in MB and percent used.
- **`GET /api/memory`** — Total/available/used RAM in MB, percent used, and low-memory flag.
- **`GET /api/wifi`** — Wi-Fi connection state, SSID, RSSI signal strength, and IP address.
- **`GET /api/info`** — Device info including IP, hostname, app version, Device Owner status, and current kiosk-mode state.
- **`GET /api/health`** — Simple health-check endpoint (`{"status":"ok"}`).
- **`GET /api/screenshot`** — Returns a live PNG screenshot of the current on-screen content (works even with the screensaver overlay active).
- **`GET /api/camera/photo`** — Takes a photo with the front or back camera at a chosen JPEG quality, for use as a Home Assistant camera entity.
- **`GET /api/camera/list`** — Lists available cameras with their facing direction and max resolution.
- **`GET /api/autoBrightness`** — Returns current auto-brightness enabled state, min/max bounds, and live ambient-light level.
- **`GET /api/location`** — Last-known GPS coordinates (latitude, longitude, accuracy, altitude, speed, bearing) via GPS/Network/Passive providers.
- **`GET /api/volume`** — Current media volume level and max level.

**Control Commands (POST)**
- **`POST /api/brightness`** — Sets screen brightness to a specific value (disables auto-brightness).
- **`POST /api/autoBrightness/enable`** — Enables ambient-light-based auto-brightness with configurable min, max, and offset, using a logarithmic response curve.
- **`POST /api/autoBrightness/disable`** — Disables auto-brightness and restores the previous manual level.
- **`GET|POST /api/screen/on`** — Wakes the device / turns the screen on.
- **`GET|POST /api/screen/off`** — Turns the screen off, using a 4-tier fallback (Device Owner → Device Admin → Accessibility Service → brightness-to-0% dimming) depending on what privileges are available.
- **`GET|POST /api/screensaver/on`** — Enables the screensaver so it triggers after the configured idle timeout.
- **`GET|POST /api/screensaver/off`** — Disables the screensaver and deactivates it if currently showing.
- **`GET|POST /api/reload`** — Reloads the current WebView page.
- **`POST /api/url`** — Navigates the WebView to a new URL.
- **`POST /api/mode`** — Switches display mode at runtime (WebView / External App / Media Player) without a reboot.
- **`GET|POST /api/wake`** — Wakes the device out of the screensaver.
- **`POST /api/tts`** — Text-to-speech using Android's native TTS engine, with automatic language auto-detection from Unicode script (or an explicit BCP-47 language tag).
- **`POST /api/volume`** — Sets the media volume (0–100).
- **`POST /api/toast`** — Shows a native Android toast notification on screen.
- **`POST /api/js`** — Executes arbitrary JavaScript inside the WebView.
- **`GET|POST /api/clearCache`** — Performs a full native cache clear (HTTP cache, cookies, localStorage/sessionStorage, form data) and remounts the WebView.
- **`POST /api/app/launch`** — Launches a specified external Android app by package name.
- **`GET|POST /api/reboot`** — Reboots the device (requires Device Owner).
- **`GET|POST /api/lock`** — Truly locks/turns off the screen via `DevicePolicyManager.lockNow()` or the Accessibility Service.
- **`GET|POST /api/restart-ui`** — Restarts just the FreeKiosk app UI (`activity.recreate()`) without rebooting the device — useful for remote UI troubleshooting.

**Audio Control**
- **`POST /api/audio/play`** — Plays audio from a URL with optional looping and volume.
- **`GET|POST /api/audio/stop`** — Stops any currently playing audio.
- **`GET|POST /api/audio/beep`** — Plays a short beep sound (handy for doorbell/notification automations).

**Remote Control (Android TV style)**
- **D-Pad/Media Endpoints** — `up`, `down`, `left`, `right`, `select`, `back`, `home`, `menu`, `playpause` endpoints dispatch key events natively via the Accessibility Service (cross-app) or `dispatchKeyEvent` fallback (FreeKiosk-only), enabling D-pad navigation, highlighting, and Back/Home/Recents system actions.

**Keyboard Emulation**
- **Single Key Press** — `GET|POST /api/remote/keyboard/{key}` presses one named key (letters, digits, function keys, navigation, editing, toggles, modifiers, media, Android keys, and symbols).
- **Keyboard Shortcut / Combo** — `GET|POST /api/remote/keyboard?map={combo}` sends a modifier+key combination (e.g. `ctrl+c`, `alt+f4`).
- **Type Text** — `POST /api/remote/text` types a full text string into the currently focused input field.
- **Android-Version-Aware Injection** — On Android 13+ everything routes through `InputMethod` APIs; on Android 5–12 it falls back to accessibility-tree traversal, `ACTION_CLICK`, and `ACTION_SET_TEXT` with some limitations on Tab/F-keys/Ctrl-Alt combos.

**Errors & Testing**
- **Standard Error Responses** — Consistent `{"success":false,"error":...}` JSON with 401/403/404/500 status codes.
- **cURL-Testable** — Every endpoint is documented with ready-to-run cURL examples.

## 1.5 MQTT Integration & Home Assistant Discovery

- **Native MQTT Client (HiveMQ)** — Built-in MQTT v5/v3.1.1 client (no separate integration/add-on needed), default port 1883.
- **Push-based Status Publishing** — Publishes a full JSON state payload on a configurable interval (default 30s; range 5–3600s) instead of requiring HA to poll.
- **Home Assistant MQTT Discovery** — Automatically publishes HA MQTT Discovery configs on connect/reconnect, registering **42 auto-discovered entities** under one HA device.
  - 11 **sensors**: battery level, brightness, Wi-Fi SSID, Wi-Fi signal, light sensor, IP address, app version, memory used %, storage free, current URL, volume.
  - 6 **binary sensors**: screen on/off, screensaver active, battery charging, kiosk mode, Device Owner status, motion detected.
  - 2 **number controls**: brightness control, volume control (writable sliders).
  - 3 **switches**: screen power, screensaver, always-on motion detection.
  - 14 **buttons**: reload, wake, reboot, clear cache, lock, remote up/down/left/right/select/back/home/menu, play/pause.
  - 6 **text entities**: navigate URL, TTS, toast message, keyboard key, keyboard combo, keyboard text.
- **Availability / LWT** — Publishes `"online"`/`"offline"` to an availability topic, using MQTT's Last Will and Testament so Home Assistant correctly shows the device as "Unavailable" on an unexpected disconnect.
- **Customizable Topic Structure** — Base topic, discovery prefix, device name (used to build human-readable topics like `freekiosk/lobby/state`), and client ID are all configurable.
- **Command Parity with REST** — Every MQTT `set/{entity}` command topic has feature parity with a corresponding REST endpoint, dispatched through the same native command handler.
- **Always-on Motion Detection Toggle** — A dedicated switch to run camera-based motion detection continuously (vs. only during screensaver) at the cost of battery life.
- **Auto-reconnect with Backoff** — Automatically reconnects on Wi-Fi drops or broker restarts, re-publishing all discovery configs and re-subscribing to command topics.
- **Concurrent REST + MQTT** — Both protocols can run at the same time without conflict.

## 1.6 Motion Detection

- **Camera-based Motion Detection** — Uses the device camera to detect movement, primarily used to wake the screen from the screensaver.
- **Motion Detection Sensitivity (Low/Medium/High)** — Adjustable pixel-change threshold (15% / 8% / 4%) for how large a change is needed to trigger motion.
- **Default vs. Always-on Behavior** — By default motion detection only runs during the screensaver (to save battery); an "Always-on" mode runs continuous detection for real-time HA automations.
- **Motion Binary Sensor** — Exposed as `binary_sensor.motion_detected` via MQTT/REST for use in Home Assistant automations.

## 1.7 Screen, Power & Brightness

- **Manual & App-Managed Brightness** — Set a fixed brightness or let FreeKiosk manage it; can be toggled off entirely so brightness is left to the OS/Tasker.
- **Auto-Brightness (Ambient Light Based)** — Adjusts brightness automatically from the ambient light sensor using a logarithmic curve, with configurable min/max bounds and an optional fixed offset.
- **Screensaver with Configurable Timeout** — Activates after a set inactivity period; can be enabled/disabled remotely.
- **4-Tier Screen-Off Strategy** — Uses whichever privilege level is available (Device Owner → Device Admin → Accessibility Service → brightness dimming) to actually turn the screen off.

## 1.8 Provisioning & Config Options (ADB Parameters)

- **PIN-gated Configuration Security Model** — A device with no PIN set requires one be supplied on first configuration; a device that already has a PIN requires that existing PIN to make further changes, preventing hijack via ADB.
- **`lock_package`** — Package name of the app to lock the device to (External App mode).
- **`external_app_mode`** — `single` (classic single-app lock) or `multi` (home-screen grid of managed apps).
- **`managed_apps`** — JSON array describing each managed app's display name, home-screen visibility, boot auto-launch, keep-alive monitoring, and accessibility whitelisting.
- **`url`** — URL to load in WebView mode.
- **`kiosk_enabled`** — Enable/disable kiosk lockdown.
- **`auto_start` / `auto_launch` / `auto_relaunch`** — Control automatic launching on configuration, on boot, and relaunching after a crash/exit.
- **`test_mode` / `back_button_mode`** — Governs whether the Android back button stays on FreeKiosk (testing) or immediately relaunches the locked app (production), or relaunches after a countdown timer.
- **`status_bar`** — Show/hide a custom in-app status bar.
- **`pin_mode`** — Numeric (4–6 digit) or alphanumeric PIN entry.
- **`rest_api_enabled` / `rest_api_port` / `rest_api_key`** — Configure the REST API server headlessly.
- **`mqtt_*` parameters** — Full MQTT configuration (broker URL/port, username/password, client ID, base topic, discovery prefix, status interval, allow-control flag, device name) settable via ADB.
- **`screensaver_enabled`** — Enable/disable the screensaver via ADB.
- **Full JSON Config Blob** — A single `--es config '{...}'` JSON payload can set most of the above keys in one command.

## 1.9 Comparison Notes vs. Fully Kiosk (per FreeKiosk's own README)

- **Price** — Free (vs. Fully's paid-per-device PLUS license).
- **License** — MIT open source (vs. Fully's closed source).
- **Device Owner mode** — Supported in both.
- **REST API** — Supported in both.
- **MQTT + native Home Assistant discovery** — FreeKiosk only (Fully requires the separate `fully_kiosk` HA integration polling its own API instead of pushing discovery).
- **Cloud fleet management** — On FreeKiosk's roadmap (not yet shipped); Fully has this today via Fully Cloud EMM.

---

# PART 2 — Fully Kiosk Browser

Fully Kiosk Browser is a long-established, closed-source Android kiosk/browser/launcher app (also offered as Fully Single App Kiosk, Fully Video Kiosk, and Fully Exam Kiosk variants) with 300+ configurable settings. Many advanced features require a paid **PLUS** license (noted below as "(PLUS)"); free-tier use displays a watermark until licensed.

## 2.1 Web Content & Browsing

- **Start URL** — The home URL (supports `http://`, `https://`, `file://`), with placeholder variables like `$mac`, `$deviceID`, `$ip4`, `$hostname`, `$ssid`, etc. Multiple URLs (one per line) open as multiple tabs.
- **Basic HTTP Authentication** — Username/password fields (or embedded in the URL) for sites requiring HTTP auth.
- **Client Certificate Authentication (PLUS)** — Load a P12/PFX client cert (with password) for mutual-TLS-protected sites.
- **Fullscreen/Autoplay HTML5 Video & Audio** — Lets embedded `<video>`/`<audio>` tags autoplay and go fullscreen.
- **File Upload / Camera / Video / Audio Capture Upload (PLUS)** — Allows web forms to accept file uploads and camera/video/audio capture uploads.
- **JavaScript Alerts** — Allow/disallow native `alert`, `prompt`, and `confirm` dialogs from web content.
- **Popups & New-Frame Links (PLUS)** — Support popups, including those triggered without user interaction.
- **Webcam / Microphone / Geolocation HTML5 Access (PLUS)** — Grants secure-origin websites access to the camera, mic, or GPS via standard browser APIs.
- **PDF Viewing (local & remote, PLUS)** — Multiple handling modes: disabled, PDF.js in-page rendering, built-in fullscreen viewer, launch external app, download-and-pass, or plain download.
- **Play Videos in Fully (PLUS)** — Plays Android-supported video/RTSP streams in a built-in fullscreen player.
- **View/Open Other Files** — Configurable handling for non-PDF file links (disable, open externally, download).
- **Links to Open in Other Apps** — A whitelist of URL patterns that should be handed off to other installed apps instead of the in-app WebView.
- **Open Other URL Schemes** — Allows `tel:`, `mailto:`, `intent:` links to be handled by other apps.
- **URL Whitelist / Blacklist** — Restrict which URLs the kiosk browser is allowed (or forbidden) to load, with wildcard support; blacklist overrides whitelist.
- **Redirect Blocked URL to Start URL** — Bounces any blocked navigation back to the Start URL.
- **Web Overlay (PLUS)** — Shows a non-interactive transparent website overlay (e.g. a clock/IP display) on top of the main content.
- **Custom Error URL** — A page to display on load errors, with query params describing the error, plus a delayed reload on internet disconnection.

## 2.2 Web Browsing Behavior

- **Pull to Refresh** — Down-swipe to reload the current page.
- **Back Button Navigation** — Hardware/nav-bar back button steps through page history.
- **Load Start URL on Home Button** — Tapping Home reloads the configured Start URL (requires Kiosk Mode).
- **Tap Sound** — Optional click sound on touch interaction.
- **Swipe to Navigate / Animate Page Transitions / Swipe to Change Tabs (PLUS)** — Gesture-based forward/back navigation and app-like animated page transitions.
- **Wait for Network Connection** — Avoids showing error pages by waiting for connectivity before loading.
- **Custom Search Provider URL** — Sets the search engine used when typing keywords into the address bar.
- **Read NFC Tags (PLUS)** — Opens URLs encoded in NDEF-formatted NFC tags.

## 2.3 Zoom & Scaling

- **Enable Zoom** — Allows pinch/zoom on pages that support it.
- **Load in Overview Mode** — Downscales older, non-responsive websites to fit device width.
- **Use Wide Viewport** — Honors the page's `<meta viewport>` tag.
- **Initial Scale %** — Manually sets an initial zoom level for pages that ignore the viewport tag.
- **Font Size Scaling** — Adjusts text size as a percentage.
- **Desktop Mode** — Requests the desktop version of a site instead of mobile.

## 2.4 Auto-Reload

- **Auto Reload on Idle** — Reloads the Start URL or current page after a set number of idle seconds.
- **Auto Reload after Page Error** — Reloads automatically after a load failure, with a configurable delay.
- **Auto Reload on Screen On / Screensaver Stop / Network Reconnect / Internet Reconnect** — Triggers a reload on any of these specific events.
- **Purge on Reload (Cache/Webstorage/History/Cookies)** — Optionally clears any combination of cache, local storage, history, or cookies immediately before an auto-reload.
- **Load Current Page vs. Start URL on Reload** — Chooses whether auto-reload returns to Start URL or refreshes whatever page is showing.
- **Skip Auto Reload if Already on Start URL** — Avoids unnecessary reloads.

## 2.5 Advanced Web Settings

- **Basic Web Automation (PLUS)** — Auto-fills form fields, toggles checkboxes, and clicks buttons/links on page load — useful for auto-login flows.
- **JavaScript Interface (PLUS)** — Exposes Fully's full JS API (`fully.*`) to loaded web pages for deep device control (see §2.13).
- **iBeacon Detection (PLUS)** — Scans for iBeacons and fires JS interface events on detection.
- **Integrated QR/Barcode Scanner (PLUS)** — Built-in barcode scanning callable from the JS interface.
- **Inject JavaScript (PLUS)** — Runs custom JS on every page load to modify third-party sites you can't edit directly.
- **Text Input / Keyboard Controls** — Enable/disable in-page text entry, force-hide the soft keyboard, and manage autofill/autocomplete behavior (with Android Autofill Manager support for Android 8+).
- **Touch, Drag, Scroll, Overscroll, Long-Tap Controls** — Fine-grained toggles for what kinds of touch interaction are permitted in the WebView.
- **Third-Party Cookies** — Allow/deny cross-site cookies.
- **Recreate Tabs on Reload** — Fully closes and reopens tabs instead of just reloading them.
- **Web Popup Window Sizing (PLUS)** — Custom width/height/position specs for popup windows.
- **Resubmit Form Data on Reload** — Resends POST data when reloading a page.
- **Localhost File Access (PLUS)** — Serves local files via `https://localhost/...` so they can be embedded in remote pages.
- **Referer / X-Forwarded-For / DNT Headers** — Adds these HTTP headers to outgoing requests.
- **Remove X-Frame/CSP/CORS Protection (PLUS)** — Strips these security headers from responses for specific URLs to allow embedding otherwise-blocked content.
- **Web Filter / Ad Blocker (PLUS)** — Loads a local hosts-blacklist file to block known ad/tracker domains.
- **Safe Browsing (experimental)** — Blocks sites Google has flagged as malicious (Android 8.1+).
- **Ignore SSL Errors** — Accepts self-signed/invalid certificates.
- **Pause WebView in Background (experimental)** — Suspends the WebView when Fully is backgrounded or the screen is off, to save resources.
- **DRM Protected Content (experimental)** — Enables protected media playback.
- **Mixed Content Mode** — Controls whether secure pages may load insecure sub-resources.
- **Restart on Unresponsiveness (PLUS, experimental)** — Auto-restarts the app after the WebView hangs for a set number of seconds.
- **Cache Mode / Clear Cache After Each Page** — Controls WebView HTTP caching behavior.
- **Resume Playback on Foreground** — Attempts to resume paused video/audio when Fully returns to the foreground.
- **Keep Screen On in Fullscreen** — Disables screensaver/screen-off while fullscreen video is playing.
- **WebView Remote Debugging** — Enables Chrome DevTools remote inspection.
- **Fake/Custom User Agent String (PLUS)** — Spoofs another browser's UA or sets an arbitrary custom UA string.
- **Default WebView Background Color** — Fallback background color when a page specifies none.
- **Graphics Acceleration Mode** — Hardware, software, or no acceleration (affects video playback and rendering issues).
- **Select WebView Implementation** — Chooses between system WebView, Chrome, or Chrome Beta as the rendering engine (Android 7+).

## 2.6 Universal Launcher

- **Select Items to Show** — Mixes installed apps, web bookmarks, and file shortcuts on one customizable launcher grid.
- **Show Launcher on Start** — Displays the launcher instead of the Start URL by default.
- **Launcher Styling** — Background color, text color, background image URL, and page scaling percentage.
- **Inject HTML/CSS/JS in Launcher** — Custom layout code for advanced launcher design.
- **Run App on Start (Foreground/Background, PLUS, experimental)** — Auto-launches selected apps in the foreground or background when Fully starts.

## 2.7 Toolbars & Appearance

- **Show/Hide Navigation, Status, Action, Tabs, Address, and Progress Bars** — Independent visibility toggles for every chrome element.
- **Custom Colors** — Background/text/icon colors configurable per bar (nav bar, status bar, action bar, tabs, address bar, progress bar).
- **Real Fullscreen (Immersive Sticky Mode)** — True edge-to-edge fullscreen on Android 4.4+.
- **Action Bar Button Set** — Toggle individual buttons: back, forward, refresh, home, print, share, barcode scan, and a custom action button with a configurable target URL.
- **Custom Action Bar Icon/Background Image** — Branding customization for the toolbar.
- **New Tab Button & New Tab URL** — Lets users open new tabs and defines what loads in them.
- **Action Bar Scaling (PLUS, experimental)** — Resize the action bar as a percentage.

## 2.8 Screensaver (PLUS)

- **Screensaver Timer** — Idle seconds before the screensaver starts; stops on interaction or motion/movement detection.
- **Screensaver Playlist** — Media files, folders, YouTube videos/playlists, or websites shown while idle.
- **Screensaver Wallpaper URL** — A background page/color shown behind or instead of the playlist.
- **Screensaver Brightness** — A separate, typically dimmer brightness level while the screensaver is active.
- **Fade In/Out Duration** — Crossfade timing between screensaver images.
- **Ignore Motion Detection During Screensaver Transitions** — Prevents false motion triggers exactly as the screensaver starts/stops.
- **Cache Images** — Caches network images used in the screensaver playlist.
- **Use Android Screen Saver (Daydream)** — Uses Android's native Daydream screensaver system instead of Fully's own.
- **Use Another App as Screensaver** — Launches a third-party app as the screensaver instead of Fully's playlist.

## 2.9 Device Management

- **Keep Screen On (+ Advanced variant)** — Prevents the display from sleeping; an "Advanced" variant addresses stubborn Android 10+ devices.
- **Screen Brightness / Force Screen Orientation (+ Globally)** — Manual brightness plus per-app or system-wide orientation locking.
- **Force Wi-Fi/Bluetooth/Hotspot Enable-Disable on App Start** — Forces these radios to a known state at launch.
- **Autostart on Boot / Bypass Lockscreen / Sleep on Power Disconnect** — Core unattended-device behaviors.
- **Set Wakelocks (CPU / Wi-Fi)** — Prevents the CPU or Wi-Fi radio from sleeping.
- **Show Battery Warning (PLUS)** — On-screen warning below a configurable battery percentage.
- **Schedule Wakeup/Sleep by Day of Week (PLUS)** — Timed hibernate/wake schedule per day or for weekends only.
- **Switch Screen Off on Idle (Screen Off Timer, PLUS)** — Screen-off after a set idle period, waking on power button, schedule, motion/movement, or API command.
- **Turn Screen Off on Proximity (PLUS)** — Uses the proximity sensor to blank the screen when something is held close.
- **Pre-configure Wi-Fi (SSID/Keyphrase/Enterprise, PLUS)** — Provisions the device onto a specific Wi-Fi network automatically, including WPA-Enterprise identity/password.
- **Reset Wi-Fi on Internet Disconnection (PLUS)** — Power-cycles Wi-Fi if the internet connection drops.
- **Redirect Audio to Earpiece (PLUS)** — Routes audio output to the phone earpiece rather than the speaker.
- **Set Initial Volume Levels (PLUS)** — Per-channel (voice/system/ring/music/alarm/etc.) starting volume levels.
- **Force Immersive Fullscreen (experimental)** — Attempts to hide system bars for other apps too (with input-blocking side effects).
- **Remove Navigation/Status Bar Globally (experimental)** — Removes system bars for all apps on older Android versions.
- **Set Device (Bluetooth) Name (experimental)** — Sets a custom Bluetooth device name.
- **Load Content from ZIP File (PLUS)** — Downloads and auto-extracts a ZIP of local content to storage, checking hourly for updates.

## 2.10 Power Settings

- **Schedule Wakeup and Sleep (PLUS)** — Per-day-of-week sleep/wake scheduling.
- **Keep Sleeping if Not Plugged** — Skips scheduled wakeup when running on battery.
- **Turn Screen On on Power Connect (experimental) / Sleep on Power Connect / Sleep on Power Disconnect** — Power-event-driven sleep/wake behavior, useful for nightly charging routines.
- **Force Screen Off If Not Powered** — Keeps the device blanked/inoperable unless plugged in (use with caution).
- **Show Battery Warning (PLUS)** — On-screen low-battery alert threshold.
- **Prevent Sleep While Screen Off** — Attempts to keep the device awake internally even with the display off, for continued motion detection/remote admin availability.

## 2.11 Kiosk Mode (PLUS)

- **Enable Kiosk Mode** — The master lockdown switch; auto-starts Fully at boot when enabled.
- **Kiosk Exit Gesture** — Choice of swipe-from-left/long-press-back, 5 fast taps, 7 fast taps (works even with another app foregrounded), or a two-corner double-tap combo.
- **Kiosk Mode PIN** — Password required to exit kiosk mode.
- **Wifi/Settings PIN (+ configurable action)** — A separate PIN that opens Wi-Fi, Bluetooth, mobile network, connection, or OTA-update settings (or a custom intent) without exposing the full kiosk PIN.
- **Disable Status Bar / Volume Buttons / Power Button / Home Button / Context Menus** — Individually blocks each of these system UI elements/hardware controls.
- **Limit Volume Level** — Caps the maximum volume percentage even if volume buttons are enabled.
- **Disable Other Apps / Advanced Kiosk Protection** — Blocks all apps not explicitly launched by Fully, and hardens against Recent Apps / power-button escape routes.
- **App Whitelist / App Blacklist** — Per-package (or per-activity/component) allow- and deny-lists, with wildcard support; blacklist takes priority.
- **Single App Mode** — Locks the entire device to one selected app, with options for remote-admin-only exit, waiting for boot completion, and pausing periodically to allow app updates.
- **Disable Notifications / Incoming Calls / Outgoing Calls** — Blocks status-bar notifications and phone calls (except emergency).
- **Disable Screenshots** — Blocks screen capture/recording of the kiosk (also blanks remote-desktop tools like AnyDesk/TeamViewer).
- **Lock Safe Mode** — Prevents booting into Android Safe Mode by activating the PIN lock screen.
- **Disable Camera** — Globally disables the camera for all apps (this also disables visual motion detection).

## 2.12 Motion & Movement Detection (PLUS)

- **Visual Motion Detection** — Front/back camera-based motion detection with adjustable sensitivity (0–100) and frame rate (1–25 fps).
- **Darkness Detection** — A separate threshold for detecting low-light/darkness conditions.
- **Camera Selection & Preview** — Choose which camera to use and optionally show a small live preview.
- **Camera API Choice (Legacy vs. CameraX, experimental)** — Selects which Android camera API to use for better device compatibility.
- **Face Detection (experimental)** — Detects faces in the camera feed, with a configurable confidence threshold, and can require faces (not just motion) to trigger detection events.
- **Acoustic Motion Detection** — Microphone-based motion detection that works in complete darkness, with its own sensitivity setting.
- **Turn Screen/Screensaver On/Off on Motion** — Ties motion events to waking the screen or exiting the screensaver.
- **Stop Web Reload on Motion** — Resets the idle-reload timer when motion is detected.
- **Turn Screen Off in Darkness** — Blanks the screen automatically when the room goes dark.
- **Device Movement Detection** — Accelerometer/compass-based detection of the device itself being moved (anti-theft).
- **Anti-Theft Alarm Sound** — Plays an alarm (optionally a custom sound file, optionally looping until the correct PIN is entered) when movement is detected.
- **iBeacon-based Anti-Theft** — Triggers movement alerts when configured iBeacons move out of a set distance threshold.

## 2.13 JavaScript Interface (PLUS)

A large `fully.*` JavaScript API exposed to trusted loaded web pages, including:
- **Device Info Getters** — IP/MAC addresses, hostname, Wi-Fi SSID/BSSID/signal, serial number, Android ID, IMEI, SIM serial, battery level, screen brightness/orientation/size, Fully/WebView/Android versions, storage space, sensor values, and data-usage counters.
- **Device Control** — Turn screen on/off, force sleep, show a toast, set brightness, enable/disable Wi-Fi/Bluetooth, show/hide the keyboard, open Wi-Fi/Bluetooth settings, vibrate, send raw hex data over TCP, show a notification, log messages, and clipboard read/write.
- **File Management** — Delete/empty/create folders, list files, read/write files, download files, unzip archives, and download-and-unzip in one step, with bound success/failure event callbacks.
- **TTS & Multimedia** — Text-to-speech (with locale/engine/queueing options), play/stop fullscreen video, set/get audio volume per stream, play/stop a sound, show a PDF, and query headset/music-active state.
- **Web Browsing Control** — Get/set the Start URL, add to home screen, share the current URL, print (including print-to-PDF), get a screenshot as base64 PNG, load stats CSV, clear cache/form-data/history/cookies/webstorage, and manage tabs (focus, close, load URL in tab, list tabs as JSON).
- **Barcode Scanner** — Trigger a QR/barcode scan with a configurable camera, timeout, beep, cancel button, and flashlight, returning the code via a callback or result URL.
- **Bluetooth Interface** — List known devices, open a serial (SPP) connection by MAC/UUID/name, send string/hex/byte data, and receive connect/data events (e.g. for driving a Bluetooth receipt printer).
- **NFC Reading** — Start/stop NFC tag scanning and receive NDEF/tag-discovered/tag-removed events.
- **Event Binding** — Subscribe to dozens of device events (screen on/off, keyboard shown/hidden, network/internet connect/disconnect, plugged/unplugged, screensaver/daydream start/stop, battery level changed, volume up/down, motion, faces detected, darkness, movement, iBeacon detected, broadcast received, QR scanned, TTS init).
- **Kiosk/App Management** — Bring Fully to foreground/background, restart/exit the app, enable/disable maintenance mode, set an overlay message, lock/unlock kiosk mode, start other apps or arbitrary intents, broadcast intents, and (rooted devices) run root/su commands.
- **Settings Management** — Read/write any of Fully's 300+ settings by key directly from JavaScript, and import a settings file by URL.
- **System Settings Access (1.55.3+)** — Get/put Android's Global/System/Secure settings values (usually requires provisioning or special permissions).

## 2.14 Remote Administration (PLUS)

- **Remote Admin Web Interface** — A browser-accessible control panel (`http://ip:2323`, HTTPS-capable with a supplied SSL cert) for viewing and changing any of Fully's 300+ settings remotely, in the local network or via VPN.
- **Remote Admin Password** — Required credential for Remote Admin, the REST interface, and Fully Cloud EMM device access.
- **File Management via Remote Admin** — List, upload, and download local files from the browser interface.
- **Screenshot / Camshot on Remote Admin** — Pull a live screenshot or (with Motion Detection enabled) a camera shot remotely.
- **Show HTML Source, Web Console, Log/Logcat** — Remote diagnostics for the currently loaded page and the app/Android log.
- **Show/Uninstall Apps, Install APK Files** — App management from the Remote Admin panel (not available if installed via Google Play).
- **Export/Import Settings (JSON)** — Backup/restore or clone the full settings set as an editable JSON file.
- **Fully App REST Interface (PLUS)** — A simple `?cmd=` query-string REST API over the same Remote Admin port, covering device info, URL loading/tab management, cache clearing, screen/screensaver/Daydream control, kiosk lock/unlock, app start/foreground/background, restart/exit, APK install/uninstall, usage-stats CSV, screenshot/camshot, TTS, audio/video playback and volume, arbitrary setting get/set (`setBooleanSetting`/`setStringSetting`), file zip/download/delete, and (on rooted/provisioned devices) shutdown/reboot/root-command execution.

## 2.15 Fully Cloud EMM

- **Cloud Device Management** — Organize, monitor, and remote-configure Fully Kiosk devices from anywhere, without port forwarding or VPN (all traffic via HTTPS to Fully's German-hosted cloud).
- **Two-Factor Login, Device Groups, Aliases** — Basic-tier account/organization management features.
- **Fast Device Provisioning** — Multiple provisioning methods (including Knox Configure support) for zero-touch deployment.
- **Google Play Managed Enterprises (Early Adopter tier)** — Silently manage apps, managed configurations, and app permissions via a connected Google Play Enterprise.
- **Remote Push Configuration (Advanced tier)** — Push a new settings configuration to one or many devices at once, including mass actions and offline-device action queuing.
- **Device Monitoring & Alerts (Advanced tier)** — Email/Pushbullet/webhook alerts on power disconnection, internet disconnection, low battery, or device movement (anti-theft).
- **Fully Cloud API (Advanced tier)** — Programmatic access to device info and remote control from external software.

## 2.16 Motion/Root/Device-Owner/Samsung KNOX Extras

- **Root Features (PLUS, rooted devices)** — Daily scheduled system restart, shutdown-on-power-disconnect timer, auto-clearing of launcher apps or the single-app after idle time, and force-killing selected apps before starting them.
- **Device Owner Settings (PLUS, provisioned devices)** — Lock Task Mode fine controls (home/recents button visibility, notifications, system info, global actions in lock-task mode), Disable Keyguard, disable volume/screen-capture/USB-storage/ADB/safe-mode-boot, OTA system-update policy (immediate/30-day postpone/nightly window), password quality/length policy, app runtime-permission default policy, arbitrary user restrictions, silent APK install from URLs with update-interval checking, enabling/disabling specific system apps, custom APN configuration, and a global HTTP proxy.
- **Samsung KNOX Settings (PLUS, Samsung devices)** — An extensive block of ~45 individual hardware/feature disables (camera, screen capture, status/nav bar, hardware buttons, USB host/MTP, safe mode, OTA, airplane mode, Bluetooth, clipboard, developer mode, Google account sync/backup, power saving, SD card write, VPN, Wi-Fi/tethering, mobile data/roaming, headphones, microphone, multi-window, task manager, Air Command/View, Edge screen, and more), plus Force Auto Start for Qualcomm/LSI chipsets and KNOX-specific APN config.

## 2.17 Other Settings

- **Daily Usage Statistics (PLUS)** — Local counters for page views, touches, reloads, screen-ons, motion detections, and device movements, viewable/exportable as CSV via Remote Admin.
- **Environment Sensors (PLUS)** — Reads any available environment sensors on the device via JS/REST API.
- **Barcode Scanner Integration (PLUS)** — Pick an external scanner app or use the built-in QR scanner; listen for keyboard-wedge input or broadcast intents from dedicated scanner hardware (e.g. Zebra DataWedge), with configurable target URL, website field insertion, and auto-submit.
- **MQTT Integration (PLUS)** — Sends device info (every 60s) and named events (screen on/off, plug state, network state, motion, darkness, movement, volume, battery level, screensaver/Daydream state, QR scan, etc.) to a configured broker, with customizable topic names.
- **Restart Fully After Crash / After Update (PLUS)** — Automatically relaunches the app after a crash or after Fully/WebView/Chrome updates (requires Kiosk Mode).
- **Run as Priority App** — Attempts to keep Android from killing Fully under memory pressure and restarts it if killed.
- **"Device in Use" Heuristics** — Suppresses idle-triggered features (screensaver, screen-off, auto-reload) while the keyboard is visible, audio is playing, another app is foregrounded, or the user keeps touching the screen/another app.
- **Regain Focus Timer / Go To Background Timer (PLUS)** — Automatically brings Fully back to the foreground after idle time, or sends it to the background after idle time.
- **Custom Text Variable** — A user-defined `$customVariable` usable in any configured URL.
- **Custom Locale (PLUS)** — Forces a specific language/locale for the app and WebView content.
- **Dark Mode Setting** — Controls how the app handles system dark-mode.
- **Video Player Engine Choice** — Android Media Player (default) vs. Media3 ExoPlayer (experimental) for fullscreen video.
- **Render in Cutout Area** — Allows content to draw into the notch/cutout area of the display.
- **Confirm Exit** — Shows a confirmation dialog before exiting the app.
- **Export / Import / Reset Settings** — Full settings-file export/import (JSON) and a one-click reset to defaults.
- **Settings Auto-Import on Start** — Automatically imports `fully-auto-settings.json`/`fully-once-settings.json` on launch, for fast fleet deployment.
- **Volume License Key** — Simplified bulk licensing entry for 10+ device deployments, with offline licensing support.

## 2.18 Companion Apps

- **Fully Single App Kiosk** — A simplified, dedicated app for quickly locking a device to one selected app.
- **Fully Video Kiosk** — A dedicated digital-signage app for playing video/image/website playlists (including YouTube) with full kiosk protection and its own playlist auto-restart triggers.
- **Fully Exam Kiosk** — A locked-down exam browser supporting Safe Exam Browser (SEB)–compatible LMS platforms (including Moodle), for secure online testing.

---

# Summary: Key Differences Relevant to a Custom Build

| Area | FreeKiosk | Fully Kiosk Browser |
|---|---|---|
| License/cost | Free, MIT open source | Closed source; core free, most advanced features require a paid PLUS license |
| Home Assistant integration | Native MQTT client with full HA auto-discovery (42 entities), plus a REST API | Official HA integration polls Fully's REST/JSON API; no native MQTT discovery (manual MQTT event publishing only) |
| Depth of settings | Smaller, modern, actively-growing settings surface (~dozens of ADB/REST/MQTT parameters) | Enormous settings surface (300+ settings across web content, kiosk lockdown, Device Owner policy, Samsung KNOX, etc.) |
| Extensibility | REST + MQTT command parity, ADB provisioning, JSON-based managed-apps config | REST/JSON-based cmd API, full JavaScript interface for in-page device control, Bluetooth/NFC/barcode JS APIs |
| Device lockdown | Device Owner, Device Admin, Accessibility Service, Lock Task Mode | Kiosk Mode, Single App Mode, Device Owner Lock Task Mode, Samsung KNOX (on Samsung hardware) |
| Cloud fleet management | Not yet shipped (roadmapped) | Fully Cloud EMM (subscription-based remote fleet management) |
