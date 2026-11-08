---
name: lazy-oracle
description: Measure real lazy.nvim behavior before implementing or claiming parity in laze. Use for questions about what lazy.nvim does with a spec field, when an issue or PR asserts lazy.nvim behavior, or when a known difference needs an executable oracle.
---

# Measure lazy.nvim

laze's public spec is a documented lazy.nvim subset, so "lazy.nvim does X" is
an empirical claim. Read the upstream source, then run it and inspect the
state laze actually consumes. Issues and PR descriptions are not the oracle;
a measured result encoded in a test is.

## Workflow

1. Pick the oracle checkout. Prefer `tests/vendor/lazy.nvim` when it exists;
   otherwise clone `folke/lazy.nvim` somewhere under `/tmp/opencode` and
   record the commit you measured.
2. Copy [`scripts/probe.lua`](scripts/probe.lua) and replace the example
   cases with the spec shapes under question.
3. Run it:

   ```sh
   LAZY_DIR=/tmp/opencode/lazy.nvim nvim --headless -u NONE -l probe.lua
   ```

4. Inspect the fields laze consumes, not just whether lazy "works":
   - `Config.plugins[name].lazy` — the startup-load verdict, computed from the
     raw spec (`dep || defaults.lazy || event || keys || ft || cmd`).
   - The raw field (`plugin.keys`, `plugin.event`, ...) — this is what the
     verdict uses, and it stays truthy even when resolution drops every entry.
   - The resolved handler map (`plugin._.handlers.keys`, or
     `require("lazy.core.handler.keys").resolve(list)`) — what actually gets
     registered.
5. Write a test whose comment names the upstream file and the measured state
   (for example `lazy/core/handler/keys.lua` + "plugin.keys stays truthy, so
   the plugin stays lazy"). If the issue assumed otherwise, say so in the
   closing comment.

## Probe gotchas

- `nvim -l` starts with `loadplugins` off, so `require("lazy").setup()` returns
  before doing anything. Set `vim.go.loadplugins = true` first.
- lazy indexes plugins by `dir` and URL (`Meta.str_to_meta`). Two probe specs
  that share a `dir` merge into one plugin — give every case a unique
  directory.
- `dir` specs must point at an existing directory; the probe creates one.
- Lazy's parser reads positional `[1]` (lhs) and `[2]` (rhs). A named
  `{ lhs = ..., rhs = ... }` entry is a laze extension and is not a valid
  oracle probe; use `{ "<F9>", false }` instead.
- `Keys.resolve` takes an array. In the real path, `Plugin.values(plugin,
  "keys", true)` wraps a bare string first.
- `Spec.new(spec, { pkg = false })` parses specs without the full setup path,
  but `Config.options` must already exist for a rebuild. Prefer
  `require("lazy").setup()` for behavior questions.
- Do not infer eagerness from an empty handler map. lazy computes `lazy` from
  the raw field; this is exactly how #34's "all-false keys become eager"
  assumption turned out to be wrong.

## Turning the result into a test

- Put the measured behavior in the owning test (`tests/test_compile.lua`,
  `tests/run.lua`, or `tests/test_subset.lua` notes), not only in prose.
- Update `docs/known-differences.md` and
  `tests/fixtures/known_differences.lua` together when the result retires or
  adds a KD id.
- Re-run the full suite; parity work usually touches compile, plan, and the
  spec-surface notes at once.
