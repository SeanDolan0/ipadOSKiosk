# IMPLEMENTATION_PLAN.md — serve.ps1 static hardening (safe sandbox target)

Disposable/regenable. **One item = one tiny, verifiable step.** The loop picks the
highest unchecked item and does ONLY that. Static review only — never claim to
have run the script.

## In progress / next up (highest first)
- [x] Grep the whole repo for stale `:8080` (or `8085`) llama-server references; list every file that disagrees with `serve.ps1`'s default `-Port 8085`
- [x] Verify `ralph-gecko/ralph.sh` `PORT=8085` default matches `serve.ps1` `-Port 8085`; fix if drifted
- [x] Verify `AI_AGENT_ENV.md` (repo root) states the 8085 default consistently (search 8080/8085)
- [x] Review the manual quoting (`$psQuote`) used to build the `Start-Process` command line for paths with spaces; fix if broken
- [x] Confirm the port-in-use check (`Get-NetTCPConnection -LocalPort $Port`) is reliable and its error message is actionable
- [x] Confirm the readiness loop detects `$serverProcess.HasExited` and surfaces the exit code
- [x] Confirm `-ngl 99` + 64k ctx + `-ctk q8_0 -ctv q8_0` VRAM estimate is internally consistent (does not exceed ~12 GB or documents a mitigation)
- [x] Confirm the printed `export WINDOWS_IP=...` guidance line uses the actual `$Port` (not a hardcoded 8080/8085)
- [x] LAN-IP filter: `serve.ps1:46` `-notlike "172.*"` drops valid 172.16.0.0/12 (RFC1918) LAN range → `$PrimaryIp` falls back to `<THIS_PC_LAN_IP>` on such networks (discovered while doing Item 8)
- [x] Confirm `start-opencode.ps1` (if present) is consistent with `serve.ps1`'s port/model/health-check

## Done
(none yet)

## Discovered along the way
- (Windows-only, NOT applied) To make the loop fast-fail on a real llama-server
  startup death: append `; exit $LastExitCode` to `$commandLine` (`serve.ps1:94`) so
  the wrapper exits with llama-server's code — and verify on a Windows machine that
  an explicit `exit` actually terminates the process despite `-NoExit`. Requires a
  Windows host; out of scope for this Mac loop (static review only).

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

### Item 5 (port-in-use check) — reliability verified; message example FIXED, 2026-09-03
Reliability of the check (serve.ps1:21-27) holds, no change needed:
- `serve.ps1:22` `Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
  Where-Object { $_.State -eq 'Listen' }` filters on `State -eq 'Listen'` — the correct,
  reliable state: only a socket actually bound-and-listening counts. An outbound
  ESTABLISHED connection to a remote :8085 (whose LOCAL port is ephemeral) never
  matches, so no false positive; a listening socket is always `Listen`, so no
  false negative for the "port taken for binding" case.
- The check actually halts the script: `serve.ps1:19` sets `$ErrorActionPreference =
  "Stop"`, and under Stop, `Write-Error` is terminating (PowerShell throws
  `ParentContainsErrorRecordException`), so execution stops at `serve.ps1:26` BEFORE
  launching llama-server — no wasted 60 s readiness poll after a conflict. This is
  consistent with the other pre-checks (`serve.ps1:34` model-not-found,
  `serve.ps1:41` llama-server-not-found), which use the same `Write-Error`+Stop pattern.
- Degraded-but-harmless edge: if `OwningProcess` is 0 (kernel/other-user socket),
  `Get-Process -Id 0 -ErrorAction SilentlyContinue` (serve.ps1:25) returns nothing,
  so the message shows `process '' (PID: 0)` — still actionable ("stop that process
  or use another port"), so not worth a fix.
Actionability defect (single fix applied): the message's "another port" example was
self-referential — pre-fix `serve.ps1:26` said `...or specify another port (e.g.
.\scripts\agent\serve.ps1 -Port 8085).`, i.e. it suggested the SAME default port
(8085) that the message just reported as in-use, so the command as written does
nothing. Fix: example now `-Port 8086` (a port other than the 8085 default), so the
suggested command is actually runnable.

### Item 6 (readiness loop HasExited / exit code) — inert under -NoExit; message FIXED, 2026-09-03
The `HasExited` check exists and does halt the script (under
`$ErrorActionPreference = "Stop"`, `Write-Error` is terminating — same pattern
verified for the pre-checks, Items 3/5), BUT under the approved `-NoExit` design it
cannot fire for the failure it claims to detect:
- `$serverProcess` is the **wrapper**, not llama-server: `serve.ps1:96`
  `$serverProcess = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile",
  "-NoExit", "-EncodedCommand", $encodedCommand) ... -PassThru`, and the wrapper's only
  statement is `serve.ps1:94` `$commandLine = "& $(& $psQuote $LlamaServer) $($quotedArgs
  -join ' ')"` — a bare `& "<llama-server>" <args>` with NO `exit $LastExitCode`.
- `-NoExit` = "do not exit after running the specified command" (powershell.exe help).
  So when llama-server exits during startup (VRAM OOM, bad Vulkan device, corrupt
  GGUF), the wrapper command completes and the process drops to an interactive
  prompt — it does NOT terminate. `HasExited` (`serve.ps1:105`) can only become true
  if the user closes the detached window (or types `exit` in it). A real startup
  failure therefore polls the full 60 s and falls into the else branch
  (`serve.ps1:127-129`), whose guidance — "Check the llama-server console window for
  error messages." — is CORRECT under `-NoExit` (the window stays open showing the
  error); verified, no change there.
- Exit code misattributed in all cases: `$serverProcess.ExitCode` is the wrapper's
  code. Even in a hypothetical auto-exit, the wrapper's last statement `& <native>`
  sets only `$LastExitCode` inside the child; the child PROCESS's own exit code would
  be 0 (the documented propagation idiom is an explicit `exit $LastExitCode`, which
  is absent) — so the old "llama-server exited before becoming ready (exit code N)"
  never showed llama-server's code.
Fix (single edit, message only, zero semantic risk): old `serve.ps1:106` said
`llama-server exited before becoming ready (exit code N). Check the server window
for details.` — both clauses wrong in the branch's only firing case (wrapper/window
closed; code not llama-server's). New message names the wrapper process, labels the
code as the wrapper's, states the `-NoExit` implication (a startup failure alone keeps
the wrapper alive at a prompt showing the error), and tells the user to re-run
serve.ps1 to capture the startup error.
No functional fix applied: adding `; exit $LastExitCode` to `$commandLine` (or
dropping `-NoExit`) is a recorded-design change — `serve.ps1:87` comment "Launch
through PowerShell -NoExit so startup errors remain visible in the detached window"
and AGENTS.md key fact — and whether an explicit `exit` inside the command
terminates the process despite `-NoExit` is host-version-dependent and cannot be
verified from this Mac (static review only). Tracked as a Windows-only follow-up
under "Discovered".

### Item 7 (VRAM estimate) — internally consistent; default est. over 12 GB, mitigation documented, 2026-09-03
Spec item 2. Verdict: the flag set is internally consistent (line-by-line below)
and the q4_0 mitigation is documented, so the item PASSES via the "documents a
mitigation" path. No re-tune applied (spec: "just verify the flag set is internally
consistent and documented"). One real finding recorded: the documented DEFAULT
(q8_0 at 64k) is estimated to exceed the 12 GB GPU, so first launch as configured
likely OOMs.
Internal consistency (verbatim, all agree):
- `serve.ps1:15` `[int]$Context = 65536,` = comment `serve.ps1:57` `-c 65536` = arg `serve.ps1:72` `"-c", "$Context",`
- `serve.ps1:16` `[string]$CacheType = "q8_0"` = comments `serve.ps1:58-59` `-ctk q8_0`/`-ctv q8_0` = args `serve.ps1:73-74` `"-ctk", $CacheType` / `"-ctv", $CacheType`
- `serve.ps1:71` `"-ngl", "99",` = comment `serve.ps1:56` `-ngl 99`; `serve.ps1:70` `"-dev", "Vulkan1",` = comment `serve.ps1:55`; `serve.ps1:75` `"--load-mode", "mlock",` = comment `serve.ps1:60`; `serve.ps1:76` `"--jinja",` = comment `serve.ps1:61`; `serve.ps1:77` `"-np", "1"` = comment `serve.ps1:62`
No drift among param defaults, the comment block, and the `$args` array.
VRAM estimate (ESTIMATE — exact KV size needs the model architecture from the GGUF,
which is NOT downloaded (9.83 GB, out of scope); assuming a Qwen3-27B-like
architecture: 64 layers, GQA 24 query / 4 KV heads, head_dim 128 — an ASSUMPTION,
not a measurement):
- Weights (Q2_K_XL, `-ngl 99`): ~9.83 GB (file size; in-VRAM ≈ file + small alignment).
- Per-token KV elements: 2 (K+V) × 64 layers × 4 KV heads × 128 head_dim = 65,536.
- q8_0 = 1.125 B/element (32×1 B + 4 B scale per 32): 73,728 B/token × 65,536 ≈ 4.8 GB.
- q4_0 ≈ 0.56–0.625 B/element: ≈ 2.4–2.7 GB. Compute/activation buffers: ~0.3–0.5 GB.
- Totals: q8_0 at 64k ≈ 9.9 + 4.8 + 0.4 ≈ **~15.1 GB** (over 12 GB by ~3 GB — default OOMs);
  q4_0 at 64k ≈ 9.9 + 2.4–2.7 + 0.4 ≈ **~12.7–13.0 GB** (borderline, at/slightly over 12 GB).
So even the documented q4_0 mitigation is borderline at 64k on a 12 GB GPU; a clean fit
would need a shorter context, a smaller KV quant (q2/q1), or fewer offloaded layers.
Mitigation (documented, not changed): `serve.ps1:58-59` "use q4_0 if tight on VRAM";
`-CacheType` param (`serve.ps1:16`) lets a user run `.\serve.ps1 -CacheType q4_0`;
`AI_AGENT_ENV.md:65` repeats "use q4_0 if VRAM is tight with 64k".
Nitpick, no fix: `serve.ps1:58-59` "saves ~50% VRAM" — q8_0 (1.125 B) vs fp16 KV (2 B)
saves ~44%, not ~50%; within the "~" leeway and it is a comment, so not fixed.
Windows-only handoff (NOT applied): the default `-CacheType q8_0` at `-c 65536` is
estimated ~15 GB > 12 GB, so first launch as configured likely OOMs. A human on
Windows should decide: change the default to q4_0, lower the default context, or
document the expected first-launch OOM + `-CacheType q4_0` retry. Not applied here
(spec: do not re-tune; architecture unverified).

### Item 8 (WINDOWS_IP guidance $Port) — VERIFIED, no fix; LAN-IP filter bug found, 2026-09-03
Spec item 5 (guidance half). The runtime-printed guidance uses the actual `$Port`;
there is NO hardcoded `8080`/`8085` in any printed line. Verbatim proof (serve.ps1):
- `serve.ps1:122` `Write-Host "  export WINDOWS_IP=$PrimaryIp"` — the `export
  WINDOWS_IP` line references only the IP (`$PrimaryIp`), which is correct: WINDOWS_IP
  is an IP address and takes no port. (The spec's parenthetical "it writes `:8085`" is
  itself inaccurate — the printed export line writes no port; the port lives in the
  adjacent lines, which DO use `$Port`.)
- Every printed line that DOES reference a port uses `$Port`:
  - `serve.ps1:80` `Starting llama-server on http://0.0.0.0:$Port (LAN-reachable) ...`
  - `serve.ps1:109` `Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/models"` (readiness poll)
  - `serve.ps1:120` `Local endpoint:  http://127.0.0.1:$Port/v1`
  - `serve.ps1:123` `curl http://${PrimaryIp}:$Port/v1/models`
  - `serve.ps1:124` `...make sure Windows Firewall allows TCP ${Port}:`
  - `serve.ps1:125` `netsh advfirewall ... localport=$Port`
  - `serve.ps1:129` `You can test manually with:  Invoke-RestMethod http://127.0.0.1:$Port/v1/models`
- The only hardcoded port literals in the file are `serve.ps1:3` and `serve.ps1:11`
  (file-header COMMENTS documenting the 8085 default) and `serve.ps1:14`
  `[int]$Port = 8085,` (the param default). `serve.ps1:26`'s `-Port 8086` is the
  intentional "another port" example from Item 5. No `8080` anywhere in the file.
So the guidance correctly tracks whatever `-Port` the user passes; verified, no fix.
Finding (NEW item, NOT fixed this iteration — the filter is the "discovery" half of
spec item 5, outside item 8's port-only scope): the LAN-IP filter
`serve.ps1:45-47` `... -and $_.IPAddress -notlike "172.*" ...` drops EVERY 172.x.x
address, including the valid RFC1918 private range 172.16.0.0/12 (a perfectly valid
LAN subnet). On a 172.16.x.x network that filter empties `$LanIps`, so
`$PrimaryIp` (`serve.ps1:48`) falls back to `"<THIS_PC_LAN_IP>"` and the guidance
(`serve.ps1:122-123`) prints the placeholder instead of the user's real IP — forcing
manual IP discovery. The other filters are fine (`*Loopback*` interface drop,
`169.254*` link-local drop) and 192.168/10.x are kept, so the `172.*` arm is the
inconsistent one. Tracked as the next unchecked item above (fix = keep RFC1918
private ranges, e.g. narrow the drop to public/other, or at minimum re-include
172.16.0.0/12).

### Item 9 (LAN-IP filter 172.16.0.0/12) — FIXED in serve.ps1, 2026-09-03
Spec item 5 (discovery half). Pre-fix verbatim (old `serve.ps1:45-48`):
- `$LanIps = Get-NetIPAddress -AddressFamily IPv4 ... | Where-Object {
  $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.254*"
  -and $_.IPAddress -notlike "172.*" } | Select-Object -ExpandProperty IPAddress`
- `$PrimaryIp = if ($LanIps) { $LanIps[0] } else { "<THIS_PC_LAN_IP>" }`
The `-notlike "172.*"` arm dropped EVERY 172.x.x.x address, including the
RFC1918 private range 172.16.0.0/12 (172.16.x.x–172.31.x.x) — a perfectly valid
LAN subnet (common in corporate/VM networks). On such a network `$LanIps` came
back empty, so `$PrimaryIp` fell back to the `<THIS_PC_LAN_IP>` placeholder and
the printed guidance (`export WINDOWS_IP=$PrimaryIp` /
`curl http://${PrimaryIp}:$Port/v1/models`) showed the placeholder instead of
the real IP, forcing manual discovery. The other filters were already correct
(`*Loopback*` interface drop, `169.254*` link-local drop; 10.* and 192.168.*
kept) — the `172.*` arm was the inconsistent one.
Fix (single edit, filter predicate only): replaced the blacklist with an
RFC1918 whitelist. New `serve.ps1:46-50` defines
`$IsRfc1918 = { param($ip) $o = $ip.Split('.') | ForEach-Object { [int]$_ };
($o[0] -eq 10) -or ($o[0] -eq 172 -and $o[1] -ge 16 -and $o[1] -le 31) -or
($o[0] -eq 192 -and $o[1] -eq 168) }`
and the pipeline (now `serve.ps1:51-53`) gates on `(& $IsRfc1918
$_.IPAddress)` in place of `-notlike "172.*"`. Result: 172.16.x.x–172.31.x.x
now survive (the bug); 10.* and 192.168.* still survive; and — a deliberate
tightening of the old blacklist's keep-everything-else behavior — public
addresses (incl. 172.0–15.x.x, 172.32+.x.x, and any other public 203.x-style
address) are no longer offered as a "LAN IP"; a machine with only public
addresses gets the placeholder, which is correct for the script's "the Mac
reaches Windows over the LAN" purpose. The explicit `-notlike "169.254*"`
link-local arm is retained (redundant with the whitelist but documents intent).
No port, launch, or readiness change; `$PrimaryIp` (now `serve.ps1:54`) and the
printed guidance lines are untouched. Static review only: no pwsh on this
Mac, so the edit is by inspection (script-block `param($ip)`, `.Split('.')`,
`[int]` cast, and `& $IsRfc1918` invocation are all standard PowerShell).

### Item 10 (start-opencode.ps1 parity) — VERIFIED, consistent, no fix; one nit, 2026-09-03
Plan item: "Confirm `start-opencode.ps1` (if present) is consistent with
`serve.ps1`'s port/model/health-check". The script is present
(`scripts/agent/start-opencode.ps1`, 26 lines). Verdict: all three dimensions
match; no code change. Verbatim proof:
- **Port**: `start-opencode.ps1:13` `$m = Invoke-RestMethod -Uri
  "http://127.0.0.1:8085/v1/models" -TimeoutSec 5` hardcodes 8085, which equals
  `serve.ps1:14` `[int]$Port = 8085,`. The hardcode is the script's documented
  contract, not drift: its own header (`start-opencode.ps1:3-4`) says opencode
  "reads the GLOBAL config (~/.config/opencode/opencode.json) which already
  defines provider 'local' -> http://localhost:8085/v1, model local/qwen3.8"
  and that "THIS script just verifies the server is reachable and launches
  opencode here" — i.e. the check must match the port opencode's config will
  actually use (8085). A `serve.ps1 -Port <other>` server is unreachable by
  opencode itself (the global config is pinned to 8085 and lives outside this
  repo), so the check failing there is the correct behavior, not a bug.
  `start-opencode.ps1:13` is the only executable port use; the other `:8085`
  in the file is the header comment (`start-opencode.ps1:4`).
- **Model**: no model name in code — `start-opencode.ps1:14` prints the
  server-reported `$m.data[0].id`; the header's `local/qwen3.8` matches
  `ralph.sh:59` (`"model": "local/qwen3.8"`), `ralph.sh:72`
  (`opencode run --model local/qwen3.8 --auto`), and `AI_AGENT_ENV.md:20`.
  The served file `Qwen3.8-27B-UD-Q2_K_XL.gguf` (`serve.ps1:31`) is the same
  model.
- **Health check**: path `/v1/models` on loopback — identical to
  `serve.ps1:115` (`http://127.0.0.1:$Port/v1/models`) and `AI_AGENT_ENV.md:86`
  (`verify http://127.0.0.1:8085/v1/models returns model JSON`); same
  terminating `try/catch` + `Write-Error` under
  `$ErrorActionPreference = "Stop"` pattern already verified in Items 3/5
  (`start-opencode.ps1:9,15-17`). `$Repo` (`start-opencode.ps1:20`,
  `Split-Path -Parent` twice on `$PSScriptRoot` = `<root>/scripts/agent`)
  yields the repo root, whose `opencode.json` (10 lines) holds only an `mcp`
  block — NO `provider`/`model` keys — so nothing in-repo overrides the global
  config the header describes; the header claim is consistent with the
  in-repo state.
Nit (recorded, NOT fixed — plan precedent "nitpick, no fix" from Items 3/5/7):
`start-opencode.ps1:16`'s error "Model server is NOT running. Start it first:
 .\scripts\agent\serve.ps1" doesn't name the port it checked (8085). A user
 who started with `serve.ps1 -Port 8086` sees "NOT running" — but the check
 (and opencode's global config) are pinned to 8085 by design, so the message
 is actionable as-is.
