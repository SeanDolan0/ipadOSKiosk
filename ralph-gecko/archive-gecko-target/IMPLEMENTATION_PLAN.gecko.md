# IMPLEMENTATION_PLAN.md — Phase 0: build libxul for arm64-apple-ios12.0

Regenerable/disposable. If it drifts from reality, REGENERATE from `specs/*`,
don't hand-patch a confused plan. **One item = one tiny, verifiable step.**

> RULE: if an item would take you more than a few minutes of focused work or
> would blow past a small context window, it is TOO BIG. Split it. Each item
> must be a SINGLE small action with a clearly checkable done-state (a command
> run, a file created, a value confirmed, a decision recorded).

## In progress / next up (highest first)
- [ ] Find this PC's LAN IP (ipconfig) — needed so the Mac knows where Qwen lives
- [ ] Decide how the Mac and this PC will move files (SSH? shared drive? git push/pull?)
- [ ] Confirm the Mac is reachable from this PC (ping / ssh test, record result)
- [ ] On the Mac: check Xcode is installed (`xcode-select -p`), record version
- [ ] On the Mac: check what iOS SDKs are present (`xcodebuild -showsdks`), record
- [ ] On the Mac: confirm rustup is installed; if not, note install steps
- [ ] On the Mac: add the `aarch64-apple-ios` rust target
- [ ] Decide + RECORD in specs/phase0-libxul.md: which source tree (mozilla-central vs gecko-tls vs GeckoEmbed re-derivation)
- [ ] Pick ONE known-good source URL/hash for the chosen tree; note disk-space need
- [ ] On the Mac: clone the source tree (or download snapshot) — one command, note it takes a while
- [ ] Copy `Gecko/mozconfig.ios12.template` into the source tree as `.mozconfig`
- [ ] Resolve + document: is `--enable-application=embed` still valid in this tree? (grep the tree for it)
- [ ] Fill in the real SDK path in `.mozconfig` (`--with-macos-sdk=...`)
- [ ] Confirm `--target=aarch64-apple-ios` and `IPHONEOS_DEPLOYMENT_TARGET=12.0` are set
- [ ] Run `./mach bootstrap`; save the FULL output to docs/build-logs/
- [ ] Run `./mach configure`; save FULL output; if it fails, paste the first real error
- [ ] If configure failed: fix the single reported error, re-run configure
- [ ] Run `./mach build`; save FULL output to docs/build-logs/ (will take hours)
- [ ] If build failed: extract the FIRST actual compile/link error and save it alone
- [ ] Fix that ONE error (may be several small sub-steps), re-run the failing piece
- [ ] MILESTONE: confirm a `libxul` artifact exists for arm64-apple-ios12.0
- [ ] MILESTONE: add it to a throwaway Xcode project and confirm it links

## Done
(none yet)

## Discovered along the way
(loop appends blockers, gotchas, new sub-tasks here — split any new item small)
