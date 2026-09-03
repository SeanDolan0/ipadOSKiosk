# Ralph Loop Usage on the Local Qwen Agent

> This branch (`qwen-local-agent`) uses the **plugin-less Ralph loop** — a files +
> bash-loop pattern, NOT a plugin (no `/ralph-loop` slash command, no
> `.claude/ralph-loop.local.md`). See `ralph-loop-setup-guide.md` (repo root) for
> the full technique.

## What the Ralph loop is
A self-referential development loop. Each iteration runs opencode **headless** with a
**fresh context window** (no memory of prior runs). The filesystem is the memory:
`git history` (ground-truth changes), `IMPLEMENTATION_PLAN.md` (living state), and
`progress.md` (append-only journal). The agent re-reads `PROMPT.md`/`AGENTS.md` cold
every iteration, does exactly ONE item, then commits.

## Files (all under `ralph-gecko/`)
| File | Role |
|---|---|
| `ralph.sh` | The loop runner (Mac). Pre-flight-checks the Windows llama-server, auto-writes `opencode.json`, then iterates. |
| `PROMPT.md` | The instruction set passed as the message each iteration. |
| `AGENTS.md` | Durable operating manual / gotchas / signs. |
| `IMPLEMENTATION_PLAN.md` | Living checklist (one item = one iteration). |
| `progress.md` | Append-only run journal. |
| `specs/*.md` | Durable requirements the plan is generated from. |

## Running it
```bash
# 0. On Windows, serve the model (default port 8085):
#    powershell -ExecutionPolicy Bypass -File .\scripts\agent\serve.ps1
#
# 1. On the Mac:
cd ralph-gecko
export WINDOWS_IP=192.168.50.177   # this PC's LAN IP (or the IP printed by serve.ps1)
export PORT=8085                    # must match serve.ps1's --port (default 8085)
./ralph.sh 50                       # cap at 50 iterations

# ralph.sh stops early when IMPLEMENTATION_PLAN.md has no unchecked items left.
```

`ralph.sh` writes a fresh `ralph-gecko/opencode.json` each run pointing the
`local/qwen3.8` provider at `http://${WINDOWS_IP}:${PORT}/v1`, then drives
`opencode run --model local/qwen3.8 --auto "$(cat PROMPT.md)"`.

## Why the user runs the local Qwen on a loop here
- The 27B Q2 model is memory/CPU-bound; letting it self-iterate on one task in a
  branch (instead of being babysat) matches the "I can't monitor it" concern.
- The loop writes its work to files/git history, which is reviewable later.

## Recommended safe pattern on THIS branch (bounded, monitored)
- Prefer a small, bounded run (`./ralph.sh 5`) on a scope the model can plausibly
  finish, so it does not churn forever on a slow local model.
- Because this branch is an experimental sandbox (`AI_AGENT_ENV.md`), keep loop
  targets small and self-contained; review `git log` + `progress.md` + `logs/`
  after each run.

## Tuning
When Ralph does something wrong, don't just fix the code by hand — add a "sign"
(capitalized blunt correction) to `ralph-gecko/AGENTS.md` so the *next* iteration
won't repeat the mistake. That feedback loop is the real tuning mechanism.
