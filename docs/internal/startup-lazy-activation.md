# Startup lazy activation

Status: implemented in `plan.lua`; spawned-session tests in `tests/run.lua` pin it.
The activation invariant lives in [design.md](../design.md).

## Problem

`laze.setup()` may run while `vim.v.vim_did_enter == 0`.
A lazy plugin can then be requested by a `FileType` or `CmdUndefined` callback before VimEnter.
For example, opening a Markdown file from the command line can make an `ft = "markdown"` route load `vim-table-mode` before the startup plugin phase has scanned it.
`:packadd!` adds the opt package directory to `runtimepath` but does not source `plugin/table-mode.vim`; `:Tableize` is still undefined at VimEnter and fails with E492.
A command trigger invoked from a startup autocmd has the same gap: `CmdUndefined` can mark the package loaded, but the plugin command does not exist yet.

`vim_did_enter == 0` is not a sufficient proxy for "the startup plugin phase has not happened yet".
A lazy opt package added after the relevant scan but before VimEnter would rely on a later startup phase that never sources it.
This is distinct from eager plugins added by `vim.pack.add(..., { load = false })`: those are present when Neovim performs its normal startup handling.

## Contract

Eager plugins keep the established activation model:

| Context | Eager plugin activation |
| --- | --- |
| During startup | `:packadd!`; Neovim's startup phases source `plugin/` and `after/plugin/` exactly once. |
| After startup | `:packadd`; laze manually sources that plugin's `after/plugin/` files. |

A plugin *requested lazily during startup* (`has_route` or `is_dep`) splits into two phases:

1. **Prepare immediately** — resolve dependencies, add the package directory with `:packadd!` (or the local-directory runtimepath fallback), and mark the entry `pending_startup`.
   Do not run module requires or `config`; `init` already ran during setup.
2. **Finalize once at VimEnter** — source the package's `plugin/**/*.{lua,vim}` and `ftdetect/*.vim`, source its `after/plugin/**/*.{lua,vim}`, then run explicit `module` requires and `config` with the ordinary post-startup error handling.
   Mark the entry loaded (or failed).

Exception: if a `module` trigger is `require()`d during startup, that plugin's declared module requires and `config` run immediately, before `require` returns.
Its `init` already ran; the entry stays `pending_startup` until VimEnter, where it is only marked loaded.
Plugins added before Neovim's own startup `plugin/` phase are sourced by that phase; the finalizer only sources plugins added after it began.

The plan owns a closure-local queue keyed by plugin id: one one-shot `VimEnter` callback drains it in dependency-first insertion order, and repeated triggers before VimEnter enqueue a plugin once.
Source-once, containment with `pcall` + `vim.notify(..., WARN)`, and the "no process-wide loaded state" rule remain.

## Command proxy

For `cmd` triggers, `CmdUndefined` prepares the plugin and installs a temporary proxy that records range, bang, modifiers, and arguments.
Finalization sources the plugin command definition, then the proxy replays the recorded invocation.
The proxy is removed if the plugin did not define the advertised command, so the replay reports the actual missing-command error instead of re-queuing.

Known limitation (measured 2026-09, Neovim core behavior, not laze's serialization): when the retried invocation carries quoted/space-containing arguments (`:Cmd "x y"`), the retry reaches the proxy with arguments already empty — the information is lost before laze sees it, so no replay encoding can recover it.
Escaped bars (`:Cmd a\|b`) round-trip fine, and post-startup invocations are unaffected.
If a startup autocmd must pass quoted args to a lazy command, wrap the call in your own `VimEnter` autocmd instead of relying on the proxy replay:

```lua
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function() vim.cmd('Cmd "x y"') end,
})
```
