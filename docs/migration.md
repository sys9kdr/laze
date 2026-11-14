# Migrating from lazy.nvim

laze accepts lazy.nvim's declarative spec shape on purpose (escape hatch first).
Most configs port with mechanical edits, and the conformance test `tests/test_subset.lua` pins the subset continuously.
The known-difference registry, with stable IDs and test references, is [`tests/fixtures/known_differences.lua`](../tests/fixtures/known_differences.lua); classes and notification policy are in [known-differences.md](known-differences.md).
What to expect per field:

## Works as-is

`[1]`/`src`, `dir`, `url`, `name`, `dev`, `dev_path`, `event`, `ft`, `cmd`, `keys`, `init`, `config`, `cond`, `enabled`, `dependencies`, `build`, `branch`/`tag`/`commit`, `pin`, `module` (laze's take on it, see below), `main` + `opts` (see below).
See the version notes for `version`.

## One-line conversions

`lazy = true`/`false` are honored as an explicit override. Without it, *no trigger* means eager and a trigger means lazy.

```lua
-- lua/plugins.lua
return {
  { "nvim-lua/plenary.nvim" },
  { "neovim/nvim-lspconfig", event = "BufReadPre" },
}
```

`import = "..."` is not supported; load your spec files yourself and pass the resulting tables to `setup`. A single spec module is enough for most configs; split it only when the file outgrows grep:

```lua
-- init.lua
local specs = { "your-name/laze" }
vim.list_extend(specs, require("plugins"))
require("laze").setup(specs)
```

With several modules, loop over their names and `vim.list_extend` each one in the order lazy.nvim used to import them.

- `priority` → **honored for eager ordering** (higher first, tie-break: id), default 50 — matches lazy.nvim's colorscheme-first workflow. Non-number priorities are rejected.
- `submodules = false`, `optional`, `specs`: consumed with a per-compile warning (each compile, not one-time), no equivalent. `submodules = true` matches vim.pack and is silent.
- `build = { ... }` (lazy.nvim's array form) → supported; items run sequentially after install/update. `build = false` means "no build", like lazy.nvim. An empty list `build = {}` normalizes to "no build" everywhere (registry and `vim.pack` spec alike).

## Rejected loudly (safe direction — lazy.nvim never breaks a laze config, only the reverse)

- Function-shaped triggers (`event`/`cmd`/`ft`/`keys` as a function): compile error — laze does not evaluate triggers.
- `keys[].ft` (per-key filetype scoping): supported — laze installs a buffer-local trigger map on the matching `FileType`, never a global map.
- `version` as a prebuilt `vim.VersionRange`, a git ref, a multi-range (`1.2 || 1.3`), or a whitespace-separated comparator set: compile error — pass a single semver range string, or use `branch`/`tag`/`commit` for refs.

### Version notes

`version` is a semver range; `branch`/`tag`/`commit` are refs.
Precedence, `version = false`, and accepted range forms: [spec.md](spec.md#pin-data-and-unknown-fields).

### Dev notes

`dev = true` uses `<dev_root>/<name>` (default `~/projects`); `dev_root` aliases `dev.path`, and `dev.fallback` controls missing clones.
Full rules: [spec.md](spec.md#dev--dev_path).

A non-range version string (e.g. `version = "main"`) is rejected — use `branch`/`tag`/`commit` for refs.

## Silently degraded

- `keys` entries keep `lhs`/`rhs`/`mode`/`desc`/`silent`; other `vim.keymap.set` options (`noremap`, `nowait`, `expr`, `callback`, `buffer`, …) are dropped (KD-016). The positional `{ lhs, rhs }` form and function `rhs` are supported. `rhs = false` / `vim.NIL` drops the entry; `""` / `"<nop>"` is a no-op map. Per-key `ft` is supported (see above).
- `module = "name"` in laze is an *opt-in* require trigger (registered as a `package.preload` entry); lazy.nvim's `module = false` is an *opt-out* of automatic require-loading. `module = false` in laze means "no module triggers".
- `opts` / `config = true` work as in lazy.nvim: `main` is optional and resolved at load (explicit value, normalized name match, or the plugin's only top-level Lua module). `opts` may be a table or a `function(plugin, opts)` mutator; `config` and `opts` may be combined, and a config function receives `(plugin, opts)`.
- `after` is a laze extension for dep ordering (lazy.nvim's equivalent: `dependencies`). lazy.nvim silently ignores it — convert to `dependencies` when moving back.
