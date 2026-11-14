# What laze doesn't have (and won't)

For evaluating laze vs lazy.nvim.
Every item below is grounded in the code or a measured doc — not a roadmap.
Sources: `lua/laze/compile.lua` (`UNSUPPORTED_FIELDS`, `validate_spec`, `validate_triggers`), `tests/test_subset.lua` (semantic notes), `docs/design.md`, `docs/migration.md`, `docs/internal/performance.md` (Rejected sections), `docs/internal/startup-lazy-activation.md` (proxy limitation).
The known-difference registry is [`tests/fixtures/known_differences.lua`](../tests/fixtures/known_differences.lua); classes and policy are in [known-differences.md](known-differences.md).

## Who laze is for (and who it is not for)

laze exists so a hand-written lazy.nvim-style config keeps working on top of Neovim's native `vim.pack`.
It is a small compatibility layer, not a general plugin manager: installation, ref/tag resolution, and dependency solving stay with `vim.pack`.

**Intended user.** You write (or copy) specs by hand — often from a plugin README — and want:

* lazy.nvim's declarative spec shape for the common fields, with lazy-loading on `event` / `cmd` / `ft` / `keys` / `module`;
* `vim.pack` to own installation, updates, and the lockfile;
* no dashboard, commands, or update UI in your startup path.

A design goal is a **cheap escape hatch**: the subset is chosen so that a laze config is also a valid lazy.nvim config.
When laze rejects an input, it does so loudly at compile time rather than silently changing behavior (the `safe-direction` class in [known-differences.md](known-differences.md)).
Moving back to lazy.nvim is mostly deleting `require("laze")` and calling `require("lazy").setup()` instead.

**Not targeted.** These are deliberate non-goals, not a roadmap: lazy.nvim's composition features (`opts` merging, `import`, automatic spec-file collection), a manager UI or command suite, reimplementing `vim.pack`, and silent emulation of inputs that would need guessing.
The sections below give the details and alternatives.

If your config depends on composition or a full manager UI, stay on lazy.nvim; porting the specs later is mechanical when you only need the declarative subset.
See [migration.md](migration.md) for the field-by-field conversion.

## Deliberate no

These are scope decisions, not missing features; the small-surface stance is in [design.md](design.md).
Out of scope: dependency solver, manager UI, install/update commands, lazy.nvim's fragment/`opts` merge pipeline, import system, background scheduler, lifecycle framework.

### UI / commands in core.

- What: no dashboard, update UI, install/update command surface in `setup()`.
- Why not: state ownership — the core is compile → plan → setup; runtime machinery belongs to opt-in modules.
- Alternative: `require("laze.extra").setup()` registers `:Laze` (`update`/`clean`/`health`/`reload`), or wire your own:

```lua
vim.api.nvim_create_user_command("Sync", function()
  vim.pack.update()
end, {})
```

### `import` / `specs` module system.

* What: `import` warns ("lazy.nvim-only; load spec files yourself"), `specs` warns ("no equivalent; inline your specs instead").
* Why not: state ownership — spec discovery is your config's job, not the compiler's.
* Alternative: load the modules yourself and pass the flattened table:

```lua
local ui = require("config.plugins.ui")
laze.setup({ { "foo/bar", event = "VeryLazy" }, unpack(ui) })
```

### `optional`

* What: consumed with a warning ("deps are always required; remove 'optional'").
* Why not: magic-vs-explicit — conditional inclusion via a flag hides the actual condition.
* Alternative: gate at the call site with `cond`/`enabled`:

```lua
{ "foo/bar", cond = function() return vim.fn.executable("rg") == 1 end }
```

### Function-shaped triggers

- What: `event`/`cmd`/`ft`/`keys` as a function is a compile error (`validate_triggers`).
- Why not: silently normalizing to "no trigger" would turn a lazy plugin eager — the worst failure mode.
- Alternative: spell the trigger list statically:

```lua
-- before: event = function() return cond and "BufRead" or nil end
{ "foo/bar", event = "BufReadPost", cond = function() return cond end }
```

### Background scheduler / lifecycle framework

- What: no timers, no deferred-task queue, no plugin-state manager beyond the closure-local `loaded` table in `plan.lua`.
- Why not: state ownership — scheduling policy belongs to your config.
- Alternative: your own autocmd/timer calls `load` via a trigger, or hooks on `build_plan`:

```lua
laze.build_plan(compiled, {
  on_load = function(id, ms) timings[id] = ms end,
})()
```

## Measured no (perf evidence)

Rejected with numbers in `docs/internal/performance.md`.
Each was A/B'd against the real function; re-proposing needs new measurements, not arguments.

### Async install

- What: no `vim.uv.spawn` around `vim.pack.add`.
- Why not: `vim.pack.add` guarantees synchronous install, so eager and trigger loads work in a first session; async complicates startup ordering for no startup win.
- Alternative: none needed — first-install blocking UX belongs to vim.pack; subsequent startups are warm.

### Dev auto-reload watching

- What: no `fs_event` watcher; `reload_all()` is manual.
- Why not: perf cost — process management, debouncing, recursion control for no gain over an explicit call.
- Alternative (three lines, your config owns it):

```lua
vim.api.nvim_create_user_command("LazeReloadAll", function()
  laze.reload_all()
end, {})
```

### Symlink-farm rtp consolidation

- What: no neobundle-style single-rtp-entry symlink tree.
- Why not: measured ~130–440 us saved at 30 plugins against a parallel source-of-truth (rebuild hooks on every install/update/del), loss of vim.pack activation, and silent symlink staleness. Lazy plugins already never touch rtp, and eager→lazy conversion (~0.1 ms/plugin) dominates it.
- Alternative: mark more plugins lazy instead:

```lua
{ "foo/heavy", event = "VeryLazy" }
```

## Native already does it (vim.pack)

Delegated per `docs/design.md`: vim.pack owns placement, installation, tag/ref resolution, the lockfile, and dependency handling.
Laze owns lowering lazy.nvim ranges/refs into vim.pack's `version` field, plus timing and trigger wiring.

### Install / update / delete

- What: no solver, no parallel fetcher, no lock module.
- Why not: state ownership — vim.pack's lockfile (`nvim-pack-lock.json`) already records revisions and installs at the locked revision on a fresh machine.
- Alternative: commit the lockfile; update via `:Laze update` (`vim.pack.update()`).

Version/ref lowering is spec behavior, not a non-goal: [spec.md](spec.md#pin-data-and-unknown-fields).

### `submodules = false`

- What: vim.pack always runs `git submodule update --init --recursive`, so the opt-out cannot be honored (`UNSUPPORTED_FIELDS`). `submodules = true` is silent because it already matches vim.pack.
- Why not: nothing to do for `true`; `false` needs a fetch policy laze does not own.
- Alternative: remove the field, or use a checkout without submodules.

### Build execution

- What: `build` passes through to `vim.pack.Spec`; `setup()` runs it on `PackChanged` (install/update) in `init.lua`.
- Why not: state ownership — vim.pack emits the hook, laze only subscribes.
- Alternative: none; `dir` plugins never run `build` (vim.pack does not manage local dirs — compile-time warning).

## Known limitation (upstream, not laze's to fix)

### Startup command proxy drops quoted args

- What: a lazy `cmd` invoked during startup (`vim_did_enter == 0`) replays through a short-lived proxy at `VimEnter` (`plan.lua` `defer_startup_command`).
  If the invocation carries quoted / space-containing args (`:Cmd "x y"`), the retry reaches the proxy with arguments already empty — Neovim core behavior, measured 2026-09 (`docs/internal/startup-lazy-activation.md`).
  No replay encoding can recover information lost before laze sees it.
  Escaped bars (`:Cmd a\|b`) round-trip fine; post-startup invocations are unaffected.
  Why not fixed: the data is gone upstream; working around it would mean permanent command stubs (rejected: persistent command state for every lazy plugin).
  Alternative: wrap the call in your own `VimEnter` autocmd instead of relying on the proxy replay:

```lua
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function() vim.cmd('Cmd "x y"') end,
})
```
