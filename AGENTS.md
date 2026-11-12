# AGENTS.md — laze.nvim

laze is a thin wrapper around `vim.pack`: it compiles a documented subset of lazy.nvim specs into `vim.pack` specs and a small execution plan. Installation, tag/ref resolution, and dependency solving stay with `vim.pack`.

- Design: docs/design.md
- Spec surface: README.md#spec-shape
- Out of scope: docs/not-have.md
- Known differences: docs/known-differences.md
- Tests are the source of truth for behavior. When laze and lazy.nvim disagree, measure lazy.nvim first; see .agents/skills/lazy-oracle/SKILL.md. When a perf claim (JIT or otherwise) is at stake, measure in fresh processes; see .agents/skills/perf-tuning/SKILL.md.

## Module design

Deepen modules and simplify interfaces. A module should hide a real mechanism behind a narrow entry point; pass each call only the values it needs, never a ctx bag of the caller's state. Adding a module has to buy that: moving code between eagerly-required files is parse-neutral, so cold bodies move behind an inline `require` only when the interface stays small (docs/performance.md). Keep plan-private mechanisms (loader state, `package.preload` wiring) in plan.lua rather than widening a module to shave a few µs.

## Commands

```sh
nvim --cmd "set rtp+=." -l tests/run.lua        # integration (+ spawned + perf)
nvim --cmd "set rtp+=." -l tests/run.lua fast   # single session
nvim --cmd "set rtp+=." -l tests/run.lua perf   # perf only
nvim --clean -l tests/test_compile.lua          # unit (luajit also works)
nvim --clean -l tests/test_subset.lua           # spec-surface conformance
selene lua                                      # static lint, production
selene --config tests/selene.toml tests         # static lint, tests
stylua .                                        # format (pinned StyLua)
stylua --check .                                # formatting check (CI)
```

## Commit style

Use present tense. Keep it to a concise single line, plus an optional body.
