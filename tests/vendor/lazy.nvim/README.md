# Vendored lazy.nvim tests

This directory pins a small part of lazy.nvim's own test suite as a
**behavioral oracle** for laze's known-differences (KD) decisions. It is
not part of laze's CI: the tests exercise lazy.nvim internals and need a
lazy.nvim checkout plus the test dependencies that `lazy.minit` installs.

## Provenance

- Upstream: <https://github.com/folke/lazy.nvim>
- Pinned commit: [`306a05526ada86a7b30af95c5cc81ffba93fef97`](https://github.com/folke/lazy.nvim/tree/306a05526ada86a7b30af95c5cc81ffba93fef97)
- License: Apache-2.0, © Folke Lemaitre and contributors
- Full license text: [`LICENSE`](LICENSE)
- Attribution and file list: [`NOTICE`](NOTICE)

Vendored files:

```
tests/minit.lua
tests/manage/semver_spec.lua
tests/handlers/keys_spec.lua
tests/core/plugin_spec.lua
```

Each file keeps its upstream content; only a provenance header was added.

## Run

```sh
# lazy.nvim checkout (the same default used by the benchmarks)
LAZY_DIR=/tmp/lazy.nvim tests/vendor/lazy.nvim/run.sh
```

The first run may install `luassert` and `mini.test` under the lazy.nvim
checkout's `.tests/` directory, so it needs network access. Later runs are
offline.

## What this covers

| Upstream test | Relevant laze coverage |
| --- | --- |
| `tests/manage/semver_spec.lua` | `tests/fixtures/lazy_semver_cases.lua`, `tests/run.lua`; KD-002, KD-003, KD-005 |
| `tests/core/plugin_spec.lua` — URL/name and spec lists | `derive_name`/`pkg_name` and bare-string/nested-list tests in `tests/test_compile.lua`; no KD |
| `tests/core/plugin_spec.lua` — dependencies | dependency tests in `tests/test_compile.lua` and `tests/run.lua` (name/source matching, disabled/cond pruning); KD-021 |
| `tests/core/plugin_spec.lua` — optional | KD-020 |
| `tests/core/plugin_spec.lua` — duplicate fragments / opts | KD-022 |
| `tests/handlers/keys_spec.lua` | raw-lhs route test in `tests/test_compile.lua`; KD-023 |

## Audit findings

The first run against the pinned commit (2026-10-31) passed all 139 upstream
cases and produced these laze changes:

- **Spec lists:** bare source strings, nested lists, and a single spec table
  are accepted, mirroring `Spec:normalize`; sparse lists are rejected rather
  than silently truncated.
- **Dependencies:** a dependency is matched by explicit name, derived name,
  and resolved source. A renamed top-level spec (for example
  `{ "foo/baz", name = "bar" }`) is no longer registered twice when
  another spec depends on `"foo/baz"`.
- **Disabled/cond-false parents:** their dependency fragments are not
  registered, matching lazy.nvim's `enabled = false` / `cond = false` cases.

Still intentionally different (see the KD registry):

- duplicate spec fragments are merged by lazy.nvim and rejected by laze
  (KD-022);
- `optional = true` does not make dependencies optional in laze (KD-020);
- nested dependencies are not expanded (KD-021);
- key notation aliases are separate raw-lhs routes, so two spellings can
  replace each other's trigger map (KD-023);
- a table-valued `config = { ... }` is lazy.nvim's deprecated opts form and
  is still a compile error in laze. This is a candidate for the opts/main
  work in PR #15 rather than a new KD yet.

## What this does not cover

- It does not run laze. It verifies what lazy.nvim itself does, so a KD can
  cite an executable upstream test instead of a hand-written observation.
- It does not vendor lazy.nvim implementation code.
- It does not track lazy.nvim `main` automatically. Update the pinned commit
  deliberately when auditing a newer revision.
