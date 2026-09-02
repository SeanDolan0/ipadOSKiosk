# Use Context7 for documentation lookups

Whenever a task requires looking up documentation, API details, or a library/framework/SDK/CLI usage, use the Context7 MCP tools **before** answering — even for well-known tools. Training data can be stale; Context7 returns current docs.

1. `resolve-library-id` with the library name + what to look up.
2. Pick the best match; prefer High-reputation sources and high snippet counts. Use version-specific IDs if a version matters.
3. `query-docs` with a focused, single-concept query (split multi-concept questions into separate calls).
4. Answer from the fetched docs.

## What this means for this project

- Theos / objective-c / iOS 12 SDK / WKWebView / UIKit patterns when touching `App/` or `Daemon/`.
- Home Assistant REST / MQTT APIs when working on `TelemetryRelay` or the planned MQTT migration.

## Do NOT use for

- Refactoring, debugging business logic, code review, or general programming concepts — those are direct work, not doc lookups.

## Note on private APIs

Server-side rules (CLAUDE.md) govern private iOS 12 symbols: verify them against the iOS 12 SDK or existing declarations in this repo before use. Context7 supplements that — it is not the authority for private/jailbreak APIs.

## Project-local, not global

This rule lives in this repo so every session in it reaches for Context7 automatically. It is deliberately a repo-scoped copy of the user's global `~/.claude/rules/context7.md` — if that global rule is updated, mirror the change here.
