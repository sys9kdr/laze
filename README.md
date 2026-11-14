# Laze.nvim

A tiny package manager with lazy.nvim-style specs, built on Neovim's native `vim.pack` APIs.
Requires Neovim **0.12+**.
Laze adds a subset of lazy.nvim's spec syntax and lazy-loading on top of `vim.pack`.
Package management (e.g. installation) is handled by `vim.pack`.

You write or copy lazy.nvim-style specs by hand and want them on `vim.pack` with lazy-loading, no manager UI, and a cheap way back to lazy.nvim.

## Quick start

`vim.pack.add` clones laze on first run and is idempotent afterwards, so it can sit at the top of your config:

```lua
vim.loader.enable()
vim.pack.add({ "https://github.com/sys9kdr/laze" })
local laze = require("laze")

laze.setup({
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

## Compatibility

Laze is **not fully compatible with lazy.nvim**.

- **Spec subset.** Most common specs work as-is.
  See [known differences](docs/known-differences.md) and [design](docs/design.md).
  It is not for configs that rely on lazy.nvim's composition features (`import`, `specs`, `opts` merging).
  See [who laze is for](docs/not-have.md#who-laze-is-for-and-who-it-is-not-for).
- **No manager UI.** Laze focuses on specs and lazy-loading, not plugin management commands.
    - `laze.extra` is opt-in and experimental util commands, they use no UIs or `vim.pack()` UIs.

## License and credits

**Apache-2.0** © 2026 Daiki Noda (sys9kdr).
Actively maintained by the author; laze's own code and tests are original.

laze's spec surface is a deliberate subset of **lazy.nvim** (Apache-2.0, © Folke Lemaitre), which also inspired the migration goal.
The semver vectors are adapted from its `tests/manage/semver_spec.lua`, and a small part of its test suite is vendored under `tests/vendor/lazy.nvim/` as a behavioral oracle (Apache-2.0; see its `LICENSE` and `NOTICE`).
It is not part of the laze runtime or CI.

See [AGENTS.md](AGENTS.md) for the repository guide.
