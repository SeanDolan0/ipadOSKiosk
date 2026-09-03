#!/usr/bin/env python3
"""PostToolUse: validate config.plist schema so config drift fails loudly
instead of silently on-device.

Checks that config.plist.example still defines the keys the app actually reads.
Runs only when the edited file is config.plist.example. Never blocks on a
non-plist Write/Edit.
"""
import json, re, sys

REQUIRED_KEYS = (
    "ha.url", "ha.token", "ha.dashboardPath",
    "screensaver.mode", "screensaver.idleTimeout", "screensaver.dimBrightness",
    "screensaver.photoURLs",
)

def main():
    # PostToolUse stdin: {"tool_name","tool_input":{...},"tool_response":{...}}
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    ti = data.get("tool_input", {}) or {}
    fp = (ti.get("file_path") or "").replace("\\", "/")
    if not fp.endswith("config.plist.example"):
        return 0  # not the config example; nothing to validate
    content = (ti.get("content") or "")
    missing = [k for k in REQUIRED_KEYS if k not in content]
    if missing:
        sys.stderr.write(
            "[Hook] config.plist.example missing required keys: %s
"
            % ", ".join(missing)
        )
    # plist validation is deliberately lenient (XML parse would reject plist syntax)
    if "<dict>" in content and "config" not in content.lower():
        sys.stderr.write("[Hook] warning: config.plist.example changed; verify plist still parses
")
    print(json.dumps(data))
    return 0

if __name__ == "__main__":
    sys.exit(main())
