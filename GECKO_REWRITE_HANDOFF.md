# GECKO REWRITE — AUTHORITATIVE HANDOFF DOCUMENT

> **READ THIS FIRST.** If you are a new Claude Code session (any harness, any machine)
> starting work on the Gecko rewrite, this document is your entry point. It
> contains everything needed to resume Phase 0 without re-explaining the project.

**Last updated**: 2026-09-02

---

## 1. TL;DR — What this project is

The **HA Smartboard** iPad kiosk app currently renders its Home Assistant Lovelace
dashboard with `WKWebView`. iOS 12.5.8's WebKit is too old for modern ES2020+ JS
(optional chaining `?.`, nullish coalescing `??`) that HA's frontend uses, so the
dashboard breaks. **This project replaces `WKWebView` with a custom-built Mozilla
Gecko engine** compiled for `arm64-apple-ios12.0`.

- Device: iPad Mini 2 (arm64), **iOS 12.5.8**, jailbroken, Theos at /opt/theos
- App repo: this repo (`ipadOSKiosk`), branch **`Gecko-Rewrite`**
- Build for the iPad happens with **on-device Theos** (see DEPLOYMENT_GUIDE.md).

---

## 2. WHERE WE ARE (ground truth, 2026-09-02)

- Branch: `Gecko-Rewrite` (this file is committed here).
- Design spec: `docs/superpowers/specs/2026-09-02-gecko-rewrite-design.md`
- Progress log: `docs/build-logs/2026-09-02-gecko-phase0-progress.md`
- Approach: **Approach 1 — full custom Gecko build**, phased:
  - Phase 0: Toolchain bring-up -> produce `libxul` for arm64-apple-ios12.0
  - Phase 1: Embedding layer (minimal GeckoView UIView wrapper)
  - Phase 2: Minimum viable kiosk view (static HTML -> live HA)
  - Phase 3: JIT/performance (optional, defer; interpreter-only may suffice)
- Build machine: a **Mac** runs the Gecko build. Claude Code runs **directly on the
  Mac** for Phase 0. This Windows checkout is the source-of-truth repo; the Mac
  should clone/pull this same branch.

### The 1 hard blocker to confirm first thing on the Mac
- **iOS 12.0 deployment target** vs available Xcode/SDK. Modern Xcode no longer ships
  a 12.0 SDK. Confirm an Xcode + iOS SDK that can target 12.0, or set
  IPHONEOS_DEPLOYMENT_TARGET=12.0 with the newest SDK and a 12.0 min. This is the
  most likely wall.

---

## 3. PHASE 0 — Toolchain bring-up, step by step (run on the Mac)

**Goal**: `./mach build` produces a static/shared `libxul` for arm64-apple-ios12.0
that links into a throwaway Xcode project.

### 3.1 Prereqs on the Mac
- Xcode with iOS SDK, `xcode-select -p` pointing at it.
- rustup with target: `rustup target add aarch64-apple-ios`
- Python 3, ability to run `./mach`.
- Plenty of disk (~50GB+) and patience: full Gecko rebuilds are slow.

### 3.2 Source
1. Prefer a fork/already-patched Gecko with iOS support (see 3.4). Otherwise:
2. mozilla-central (hg) or GitHub mirror mozilla/gecko-dev.
3. Embedding PoC reference: hg.mozilla.org/users/tmielczarek_mozilla.com/gecko-ios/ (2015 GeckoEmbed).

### 3.3 mozconfig (template at `Gecko/mozconfig.ios12.template`)
Skeleton (adjust to chosen source):
```bash
mk_add_options MOZ_OBJDIR=@TOPSRCDIR@/../gecko-ios-objs
ac_add_options --enable-application=embed
ac_add_options --target=aarch64-apple-ios
ac_add_options --with-macos-sdk=<path-to-iOS-SDK-or-12-capable-toolchain>
ac_add_options IPHONEOS_DEPLOYMENT_TARGET=12.0
ac_add_options --disable-tests
ac_add_options --disable-debug
ac_add_options --enable-optimize
ac_add_options --disable-jit
ac_add_options --disable-jemalloc
```
> NOTE: modern mozilla-central may have renamed the `embed` application framework.
> VERIFY against the chosen source's docs; the 2015 GeckoEmbed used `embedding/ios/`.
> If `embed` is gone, use a GeckoView-style embedding or standalone xul link.

### 3.4 Reference sources (verified 2026-09-02)
- Mozilla wiki (2015 build steps): https://wiki.mozilla.org/Mobile/Gecko-iOS
- 2015 GeckoEmbed repo: https://hg.mozilla.org/users/tmielczarek_mozilla.com/gecko-ios/
- Unmaintained iOS embed prototype: https://github.com/dreamland-blog/gecko-tls (dir mobile/ios)
- Modern discussion: https://github.com/mozilla-mobile/firefox-ios/issues/19063
- GeckoView (Android, architecture reference): https://mozilla.github.io/geckoview/

### 3.5 Milestone / gate
**Do NOT proceed to Phase 1** until you have a `.a`/`.framework` that links into a
bare-bones Xcode iOS app (even one that renders nothing). That proves the toolchain.

---

## 4. PHASE 1 — Embedding layer (after Phase 0 gate)

Refactor to a **minimal single-view GeckoView**:
- Keep: UIView subclass owning a Gecko browsing context; loadURL/reload/stop/goBack/goForward; delegate callbacks (didFinishLoad, didFailLoad, titleChanged).
- Delete: tabs, history, extensions, favicons, private browsing, autofill, link previews, browser chrome, settings.
- Concurrency: replace any Swift async/await, Task{}, actor with GCD (DispatchQueue, completion handlers); one call site at a time.

Proposed layout in this repo:
```
Gecko/
├── libxul.framework            <- Phase 0 artifact (gitignored until needed)
├── mozconfig.ios12.template
├── GeckoView.h / GeckoView.mm  <- ObjC++ UIView wrapper
├── GeckoViewDelegate.h
├── GeckoConfig.h / .m
└── GeckoBridge.h / .mm         <- internal Gecko <-> ObjC++ bridge
```

---

## 5. PHASE 2 — Minimum viable kiosk view
1. Load a **static local HTML** first (proves rendering, isolates engine from network).
2. Point at real HA: http://192.168.50.150:8123 + dashboard path (from app config).
3. Only then attack networking/WebSocket/SSE issues.
4. Integration point: replace `WKWebView` in `App/KioskViewController.m:setupWebView`.

## 6. PHASE 3 — JIT & performance (optional)
Jailbroken iOS 12 JIT differs from TrollStore-era. If interpreter-only Gecko renders
a mostly-idle dashboard acceptably, skip JIT entirely.

---

## 7. Rules for working here (IMPORTANT — from the user)
1. **All work stays on branch `Gecko-Rewrite`.** Commit early and often.
2. **Document everything.** Do not let a session lose state. Update:
   - GECKO_REWRITE_HANDOFF.md (this file: TL;DR + status + how-to-resume)
   - docs/build-logs/ (append per-session progress)
   - Commit after every meaningful step.
3. Resumable by a **fresh Claude Code on a different machine/harness** — keep docs
   self-contained, clear, current.
4. Never commit real HA tokens / MQTT passwords (device plist only; schema config.plist.example).

---

## 8. Resuming from a cold start (any session)
1. `git checkout Gecko-Rewrite && git pull`.
2. Read this file, the design spec, and the latest progress log.
3. Check `git log` for the newest commits to see what changed.
4. If Phase 0 not done -> do it. If done -> follow the progress log's next steps.
5. When you finish a step, append to the progress log + commit.

---

## 9. Contact / environment facts
- iPad: root@192.168.50.53, HA at 192.168.50.150:8123. See DEPLOYMENT_GUIDE.md for
  the full device workflow (PuTTY plink/pscp, hostkey pinned there).
- Existing app architecture: see CLAUDE.md and DEPLOYMENT_GUIDE.md.
