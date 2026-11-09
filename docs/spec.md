# Spec field details

Authoritative behavior for the fields listed in
[README § Spec shape](../README.md#spec-shape). For converting a spec from
lazy.nvim, see [migration.md](migration.md); for the canonical difference
registry, see [known-differences.md](known-differences.md).

## Field notes

### `cond` / `enabled`

`cond`/`enabled` are resolved once during `setup()`, before `vim.pack.add`:
`false` (literal or a function returning false) means the plugin is not
installed and its `init`, triggers, keys and `config` are skipped — lazy.nvim
parity. Verdicts are shared with the plan, so the hooks are evaluated exactly
once. See [design.md](design.md).

### `dependencies`

`dependencies` is **recursive** syntax sugar: each dependency is registered as
a separate spec and mapped to `after`, and an inline dep's own `dependencies`
are expanded first (deepest-first load order). A dependency is matched by
explicit `name`, derived name, or resolved source, so a renamed top-level spec
is referenced instead of registered a second time; a shared dep is registered
once. Dependencies of an `enabled = false` or `cond = false` spec are not
registered (lazy.nvim behavior). No config/trigger inheritance. Dependencies
are **never eager** unless `lazy = false` says otherwise: they load with their
parents — eagerly when the parent is eager, lazily when the parent is lazy
(lazy.nvim-compatible: *"Dependencies are always lazy-loaded unless specified
otherwise"*). To load a dep independently, give it its own trigger (e.g.
`event = "InsertEnter"`).

### `[1]` / `src`

Content-aware: absolute and `.`-prefixed paths (`./foo`, `../foo`) are treated
as local dirs, `~` expands, `https://`/`git@` URLs as-is, anything else is
expanded to `https://github.com/<src>`. A bare relative path like `foo/bar` is
NOT a local dir — it becomes a GitHub URL.

### `name`

Used for internal routing (routes, after deps) and defaults to the plugin's
repository name with `.nvim`/`.lua` stripped (lazy.nvim-compatible:
`folke/which-key.nvim` → `which-key`). The installed directory
(`pack/<pkg>/opt/<name>`) and `:packadd` use the *full* repository name
(vim.pack's own derivation) — for `which-key.nvim` that directory is
`which-key.nvim`, matching existing installs. It is **not** passed directly to
`require` — laze only requires module names explicitly declared via `module`.

### `silent`

`silent = true` suppresses `vim.notify` warnings when `require` fails (e.g. for
optional plugins).

### `pin`, `data`, and unknown fields

Unknown fields (e.g. `pin`, `data`) are passed through to the `pack` entry for
`vim.pack.Spec`. `version` is consumed as a semver range and lowered to a
`vim.VersionRange` via `vim.version.range()`; `branch`/`tag`/`commit` are
consumed as git refs and lowered to vim.pack's version string. Precedence
matches lazy.nvim: `commit > tag > version > branch`. `version = false` skips
the range and falls back to `branch` / the default branch. `version` is parsed
only when it wins precedence; `dir` plugins do not lower it (lazy.nvim ignores
it), but a range is still validated. An active dev path (`dev`/`dev_path`) is a
local checkout too: `version`/`branch`/`tag`/`commit` are validated but never
lowered into the pack entry, so vim.pack cannot check out a ref in your dev
clone (lazy.nvim turns `dev` into a local `dir`). Unsupported version strings
(git refs like `"main"`, commit hashes, multi-ranges like `"1.2 || 1.3"`, and
whitespace-separated comparator sets) are rejected with a compile error — use
`branch`/`tag`/`commit` for refs. vim.pack errors if no tag matches the range;
lazy.nvim falls back to the default branch, so use a ref for repos without
semver tags.

### `dir`

`dir` takes priority over `[1]`, `dev`, and `url`.

`dir` plugins are **local**: they are excluded from the `pack` array (vim.pack
never installs or manages them) and the plan loads them at trigger/eager time
by prepending the exact directory path to `'runtimepath'`. This mirrors
lazy.nvim's `dir` behavior — the directory must already exist on disk.

### `url`

`url` takes priority over `[1]` and auto-detected URLs.

### `keys`

`keys = { { lhs = "<leader>x" } }` without `rhs` is a *takeover* trigger: the
plugin's own keymap for that lhs replaces laze's after load. The replay expands
`<leader>` with the **current** `g:mapleader` — set it before `laze.setup()`
and don't change it mid-session (the plugin's map is created with whatever
leader was active at registration). `rhs = false` (or `vim.NIL`) drops the
entry at compile time, so nothing is registered and the key never loads the
plugin; the spec still counts as having a `keys` trigger and stays lazy
(measured lazy.nvim behavior: `plugin.keys` stays truthy even when the resolved
handler map is empty). A later entry for the same `(lhs, mode, ft)` replaces an
earlier one, so `{ "<F7>", "x" }, { "<F7>", false }` removes the map while the
reverse order re-adds it. `rhs = ""` or `"<nop>"` registers a plain no-op map
that never loads it. All of these match lazy.nvim.

### Triggers

Triggers (`event`/`ft`/`cmd`/`keys`) accept `string` or `string[]`; `event`
additionally accepts lazy.nvim's `{ event, pattern }` table, either alone or in
an array (e.g. `event = { event = "BufReadPre", pattern = "*.lua" }` or
`event = { "BufEnter", { event = "BufLeave", pattern = "*.md" } }`), and `keys`
accepts `{ lhs, mode?, rhs?, desc?, silent? }` entries (`mode` may be a
`string[]`, default `"n"`). `pattern` must be a string. Each distinct
`(event, pattern)` pair is routed independently: a spec without a pattern never
inherits another spec's pattern, and a patterned spec never fires for buffers
that do not match. Keys are routed **per `(lhs, mode)` variant**: a `mode`
array expands to one independent trigger map per mode, so two entries sharing
an `lhs` with different modes both work — an `n`-mode press loads only the `n`
variant, a `v`-mode press only the `v` variant. If entries share the same `lhs`
*and* mode but disagree on `rhs`/`desc`/`silent`, laze warns and keeps the
first entry's map options (the trigger map is shared; every declaring plugin
still loads on that key). Empty `mode` values follow lazy.nvim: `mode = ""` is
passed to `vim.keymap.set` (multi-mode mapping), and `mode = {}` installs no
key trigger but keeps the plugin lazy. Event names use Neovim's stored form —
aliases are normalized at compile time (`BufRead`→`BufReadPost`,
`BufCreate`→`BufAdd`, `BufWrite`→`BufWritePre`, same mapping
`nvim_create_autocmd` applies). **Function-shaped triggers are rejected with a
compile error** — laze has no runtime trigger evaluation, and silently treating
them as "no trigger" would turn the plugin eager. Key-level `ft`
(`keys = { { lhs, ft = "http" } }`, `ft` may be a `string[]`) installs a
**buffer-local** trigger map via a `FileType` autocmd and never a global map —
lazy.nvim parity; a key-level `ft` and a global declaration for the same
`lhs`/mode are independent variants.

## `VeryLazy`

`VeryLazy` is a convenience post-startup event. `User VeryLazy` is always
emitted, even if no spec uses `event = "VeryLazy"`, so your own autocmds on it
run too.

In GUI mode it fires on `UIEnter`. In headless mode — or whenever the plan is
built after startup (`vim_did_enter ~= 0`, when a one-shot `UIEnter` autocmd
would be dead) — it fires immediately after the execution plan is set up.

Use it for plugins that should not be on the critical path.

## `module`

```lua
{
  "folke/which-key.nvim",
  module = "which-key",        -- single module
  -- or: module = { "which-key", "which-key.util" }
}
```

When you call `require("which-key")`, the plugin loads automatically (with its
`after` deps). Triggers are registered as **`package.preload` entries** at plan
build time — the global `require` is never wrapped, unrelated requires pay zero
overhead, and each entry consumes itself on first use.

## `build`

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

## `dev` / `dev_path`

```lua
{ "folke/flash.nvim", dev = true },          -- <dev_root>/<name> (default ~/projects)
{ "folke/lazydev.nvim", dev = "~/work/lazydev.nvim" }, -- or an explicit path

{
  "my/plugin",
  dev_path = "~/projects/my-plugin",  -- just metadata: your own commands decide what to do with it
}
```

`dev = true` or a string re-points the install source at your local clone. `~`
expands; absolute and relative paths pass through verbatim. `dev_path` is a
fallback source with the same effect when `dev` is unset — see
[Custom commands](commands.md) for sync / dev-mode / hot-reload recipes.

Global dev settings use lazy.nvim's shape as the second argument to
`setup()`/`compile()`:

```lua
laze.setup(specs, {
  dev = {
    path = "~/projects",          -- default ~/projects; `dev_root` is an alias
    patterns = { "my-org/" },     -- plain substrings matched against the plugin URL
  },
})
```

`patterns` are **plain substrings**, not Lua patterns (lazy.nvim uses
`find(pattern, 1, true)`), and only apply to specs that leave `dev` unset.
A match behaves like `dev = true` (`<dev.path>/<name>`); `dev = false`,
`dev = "<path>"`, and `dev_path` still win per spec.

A dev path is a local checkout, so laze never lowers
`version`/`branch`/`tag`/`commit` for it (lazy.nvim treats dev plugins as local
`dir`s). A semver `version` is still validated at compile time; it just cannot
select a tag in your working tree.
