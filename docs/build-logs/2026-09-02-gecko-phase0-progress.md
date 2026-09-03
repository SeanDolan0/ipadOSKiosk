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

---

## SEPARATE BRANCH: qwen-local-agent (2026-09-02)

Created branch `qwen-local-agent` forked from `Gecko-Rewrite` for an isolated
local-quantized-LLM agent sandbox.

**User request**: build an environment to run `Qwen3.8-27B-UD-Q2_K_XL.gguf`
(Unsloth, 9.83 GB Q2_K_XL) on a Ralph loop, using llama.cpp runtime with
opencode (which gives tools + MCP) as the harness. Kept on its own branch so
the smaller/riskier model can't corrupt Gecko work it can't be monitored for.

**What was built** (committed 340bb58, branch qwen-local-agent):
- scripts/agent/download-model.ps1 (resumable HF fetch of the 9.83 GB GGUF)
- scripts/agent/serve.ps1 (llama-server on 127.0.0.1:8080, flags validated)
- scripts/agent/start-opencode.ps1 (verify server + launch opencode)
- AI_AGENT_ENV.md (authoritative handoff)
- docs/ralph-loop-usage.md (bounded ralph-loop patterns)
- .gitignore: /models/ (9.83 GB GGUF never committed)

**Environment facts verified**: 32GB RAM (fits model + 32k ctx), no discrete GPU
(CPU-only, serve uses -ngl 0), llama-server installed via WinGet build 10507,
opencode global config ALREADY has provider local/qwen3.8 -> http://localhost:8080/v1.

**Not done (needs user)**: the 9.83 GB model download + first-run sanity check.
Run: .\scripts\agent\download-model.ps1 then .\scripts\agent\serve.ps1
then .\scripts\agent\start-opencode.ps1
