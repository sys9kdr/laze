# Migrating from lazy.nvim

laze accepts lazy.nvim's declarative spec shape on purpose (escape hatch first). Most configs port with mechanical edits, and the conformance test `tests/test_subset.lua` pins the subset continuously. What to expect per field:

**Works as-is** — `[1]`/`src`, `dir`, `url`, `name`, `dev`, `dev_path`, `event`, `ft`, `cmd`, `keys`, `init`, `config`, `cond`, `enabled`, `dependencies`, `build`, `branch`/`tag`/`commit`, `pin`, `module` (laze's take on it, see below), `main` + `opts` (see below). See the version notes for `version`.

**One-line conversions**
* `lazy = true` → remove it. In laze, *no trigger* means eager and a trigger means lazy — there is no separate `lazy` flag.
* `import = "..."` → not supported; load your spec files yourself and pass the resulting tables to `setup`.
* `priority` → **honored for eager ordering** (higher first, tie-break: id), default 50 — matches lazy.nvim's colorscheme-first workflow. Non-number priorities are rejected.
* `submodules`, `optional`, `specs`: consumed with a per-compile warning (each compile, not one-time), no equivalent.

**Rejected loudly (safe direction — lazy.nvim never breaks a laze config, only the reverse)**

* Function-shaped triggers (`event`/`cmd`/`ft`/`keys` as a function): compile error — laze does not evaluate triggers.
* `build` as a list of commands (lazy.nvim's array form): compile error — use a single string or function. (`build = false` is accepted and means "no build", like lazy.nvim.)
* `version` as a prebuilt `vim.VersionRange`, a git ref, a multi-range (`1.2 || 1.3`), or a whitespace-separated comparator set: compile error — pass a single semver range string, or use `branch`/`tag`/`commit` for refs.

**Version notes** — `version` is lazy.nvim's semver range and is lowered to a `vim.VersionRange` via `vim.version.range()`; `branch`/`tag`/`commit` are refs and lower to vim.pack's version string. Precedence is `commit > tag > version > branch`; `version = false` falls back to `branch` / the default branch. A range is parsed only when it wins precedence, so a bad `version` overridden by `tag`/`commit` is ignored (like lazy.nvim). `dir` plugins do not lower `version` (lazy.nvim ignores it), but the range is still validated.

Accepted range forms: `*`, `""`, partial versions (`1`, `1.2`), `x`/`X`/`*` wildcards (`1.2.x`), comparators `^ ~ > >= < <= =`, hyphen ranges (`1.2.3 - 2.0.0`), and prerelease/build. Only one range is accepted: multi-ranges (`||`) and whitespace-separated comparator sets are rejected. A prebuilt `vim.VersionRange` is not accepted; pass the range string.

A non-range version string (e.g. `version = "main"`) is rejected — use `branch`/`tag`/`commit` for refs. vim.pack errors when no tag matches the range; lazy.nvim falls back to the default branch, so use a ref for repos without semver tags.

**Silently degraded**

* `keys` entries keep `lhs`/`rhs`/`mode`/`desc`/`silent`; other `vim.keymap.set` options (`noremap`, `nowait`, `expr`, `callback`, `buffer`, …) are dropped. The positional `{ lhs, rhs }` form and function `rhs` are supported.
* `module = "name"` in laze is an *opt-in* require trigger (registered as a `package.preload` entry); lazy.nvim's `module = false` is an *opt-out* of automatic require-loading. `module = false` in laze means "no module triggers".
* `opts = {...}` needs an explicit `main = "..."`: laze runs `require(main).setup(opts)` at load and never guesses the module name from the repo (`opts` without `main` is a compile error, as is `config` + `opts` together). `opts` must be a table — the function form is rejected. `config = true` stays an error; write the function or use `opts` + `main`.
* `after` is a laze extension for dep ordering (lazy.nvim's equivalent: `dependencies`). lazy.nvim silently ignores it — convert to `dependencies` when moving back.
