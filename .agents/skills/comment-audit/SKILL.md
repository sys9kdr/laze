---
name: comment-audit
description: Audit laze's source comments for restatement and bloat, then delete or compress them without losing rationale. Load manually when asked to sweep comments; never auto-invoked.
metadata:
  opencode/autoinvoke: false
---

# Audit comments

The comments in `lua/laze/` are mostly "why" and should stay that way. The
failure mode is not too few comments but comments that restate the line below
them, duplicate a neighbour, or narrate the order of statements. Sweep in
passes: classify first, then edit, then verify.

## Scope

Production code (`lua/laze/**/*.lua`) first. `tests/` comments often name the
measured upstream state and are part of the test's evidence, so only touch them
when the user asks. `---@field`, `---@param`, and `---@return` annotations are
API documentation, not comments to sweep.

## Delete

A comment earns deletion when the code below already says it:

- **Narration.** `has_route = false, -- set below`, "first do X, then Y", "set
  in the loop below". The reader can see the flow.
- **Structural restatement.** "Single `{ event = ..., pattern = ... }` table or
  the array form" above the `if` that branches on exactly that; "FileType
  autocmd pattern for the buffer-local map" above `item.ft`.
- **Duplicated fact.** A second comment saying the same thing about the same
  check (`sparse` explained twice), or a field explained in the `---@class` in
  `init.lua` and again at the use site.
- **Expression read-back.** "`range or ...` reuses the validated range",
  "`if not contains(...)` dedupes".
- **Pointer to convention already documented.** The inline-`require` parse-cost
  convention is stated in `internal/diag.lua` and `internal/dispatch.lua`;
  repeating "keep the require off startup" at every call site adds nothing.
- **Lua semantics.** "nil cannot flow through and/or", "ipairs stops at the
  first hole". Keep the consequence for laze instead of the language rule.
- **Speculation without measurement.** "Linear scan is fine" with no benchmark
  and an obviously small list. If the cost matters, cite the measurement and
  keep it; if not, drop it.

## Keep

Never delete a comment that carries information the code cannot express:

- lazy.nvim parity claims, especially with a commit or issue id (`306a055`,
  `#50`, `KD-004`).
- Measured perf numbers and the benchmark that produced them.
- Traps where a refactor reintroduces a bug: `nil` through `and/or`, `vim.NIL`
  as JSON null, `rhs == false` cancelling a mapping, feedkeys ordering,
  source-exactly-once across startup phases.
- `docs/` pointers (`docs/internal/performance.md`).
- Why a byte loop or byte compare replaces a pattern match.
- Why an invalid input is rejected at compile time instead of failing later.

ASCII byte annotations (`47` = `"/"`) are for humans even when a model would
infer them. Leave them unless the user asks otherwise.

## Compress

Rewrite rather than delete when the fact matters but the prose is loose:

- One sentence per fact. Drop trailing summary sentences ("This tracks the
  handover") that only name the variable above.
- Fold a duplicate pair into a single comment placed before the first check.
- Prefer the concrete consequence over the general rule: say what goes wrong
  (`ipairs` drops the trailing entry), not that the input is unusual.
- Keep the wording plain. No metaphors for runtime state; name the mechanism
  (`package.preload`, `:packadd!`, `VimEnter finalizer`).
- Preserve every literal: field names, ids, event names, file paths, and
  numbers are the contract.

## Verify

Comments are code-adjacent, so run the same gates: `make fast` (fast
integration, unit, subset, format check).

If a comment claimed a measurement and you cannot point at it, delete the
claim rather than the measurement. If a comment turns out to be stale (the code
now does the opposite), fix it in the same commit and note it in the message.

## Deliver

Group by intent so the diff is reviewable: one commit for deletions and one for
compressions, or a single `Trim restating comments` commit when the change is
small. Present tense, one line, optional body naming the categories removed.
