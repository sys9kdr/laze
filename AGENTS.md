# AGENTS.md — laze.nvim

laze lowers a documented subset of lazy.nvim specs into `vim.pack` specs and
a small execution plan. It does not own installation, tag/ref resolution, or
dependency solving — `vim.pack` does. Philosophy and the output model live in
[docs/design.md](docs/design.md); the supported field list is
[README § Spec shape](README.md#spec-shape).

## Scope

The core is compile → plan → setup. Everything beyond that is an opt-in
module under `lua/laze/extras/` that the core never requires.

Out of scope (do not add): a dependency solver, a plugin-manager UI,
install/update commands in the core, lazy.nvim's fragment/`opts` merge
pipeline, the import system, `require()` hook interception, and a runtime
lifecycle framework.

## Subset discipline

- **The target representation must not dictate source semantics.** The public
  spec is lazy.nvim-shaped; `vim.pack` is the target IR. Shared fields keep
  lazy.nvim's name, type, and meaning. Never overload a shared field with a
  target-specific meaning — lower explicitly (e.g. semver `version` vs
  `branch`/`tag`/`commit`).
- **Maximize the faithful subset.** If a case cannot be represented with the
  same behavior, fail loudly at compile time or document the exact
  conversion. A warning that ignores the field is still a silent drop.
- **Extensions live outside the subset.** Use non-colliding names, document
  the reverse migration to lazy.nvim, and never change shared semantics.
- **Differences are explicit.** [docs/known-differences.md](docs/known-differences.md)
  is canonical; `tests/fixtures/known_differences.lua` mirrors it. IDs are
  stable (never reuse a retired ID). Only `notify = "compile"` entries get a
  runtime message, from `lua/laze/known_differences.lua`.

When a laze behavior and lazy.nvim disagree, measure lazy.nvim first and make
the test the oracle; do not trust an issue's assumed behavior. Source reading
alone is not enough: run lazy.nvim and inspect the state laze actually
consumes (`Config.plugins[name].lazy`, raw spec fields, resolved handlers).
The probe recipe and its gotchas live in
[`.opencode/skills/lazy-oracle/SKILL.md`](.opencode/skills/lazy-oracle/SKILL.md).
Record the measured result in a test comment next to the upstream file path.

## Structure

```
lua/laze/init.lua             public API: compile, build_plan, setup, reload_all
lua/laze/compile.lua          pure spec -> IR transform
lua/laze/plan.lua             trigger wiring / lazy loading
lua/laze/known_differences.lua compile-time KD messages
lua/laze/extra.lua            opt-in :Laze public entry point
lua/laze/extras/              opt-in implementation (maintenance, commands)
docs/                         design, extras, commands, migration, known differences
tests/run.lua                 integration + perf suite
tests/test_compile.lua        standalone unit tests (luajit)
tests/test_subset.lua         spec-surface conformance (luajit)
tests/fixtures/, tests/snapshots/  input specs and generated expected IR
tests/benchmarks/, tests/profile/  manual benchmarks
.opencode/skills/             project skills (lazy.nvim measurement recipe)
```

Types (LuaCATS) are defined in code: `lua/laze/init.lua` (`LazeSpec`,
`LazeCompiled`, `LazeEntry`, `LazeRoutes`, `LazePlan`).

## Invariants (tests are the source of truth)

| Invariant | Owner |
| --- | --- |
| compile never mutates input; repeated compiles are deterministic | `tests/test_compile.lua`, `tests/run.lua` |
| the consumed spec surface is a documented lazy.nvim subset | `tests/test_subset.lua` |
| activation is exactly-once: startup `:packadd!` phases vs post-startup `:packadd` + `after/plugin` sourcing | `tests/run.lua` spawned startup tests |
| dependencies are lazy; `after` is recursive and cycle-checked | `tests/test_compile.lua` |
| trigger shapes, self-destruct/replay, and module preload behavior | `tests/run.lua`, `tests/test_compile.lua` |
| key routes are per `(lhs, mode, ft)`; `ft` is buffer-local | `tests/run.lua`, `tests/test_compile.lua` |
| `VeryLazy` fires once (UIEnter / immediate post-startup / headless) | `tests/run.lua` |
| known-difference registry, docs, and runtime messages stay in sync | `tests/test_subset.lua` |
| static Lua issues (syntax, undefined globals, unused locals) | `luacheck lua tests` |

Do not describe exact behavior here twice: update the owning test (and the
referenced doc) instead.

## Conventions

- Pure transforms in compile; minimal logic in plan.
- Dependency-derived `after` names live in a side table, never on the user's
  spec. Documented global state exceptions only: `setup()` remembers the last
  specs/opts for `reload_all()`, and plan keeps `installed_preloads` so a
  rebuild can clear stale `package.preload` entries. The plan itself is
  closure-local.
- Plan errors are handled with `pcall` + `vim.notify(..., WARN)`; the plan
  never throws.
- `cond: nil` means no condition; `cond` returning false skips the load.
  `enabled`/`cond` are resolved once before `vim.pack.add`, so a false
  verdict also skips installation.
- Known-difference messages are deduped per compile and can be silenced with
  `{ known_differences = false }`.
- Fixtures use the `FN` sentinel for functions. Regenerate snapshots with
  `nvim --cmd "set rtp+=." -l tests/update_snapshots.lua`. Adding a fixture
  means registering it in both `tests/test_compile.lua` (the fixtures list)
  and `tests/update_snapshots.lua` *before* regenerating, otherwise the unit
  test cannot load the new snapshot.
- Promoting a lazy.nvim field from unsupported to supported touches:
  [README § Spec shape](README.md#spec-shape) and its notes,
  [docs/migration.md](docs/migration.md), [docs/not-have.md](docs/not-have.md)
  (section and out-of-scope list), `tests/test_subset.lua` semantic notes,
  [docs/known-differences.md](docs/known-differences.md) (retire IDs), and
  this file's out-of-scope list. Run the whole suite afterwards.

## Commands

```sh
nvim --cmd "set rtp+=." -l tests/run.lua        # integration (+ spawned + perf)
nvim --cmd "set rtp+=." -l tests/run.lua fast   # single session
nvim --cmd "set rtp+=." -l tests/run.lua perf   # perf regression only
luajit tests/test_compile.lua                   # unit, no nvim
luajit tests/test_subset.lua                    # spec-surface conformance
luacheck lua tests                              # static lint (1.2.0)
```

Luacheck is pinned to 1.2.0. Install it with
`sudo luarocks install luacheck 1.2.0-1` (or your distro package); no Rust
toolchain is needed. Selene was evaluated but its prebuilt binary cannot
parse the LuaJIT `goto`/labels used by the tests.

Vendored lazy.nvim tests are an optional behavioral oracle, not CI:
`LAZY_DIR=/tmp/lazy.nvim tests/vendor/lazy.nvim/run.sh`.

## GitHub

`main` is protected by the `protect-default` ruleset (deletion,
non-fast-forward, pull request): direct pushes are rejected with `GH013`.
Push a branch and open a PR with `gh pr create`; merge with `gh pr merge`.
The SSH remote lacks write access in this environment, so push over HTTPS:
`git -c credential.helper='!gh auth git-credential' push <https-url>`.
`git push --dry-run` does not exercise server-side rules; verify protection
with a throwaway commit and reset.

## Commit style

Present tense, concise, single line plus an optional body.
