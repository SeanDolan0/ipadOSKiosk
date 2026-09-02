#!/usr/bin/env python3
"""Validate config.plist.example against the schema the app/daemon read at startup.

Run as a PostToolUse hook whenever config.plist.example (or any config plist)
is written. Exits 1 on a malformed plist or a missing top-level key — the hook
will surface this to Claude so a schema-drift edit is caught before it fails
silently on-device.

Usage: python validate_config_plist.py <path-to-plist-xml>
"""
import json
import plistlib
import sys


def tool_path_from_stdin() -> str | None:
    """Extract tool_input.file_path from the hook JSON Claude Code pipes on stdin."""
    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, AttributeError):
        return None
    tool_input = payload.get("tool_input") or payload.get("input") or {}
    return tool_input.get("file_path")


def main(path: str) -> int:
    try:
        with open(path, "rb") as f:
            data = plistlib.load(f)
    except Exception as e:  # noqa: BLE001 - report any parse failure
        print(f"[validate_config_plist] PARSE FAILURE in {path}: {e}")
        return 1

    if not isinstance(data, dict):
        print(f"[validate_config_plist] {path}: expected top-level <dict>, got {type(data).__name__}")
        return 1

    # Keys the running code actually reads (see KioskViewController loadHAConfig,
    # showScreensaver, and the planned settings/MQTT work). Missing ha/screensaver
    # is a red flag; warn, don't hard-fail (both blocks can legitimately be absent
    # on first boot, with code defaults taking over).
    problems = []
    if "ha" in data:
        ha = data["ha"]
        if not isinstance(ha, dict):
            problems.append("'ha' is not a dict")
        else:
            for k in ("url", "token", "dashboardPath"):
                if k in ha and not isinstance(ha[k], str):
                    problems.append(f"'ha.{k}' is not a string")
    else:
        print("[validate_config_plist] note: no 'ha' block — code defaults will be used")
    if "screensaver" in data:
        ss = data["screensaver"]
        if not isinstance(ss, dict):
            problems.append("'screensaver' is not a dict")
        elif "mode" in ss and ss["mode"] not in ("clock", "photo"):
            problems.append(f"'screensaver.mode' is '{ss['mode']}', expected 'clock' or 'photo'")

    if problems:
        for p in problems:
            print(f"[validate_config_plist] SCHEMA: {path}: {p}")
        return 1
    print(f"[validate_config_plist] OK: {path}")
    return 0


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) == 2 else tool_path_from_stdin()
    if not path:
        print("usage: validate_config_plist.py <path-to-plist-xml>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(path))
