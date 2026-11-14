# AGENTS.md — laze.nvim

laze is a thin wrapper around `vim.pack`: it compiles a documented subset of lazy.nvim specs into `vim.pack` specs and a small execution plan.
Installation stuff stays with `vim.pack`.

- Design: docs/design.md
    - docs/not-have.md
    - docs/known-differences.md (registry: tests/fixtures/known_differences.lua)
- Spec surface: docs/design.md#spec-shape
- Docs policy:
    - `docs/` is the user-facing contract; implementation notes live in `docs/internal/`.
    - `docs/internal/performance.md` is the single ledger for measurements and rejected ideas.
    - No ADR numbering or one-off design notes: fold durable facts into the current contract or the perf ledger, then delete the note.
    - Roles: `design.md` = architecture; `spec.md` = field behavior; `migration.md` = lazy.nvim deltas; `not-have.md` = non-goals. Link instead of restating.
- Tests are the source of truth for behavior.
  When laze and lazy.nvim disagree, measure lazy.nvim first; see .agents/skills/lazy-oracle/SKILL.md.
  When a perf claim (JIT or otherwise) is at stake, measure in fresh processes; see .agents/skills/perf-tuning/SKILL.md.

## Commands

Dev commands live in the Makefile.

## Commit style

Use present tense.
Keep it to a concise single line, plus an optional body.
