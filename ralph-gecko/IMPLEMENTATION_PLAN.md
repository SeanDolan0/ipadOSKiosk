# IMPLEMENTATION_PLAN.md — serve.ps1 static hardening (safe sandbox target)

Disposable/regenable. **One item = one tiny, verifiable step.** The loop picks the
highest unchecked item and does ONLY that. Static review only — never claim to
have run the script.

## In progress / next up (highest first)
- [x] Grep the whole repo for stale `:8080` (or `8085`) llama-server references; list every file that disagrees with `serve.ps1`'s default `-Port 8085`
- [ ] Verify `ralph-gecko/ralph.sh` `PORT=8085` default matches `serve.ps1` `-Port 8085`; fix if drifted
- [ ] Verify `AI_AGENT_ENV.md` (repo root) states the 8085 default consistently (search 8080/8085)
- [ ] Review the manual quoting (`$psQuote`) used to build the `Start-Process` command line for paths with spaces; fix if broken
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
