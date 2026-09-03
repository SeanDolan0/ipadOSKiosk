# Gecko/ — Third-party engine work area

This directory holds everything for replacing WKWebView with a custom Gecko build.

**START HERE**: read `GECKO_REWRITE_HANDOFF.md` at the repo root. It is the
authoritative, self-contained resume point for any new Claude Code session
(any machine/harness).

Contents (planned):
- `mozconfig.ios12.template` — starting mozconfig for the Phase 0 libxul build.
- `libxul.framework` — Phase 0 artifact (gitignored until needed).
- `GeckoView.h/.mm`, `GeckoViewDelegate.h`, `GeckoConfig.h/.m`, `GeckoBridge.h/.mm`
  — Phase 1 minimal embedding layer (not yet created).

The Gecko engine source is NOT stored here. It lives on the build Mac (mozilla-central
or a fork). Docs and build logs for the port live in this repo so they are never lost.
