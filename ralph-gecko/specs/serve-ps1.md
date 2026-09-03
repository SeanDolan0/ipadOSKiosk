# Spec — serve.ps1 static validation & hardening

`serve.ps1` starts `llama-server` serving the local Qwen model on
`0.0.0.0:<PORT>` (default **8085**) for the Mac-side Ralph loop. This Mac loop
reviews the script statically (PowerShell cannot run here).

## What to check (in order of importance)

1. **Port consistency.** `serve.ps1` defaults `-Port 8085`; the Mac reads
   `ralph-gecko/ralph.sh`, which defaults `PORT=8085`. Confirm the two never
   drift from each other. (Port was recently moved 8080 -> 8085; grep all docs
   and scripts for any stale `:8080` reference and fix.)
2. **`-ngl 99` + 12 GB VRAM feasibility.** `-ngl 99` offloads all layers. Confirm
   at 64k context with `-ctk q8_0 -ctv q8_0` the VRAM stays under ~12 GB; if
   borderline, `serve.ps1` already suggests dropping KV cache to `q4_0`. Do not
   re-tune — just verify the flag set is internally consistent and documented.
3. **Port-in-use race.** `serve.ps1` checks `Get-NetTCPConnection -LocalPort
   $Port` before launching. Confirm the check is reliable (listening state),
   and that the error message is actionable.
4. **Detached-window launch.** The script builds a command line with manual
   quoting (`$psQuote`) and launches via `Start-Process powershell -NoExit`.
   Review quoting for correct handling of paths with spaces (the model path may
   contain spaces if the repo is on a path with a space). Note any PowerShell
   injection/quoting bug.
5. **LAN IP discovery + guidance.** The script prints detected IPv4s. Confirm the
   filter drops loopback/link-local and that the printed `export WINDOWS_IP=...`
   line matches the port actually used (it writes `:8085`).
6. **Readiness loop.** `Invoke-RestMethod .../v1/models` polls for 60 s. Confirm
   it detects `$serverProcess.HasExited` and reports the exit code clearly.
7. **Docs parity.** `AI_AGENT_ENV.md` (repo root) must match the real default
   port (8085) and the real invocation. Flag and fix any mismatch.

## Output contract per iteration
- Pick exactly ONE item from `IMPLEMENTATION_PLAN.md`.
- Either apply a concrete fix to `scripts/agent/*.ps1` (or a doc), or, if you
  only verified, record the finding + the specific proof.
- Never fabricate what the script does — quote it.
- Append 1-2 lines to `progress.md`; check the item off; commit.

## Signs (hard rules for this loop)
- STATIC REVIEW ONLY. DO NOT CLAIM to have run serve.ps1.
- ONE CHECKLIST ITEM PER ITERATION.
- QUOTE THE SCRIPT, then make ONE change; don't rewrite whole files speculatively.
- KEEP PORT 8085 CONSISTENT ACROSS serve.ps1, ralph.sh, and AI_AGENT_ENV.md.
- No Gecko work, no model downloads, nothing requiring Xcode or the iPad.
