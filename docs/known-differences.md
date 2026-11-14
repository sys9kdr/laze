# Known differences from lazy.nvim

This page defines the vocabulary and notification policy.
The registry itself is data, in [`tests/fixtures/known_differences.lua`](../tests/fixtures/known_differences.lua): `active` holds the current differences, `resolved` retires IDs without reusing them.
`tests/test_subset.lua` validates the records and checks that every `notify = "compile"` entry has a matching call site in `lua/laze/compile.lua`.

Related: [migration notes](migration.md), [what laze does not have](not-have.md), and the message-policy design in issue [#12](https://github.com/sys9kdr/laze/issues/12).

## Baseline

The subset is measured against lazy.nvim's documented spec at <https://lazy.folke.io/spec>, fetched **2026-08-18**.
Coverage targets documented fields; undocumented behavior that happens to work is not part of the contract.

The vendored behavioral oracle in [`tests/vendor/lazy.nvim/`](../tests/vendor/lazy.nvim/) is pinned to lazy.nvim commit [`306a055`](https://github.com/folke/lazy.nvim/tree/306a05526ada86a7b30af95c5cc81ffba93fef97).

## Classes

| Class | Meaning |
| --- | --- |
| `safe-direction` | laze rejects a lazy.nvim-valid input loudly. A laze config remains valid for lazy.nvim; the reverse may need an edit. |
| `delegated` | The behavior is owned by `vim.pack` or Neovim, not laze. laze documents the boundary instead of reimplementing it. |
| `extension` | A laze-only field or value shape. lazy.nvim ignores it; see the migration note for the reverse conversion. |
| `encoding` | The same effective behavior for ordinary stable tags, but a different IR or a different edge case. |
| `silent-drop` | laze accepts the input but does not honor all of it. It warns where possible; the entry records the gap. |

## Message policy

`notify` is the policy for issue [#12](https://github.com/sys9kdr/laze/issues/12):

* `never` — docs-only.
  Warning on every use would be noise (for example, an `encoding` difference in every version spec).
* `compile` — surfaced at compile time with a `vim.notify` WARN that names the KD id and this file.
  Messages are deduped per compile, so many specs sharing one difference cost one notification.
  Opt out with `compile(specs, { known_differences = false })` (or the same option to `setup`).
  The runtime formatter is [`lua/laze/internal/known_differences.lua`](../lua/laze/internal/known_differences.lua).

## Adding an entry

1. Pick the next free `KD-xxx` ID.
   Do not renumber existing entries or reuse retired IDs.
2. Add the full record to the `active` list in [`tests/fixtures/known_differences.lua`](../tests/fixtures/known_differences.lua): `id`, `title`, `area`, `class`, `notify`, `lazy`, `laze`, `rationale`, and `test`.
3. Add or point at an executable test.
   Use a static label that appears in the test file, or `docs-only: <reason>` when the difference is delegated to `vim.pack` and cannot be exercised in laze.
4. When the lazy.nvim side is covered by an upstream test, cite the vendored oracle in [`tests/vendor/lazy.nvim/README.md`](../tests/vendor/lazy.nvim/README.md) instead of relying on a hand-written observation.
5. When the difference is resolved, move the record to `resolved` with the release/description and a note.
   Keep the ID retired.
6. Run `make test-subset`.
