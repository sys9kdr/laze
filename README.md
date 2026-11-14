# Laze.nvim

A tiny package manager with lazy.nvim-style specs, built on Neovim's native `vim.pack` APIs. Requires Neovim **0.12+**.

Laze adds a subset of lazy.nvim's spec syntax and lazy-loading on top of `vim.pack`. Package management (e.g. installation) is handled by `vim.pack`.

## Who it's for

You write or copy lazy.nvim-style specs by hand and want them on `vim.pack`
with lazy-loading, no manager UI, and a cheap way back to lazy.nvim. It is
not for configs that rely on lazy.nvim's composition features (`import`,
`specs`, `opts` merging). See [who laze is for](docs/scope.md).

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

## Spec shape

A spec is a table, a bare `"owner/repo"` string, or a nested list of those.
Nested lists are flattened; sparse lists are rejected.

The full field set is the `LazeSpec` LuaCATS type in [`lua/laze/init.lua`](lua/laze/init.lua); behavior details are in [docs/spec.md](docs/spec.md).

## Development

Dev commands are wrapped in the [`Makefile`](Makefile); run `make` from the
repository root to list every target (`test-*`, `lint*`, `fmt*`, `bench-*`,
`e2e`). The usual entry points:

```sh
make check   # all gates: unit, subset, integration, lint, format check
make fast    # quick gates: fast integration, unit, subset, format check
```

Install the pinned Selene 0.32.0 and StyLua 2.6.0 from their GitHub Release
archives ([Selene](https://github.com/Kampfkarren/selene/releases/tag/0.32.0),
[StyLua](https://github.com/JohnnyMorganz/StyLua/releases/tag/v2.6.0)); both
ship prebuilt binaries, no Rust toolchain is required. `tests/vendor/` and
`tests/snapshots/` are excluded from linting (selene configs) and from
formatting (`.styluaignore`).

CI runs these same targets — `make check` is the union of what its jobs run —
so a failing pipeline is reproducible with the command above.

### README e2e (manual, network only)

`tests/e2e/` fetches a fixed set of real plugin READMEs at pinned commits,
takes each lazy.nvim snippet verbatim, installs it in an isolated headless
Neovim, fires one trigger, and runs one smoke assertion. It needs network and
is not part of CI:

```sh
make e2e                   # all plugins
make e2e ARGS="oil flash"  # by name
make e2e ARGS=--failed     # last report's failures
make e2e ARGS=--clean      # drop cached installs
```

Each row reports `ok` / `warned` (unsupported field) / `failed` with a reason
category (`unsupported_field`, `validation_error`, `install_error`,
`runtime_error`, `environment`, `extraction_error`). This is a diagnosis, not
a pass rate. Reports land in `tests/e2e/report/` (gitignored).

## Further reading

* [Who laze is for (and who it is not for)](docs/scope.md)
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
