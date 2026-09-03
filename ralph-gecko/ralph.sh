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

MAX_ITERATIONS="${1:-50}"
LOG_DIR="logs"
mkdir -p "$LOG_DIR"

# Qwen lives on the Windows box. Point opencode at it, not the Mac's own localhost.
WINDOWS_IP="${WINDOWS_IP:?Set WINDOWS_IP to this PC's LAN IP, e.g. WINDOWS_IP=192.168.1.50}"
export OPENCODE_LLAMACPP_BASE_URL="http://${WINDOWS_IP}:8080/v1"

echo "WINDOWS_IP=$WINDOWS_IP"
echo "Ensure llama-server is running on Windows:  .\\scripts\\agent\\serve.ps1  (GPU, 0.0.0.0:8080)"

for i in $(seq 1 "$MAX_ITERATIONS"); do
  echo "=== Ralph iteration $i/$MAX_ITERATIONS ==="

  # Fresh context every iteration: pipe PROMPT.md into a NEW headless opencode run.
  if command -v opencode >/dev/null 2>&1; then
    cat PROMPT.md | opencode run --model local/qwen3.8 -p \
      2>&1 | tee "$LOG_DIR/iteration-$i.log"
  else
    echo "opencode not found on this machine — cannot run the loop headless. Install it or set an alias."
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
