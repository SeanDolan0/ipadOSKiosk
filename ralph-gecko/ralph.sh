#!/usr/bin/env bash
# Ralph loop for the Gecko-for-iOS Phase 0 build.
# Drives opencode HEADLESS against the local Qwen server on Windows.
#
# Usage:
#   WINDOWS_IP=192.168.x.y  # this PC's LAN IP (llama-server bound to 0.0.0.0:8080)
#   ./ralph.sh [MAX_ITERATIONS]     # default 50
#
# Runs on the MAC (Xcode needed for the Gecko build); Qwen runs on the Windows GPU.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MAX_ITERATIONS="${1:-50}"
LOG_DIR="logs"
mkdir -p "$LOG_DIR"

# Qwen lives on the Windows box.
WINDOWS_IP="${WINDOWS_IP:?Set WINDOWS_IP to the Windows host LAN IP, e.g. WINDOWS_IP=192.168.50.177}"

echo "WINDOWS_IP=$WINDOWS_IP"

# 1. Pre-flight health check
echo "Checking connection to llama-server at http://${WINDOWS_IP}:8080/v1/models ..."
if ! curl -s -f -m 5 "http://${WINDOWS_IP}:8080/v1/models" >/dev/null; then
  echo "ERROR: Cannot reach llama-server at http://${WINDOWS_IP}:8080/v1"
  echo "Troubleshooting:"
  echo '  1. On Windows, verify llama-server is running via: .\scripts\agent\serve.ps1'
  echo '  2. On Windows, ensure Firewall allows port 8080:'
  echo '     netsh advfirewall firewall add rule name="llama-server 8080" dir=in action=allow protocol=TCP localport=8080'
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
        "baseURL": "http://${WINDOWS_IP}:8080/v1",
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

for i in $(seq 1 "$MAX_ITERATIONS"); do
  echo "=== Ralph iteration $i/$MAX_ITERATIONS ==="

  # Fresh context every iteration: pipe PROMPT.md into a NEW headless opencode run.
  # --yolo bypasses the need for user confirmation in unattended headless execution.
  if command -v opencode >/dev/null 2>&1; then
    cat PROMPT.md | opencode run --model local/qwen3.8 --yolo \
      2>&1 | tee "$LOG_DIR/iteration-$i.log"
  else
    echo "opencode not found on this machine — cannot run the loop headless. Install it: npm i -g opencode-ai"
    exit 1
  fi

  # Backpressure (weak for this loop — the Gecko build is hours long; see AGENTS.md).
  # No unchecked items left means the whole plan is done.
  if ! grep -q '^- \[ \]' IMPLEMENTATION_PLAN.md; then
    echo "No unchecked items remain in the plan — Phase 0 loop is done."
    break
  fi

  echo "Iteration $i complete. Next up: $(grep -m1 '^- \[ \]' IMPLEMENTATION_PLAN.md)"
done

echo "Ralph loop finished after $MAX_ITERATIONS iterations (or plan exhausted)."
echo "Review: $LOG_DIR/ for per-iteration logs, progress.md, and git log."
