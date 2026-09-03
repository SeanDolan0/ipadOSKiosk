# IMPLEMENTATION_PLAN.md — Phase 0: build libxul for arm64-apple-ios12.0

Regenerable/disposable. If it drifts from reality, REGENERATE from `specs/*`,
don't hand-patch a confused plan. One item = one iteration.

## In progress / next up (highest first)
- [ ] Determine how to reach the Mac over the network (SSH hostname/IP from Windows)
- [ ] On the Mac: confirm Xcode + iOS SDK; install rustup + aarch64-apple-ios target
- [ ] Decide source tree: mozilla-central vs gecko-tls vs GeckoEmbed re-derivation; record in spec
- [ ] Clone the chosen source tree on the Mac
- [ ] Create `.mozconfig` from template; resolve `--enable-application` name + SDK path
- [ ] `./mach bootstrap` + `./mach configure`; capture any error verbatim
- [ ] `./mach build`; iterate on errors; capture stderr to `docs/build-logs/`
- [ ] MILESTONE: verify libxul artifact for arm64-apple-ios12.0 links into a test Xcode proj

## Done
(none yet)

## Discovered along the way
(loop appends blockers, gotchas, new sub-tasks here)
