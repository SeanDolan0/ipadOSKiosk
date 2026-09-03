# Gecko Rewrite — Phase 0 Progress Log

**Started**: 2026-09-02
**Branch**: `Gecko-Rewrite`
**Device**: iPad Mini 2 (arm64, iOS 12.5.8), jailbroken, Theos at /opt/theos

---

## Session Log

### 2026-09-02 — Research Findings

**Objective**: Confirm feasibility of building modern Gecko for iOS 12.5.8 on this machine.

#### Key Findings

1. **Historical precedent confirmed**:
   - Mozilla built `GeckoEmbed` (2015) — a minimal single-view Gecko embedding for iOS.
     Source: hg.mozilla.org/users/tmielczarek_mozilla.com/gecko-ios/
     Wiki: https://wiki.mozilla.org/Mobile/Gecko-iOS
   - `--enable-application=embed` + `embedding/ios/GeckoEmbed/GeckoEmbed.xcodeproj`
   - Two mozconfigs: `iphone-simulator-mozconfig`, `iphone-device-debug-mozconfig`
   - Last updated 2015 (Firefox 35-44 era) — code is stale but proves architecture.

2. **Modern Gecko iOS status**:
   - Mozilla only now (iOS 17.4+ EU) working on non-WebKit Firefox.
   - `GeckoView` is Android-only; **no maintained iOS embedding exists**.
   - dreamland-blog/gecko-tls (GitHub) is an unmaintained prototype (0 stars/forks).

3. **Reynard Browser** (jailbreak Gecko port): onejailbreak.com article exists; GitHub source not
   locatable via nickcano/reynard (404). Status uncertain.

4. **CRITICAL — BUILD ENVIRONMENT CONSTRAINT**:
   - Current machine: **Windows 11** (MINGW64), WSL Ubuntu 22.04 available, **NO macOS / Xcode**.
   - mozilla-central build for iOS is tightly coupled to **macOS + Xcode** for the iOS target.
   - Rust aarch64-apple-ios can cross-compile from Linux, but C/C++ (Clang from Xcode, iOS SDK) 
     realistically requires macOS.
   - **This is the single biggest blocker to Phase 0.**

#### Open Questions / Decisions Needed
1. Do we have access to a Mac for the Gecko build (then copy artifacts to Windows)?
2. If no Mac: WSL-based iOS cross-compilation (very high risk).
3. Source of truth for embed: fork mozilla-central vs gecko-tls vs GeckoEmbed re-derivation.

#### Precedent Sources (verified)
- https://wiki.mozilla.org/Mobile/Gecko-iOS (2015 GeckoEmbed build steps)
- https://hg.mozilla.org/users/tmielczarek_mozilla.com/gecko-ios/ (2015 repo)
- https://github.com/dreamland-blog/gecko-tls (unmaintained prototype)
- https://github.com/mozilla-mobile/firefox-ios/issues/19063 (modern Gecko-on-iOS)

---

## Status: BLOCKED on build-environment decision
Phase 0 (build libxul) cannot proceed on Windows-only. Need decision on Mac availability.

---

## UPDATE (same session) — Decision recorded

**User confirmed: a Mac IS available** for the Gecko/libxul build. Artifacts will be built on the Mac,
then copied to Windows for Theos integration (or the whole Theos build could also move to the Mac).

### Next steps (Phase 0)
1. Determine how to reach the Mac (SSH hostname/IP from this Windows box).
2. On the Mac: install Xcode + iOS 12.0 SDK compatible toolchain, rustup with aarch64-apple-ios.
3. Clone mozilla-central (or gecko-tls fork with iOS patches).
4. Create iOS 12.0 mozconfig, run ./mach build -> libxul.
5. Copy artifacts back to this repo under Gecko/ (gitignored until needed).
