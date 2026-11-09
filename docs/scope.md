# Who laze is for (and who it is not for)

laze exists so that a hand-written lazy.nvim-style config keeps working on
top of Neovim's native `vim.pack`. It is a small compatibility layer, not a
general plugin manager: installation, ref/tag resolution, and dependency
solving stay with `vim.pack`.

## Intended user

You write (or copy) specs by hand — often from a plugin README — and want:

* lazy.nvim's declarative spec shape for the common fields, with
  lazy-loading on `event` / `cmd` / `ft` / `keys` / `module`;
* `vim.pack` to own installation, updates, and the lockfile;
* no dashboard, commands, or update UI in your startup path.

A design goal is a **cheap escape hatch**: the subset is chosen so that a
laze config is also a valid lazy.nvim config. When laze rejects an input, it
does so loudly at compile time rather than silently changing behavior
(the `safe-direction` class in [known-differences.md](known-differences.md)).
Moving back to lazy.nvim is therefore mostly deleting `require("laze")` and
calling `require("lazy").setup()` instead.

## Not targeted

These are deliberate non-goals, not a roadmap. Details and alternatives are
in [not-have.md](not-have.md).

* **Composition features.** lazy.nvim's spec merging (including `opts`
  merging), `import`, and automatic collection of scattered spec files.
  laze warns and ignores `import` / `specs` / `optional`; load your spec
  files yourself and pass the tables in.
* **A manager UI or command suite.** No dashboard, install/update UI, or
  command surface in the core. `laze.extra` is an opt-in module for a few
  maintenance commands; otherwise wire your own around `vim.pack`.
* **Reimplementing `vim.pack`.** Installation, update, lockfile, and
  ref/range resolution are delegated, not wrapped.
* **Silent emulation.** Function-shaped triggers and non-semver `version`
  strings are compile errors. If honoring an input would require guessing,
  laze rejects it instead.

If your config depends on composition or a full manager UI, stay on
lazy.nvim; porting the specs later is mechanical when you only need the
declarative subset. See [migration.md](migration.md) for the field-by-field
conversion.

## Where to go next

* [migration.md](migration.md) — what works as-is, what needs an edit, what
  is rejected.
* [known-differences.md](known-differences.md) — the canonical, stable-ID
  index of deliberate differences.
* [not-have.md](not-have.md) — the full "won't do" list with alternatives.
* [design.md](design.md) — the IR and activation model.
