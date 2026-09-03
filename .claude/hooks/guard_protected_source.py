#!/usr/bin/env python3
"""PreToolUse guard: block Edit/Write to protected source unless confirmed.

Reads the Claude tool-use JSON from stdin. Passes writes THROUGH (exit 0)
when the target is not protected, or when the user has explicitly provided a
confirmation reason in the tool_input (note: text containing "confirmed").

Protected paths (kept in sync with CLAUDE.md conventions):
  - localhost-only bind (Daemon HTTP server)      -> any file under Daemon/
  - HA bridge / telemetry relay                     -> App/KioskViewController.m, App/TelemetryRelay.*
  - pinned SDK / install path                     -> Makefile, Daemon/Makefile, control, *.plist
Users can override by including a note that mentions "confirmed" (e.g. when
Claude reports the change the user already approved).
"""
import json, os, sys

PROTECT_PARTIALS = (
    # localhost-only bind lives in the daemon
    "Daemon/",
    # HA bridge + telemetry relay
    "App/KioskViewController",
    "App/TelemetryRelay",
    # pinned SDK/install path + packaging
    "Makefile",
    "Daemon/Makefile",
    "control",
)

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        # If we can't parse stdin, do not silently block writes.
        return 0
    tool_input = data.get("tool_input", {}) or {}
    note = (tool_input.get("note") or tool_input.get("reason") or "")
    confirmed = "confirmed" in note.lower()

    file_path = tool_input.get("file_path", "") or ""
    rel = file_path.replace("\\", "/").replace("\\", "/")
    rel = rel.replace("\\", "/")
    base = rel.rsplit("/", 1)[-1]
    protected = any(
        (p in rel) or (p in base)
        for p in PROTECT_PARTIALS
    )
    if protected and not confirmed:
        sys.stderr.write(
            "[Hook] BLOCKED: %s is protected source (localhost bind / HA bridge / "
            "pinned path). Re-run with a note mentioning 'confirmed' to proceed.
"
            % file_path
        )
        return 2  # block
    # passthrough
    print(json.dumps(data))
    return 0

if __name__ == "__main__":
    sys.exit(main())
