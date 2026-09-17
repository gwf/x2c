# Region escape warnings

> Status: active - 2026-09-17. Shipped in ac931c4: on by default, with
> `$let` taught to the pass. Summaries no longer cross units: a summary
> recorded during transform and read back from interfaces made warnings
> depend on input order, `-j`, and earlier `.xi` files, so each unit now
> uses its own summaries and the runtime table. The false positives and
> missed escapes from the 2026-09-17 merge review are fixed, and
> `src/regions.x` was rewritten from 1,195 lines to under 800 on typed
> records and one runtime table. Open: `Context` regions are not modeled,
> so the `lifetime-escapes` command in `tools/x2c-graph` still serves them.
> Decided by the Scope memory safety spike
> (`.context/scope-memory-safety-spike.md` in worktree
> frosty-jang-06431e). A Python prototype over `--dump-ast` found 0 real
> escapes in src, lib, and examples and 5 explained reports in packages, with
> 7 of 7 planted escapes detected. The runtime barrier variant was measured
> at 1.42x to 2.35x translation cost and dropped.

## The result

The compiler warns when a value allocated inside a region can outlive it.
A region is a `$scope()` block, a retain and release pair, a `$scope(&slot)`
push, a `String.pool_retain` bracket, an `$auto` local, or a Scope local that
`Scope.destroy` ends. The warning names the value, the region it was born
in, and the way it leaves: returned,
assigned to a variable declared outside the region, stored through a
parameter, a static, an object of an outer region, or an unknown pointer,
or handed to a callee that stores it in one of those places. The compiler
also warns on a region opened without a release in the same block, and on
a use of a local after `Scope.free` or `Array.list_free`.

Code that stays inside the pattern compiles silently. The pattern is the one
the book already teaches: return canonical values, move mutable storage with
`Scope.move` or export it through a `Context`, or let the caller own the
scope and pass the slot down. The warnings are the list of departures. They
are not a claim of memory safety for raw C stores, pointer arithmetic,
callbacks, or storage the runtime did not allocate.

## Settled choices

- **Warnings, not errors.** Every report is a statement about a lifetime the
  compiler cannot see; the author decides. `Compiler.report_warning` exists
  and carries locations.
- **Static, no runtime support.** The pass reads typed forms after
  `$scope`, `$auto`, and `foreach` have expanded and before cleanup
  lowering, so regions are still visible as `Scope_retain`, `defer
  Scope_release`, `Scope_push`, `String_pool_retain`, and `defer X_cleanup`.
- **Per-function summaries stay within the unit.** A summary is two
  facts: returns fresh storage; and for each parameter, where it is sunk
  (returned, into another parameter's object, into a static, through an
  unknown pointer). A unit's functions are summarized to a fixpoint, and
  the first round that changes no summary reports. A call into another
  unit has a summary only through the runtime table, which lists each
  allocator, pool constructor, container store, wrapper, free, and region
  call by C name. The shipped pass also recorded whether a function
  allocates into the caller's active region; no decision read that fact,
  and it was removed. Publishing summaries in the
  `.xi` interface was shipped and removed on 2026-09-17: dependents collect
  interfaces before the summarized unit is transformed, so the warnings
  depended on translation order.
- **Ownership sources.** A value is region-born when it comes from
  `Scope.malloc` and family, `Block.new`, `Bytes.new`, `Array.new`,
  `Map.new`, `Buffer.new`, `String.malloc`, an array or map literal, `cons`
  inside a pool bracket, a closure, or a callee whose summary returns fresh
  storage; the region is the innermost open scope or pushed slot at the
  call. A closure lives in the region of a captured value when it has one.
  A bare `$auto` Scope is not the active region. A slot-born value lives
  with its Scope: `Scope.pop` does not end it, `Scope.destroy` or the
  slot's `$auto` cleanup does. Types are classified by the compiler's `Var`
  tag, so a typedef of `List` is canonical and a `List *` is not.
- **Exits that end tracking.** `Scope.move` to a parameter slot or a slot the
  function does not destroy, `Context.export`, `List.promote`, and a typed
  conversion to `List`, `String`, or `Symbol`. Canonical-typed values are
  never region-born except inside a pool bracket.
- **Rules the prototype needed**, each a false positive found on the
  corpus and each part of the specification: deferred and branch-only frees
  and releases do not kill the fall-through; an assignment ends a free; a
  store that reports an escape into an outer local does not report again
  when that local is used; a store into a struct local is a stack
  store, a store through a pointer local is a heap store, and `&local`
  names the local; a parameter moved with `Scope.move` before being stored
  is not a sink; owned locals may be swapped within their own block;
  control constructs are walked once and their children count as a nested
  block for consumption; raw C indexing and casts are looked through.
- **`$let`.** Its expansion stores an owned local into a field of a
  parameter and restores it in a defer. The pass recognizes the paired
  store and restore in one block and does not report it. If Gary prefers,
  the macro can be rewritten to save through a local instead; either
  choice makes src warning-free.
- **Not covered, stated in the book.** Aliasing through fields of stack
  structs, callbacks and function pointers, Lisp-visible entry points,
  storage from plain `malloc` or a C library, and `Context` regions, which
  the existing `lifetime-escapes` command in `tools/x2c-graph` continues
  to serve until the pass absorbs them.

## Implementation

1. `src/regions.x`, a new pass owned by the transform stage. It walks one
   function body with a stack of open regions and a map from binding to
   what is known about it (parameter index, birth region, pointee for a
   local pointer assigned from `&x`, dead after a consuming call). The walk
   follows the prototype in `.context/regions-spike.py`; every rule above
   has a direct counterpart there.
2. Summaries: a fixpoint over the unit's functions. The round that changes
   no summary submits its warnings.
3. Diagnostics: one warning code, `region`, with the value name and the
   exit kind in the message and the birth line as a note; `unbalanced` for
   a non-lexical region; `after-free` for a dead local.
4. Corpus: teach `$let` or rewrite it; leave the torch conditional pool
   retain and the libuv raw-calloc stores as the documented departures, or
   fix them if their authors prefer.
5. Book: one section in the memory chapter naming the pattern, the exits,
   the warnings, and the unsafe list. The reference gets the warning codes.
6. Book, internals: a short chapter beside the implementation map on the
   region model, written against the shipped behavior. It holds five
   things and nothing else: the invariant in one sentence with the four
   kinds of places that outlive a region; the exemptions and why each is
   sound (canonical values are never freed, moves and exports change the
   owner, typed conversions copy); the unsafe list, identical to what the
   warnings implement (raw C storage, pointer arithmetic and casts,
   callbacks, `Scope.free` and `Scope.realloc`, stores through fields of
   stack structs, Contexts until covered); how the check works in two
   paragraphs (the summary per function and the consequence that a callee
   change can surface a warning in a caller in the same unit); and one
   factual paragraph each placing the design
   beside the ML Kit and Cyclone as ancestors, Rust and Swift as the
   annotate-and-check-locally choice, and Go's escape analysis and Infer as
   summary-based relatives. No measurements, no false-positive catalog, and
   never the phrase "memory safe" without the unsafe list beside it.
7. Review the completed diff against the settled choices before validation.

## Compatibility

No generated C changes, and the `.xi` interface carries no summaries.
Programs that trip a warning still compile.

## Validation

- Compiler fixtures under `unittest/compiler-fixtures` from
  `.context/regions-planted.x`: seven escapes each producing its warning,
  four safe idioms producing none.
- Translation of src, lib, and examples produces zero warnings; packages
  produce the five known reports, or zero after their authors act.
- Self-translation time with and without the pass. Measured 2026-09-17 on
  main a1d763e, `translate -q -j1 src/*.x`, user time, median of seven
  alternating runs: 3.92 s without the `check_regions` call, 4.25 s with
  the shipped pass (+8.5%), and 4.09 s with the rewritten pass (+4.3%).
  Runs of one binary vary by about 3%.
- `tools/gate-state.py ensure agent-pr-check`.

## Plan review

- **Facts established elsewhere and not rechecked.** Binding identity and
  expression types come from the typing pass; the pass reads them and adds
  no second resolver. Region open and close forms are the ones the macros
  emit; the pass matches those forms and does not track lifetimes at
  runtime. Where a function sinks its parameters is derived once per unit
  into its summary, never recomputed by callers.
- **Reuse and deletion.** `Compiler.report_warning`, the transform-stage
  walk, the compiler's `Var` tag resolution, and the match forms are all
  reused.
  The `lifetime-escapes` command in `tools/x2c-graph` overlaps on returns
  from explicit scopes and Contexts; once the pass covers Contexts the
  command should be deleted rather than kept as a second implementation.
  The one new mechanism is the pass; no existing pass sees regions.
- **Idiomatic x2c.** The pass is a Match walk over canonical forms with a
  Map from binding to a small record, the same shape as `cleanup.x`, not a
  dataflow framework: no lattice, no worklist beyond the per-unit fixpoint,
  no annotations on signatures.
- **Validators and negative fixtures.** The fixtures each protect
  deliberate public behavior: the warning text a user relies on. No
  validator rejects legal syntax; a warning never stops translation.
