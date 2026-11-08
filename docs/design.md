# Design

## Output model

Laze produces a pure IR with three parts:

* `pack`: passed to `vim.pack.add()`
* `registry`: plugin metadata and callbacks
* `routes`: trigger indexes

The execution plan is then generated from that IR.
At load time, laze only requires module names explicitly declared via `module`. It never guesses the module from the repo name (`hrsh7th/cmp-buffer` ships the `cmp_buffer` module), and `config` functions do their own requires — mirroring lazy.nvim.

Laze is deliberately small: specs compile to a pure IR, the plan only wires triggers, and everything else is an opt-in extra.

## When does a plugin's code run?

* **Disabled** (`enabled = false` or `cond = false`, literal or a function returning false): resolved once at setup while the spec is processed, before `vim.pack.add`, so the spec is not installed at all (lazy.nvim parity). The verdicts are shared with the plan, so `init`, loads and key triggers agree, and the hooks are evaluated once.
* **Eager** (no triggers, not a `dependencies` dep): the installed directory is added to the runtimepath at setup (`:packadd!`), so the startup `plugin/` and `after/plugin/` phases source its files exactly once. `config` runs from the plan at setup time.
* **`init`** runs once during setup for every enabled plugin whose `cond` passes, before any plugin loads (lazy.nvim parity), and receives the plugin as `{ name, dir, url, lazy }`. lazy.nvim's own init order is unspecified (pairs over its plugin map), so laze sorts by id to keep re-compiles deterministic. A failing `init` warns and the plugin still loads; `reload_all()` builds a fresh plan and runs it again.
  Since laze does not hook global `require`, an `init` for a lazy plugin cannot
  require that plugin's module before it is activated unless the module is
  explicitly declared with `module`; otherwise defer the require to `config`.
* **Lazy** (has a trigger, or is a `dependencies` dep of a lazy plugin): **nothing** runs at startup — the plugin is not even on the runtimepath. When its trigger fires after startup, the plan `:packadd`s it (sourcing `plugin/` and `ftdetect/`), sources its `after/plugin/` scripts, then runs `module` requires → `config`. If a trigger fires during startup, laze adds it to a closure-local pending queue and finalizes it at `VimEnter`; this avoids a lazy opt package being left on the runtimepath with its `plugin/` files unsourced.
* `dependencies` of a lazy plugin stay off the runtimepath too; they activate immediately before the parent.
* **Trigger replay** (lazy.nvim parity): once a trigger has loaded a plugin, the triggering event is re-fired so handlers the plugin registered while loading still see it. `FileType` replays once for the triggering buffer, so ft handlers receive it wherever they are grouped (pre-existing ft handlers therefore see it twice, as with lazy.nvim). Other events replay once per augroup **added by the load**: groups that already existed are excluded and ungrouped autocmds are skipped, because a fresh ungrouped row cannot be told apart from a pre-existing one. A dispatch that loads nothing never replays.

### The activation invariant

Every plugin's `plugin/` and `after/plugin/` files are sourced **exactly once**, ordered by one rule:

> `vim_did_enter == 0` (during startup) → eager plugins use `:packadd!` only; startup-requested lazy plugins are finalized once at `VimEnter`.
> `vim_did_enter ~= 0` (after startup) → `:packadd` (sources `plugin/`, `ftdetect/`) + manually source the plugin's own `after/plugin/` files (`:packadd` never sources those — startup-only).

The one exception: a load reached from inside an eager plugin's startup load (its `dependencies`) is not deferred to `VimEnter` — it loads with its parent, so the parent's `config` sees it already loaded (lazy.nvim recurses into deps inside `load()`; see `tests/run.lua`, "startup eager deps").

Breaking this invariant produces double-source (side effects run twice) or missing files. The startup-phase integration test in `tests/run.lua` asserts it by spawning real sessions; keep it green when touching activation.

Note: `:packadd` after startup also sources `ftdetect/`; during startup the runtime's filetype machinery picks it up from the runtimepath on demand.

## Loading laze itself

Laze is installed and managed by `vim.pack` like any other plugin — but that
does not mean it must be **loaded** through `vim.pack.add()` on every startup.
Skipping that call for an already-installed laze saves its per-plugin
filesystem/placement checks and keeps one module requirable via a plain
`rtp:prepend`.

The cheap load pattern (used in the author's config):

```lua
vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/site/pack/core/opt/laze")
local ok, laze = pcall(require, "laze")
if not ok then
	-- Fresh machine only: install through the normal path once.
	vim.pack.add({ "https://github.com/sys9kdr/laze" })
	laze = require("laze")
end
laze.setup(require("config-extensions"))
```

Why this is safe despite looking like a layering violation:

* Management and loading are orthogonal. `vim.pack.update/del/get` operate on
  everything under the managed `site/pack/core/opt` directory; they never
  require the plugin to have been added in the current session.
* Lockfile synchronization runs on the *first* `vim.pack` function call —
  which is inside `setup()`, since laze always calls `vim.pack.add` for the
  user's specs. A fresh-machine install via the fallback also keeps the
  lockfile consistent.
* The plugin shows up as `active = false` in `vim.pack.get()` output. That is
  cosmetic: "not added this session", not "unmanaged".

What does NOT work: copying laze into a plain `pack/*/start/` directory of
'packpath'. Native startup would source it for free, but plugins outside
`site/pack/core/opt` are invisible to `vim.pack.update`, the lockfile, and
`PackChanged` build hooks — you would be back to manual `git pull`.

Measured head-to-head (headless `--startuptime`, 7 samples each, same
machine/minute): startup median 43.9 ms → 41.0 ms with the pattern above.

## Notes

* `vim.loader.enable()` goes on the first line, before any `require`.
  Only modules required *after* the call use the bytecode cache —
  anything loaded before it pays full parse on every startup. Measured:
  laze's own require ~2.7 ms → ~0.7 ms warm (one-time ~1 ms cache-write
  tax per upgrade). The win is size-dependent: ~30 KB modules save
  milliseconds, ~2 KB modules can cost more in cache overhead than they
  save in parsing — so "early" matters precisely because the big modules
  (manager, plugins) all load after init starts.
* `vim.pack` is responsible for placement / installation.
* Laze is responsible for timing and trigger wiring.
* The core itself cannot be deferred to command time: eager activation
  and trigger wiring are startup work by design (compare minpac, which
  skips startup entirely by not wiring triggers at all).
* The plugin itself is responsible for its own semantics.
* Dev paths with `~` are expanded at compile time via `vim.fn.expand`. Absolute and relative paths pass through verbatim.

## Philosophy

Laze is intentionally small.

It values:

* explicitness over magic
* pure transforms over stateful managers
* runtime simplicity over feature sprawl
* easy deletion over clever abstractions

---

Laze is a tiny compiler for lazy.nvim-like specs.

It keeps three things separate:

* user input
* pure compiled IR
* thin execution plan

That separation is the whole point.
