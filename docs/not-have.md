# What laze doesn't have (and won't)

For evaluating laze vs lazy.nvim. Every item below is grounded in the
code or a measured doc — not a roadmap. Sources: `lua/laze/compile.lua`
(`UNSUPPORTED_FIELDS`, `validate_spec`, `validate_triggers`),
`tests/test_subset.lua` (semantic notes), `docs/design.md` (Philosophy),
`docs/migration.md`, `docs/performance.md` (Rejected sections),
`docs/startup-lazy-activation.md` (proxy limitation).

## Deliberate no (philosophy)

Explicitness over magic, pure transforms over stateful managers
(`docs/design.md` Philosophy). Out of scope per `AGENTS.md`:
dependency solver, manager UI, install/update commands, `opts`
abstraction, import system, background scheduler, lifecycle framework.

- **UI / commands in core.** What: no dashboard, update UI,
  install/update command surface in `setup()`.
  Why not: state ownership — the core is compile → plan → setup;
  runtime machinery belongs to opt-in modules.
  Alternative: `require("laze.extra").setup()` registers `:Laze`
  (`update`/`clean`/`health`/`reload`), or wire your own:
  ```lua
  vim.api.nvim_create_user_command("Sync", function()
    vim.pack.update()
  end, {})
  ```

- **`lazy` flag.** What: `lazy = true` is consumed with a warning
  (`UNSUPPORTED_FIELDS`: "no equivalent; plugins without triggers are eager").
  Why not: magic-vs-explicit — triggers already determine laziness.
  Alternative: delete the flag; add or remove a trigger:
  ```lua
  -- before: { "foo/bar", lazy = true, event = "VeryLazy" }
  { "foo/bar", event = "VeryLazy" }
  ```

- **`import` / `specs` module system.** What: `import` warns
  ("lazy.nvim-only; load spec files yourself"), `specs` warns
  ("no equivalent; inline your specs instead").
  Why not: state ownership — spec discovery is your config's job,
  not the compiler's.
  Alternative:
  ```lua
  local ui = require("config.plugins.ui")
  laze.setup({ { "foo/bar", event = "VeryLazy" }, unpack(ui) })
  ```

- **`optional`.** What: consumed with a warning
  ("deps are always required; remove 'optional'").
  Why not: magic-vs-explicit — conditional inclusion via a flag
  hides the actual condition.
  Alternative: gate at the call site with `cond`/`enabled`:
  ```lua
  { "foo/bar", cond = function() return vim.fn.executable("rg") == 1 end }
  ```

- **`opts` function form.** What: `opts` must be a table
  (`validate_spec`: "opts must be a table"); the lazy.nvim
  `fun(_, opts)` mutator is rejected.
  Why not: magic-vs-explicit — a mutating callback hides the final
  value from the pure IR.
  Alternative: compute the table yourself, pass it with `main`:
  ```lua
  { "foo/bar", main = "bar", opts = vim.tbl_extend("force", defaults, { extra = true }) }
  ```

- **`config = true`.** What: compile error
  (`validate_spec`: "config = true is not supported").
  Why not: magic-vs-explicit — `true` implies an `opts` pipeline
  laze does not own (safe direction per `test_subset.lua`: lazy.nvim
  accepts the laze form, not vice versa).
  Alternative:
  ```lua
  { "foo/bar", main = "bar", opts = {} }
  -- or:
  { "foo/bar", config = function() require("bar").setup({}) end }
  ```

- **`main` guessing (module-name inference).** What: `opts` without
  `main` is a compile error ("laze never guesses the module name");
  laze never derives the module from the repo name.
  Why not: magic-vs-explicit — repo names don't map to modules
  (`hrsh7th/cmp-buffer` ships `cmp_buffer`; `compile.lua`,
  `design.md`).
  Alternative: always name it:
  ```lua
  { "hrsh7th/cmp-buffer", main = "cmp_buffer", opts = {} }
  ```

- **Function-shaped triggers.** What: `event`/`cmd`/`ft`/`keys` as a
  function is a compile error (`validate_triggers`).
  Why not: silently normalizing to "no trigger" would turn a lazy
  plugin eager — the worst failure mode.
  Alternative: spell the trigger list statically:
  ```lua
  -- before: event = function() return cond and "BufRead" or nil end
  { "foo/bar", event = "BufReadPost", cond = function() return cond end }
  ```

- **`build` list form.** What: `build` as a list is a compile error
  ("use a single string or function"); `false`/string/function accepted.
  Why not: magic-vs-explicit — one build step, one value.
  Alternative:
  ```lua
  { "foo/bar", build = "make && make install" }
  ```

- **Background scheduler / lifecycle framework.** What: no timers,
  no deferred-task queue, no plugin-state manager beyond the
  closure-local `loaded` table in `plan.lua`.
  Why not: state ownership — scheduling policy belongs to your config.
  Alternative: your own autocmd/timer calls `load` via a trigger,
  or hooks on `build_plan`:
  ```lua
  laze.build_plan(compiled, {
    on_load = function(id, ms) timings[id] = ms end,
  })()
  ```

## Measured no (perf evidence)

Rejected with numbers in `docs/performance.md` ("Rejected (measured —
re-proposing needs new numbers)"). Each was A/B'd against the real
function; re-proposing needs new measurements, not arguments.

- **Async install.** What: no `vim.uv.spawn` around `vim.pack.add`.
  Why not: `vim.pack.add` guarantees synchronous install, so eager
  and trigger loads work in a first session; async complicates
  startup ordering for no startup win.
  Alternative: none needed — first-install blocking UX belongs to
  vim.pack; subsequent startups are warm.

- **Dev auto-reload watching.** What: no `fs_event` watcher;
  `reload_all()` is manual.
  Why not: perf cost — process management, debouncing, recursion
  control for no gain over an explicit call.
  Alternative (three lines, your config owns it):
  ```lua
  vim.api.nvim_create_user_command("LazeReloadAll", function()
    laze.reload_all()
  end, {})
  ```

- **Symlink-farm rtp consolidation.** What: no neobundle-style
  single-rtp-entry symlink tree.
  Why not: measured ~130–440 us saved at 30 plugins against a
  parallel source-of-truth (rebuild hooks on every
  install/update/del), loss of vim.pack activation, and silent
  symlink staleness. Lazy plugins already never touch rtp, and
  eager→lazy conversion (~0.1 ms/plugin) dominates it.
  Alternative: mark more plugins lazy instead:
  ```lua
  { "foo/heavy", event = "VeryLazy" }
  ```

## Native already does it (vim.pack)

Delegated per `docs/design.md`: vim.pack owns placement,
installation, version resolution, dependency handling. Laze only owns
timing and trigger wiring.

- **Install / update / delete.** What: no solver, no parallel
  fetcher, no lock module.
  Why not: state ownership — vim.pack's lockfile
  (`nvim-pack-lock.json`) already records revisions and installs at
  the locked revision on a fresh machine.
  Alternative: commit the lockfile; update via `:Laze update`
  (`vim.pack.update()`).

- **Version resolution.** What: `version` passes straight through
  to vim.pack (`string|vim.VersionRange`); `branch`/`tag`/`commit`
  are lazy.nvim-only and warn; `pin` passes through untouched.
  Why not: state ownership — one resolver (vim.pack), not two.
  Alternative: write the ref or semver range directly:
  ```lua
  { "foo/bar", version = vim.version.range(">=2.0.0") }
  ```

- **Submodules.** What: consumed, no equivalent
  (`UNSUPPORTED_FIELDS`: "vim.pack fetches submodules by default").
  Why not: nothing to do — native already does it.
  Alternative: none.

- **Build execution.** What: `build` passes through to
  `vim.pack.Spec`; `setup()` runs it on `PackChanged`
  (install/update) in `init.lua`.
  Why not: state ownership — vim.pack emits the hook, laze only
  subscribes.
  Alternative: none; `dir` plugins never run `build` (vim.pack does
  not manage local dirs — compile-time warning).

## Known limitation (upstream, not laze's to fix)

- **Startup command proxy drops quoted args.** What: a lazy `cmd`
  invoked during startup (`vim_did_enter == 0`) replays through a
  short-lived proxy at `VimEnter` (`plan.lua`
  `defer_startup_command`). If the invocation carries quoted /
  space-containing args (`:Cmd "x y"`), the retry reaches the proxy
  with arguments already empty — Neovim core behavior, measured
  2026-09 (`docs/startup-lazy-activation.md`). No replay encoding can
  recover information lost before laze sees it. Escaped bars
  (`:Cmd a\|b`) round-trip fine; post-startup invocations are
  unaffected.
  Why not fixed: the data is gone upstream; working around it would
  mean permanent command stubs (rejected: persistent command state
  for every lazy plugin).
  Alternative: wrap the call in your own `VimEnter` autocmd instead
  of relying on the proxy replay:
  ```lua
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function() vim.cmd('Cmd "x y"') end,
  })
  ```
