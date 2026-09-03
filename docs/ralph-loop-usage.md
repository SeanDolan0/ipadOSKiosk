# Ralph Loop Usage on the Local Qwen Agent

## What the Ralph loop is
A self-referential development loop (plugin: `ralph-loop`). It feeds the SAME prompt
back after each iteration, so the agent iteratively improves toward a completion
message. State file: `.claude/ralph-loop.local.md`.

Invocation (from the harness prompt / CLI):
```
/ralph-loop YOUR_PROMPT [--max-iterations N] [--completion-promise 'TEXT']
```
- No `--completion-promise` → runs forever (use `--max-iterations` to bound it).
- Stop only via hitting `--max-iterations` or outputting `<promise>TEXT</promise>`.
- The loop WILL NOT lie to exit — that is a hard rule of the plugin.

## Why the user runs the local Qwen on a loop here
- The 27B Q2 model is memory/CPU-bound; letting it self-iterate on one task in a
  branch (instead of being babysat) matches the "I can't monitor it" concern.
- The loop writes its work to files/git history, which is reviewable later.

## Recommended safe pattern for THIS branch (bounded, monitored)
```
/ralph-loop "Improve the README of this repo's scripts/agent/ directory" --max-iterations 5
```
Bounded loops are safer than unlimited on a slow local model. Prefer a scope the
model can plausibly finish, so it does not churn forever on ~1 token/sec.

## Command reference (from ralph-loop plugin help)
```
--max-iterations <n>           0 = unlimited (default)
--completion-promise '<text>'  exact phrase the loop greps for to stop
```

## On this branch — recommended loop tasks (examples only)
- Iterate on `scripts/agent/serve.ps1` correctness until it starts clean.
- Improve the `AI_AGENT_ENV.md` documentation for readability.
- Generate a test prompt-set for the local model and evaluate outputs.
Do NOT point the loop at Gecko engine work (that lives on `Gecko-Rewrite`).
