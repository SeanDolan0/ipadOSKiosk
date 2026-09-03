# AI_AGENT_ENV — Local Quantized Qwen 27B Agent Environment

> **READ THIS FIRST.** Authoritative resume point for this branch
> (`qwen-local-agent`). Any Claude Code / opencode / Pi session picks up here.

**Branch purpose** (per user): run a **local, quantized LLM agent** isolated on its
own branch so a smaller/riskier model cannot corrupt the Gecko rewrite work on
`Gecko-Rewrite`. This branch is a fork of `Gecko-Rewrite` (the Gecko handoff docs
are present, but the engine work lives on `Gecko-Rewrite`; treat this branch as
experimental sandbox only).

## 1. TL;DR — what runs here

| Piece | What | Status |
|---|---|---|
| Model | `unsloth/Qwen3.8-27B-GGUF` → `Qwen3.8-27B-UD-Q2_K_XL.gguf` (9.83 GB, Q2_K_XL Unsloth Dynamic) | NOT yet downloaded |
| Runtime | **llama.cpp** `llama-server` (installed via WinGet, v0.1.2-dev build 10507) | installed |
| Harness | **opencode** (gives tools: read/write/edit/bash + MCP) | installed, config exists |
| Loop | **Ralph loop** plugin/command | see docs/ralph-loop-usage.md |

The whole flow: `download-model` → `serve` (llama-server on :8080) → `start-opencode`
(opencode with provider `local/qwen3.8` → that OpenAI-compat endpoint).

## 2. One-time setup

```powershell
# 1) Get the model (~9.83 GB). Run from repo root.
powershell -ExecutionPolicy Bypass -File .\scripts\agent\download-model.ps1

# 2) Start the server (opens llama-server in its own window)
powershell -ExecutionPolicy Bypass -File .\scripts\agent\serve.ps1
```

Then open a second terminal:
```powershell
# 3) Launch the harness against the local model
powershell -ExecutionPolicy Bypass -File .\scripts\agent\start-opencode.ps1
```

## 3. How the pieces connect (verified 2026-09-02)

- **opencode global config** `~/.config/opencode/opencode.json` already defines:
  - `provider.local` → `{ baseURL: http://localhost:8080/v1, apiKey: sk-dummy }`
  - `provider.local.models.qwen3.8` and default `model: local/qwen3.8`
  - MCP servers: **context7** (docs), **wiremcp** (custom; `C:\Users\sedol\Documents\WireMCP\index.js`)
  - Plugins: `ecc-universal`, `superpowers@git+...`
- **llama-server** (llama.cpp) exposes an OpenAI-compatible API at
  `http://127.0.0.1:8080/v1` — that is exactly the baseURL the opencode provider hits.
- So the user does NOT need to write new provider config; the harness + config exist.
  This branch documents and scripts the missing "download + serve" glue and adds docs.

## 4. Hardware envelope (this Windows box, verified)
- RAM: **32 GB** — fits a ~9.8 GB Q2 K_XL model with room for a 32k context.
- GPU: **no non-integrated GPU detected via wmic** → the serve script sets `-ngl 0`
  (CPU inference). Expected throughput: a few tokens/sec for 27B Q2 on CPU. Fine for
  agentic tasks; not fast. If a discrete GPU becomes available, bump `-ngl 99`.
- Disk: ~52 GB free — enough for the 9.8 GB model + llama.cpp + opencode (~1 GB sober).

## 5. Files in this branch
```
scripts/agent/
  download-model.ps1     # fetch GGUF from Hugging Face (resumable curl)
  serve.ps1              # llama-server on 127.0.0.1:8080 with the model
  start-opencode.ps1     # verify server + launch opencode in repo root
docs/ralph-loop-usage.md # how to run this on the Ralph loop
AI_AGENT_ENV.md          # this file
models/                  # (gitignored) where the 9.83 GB GGUF lands
```

## 6. Status / next steps
- [ ] Download the model (script provided).
- [ ] First run: serve + verify `/v1/models`, then opencode chat sanity check.
- [ ] Decide harness: opencode (configured) vs Pi (Pi infra exists in ~/.claude/daemon).
- [ ] Document a concrete Ralph-loop prompt/task on this env.

## 7. Rules (user requirements)
- This branch is experimental sandbox. Do NOT merge experiment cruft back into
  `Gecko-Rewrite` or `master`.
- Commit meaningful steps; keep this doc + docs current so any session resumes cold.
- The 9.83 GB `.gguf` is gitignored and MUST never be committed.
