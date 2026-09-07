> Status: done
> Implemented and source-reviewed, 2026-09-07, for PR #29.
> Publication uses the existing full gate; main remains unmerged.

# Use x2c-graph to remove unnecessary compiler work

The graph led to three source changes that together reduced compiler/runtime
translation time from 5.505s to 4.540s (17.5%) on this machine. Every prototype
produced identical bytes for all 146 C/header files. This is a useful next
increment; the tail-call reporting fix alone was not its justification.

## Measurement

Baseline: 24c3f8d0dcb869aaa2c3e38c29bc05dcf8083302, based on main 885c1a1.
Commands translate all 27 src and 46 lib inputs, including generated lib/x2c.x,
with `translate -q -j 1 --no-deps`, into separate temporary directories.
These numbers measure translation, not native compilation or complete builds.

Three runs per variant ran serially, reversing order on the middle run:

| Compiler variant | Median seconds | Range |
| --- | ---: | --- |
| Original | 5.505 | 5.254-5.725 |
| Type canonicalization change | 5.202 | 5.083-5.251 |
| Lambda preparation change | 5.099 | 5.020-5.154 |
| Shared AST rewrite macro | 5.070 | 4.940-5.437 |
| All three | 4.540 | 4.364-4.614 |

A separate three-pair comparison measured Type+lambda at 4.960s versus all
three at 4.518s: adding the macro reduced translation time another 8.9%, and
every pair improved. The lazy Ast helper alone showed no measurable gain.
RSS varied too much between identical binaries to claim memory savings.

The normal rebuilt implementation (`builds/0/x2c`, optimized with `-O2`)
was measured against a saved baseline compiler on the final source corpus.
Three alternating pairs gave medians of 5.916s and 4.847s, an 18.1% reduction
(original range 5.897-5.951s; changed range 4.835-4.852s). All 146 C/header
files were byte-identical in every pair. This includes the final value-only
Ast callback expression and literal-zero scratch pointer. The earlier
prototype figures above remain the comparison of individual changes.

## What the graph found

1. `loop-allocations --all` and `focus Ast_rewrite_children` led to
   `src/transform.x::_children`. It duplicates the child-rewriting loop in
   `Ast.rewrite_children`, but creates an Array and interns a result every
   time. Instrumentation recorded 2,121,375 temporary Arrays; 2,079,680 calls
   (98.03%) returned the original canonical List.
2. `focus Type_scalar`, `focus Type_var_tag`, and `focus _canonical` connected
   type inspection to `src/type.x::_canonical`. It made 1,883,414 temporary
   Arrays; 1,861,442 results (98.8%) were identical to the input.
3. `walks`, `focus _prepare_lambda_region`, and
   `sites Compiler_prepare_lambda_cells` exposed repeated lambda-preparation
   walks. There were 16,318 calls on bodies containing no lambda, versus 20
   containing one. Binding collection changes only temporary containers; with
   no nested lambda, it cannot discover a reference capture requiring a cell.

The graph supplied candidates and callers, not execution counts. The counts
above come from separately instrumented compiler objects translating the real
corpus. No static call weight is being treated as runtime traffic.

## Decided implementation: one compiler performance PR

Keep the three measured changes together as the useful increment, with no
language, API, runtime, build-target, or graph-format change:

1. Put the common lazy child-rewriting algorithm in
   `src/ast-rewrite.xmacro`. Import it in ast.x and transform.x. Keep the
   existing `Ast.rewrite_children(Ast, Func)` API as a wrapper; use the macro
   directly in `_children`, where the `_node` call is statically known.
   Each caller declares the child before passing its Name and replacement
   Expr. Ast uses `Var child` and retains `per_child(child.list())`, so a
   callback receives a value just as before. Transform uses `List child` for
   the direct `_node` call. Both expressions are typed before expansion.
   Visit every child once in order. Allocate the scratch Array only after the
   first changed value; copy the preceding unchanged cells once, append later
   values, and otherwise return the original node. Distinguish an absent
   scratch pointer with `(void *) rewritten`, not Array truth (which tests
   length). The scratch initializer uses `(Array) 0`: `NULL` in this macro
   otherwise captures a name in the expanded Func call, a pre-existing bug
   reproduced in `unittest/STATUS.md`. This shares one algorithm without
   constructing a Func per node.
2. In type.x, factor the existing specifier-removal expression into one
   `_omit_specifier` predicate. Look for a removable specifier before making
   an Array; return the existing Type when none exists. Reuse that predicate
   in the existing materialization loop. Preserve typedef, qualifier,
   storage-class, inline, nested-modifier, and ordering behavior exactly.
3. In lambda.x, put the existing lambda containment check before region
   preparation. Move the nested helper's check into its recursive callback,
   so known-containing roots are not scanned twice and child pruning remains.
   Do not collect bindings or create temporary containers for no-lambda bodies.
4. Add focused behavior coverage for unchanged AST identity, callback order,
   changes at first/middle/last positions, nil, and Context export; retain
   Type canonicalization/declared/scalar parity and the existing capture
   fixtures. Confirm original/prototype generated-output equality over the
   same corpus. The completed implementation adds 15 authored source lines
   in total, including the 20-line macro, imports, and comment corrections.
5. Review and fix the completed authored diff for duplicate checks, avoidable
   state/helpers, allocation/lifetime changes, and idiomatic x2c use. Then use
   the existing `tools/gate-state.py ensure agent-pr-check` for publication.
   Do not add or expand a recurring gate. Publish only for review; do not merge
   into main without Gary's instruction.

## Evidence and rejected alternatives

The combined compiler independently translated, native-compiled, and ran all
14 existing lambda/capture stdout fixtures with exact expected output. A native
Ast harness passed unchanged identity, visitation order, changed positions,
nil, and Context export with original and corrected prototypes. A direct Type
harness compared 10,648 inputs through canonicalize/declared/scalar with
identical output. All final measured variants passed 146-file byte equality.
The implementation adds five focused tests to the existing Ast suite. Its
six tests pass with 24 assertions. The rebuilt compiler also passes the
10,648-input Type comparison and all 14 native lambda/capture fixtures.
Publication requires `tools/gate-state.py ensure agent-pr-check`; its final
result is recorded on PR #29.

Reusing the Func-based Ast helper directly in `_children` created a captured
closure at every node and did not justify its cost. The shared macro removes
that allocation while preserving the existing callable API. Simply making the
public Ast helper lazy gave no measured benefit on its own.

Two prototype failures were caught and corrected before the final results:
Array truth discarded first-child changes; macro-introduced child names left
captured Func arguments untyped. Explicit optional-pointer tests and an
already-declared typed child fix those cases without changing the compiler.
Implementation review additionally caught reference-parameter acceptance when
the Ast wrapper passed an addressable List. Keeping the original
`per_child(child.list())` expression preserves the original rejection and
its exact diagnostic; the new value-callback test covers it.

The 27 static compiler functions with no incoming graph edge are SDK callbacks
or shutdown hooks, not dead code. Cache scans, emitter label/capture collection,
and defer capture discovery did not yield justified deletions. Do not turn
these findings into file moves or additional graph-tool work.

Reproducers, graph reports, patches, exact commands, fixture outputs, and timing
JSON are in `.context/graph-use/`. `allocations/serial-bench.py` and
`incremental-bench.py` reproduce the measurements with the temporary binaries;
`ast/reproduce.py`, `source/type-canonical-probe.py`, and `walks/probe.py` rebuild
the individual experiments. The source changes are implemented in src/; implementation commands and
results are under `.context/graph-use/implementation/`.

## Plan review

The compiler supplies bound, typed canonical AST Lists; cons already guarantees
canonical identity. Returning an unchanged List preserves its value and
lifetime. The rewrite macro trusts those facts, preserves callback order, and
shares the existing operation; it does not bind, validate, or reinterpret ASTs.
The Array pointer test distinguishes optional scratch storage, not allocation
success. The type predicate reuses the exact existing removal rule. Absence of
lambda nodes makes capture-cell preparation unnecessary; its existing traversal
is moved earlier rather than adding metadata or a second root scan.

The completed authored diff was reviewed against these facts. The source
uses one small typed-slot macro, ordinary List traversal, and the
existing Type and lambda operations. It deletes duplicate child-loop ownership
without introducing a callback object or changing Ast's public signature. The
new predicate is needed by the precheck and materialization to keep their
specifier rules identical. No new representation, cache, validator, diagnostic,
negative-language fixture, or recurring process is proposed.
