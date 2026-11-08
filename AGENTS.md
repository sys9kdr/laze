# AGENTS.md — laze.nvim

laze is a thin wrapper around `vim.pack`: it compiles a documented subset of lazy.nvim specs into `vim.pack` specs and a small execution plan. Installation, tag/ref resolution, and dependency solving stay with `vim.pack`.

- Design: docs/design.md
- Spec surface: README.md#spec-shape
- Out of scope: docs/not-have.md
- Known differences: docs/known-differences.md
- Tests are the source of truth for behavior. When laze and lazy.nvim disagree, measure lazy.nvim first; see .agents/skills/lazy-oracle/SKILL.md.

## Commands

```sh
nvim --cmd "set rtp+=." -l tests/run.lua        # integration (+ spawned + perf)
nvim --cmd "set rtp+=." -l tests/run.lua fast   # single session
nvim --cmd "set rtp+=." -l tests/run.lua perf   # perf only
luajit tests/test_compile.lua                   # unit, no nvim
luajit tests/test_subset.lua                    # spec-surface conformance
luacheck lua tests                              # static lint
```

## Commit style

Use present tense. Keep it to a concise single line, plus an optional body.
