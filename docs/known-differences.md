# Known differences from lazy.nvim

This is the canonical index of deliberate differences between laze and
lazy.nvim. It is not a bug list: each entry is a design decision, a
delegation boundary, or an encoding detail.

The machine-readable mirror lives in
[`tests/fixtures/known_differences.lua`](../tests/fixtures/known_differences.lua).
`tests/test_subset.lua` keeps the two in sync: IDs must be unique, required
fields must be present, every test reference must resolve, and every ID here
must exist in the registry (and vice versa).

Related: [migration notes](migration.md), [what laze does not have](not-have.md),
and the message-policy design in issue
[#12](https://github.com/sys9kdr/laze/issues/12).

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

* `never` — docs-only. Warning on every use would be noise (for example, an
  `encoding` difference in every version spec).
* `compile` — the difference should be surfaced at compile time. `KD-020`
  already warns; `KD-016` is the first planned addition.

The registry is metadata, not runtime behavior. It does not read this file or
the test fixture at runtime.

## Active registry

IDs are stable. Never renumber an ID or reuse it for a different difference;
add a new ID instead. When a difference is resolved, remove it from the active
registry and note the removal without reassigning the ID.

| ID | Area | Class | Notify | lazy.nvim | laze | Why | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| KD-001 | version | delegated | never | No tag matches the range: falls back to the default branch. | No tag matches: `vim.pack` errors. Use `branch`/`tag`/`commit` for repos without semver tags. | `vim.pack` owns tag resolution; laze does not run a second resolver. | docs-only |
| KD-002 | version | encoding | never | `>1.2.3` starts at 1.2.4 and excludes `1.2.4-alpha`. | `vim.version.range('>1.2.3')` starts at `1.2.4-0` and includes `1.2.4-alpha`. | Neovim's `vim.version.range` owns the comparison; laze does not reimplement semver. | `tests/run.lua` |
| KD-003 | version | encoding | never | `1.2.3` is encoded as `[1.2.3, 1.2.4)`. | `vim.version.range('1.2.3')` is encoded as `[1.2.3, 1.2.3]`; stable-tag membership is the same. | The IR uses Neovim's `VersionRange`; exact versions stay exact. | `tests/run.lua` |
| KD-004 | version | safe-direction | never | Ignores `version` for `dir` plugins. | Validates the range for `dir` plugins but does not lower it (there is no pack entry). | A malformed range should fail loudly even when there is no pack entry. | `tests/test_compile.lua` |
| KD-005 | version | safe-direction | never | Does not define compound ranges; `vim.version.range` would parse only the first range or misparse a ref. | Rejects multi-ranges, whitespace-separated comparator sets, and git refs in `version`. | Silently narrowing a range would select the wrong tag; failing loudly is safe. | `tests/test_subset.lua` |
| KD-010 | triggers | extension | never | `module = false` opts out of automatic require-loading; module strings are not triggers. | `module = string` or `string[]` is an opt-in require trigger via `package.preload`; `false` means no triggers. | laze never patches global `require`; preload entries are explicit and single-shot. | `tests/test_compile.lua` |
| KD-011 | triggers | safe-direction | never | Accepts function-shaped `event`/`cmd`/`ft`/`keys` triggers. | Rejects them with a compile error. | Normalizing a function trigger to "no trigger" would make a lazy plugin eager. | `tests/test_compile.lua` |
| KD-012 | setup | safe-direction | never | `config = true` is valid and implies `opts` support. | Compile error; use `opts` with explicit `main`, or a config function. | laze does not own lazy.nvim's opts abstraction; failing loudly avoids a silent no-op. | `tests/test_compile.lua` |
| KD-013 | setup | safe-direction | never | Resolves a default `main` module from the plugin's Lua modules. | `opts` without `main` is a compile error; laze never guesses module names. | Explicit `main` keeps the pure IR deterministic and avoids loading the wrong module. | `tests/run.lua` |
| KD-014 | setup | safe-direction | never | Accepts `opts` as a table or a function mutator. | Accepts a table only; the function form is a compile error. | A mutating callback hides the final opts from the pure IR. | `tests/run.lua` |
| KD-015 | build | safe-direction | never | Accepts a list of build commands. | Accepts string, function, or `false`; the list form is a compile error. | One build command is representable; a list would need a runner laze does not own. | `tests/test_compile.lua` |
| KD-016 | keys | silent-drop | compile | Passes `vim.keymap.set` options such as `noremap`, `nowait`, `expr`, `callback`, and `buffer`. | Keeps `lhs`/`rhs`/`mode`/`desc`/`silent`; other options are dropped. | The trigger map is a laze-owned pre-load stub, not a full keymap. | `tests/test_compile.lua` |
| KD-017 | source | extension | never | Documents `dev` as boolean; a string is truthy and uses `config.dev.path`. | A string `dev` is used as the per-plugin dev directory. | laze has no global `dev.path`; `dev_path`/string `dev` make the local source explicit. | `tests/test_compile.lua` |
| KD-018 | dependencies | extension | never | Has no top-level `after` field; use `dependencies` for ordering. | `after = { ... }` orders loading after named plugins; dependency-derived `after` is merged. | laze uses `after` for explicit ordering without making a plugin a dependency. | `tests/test_compile.lua` |
| KD-019 | loading | extension | never | `silent` exists only on keys entries; top-level `silent` is not a lazy.nvim field. | Top-level `silent = true` suppresses require-failure notifications for that plugin. | laze's module trigger can fail at require time; `silent` lets optional integrations stay quiet. | `tests/run.lua` |
| KD-020 | spec | silent-drop | compile | Supports `import`, `submodules`, `optional`, and `specs`. | `import`, `optional`, and `specs` warn once per compile and are ignored. `submodules = true` matches vim.pack; `submodules = false` warns because vim.pack always fetches submodules. | laze's core is compile -> plan -> setup; spec discovery and optional resolution are outside it. | `tests/test_compile.lua` |

## Resolved differences

These IDs were resolved and removed from the active registry. IDs are stable
and are never reused.

| ID | Area | Resolution |
| --- | --- | --- |
| KD-021 | dependencies | Nested dependency specs are expanded recursively (deepest first), registered once, and shared deps are deduplicated. |

## Adding an entry

1. Pick the next free `KD-xxx` ID. Do not renumber existing entries.
2. Add the full record to `tests/fixtures/known_differences.lua`:
   `id`, `title`, `area`, `class`, `notify`, `lazy`, `laze`, `rationale`,
   and `test`.
3. Add the row to the table above with the same ID.
4. Add or point at an executable test. Use a static label that appears in the
   test file, or `docs-only: <reason>` when the difference is delegated to
   `vim.pack` and cannot be exercised in laze.
5. Run `luajit tests/test_subset.lua`. It fails if the registry and this file
   drift apart.
