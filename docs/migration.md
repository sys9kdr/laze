# Migrating from lazy.nvim

laze accepts lazy.nvim's declarative spec shape on purpose (escape hatch first). Most configs port with mechanical edits, and the conformance test `tests/test_subset.lua` pins the subset continuously. The canonical index of known differences, with stable IDs and test references, is [known-differences.md](known-differences.md). What to expect per field:

**Works as-is** — `[1]`/`src`, `dir`, `url`, `name`, `dev`, `dev_path`, `event`, `ft`, `cmd`, `keys`, `init`, `config`, `cond`, `enabled`, `dependencies`, `build`, `branch`/`tag`/`commit`, `pin`, `module` (laze's take on it, see below), `main` + `opts` (see below). See the version notes for `version`.

**One-line conversions**
* `lazy = true`/`false` → honored as an explicit override. Without it, *no trigger* means eager and a trigger means lazy.
* `import = "..."` → not supported; load your spec files yourself and pass the resulting tables to `setup`.
* `priority` → **honored for eager ordering** (higher first, tie-break: id), default 50 — matches lazy.nvim's colorscheme-first workflow. Non-number priorities are rejected.
* `submodules = false`, `optional`, `specs`: consumed with a per-compile warning (each compile, not one-time), no equivalent. `submodules = true` matches vim.pack and is silent.
* `build = { ... }` (lazy.nvim's array form) → supported; items run sequentially after install/update. `build = false` means "no build", like lazy.nvim. An empty list `build = {}` normalizes to "no build" everywhere (registry and `vim.pack` spec alike).

**Rejected loudly (safe direction — lazy.nvim never breaks a laze config, only the reverse)**

* Function-shaped triggers (`event`/`cmd`/`ft`/`keys` as a function): compile error — laze does not evaluate triggers.
* `keys[].ft` (per-key filetype scoping): supported — laze installs a buffer-local trigger map on the matching `FileType`, never a global map.
* `version` as a prebuilt `vim.VersionRange`, a git ref, a multi-range (`1.2 || 1.3`), or a whitespace-separated comparator set: compile error — pass a single semver range string, or use `branch`/`tag`/`commit` for refs.

**Version notes** — `version` is lazy.nvim's semver range and is lowered to a `vim.VersionRange` via `vim.version.range()`; `branch`/`tag`/`commit` are refs and lower to vim.pack's version string. Precedence is `commit > tag > version > branch`; `version = false` falls back to `branch` / the default branch. A range is parsed only when it wins precedence, so a bad `version` overridden by `tag`/`commit` is ignored (like lazy.nvim). `dir` plugins do not lower `version` (lazy.nvim ignores it), but the range is still validated. An active dev path (`dev`/`dev_path`) is local too: like `dir`, `version`/`branch`/`tag`/`commit` are validated but never lowered, because lazy.nvim turns `dev` into a local `dir` and vim.pack would otherwise clone the dev path and check out the ref there.

Accepted range forms: `*`, `""`, partial versions (`1`, `1.2`), `x`/`X`/`*` wildcards (`1.2.x`), comparators `^ ~ > >= < <= =`, hyphen ranges (`1.2.3 - 2.0.0`), and prerelease/build. Only one range is accepted; multi-ranges (`||`) and whitespace-separated comparator sets are rejected. The only whitespace allowed inside a range is the ` - ` hyphen separator. A prebuilt `vim.VersionRange` is not accepted; pass the range string. Prerelease handling matches lazy.nvim: a tag matches only when its prerelease equals the range's lower-bound prerelease, so `>1.2.3` does not accept `1.2.4-alpha` (the lowered range wraps `has` for this filter; the comparison itself stays Neovim's).

**Dev notes** — `dev = true` resolves to `<dev_root>/<name>`; the default `dev_root` is `~/projects`, matching lazy.nvim's `config.dev.path` default. Override it with `setup(specs, { dev_root = "~/src" })` or `compile(specs, { dev_root = ... })`.

A non-range version string (e.g. `version = "main"`) is rejected — use `branch`/`tag`/`commit` for refs. vim.pack errors when no tag matches the range; lazy.nvim falls back to the default branch, so use a ref for repos without semver tags.

**Silently degraded**

* `keys` entries keep `lhs`/`rhs`/`mode`/`desc`/`silent`; other `vim.keymap.set` options (`noremap`, `nowait`, `expr`, `callback`, `buffer`, …) are dropped (KD-016). The positional `{ lhs, rhs }` form and function `rhs` are supported. `rhs = false` / `vim.NIL` drops the entry; `""` / `"<nop>"` is a no-op map. Per-key `ft` is supported (see above).
* `module = "name"` in laze is an *opt-in* require trigger (registered as a `package.preload` entry); lazy.nvim's `module = false` is an *opt-out* of automatic require-loading. `module = false` in laze means "no module triggers".
* `opts` / `config = true` work as in lazy.nvim: `main` is optional and resolved at load (explicit value, normalized name match, or the plugin's only top-level Lua module). `opts` may be a table or a `function(plugin, opts)` mutator; `config` and `opts` may be combined, and a config function receives `(plugin, opts)`.
* `after` is a laze extension for dep ordering (lazy.nvim's equivalent: `dependencies`). lazy.nvim silently ignores it — convert to `dependencies` when moving back.
