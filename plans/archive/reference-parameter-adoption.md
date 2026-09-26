# Adopt reference parameters in place of pointer out-parameters

> Status: done - delivered to dev 2026-09-25. Gary chose the breaking
> `try_get` change with every in-repo caller migrated. `&` in `src/` fell
> from 311 to 102; no `(void *)` null casts remain in `src/` or `lib/`.

## Result

The compiler stops writing C address-of and dereference for values it only
wants to hand back through a parameter. Out-parameters become `T &?name`
(or `T &name` when no caller passes `NULL`), callers write `x` instead of
`&x`, and callees write `name = value` instead of `*name = value`. The
redundant `(void *)` casts on heap-class null tests go away. The generated
C does not change: an optional reference is still a `T *` parameter, and a
heap class compared with `NULL` is already a pointer comparison.

## Evidence

Probes with `builds/0/x2c` on 2026-09-25:

- `Map == NULL` and `Array == NULL` emit a plain C pointer comparison.
  `Map m = {}` gives `m == NULL` false. The 37 `src/` and 64 `lib/` casts
  of the form `(void *) map == NULL` are all on `Map`, `Array`, or `Lisp`
  values, so dropping the cast changes nothing. `!map` is the emptiness
  test, which is why the lazy-initialization sites cannot use it.
- `T &?out` forwards to a `T *` parameter by name, accepts `NULL`, forwards
  to another `&?` parameter, and `if (out) out = v;` writes the caller's
  object. After a nonnull proof, `out` in a condition is the value's truth
  (`List_truth(*out)`), not the reference test.
- Passing `&v` to a `&?` parameter is a compile error ("cannot pass
  (* "Var") where (opt-ref "Var") is expected"). Every missed caller fails
  loudly, and none is silently accepted.
- Optional references landed in 1ed5d4a8 and the checked-in `bootstrap/`
  already contains them, so signatures and callers can change in one
  commit.

## Steps

1. **Null-test casts.** Replace `(void *) x == NULL` / `!= NULL` with
   `x == NULL` / `!= NULL` in `src/` (37) and `lib/` (64), after confirming
   each operand is a heap class. Self-translated `src/` C must equal
   `bootstrap/` apart from line positions.

2. **The `try_get` family.** Change these to `&?` out-parameters:
   `Map.try_get` (`lib/map.x`), `$map.try_get` (`lib/map-generics.xmacro`),
   `$array.try_get` (`lib/array-generics.xmacro`), `Lisp.try_get`
   (`lib/lisp.x`), and `Buffer.try_get` (`lib/buffer.x`). They stay
   optional because `unittest/test-typed-map.x` passes `NULL`. Callers that
   write `&x`: src 123, lib 17, commands 27, unittest 29, examples 8,
   packages 9, docs 11, site 2. Most are the single-line `, &x)` rewrite;
   the compiler rejects the rest by position. Docstrings and the book show
   the new call form.

3. **Internal out-parameters in `src/`.** Convert these to `&?`, since most
   have callers passing `NULL`: `binding_identity_try_parts`,
   `_typed_function_parts`, `_lower_binder`, `match_value_flat_head`,
   `Compiler.match_pattern_binders`, `Sym.lookup`, `Sym.reference`,
   `Sym.resolve_global` and their shared worker, `Sym.var_tag_for_type` and
   its worker, `_integer_literal_kind`, `Compiler.take_meta_marker`,
   `_fact_of`, `_value_fact`, `_returned_argument`, `_borrow`,
   `_import_path`, `_source_capture_parts`, the `cache.x` walkers
   (`List *seen`, `int *replaced`), the `native_used` family in
   `expressions.x`, `_method_identity` in `parse.x`, `_lower_compound`
   (`List *rhs`) in `transform.x`, the cycle walker (`List *first_cycle`),
   the `protocol.x` `binding_out` helper, `tool_capture` (`String *output,
   *errors, *dependencies`), and `cli.x` `String *spelling, int *attached`.
   In each callee, `if (p) *p = v;` becomes `if (p) p = v;`.

   Keep as pointers: `CcJob *`, `long *pids`, `CliOption *`,
   `CliCommand *`, `SymbolSetEdge *`, `SymScope *`, and `struct Region *`.
   These are array or row cursors, and a reference would misstate them.
   `Scope.push(Scope *)` has 25 `&scope` callers. It is `meta native`, so
   probe whether a reference parameter works there before converting it;
   if not, leave it.

4. **Review.** Review the completed diff for missed `*p` reads in converted
   callees and for pointer-to-reference forwards that now need `*p` over a
   possibly null pointer. Rerun the pointer survey and record the counts
   here.

## Outcome

Differences from the plan:

- `_collect_cache_ids` keeps `List *seen`, because it is a 4096-slot memo
  array and not an out-parameter. `Scope.push` keeps `Scope *`, because the
  scope stack records the caller's slot address.
- `Toolchain.preprocess` has one caller, and it always supplied all three
  outputs, so they became required `String &` parameters. The null handling
  for an absent depfile is gone.
- `_find_delegate_methods` takes a required `List &first_cycle`.
- The `Sym.lookup` family takes `Type &?type`. Callers that held the type
  in a `List` now declare `Type`.
- Presence is proven only by a direct test. `if (!a || !out) return` and
  `if (out && x) out = v` do not prove `out`, so `Buffer.try_get`,
  `$array.try_get`, and two helpers in `regions.x` were restructured to use
  a direct test. Accepting `&&` and `||` would be a language change.
- A `meta` function that calls a native function with a reference
  parameter now passes address carriers. `_lower_native_call` in
  `comptime.x` does this when the call runs and the callee is a native
  `Func`. Before this change, `meta-output-cells` failed on `try_get`.
- `tools/definitions.x` now renders `&` and `&?` parameters for the
  generated API pages.

## Out of scope

libc boundary code (`char *` argv, `strtol(&end)`, `stat`, `uname`,
`clock_gettime`, the `project.x` character scanner) stays C. Runtime
internals in `lib/` keep their pointers except the signatures above.

## Validation

`make x2c` and the unit suites touching maps, arrays, Lisp, and buffers
after each step. Before delivery, diff self-translated `src/` C against
`bootstrap/`; it should differ only in line positions and parentheses. Then run
`tools/gate-state.py ensure agent-pr-check` once for the batch. Steps 1-3
can land as one commit or as three. Each step is independently revertable.

## Design review

This adds no new machinery. It uses a language feature that already shipped
and deletes syntax. The risk is a converted callee that still tests the
value where it meant to test the reference, or the reverse, before the
nonnull proof. Reviewing each converted callee in step 4 covers it. The
public signature change in step 2 is the one consequential choice.

## Library out-parameters (group 1)

Delivered 2026-09-25 under Gary's rule: a reference fits when the callee
reassigns the caller's variable or fills the caller's struct and keeps no
address. These took `&?`, or `&` where the callee always wrote the result:
`Map.try_del` and typed `try_del`, typed `try_take_last`, the
`List`/`MatchPlan`/`MatchCache`/`match_recursive` match results,
`MatchCache.acquire` (`&lease`), `MatchCache.search` and `search_replace`
(`&`), `Lisp.read`, `Var.numeric_info` and `numeric_decode`, the
`try_dispatch_*` functions, `Var.dispatch_truth`, `Var.try_export_context`,
and `File.copy_to`.

Kept as pointers:

- The `try_next` family at first. It later moved to references in two
  steps; see the next section.
- `String.try_long`, `String.try_double`, and `Symbol.try_new`. A
  `meta native` declaration must match its native target.
- `RenderPath.enter`, which links the caller's path into a chain.
- The compiler-emitted `x2c_match_*` functions. These now pass `*p` to the
  converted functions.

The work exposed a compiler defect. An unproven optional reference converted
to a value, for example as a declaration initializer, emitted the raw
pointer and was not diagnosed. `convert_expression` now reports "check
optional reference before using its value"; see fixture
`optional-reference-initializer`.

## The `try_next` family and `foreach`

Delivered 2026-09-25 in two steps, because the build compiles `lib/` with
the checked-in bootstrap compiler:

1. `foreach` passes the cursor and outputs directly when `try_next` takes
   references, and passes their addresses when it takes pointers. The
   compile-time cursor-loop analysis in `comptime.x` accepts both argument
   forms. This step landed with a bootstrap refresh, and the generated C was
   unchanged.
2. `List`, `Array`, `Map`, `String`, `Split`, and `Iter.try_next`, along
   with the typed map and array versions, take `&?` cursors and outputs.
   `Split_try_next` and `Iter_try_next` in `etc/comptime.xlisp` now bind
   their natives directly, as the other `try_next` bindings do, so a meta
   `foreach` passes reference carriers.
   In `List.try_next`, the empty-list test (`!*cursor`) became a test of a
   local copy of the checked cursor.

User types that keep pointer-style `try_next` still work with `foreach`.

