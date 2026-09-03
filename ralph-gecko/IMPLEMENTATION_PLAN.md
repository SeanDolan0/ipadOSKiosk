# IMPLEMENTATION_PLAN.md — serve.ps1 static hardening (safe sandbox target)

Disposable/regenable. **One item = one tiny, verifiable step.** The loop picks the
highest unchecked item and does ONLY that. Static review only — never claim to
have run the script.

## In progress / next up (highest first)
- [x] Grep the whole repo for stale `:8080` (or `8085`) llama-server references; list every file that disagrees with `serve.ps1`'s default `-Port 8085`
- [x] Verify `ralph-gecko/ralph.sh` `PORT=8085` default matches `serve.ps1` `-Port 8085`; fix if drifted
- [x] Verify `AI_AGENT_ENV.md` (repo root) states the 8085 default consistently (search 8080/8085)
- [x] Review the manual quoting (`$psQuote`) used to build the `Start-Process` command line for paths with spaces; fix if broken
- [ ] Confirm the port-in-use check (`Get-NetTCPConnection -LocalPort $Port`) is reliable and its error message is actionable
- [ ] Confirm the readiness loop detects `$serverProcess.HasExited` and surfaces the exit code
- [ ] Confirm `-ngl 99` + 64k ctx + `-ctk q8_0 -ctv q8_0` VRAM estimate is internally consistent (does not exceed ~12 GB or documents a mitigation)
- [ ] Confirm the printed `export WINDOWS_IP=...` guidance line uses the actual `$Port` (not a hardcoded 8080/8085)
- [ ] Confirm `start-opencode.ps1` (if present) is consistent with `serve.ps1`'s port/model/health-check

## Done
(none yet)

## Discovered along the way
(loop appends blockers/gotchas/new sub-tasks here)

### Item 1 (port grep) — full file list, 2026-09-03
Every file containing `8080`/`8085`, classified against `serve.ps1`'s default
`-Port 8085`:

- **llama-server, already 8085 (no change):** `scripts/agent/serve.ps1`,
  `scripts/agent/start-opencode.ps1`, `ralph-gecko/ralph.sh`,
  `ralph-gecko/opencode.json`, `ralph-gecko/opencode.json.template`,
  `AI_AGENT_ENV.md`, `docs/ralph-loop-usage.md`
- **llama-server, stale `8080` — FIXED to 8085:** `docs/agent-research.md`
  (2 lines: `0.0.0.0:8080` and `http://<WINDOWS_IP>:8080/v1` in the
  "Architecture (final)" section — present-tense, so it disagreed)
- **`8080` present but NOT llama-server (kiosk daemon REST API, separate
  subsystem — explicitly OUT of scope for this loop, left untouched):**
  `kiosk-app-features.md`, `docs/superpowers/specs/2026-09-01-bidirectional-mqtt-rest-tts-design.md`,
  `docs/superpowers/plans/2026-09-01-bidirectional-mqtt-rest-tts.md`,
  `Daemon/main.m` (`#define HTTP_PORT 8080`), `Daemon/tests/test_http_server.c`
  (`TEST_PORT 18080`)
- **Historical/append-only (port moved 8080->8085 is itself the narrative;
  do not rewrite history):** `docs/build-logs/2026-09-02-gecko-phase0-progress.md`
  (lines 84/92 record state at commit 340bb58, before the port move),
  `ralph-gecko/progress.md`, `ralph-gecko/specs/serve-ps1.md`,
  `ralph-gecko/AGENTS.md`, `ralph-gecko/PROMPT.md`, this plan itself

### Item 2 (ralph.sh port parity) — verified, no drift, 2026-09-03
`ralph.sh` default matches `serve.ps1` default; no fix needed. Proof (verbatim):
- `ralph.sh:28`: `PORT="${PORT:-8085}"` — the only port default assignment in the file
- `serve.ps1:14`: `[int]$Port = 8085,` — the only port default assignment in the file
- Every live use of the port in `ralph.sh` expands `${PORT}` (no hardcoded literal):
  preflight echo line 31 (`http://${WINDOWS_IP}:${PORT}/v1/models ...`),
  preflight `curl` line 32, error echo line 33, and the generated
  `opencode.json` `baseURL` line 51 (`"baseURL": "http://${WINDOWS_IP}:${PORT}/v1"`)
- Comments naming the default (ralph.sh lines 6-7, 27, 36) all say 8085, matching

### Item 3 (AI_AGENT_ENV.md 8085 parity) — verified, no drift, 2026-09-03
`AI_AGENT_ENV.md` states the 8085 default consistently: ZERO `8080` occurrences
in the file; all 7 port-literal hits are `8085`, matching `serve.ps1:14`
`[int]$Port = 8085,`. Verbatim proof (AI_AGENT_ENV.md line numbers):
- Line 24: `Run `download-model.ps1` → `serve.ps1` (listens on `0.0.0.0:8085` by default, ...)`
- Line 25: `Set `WINDOWS_IP=192.168.x.y` (and `PORT=8085`)`
- Line 33: `# 2) Allow inbound port 8085 through Windows Defender Firewall`
- Line 34: `netsh advfirewall firewall add rule name="llama-server 8085" ... localport=8085`
- Line 46: `export PORT=8085                   # must match serve.ps1 --port (default 8085)`
- Line 72: `serve.ps1              # llama-server on 0.0.0.0:8085 using RTX 5070 Ti (Vulkan1)`
- Line 86: `verify `http://127.0.0.1:8085/v1/models` returns model JSON`
Invocation parity also holds: AI_AGENT_ENV.md line 37
`powershell -ExecutionPolicy Bypass -File .\scripts\agent\serve.ps1` matches
`serve.ps1:8`'s documented usage line verbatim; the `WINDOWS_IP` guidance
(line 45, "or the LAN IP printed by serve.ps1") matches `serve.ps1:84`
(`Detected LAN IP(s)`) and `serve.ps1:117` (`export WINDOWS_IP=$PrimaryIp`).
Nitpick, no fix: line 46 writes `serve.ps1 --port`; the script's actual param
is `-Port` (`serve.ps1:14`). `--port` is the llama-server flag that serve.ps1
forwards (`serve.ps1:69` `--port "$Port"`), so the shorthand is defensible and
the stated default (8085) is correct either way — not a port mismatch.

### Item 4 ($psQuote quoting) — BROKEN, FIXED in serve.ps1, 2026-09-03
The manual quoting was broken in two compounding ways (pre-fix verbatim):
- Old `serve.ps1:88` `$psQuote = { param($value) '"' + ($value -replace "'", "''") + '"' }`
  wraps each value in **double** quotes but escapes **single** quotes by doubling.
  In a PowerShell double-quoted string, `'` needs no escaping (so a path like
  `C:\O'Brien\...gguf` was sent as `C:\O''Brien\...` — wrong file), and `"`/`` ` ``
  are the chars that actually need escaping (doubled / backtick-doubled) — neither
  was handled, so any `"` in the value terminated the string early.
- Old `serve.ps1:91` `Start-Process ... @("-NoProfile","-NoExit","-Command", $commandLine)`:
  `$commandLine` always contains spaces, so `Start-Process` re-quotes the element
  (wrapping in quotes without escaping its internal quotes) — garbling even the
  spaces-only case.
Fix (serve.ps1, single change): escaper now emits correct double-quote form
(`$psQuote = { param($value) '"' + (($value -replace '`','``') -replace '"','""') + '"' }`,
now line 92) and the command is transported via `-EncodedCommand`
(Base64 UTF-16LE, new `$encodedCommand` line 95, `Start-Process ... -EncodedCommand
$encodedCommand` line 96) so `Start-Process` performs no re-quoting; spaces, single
quotes, double quotes, and backticks in `$Model`/`$LlamaServer` all survive intact.
