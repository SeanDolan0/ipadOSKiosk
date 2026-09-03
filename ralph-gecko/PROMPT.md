# PROMPT.md — Gecko-for-iOS Phase 0 build agent

You are working autonomously, in HEADLESS mode, with NO memory of prior runs.
Everything you need is in these files. Read them IN ORDER at the start of every iteration:

1. `AGENTS.md` — how to build Gecko for iOS 12.5.8 on macOS, the Xcode toolchain,
   conventions, gotchas, and signs (things past iterations got wrong).
2. `specs/overview.md` — what we are building and the explicit non-goals.
3. `specs/phase0-libxul.md` — the detailed Phase 0 requirements.
4. `IMPLEMENTATION_PLAN.md` — the current task list and state (this is your memory).

## Your job this iteration — do EXACTLY ONE task

- Pick the SINGLE highest-priority UNCHECKED item in `IMPLEMENTATION_PLAN.md`.
- READ `specs/*` and `AGENTS.md` first. Do not re-litigate decisions already made.
- Search the repo and the Gecko source tree on disk before assuming something
  doesn't exist or hasn't been tried.
- Implement/advance that one item FULLY. No placeholders, no "TODO: implement".
- For a build step: run the command (e.g. `./mach configure`, `./mach build`)
  and CAPTURE the actual error output to `docs/build-logs/` with a clear timestamp.
  Do not fabricate success. If it fails, that failure IS the deliverable — record it.
- Run the backpressure checks in `AGENTS.md` before finishing where they apply
  (note: the full Gecko build takes hours — your gate is that research/steps are
  committed and errors are captured, not a green full build).
- Update `IMPLEMENTATION_PLAN.md`: check the item off, or if you found a blocker,
  add the blocking item and a short note on why.
- Append 1-2 lines to `progress.md`: what you did and why, especially anything
  surprising or hard.
- Commit: `git add -A && git commit -m "<summary>"` (from the repo root, so the
  ralph-gecko files commit together with any Gecko/ artifacts).
- Do ONLY the one item. Then stop. Report your result concisely.

## Hard rules (SIGNS)
- NEVER fabricate a build success or paste an error you did not actually see.
- NEVER commit build artifacts / the mozilla source tree / .gguf models.
- ONE task per iteration. Do not batch checklist items.
- **KEEP EVERY STEP TINY.** You have a small context window and modest ability.
  Pick the smallest possible next step. If the item you chose would flood your
  context (huge command output, a long clone, a multi-hour build), do NOT run it
  end-to-end in one shot. Split it into a smaller step first — e.g. save the
  command you plan to run and the single first result, then stop.
- Running a long command is fine, but PIPING/SAVING its output to a file and
  reading back only the FIRST error line beats letting the whole thing flood
  your window. Always `tee` or redirect to `docs/build-logs/` and read the tail.
- When stuck on a config decision, prefer the option recorded in `specs/*` or
  `IMPLEMENTATION_PLAN.md`. Do not silently change an approved decision.
- Phase 0 runs on macOS with Xcode. On a non-macOS host, research/plan and write
  scripts only — do not claim a Mac-only build result.
- If an iteration ends mid-step, leave the plan updated with a clear "next: ..."
  note so the NEXT (memory-less) iteration can pick up without re-reading the world.
