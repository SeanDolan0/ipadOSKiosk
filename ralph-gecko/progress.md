# progress.md — append-only journal (what/why per iteration)

Iterations append lines here. Do NOT rewrite history.

## Iteration 0 (seeded)
Scaffolded the ralph-gecko loop from the Phase 0 design. The loop's goal is the
libxul build for arm64-apple-ios12.0. It runs from the Mac via ralph.sh against
the Windows GPU Qwen server.

## Re-target (manual, not a loop iteration)
Re-pointed this loop OFF Gecko (per AI_AGENT_ENV.md: this branch is a sandbox; do
not point the loop at Gecko engine work, which lives on Gecko-Rewrite). New safe
target: static review & hardening of `scripts/agent/serve.ps1`. The old Gecko
prompt/spec/plan are archived in `ralph-gecko/archive-gecko-target/` (recoverable).
Also fixed two blockers: port default 8080 -> 8085 (matches serve.ps1) across
ralph.sh/opencode.json.template/docs, and the opencode invocation used an invalid
`--yolo` flag -> `opencode run --model local/qwen3.8 --auto "$(cat PROMPT.md)"`.

## Iteration 1
Item 1 (port grep): swept the whole repo for `8080`/`8085`; only
`docs/agent-research.md` had stale present-tense llama-server `:8080` refs —
fixed both lines to 8085 (matches `serve.ps1 -Port 8085`). All other 8080 hits
are either the kiosk daemon REST API (`Daemon/`, `docs/superpowers/`,
`kiosk-app-features.md` — different subsystem, out of scope) or historical
  records of the 8080->8085 move (build log at commit 340bb58, progress/spec/
  AGENTS notes) — left as-is; full list recorded in IMPLEMENTATION_PLAN.md.

## Iteration 2
Item 2 (ralph.sh port parity): verified `ralph.sh:28` `PORT="${PORT:-8085}"`
matches `serve.ps1:14` `[int]$Port = 8085,`; every live port use in ralph.sh
(preflight curl lines 31-33, generated opencode baseURL line 51) expands
`${PORT}` — no drift, verification only, no fix applied.
