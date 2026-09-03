# Overview — Gecko as the kiosk web engine

## What we are building
Replace Apple's `WKWebView` in the HA Smartboard kiosk app with a custom-built
Mozilla **Gecko** embedding for **jailbroken iPad Mini 2 (arm64, iOS 12.5.8)**.

## Why
iOS 12.5.8's WebKit is too old for ES2020+ JavaScript (optional chaining `?.`,
nullish coalescing `??`, etc.) that Home Assistant's Lovelace dashboard needs.
Gecko (built fresh) supports modern JS and renders HA correctly.

## Stack
- Mozilla **Gecko** (mozilla-central) built for `arm64-apple-ios12.0`.
- **Objective-C++** embedding layer (a `UIView` subclass owning a Gecko browsing
  context) — Phase 1.
- Theos-based app packaging (later phases, on-device with iPad).
- Build host: **macOS + Xcode** (Phase 0). No Android-only `GeckoView` reuse.

## Scope for THIS loop
**Phase 0 only**: produce a linkable `libxul` (`libxul.framework`/static lib) for
`arm64-apple-ios12.0`. The embedding layer, packaging, and JIT are later phases /
later loops. Do not attempt them here.

## Non-goals (explicitly OUT of scope)
- Android/GeckoView integration (server-side).
- Swift `async/await`/actor embed code — Phase 1 uses GCD, not this loop.
- iOS 17+ EU non-WebKit Firefox work.
- Re-architecting the kiosk daemon / MQTT / telemetry.
- Any Theos packaging or on-device install in THIS loop.
