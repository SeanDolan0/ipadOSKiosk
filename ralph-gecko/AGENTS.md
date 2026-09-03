# AGENTS.md — Gecko-for-iOS build operating manual

Durable, slow-changing knowledge. You read this fresh every iteration.
This is the ONLY place lessons can accumulate across hundreds of runs.

## Goal
Build Mozilla Gecko (`libxul`) for `arm64-apple-ios12.0` on a Mac, as the web
engine for the HA Smartboard kiosk (replacing WKWebView on iOS 12.5.8). Full
design + handoff: `GECKO_REWRITE_HANDOFF.md` and
`docs/superpowers/specs/2026-09-02-gecko-rewrite-design.md` (repo root).

## Where things live
- `Gecko/mozconfig.ios12.template` — the starting mozconfig (COPY into the
  mozilla-central tree as `.mozconfig` or set `$MOZCONFIG`, adjust SDK path).
- `Gecko/README.md` — planned layout.
- `docs/build-logs/2026-09-02-gecko-phase0-progress.md` — research so far.
- `ralph-gecko/` — THIS loop's files.

## Build environment (the single biggest constraint)
- Phase 0 is a **macOS + Xcode** build. mozilla-central needs macOS + Xcode (Clang
  from Xcode, iOS SDK) for the aarch64-apple-ios target. Windows cannot do this.
- This loop is driven from the Mac by `ralph.sh`; Qwen runs on the Windows GPU server.
- Required on the Mac:
  1. Xcode with an iOS 12-compatible SDK/toolchain.
  2. `rustup` with the `aarch64-apple-ios` target.
  3. A mozilla-central (or iOS-patched fork) checkout.
- ARM64 iOS device build; the iPad itself is NOT needed for Phase 0 — it becomes
  necessary later, for the Theos app packaging (`make install`, ldid, launchctl).

## Template kickoff (Phase 0)
```
# on the Mac, in your mozilla-central checkout:
cp /path/to/repo/Gecko/mozconfig.ios12.template .mozconfig
# edit .mozconfig: set --with-macos-sdk / --target, confirm --enable-application
export TARGET=  # do NOT override with a stale value; follow the template
./mach bootstrap
./mach configure
./mach build   # -> produces libxul for arm64-apple-ios12.0 (HOURS)
```

## Backpressure (what must hold before a commit sticks up)
- The FULL `./mach build` takes hours and often fails late. Do NOT gate commits on
  a full green build. Instead, the loop's contract is:
  - `./mach configure` succeeds, OR the configure failure is captured verbatim.
  - Every attempted build/configure run's stderr is saved to `docs/build-logs/`.
  - `IMPLEMENTATION_PLAN.md` is updated to reflect real progress.
- This is WEAKER than a normal test/build gate because Gecko's feedback loop is
  hours long. Compensate with rigorous error capture per iteration.
- If a later phase (Theos app packaging) runs, THAT build is iPad-only and runs
  `make` on-device — not from this loop.

## Signs (things Ralph keeps getting wrong — add to this list)
- FULL STEPS + VERBATIM ERRORS ONLY. NO FABRICATED SUCCESS.
- ONE ITEM PER ITERATION.
- Don't re-derive the mozconfig; START from the template and change only what a
  real configure error tells you to change.
- `--enable-application=embed` may be renamed in modern mozilla-central — VERIFY
  before building; if gone, document the current equivalent.
