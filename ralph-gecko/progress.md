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

## Iteration 3
Item 3 (AI_AGENT_ENV.md 8085 parity): grepped the repo-root doc for
`8080`/`8085` — zero `8080` hits, all 7 port literals are `8085` matching
`serve.ps1:14` default; invocation line 37 (`powershell -ExecutionPolicy
Bypass -File .\scripts\agent\serve.ps1`) matches `serve.ps1:8` verbatim.
Verified, no fix needed; only nitpick: line 46 says `serve.ps1 --port` where
the real param is `-Port` (llama-server's `--port` flag is what it forwards) —
noted in plan, no change.

## Iteration 4
Item 4 ($psQuote quoting): reviewed the manual quoting and found it BROKEN in two
ways, fixed both in serve.ps1 (one change). (1) Old line 88 wrapped each arg in
DOUBLE quotes but escaped SINGLE quotes by doubling (`-replace "'", "''"`), which is
the wrong convention: a `'` needs no escaping in a double-quoted string (so a path
like `C:\O'Brien\x.gguf` was sent as `C:\O''Brien\...`), while `"` and `` ` `` — the
chars that DO need escaping in `"..."` — were left unescaped (a `"` terminated the
string early). (2) Old line 91 sent `$commandLine` via `Start-Process -Command`;
that string always has spaces, so Start-Process re-quoted the element without
escaping its internal quotes, garbling even the plain spaces case. Fix: escaper now
doubles backticks then doubles `"` (correct double-quote form), and the command is
passed to the child via `-EncodedCommand` (Base64 UTF-16LE) so Start-Process does no
re-quoting — spaces/quotes/backticks in the model path survive. Surprising bit: the
"spaces" framing undersold it — the escaper's wrong single/double convention was a
separate, quote-only corruption; the `-EncodedCommand` transport fixes the spaces
case the old `-Command` path couldn't.

## Iteration 5
Item 5 (port-in-use check): verified the check is reliable — `serve.ps1:22` filters
`State -eq 'Listen'` (the only state a bound-and-listening socket has), so an
outbound ESTABLISHED connection to a remote :8085 (ephemeral local port) never
false-positives; and under `$ErrorActionPreference = "Stop"` (serve.ps1:19) the
`Write-Error` at serve.ps1:26 is terminating, so the script halts before launching
llama-server (no 60 s poll after a conflict), matching the model/llama-server
pre-checks. Found + fixed one actionability defect: the "another port" example was
self-referential (`-Port 8085` — the very default port reported in-use); changed it
to `-Port 8086` so the suggested command is runnable.

## Iteration 6
Item 6 (readiness-loop HasExited/exit code): the fast-fail path is INERT under the
approved -NoExit design — `$serverProcess` is the powershell.exe WRAPPER
(serve.ps1:96), and -NoExit keeps that process at an interactive prompt after
llama-server's startup failure (command is a bare `& "<llama-server>" <args>`, no
`exit $LastExitCode`, serve.ps1:94), so HasExited can only fire on a user-closed
window; and the surfaced code was the wrapper's, never llama-server's. Fixed the
Write-Error message (one edit, serve.ps1:106) to name the wrapper, label its exit
code honestly, and say re-run to capture the error. 60 s fallback path verified
correct as-is (window stays open under -NoExit). Surprising: -NoExit (the "keep
startup errors visible" design choice) silently disables the loop's own
HasExited detection; Windows-only follow-up (`; exit $LastExitCode` + verify
exit-under--NoExit) noted in plan, NOT applied (unverifiable semantics here +
recorded-design change).

## Iteration 7
Item 7 (VRAM estimate): verified the flag set is internally consistent
(`serve.ps1:15/16` param defaults = `:56-59` comment block = `:70-74` `$args`,
line-by-line) and the q4_0 mitigation is documented (`serve.ps1:58-59`, `:73-74`;
`AI_AGENT_ENV.md:65`), so the item passes. No re-tune (per spec). Real finding,
recorded not fixed: assuming a Qwen3-27B-like architecture (64 layers, GQA 4 KV
heads, head_dim 128 — an ASSUMPTION; the 9.83 GB GGUF is not downloaded, out of
scope), q8_0 at 64k ≈ 9.9 GB weights + 4.8 GB KV ≈ **~15 GB > 12 GB**, so the
DEFAULT likely OOMs on first launch; the documented q4_0 mitigation ≈ ~12.7–13 GB,
still borderline. Nitpick: the "saves ~50% VRAM" comment is really ~44% (1.125 vs
2 B/element) — within "~", not fixed. Surprising bit: even the recommended q4_0
fallback is borderline at 64k on a 12 GB GPU, so a clean fit needs shorter context
or a smaller KV quant. Windows-only handoff (decide default q4_0 / shorter context /
document expected OOM) recorded in plan, NOT applied.
