# AGENTS.md — laze.nvim

Laze is a tiny compiler that transforms a well-defined subset of
lazy.nvim specs into `vim.pack` specs and a minimal execution plan.
It delegates installation, placement, tag/ref resolution, and dependency
handling to Neovim's native `vim.pack`; laze lowers lazy.nvim ranges/refs to
its `version` field. Philosophy and output model:
[docs/design.md](docs/design.md).

## Scope

Implements only a subset of lazy.nvim. Everything beyond the core
(compile → plan → setup) is an opt-in module in `lua/laze/` (`extra.lua`),
never required by the core and free unless loaded. Compatibility is pinned
to the lazy.nvim spec documented as of 2026-08-18 (`tests/test_subset.lua`),
not to every upstream change.

Supported spec fields: [README § Spec shape](README.md#spec-shape) —
mechanically pinned by `tests/test_subset.lua` (every laze-consumed
field must be a documented lazy.nvim spec field or a justified
exception in compile.lua). Update both when the surface changes.

Explicitly out of scope (do not add):

* Dependency solver, plugin manager UI, install/update commands in the core
  (opt-in `:Laze` wrappers live in `lua/laze/extra.lua`)
* `opts` abstraction, import system
* `require()` hook interception — `module` triggers are
  `package.preload` entries (the global `require` is never touched)
* Runtime plugin state manager, background scheduler, lifecycle framework

## Subset discipline

**Core principle: the target representation must not dictate source
semantics.** laze's public spec is lazy.nvim-shaped; `vim.pack` is the target
IR. Compile lowers one to the other. vim.pack's shape (e.g. its single
`version` field) is an encoding detail, not a licence to redefine a lazy.nvim
field.

- Shared fields keep lazy.nvim's name, type, and meaning unless the deviation
  is an explicit, documented, tested exception (e.g. `module`). Never overload
  a shared field with a target-specific meaning: lazy.nvim's `version` is a
  semver range, refs are `branch`/`tag`/`commit`; vim.pack's single `version`
  is the lowering target. Lower explicitly; sniff only to reject a value,
  never to reclassify it (e.g. `version = "main"` is an error, not a branch).
- Maximize the *faithful* subset, not raw acceptance: accept as much lazy.nvim
  surface as can be represented with identical behavior. If a case cannot be
  represented faithfully, fail loudly (compile error) or document the exact
  conversion — never a silent drop or best-effort approximation. A warning
  that ignores the field is still a silent drop.
- Extensions are outside the subset: use explicit, non-colliding names,
  document what happens when the spec moves back to lazy.nvim, and don't let
  them change shared-field semantics.
- Differences are inevitable (vim.pack owns resolution). Make them explicit in
  docs and tests. `tests/test_subset.lua` pins the surface; semantic cases
  (precedence, range vs ref, `version = false`) need explicit tests too.

## Structure

```
lua/laze/init.lua      — Public API: compile(), build_plan(), setup(), reload_all()
lua/laze/compile.lua   — Spec → IR transformation
lua/laze/plan.lua      — Thin execution plan (trigger wiring, lazy loading)
lua/laze/extra.lua      — Opt-in: :Laze subcommands (update/clean/health/reload) + public helpers
docs/                  — design / extras / commands / migration / performance
tests/run.lua              — Test runner incl. perf suite: nvim --cmd "set rtp+=." -l tests/run.lua [perf]
tests/test_compile.lua     — Standalone unit tests (luajit tests/test_compile.lua)
tests/test_subset.lua      — Spec-surface conformance vs lazy.nvim docs
tests/test_e2e.lua         — Manual e2e harness with real plugins (run instructions in file header)
tests/update_snapshots.lua — Snapshot generator (regenerates tests/snapshots/*.lua)
tests/fixtures/            — Input specs (*.lua); _sentinel.lua = FN sentinel
tests/snapshots/           — Auto-generated expected outputs (compare against)
tests/benchmarks/          — Manual benchmarks (commands in docs/performance.md)
tests/profile/             — Manual profile harness with real plugins
```

Types (LuaCATS) are defined in code: `lua/laze/init.lua` (`LazeSpec`,
`LazeCompiled`, `LazeEntry`, `LazeRoutes`, `LazePlan`).

## Conventions

- Pure transforms in compile, minimal logic in plan
- compile must never mutate input spec tables (dependency-derived `after` names live in a side table); re-compiling the same specs must be deterministic
- No global state; plan uses closure-local state (`loaded` table). Documented exceptions: (1) `setup()` keeps the last specs/opts (module-local in init.lua) so `reload_all()` can rebuild the plan; (2) plan.lua keeps `installed_preloads` module-local so a rebuilt plan can clear stale `package.preload` entries on reload. The plan itself stays closure-local.
- Error handling via `pcall` + `vim.notify(..., vim.log.levels.WARN)` — never throw in plan
- `cond: nil` → no condition (always load). `cond` returning `false` → skip load. Plugins with no triggers and `cond = false` stay unloaded permanently.
- Activation: `setup()` splits the pack by `has_route`/`is_dep` — eager plugins via `vim.pack.add(..., { load = false })` (`:packadd!`, startup phases source their files), lazy plugins via a no-op `load` fun (never on rtp). The plan is the sole activator — **activation invariant**: `vim_did_enter == 0` → `:packadd!` only (the startup `plugin/`/`after/plugin/` phases source files exactly once); `vim_did_enter ~= 0` → `:packadd` + manual sourcing of the plugin's own `after/plugin/` files. Breaking this yields double-source or missing files; the startup-phase test in `tests/run.lua` asserts it via spawned sessions (keep it green).
- "Eager" = no trigger AND not referenced as an `after` dep (`has_route`/`is_dep`, computed at compile time and shared by `setup()`'s pack split and the plan's eager list).
- Dependencies are never eager on their own: they load via their parents (`is_dep`). Matches lazy.nvim's "dependencies are always lazy-loaded unless specified otherwise".
- Spec validation: unknown fields are passed through to `vim.pack.Spec`, error on type mismatch
- Trigger shapes (`event`/`ft`/`cmd`/`keys`): accept `string`/`string[]` (+ lazy.nvim's `{event, pattern}` for `event`, `{lhs, mode?|[{string}]...}` for `keys`); function-shaped triggers are rejected with a compile error — silently normalizing them to "no trigger" would turn a lazy plugin eager (`validate_triggers` in compile.lua)
- Trigger self-destruct: commands use `CmdUndefined` autocmd (stateless), keys delete the trigger map *before* loading (del removes every map for the lhs — deleting after load would kill the plugin's own map) and then `nvim_feedkeys` the replay
- Module triggers: single-shot `package.preload` entries; the preload fn clears nvim's in-flight `package.loaded` sentinel before loading so the declared module is actually requirable (regression-tested in run.lua)
- `VeryLazy` → fires `User VeryLazy` via `UIEnter` (GUI, one-shot), or immediately when the plan runs post-startup (`vim_did_enter ~= 0`) or headless (`nvim_list_uis()` empty) — the one-shot would otherwise be dead
- `priority` (number, default 50) orders the eager load: higher first, tie-break id — lazy.nvim-compatible colorscheme-first workflow
- `after` deps: recursive with cycle detection

## Tests

```sh
nvim --cmd "set rtp+=." -l tests/run.lua        # integration (incl. spawned sessions + perf)
nvim --cmd "set rtp+=." -l tests/run.lua fast   # single session (skips spawned startup/build/pkg tests)
nvim --cmd "set rtp+=." -l tests/run.lua perf   # perf regression suite only
luajit tests/test_compile.lua                   # unit, no nvim needed
luajit tests/test_subset.lua                    # spec-surface conformance
```

- Fixture pattern: `fixtures/foo.lua` (input specs) + `snapshots/foo.lua` (expected `LazeCompiled`)
- Use the `FN` sentinel for function fields in expected output; runner deep-compares with sentinel-aware type checking
- Regenerate snapshots: `nvim --cmd "set rtp+=." -l tests/update_snapshots.lua`
- Perf thresholds are asserted inside `tests/run.lua perf`; benchmarks for manual profiling are documented in [docs/performance.md](docs/performance.md)

## Commit style

- Present tense, concise, single line + optional body
