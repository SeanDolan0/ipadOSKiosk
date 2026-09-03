# Archived Gecko Phase 0 loop target

The `ralph-gecko` loop was re-pointed to a safe sandbox task (hardening
`scripts/agent/serve.ps1`) as part of reconciling the `qwen-local-agent` branch
(`AI_AGENT_ENV.md`: this branch is a sandbox; do not point the loop at Gecko engine
work, which lives on `Gecko-Rewrite`).

These files documented the **prior** Gecko Phase 0 (build `libxul` for
`arm64-apple-ios12.0`) target. They are preserved here for reference and are fully
recoverable from git history. To restore them:

```
git mv ralph-gecko/archive-gecko-target/specs/overview.md ralph-gecko/specs/overview.md
git mv ralph-gecko/archive-gecko-target/specs/phase0-libxul.md ralph-gecko/specs/phase0-libxul.md
git mv ralph-gecko/archive-gecko-target/IMPLEMENTATION_PLAN.gecko.md ralph-gecko/IMPLEMENTATION_PLAN.md
```

See `GECKO_REWRITE_HANDOFF.md` (repo root) and also Gecko-for-iOS design/handoff:
`docs/superpowers/specs/2026-09-02-gecko-rewrite-design.md`.
