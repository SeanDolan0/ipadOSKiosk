# Phase 0 — Build libxul for arm64-apple-ios12.0

## Objective (definition of done)
Produce a static library / framework linkable into a throwaway Xcode project for
the `arm64-apple-ios12.0` target. This is the foundation every later phase builds on.

## Provenance / precedent
- **GeckoEmbed (2015)**: Mozilla's minimal single-view iOS Gecko embedding.
  - repo: hg.mozilla.org/users/tmielczarek_mozilla.com/gecko-ios/
  - wiki: https://wiki.mozilla.org/Mobile/Gecko-iOS
  - `--enable-application=embed` + `embedding/ios/GeckoEmbed/GeckoEmbed.xcodeproj`
  - two mozconfigs: `iphone-simulator-mozconfig`, `iphone-device-debug-mozconfig`
  - Firefox 35-44 era — code stale, but PROVES the architecture is achievable.
- **Modern status**: no maintained iOS Gecko embedding exists (GeckoView is
  Android-only). dreamland-blog/gecko-tls is an unmaintained prototype.
  See firefox-ios issue #19063.

## Build requirements (MUST all be satisfied)
1. macOS with Xcode (iOS 12-compatible toolchain).
2. `rustup` target: `aarch64-apple-ios`.
3. A Gecko source checkout (mozilla-central or an iOS-patched fork with the embed
   framework present).
4. A valid mozconfig. Start from `Gecko/mozconfig.ios12.template`. Key options:
   - `--target=aarch64-apple-ios`
   - `--with-macos-sdk=<ios-sdk-or-12-capable-toolchain>`
   - `IPHONEOS_DEPLOYMENT_TARGET=12.0`
   - `--enable-application=embed` (VERIFY name; may be renamed in modern tree)
   - `--disable-tests --disable-debug --enable-optimize`
   - `--disable-jit --disable-jemalloc` (iOS has no JIT; kiosk needs no jemalloc)

## Ordered task list (seeded; the loop advances one at a time)
- [ ] Determine how to reach the Mac over the network from this Windows box
      (SSH hostname/IP) so artifacts/docs can move between them.
- [ ] On the Mac: confirm Xcode + iOS SDK version; install `rustup` and the
      `aarch64-apple-ios` target.
- [ ] Decide the source tree: fork mozilla-central vs gecko-tls vs re-derive from
      GeckoEmbed. Record the choice in this spec.
- [ ] Clone the chosen source tree on the Mac.
- [ ] Create `.mozconfig` from the template; resolve the `--enable-application`
      name question and the SDK path.
- [ ] `./mach bootstrap` then `./mach configure` — capture any error verbatim.
- [ ] `./mach build` — iterate on errors; capture stderr to `docs/build-logs/`.
- [ ] MILESTONE: verify a `libxul` artifact exists for arm64-apple-ios12.0
      and is linkable into a throwaway Xcode project.

## Key risks
| Risk | Mitigation |
|------|------------|
| embed framework renamed on modern tree | verify against source before building; document equivalent |
| Xcode/SDK version mismatch | pin an iOS 12-capable SDK; note exact version used |
| Build time: hours per iteration | capture errors rigorously; one task per iteration |
| JIT unavailable on iOS | interpreter-only for now; Phase 3 decides if needed |
| iPad Mini 2 has 2GB RAM | plan Gecko cache/memory limits in a later phase |
