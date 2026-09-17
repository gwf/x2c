# Region escape warnings

> Status: needs author scoping - 2026-09-16. Decided by the Scope memory
> safety spike (`.context/scope-memory-safety-spike.md` in worktree
> frosty-jang-06431e). A Python prototype over `--dump-ast` found 0 real
> escapes in src, lib, and examples and 5 explained reports in packages, with
> 7 of 7 planted escapes detected. The runtime barrier variant was measured
> at 1.42x to 2.35x translation cost and dropped. Open for Gary: whether the
> warnings are on by default (recommended) and whether `$let` is taught to
> the pass or rewritten to avoid the parameter store.

## The result

The compiler warns when a value allocated inside a region can outlive it.
A region is a `$scope()` block, a retain and release pair, a `$scope(&slot)`
push, a `List.pool_retain` bracket, or an `$auto` local. The warning names
the value, the region it was born in, and the way it leaves: returned,
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
  Scope_release`, `Scope_push`, `List_pool_retain`, and `defer X_cleanup`.
- **Per-function summaries cross units through the interface file.** A
  summary is three facts: allocates into the caller's active region;
  returns fresh storage; and for each parameter, where it is sunk
  (returned, into another parameter's object, into a static, through an
  unknown pointer). Static functions are summarized within their unit to a
  fixpoint. Public functions publish their summary in the unit's `.xi`
  interface beside the signature, so a dependent unit reads it the way it
  reads the type. Interface format version increments.
- **Ownership sources.** A value is region-born when it comes from
  `Scope.malloc` and family, `Block.new`, `Bytes.new`, `Array.new`,
  `Map.new`, `Buffer.new`, `String.malloc`, an array or map literal, `cons`
  inside a pool bracket, or a callee whose summary returns fresh storage;
  the region is the innermost open scope or pushed slot at the call. A
  bare `$auto` Scope is not the active region. A slot-born value lives with
  its Scope: `Scope.pop` does not end it, `Scope.destroy` or the slot's
  `$auto` cleanup does.
- **Exits that end tracking.** `Scope.move` to a parameter slot or a slot the
  function does not destroy, `Context.export`, `List.promote`, and a typed
  conversion to `List`, `String`, or `Symbol`. Canonical-typed values are
  never region-born except inside a pool bracket.
- **Rules the prototype needed**, each a false positive found on the
  corpus and each part of the specification: deferred and branch-only frees
  do not kill the fall-through; a store into a struct local is a stack
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
2. Summaries: a fixpoint over the unit's functions, then publication of
   public summaries into the `.xi` writer in `src/collect.x` and reading
   them back where dependency interfaces are replayed.
3. Diagnostics: one warning code, `<region-escape>`, with the value name,
   the birth line, and the exit kind as notes; `<region-unbalanced>` for a
   non-lexical region; `<use-after-free>` for a dead local.
4. Corpus: teach `$let` or rewrite it; leave the torch conditional pool
   retain and the libuv raw-calloc stores as the documented departures, or
   fix them if their authors prefer.
5. Book: one section in the memory chapter naming the pattern, the exits,
   the warnings, and the unsafe list. The reference gets the warning codes.
6. Review the completed diff against the settled choices before validation.

## Compatibility

No generated C changes. The `.xi` format gains a field and its version
number moves, so interfaces are regenerated on the first build, as the
existing determinism rules already require. Programs that trip a warning
still compile.

## Validation

- Compiler fixtures under `unittest/compiler-fixtures` from
  `.context/regions-planted.x`: seven escapes each producing its warning,
  four safe idioms producing none.
- Translation of src, lib, and examples produces zero warnings; packages
  produce the five known reports, or zero after their authors act.
- Self-translation time before and after the pass; the prototype's walk is
  linear in the AST and the fixpoint is per unit, so the cost should sit in
  the noise of `make build`. Record the number.
- `tools/gate-state.py ensure agent-pr-check`.

## Plan review

- **Facts established elsewhere and not rechecked.** Binding identity and
  expression types come from the typing pass; the pass reads them and adds
  no second resolver. Region open and close forms are the ones the macros
  emit; the pass matches those forms and does not track lifetimes at
  runtime. Which functions allocate is derived once per unit into the
  summary and read back from the interface, never recomputed by callers.
- **Reuse and deletion.** `Compiler.report_warning`, the transform-stage
  walk, the `.xi` writer and reader, and the match forms are all reused.
  The `lifetime-escapes` command in `tools/x2c-graph` overlaps on returns
  from explicit scopes and Contexts; once the pass covers Contexts the
  command should be deleted rather than kept as a second implementation.
  The new mechanisms are one pass and one interface field; both are
  necessary because no existing pass sees regions and no existing artifact
  carries per-function allocation facts across units.
- **Idiomatic x2c.** The pass is a Match walk over canonical forms with a
  Map of binding facts, the same shape as `cleanup.x`, not a dataflow
  framework: no lattice, no worklist beyond the per-unit fixpoint, no
  annotations on signatures.
- **Validators and negative fixtures.** The seven fixtures each protect
  deliberate public behavior: the warning text a user relies on. No
  validator rejects legal syntax; a warning never stops translation.
