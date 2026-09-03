# HARNESS RESEARCH — Pi vs opencode for the local Qwen 27B agent (REVISED)

**Branch**: `qwen-local-agent`. Updated 2026-09-02 after reading
`ralph-loop-setup-guide.md` — this doc supersedes the earlier draft.

> **KEY CORRECTION**: Ralph is NOT the `ralph-loop` Claude plugin. It is a
> **no-plugin pattern**: a bash `while :; do` loop that pipes a fresh PROMPT
> into a **headless, non-interactive** agent invocation, each iteration
> starting with a completely fresh context window. The filesystem (git history
> + markdown state files) is the memory. The loop is harness-agnostic —
> `ralph.sh` just swaps which CLI it drives (`claude -p`, `opencode run`, etc.).

## Architecture (final)
- **Windows (this PC, NVIDIA CUDA GPU)**: `llama-server` serves the Qwen
  27B Q2_K_XL on `0.0.0.0:8085` — no auth (user chose LAN-only, no API key).
  All layers GPU offloaded (`-ngl 99`), ~64k context (`-c 65536`).
- **Mac (client)**: `ralph.sh` loops `opencode run -p` (headless) against
   `http://<WINDOWS_IP>:8085/v1`. The Mac's repo holds the Ralph files
  (PROMPT.md, AGENTS.md, specs/, IMPLEMENTATION_PLAN.md, progress.md, ralph.sh).

## Pi vs opencode (brief)

| | Pi | opencode |
|---|---|---|
| Fixed overhead | ~1,000 tokens | ~6,900 tokens |
| Tools | 4 core (read/write/edit/bash), + TS extensions | full: MCP, subagents, permissions, LSP |
| Headless run mode | confirm `pi` TUI only vs non-interactive | yes: `opencode run` |
| Local model | Ollama/vLLM/llama.cpp | llama.cpp via BYOK (`llamacpp/*`) |
| Config on Mac | minimal | global `opencode.json` already points at local qwen |

## Decision
Use **opencode** via `opencode run` (headless) in `ralph.sh`. Reasons:
1. User explicitly wants "extra tools" → opencode's MCP + subagents are the
   fullest tool set. Pi would require hand-building tools via TS extensions.
2. opencode already has a global config wired to the local qwen provider.
3. `opencode run` gives the non-interactive headless mode Ralph needs.
The 6.9k overhead is acceptable at 64k ctx; the instruction set (PROMPT.md)
should stay lean to compensate.

Pi remains a fallback if opencode's tool-calling on the quantized model proves
unreliable — it is leaner for small-context quantized models.

## Recommended Ralph repo structure (harness-agnostic, from the setup guide)
```
ralph-kiosk-agent/          # e.g. a subdir or the branch working tree
├── PROMPT.md               # the ONE file piped to the agent every iteration
├── AGENTS.md               # build/test commands, conventions, gotchas, "signs"
├── IMPLEMENTATION_PLAN.md  # the disposable living task list / state
├── specs/                  # durable requirements (overview.md, one per feature)
├── progress.md             # append-only journal (what/why each iteration)
├── ralph.sh                # the loop: pipe PROMPT into `opencode run`
└── (worktree / src)        # where the agent does real work
```

## Ralph files (consistent with the guide)
- **PROMPT.md** — short, directive, tells the cold agent what to read first,
  pick the SINGLE highest-priority item, implement fully, run backpressure
  checks, update plan/progress, commit, stop after ONE item.
- **AGENTS.md** — durable operating knowledge: exact test/build/typecheck
  commands, conventions, gotchas, and "signs" (capitalized blunt corrections
  for what past iterations got wrong).
- **IMPLEMENTATION_PLAN.md** — the changing state; treated as disposable
  (regenerate from specs if it drifts, don't hand-patch confusion).
- **specs/** — guarded, rarely changed, source of truth the plan regenerates from.
- **progress.md** — append-only trail for reviewing an unattended run.
- **ralph.sh** — `for i in $(seq 1 "$MAX"); do cat PROMPT.md | opencode run ... ; <backpressure build/test>; done`, stop when no unchecked items remain.

## Backpressure
Automated checks that must pass before a commit sticks — typecheck, tests,
build. Without it a hallucinating iteration commits broken code that the next
iteration inherits as ground truth. For this kiosk repo the checks would be
`make` (Theos build) — but note the build only runs on the iPad, so the
backpressure for the Qwen agent needs a real, runnable-on-Mac/Windows check.

## Open questions resolved by user
- Bind: **0.0.0.0, no auth (LAN only)**.
- GPU: **CUDA (NVIDIA)** → `-ngl 99`.
- Model location: Windows GPU; client on Mac (LAN reach).

## Still to confirm
- Windows LAN IP for the Mac to target, and GPU VRAM to size the KV cache at 64k.
- What "backpressure" checks the Qwen agent can actually run on the Mac/Windows
  (the Theos build is iPad-only). May need a lightweight substitute (syntax
  check, a test script) for the loop's safety net.
- Whether `opencode run` reliably supports tool-calling on the Q2 quantized
  model — needs a live smoke test once the server is up.
