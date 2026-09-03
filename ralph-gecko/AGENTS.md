# AGENTS.md — serve.ps1 hardening loop operating manual

Durable, slow-changing knowledge. You read this fresh every iteration.
This is the ONLY place lessons can accumulate across runs.

## Goal
Statically review and harden `scripts/agent/serve.ps1` (the Windows-side launcher
for the local Qwen model) so it starts clean and serves the Mac Ralph loop
correctly, with ports/health-checks consistent across all docs. This is a safe
sandbox task on the `qwen-local-agent` branch (see `AI_AGENT_ENV.md`).

## Where things live
- `scripts/agent/serve.ps1` — the main script under review (Windows/PowerShell).
- `scripts/agent/download-model.ps1` — fetches the GGUF (not under review unless relevant).
- `scripts/agent/start-opencode.ps1` — optional Windows launcher (verify parity only).
- `AI_AGENT_ENV.md` (repo root) — authoritative environment record; must match port 8085.
- `ralph-gecko/` — THIS loop's files (PROMPT/AGENTS/plan/specs/progress).
- `ralph-gecko/archive-gecko-target/` — archived PRIOR Gecko target (do not touch).

## Key facts (verify, don't re-derive)
- llama-server/model port default is **8085** (`serve.ps1 -Port` param, default
  8085). `ralph.sh` default `PORT=8085` must match. It was recently moved from 8080.
- Model packs into GPU: `-dev Vulkan1` (NVIDIA RTX 5070 Ti 12 GB), `-ngl 99`,
  64k ctx (`-c 65536`), quantized KV cache `-ctk q8_0 -ctv q8_0`.
- Health check the Mac uses: `http://${WINDOWS_IP}:${PORT}/v1/models`.
- `serve.ps1` launches llama-server detached via `Start-Process` + `-NoExit`, with
  manual command-line quoting (`$psQuote`).

## Backpressure (what must hold before a commit sticks up)
- This Mac loop CANNOT run `serve.ps1` (Windows PowerShell). There is no
  executable gate. Instead:
  - Every claimed finding quotes the actual lines of the script it judges.
  - Every "fixed" item must be a complete, correct edit to `scripts/agent/*.ps1`
    or a doc — no stubs.
  - `IMPLEMENTATION_PLAN.md` is kept truthful (checked only when actually done).
- This is WEAKER than a test/build gate because we cannot execute the target here.
  Compensate with rigorous, verbatim quoting and small single-item steps.

## Signs (things the loop keeps getting wrong — add to this list)
- STATIC REVIEW ONLY. NEVER CLAIM to have run serve.ps1 / llama-server.
- ONE ITEM PER ITERATION.
- QUOTE THE SCRIPT, then make ONE change. Don't rewrite whole files speculatively.
- KEEP PORT 8085 CONSISTENT across serve.ps1, ralph.sh, AI_AGENT_ENV.md.
- NO Gecko work, NO model downloads, NO Xcode/iPad/on-device work — this branch is
  a sandbox for the local-Qwen loop only.
