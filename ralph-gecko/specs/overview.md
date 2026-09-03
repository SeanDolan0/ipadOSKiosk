# Overview — serve.ps1 hardening sandbox

## What we are doing
Iteratively validate and harden the Windows-side `scripts/agent/serve.ps1`
(and its sibling `scripts/agent/serve.ps1`'s helper docs) so it starts clean and
serves the local Qwen model correctly. This is a self-contained, verifiable
task chosen as a **safe sandbox target** for the `qwen-local-agent` branch —
see `AI_AGENT_ENV.md` (repo root) which states this branch is experimental and
must NOT be used for Gecko engine work (that lives on `Gecko-Rewrite`).

## Why the loop targets this
- The 27B Q2 model is memory/CPU-bound; a bounded Ralph loop lets it self-iterate
  on one task without being babysat.
- `serve.ps1` runs on the **Windows** host (PowerShell). This Mac-side loop cannot
  execute it, so the agent does **static review**: it reads the script, spots
  bugs/edge cases, and proposes concrete fixes.
- Every finding/fix is written to disk (spec/plan/progress + git), so a memory-less
  iteration can build on the last one.

## Stack / language
- `scripts/agent/serve.ps1` and `scripts/agent/download-model.ps1` — PowerShell
  (`#Requires`-less scripts run via `powershell -ExecutionPolicy Bypass -File`).
- `scripts/agent/start-opencode.ps1` — optional Windows launcher.
- Backing doc: `AI_AGENT_ENV.md` (repo root) is the authoritative environment record.

## Scope for THIS loop
Only static review + documentation improvements of `scripts/agent/*`. Do not
touch the kiosk app, the daemon, MQTT, or Gecko. Do not write or run anything
that requires Xcode, on-device builds, or the iPad.

## Non-goals (explicitly OUT of scope)
- Running or executing `serve.ps1` (it is a Windows-only PowerShell script).
- Downloading the 9.83 GB model, or any GPU/VRAM tuning (already settled — see
  `AI_AGENT_ENV.md` Hardware envelope).
- Gecko / libxul / WKWebView replacement work (see archived
  `ralph-gecko/archive-gecko-target/`).
- Any change to the kiosk app, daemon, MQTT, or telemetry.
