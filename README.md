# Laze.nvim

A tiny package manager with lazy.nvim-style specs, built on Neovim's native `vim.pack` APIs. Requires Neovim **0.12+**.

Laze adds a subset of lazy.nvim's spec syntax and lazy-loading on top of `vim.pack`. Package management (e.g. installation) is handled by `vim.pack`.

## Compatibility

Laze is **not fully compatible with lazy.nvim**.

- **Spec subset.** Most common specs work as-is. See [known differences](docs/known-differences.md) and [design](docs/design.md).
- **No manager UI.** Laze focuses on specs and lazy-loading, not plugin management commands.
    - `laze.extra` is opt-in and experimental util commands, they use no UIs or `vim.pack()` UIs.

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

`setup()` returns the compiled IR (`LazeCompiled`). You can hand it to [`laze.build_plan`](docs/performance.md#instrumenting-load-time) for hooks like load-time timings, or just keep it around for inspection — otherwise ignore it. Pinning needs no code: commit `vim.pack`'s own lockfile (`$XDG_CONFIG_HOME/nvim/nvim-pack-lock.json`).

That's it. Everything else in laze is declarative spec fields, opt-in extras, and your own commands — [see below](#spec-shape).

## Spec shape

A spec is a table, a bare `"owner/repo"` string, or a nested list of those.
Nested lists are flattened; sparse lists are rejected.

The full field set is the `LazeSpec` LuaCATS type in [`lua/laze/init.lua`](lua/laze/init.lua); behavior details are in [docs/spec.md](docs/spec.md).

```lua
{
  { "owner/repo" },                                 -- eager: no trigger
  { "owner/repo", event = "VeryLazy" },             -- lazy: event
  { "owner/repo", cmd = "Cmd", keys = { "<F5>" } }, -- lazy: command / key
  { "owner/repo", module = "mod", config = true },  -- lazy: require("mod")
  { "owner/repo", dependencies = { "dep/repo" } },
  { "owner/repo", version = "^1.2" },               -- or branch/tag/commit
  { "owner/repo", build = ":Build", dev = true },
  { "owner/repo", dir = "~/src/repo", priority = 60 },
}
```

Rejected at compile time:

```lua
{ "owner/repo", event = function() end }   -- function-shaped triggers
{ "owner/repo", version = "main" }         -- use branch/tag/commit
```

`import`, `specs`, `optional`, and `submodules = false` are warned and ignored.

## Development

Run the packaged test suites and the pinned linter from the repository root:

```sh
nvim --cmd "set rtp+=." -l tests/run.lua        # integration (+ perf)
luajit tests/test_compile.lua                   # unit
luajit tests/test_subset.lua                    # spec-surface conformance
luacheck lua tests                              # static lint (1.2.0)
```

Install the linter with `sudo luarocks install luacheck 1.2.0-1` (or your
distribution's package). Pin the same version; no Rust toolchain is required.
`tests/vendor/` is excluded from linting.

## Further reading

* [Spec field details: triggers, keys, dependencies, name/src, refs](docs/spec.md)
* [Design: output model, activation invariant, philosophy](docs/design.md)
* [Extras: maintenance commands](docs/extras.md)
* [Custom commands: sync, dev mode, hot reload, sandbox](docs/commands.md)
* [Migrating from lazy.nvim](docs/migration.md)
* [Known differences from lazy.nvim](docs/known-differences.md)
* [Performance: measured numbers, instrumentation hooks, accepted trade-offs](docs/performance.md#instrumenting-load-time)
* [What laze doesn't have (and won't)](docs/not-have.md)

## License and credits

**Apache-2.0** © 2026 Daiki Noda (sys9kdr). Actively maintained by the author;
laze's own code and tests are original.

laze's spec surface is a deliberate subset of **lazy.nvim** (Apache-2.0, ©
Folke Lemaitre), which also inspired the migration goal. The semver vectors are
adapted from its `tests/manage/semver_spec.lua`, and a small part of its test
suite is vendored under `tests/vendor/lazy.nvim/` as a behavioral oracle
(Apache-2.0; see its `LICENSE` and `NOTICE`). It is not part of the laze runtime
or CI.

See [AGENTS.md](AGENTS.md) for the repository guide.
