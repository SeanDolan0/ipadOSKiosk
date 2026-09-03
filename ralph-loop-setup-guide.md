# Setting Up a Ralph Loop — No Plugin, Just Files + a Bash Loop

## What Ralph actually is

Ralph (the "Ralph Wiggum technique," coined by Geoffrey Huntley) is not a tool.
It's a pattern: you run an AI coding agent in a `while true` loop, in
**headless/non-interactive mode**, and every single iteration starts with a
**completely fresh context window**. The agent has no memory of the previous
iteration except what's sitting on disk.

```bash
while :; do
  cat PROMPT.md | claude --dangerously-skip-permissions -p
done
```

That's the whole mechanism. Everything else — the md files, the directory
layout, the "backpressure" — exists purely to answer one question: **if the
agent wakes up with zero memory every single time, how does it know what to
do next and not repeat/undo its own past work?**

The answer is: the filesystem *is* the memory. Specifically:
- **git history** — the actual, ground-truth record of what changed
- **A handful of markdown files** — the agent's working memory, rewritten to
  disk at the end of every iteration
- **Automated checks (tests/build/lint)** — "backpressure" that rejects bad
  work before it gets committed, so a confused iteration can't quietly
  corrupt state for the next one

Because there's no persistent process managing state, there's no plugin
required. The loop is just a shell script; the "state machine" is just files.

---

## Directory layout

```
my-project/
├── PROMPT.md                 # the one file fed to the agent every iteration
├── AGENTS.md                 # (or AGENT.md/CLAUDE.md) — how to build/test/run
├── IMPLEMENTATION_PLAN.md    # the living task list / state file
├── specs/
│   ├── overview.md           # what you're building, stack, non-goals
│   ├── <feature>.md          # one file per feature/subsystem
│   └── ...
├── progress.md               # append-only log the agent writes each loop
├── ralph.sh                  # the loop script itself
└── src/                      # your actual codebase
```

Some implementations tuck the Ralph-specific files into a `.ralph/` or
`.agent/` subfolder to keep the project root clean. Either works — what
matters is that the paths are stable so every iteration finds the same files.

---

## The files, one at a time

### 1. `PROMPT.md` — the instruction set, re-read every iteration

This is the only thing piped into the agent each loop. Keep it short and
directive — every extra sentence here is a fixed tax paid on every single
iteration, forever. Its job is to tell the agent, cold, with no conversation
history:

- what to read first (in order)
- how to pick the next task
- that it does **exactly one task** per iteration
- what "done" looks like for a task
- to run the backpressure checks before committing
- to update the plan/progress files before exiting

A minimal but complete example:

```markdown
# PROMPT.md

You are working autonomously on this codebase. You have no memory of
previous runs — everything you need is in these files. Read them in order:

1. AGENTS.md — build/test commands and conventions
2. specs/*.md — the requirements you're implementing against
3. IMPLEMENTATION_PLAN.md — the current task list and state

## Your job this iteration

- Pick the SINGLE highest-priority unchecked item in IMPLEMENTATION_PLAN.md.
- Search the codebase first — do not assume something isn't implemented.
- Implement it FULLY. No placeholders, no TODOs, no stubs.
- Run the test/build commands from AGENTS.md. Do not proceed until they pass.
- If you discover new work, a bug, or a gotcha, add it to
  IMPLEMENTATION_PLAN.md (or AGENTS.md if it's a durable convention).
- Check the item off in IMPLEMENTATION_PLAN.md.
- Append one or two lines to progress.md describing what you did and why.
- Commit: `git add -A && git commit -m "<summary>"`.
- Do ONLY the one item. Then stop.
```

Split into two if you're following the plan/build pattern (common in most
real-world Ralph setups):

- `PROMPT_plan.md` — reads `specs/*.md` + existing code, does gap analysis,
  (re)writes `IMPLEMENTATION_PLAN.md`. No code changes.
- `PROMPT_build.md` — reads the plan, implements exactly one item, tests,
  commits.

You run the plan prompt for a few iterations first, review the plan by hand,
then switch the loop to the build prompt.

### 2. `AGENTS.md` (or `AGENT.md`/`CLAUDE.md`) — the operating manual

This is not a task list — it's durable, slow-changing knowledge about *how
this specific codebase works*. Because the agent reads it fresh every
iteration, it's the only place "lessons learned" can accumulate over hundreds
of runs. Contents:

- exact build/test/lint/typecheck commands (the actual backpressure checks)
- project structure / where things live
- coding conventions and patterns already in use ("use the `Result<T,E>`
  helper in `src/util/result.ts`, don't roll your own error type")
- gotchas discovered by past iterations ("changing the schema requires
  running `make migrate` — the agent forgot this three times before this
  line was added")
- explicit prohibitions added after watching Ralph go wrong — Huntley calls
  these "signs": short, blunt, capitalized corrections like
  `FULL IMPLEMENTATIONS ONLY. NO PLACEHOLDERS.` or `DO ONE ITEM ONLY.`

Example skeleton:

```markdown
# AGENTS.md

## Build & test
- Install: `npm ci`
- Typecheck: `npm run typecheck`
- Test: `npm test`
- Build: `npm run build`
All four must pass before committing.

## Conventions
- State management: Zustand stores in `src/stores/`, one per domain.
- API calls go through `src/lib/api.ts`, never raw `fetch()` elsewhere.
- Every new endpoint needs a corresponding test in `tests/api/`.

## Gotchas
- Editing `schema.prisma` requires `npx prisma generate` before typecheck
  will pass.
- The dev server must be restarted after changing `.env` — it does not
  hot-reload env vars.

## Signs (things Ralph kept getting wrong)
- FULL IMPLEMENTATIONS ONLY. NO PLACEHOLDER FUNCTIONS OR "TODO: implement".
- Search the codebase before assuming something doesn't exist yet.
- ONE task per iteration. Do not batch multiple checklist items.
```

Prune this file periodically. If it grows into a wall of contradictory
signs, that's the signal to sit down, re-tune it, and cut it back down —
an overloaded AGENTS.md degrades every future iteration.

### 3. `IMPLEMENTATION_PLAN.md` (a.k.a. `fix_plan.md`) — the actual state

This is the one file that changes constantly and is the closest thing Ralph
has to "memory." It's a checklist, ideally ordered by priority, granular
enough that one item = one iteration's worth of work.

```markdown
# IMPLEMENTATION_PLAN.md

## In progress / next up
- [ ] Add password-reset email flow (see specs/auth.md)
- [ ] Add rate limiting to /api/login

## Done
- [x] User signup endpoint
- [x] Session cookie handling

## Discovered along the way
- [ ] `src/lib/mailer.ts` has no retry logic — needed once reset emails ship
```

Treat this file as **disposable**. If the agent goes off the rails or the
plan drifts from reality, the fix is usually to delete/regenerate it from
`specs/*.md`, not to hand-patch a confused plan. Regenerating a plan is
cheap; debugging a stale one across dozens of iterations isn't.

### 4. `specs/*.md` — the requirements, one concern per file

These are the durable "what are we building" documents — they change rarely,
and they're what the plan gets regenerated *from*. Split by concern so the
agent (and you) can reason about one thing at a time:

- `specs/overview.md` — stack, high-level features, explicit **non-goals**
- `specs/data-model.md` — schema, entities, relationships
- `specs/api.md` — endpoints, request/response shapes
- `specs/<feature>.md` — one per major feature

Each should be detailed enough that a competent developer (or agent) could
implement it without asking a follow-up question. Vague specs are the #1
cause of a Ralph loop wandering — spend real time here before starting the
loop, the same way you'd invest in a PRD before assigning work to a person.

### 5. `progress.md` — append-only journal

Optional but genuinely useful once you're running dozens+ of iterations
unattended overnight. The prompt instructs the agent to append (never
rewrite) a couple of lines per iteration: what it did, and — more
importantly — *why*, especially for anything surprising or hard. This is
where you get a human-readable trail of what an overnight run actually did
when you check in the next morning, without reading the entire git log.

```markdown
## Iteration 47
Implemented rate limiting on /api/login using a token bucket in Redis.
Chose Redis over in-memory because two app instances run behind the LB —
in-memory would let each instance let through 2x the intended rate.
```

### 6. `ralph.sh` — the loop itself (no plugin required)

```bash
#!/usr/bin/env bash
set -euo pipefail

MAX_ITERATIONS="${1:-100}"
LOG_DIR="logs"
mkdir -p "$LOG_DIR"

for i in $(seq 1 "$MAX_ITERATIONS"); do
  echo "=== Ralph iteration $i/$MAX_ITERATIONS ==="

  # Fresh context every time: pipe the prompt into a NEW headless invocation.
  cat PROMPT.md | claude --dangerously-skip-permissions -p \
    2>&1 | tee "$LOG_DIR/iteration-$i.log"

  # Backpressure: don't loop forever on top of a broken build.
  if ! npm run build >/dev/null 2>&1; then
    echo "Build broken after iteration $i — stopping for review."
    exit 1
  fi

  # Stop condition: no unchecked items left in the plan.
  if ! grep -q '^- \[ \]' IMPLEMENTATION_PLAN.md; then
    echo "No unchecked items remain — Ralph is done."
    break
  fi
done
```

Adjust the agent invocation for whichever CLI you're driving (`claude -p`,
`amp`, `codex exec`, `opencode run`, etc.) — the loop logic doesn't care.
Swap in your own build/test command for the backpressure check.

---

## Backpressure — the part that actually keeps this from going off a cliff

"Backpressure" just means: automated checks that must pass before a commit
is allowed to stick. Without it, a hallucinating iteration commits broken
code, and the *next* iteration inherits that brokenness as if it were
ground truth — errors compound instead of getting caught.

Layer it:
1. Typecheck — catches an entire class of nonsense immediately
2. Tests — verifies actual behavior, not just "it compiles"
3. Build — catches anything the above missed
4. (Optional) LLM-as-judge — for subjective acceptance criteria a script
   can't check (visual polish, tone, UX feel), have a second agent call
   grade the output pass/fail against a rubric in the spec

`PROMPT.md` should say explicitly: run these checks, and do not commit
until they're green. `AGENTS.md` should say exactly which commands those
are for this project.

---

## Running it

1. Write `specs/*.md` by hand (or via a normal, human-in-the-loop
   conversation with the agent first — don't skip straight to autonomous
   mode with vague requirements, it's the single biggest failure cause).
2. Write `AGENTS.md` with real build/test commands.
3. Seed `IMPLEMENTATION_PLAN.md`, either by hand or by running a
   "plan" prompt once against the specs.
4. `chmod +x ralph.sh`, then `./ralph.sh 50` to cap it at 50 iterations.
5. Watch the first several iterations. When Ralph does something wrong,
   don't fix the code by hand and move on — add a "sign" to `PROMPT.md` or
   `AGENTS.md` so the *next* iteration doesn't repeat the mistake. That
   feedback loop, more than anything else, is what tuning a Ralph setup
   actually is.

---

## Key things to keep in mind

- **Fresh context is the whole point.** If you're tempted to keep one
  long-lived session alive and just feed it reminders, you're not running
  Ralph — you're running a regular agent session with extra steps. The
  fresh-context-per-iteration is what prevents context rot and keeps every
  loop deterministic and debuggable in isolation.
- **One task per iteration.** It's counterintuitive, but batching multiple
  checklist items per loop is one of the most common causes of things going
  sideways — smaller, verifiable, committed increments compound; large ones
  don't.
- **Plans are disposable, specs are not.** Regenerate `IMPLEMENTATION_PLAN.md`
  freely. Guard `specs/*.md` more carefully — that's your actual source of
  truth.
