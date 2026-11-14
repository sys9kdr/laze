# Performance

Internal ledger for measurements and rejected ideas; current contracts live in [design.md](../design.md) and [spec.md](../spec.md).
Status: 2026-10, Neovim 0.12.6.
Measured by `tests/run.lua perf` (ranges vary by machine and by whether the full suite or perf-only mode is used):

```
compile 50 plugins:        ~0.7–1.3 ms (threshold 20ms)
build_plan 50 plugins:     ~0.02–0.09 ms (threshold 50ms)
plan execution (30 eager): ~0.5–0.9 ms (threshold 30ms)
```

All critical paths are one-shot (compile/setup) or deferred (load time).
Nothing in the startup path scales with plugin count beyond O(N) table walks.
Items below are grouped by status.

## JIT on this engine (measured 2026-11, LuaJIT 2.1.1793383622)

This engine is a rewrite of the one the older entries below were measured on.
`jit.attach` trace/record/compile/abort callbacks never fire, and `jit.profile`/`jit.dump`/`jit.v`/`jit.util` do not exist (`pairs(jit)` yields arch attach flush off on opt os security status version version_num).
Entries citing `jit.v` output are pre-rewrite measurements and are not reproducible here.
The only surviving mechanism is fresh-process timing A/B — `tests/benchmarks/jit_ab.lua`; protocol rules and pitfalls: `.agents/skills/perf-tuning/SKILL.md`.

- Cold vs warm flips the JIT verdict on one-shot paths: the first `compile()` pass is FASTER with `jit.off()` (trace-build overhead: 0.21 vs 0.89 ms at n=40, 0.70 vs 1.33 at n=100, 2.13 vs 2.89 at n=400); the JIT wins only warm (reload×10: 0.36 vs 0.42 ms/iter at n=100, 1.20 vs 1.66 at n=400).
  Startup never warms traces.
- "Byte loops stay JIT-compiled" therefore justifies warm loops, not startup.
  A compiled byte loop runs ~0.75 ns/byte, an interpreted one ~19 ns/byte — 2.8x SLOWER than the ~7 µs/call interpreted patterns it replaced, cold.
  The `last_segment` rewrite still stands on its own measurements (patterns never enter traces at all), but re-measure with `jit_ab.lua` before citing the folklore for new work.
- `jit.off()` does not evict compiled traces, so same-session A/B silently reports 1.0x; every JIT number here comes from fresh processes, best-of-3.

## Resolved

### plan.lua: trigger bodies parsed every startup — resolved (2026-11)

The key/event/ft/cmd callbacks, the event snapshot/replay/refire helpers, and the hot-reload key sweep run only when their trigger fires, but `build_plan` parsed them on every startup.
They now live in `laze.internal.dispatch`, required inline on the first such path.
Its bodies take only the values they need; the loader state (`loaded`, startup pending + finalizer, `rtp_index`, `eager_depth`) stays in plan.lua, so the startup-ordering and hot-reload invariants are unchanged.
`load_with_deps` now returns whether the root freshly loaded, replacing the dispatchers' `loaded[id]` transition reads.
The `package.preload` body stays in plan: it needs four pieces of plan state, and widening dispatch's interface to absorb it was a worse trade than the ~5 µs it costs.

`load()` oracle (median of 60, three runs, fresh baseline worktree): plan.lua 28,926 B / 169.9–173.0 µs → 24,541 B / 127.2–133.5 µs, i.e. **-4.39 KB / ~36–46 µs per startup**.
Best-of-3 breakdown `req.plan` 253 → 215 µs.
`laze.internal.dispatch` is 5,789 B (~31 µs) and parses once at the first trigger fire; a startup that never fires a trigger never pays it.
All 184 integration tests, spawned included, pass unedited.
Issue #49.

### comment sweep: fewer bytes to parse, but not many fewer µs — resolved (2026-11, cc1d14f)

The comment trim + re-wrap (b4a9761→cc1d14f) shrank the startup-parsed trio 95,415 → 80,305 B, yet the `load()` oracle (median of 60, best-of-3, fresh tree vs baseline worktree) shows only ~11 µs: plan.lua 183.9–197.2 → 172.9–185.6 µs (disjoint bands), while compile.lua 240.1–268.8 → 244.2–257.5 µs and init.lua are flat.
End-to-end nothing moved: breakdown `req.*` phases overlap within their run spreads.
The trio extrapolated at code's 5.2–6.3 ns/B predicts -79–95 µs; the observed 0–11 µs says comment bytes lex far cheaper than code bytes (the lexer scans them to EOL without tokenizing).
Comment removal is a readability change, not a perf lever.

### plan.lua: startup command proxy body parsed every startup — resolved (2026-11)

The CmdUndefined startup bridge (the proxy installed when a command misfires before VimEnter) runs only once a startup command actually misses.
Moved verbatim from `build_plan` to `laze.internal.cmdproxy`, required inline at the CmdUndefined call site.
`load()` oracle (median of 60 in-process parses, three runs): plan.lua 40711 B / 188.2–198.1 µs → 37942 B / 169.8–177.1 µs, i.e. **-2.77 KB / ~16 µs per startup**.
Best-of-3 breakdown `req.plan` 291 → 263 µs; the parse oracle is the stable number because fresh-process deltas sit near the ±100 µs noise floor.
The new module (3.1 KB) parses only if the bridge fires.
All 184 integration tests, including the spawned proxy-replay tests, pass unedited.

### compile.lua: code only run at load time or by `version` specs was parsed every startup — resolved (2026-11)

Cold-setup breakdown (`tests/benchmarks/breakdown.lua`): requiring compile + plan + init costs ~0.85–0.95 ms of module parsing, on par with compile()'s actual work for 50 specs (~0.7 ms). Parsing scales with bytes (~5.2–6.3 ns/B measured), so code that most startups never execute is pure overhead.
Two blocks moved out of compile.lua into modules required inline at their call sites: `laze.internal.semver` (the semver scanner + range lowering, 6.3 KB, runs only when a spec carries `version`) and `laze.internal.mainmod` (the `get_main` scan of `<plugin>/lua`, runs only in the desugared `config = true` closure at load time).
`load()` oracle (median of 60 in-process parses of compile.lua): 329.7 → 229.5 µs.
Even a user who requires both modules parses less in total (271 µs vs 330 µs).
Error messages and behavior unchanged (moved verbatim); the unit tests pass unedited.

### plan.lua: SourcePre startup probe ran an interpreted pattern — resolved (2026-11)

The `startup_plugin_phase_started` probe fires on every SourcePre event — one per file Neovim is about to source — and used `find("[/\\]plugin[/\\]")`.
Patterns never enter traces; plain finds do.
Fresh-process A/B over rotating paths (`jit_ab.lua WORKLOAD=probe`): 286 → 37 ns per call with the JIT on, 304 → 65 ns with it off (two plain finds, `/plugin/` and `\plugin\`).
The absolute saving is event-count × ~250 ns, but the cost was paid on every startup regardless of plugin count.
Probe semantics unchanged (both separators, same segments).

### tests/benchmarks/compile_compare.lua: lazy.nvim profile UI inside the timed region — resolved (2026-10)

The "fair" comparison timed `require("lazy").setup()` together with `require("lazy").profile()`.
The latter opens the profile view, so the reported lazy.nvim number (and the derived speedup) included UI work that is not part of startup.
The harness also passed a non-option `profile = true` (lazy.nvim uses `profiling`).
It now runs each implementation in a fresh process, discards one warmup, interleaves five measured runs, and times only `require()` + `setup()`.
Re-measured: laze median 1.29–1.34 ms vs lazy.nvim 4.85–4.96 ms (delta ~3.6 ms), not the previous 4.8–21 ms range that mixed first-run outliers with profile UI work.

### compile.lua: pattern-based name derivation ran interpreted — resolved (2026-08)

`derive_name`/`pkg_name` used `string.match`/`gsub`, which are NYI in LuaJIT: ~7 µs/call interpreted, roughly half of per-spec compile cost.
Both now share a byte-scan `last_segment` helper (byte loops and `sub` stay on the JIT-compiled fast path): derive_name+pkg_name 11.75 → 0.8–1.3 µs/pair, 100-spec compile ~13 → ~11 µs/spec.
Equivalence with the pattern forms was fuzzed over 300k adversarial inputs (zero mismatches); the raw-fallback and sequential-suffix edge cases are pinned by unit tests in tests/test_compile.lua.
Related harness fix: tests/benchmarks/bench.lua disabled entries after build_plan — a no-op, since the plan resolves `enabled` at build time (plan.lua) — so its "plan() (no load)" number silently included eager activation attempts (~5.6 ms instead of the true ~1.9 ms registration cost).
Entries are now disabled between compile and build_plan.

### compile.lua: unsupported-field warnings paid per spec — resolved (2026-09)

`warn_unsupported` called `vim.notify` once per offending spec — measured ~180 µs per notify headless, so 20 specs sharing `optional = true` paid ~3.6 ms on every startup for the same message.
Warnings are now deduped to one per field per compile (first offending spec named): same case ~0.7 ms. Clean configs pay nothing extra (one table alloc per compile; A/B best-of-15 ×3 runs each: distributions overlap, 244–464 µs range both ways — the added work is O(1) ≈ tens of ns, far below the ±100 µs inter-run noise floor).
Pinned by a dedupe test in run.lua.

### compile.lua: diagnostics moved out of the functional core — resolved (2026-11)

`compile` called `vim.notify` on the warning paths (keys conflicts, local-dir build, missing `after`, KD notices), so a transform described as pure still emitted user-visible effects.
It now returns `diagnostics` in the IR; public `laze.compile`/`setup` flush only when the list is non-empty.
Fresh-process A/B (11 alternating processes; 100-spec clean compile, 20-spec warning compile): clean core 0.250 → 0.255 ms warm (+4 µs), clean public first 1.363 → 1.479 ms and warning public 0.399 → 0.423 ms (both inside the ±100 µs first-run floor; warning public min 0.328 → 0.313 ms), warning core first 0.370 → 0.198 ms because the core no longer notifies, all-`dir` `setup()` measured post-startup (`-l`, the `:Laze reload` path) 2.078 → 1.993 ms.
`laze.internal.diag` is required only when `#diagnostics > 0`, so clean configs pay no extra module parse.

### plan.lua: per-plugin runtimepath rescan on the startup fast path — resolved (2026-08)

The startup fast path called `nvim_list_runtime_paths()` and rescanned every entry for each plugin hitting it (`O(E × R)`).
One pass now builds a closure-local `{ pkg → dir }` index on first use; plan-owned runtimepath mutations invalidate it, and misses keep the glob + `:packadd` fallback (`reload_all()` gets a fresh plan, so no stale cache carries over).
The only stale-hit edge is third-party code removing a pack directory from `'runtimepath'` mid-startup; no known actor does that, and a module-level cache was rejected because a rebuilt plan could inherit it.
Headless micro-bench (33 rtp entries, 15 fast-path lookups): 110.6 → 9.7 µs per startup.

### plan.lua: redundant glob + `:packadd!` for already-active plugins — resolved (2026-08)

`vim.pack.add(..., { load = false })` already runs `:packadd!` per eager plugin before the plan executes; the plan's own activation then repeated a directory glob plus another `:packadd!` (an rtp-deduped no-op that still costs an API roundtrip).
During startup the plan now checks the runtimepath first (`active_pack_dir`, mirroring the glob's `pack/*/opt/<pkg>` shape and first-match rule) and skips both when the directory is present; post-startup loads keep the full path (`:packadd` without bang is what sources `plugin/`).
Also hoisted `stdpath("data")` to plan scope and added a no-deps fast path to `load_with_deps`.
Spawned-session A/B (40 specs, 20 eager): setup median ~51 ms vs ~61 ms baseline; semantics identical (eager sourced once, rtp state equal).
compile-side: removed the dead `repo_name` computation (one unused `derive_name` chain per spec): 0.37 → 0.28 ms per 50-spec compile (best-of-30).

### compile.lua: pattern-based src classification ran interpreted — resolved (2026-09)

`resolve_src` used six `:match` anchored-prefix tests per spec (`^~`, `^/`, `^%.`, `^https?://`, `^git@`).
Patterns are NYI in LuaJIT: 6-src batch 4.11 µs vs byte/`sub` prefix version 0.15 µs (~27×, `jit.v` showed `stitch string.match` side traces).
Replaced with `:byte(1)` checks and `sub` literal-prefix compares — equivalence with the pattern forms fuzzed over 200k adversarial inputs plus targeted edges (zero mismatches).
End-to-end compile delta is inside run noise (the component is ~10% of per-spec cost), but the win is micro-proven and the shape matches the existing `last_segment` precedent.
Same replacement applied to the `dir`/`dev`/`dev_path` `^~` tests.

### compile.lua: per-spec table literals — resolved (2026-08, c8ac8e5)

`validate_triggers`/`validate_spec` built `{ "event", "ft", "cmd", "keys" }` etc. per spec — LuaJIT does not fold constant table constructors in loops, so most of the compile time went to throwaway allocs and GC.
Hoisted to module constants: 1000-spec compile 27.1ms → 11.5ms (2.3x), real-plugin cold start 9.58ms → 7.19ms.

### plan.lua: one autocmd per event name — resolved (2026-09)

`plan()` created one autocmd per distinct event (~12 µs each).
`nvim_create_autocmd` accepts an event list in one call, so variants sharing a pattern are now wired by a single call dispatching on `ev.event` (100 distinct events: ~130 µs saved, ~10 µs at realistic scale; no memory win — nvim still stores N rows).
Routes are modelled per distinct `(event, pattern)` variant, so different patterns for the same event are separate buckets (separate calls) while the patternless bucket stays unrestricted.
`once = true` is per-event-row (verified: rows self-delete independently), so fire-once semantics are unchanged.
VeryLazy stays separate (not a real event).
Required a compile-side fix found by the new tests: Neovim stores `BufRead`→`BufReadPost`, `BufCreate`→`BufAdd`, `BufWrite`→`BufWritePre` (verified by create + read-back), so route keys are canonicalized in `normalize_events` — the grouped dispatch matches on `ev.event`.

### plan.lua: N per-trigger autocmds for ft/cmd routes — resolved (2026-09)

`plan()` created one `FileType` autocmd per distinct ft and one `CmdUndefined` autocmd per cmd (~12–15 µs of API cost each — 100 distinct fts measured 1513 µs, 100 cmds 1227 µs for registration alone).
Both are now a single `*`-pattern dispatcher that does an O(1) `routes` hash lookup on `ev.match` (100 fts → 13 µs, 100 cmds → 12 µs).
Per-plugin idempotency comes from `load_with_deps`' `loaded[]` guard (the old per-ft `once` self-delete is subsumed by it); misfires on unrelated filetypes/commands cost one hash miss.
Events were already one autocmd per event name; keys need one mapping per `(lhs, mode)` variant by nature (`vim.keymap.set`, ~15 µs each — accepted, inherent API cost).

### plan.lua: O(N×M) route scan on every startup — resolved

Formerly `plugin_has_routes()` walked all routes × entries × IDs per plugin (O(N×M)).
Now `has_route` is computed **at compile time** per registry entry (compile.lua: `#norm.event > 0 or #norm.ft > 0 or #norm.cmd > 0 or #norm.keys > 0 or module trigger`) and the plan's eager loop is O(N) with O(1) per entry (`entry.has_route`, plan.lua).

### plan.lua: `_G.require` wrapper — resolved (replaced by `package.preload`)

Module triggers were implemented by replacing `_G.require` at plan build time — a per-require call overhead on **every require in the session**, even without `module` fields.
Now each trigger is a `package.preload` entry (plan.lua): zero interception of unrelated requires, no global mutation, and each entry consumes itself on first require (single-shot).
`installed_preloads` tracks entries across `build_plan` calls so hot reloads clear stale closures.
Regression-tested in `tests/run.lua` (unrelated requires untouched, entry consumed, stale entries cleared).

### plan.lua: `vim.keymap.del` + `nvim_feedkeys` — resolved (design pinned)

Takeover keys (no `rhs`): delete the trigger mapping **before** loading (`vim.keymap.del` removes *every* map for the lhs — deleting after load would kill the plugin's own fresh map), then replay with `nvim_feedkeys(_, "", true)` (default flags; no `"n"` no-remap — the plugin's own map must receive the key).
`<leader>` expands against the current `g:mapleader` at replay time.
See plan.lua.

## Accepted by design (no action)

### compile.lua: `vim.fn.expand` per dev spec

One `expand()` API call per dev spec, compile is one-shot.
Reads `$HOME`.
Acceptable.

### plan.lua: `vim.keymap.set` with function callback

Registering a Lua callback is an API call at plan time (one mapping per lhs × mode — `{ "n", "v" }` creates two); the callback only runs on keypress.
No I/O at setup.

### Load-time I/O (the point of lazy loading)

Each lazy activation of a pack plugin does: one `:packadd` (vim.cmd), one glob for the pack directory (plan.lua), one glob for `after/plugin/**/*.{lua,vim}` (post-startup only), and `require` of **explicitly declared** `module` names — never derived from the source.
Dir plugins instead prepend to `'runtimepath'` and source `plugin/` + `ftdetect/` globs manually.
Startup-requested lazy plugins defer all sourcing to the `VimEnter` finalizer.
This is deferred I/O by design.

### compile.lua: version range lowering

`validate_spec` validates a range and returns the `VersionRange` so `resolve_version` reuses it; a range that cannot win precedence is not parsed.
Each used range is parsed once.
This is new work relative to main, which only converted `"*"`: 100 versioned specs ~0.20–0.22 ms vs ~0.06 ms before; 100 plain specs unchanged (~0.07 ms). The cost is inherent to faithful lowering, not a regression in an existing path.
(Since 2026-11 the scanner lives in the lazily-required `laze.internal.semver`; see Resolved.)

A `version` spec's first-use cost is module loading, not parsing: `require("vim.version")` ~0.15–0.27 ms plus `require("laze.internal.semver")` ~0.12 ms, against ~0.005 ms for `to_semver_range("*")` itself.
It does not stop at laze: vim.pack writes the lowered range into the lockfile and re-runs `vim.version.range()` over it on every later startup, so both modules load before laze is asked anything.
A 15-spec config carrying one `version = "*"` spec measured 9.67 → 9.34 ms startup and 2.99 → 2.63 ms `laze.setup()` with that spec removed (12 alternating fresh processes).
A `"*"` fast path skipping `semver` was prototyped: 0.11 ms of `compile()` (the `vim.version` load stays, paid by vim.pack) for a second copy of `with_lower_prerelease`'s prerelease rules — rejected.
The cheap fix is the spec, not laze.

### Compile-time micro-items (negligible, one-shot)

- `normalize_array`/`normalize_events`/`normalize_keys` allocate fresh tables even for already-array inputs
- DFS cycle detection is O(depth²) — fine for typical chains (< 5 levels); a depth-limited hash set would fix deep graphs
- `CONSUMED_KEYS` passthrough filter iterates `pairs(spec)` per spec

### Rejected (design decisions)

- **async loading** (`vim.uv.spawn` around `vim.pack.add`): `vim.pack.add` guarantees synchronous install, so eager and trigger loads work even in a first session.
  Async would complicate startup ordering against the small-core principle; first-install blocking UX belongs to vim.pack.
- **dev auto-reload via file watching**: `reload_all()` invoked manually gives the same effect; watching adds process management, debouncing and recursion control for no gain.
  Three lines of `vim.uv.fs_event` in your own config do it if wanted.
- **perf regression tests in CI**: local thresholds risk flaking on CI machines; they stay in `tests/run.lua perf` (run locally).

### Rejected (measured — re-proposing needs new numbers)

Zero-based audit 2026-09 (5 profilers, all claims warmed best-of-N or spawned medians; rejections below were each A/B'd against the real function, not microbenchmarked in isolation):

- **loading laze via `rtp:prepend` instead of `vim.pack.add`**: `vim.pack` manages only `site/pack/core/opt`, so the prepend is a valid `:packadd!` equivalent, but it only skips laze's own add.
  Measured post-startup (`-l`, laze also in the `setup` specs): add 5.939 vs prepend 5.958 ms; without laze in the specs, 5.903 vs 5.633 ms (+0.270 ms for add); all-`dir` setup 2.963 vs 2.113 ms (+0.850 ms).
  Add-only vs prepend-only: 0.72 vs 0.02 ms.
  The shortcut also leaves `active = false` and skips `PackChanged` for laze; keep the plain idempotent `vim.pack.add`.
- **listing laze in its own `setup` specs**: no install/update/load effect (`vim.pack.update()` covers the lockfile + `opt` scan, and `:Laze clean` now excludes the running plugin), so there is nothing to dogfood.
  Cost of one extra eager pkg spec (15 git plugins added first): startup 3.899 vs 3.817 ms — noise; post-startup setup (`-l`) 5.838 vs 5.987 ms (+0.149 ms) because every eager pkg entry pays a glob + `:packadd` + `after/plugin` glob there.
  In-process `compile` + `build_plan` marginal: ~0.
- **rtp symlink-farm** (neobundle-style consolidation): full runtime-file search drops ~130–440 µs at 30 plugins (~4.5 µs/entry), but laze's lazy plugins already never touch rtp, so the saving is ~0.1 ms級 per file event against a parallel source-of-truth (rebuild hooks on every install/update/del), loss of vim.pack activation, and silent symlink staleness.
  Eager→lazy conversion (≈0.1 ms/plugin) dominates it.
- **`vim.pack.add` 2-call → 1-call merge**: medians 3011 vs 3015 µs — identical.
  The split's price is the ~3–20 µs empty-call floor.
  Re-checked 2026-11 with the merge written out (`load` is per-call, so one callable branches on eager vs lazy and replicates `:packadd!`): `laze.setup()` 2.665/2.975 ms split vs 2.710/3.077 ms merged (min/median, 18 alternating fresh processes), same `'runtimepath'` afterwards.
  Nothing to recover — `lock_read` returns as soon as `plugin_lock` is set, so only the first call reads the lockfile and runs `lock_sync`, and the per-spec normalize/validate runs once either way (empty `add` 4–14 µs warm, a re-added installed spec ~20–30 µs).
  The merged form would also take over `:packadd!`'s name escaping and the post-startup `after/plugin` sourcing that vim.pack owns today.
- **keys raw-API swap / opts trimming**: true floor is ~8 µs/map (API+store ~6.3, callback ~0.7, wrapper ~1.0 — measured decomposition), recoverable ≤ ~1.5 µs/map.
  Reimplementing wrapper semantics for that is not worth it.
- **`table.insert` → `t[#t+1]`, `pairs` → `ipairs`, hash → array dispatch**: micro wins exist; real-`compile()` A/B shows no end-to-end delta (noise-dominated, stock faster in 2/3 reps).
- **eager-sort comparator hoisting, `fs_stat` glob guard, dep/after hash-set dedup, cycle-scan hash set**: each micro-proven, each end-to-end invisible or negative at realistic sizes (after-chains ≤ 5, dep lists < 10).
  Hash sets only win past ~100 entries, which never occurs.
- **comment stripping** (61 → 38 KB): reversed-order A/B flips the apparent win — distributions fully overlap.
  Lexer comment-skipping is ~10× cheaper per byte than code parsing; max realistic diet ≤ ~0.1 ms.
- **`jit.off()` around require**: measured worse (+0.5 ms).
- **`jit.off()` around the `compile()` body**: prototyped and measured — the first `compile()` on 15 real specs drops 1.02 → 0.40 ms, `laze.setup()` 2.81 → 1.88 ms, and end-to-end startup 9.00 → 8.16 ms (10 alternating fresh processes, `--startuptime`).
  The cold path never amortizes trace construction, so the win is real and reproducible.
  Not adopted: a library flipping global VM state around a call is surprising for callers (a nested or profiled `compile` silently runs interpreted), and restoring it on the error path needs `pcall`, which drops the traceback for internal errors.
  Callers who want it can wrap `laze.compile` themselves.
  Distinct from the `require` variant above, which also moved module parsing off the JIT and measured worse.
- **startup-mechanism cuts** (pending queue, cmd proxy, ft catch-up, VeryLazy bridge, lazy rtp_index): always-paid total ≈ 2 µs; removal buys E492 / silent non-load / late-UI regress.
  All kept.
- **`resolve_src` further work**: byte/`sub` form already landed; the remaining per-spec cost is table construction (compile purity forbids reuse) — no further action.

## Open items

- Startup parsing is one module per component: setup parses only compile + plan + init (~0.8–0.95 ms; the `internal/` helpers are required inline at first use).
  The first-fire bodies moved to `laze.internal.dispatch` (-4.39 KB, ~40 µs; see Resolved), leaving the VimEnter startup finalizer (~1.2 KB, ~7 µs) as the only cold body still in plan.lua.
  Moving it would hand `source_glob`/`run_hooks` state to the dispatch module to save one VimEnter-only parse.
  `laze.loader` was dropped: its contents run during plan build/execution, so extraction is parse-neutral.
  Design: issue #49.

New hot paths must land with a perf regression test in `tests/run.lua perf` (asserted thresholds) or a note here explaining why the threshold doesn't apply.

## Instrumenting load time

Hooks belong to the execution plan, not the compiler — `build_plan` takes two optional hooks (`setup` passes them through).
Measure plugin load time in a few lines — no wrapper module needed:

```lua
local compiled = laze.compile(specs)
local timings = {}
laze.build_plan(compiled, {
  on_load = function(id, ms) table.insert(timings, { id = id, time_ms = ms }) end,
  on_fail = function(id, err) vim.notify(id .. ": " .. err) end,
})()
-- later: for _, t in ipairs(timings) do print(("%6.2f  %s"):format(t.time_ms, t.id)) end
```

## Benchmarks

Standalone benchmarks for manual profiling (not part of CI); each is a `Makefile` target:

```sh
make bench             # cold/warm start + profile breakdown (bash)
make bench-lua         # Lua micro-benchmark (μs scale, multiple sizes)
make bench-compile     # laze.nvim only: setup cost
make bench-compare     # fair comparison: laze.nvim vs lazy.nvim
make bench-breakdown   # cold-setup breakdown (BENCH_BREAKDOWN_N=50)
make bench-parse       # parse-cost oracle (median-of-60 in-process load())
make bench-jit         # JIT A/B oracle, compile (fresh process/row; BENCH_JIT_N=100)
make bench-jit-pro     # JIT A/B oracle, probe workload (JIT=on|off)
```

Latest manual run (2026-10-29, Neovim 0.12.6, 4 real dir plugins): `compile_only` cold 1.45–1.72 ms / warm median 1.00–1.43 ms (3 runs); `compile_compare` laze median 1.29–1.34 ms vs lazy.nvim median 4.85–4.96 ms, delta ~3.6 ms (3.7x).
Each implementation runs in a fresh process; one warmup run is discarded and the median of five interleaved runs is reported.
The timed region is `require()` + `setup()` only.
The specs use eager/`ft`/`cmd` triggers only: `VeryLazy` is excluded because laze fires it immediately in headless mode while lazy.nvim defers it, which would make the setup comparison asymmetric.

All four specs are `dir`, so laze does no `vim.pack.add` and lazy.nvim does no install: this compares setup/registration, not the install path or full process startup.
`bench.sh` startup numbers are dominated by process startup.
