# Design

1. **Spec** — the lazy.nvim-style input.
2. **Compile** — a pure transform into `pack` for `vim.pack` plus `registry`/`routes` for the plan; diagnostics come back as data, never notifications.
3. **`vim.packing`** — `setup()` adds `pack`, then the plan wires triggers and `:packadd`s plugins.

Laze stays intentionally small: explicitness over magic, pure transforms over stateful managers, runtime simplicity over feature sprawl, and easy deletion over clever abstractions.

## Principles

- **Deep modules, small interfaces.** `compile` and `build_plan` each expose one function; the complexity stays inside.
- **Well-typed where Lua allows.** Public shapes are LuaCATS classes; there is no runtime type checker.
- **Functional core, imperative shell.** `compile` is the data-only core; `setup` and the plan are the imperative shell.
- **Pragmatic purity.** Neovim itself is stateful, so absolute purity is not a goal: keep `compile` as pure as practical and put unavoidable effects in the shell.

## Activation contract

`vim.pack` handles placement, not load timing: `:packadd!` only adds to `runtimepath`, and `:packadd` never sources `after/plugin/` (a startup-only phase), so laze must own both timing and source-once behavior.

Every plugin's `plugin/` and `after/plugin/` files are sourced **exactly once**: during startup eager plugins use only `:packadd!`, while after startup laze `:packadd`s and manually sources `after/plugin/`; startup-requested lazy plugins finalize once at `VimEnter` ([details](internal/startup-lazy-activation.md)).
Trigger replay follows lazy.nvim: re-fire the event for handlers registered during the load, once per augroup added by that load (a `FileType` replays once for the triggering buffer).

## Loading laze itself

`vim.pack` manages only `site/pack/core/opt`; the native `pack/*/start` directory is separate and not managed by `vim.pack`.
An installed plugin becomes requirable through `vim.pack.add` (which runs `:packadd!` during `init.lua`), and that call is idempotent, so the normal pattern is one call before `require("laze")`:

```lua
vim.pack.add({ "https://github.com/sys9kdr/laze" })
local laze = require("laze")
```

This keeps `vim.pack.get()` and `PackChanged` bookkeeping intact, and laze needs no spec entry of its own: `:Laze clean` excludes the running plugin, and `vim.pack.update()` covers every plugin installed under the managed `opt` directory.
Prepending `site/pack/core/opt/laze` to `runtimepath` is the `:packadd!` equivalent, but it only skips laze's own add — a saving of at most one add, zero when `setup()` adds other git plugins ([measurements](internal/performance.md)).
A copy under `pack/*/start/` is not an alternative: it is invisible to `vim.pack.update`, the lockfile, and `PackChanged`.

## Notes

* Call `vim.loader.enable()` before any `require`: only later modules use the bytecode cache. The win is size-dependent, and laze's big modules load after `init` starts; measurements are in [performance.md](internal/performance.md).
* Eager activation and trigger wiring are startup work by design, so the core cannot be deferred to command time (minpac skips startup by not wiring triggers at all).
* Dev paths with `~` are expanded at compile time via `vim.fn.expand`; other paths pass through verbatim. Details: [spec.md](spec.md#dev--dev_path).

## Spec shape

The full field set is the `LazeSpec` LuaCATS type in [`lua/laze/init.lua`](../lua/laze/init.lua); behavior details are in [spec.md](spec.md).
