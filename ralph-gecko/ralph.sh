#!/usr/bin/env bash
# Ralph loop for the serve.ps1 sandbox task (safe target on qwen-local-agent).
# Drives opencode HEADLESS against the local Qwen server on Windows.
#
# Usage:
#   WINDOWS_IP=192.168.x.y  # this PC's LAN IP (llama-server bound to 0.0.0.0:8085)
#   PORT=8085                # optional, must match serve.ps1 (default 8085)
#   ./ralph.sh              # runs CONTINUOUSLY (while true) until the plan is exhausted
#
# Driven from the MAC; Qwen runs on the Windows GPU. The loop's task is to
# statically validate & harden scripts/agent/serve.ps1 (it runs on Windows, so
# this Mac-side loop reviews the script, does not execute it). See PROMPT.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOG_DIR="logs"
mkdir -p "$LOG_DIR"

# Qwen lives on the Windows box.
WINDOWS_IP="${WINDOWS_IP:?Set WINDOWS_IP to the Windows host LAN IP, e.g. WINDOWS_IP=192.168.50.177}"

echo "WINDOWS_IP=$WINDOWS_IP"

# Port must match serve.ps1 (default 8085) on the Windows host.
PORT="${PORT:-8085}"

# 1. Pre-flight health check
echo "Checking connection to llama-server at http://${WINDOWS_IP}:${PORT}/v1/models ..."
if ! curl -s -f -m 5 "http://${WINDOWS_IP}:${PORT}/v1/models" >/dev/null; then
  echo "ERROR: Cannot reach llama-server at http://${WINDOWS_IP}:${PORT}/v1"
  echo "Troubleshooting:"
  echo '  1. On Windows, verify llama-server is running via: .\scripts\agent\serve.ps1'
  echo '     (default port 8085; override here with PORT=<n> if you set a different one)'
  echo '  2. On Windows, ensure Firewall allows the port:'
  echo '     netsh advfirewall firewall add rule name="llama-server" dir=in action=allow protocol=TCP localport=<port>'
  echo "  3. Verify WINDOWS_IP matches the Windows host actual LAN IP."
  exit 1
fi
echo "Connection OK: llama-server is reachable."

# 2. Configure local opencode provider pointing to the Windows llama-server
cat <<EOF > opencode.json
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "local": {
      "options": {
        "baseURL": "http://${WINDOWS_IP}:${PORT}/v1",
        "apiKey": "sk-dummy"
      },
      "models": {
        "qwen3.8": {}
      }
    }
  },
  "model": "local/qwen3.8"
}
EOF

i=0
while :; do
  i=$((i+1))
  echo "=== Ralph iteration $i ==="

  # Fresh context every iteration: pass PROMPT.md as the message into a NEW
  # headless opencode run. --auto auto-approves permissions for unattended use
  # (there is no --yolo flag on opencode; that's Claude Code only).
  if command -v opencode >/dev/null 2>&1; then
    opencode run --model local/qwen3.8 --auto "$(cat PROMPT.md)" \
      2>&1 | tee "$LOG_DIR/iteration-$i.log"
  else
    echo "opencode not found on this machine — cannot run the loop headless. Install it: npm i -g opencode-ai"
    exit 1
  fi

  # Stop condition: no unchecked items left in the plan means the loop is done.
  # Runs continuously (while true) until the plan is exhausted.
  if ! grep -q '^- \[ \]' IMPLEMENTATION_PLAN.md; then
    echo "No unchecked items remain in the plan — loop is done after $i iterations."
    break
  fi

  echo "Iteration $i complete. Next up: $(grep -m1 '^- \[ \]' IMPLEMENTATION_PLAN.md)"
done

echo "Ralph loop finished after $i iterations (plan exhausted)."
echo "Review: $LOG_DIR/ for per-iteration logs, progress.md, and git log."
