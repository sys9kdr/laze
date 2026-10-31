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
| `tests/core/plugin_spec.lua` — URL/name | `derive_name`/`pkg_name` tests in `tests/test_compile.lua`; no KD |
| `tests/core/plugin_spec.lua` — dependencies | dependency tests in `tests/test_compile.lua` and `tests/run.lua`; KD-021 |
| `tests/core/plugin_spec.lua` — optional | KD-020 |
| `tests/core/plugin_spec.lua` — duplicate fragments / opts | KD-022 |
| `tests/handlers/keys_spec.lua` | key notation aliases are not yet covered by a KD or a laze test; candidate for a follow-up |

## What this does not cover

- It does not run laze. It verifies what lazy.nvim itself does, so a KD can
  cite an executable upstream test instead of a hand-written observation.
- It does not vendor lazy.nvim implementation code.
- It does not track lazy.nvim `main` automatically. Update the pinned commit
  deliberately when auditing a newer revision.
