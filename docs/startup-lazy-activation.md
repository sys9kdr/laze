# Startup lazy activation

Status: implemented (plan.lua) and tested (spawned-session tests in
tests/run.lua). This doc keeps the original problem analysis and the
design rationale; "proposed"/"verification" phrasing below is historical.

## Problem

`laze.setup()` may run while `vim.v.vim_did_enter == 0`. A lazy plugin can
then be requested by a `FileType` or `CmdUndefined` callback before VimEnter.

For example, opening a Markdown file from the command line can produce this
sequence:

1. Neovim assigns `filetype=markdown` during startup.
2. laze's `ft = "markdown"` route loads `vim-table-mode`.
3. `load_plugin()` uses `:packadd!` because startup has not reached VimEnter.
4. `:packadd!` adds the opt package directory to `runtimepath`, but does not
   source `plugin/table-mode.vim`.
5. `:Tableize` is still undefined at VimEnter and fails with E492.

The same gap affects a command trigger invoked from a startup autocmd. A
`CmdUndefined` callback can mark the package loaded, but the plugin command
does not exist yet.

## Constraints

The existing activation model remains the contract for eager plugins:

| Context | Eager plugin activation |
| --- | --- |
| During startup | `:packadd!`; Neovim's startup phases source `plugin/` and `after/plugin/` exactly once. |
| After startup | `:packadd`; laze manually sources that plugin's `after/plugin/` files. |

The fix must also preserve these properties:

- A plugin's `plugin/`, `ftdetect/`, and `after/plugin/` files must not be
  sourced twice.
- Module requires and `config` must run only after the plugin runtime
  files needed by them are available.
- Command routes continue to be based on `CmdUndefined`; no permanent command
  stubs are installed during normal operation.
- Loading failures remain contained with `pcall` and `vim.notify(..., WARN)`.
- The plan stays closure-local. No process-wide "loaded plugin" state is added.

## Why the current startup rule is insufficient for lazy opt packages

`vim_did_enter == 0` is not a sufficient proxy for "the startup plugin phase
has not happened yet". A lazy opt package may be added to `runtimepath` after
the relevant startup scan, but before VimEnter. In that interval, relying on a
later startup phase to source the package leaves it on `runtimepath` without
executing its `plugin/` files.

This is distinct from eager plugins added by `vim.pack.add(..., { load =
false })`: those are present when Neovim performs its normal startup handling.

## Proposed design

Split activation into two phases for a plugin that is *requested lazily during
startup* (`entry.has_route` or `entry.is_dep`):

1. **Prepare immediately**

   - Resolve dependencies in the existing order.
   - Add the package directory with `:packadd!` (or the local-directory
     runtimepath fallback).
   - Mark the plan entry as `pending_startup`, not fully loaded.
   - Do not run module requires or `config` yet. (`init` already ran during setup.)

2. **Finalize once at VimEnter**

   - Source that package's `plugin/**/*.{lua,vim}` and `ftdetect/*.vim` files.
   - Source its `after/plugin/**/*.{lua,vim}` files.
   - Run explicit `module` requires and `config` using the same error
     handling and callbacks as an ordinary post-startup load.
   - Change the entry state to loaded (or failed).

Exception: if a `module` trigger is `require()`d during startup, the plugin's
declared module requires and `config` run right then, before `require` returns.
Its `init` already ran during setup. The entry stays `pending_startup` until
VimEnter (where it is only marked loaded). Plugins added before Neovim's own
startup `plugin/` phase are sourced by that phase; the finalizer only sources
plugins added after it began.

The plan owns a closure-local queue keyed by plugin id. It registers one
one-shot `VimEnter` callback to drain it in dependency-first insertion order.
Repeated triggers before VimEnter only enqueue a plugin once.

For `cmd` triggers, retain the temporary startup command proxy already added:

1. `CmdUndefined` prepares the plugin and installs a proxy for the retried
   command.
2. The proxy records range, bang, modifiers, and arguments.
3. Finalization sources the plugin command definition.
4. The proxy replays the recorded invocation after finalization.

The proxy must be removed if the plugin did not define the advertised command,
so the replay reports the actual missing-command error instead of re-queuing.

Known limitation (measured 2026-09, Neovim core behavior, not laze's
serialization): when the retried invocation carries quoted/space-containing
arguments (`:Cmd "x y"`), the retry reaches the proxy with arguments already
empty — the information is lost before laze sees it, so no replay encoding
can recover it. Escaped bars (`:Cmd a\|b`) round-trip fine, and post-startup
invocations are unaffected (quoted args arrive intact). If a startup autocmd
must pass quoted args to a lazy command, wrap the call in your own `VimEnter`
autocmd instead of relying on the proxy replay.

## State model

`loaded[id]` currently uses `nil`, `true`, and `"failed"`. Extend the
closure-local state with `"pending_startup"`:

| State | Meaning | Trigger behaviour |
| --- | --- | --- |
| `nil` | Not requested | Resolve and activate it. |
| `pending_startup` | Added to rtp; finalization waits for VimEnter | Do not enqueue or configure it again. |
| `true` | Fully activated | No-op. |
| `"failed"` | Activation failed | No-op; preserve existing failure semantics. |

Dependencies may also be pending. The finalization queue must retain the
dependency-first ordering established by `load_with_deps`.

## Alternatives rejected

### Use `:packadd` during startup

This exposes commands immediately, but `plugin/` is sourced again when the
startup phases process the package. It violates the source-once invariant.

### Source only `plugin/` in the trigger callback

This has the same double-source risk and runs `config` at an inconsistent point
relative to `after/plugin/`.

### Keep a permanent user-command stub for every `cmd` route

This avoids `CmdUndefined`, but changes the documented trigger mechanism and
creates persistent command state for all lazy plugins.

### Only re-check the current filetype

Replaying the current `FileType` route fixes events that happened before
`laze.setup()`, but not events that happen after Neovim's relevant startup scan.
The package can still be added with `:packadd!` without its plugin files being
sourced.

## Verification (done — covered by spawned-session tests in tests/run.lua)

Add spawned-session tests covering both fresh-install and warm-package runs:

1. Start Neovim with a command-line `.md` file and `ft = "markdown"` plugin.
   At VimEnter, assert its plugin-defined command exists and works.
2. Invoke a `cmd`-triggered command from startup with range, bang, and
   arguments. Assert it runs once after VimEnter with the original values.
3. Use a dependency chain requested during startup. Assert source and config
   order remains dependency-first.
4. Instrument `plugin/` and `after/plugin/` files. Assert each is sourced once
   for eager plugins and once for startup-requested lazy plugins; unrelated
   lazy plugins remain silent.
5. Re-run the existing post-startup trigger, reload, module-trigger, and perf
   suites to confirm no change outside the startup path.

