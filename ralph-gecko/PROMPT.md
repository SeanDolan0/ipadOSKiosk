# PROMPT.md — serve.ps1 static hardening agent

You are working autonomously, in HEADLESS mode, with NO memory of prior runs.
Everything you need is in these files. Read them IN ORDER at the start of every iteration:

1. `AGENTS.md` — how this loop works, conventions, gotchas, and signs.
2. `specs/overview.md` — what we are doing and the explicit non-goals.
3. `specs/serve-ps1.md` — the detailed checklist / validation spec.
4. `IMPLEMENTATION_PLAN.md` — the current task list and state (this is your memory).

## Your job this iteration — do EXACTLY ONE task

- Pick the SINGLE highest-priority UNCHECKED item in `IMPLEMENTATION_PLAN.md`.
- READ `specs/*` and `AGENTS.md` first. Do not re-litigate decisions already made.
- The task is a STATIC review of `scripts/agent/serve.ps1` (and docs). You CANNOT
  run it (it's Windows PowerShell; this is a Mac). Quote the actual script lines
  you're judging; never fabricate what it does.
- Apply ONE concrete fix to `scripts/agent/*.ps1` (or a doc under this repo) for the
  chosen item, OR, if you only verified, record the finding with specific proof.
- No placeholders, no "TODO: implement". A fix must be complete and correct.
- Update `IMPLEMENTATION_PLAN.md`: check the item off; if you found a blocker, add
  it as a new item with a short note.
- Append 1-2 lines to `progress.md`: what you did and why, especially anything
  surprising.
- Commit: `git add -A && git commit -m "<summary>"` (from the repo root).
- Do ONLY the one item. Then stop. Report your result concisely.

## Hard rules (SIGNS)
- STATIC REVIEW ONLY. DO NOT CLAIM to have run serve.ps1 or llama-server.
- NEVER fabricate behavior or paste output you did not actually see.
- ONE task per iteration. Do not batch checklist items.
- KEEP PORT 8085 CONSISTENT across serve.ps1, ralph.sh, and AI_AGENT_ENV.md.
- Do NOT download the model, run Xcode-side builds, or touch Gecko/app/daemon/MQTT.
- When in doubt, prefer the decision already recorded in `specs/*` or
  `IMPLEMENTATION_PLAN.md`. Do not silently change an approved decision.
- If an iteration ends mid-step, leave a "next: ..." note so the next (memory-less)
  iteration can pick up cleanly.
