---
name: perf-tuning
description: Measure real startup cost before claiming a laze change is fast or slow. Use when a change touches compile/plan/setup, when a JIT or "the compiled path stays hot" folklore claim is made, when a perf difference needs an executable oracle, or when re-proposing something from the rejected list in docs/performance.md.
---

# Measure startup cost

laze's hot paths are one-shot (compile/setup) or event-driven (per autocmd
fire), so the number that ships is almost always the first-run number. "This
is O(1), so it is fast" and "this stays on the JIT" are empirical claims:
fresh process, run, measure. Comments and folklore are not the oracle; a
measured number encoded in a test or doc is.

## Workflow

1. Identify what runs in production: one-shot (cold, no warmed traces) or
   repeated in-process (`reload_all`, per-event probes). A rewrite that only
   wins warm never wins at startup.
2. Baseline before the change, apply it, then A/B in fresh processes —
   [tests/benchmarks/jit_ab.lua](../../../tests/benchmarks/jit_ab.lua) shows the
   protocol (`make bench-jit` runs it from the repo root):

   ```sh
   for r in 1 2 3; do nvim --clean -l harness.lua; done   # best-of-3 per side
   ```

   The inter-process noise floor is ±100 µs (process startup), so a µs-scale
   claim needs an in-process N-loop micro-harness, and an end-to-end sub-ms
   claim needs best-of-3 ×3 before it is real.
3. Encode the number: a `tests/run.lua perf` threshold, a docs/performance.md
   Resolved entry with before→after figures, or both. Entries under
   "Rejected (measured)" are law: re-proposing requires new numbers.
4. Only propose JIT-shaped rewrites (byte loops, pattern-free probes,
   hoisting) when the measurement shows they win in the mode that runs —
   usually cold. See the JIT facts before repeating an old comment's claim.

## JIT facts (measured on this engine: LuaJIT 2.1.1793383622, Neovim 0.12.6)

The engine was rewritten out from under the older comments; re-run
jit_ab.lua after engine bumps.

| Folklore claim | Measured |
| --- | --- |
| Startup warms traces | No: the first run pays trace construction. 100-spec `compile()`: 0.70 ms with `jit.off()` vs 1.33 ms with jit on |
| JIT wins on repeated code | Only warm: reload×10, 0.36 vs 0.42 ms/iter (n=100), 1.20 vs 1.66 (n=400) — helps `reload_all`, not startup |
| Byte loops beat patterns | Warm only: byte loops run 0.75 ns/byte compiled but ~19 ns/byte interpreted, slower than the ~7 µs/call interpreted pattern they replaced; cold, patterns win |
| `find(…, true)` beats pattern `find` | Yes, both JIT states: SourcePre probe 286→37 ns/call (jit on), 304→65 (off). Patterns never enter traces; plain `find` does |
| `jit.off()` evicts traces | No: already-compiled code stays compiled. Same-session warm-then-off A/B silently reports 1.0x |

Introspection is gone on this build: `jit.attach` trace/record/compile/abort
callbacks never fire, and `jit.profile`/`jit.dump`/`jit.v`/`jit.util` do not
exist (`pairs(jit)` yields only arch attach flush off on opt os security
status version version_num). Fresh-process timing A/B is the only mechanism
left — old doc entries citing "jit.v showed …" are not reproducible here.

## General levers (all measured in this repo)

- `vim.notify` costs ~180 µs headless per call: dedupe or defer anything on
  a per-spec or per-event path.
- API calls dominate table work: `nvim_create_autocmd` ~12–15 µs each,
  `nvim_exec_autocmds("FileType")` ~876 µs even with no handlers. One
  dispatcher + O(1) hash lookup in the callback beats N registrations.
- LuaJIT does not fold constant table constructors in loops: hoist invariant
  `{ … }` literals to module scope.
- Build an index once instead of rescanning (O(E×R) → one hash miss), and
  invalidate on your own mutations.
- `require` cost is parse+execute: keep rare paths (error formatting,
  notify) behind an inline `require` at the call site so the module is
  parsed only when the path fires.
- Patterns (`match`/`gsub`/`find` without `plain`) never compile: use
  `byte`/`sub` prefix checks or plain `find` for fixed-shape hot-path
  probes — but verify with cold numbers, not warm.

## Pitfalls (each one made a measurement lie before being fixed)

- Same-session A/B: traces survive `jit.off()` — fresh process per row.
- Constant input in the timed loop: the engine hoists loop-invariant pure
  calls (measured `s:find(…)` at ~1 ns that way). Rotate inputs.
- `nvim -l script.lua extra` does not expose `extra` via argv — pass env vars.
- Warm-only timing: report cold and warm separately; jit_ab.lua prints
  `first=` and `reload10=` for exactly this reason.
- A single sub-100 µs end-to-end delta is noise until best-of-3 ×3 says
  otherwise.
