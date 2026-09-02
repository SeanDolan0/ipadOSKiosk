# Claude Code Automation Recommendations

Generated for **HA Smartboard** (iPadOS 12.5.8 jailbreak kiosk, Theos/Objective-C).

## Codebase Profile

- **Type**: Objective-C / C (UIKit app + root launchd daemon)
- **Build**: Theos on-device (arm64, `TARGET = iphone:clang:12.4:12.0`), no Xcode
- **Deploy**: manual Windows→iPad sync (plink/pscp) → on-device `make → package → install` → ldid/chown/launchctl/uicache
- **Testing**: none (no suite, no linter); validation is on-device `curl`/logs
- **External**: Home Assistant REST API (single token, planned MQTT migration)
- **Notable**: no `.claude/` config yet — clean slate

---

## 🎯 Skill (highest value — build/deploy)

#### `deploy-kiosk`
**Why**: Deployment here is a ~9-step, order-mandatory, easy-to-miss-`ldid`-or-`uicache` ritual documented across `DEPLOYMENT_GUIDE.md` + `CLAUDE.md`. Today every reinstall is hand-retaped over SSH. Wrap it in one repeatable, checked skill so future edits to `App/` or `Daemon/` reliably reach the device.
**Create**: `.claude/skills/deploy-kiosk/SKILL.md`
**Invocation**: User-only (`disable-model-invocation: true`) — it runs side-effecting SSH commands.
**Contents**: Both supported modes from the guide, each ending in on-device verification:
1. **From Windows** — `pscp` source → device checkout, then one `plink` batch: `make && make package && make install`, followed by the mandatory post-install (`ldid -S Daemon/kioskd.entitlements`, `chown root:wheel` + `chmod 644` the plist, `launchctl unload/load`, `uicache -p`).
2. **On-device or via plink** — cd `/var/mobile/Apps/ipadOSKiosk` and run the same sequence.
3. **Verify** — `curl -sf http://127.0.0.1:9090/health`, `launchctl list | grep hasmartboard`, tail `kioskd.log`/`hasmartboard.log`.
Pin the hostkey (`SHA256:tTQh0tVy4n2k+Kwntq4etfwboSdVHEF+jw8Hq66MxQo`), use plink/pscp (sshpass-win32 is broken here), and **never** `export TARGET` over the pinned 12.4 SDK.
**Also consider**: a companion `sync` shortcut (docs-only edits → just `pscp` the changed source files, skip rebuild) for fast iteration.

---

## 🛠️ Hooks

#### PostToolUse — guard the device plist / config schema
**Why**: `config.plist.example` defines the single source of truth the app + daemon read at startup; a malformed or schema-drifted plist just silently fails on-device with no test suite to catch it. `App/KioskViewController.m:loadHAConfig` and the daemon both depend on exact keys.
**Where**: `.claude/settings.json`
**Behavior**: on Write/Edit of `config.plist.example` or `App/KioskViewController.m` config-loading code, run a `plutil -lint`-style check (or a small `xmlstarlet`/python `plistlib` validation) and flag any mismatch against the keys the code reads.

#### PreToolUse — require confirmation before daemon/app source edits
**Why**: The project convention (CLAUDE.md) is strict about the localhost-only bind, endpoint shapes, and runtime `dlsym` for private APIs. A review gate on new `Validate` commands isn't needed; but blocking accidental edits to `Daemon/main.m` (the localhost bind) and the HA bridge is cheap insurance.
**Where**: `.claude/settings.json`

---

## 🤖 Subagents

#### `deploy-reporter` (or rely on the `deploy-kiosk` skill's verify step)
**Why**: On-device validation after a deploy is the project's substitute for a test suite. A short subagent that SSHes in, runs the `health`/`telemetry`/`launchctl`/log checks, and returns a PASS/FAIL summary with the relevant log tail saves you re-reading half the CLI output yourself.
**Where**: `.claude/agents/deploy-reporter.md`
**Note**: This duplicates the skill's verify step — pick whichever you prefer (skill = human-invoked, agent = Claude-invoked during a session).

#### `security-reviewer` (existing, recommended by default)
**Why**: A jailbroken **root** daemon handling device control commands (`reboot`, `relaunchApp`) is security-sensitive: it binds localhost, and `DeviceControl.m` acts on `POST /command`. Have a focused reviewer check that command validation stays tight and the plist token never lands in git/logs.

---

## 🔌 MCP Servers

The codebase has no local web server, database, or browser UI to drive — the usual MCP targets don't apply. Two modest fits:

#### `context7`
**Why**: You work against iOS 12 SDK private APIs and Theos conventions that drift over time. `context7` gives live docs for Theos / Objective-C / iOS SDK patterns when touching `App/` or `Daemon/`.
**Install**: `claude mcp add context7`
**Caveat**: The project's own rules (CLAUDE.md) explicitly say to verify private symbols against the iOS 12 SDK, not to invent them — context7 is a supplement, not authority.

#### Home Assistant REST/MQTT (optional — deferred)
**Why**: After the MQTT migration (TODO Feature 1), a scratch HA API call during development (list entities, test discovery topics) could help. **Not worth adding now** — the MQTT work isn't implemented, and the HA token shouldn't flow through an MCP config. Revisit post-migration.

---

## 📦 Plugins

#### `anthropic-agent-skills` (general productivity core)
**Why**: Ships `commit-commands` (conventional commit), `docx/xlsx/pdf` (config/guide docs), and generic skills that slot into this repo with zero codebase-specific setup.

#### `mcp-builder` only if you build an MQTT MCP helper later — skip for now (YAGNI).

---

## Want more?

Ask and I'll expand any category — e.g. *"more hook options"*, *"a second deploy skill variant"*, or *"custom skills for the HA REST/MQTT migration"*.

## Want help implementing?

Just ask — I can create the `deploy-kiosk` skill, wire the hooks into `.claude/settings.json`, or scaffold the subagent.
