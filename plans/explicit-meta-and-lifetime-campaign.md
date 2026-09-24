> Status: active
> Updated September 23, 2026. Scope decided by Gary on September 23,
> including the piece 0 deletions below. Stabilization and its scope strip
> reached `dev` as `9b71607f`; this campaign starts from that commit.

# Next phase: explicit meta calls, lifetimes, and computed values

Make compile-time execution explicit, give meta code working lifetimes,
computed collection results, and heap objects, and prove the result with
bounded internal adoption. First delete the machinery that no requirement
established, so the new capabilities build on a smaller evaluator.

## Baseline

Start from `9b71607f`, the `dev` commit that delivered the
[stabilization plan](post-merge-stabilization-2026-09-23.md) and its scope
strip. Line references below were read at `3962fb35`, before the strip;
recheck each against the current tree. Survey notes
with more detail are in the handoff session's
`.context/next-phase-survey-2026-09-23.md`; copy that file into the new
worktree's `.context/`.

The earlier [heap-object investigation](meta-heap-objects.md) is background.
Its speculative folding rules and blanket deferral of Scope cleanup are
superseded by this plan.

## Decisions

Gary decided these on September 23, 2026:

- `$f(args)` runs at compile time and inserts its result. A bare `f(args)`
  always calls the compiled function. Automatic folding is removed.
- Packed layouts stay unsupported. A packed attribute on a struct x2c parses
  is a compile error; `#pragma pack` passes through to the C compiler.
- Meta record layouts cover structs defined in x2c units only. Structs from
  C headers decline in meta code. `--system-headers` is removed.
- Function-local statics decline in meta code.
- `Func` carriers stay; their argument preparation moves to its owner.
- The compound List selectors (`caaar` through `cdddar`, depth 3 and 4) stay
  available in compiled x2c, in meta functions, and in compile-time Lisp, from
  one definition. Compile-time Lisp gains the depth-4 names it lacks today.
- The meta API coverage inventory, bindings with no caller, the cross-unit
  region tool, and the advisory reports listed in piece 0 are deleted.

## 0. Delete unrequested machinery

Each item is a separate commit with its own focused check. Counts are
estimates from reading source.

1. **Meta API coverage inventory (~1,470 authored, ~3,700 generated).**
   Delete `tools/meta-api-coverage.py`, `tools/meta_api_disposition.py`,
   `docs/src/guide/meta-api-coverage.md`, its `docs/src/SUMMARY.md` entry and
   `site/public/llms.txt` line. Replace the link paragraph in
   `docs/src/guide/meta-functions.md` (~808) with one sentence pointing to the
   operations that chapter documents. Mark the coverage work in
   `plans/meta-authoring-and-coverage.md` as retired.
2. **Var numeric internal bindings (~400).** Delete the `box_*`, `decode_*`,
   `fallback_*`, `integer_*`, `payload32`, and `width_mask` bindings from
   `etc/lisp-values.xlisp` (~461-497), `etc/comptime.xlisp` (~549-583), and
   their target rows in `lib/lisp.x` (~1872-1907). Keep `clone_wide`,
   `getindex`, and `null`. Delete `meta-numeric-operations`. Grep proves no
   meta caller before deletion.
3. **One owner for the compound selectors.** Replace the hand table in
   `etc/lisp-values.xlisp` (~204-323: the `_selector_*` helpers and 44
   `List.`/`Var.` definitions), its ~56 aliases in `etc/comptime.xlisp`, and
   the `cdddr`/`cddddr` rows in `lib/lisp.x` with the definitions in
   `lib/list-selectors.x`. Each setting keeps today's availability rule:
   compiled x2c includes the module; meta functions and compile-time Lisp have
   the names without an include. Compile-time Lisp gains the depth-4 names.
   Acceptance: all 22 names plus `cdddr` and `cddddr` return the same values in
   all three settings, including on `nil` and on exhausted (`void`) input.
   If one declaration cannot serve compile-time Lisp directly, generate the
   Lisp names from it; do not keep a second hand-written table.

   **Parked by Gary on September 23.** Marking the selectors `meta inline`
   does not work: an included `.x` unit passes only its native `meta`
   prototypes to the includer, so a probe's meta call reported "no binding
   for List_cadar". Only three kinds of meta body are installed: a unit's
   own, one from a `.xmacro` import, and `lib/meta.x`, which
   `_preload_meta_surface` in `src/frontend.x` loads. Preloading
   `lib/list-selectors.x` the same way is about 5-10 lines. It would give
   compiled and meta code one owner and remove the `lisp-values` and
   `comptime` tables. What remains open is the bare Lisp spellings in
   `etc/init.x` (`caaar`..`cdddr`). Runtime Lisp and compile-time Lisp share
   them, they raise on exhausted input, and their only depth-3 user in the
   repository is `cdddr` in `lib/native-scalar-types.xmacro`.
4. **Cross-unit region tool (~260).** Delete `Compiler.region_escapes`,
   `_located`, and the `seed` parameter of `_fixpoint` in `src/regions.x`;
   `_region_seed`, `_region_pass`, `_parse_region_units`, and the CLI flag in
   `tools/x2c-graph/x2c-graph.x`; its tests, two graph fixtures, and README
   and `regions.md` text.
5. **Advisory region pieces.** Delete the `unbalanced` warning
   (`Region.lexical` and the warning in `_close_to`) and its doc rows. Delete
   `docs/src/internals/meta-lifetime-equivalence.md` (374 lines) and its
   links; the lifetime section in piece 2 replaces it.
6. **Meta function-local statics.** Decline a function-local static in a meta
   body with the existing decline diagnostic. Delete the evaluator static
   slots in `lib/lisp.x` (~1229-1289), their lowering in `src/comptime.x`
   (~380-407, ~2236-2276), `C.saddress`/`C.sinit`, the meta-static fixtures,
   `run-meta-local-statics.sh`, and the book text. Native static behavior
   and S1 initializer classification are unchanged.
7. **Foreign-header records.** Give meta record layouts only to structs
   defined in x2c units. Delete `--system-headers` (`src/cli.x`,
   `src/frontend.x` ~229-248, `src/toolchain.x` ~390-417, `src/build.x` ~333,
   `src/editor.x`), the layout-macro scan for C headers in `src/compiler.x`,
   the fixtures `meta-system-header-record`, `meta-native-system-record`, and
   `meta-system-header-packed`, and the book's system-header row, the
   `struct timespec` example, and its CLI entry. Keep the packed-struct error
   for structs x2c parses. Fix the book's remaining `#pragma pack` text.
8. **`Func` carrier ownership.** Move carrier preparation from
   `_lower_func_block` (`src/comptime.x` ~175-228, ~1048-1122), which pattern
   matches the `Func_apply` expansion, into the owner of that expansion.
   `Iter.map`, `Iter.filter`, and `Iter.zip_with` meta prototypes keep
   working.

## 1. Make compile-time entry explicit

Delete automatic folding:

- `fold_meta_call` and its call in `_finish_call` (`src/expressions.x`
  ~1540), `_meta_constant`, `_installed_comptime`, and
  `lower_reached_globals`.
- `Lowering.globals` and every assignment to it, and the `globals` field of
  the lowering cache entry. `lowered_meta_regions` matches that entry's
  shape; update it in the same commit.
- The `meta_folds` and `meta_impure` maps, their resets and sharing, and the
  `meta_impure` write in `_bind_native_meta`.
- Fixtures `meta-folding` (piece 0 deleted `meta-fold-effects`) and the `mt_fold` block in
  `comptime-lowering`; the fold text in `docs/src/reference/language.md` and
  `docs/src/guide/meta-functions.md`.

Keep what explicit calls need: `meta_value_expression`, the decline of file
state not declared `meta`, the enum-constant decline, `check_meta_call` and
compile-time-only reachability, `meta_regions`, and `inherit_shared_meta`
without its `globals` line.

Switch `meta-differential` to explicit `$` calls so the native/evaluator
parity column still comes from the evaluator. Recheck `meta-globals.c` and
`meta-value-aliases.x`, whose comments exist to prevent folding.

Calls inside a running meta body stay at compile time. A failed `$` call is
a diagnostic. After a decline, remove the placeholder `(def f (lambda () 0))`
so later calls report the decline instead of a `bad-arity` error.

Find intended precomputation in `src/`, `lib/`, and `examples/` by grepping
calls to `meta` functions with constant arguments. Convert each intended site
to `$f(...)`. Generated C changes; regenerate `bootstrap/` through the gate.

## 2. Temporary lifetimes in meta code

Meta bodies lower to compile-time Lisp. Today `defer`, `$scope`, `$let`, and
`$auto` decline at `_lower_scan` (`src/comptime.x` ~572), and `try`/`raise`
are unsupported statements.

- **Evaluator storage.** `$lisp.entry` (`lib/lisp.x` ~681-697) pushes a
  separate user Scope slot, which is the session default for user
  allocation. `_lowered_owner`, `lisp_record_result`, and `lisp_session_copy`
  name `lisp.scope` explicitly, so a user release never frees evaluator
  bindings, automatic storage, or session state.
- **Exits.** Keep block boundaries in `_lower_stmnt` (today blocks are
  spliced into the rest). Hold pending cleanups in `Lowering` with loop marks.
  `return` binds its value, runs every pending cleanup, then returns.
  `break` and `continue` run cleanups down to the loop mark.
- **Error unwinding.** Add one native that runs a body and then its cleanup
  on any exit, implemented with C `defer`, and wrap only blocks that hold a
  cleanup. It is a new native target, so it lands in `bootstrap/` before the
  lowering that emits it.
- **Bindings.** Bind `Scope.retain`, `release`, `push`, `pop`, `Scope.move`,
  and `Context.export`.
- **Loops.** A cleanup on a loop's iteration path takes the body out of tail
  position. Measure a 10,000-iteration loop; if the frame grows with the
  count, that form declines with a diagnostic.

`check_meta_regions` already walks these forms; its `$let` and `defer`
restore tracking becomes load-bearing and stays. Book: a lifetime contract
section in `docs/src/guide/meta-functions.md` with a working example of each
exit.

## 3. Materialize computed collections

`Compiler.meta_value_expression` (`src/comptime.x` ~3049) emits
post-lowering forms, bypasses the literal cache, and handles only a root
Array or Map with flat immutable children.

Rebuild it to produce the parser's canonical forms:

- Immutable values (scalars, Strings, Symbols, Lists) go through
  `_cache_literal_var` and `Compiler.cache` (`src/compiler.x` ~2343),
  extended to floats and tagged scalars.
- Arrays and Maps at any depth become `(expr ("Array") (array ...))` and
  `(expr ("Map") (map ...))`, which `transform_array_literal`,
  `transform_map_literal`, and `Emitter._var_collection` build fresh on every
  execution.
- Remove the `mutable_root` flag.
- One identity Map keyed by the payload address, with in-progress and done
  marks, reports a cycle or a shared mutable child as a diagnostic.
- Map entries keep their sort by code AST, so emission and cache ids are
  deterministic.

Fix `m["k"] = {}` inside a meta body, which fails as an unsupported
expression. The List syntax-versus-data rule stays: the declared type and
context decide.

## 4. Heap allocation and typed heap objects

1. **Bindings.** Add bodyless `meta` prototypes for `Scope.malloc`, `calloc`,
   `memdup`, `realloc`, and `free` in `lib/scope.x`. They reach the evaluator
   through `record_native_meta_effect` and `bind_native_meta`. Land them and
   the bootstrap refresh before any in-repository meta code calls them.
2. **One declaration per operation.** Today each bound operation is declared
   in `lib/lisp.x`, `etc/lisp-values.xlisp`, and `etc/comptime.xlisp`.
   Generate the two Lisp tables from `meta` marks before adding the heap
   operations, so each new operation has one declaration.
3. **`sizeof`.** Add a `_lower_content` case that answers from the existing
   scalar and record layout facts.
4. **Typed heap objects.** Construct and use structs defined in x2c units
   through native storage and the existing `lisp_peek`/`lisp_poke`. Do not
   box an unsupported class as a generic pointer.
5. **Region facts.** Make `Scope_realloc` a transfer that ends the old
   pointer. Report `free` or `realloc` of storage no Scope allocator returned
   and reads through a stale pointer. No allocation registry.
6. **Results.** A heap pointer may flow between meta helpers. An inserted
   result must satisfy piece 3; an evaluator address never becomes a constant.

## 5. Bounded internal adoption

- Replace `lib/native-scalar-types.xmacro`'s construction of `scalartypes`
  (`src/type.x` ~341) with a meta function returning a Map. The Lisp
  accessors that read the same rows must read the new owner; do not keep two.
  `varrows` (`src/type.x` ~581) is the fallback candidate.
- Convert the throwaway Arrays in `lib/autodiff.xmacro` meta helpers to
  `$scope` with the returned value exported.
- Record lines removed and the before/after translation time and peak
  memory of the affected units.
- Book: the phase rule, the lifetime contract, and working examples.

## Sequence and delivery

Piece 0, then 1, then 2 and 3 (sequenced edits to `src/comptime.x`), then
4, then 5. Each piece is one coherent change delivered to `dev` after
`tools/gate-state.py ensure agent-pr-check`. A new native target lands in
`bootstrap/` one change before its callers. Workers are bounded; the
coordinator owns integration, review of the completed authored diff, the
gate, and delivery.

A clean `make build-safe` takes about 9 seconds and a stage self-build about
23 seconds. Any build over one minute stops work and is reported to Gary.
Surveys read source; they do not rebuild the compiler or sweep fixtures.

## Backlog

Alias-preserving graph reconstruction, isolated meta pools, meta Var
protocols for unit-defined classes, and wider effect inference. Separate
read-only audits of the macro implementations, experimental tools, and the
REPL follow delivery of piece 0.

A meta body that assigns a function name or a `%!` lambda directly, such as
`f = twice;`, declines as "file-scope state not declared meta". The Func
conversion in `src/lambda.x` replaces the right-hand side with the hidden
global `_x2c_func_handle_N` before lowering sees it. Binding a local first,
as in `Func f = twice; chosen = f;`, works.

## Plan review

- **Trusted facts.** The parser, type, layout, region, and literal-cache
  owners establish the facts each piece consumes. No piece rechecks them.
  Piece 0 removes checks and fences that existed only for automatic folding
  and foreign layouts.
- **Reuse and deletion.** Piece 0 and piece 1 delete about 3,000 authored
  lines and 3,700 generated lines. New state is limited to the pending-cleanup
  stack in `Lowering`, the user Scope slot, one unwind native, and the
  identity Map during materialization. Each serves an exit or aliasing case
  that the existing owners cannot express.
- **Idiom.** Materialization emits ordinary collection literals; lifetimes
  reuse `$scope`, `defer`, and Context export; heap operations are ordinary
  `meta` prototypes on existing Scope methods.
- **Diagnostics.** A failed `$` call (explicit phase contract), cycles and
  shared mutable children (wrong aliasing), invalid `free`/`realloc` and stale
  reads (use-after-free), evaluator addresses in results (unsafe native
  crossing), and the existing decline for statics and non-x2c records.
  No other validator or negative fixture is planned.
- **Final step of every piece.** Review the completed authored diff for
  repeated facts, reusable code, and unneeded machinery; fix what it finds
  before the gate.
