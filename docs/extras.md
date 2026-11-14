# Opt-in extras

The core ships no commands and no runtime machinery.
Everything beyond compile → plan → setup lives in the **optional** `lua/laze/extras/` directory (it is never required by the core — load cost is zero unless you `require` it).
The public module is `laze.extras`.

## `laze.extras` — maintenance commands

The entry point re-exports the maintenance functions and registers commands only on explicit `setup()`:

```lua
require("laze.extras").setup()
```

The implementation is split so you can load only what you need:

| Module | Contents |
| --- | --- |
| `laze.extras` | `update`, `clean`, `health`, `reload`, `setup` (the public API) |
| `laze.extras.maintenance` | the four functions, no command registration |
| `laze.extras.commands` | `setup(api)` command wiring, no side effects on require |

`laze.extras` is the public entry point; `laze.extras.maintenance` and `laze.extras.commands` are the internals behind it.
`require("laze.extra")` is a deprecated alias: it warns and returns the same table (removed in 1.0).

One command with subcommands (lazy.nvim-style, tab-completed):

| Subcommand     | Effect                                                      |
| --- | --- |
| `:Laze update` | `vim.pack.update()` for managed plugins                     |
| `:Laze clean`  | list managed plugins missing from the last setup (dry-run)  |
| `:Laze clean!` | delete them via `vim.pack.del` (inactive only)              |
| `:Laze health` | per-plugin setup/compile/install report                     |
| `:Laze reload` | re-run the last `setup()` (dev loop)                        |

`:Laze clean` without `!` never deletes — it prints the stale names so you can check them first.
The desired set is exactly the specs from the last `setup()`; laze itself is never reported, so it does not need to appear in its own specs.
`clean!` skips plugins that are active in the current session (plain `vim.pack.del` refuses them) and warns which need a restart.
`:Laze health` covers the spec side only (installed/MISSING, lazy/eager); install, lockfile and `active` state belong to `vim.pack` — use `:checkhealth vim.pack` for those.
Unknown subcommands warn with the valid list instead of throwing.

Prefer your own names?
The commands are thin wrappers over public functions — wire them yourself instead of calling `setup()`:

```lua
local extra = require("laze.extras")
-- extra.update() / extra.clean(true) / extra.health() / extra.reload()
vim.api.nvim_create_user_command("Sync", function() extra.update() end, {})
```

## Pinning versions (no code needed)

`vim.pack` owns the lockfile natively (`$XDG_CONFIG_HOME/nvim/nvim-pack-lock.json`): it records each plugin's revision and installs at the locked revision on a fresh machine — verified end-to-end (fresh data dir + lockfile, no version pin → locked revision installed).
Commit it to version control — that is the entire workflow.

## Manual wiring

The core exposes two small hooks on `build_plan` (`setup` passes them through; the compiler itself stays pure):

* `on_load = fun(id, time_ms)` — called after a plugin loads successfully
* `on_fail = fun(id, err)` — called after a plugin fails to load

Use them directly — no wrapper module needed:

```lua
laze.setup(specs, {
  on_load = function(id, ms) collect(id, ms) end,
  on_fail = function(id, err) notify(id .. ": " .. err) end,
})
```