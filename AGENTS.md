# AGENTS.md — laze.nvim

Laze compiles a documented subset of lazy.nvim specs into `vim.pack` specs and
a small execution plan. Neovim owns installation, placement, ref resolution,
and dependency handling. See [docs/design.md](docs/design.md) for the output
model and design rationale.

## Project boundaries

- The public spec stays lazy.nvim-shaped; `vim.pack` is only the target IR.
  Lower shared fields explicitly and preserve their lazy.nvim meaning.
- Prefer faithful support. If behavior cannot be represented, reject it or
  document the exact conversion; do not silently drop or approximate it.
- Features beyond compile → plan → setup belong in opt-in `lua/laze/extra.lua`.
- Do not add a dependency solver, core manager UI/commands, `opts` abstraction,
  imports, `require()` interception, or runtime state/scheduling framework.
- Compatibility follows the pinned spec surface in `tests/test_subset.lua`,
  not every upstream lazy.nvim change.

The supported fields are listed in [README § Spec shape](README.md#spec-shape).
When changing that surface, update the README, compiler, and subset tests
together. Laze-specific exceptions need an explanation in the compiler and
documentation of their lazy.nvim portability.

## Where behavior is specified

Keep exact, machine-checkable behavior in tests. Use these sources when changing
behavior instead of copying their full inventories into this guide:

- Spec fields, conversions, and known differences: `tests/test_subset.lua`,
  `tests/fixtures/known_differences.lua`, and
  [docs/known-differences.md](docs/known-differences.md).
- Pure compilation, validation, dependency expansion, and deterministic output:
  `tests/test_compile.lua` and `tests/snapshots/`.
- Trigger routing, loading, reloads, and runtime behavior:
  `tests/run.lua`.
- Startup activation and exactly-once plugin/after-plugin sourcing:
  the spawned-session startup-phase checks in `tests/run.lua`. Preserve the
  invariant described in [docs/design.md](docs/design.md#the-activation-invariant).

When a behavior changes, update or add its test and the relevant user-facing
docs. Do not rely on this file as the only record of a runtime contract.

## Implementation guardrails

- Keep compilation pure: never mutate input spec tables; keep derived state in
  side tables; repeated compilation of the same input must be deterministic.
- Keep plan state closure-local. The documented module-local exceptions are
  setup's saved specs/options for `reload_all()` and installed preload tracking
  for clearing stale module triggers.
- Plan callbacks must not throw: handle failures with `pcall` and report through
  `vim.notify(..., vim.log.levels.WARN)`.
- Preserve the startup activation split: before `VimEnter`, eager plugins use
  `:packadd!` so startup phases source files once; after startup, use `:packadd`
  and manually source the plugin's own `after/plugin/` files.
- Keep dependencies lazy unless a parent activates them. `after` dependencies
  load recursively, with cycle detection.
- Reject unsupported function-shaped triggers at compile time; turning one into
  no trigger can accidentally make a plugin eager.

## Tooling and checks

Selene is the provisional lint candidate; adoption and CI wiring are tracked in
[Issue #35](https://github.com/sys9kdr/laze/issues/35). Do not assume a lint
command or config exists until that issue is implemented. Once wired, keep the
version pinned and document a local install path that does not require Rust.

Run the relevant checks before submitting code:

```sh
luajit tests/test_compile.lua
luajit tests/test_subset.lua
nvim --cmd "set rtp+=." -l tests/run.lua
```

`tests/run.lua fast` skips spawned-session checks; `tests/run.lua perf` runs
only performance regression checks. Regenerate snapshots with:

```sh
nvim --cmd "set rtp+=." -l tests/update_snapshots.lua
```

## Changes to the supported surface

- Every laze-consumed spec field must be documented by lazy.nvim or justified
  as an explicit exception in `lua/laze/compile.lua`.
- Keep known-difference entries synchronized between the docs and fixture; add
  a stable `KD-xxx` ID and a test reference for each, following
  [the message policy](https://github.com/sys9kdr/laze/issues/12).
- Use the `FN` sentinel in snapshots for function fields.

## Commits

Use a concise, present-tense subject; add a body only when it clarifies intent.
