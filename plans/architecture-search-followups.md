# Architecture search follow-ups

> Status: needs author scoping - three items left over from the 2026-09-12
> architecture search (331be78..d7bb8da). Each has evidence and, for two of
> them, an unlanded prototype. Nothing here is started on `main`.

The search itself is closed. Its confirmed deletions, performance changes,
and bug fixes are on `main`; its library removals were reverted and repaired
in `d7bb8da`. The rejected hypotheses and their evidence are recorded in the
brazzaville workspace under `.context/arch-search/REPORT.md` and need no
plan. These three items were found on the way and remain worth doing.

## 1. Parallel translation in `x2c build -j N`

`x2c build` never translates units in parallel. `_build_translation_request`
in `src/main.x` builds one-input requests, so the `total > 1` condition that
forks translation workers is never true, while the `--jobs` help text in
`src/cli.x` promises parallel translation. Measured on lib: `translate -j1`
2.53 s against `-j16` 0.58 s, so a cold manifest build spends about 6.8 s in
serial translation that is about 1.6 s parallel.

Design: hand the translation phase one multi-input request so the existing
worker path engages; give each unit its own output directory so units that
share a stem cannot collide; use one slice per unit on the build path so a
unit's recorded prerequisites reflect its own parse rather than what an
earlier unit in the same worker left in the process cache, because build
reuse is decided from those prerequisites. Generated C must be byte-identical
across `-j1` and `-j N`, and failures must propagate as before.

A prototype implementing exactly this exists, staged and never gated, in
`/Users/gary/Git/x2c/.claude/worktrees/agent-a70d3375abbcd2bd3` (main.x,
a `run-build-parallel.sh` probe, cli.md text). It predates `d7bb8da` and
must be rebased and re-verified against current `src/build.x`.

Validation: the probe asserting worker count under `--verbose`, `-j1` versus
`-j4` output identity for src+lib, the CLI boundary probes, then
`tools/gate-state.py ensure agent-pr-check`.

## 2. No-op `x2c build` still preprocesses every object

An up-to-date retained build runs `cc -E` per object to recompute its
fingerprint: measured 1.18 s for a no-op build of the repository against
0.10 s for `make`. The archived plan `archive/native-build-reuse.md`
overlapped that work with compilation but did not remove it for objects the
state file already covers.

Design: when the recorded state for an object matches the request options,
the compiler hash, and the source and header prerequisites the depfile
already lists, skip preprocessing and treat the object as current. Keep the
preprocessed-input fingerprint for any object whose prerequisites changed,
so new include shadowing is still caught. Estimated at under ten lines in
`src/build.x`; not implemented.

Validation: unchanged-build and one-file-edit timings at `-j1` and `-j N`
compared with the table in the archived plan; a probe that changes a header
found through a new shadowing directory still recompiles.

## 3. Total Lisp lowering

`lib/lisp.x` compiles a lambda to the machine only when every subform is
eligible; about twenty named rejection reasons send the whole lambda to the
tree-walking evaluator, which recurses on the C stack. A `def` inside a body
is one such reason, so a `def`-carrying recursion 100,000 deep segfaults and
a 200-deep one takes 1.1 ms.

Design: one opcode, `MW_LEVAL` generalizing `MW_LPRECALL`, hands a declining
subform to `Lisp.evaluate` over the machine frame's existing `LispEnv`, with
a builder rewind so a partially lowered body is released. Every lambda then
compiles; the per-form rejection list goes. The parameter-count and rest-
parameter limits stay, because they are frame limits, not body limits; the
warm-up counter, `auto_specials` guards, and `Lisp.auto_disable` stay for
the reasons the prototype report records.

Measured in the prototype: the 100,000-deep case runs correctly in 113 ms,
`def`-in-body 200 deep goes from 1.100 ms to 0.098 ms, 800 unit tests and
646 fixtures byte-identical, self-translation unchanged. Net +45 authored
lines; this is a behavior fix, not a simplification. The prototype is in
`/Users/gary/Git/x2c/.claude/worktrees/agent-a42a88f532b23d9e2` and its
report is `.context/arch-search/experiments/macros-h1-total-lowering.md`
in the brazzaville workspace. Two Lisp tests that asserted rejection reasons
were rewritten there, not deleted.

Validation: Lisp and Func suites, the `lisp-auto` gate lane, macro and
inline-Lisp fixtures, a deep-recursion probe, and one `agent-pr-check`.

## Recorded, not planned

- `etc/header-symbols.xlisp` replay adds 74 generated-protocol rows that a
  cold raw walk does not produce, so cached and cold collection disagree
  today. The rows looked inert. Worth a check when the collector is next
  touched.
- `struct VarMethods` in `lib/common.x` is a hand copy of the protocol row
  set; a row added without a field silently loses its dynamic route.

## Plan review

Facts established elsewhere: the translation worker path, output-directory
layout, and depfile prerequisites already exist in `src/main.x` and
`src/build.x`; item 1 routes the build through them and adds no second
scheduler. Item 2 trusts the state file and depfile the build already
writes; it adds no new fingerprint. Item 3 reuses the machine's existing
evaluator re-entry and `LispEnv`; the one new opcode replaces a rejection
list rather than adding a route.

Nothing here introduces a cache, a representation, or a validator. Item 1's
probe and item 2's shadowing probe protect deterministic output and correct
rebuilds, which are documented build behavior. Item 3 has no negative
fixture; the rewritten Lisp tests cover the rewind's program release.
