# Gecko Rewrite Design — HA Smartboard Kiosk

## Project Context

**Current State**: Theos-based iOS app (`HASmartboard`) using `WKWebView` on jailbroken iPad Mini 2 (arm64, iOS 12.5.8). Loads Home Assistant Lovelace dashboard.

**Problem**: iOS 12.5.8 WebKit lacks ES2020+ JavaScript features (optional chaining `?.`, nullish coalescing `??`, etc.) causing HA dashboard failures.

**Goal**: Replace `WKWebView` with a custom-built Gecko (Firefox engine) embedding for iOS 12.5.8.

---

## Approach: Full Custom Gecko Build (Approach 1)

Based on Mozilla's historical `GeckoEmbed` project (2015, tmielczarek) and the Reynard Browser jailbreak port — both proved single-view Gecko embedding on iOS is possible. We're redoing this against modern Gecko and iOS 12.0 deployment target.

---

## Phased Plan

### Phase 0 — Toolchain Bring-Up (High Risk, Long Feedback Loops)

**Objective**: Produce `libxul.a` / `libxul.framework` for `arm64-apple-ios12.0`

**Steps**:
1. Clone mozilla-central (or Reynard's fork with iOS patches)
2. Configure `mozconfig` with:
   - `--target=arm64-apple-ios12.0`
   - `--enable-application=embed`
   - `--disable-jemalloc` (optional, for iOS)
   - Explicit Clang/SDK paths for Xcode with iOS 12.0 SDK
   - Rust target: `aarch64-apple-ios` (should work)
3. Run `./mach build` → iterate on build errors
4. **Milestone**: Static library/framework linkable into throwaway Xcode project

**Expected Challenges**:
- Clang/SDK version mismatches (mozilla-central expects newer Xcode)
- Rust iOS target compatibility
- JIT disabled (iOS restriction) → `--disable-jit` or similar
- Build time: hours per iteration

---

### Phase 1 — Embedding Layer (Reynard Fork → Strip Down)

**Objective**: Minimal Objective-C++ bridge: one `UIView` subclass owning a Gecko browsing context

**Source**: Reynard Browser (jailbreak Gecko port) embedding layer

**Strip List** (delete entirely):
- Tabs, history, extensions, favicons
- Private browsing, autofill, link previews
- Browser UI chrome, settings, bookmarks
- All Swift `async/await`, `Task {}`, `actor` → replace with GCD (`DispatchQueue`, completion handlers)

**Keep**:
- `UIView`/`NSView` subclass wrapping Gecko browsing context
- Minimal ObjC++ bridge: `loadURL:`, `reload`, `stop`, `goBack`, `goForward`
- Delegate callbacks: `didFinishLoad`, `didFailLoad`, `titleChanged`

**Milestone**: Compiles and links against Phase 0 `libxul`

---

### Phase 2 — Minimum Viable Kiosk View

**Objective**: Render content in the HA Smartboard app

**Steps**:
1. Static local HTML file first (isolates engine from network)
2. Point at real HA instance
3. Observe failures: JS engine differences, missing APIs, performance

**Integration Point**: Replace `WKWebView` in `KioskViewController.m:setupWebView` with Gecko view

**Milestone**: HA dashboard loads (even if broken)

---

### Phase 3 — JIT & Performance (Optional, Deferred)

**Context**: Jailbroken iOS 12 has different JIT mechanisms than TrollStore-era iOS

**Decision Point**: If interpreter-only Gecko performs acceptably for mostly-idle dashboard, skip JIT entirely.

---

## Architecture Integration

### Current App Structure (to preserve)
```
App/
├── KioskViewController.m/h    ← Main view, replaces WKWebView
├── ScreensaverView.m/h        ← Unchanged
├── SettingsViewController.m/h ← Unchanged
├── NetworkMonitor.m/h         ← Unchanged
├── DaemonBridge.m/h           ← Unchanged
├── AppDelegate.m/h            ← Unchanged
└── main.m                     ← Unchanged

Daemon/
├── kioskd                     ← Unchanged (telemetry daemon)
└── ...                        ← Unchanged
```

### New Gecko Components (to add)
```
Gecko/
├── libxul.framework           ← Phase 0 output (gitignored, built artifact)
├── GeckoView.h/.mm            ← ObjC++ UIView wrapper (Phase 1)
├── GeckoViewDelegate.h        ← Delegate protocol
├── GeckoConfig.h/.m           ← Config: user agent, cache, etc.
└── GeckoBridge.h/.mm          ← Internal: Gecko ↔ ObjC++ bridge
```

### Build System Changes
- `App/Makefile`: Link `libxul.framework`, add Gecko source files
- Root `Makefile`: Add Gecko as subproject or prebuilt dependency
- Theos `application.mk` continues to work

---

## Risk Mitigation

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Phase 0 build fails permanently | High | Fallback: Use Reynard's prebuilt libxul if compatible |
| JIT required for performance | Medium | Test interpreter-only first; dashboard is mostly static |
| Memory on iPad Mini 2 (2GB) | High | Profile early; configure Gecko cache limits |
| WebSocket/SSE for HA realtime | Medium | Test after Phase 2; may need necko config |
| Build time / iteration speed | Very High | Document every working config; cache artifacts |

---

## Documentation Strategy

All progress documented in:
- `docs/superpowers/specs/2026-09-02-gecko-rewrite-design.md` (this file)
- `docs/superpowers/plans/2026-09-02-gecko-rewrite.md` (implementation plan)
- Commit messages on `Gecko-Rewrite` branch
- Build logs saved to `docs/build-logs/`

---

## Success Criteria

1. ✅ `libxul` builds for `arm64-apple-ios12.0`
2. ✅ Minimal `GeckoView` compiles and links
3. ✅ Static HTML renders in GeckoView on device
4. ✅ HA dashboard loads (JavaScript executes)
5. ✅ Screensaver, settings, daemon IPC all still work
6. ✅ Performance acceptable on iPad Mini 2

---

## Next Actions

1. **Immediate**: Research Reynard's build scripts and mozconfig
2. **Phase 0**: Clone mozilla-central, create iOS 12.0 mozconfig, start build
3. **Parallel**: Set up Theos integration for linking libxul
