#!/usr/bin/env python3
"""PreToolUse guard: require confirmation before editing protected source files.

These files carry invariants the project treats as non-negotiable (see CLAUDE.md):
the daemon's localhost-only bind and endpoint shapes, the app-side HA bridge, and
the pinned Theos SDK / install path. An accidental edit here breaks the device
silently-then-loudly (daemon SIGKILLed, or the .deb not shipping).

The harness passes the tool call JSON via $CLAUDE_TOOL_INPUT_FILE (or pokes the
raw JSON on stdin). Cross-check the target path; if it's protected, print a clear
message and exit 2 (block) so Claude/Lier confirm intentionally.

Usage: python guard_protected_source.py <tool-input-file-or->-
"""
import json
import os
import sys

# Paths (repo-root-relative, forward slashes) whose edits need confirmation.
# Keeping these out of the .deb / breaking the bind is the classic silent killer.
PROTECTED = {
    "Daemon/main.m",            # localhost-only HTTP bind, port 9090
    "Daemon/HTTPServer.m",      # endpoint shapes /telemetry /health /command /wake
    "Daemon/HTTPServer.h",
    "Daemon/Makefile",          # kioskd_INSTALL_PATH, TARGET pin, source list
    "App/DaemonBridge.m",       # app<->daemon IPC over 127.0.0.1:9090
    "App/TelemetryRelay.m",     # the only HA bridge (token, sensor pushes)
    "Makefile",                 # TARGET = iphone:clang:12.4:12.0 — do not override
}


def protected_paths(text: str):
    """Return protected file_paths referenced by an Edit/Write tool call body."""
    hits = []
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return hits
    tool_input = payload.get("tool_input") or payload.get("input") or {}
    path = tool_input.get("file_path")
    if path:
        norm = path.replace("\\", "/").lower()
        for p in PROTECTED:
            if norm.endswith(p.lower()):
                hits.append(p)
    return hits


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] != "-":
        with open(sys.argv[1], encoding="utf-8") as f:
            body = f.read()
    else:
        body = sys.stdin.read()
    hits = protected_paths(body)
    if not hits:
        return 0  # allow
    print("[guard_protected_source] BLOCKED: protected file(s) being modified:")
    for h in hits:
        print(f"  - {h}")
    print(
        "This file has a project invariant (localhost bind, HA bridge, pinned SDK/install path). "
        "Edit it intentionally (and review after); to proceed anyway, say so explicitly and grant the edit."
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
