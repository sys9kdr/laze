# Laze.nvim

Tiny package manager. A thin wrapper around Neovim's `vim.pack` APIs.
Requires Neovim **0.12+** (`vim.pack`).

It adds a lazy.nvim-shaped spec subset and a small lazy-loading plan on top of native package management. `vim.pack` still owns installation, placement, tag/ref resolution, the lockfile, and dependency handling; laze lowers lazy.nvim ranges/refs to vim.pack's `version` field.

It intentionally does not provide its own dependency solver or `:Lazy`-style manager UI. Opt-in `:Laze update/clean/health/reload` wrappers live in `laze.extra`.

Its wrapper layer is narrow:

* accept a small lazy.nvim-shaped spec subset
* normalize it into a pure IR
* build a thin execution plan
* delegate package operations to Neovim-native primitives (`vim.pack`, startup phases, autocmds)

It has:

* small surface area — easy to debug, easy to delete
* deterministic compilation — identical specs → identical IR
* escape hatch first — migrate (back) to lazy.nvim with little or no changes ([docs/migration.md](docs/migration.md))
* opt-in extras only — everything beyond compile → plan → setup lives next to the core, opt-in ([docs/extras.md](docs/extras.md))

It does not have:

* 100% lazy.nvim compatibility — see [Compatibility](#compatibility)

## Compatibility

laze aims to be a lightweight alternative to lazy.nvim: it accepts a
lazy.nvim-shaped declarative spec so most ordinary plugin configurations can
be reused with minimal changes. It does not aim for 100% compatibility. Some
lazy.nvim features, manager commands, and edge cases behave differently or
remain unsupported; the goal is to cover the common declarative core while
keeping the implementation small, simple, and maintainable.

Compatibility is pinned to the lazy.nvim spec documented as of **2026-08-18**
(the reference date in `tests/test_subset.lua`), not to every upstream change.
When a field cannot be represented faithfully, laze fails loudly at compile
time or documents the exact conversion. A few fields are explicitly
warned-and-ignored (`lazy`, `import`, `submodules`, `optional`, `specs`), and
unsupported `keys` entry options are dropped; see
[docs/migration.md](docs/migration.md). Extensions are outside the subset and
use non-colliding names. Known differences are indexed in
[docs/known-differences.md](docs/known-differences.md) with stable IDs and
test references.

Notable gaps: no `:Lazy` UI or install/sync surface (only the opt-in `:Laze`
wrappers); `import`, `specs`, `optional`, `submodules`, and `lazy` are not
implemented; function-shaped triggers are rejected; `opts` requires an
explicit `main`; and `version` accepts semver ranges only (refs use
`branch`/`tag`/`commit`).

The guiding principle is to preserve compatibility where practical, without
letting it undermine laze's primary goal: a small, maintainable alternative
built around Neovim's native plugin management. See
[docs/migration.md](docs/migration.md) for field-by-field expectations and
[AGENTS.md](AGENTS.md) for the subset discipline.

## Quick start

Install laze with a single command — the Neovim interpreter runs
`vim.pack.add`, which clones laze into your data dir:

```sh
nvim -c 'lua vim.pack.add({ "https://github.com/sys9kdr/laze" })' -c qa
```

Then manage laze like any other plugin — by laze itself:

```lua
vim.loader.enable()
vim.pack.add({ "https://github.com/sys9kdr/laze" }) -- idempotent after install
local laze = require("laze")

laze.setup({
  { "sys9kdr/laze" }, -- dogfooding: laze manages itself

  -- Eager: no trigger → loads at startup (colorscheme first)
  { "folke/tokyonight.nvim" },

  -- Lazy: event
  { "folke/which-key.nvim", event = "VeryLazy",
    config = function() require("which-key").setup() end },

  -- Lazy: command
  { "nvim-telescope/telescope.nvim", cmd = "Telescope",
    dependencies = { "nvim-lua/plenary.nvim" } },

  -- Lazy: key (rhs = replay; no rhs = takeover, the plugin's map wins)
  { "stevearc/oil.nvim", keys = { { "<leader>o", "<cmd>Oil<CR>" } } },

  -- Lazy: require() of a declared module
  { "folke/snacks.nvim", module = { "snacks" }, config = function()
    require("snacks").setup() end },
})
```

Or just one call if you have specs elsewhere:

```lua
local compiled = laze.setup(specs)   -- compile + vim.pack.add + plan(), returns compiled
```

`setup()` returns the compiled IR (`LazeCompiled`). You can hand it to [`laze.build_plan`](#instrumenting-load-time) for hooks like load-time timings, or just keep it around for inspection — otherwise ignore it. Pinning needs no code: commit `vim.pack`'s own lockfile (`$XDG_CONFIG_HOME/nvim/nvim-pack-lock.json`).

That's it. Everything else in laze is declarative spec fields, opt-in extras, and your own commands — [see below](#spec-shape).

## Spec shape

Supported fields:

* `[1]` or `src`
* `name`
* `dir`
* `url`
* `event`
* `ft`
* `cmd`
* `keys`
* `dev`
* `init`
* `config`
* `cond`
* `enabled`
* `silent`
* `version` — semver range (`string|false`), lowered to a `vim.VersionRange`
  via `vim.version.range()`. Single ranges only: `*`, partial versions,
  `^`/`~`/`>`/`>=`/`<`/`<=`/`=`, `x` wildcards, hyphen ranges, and
  prerelease/build. Multi-range (`||`) and whitespace-separated comparator
  sets are rejected; the only whitespace allowed inside a range is the
  ` - ` hyphen separator.
* `branch` / `tag` / `commit` — git refs, lowered to vim.pack's version string
  (lazy.nvim precedence: `commit > tag > version > branch`; `version = false`
  skips the range and falls back to `branch` / the default branch)
* `pin` — passed through to `vim.pack.Spec`
* `data`
* `after`
* `dependencies`
* `module` — module name(s) that trigger lazy load on `require`
* `main` — module name for `opts` (explicit; never guessed from the repo)
* `opts` — table passed to `require(main).setup(opts)` at load (requires `main`)
* `build` — build command or function (passed to `vim.pack`)
* `priority` — eager plugin load order: higher loads first, tie-break by id (default 50)
* `dev_path` — local path for dev mode (used by your own commands)

Accepted value shapes:

* `string`
* `string[]`
* `boolean`
* `function`

Notes:

* `dependencies` is a **shallow, non-recursive** syntax sugar: each dependency is registered as a separate spec and mapped to `after`. No config/trigger inheritance, no transitive resolution — an inline dep spec that carries its own `dependencies` field gets a compile-time warning (move it to the top-level spec list). Dependencies are **never eager**: they load with their parents — eagerly when the parent is eager, lazily when the parent is lazy (lazy.nvim-compatible: *"Dependencies are always lazy-loaded unless specified otherwise"*). To load a dep independently, give it its own trigger (e.g. `event = "InsertEnter"`).
* `[1]`/`src` is content-aware: absolute and `.`-prefixed paths (`./foo`, `../foo`) are treated as local dirs, `~` expands, `https://`/`git@` URLs as-is, anything else is expanded to `https://github.com/<src>`. A bare relative path like `foo/bar` is NOT a local dir — it becomes a GitHub URL.
* `name` is used for internal routing (routes, after deps) and defaults to the plugin's repository name with `.nvim`/`.lua` stripped (lazy.nvim-compatible: `folke/which-key.nvim` → `which-key`). The installed directory (`pack/<pkg>/opt/<name>`) and `:packadd` use the *full* repository name (vim.pack's own derivation) — for `which-key.nvim` that directory is `which-key.nvim`, matching existing installs. It is **not** passed directly to `require` — laze only requires module names explicitly declared via `module`.
* `silent = true` suppresses `vim.notify` warnings when `require` fails (e.g. for optional plugins).
* Unknown fields (e.g. `pin`, `data`) are passed through to the `pack` entry for `vim.pack.Spec`. `version` is consumed as a semver range and lowered to a `vim.VersionRange` via `vim.version.range()`; `branch`/`tag`/`commit` are consumed as git refs and lowered to vim.pack's version string. Precedence matches lazy.nvim: `commit > tag > version > branch`. `version = false` skips the range and falls back to `branch` / the default branch. `version` is parsed only when it wins precedence; `dir` plugins do not lower it (lazy.nvim ignores it), but a range is still validated. An active dev path (`dev`/`dev_path`) is a local checkout too: `version`/`branch`/`tag`/`commit` are validated but never lowered into the pack entry, so vim.pack cannot check out a ref in your dev clone (lazy.nvim turns `dev` into a local `dir`). Unsupported version strings (git refs like `"main"`, commit hashes, multi-ranges like `"1.2 || 1.3"`, and whitespace-separated comparator sets) are rejected with a compile error — use `branch`/`tag`/`commit` for refs. vim.pack errors if no tag matches the range; lazy.nvim falls back to the default branch, so use a ref for repos without semver tags.
* `dir` takes priority over `[1]`, `dev`, and `url`.
* `dir` plugins are **local**: they are excluded from the `pack` array (vim.pack never installs or manages them) and the plan loads them at trigger/eager time by prepending the exact directory path to `'runtimepath'`. This mirrors lazy.nvim's `dir` behavior — the directory must already exist on disk.
* `url` takes priority over `[1]` and auto-detected URLs.
* `keys = { { lhs = "<leader>x" } }` without `rhs` is a *takeover* trigger: the plugin's own keymap for that lhs replaces laze's after load. The replay expands `<leader>` with the **current** `g:mapleader` — set it before `laze.setup()` and don't change it mid-session (the plugin's map is created with whatever leader was active at registration).
* Triggers (`event`/`ft`/`cmd`/`keys`) accept `string` or `string[]`; `event` additionally accepts lazy.nvim's `{ event, pattern }` table, either alone or in an array (e.g. `event = { event = "BufReadPre", pattern = "*.lua" }` or `event = { "BufEnter", { event = "BufLeave", pattern = "*.md" } }`), and `keys` accepts `{ lhs, mode?, rhs?, desc?, silent? }` entries (`mode` may be a `string[]`, default `"n"`). `pattern` must be a string. Each distinct `(event, pattern)` pair is routed independently: a spec without a pattern never inherits another spec's pattern, and a patterned spec never fires for buffers that do not match. Keys are routed **per `(lhs, mode)` variant**: a `mode` array expands to one independent trigger map per mode, so two entries sharing an `lhs` with different modes both work — an `n`-mode press loads only the `n` variant, a `v`-mode press only the `v` variant. If entries share the same `lhs` *and* mode but disagree on `rhs`/`desc`/`silent`, laze warns and keeps the first entry's map options (the trigger map is shared; every declaring plugin still loads on that key). Event names use Neovim's stored form — aliases are normalized at compile time (`BufRead`→`BufReadPost`, `BufCreate`→`BufAdd`, `BufWrite`→`BufWritePre`, same mapping `nvim_create_autocmd` applies). **Function-shaped triggers are rejected with a compile error** — laze has no runtime trigger evaluation, and silently treating them as "no trigger" would turn the plugin eager.

## `module` — module-triggered lazy load

```lua
{
  "folke/which-key.nvim",
  module = "which-key",        -- single module
  -- or: module = { "which-key", "which-key.util" }
}
```

When you call `require("which-key")`, the plugin loads automatically (with its `after` deps). Triggers are registered as **`package.preload` entries** at plan build time — the global `require` is never wrapped, unrelated requires pay zero overhead, and each entry consumes itself on first use.

## `build` — pass-through to vim.pack

```lua
{
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",         -- string command
  -- or:
  build = function()           -- or function
    vim.cmd("TSUpdate")
  end,
}
```

Passed directly to `vim.pack.Spec`.

## `dev` / `dev_path` — local dev clones

```lua
{ "folke/flash.nvim", dev = true },          -- <dev_root>/<name> (default ~/dev)
{ "folke/lazydev.nvim", dev = "~/work/lazydev.nvim" }, -- or an explicit path

{
  "my/plugin",
  dev_path = "~/dev/my-plugin",  -- just metadata: your own commands decide what to do with it
}
```

`dev = true` or a string re-points the install source at your local clone. `~` expands; absolute and relative paths pass through verbatim. `dev_path` is a fallback source with the same effect when `dev` is unset — see [Custom commands](docs/commands.md) for sync / dev-mode / hot-reload recipes.

A dev path is a local checkout, so laze never lowers `version`/`branch`/`tag`/`commit` for it (lazy.nvim treats dev plugins as local `dir`s). A semver `version` is still validated at compile time; it just cannot select a tag in your working tree.

## `VeryLazy`

`VeryLazy` is a convenience post-startup event.

In GUI mode it fires on `UIEnter`. In headless mode — or whenever the plan is built after startup (`vim_did_enter ~= 0`, when a one-shot `UIEnter` autocmd would be dead) — it fires immediately after the execution plan is set up.

Use it for plugins that should not be on the critical path.

## Instrumenting load time

Hooks belong to the execution plan, not the compiler — `build_plan` takes two optional hooks (`setup` passes them through). Measure plugin load time in a few lines — no wrapper module needed:

```lua
local compiled = laze.compile(specs)
local timings = {}
laze.build_plan(compiled, {
  on_load = function(id, ms) table.insert(timings, { id = id, time_ms = ms }) end,
  on_fail = function(id, err) vim.notify(id .. ": " .. err) end,
})()
-- later: for _, t in ipairs(timings) do print(("%6.2f  %s"):format(t.time_ms, t.id)) end
```

## Further reading

* [Design: output model, activation invariant, philosophy](docs/design.md)
* [Extras: maintenance commands](docs/extras.md)
* [Custom commands: sync, dev mode, hot reload, sandbox](docs/commands.md)
* [Migrating from lazy.nvim](docs/migration.md)
* [Known differences from lazy.nvim](docs/known-differences.md)
* [Performance: measured numbers, resolved items, accepted trade-offs](docs/performance.md)
* [What laze doesn't have (and won't)](docs/not-have.md)

## License and credits

**Apache-2.0** © 2026 Daiki Noda (sys9kdr).

laze is **actively maintained** by Daiki Noda (sys9kdr). Core, extras,
tests, fixtures and docs are written for laze itself; no lazy.nvim
implementation code is vendored or copied. The semver range vectors in
`tests/fixtures/lazy_semver_cases.lua` are adapted from lazy.nvim's
`tests/manage/semver_spec.lua` (Apache-2.0) and carry an attribution header.

Credits:

* **lazy.nvim** (Apache-2.0, © Folke Lemaitre) — laze's spec surface is a deliberate subset of lazy.nvim's declarative spec format, its name derivation (`Spec.get_name`) informed laze's id/pkg derivation, and the migration-compatibility goal (escape hatch first) is directly inspired by it. https://github.com/folke/lazy.nvim
* **Neovim / `vim.pack`** (Apache-2.0) — installation, placement, tag/ref resolution, and the lockfile are delegated to `vim.pack`; laze lowers lazy.nvim ranges/refs to its `version` field.

See AGENTS.md for design invariants and conventions.
