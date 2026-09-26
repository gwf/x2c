# Rebuild design: fewest passes

Stance: the smallest number of walks from source to C. Research spike,
2026-09-26, read-only. Line counts are `wc -l` on current dev; file:line
citations were read in source during this pass unless marked "(map)".

## 1. Thesis

Today one translation unit's bodies are walked by collection (token skip),
parse+resolve, regions, the transform driver at least twice (once to change,
once to confirm identity, plus one round per batch of lifted lambdas), the
cleanup pass, two cache-id collections (header and source), the header
cache-reference rewrite, emit, and format. Each walk keeps its own state on
a Compiler struct of about 115 fields. The idea of this design is that
every rewrite the compiler performs is already local to the node it
rewrites (src/transform.x:1586-1589 says so, and plans/archive/
meta-functions.md:470-476 measured that re-transforming transform output is
idempotent), so the unit-wide fixed point, the separate cleanup walk, and
the separate cache walks are traversal skeletons around work that one
recursive descent can do as it returns: rewrite a node until its head is
stable, then descend, carrying the open cleanup regions as walk state and
recording cache references as they are printed. The design keeps parse,
regions, and lowering as three distinct walks over bodies, for reasons
given in section 2, and reduces the rest to one lowering walk feeding a
direct emitter. The payoff is translation time (the fixed point alone was
recorded at about 0.1 s per unit, plans/archive/architecture-salvage.md
"Declined, with reasons") and a Compiler struct that shrinks to the state
the remaining walks actually share. The line payoff is modest and honest:
about 1,300 lines of src/ and none of lib/. Fewest passes is a performance
and clarity lever, not the line lever; this document says so rather than
inflating the estimate.

This design contradicts one declined decision and says why: the 2026-09-17
decline of "ordered lowering passes replacing the fixed point" rejected a
pass *list* because it "moves ordering constraints somewhere nobody can
verify" (architecture-salvage.md, Declined). A local fixed point imposes no
order between helpers: each helper still rewrites only its node and the
driver re-dispatches the result until it stops changing, exactly the
composability the unit-wide loop buys, minus the re-walk of everything the
rewrite did not touch. The 0.1 s per unit was paid for composability; the
local loop keeps composability for free.

## 2. Architecture

Walks over a unit, in order. "Body walk" means a traversal that enters
function bodies; the others touch top-level nodes only.

| # | walk | owner | input | output | kernel or macro |
|---|---|---|---|---|---|
| 1 | scan | lib/tokenizer.x | bytes | Token array | kernel (as today) |
| 2 | collect | src/collect.x + one classifier shared with walk 3 | tokens | globals Map, `.xi` | kernel (as today, one dispatcher) |
| 3 | parse + resolve + convert | src/parse.x, statements.x, expressions.x, literals.x, macros.x, protocol.x | tokens + globals | typed canonical AST, per top-level form | kernel; macros and meta functions expand inside it as today |
| 4 | regions | src/regions.x | typed AST (pre-lowering) | warnings, summaries | kernel (as today, read-only) |
| 5 | partition | src/generate.x:604-695 | typed top-level nodes | header/source membership per node | kernel, top-level only |
| 6 | lower | new src/lower.x = transform.x + lambda.x + cleanup.x with one driver | typed AST | emitter-ready AST, lambda siblings placed beside their function | kernel; local fixed point per node |
| 7 | emit + cache | src/emit.x with cache materialization folded in | emitter-ready AST | flat token Lists for .h and .c, cache slots and initializers | kernel |
| 8 | format | src/format.x | tokens | text with `#line` | kernel (as today) |

Body walks: 2 (token skip), 3, 4, 6, 7, 8 (tokens). Today: 2, 3, 4,
transform x k (k >= 2, src/transform.x:1780-1784), the early-declaration
rounds (1787-1796), cleanup (1800; src/cleanup.x:762-781), cache-id
collection over header and over source (src/cache.x:533-542, called at
696-702), the header reference rewrite (545-558, 616), emit, format. The
design removes at least four body walks per unit and every re-cons of an
unchanged `(at ...)` anchor that the `fixed` memo exists to avoid
(src/compiler.x:110-113, src/transform.x:1601-1617).

### Why parse and lower stay two walks

Lowering could run on each top-level form as soon as it commits, and
nothing in lowering needs a later form. Three facts keep it a separate
walk. (a) main.x stops after the parse when it has errors
(src/main.x:126-129) and again after the transform (74-81), so lowering
never runs on an erroneous unit; a fused walk would report lowering
diagnostics for forms before a later parse error, and 413 `.diagnostics`
fixtures pin exact stderr bytes. (b) Regions must read the typed forms of
the whole unit before any of them is lowered, because its function
summaries reach a unit-wide fixpoint (src/regions.x:1200-1204, 1212-1217)
and it reads `$scope`/`$auto`/`defer` before rewriting (src/transform.x:
1777-1779; docs/src/guide/regions.md:15-17). (c) Speculative macro
expansion runs inside a semantic transaction that snapshots symbol state
only (src/compiler.x:2538-2543, map 2.13); lowering emits lambda siblings
and adapters into the output queue, which a rollback would also have to
undo. Fusing buys no lines and one walk; it is not proposed.

### Why regions stays a walk of its own

It is warning-only in ordinary translation, hard-error only for `meta`
functions at their definition (src/regions.x:1227-1256), and its audit
entry is consumed by `commands/graph/x2c-graph.x:2605`
(`compiler.audit_regions`), a consumer surface the brief says must survive.
The summaries fixpoint re-analyzes functions whose callees changed; folding
that into the lowering descent would require a summary dataflow that does
not re-walk ASTs, which is a redesign of regions.x, not a pass merge. It
stays as today; its two worklist walkers (map 2.5) merge.

### The lowering walk (walk 6)

One function, `_lower(Walk w, Ast node)`, replaces `_node`, `_finish`,
`_children`, `_sequence`, `_op_chain`, `Compiler.transform`
(src/transform.x:1471-1801), `_units`, `_function`, `_rewrite`, `_bounded`,
`_inside`, `_transfer`, `_unwind` (src/cleanup.x:123-148, 626-781), and
`_lower_nested_lambdas` (src/lambda.x:1416-1436):

1. Rewrite the node with the helper for its head until the result is the
   same List (identity, as today's driver compares). The helpers are
   today's: `_call`, `_declaration`, `_operator`, `_cast`, `_cons`,
   `_append`, `_to_var`, `_string_segments`, destructuring, `_raise`,
   `_return`, `_match_cases`, `_catch_cases`, `_truthy`, `_postfix`,
   getindex/setindex/slice, lambda and adapter lowering. None changes.
2. If the node is a region (`try`, the `defer` produced by
   `_rewrite_defer_list`, `localinit`), push its record binding and leave
   statements on `w.regions`, descend, pop. If it is `return`, `break`,
   `continue`, or `goto`, splice the unwind of the regions being left,
   exactly as `_rewrite` does (src/cleanup.x:640-731), using the same
   barriers (`break_stop`, `continue_stop`) and the same label ancestry.
3. Descend into children; a `block` absorbs `(seq ...)` results and runs
   `_rewrite_defer_list` first (src/transform.x:1311-1342, 1754-1758).
4. A `function` node: save `fn_name`/`inline_header`, prepare lambda
   cells (src/lambda.x:1350), pre-scan labels (src/cleanup.x:167-207, kept:
   a forward `goto` needs the label's ancestry before the label is
   reached), lower the body, run the volatile analysis over the lowered
   body when the function opened a `try` region (src/cleanup.x:242-624,
   kept unchanged), and append lifted siblings beside the function.

The order "defer rewrite, lambda lifting, then cleanup" that Phase 1 of
plans/archive/emit-cleanup-lowering.md required is preserved by
construction: the region cases run on the forms `_rewrite_defer_list` and
`_lower_defer_region` produce, and a lifted lambda body is lowered as its
own `function` with its own region stack, which is what cleanup.x:733-734
already requires. Lambda siblings land beside their function instead of at
the unit's end (today: src/transform.x:1785-1797); meta-functions.md:473-475
recorded that this changes only sibling placement and generated C is
otherwise byte-identical.

### Emit with cache materialization (walk 7)

`Compiler.emit` is already one bottom-up pass (src/emit.x:1457-1459). It
gains one case: printing `(cache id)` records the id in the Emitter (as
`static_objects` already records local statics, src/emit.x:22-29,
301-421). Generation then declares the referenced slots and queues their
initializers for the region that referenced them, which is what
`_setup_header_cache` and `_setup_source_cache_init` do today after their
own walks (src/cache.x:588-679). The header-prefix rename
(`_rewrite_header_cache_refs`, 545-558) becomes the header emitter's
spelling of the ident. The deferred-kind rule for `String_initialize` and
`List_initialize` (640-666) and the early/middle/late queues stay. The
static-init dependency walk between file statics stays (it is a
declaration-level fact, not a body walk).

### Partition before lowering (walk 5)

`_header_and_source` reads only top-level heads, types, bindings, and
binding facts (src/generate.x:604-695); the typedef promotion lookahead
(491-524) and aggregate forwards (529-565) read typedef spellings. None of
that needs lowered bodies, so partition runs on the typed unit and each
node carries its destination into walk 6. Lowering then emits into two
token streams directly. This is a reordering, not a merge; it removes the
`(pending ...)`/`(conditional ...)` marker lists only if the conditional
balancing (567-602) can be expressed as a per-node destination, which it
can: a group's directive goes to each file that holds one of its items.

### What is kernel, what is macro

Kernel (needs binding, types, layout, lifetimes, or emission order):
walks 2-8 entirely. Macro or meta over canonical syntax, as today: every
built-in system macro (etc/builtin-macros.x lowered through
src/comptime.x), user macros and decorators, meta functions. This stance
does not move any kernel operation into a macro; the transforms' helpers
need protocol resolution and typedef chains (src/transform.x:1649, 1664;
src/expressions.x:4068-4075) at every rewrite, and a macro cannot ask for
those without the native surface lib/meta.x already provides.

### The Compiler struct

Today: about 115 fields (src/compiler.x:71-184; the map says ~110, a
field-name count gives 119). Many exist only to carry facts from one walk
to a later one: `fixed`, `early_decls`, `needs_exception`, `init_tokens`,
`static_init_deps`, `fn_defs`, `id_keys`, `key_ids`, `inits`, `init_fn`,
`fini_fn`, `inline_header`, `runtime_literals`, `in_pattern`, `match_is`,
`match_types`, `lambda_scopes`, `shallow`, `collect_protocols`,
`declaration_projection`, `declaration_produced`. The struct becomes a
unit record with five delegates, each owned by the walk that mutates it:

| record | fields (today's names) | owner |
|---|---|---|
| Unit | filename, text, root_dir, package*, include_dirs, names, sources, source_map, unit_script, script, deps, diagnostics, origins, origin, import_stack, recovery_depth | frontend, diagnostics |
| Parser | token, input_boundary, tokenizer, braces, directives_taken, arms, arm_stacks, layout_marks, packed_marks, object_macros, kw_seen, open_linkage, layout, shallow, collect_protocols, source_private, return_type, aggregate_type, params, in_pattern, match_is, match_types, lambda_scopes, runtime_literals | walks 2-3 |
| Sym | sym, key_ids/id_keys (the literal cache is interned at parse time, src/literals.x:94, src/compiler.x:2254-2260), protocols, conforms, protocol_helpers, proto_cache, adoptions, import_protocols, in_proto, declaration_effects, fn_defs | walks 2-3, read by 5-7 |
| Meta | macros, kw_aliases, macro_stack, macro_holes, local_macro_captures*, macro_count, imports, macro_lisp, import_src, borrowed_lisp, inherited_lisp, builtin_defs, meta_defs, meta_comptime, meta_regions, meta_values, meta_layouts, native_meta, meta_body, declaration_projection, declaration_produced | macros.x, comptime.x |
| Out | fn_name, inline_header, needs_exception, siblings (was early_decls), inits, init_fn, fini_fn, init_tokens, static_init_deps, prelude, cache slots by region | walks 6-7 |
| SourceFacts | source_facts, source_primary, source_occurrences, source_definitions, source_declarations, source_texts | editor.x |

`fixed` is deleted. `full_parse`'s reset of twenty fields
(src/compiler.x:2000-2028) becomes a reset of Parser and Out. `SymTxn`
snapshots Sym and Meta only, which is the set its doc comment already
lists (2538-2543). The field count drops to about 95; the deletion is
small in lines (about 60 declarations and comments, 30 of reset) and
large in legibility: "which walk owns this" is answerable by record.

## 3. Compile-time execution model

Unchanged by this stance. Meta functions are lowered by src/comptime.x from
the typed, pre-lowering AST (M3 declined, map section 6), which walk 3
still produces and walk 6 consumes later, so nothing moves. The mid-parse
`Compiler.transform` of one function that meta-functions.md:470-476
probed stays possible: the local fixed-point driver is idempotent on its
own output as the unit-wide one is. `$(...)` Lisp, `$lisp.bind`,
`$(import ...)`, dlopen native modules, hygiene at definition time
(src/macros.x:2499-2576, map), and the shared read-only parent session
(src/macros.x:1155, map) are as today. comptime.x, lisp.x, lisp-machine.x,
machine.x, and match-machine.x all survive unchanged. The one interaction
worth naming: `check_meta_regions` is called from comptime.x at
definition time (src/regions.x:1237-1256), so regions.x cannot become
lowering-time state even for the meta path; that is a second reason walk 4
stays a module of its own.

## 4. Feature coverage

Map section 4 rows, grouped. Every row is kept.

Language surface, "kernel, walk 3 (parse/resolve/convert) as today": C
foundation and expression-bodied functions; scalar declarations, literals,
arithmetic; collection and string literals (interning at parse,
src/literals.x:94); symbol and atom literals; indexing and slicing
(resolved in 3, lowered in 6); method-style calls; postfix chains, unary,
sizeof, offsetof, _Generic, va_arg, casts, designated initializers,
compound literals; generic selection; mixed declaration rows; C
initializers and static assertions; exact Var-tag tests; membership `in`;
Var boxing, conversion, operators, dispatch (conversion is
`convert_expression`, an operation with 69 call sites across seven files,
23 at resolve time and 30 at lowering; it is not a pass and stays one
kernel operation); dynamic numeric conversion (runtime); reference
parameters; delegate fields; protocols (declaration, adoption, conversions,
member resolution, punctuation); checked foreign aliases; type-owned
initialization and shutdown; managed-initializer syntax; named types and
class declarations; package imports and `name__` prefixing; source files,
pragmas, script units; indentation syntax; host preprocessing; two-pass
compilation and `.xi` (walk 2, one dispatcher, one serialization); editor
overlays and one-shot queries (SourceFacts record); `Var`, Null, `void`
as values (map coverage critique b).

Language surface, "kernel, walk 6 (lower)": lambdas and typed callback
adapters (one adapter helper replacing five paths, map 2.5); control flow
exits through cleanup regions; `foreach` after macro expansion (iterator
lowering); `with`; `match` and typed capture patterns; raise, filtered
catch, finally, defer; string interpolation lowering; printf Var inference;
list destructuring lowering; Var operator lowering.

Language surface, "macro/meta as today": compile-time macros and
decorators; meta functions; inline Lisp bindings; `$(import ...)` and
native modules; system macros ($scope, $let, $lock, $auto, $class,
$switch, $dedent, $todo, $unreachable, $time, $assert).

Language surface, "kernel, walk 4 as today": region model, lifetime
warnings, optional lifetime proof.

Language surface, "kernel, walks 7-8 and driver as today": structured
diagnostics; stable x2c_* entry points.

Runtime library: every row "runtime as today". This stance touches no
lib/ module; the Match, Lisp, Scope/Pool, Error, Var, and collection
modules are untouched, including lib/match-recursive.x (oracle) and
lib/machine.x.

Tooling and packaging: every row "as today" (cli, project, build,
workers, install, bootstrap, script, report, repl, graph, lint, torch).
The Compiler surface graph and repl depend on (map 2.12) is preserved:
`audit_regions`, `semantic_binding_facts`, `emitted_binding_name`,
`region_*`, `dump_*`, and `CliRequest.command=<translate>`.

Drops: none.

## 5. Line ledger

Lines by map subsystem, before and after. lib/ residual lists the 23
lib files no subsystem section names (lib/protocols.x, error_init.x,
diff.x, digest.x, list-selectors.x, scripting.x, string-classify.x,
string-number.x, thread-state.x, typed-list.x, list-generics.xmacro,
var-adapters.xmacro, var-ledger.x, var-unbox.xmacro, varops.xmacro,
static-init.x, clibc.x, cmath.x, native-scalar-types.xmacro,
integer-ops.xmacro, system-macros.xmacro, error-private.xmacro,
private-keywords.xmacro). lib/machine.x is counted once, in 2.4.

| subsystem | before | after | reasoning |
|---|---|---|---|
| 2.1 front end (tokenizer, parse, frontend, collect, deps, sourceview) | 5,341 | 5,316 | `_write_datum` (src/collect.x:979-1001) becomes freeze then Lisp print; -25 |
| 2.2 syntax (ast, ast-rewrite, literals, expressions, statements) | 6,637 | 6,590 | shared cons-boxing helper (src/literals.x:75-97 vs src/expressions.x:2109-2129), one postfix member parser (map 2.2); -47. `_resolve_content` and `convert_expression` unchanged |
| 2.3 macros and comptime | 8,818 | 8,818 | as today |
| 2.4 Lisp and wordcode (lisp, lisp-machine, machine, hand .xlisp, lisp-bindings, x2c-payload) | 5,878 | 5,878 | as today |
| 2.5 transforms (transform, lambda, cleanup, regions) | 5,542 | 4,830 | transform+lambda+cleanup 4,261 -> ~3,600: driver 330 -> 120 (src/transform.x:1471-1801), cleanup walk skeleton -120 (src/cleanup.x:123-148, 626-781 fold into the driver's cases), adapter unification -200 (src/lambda.x keys at 236, 496, 577, 645, 703, 786), nested-lambda walker -25, origin handling once instead of in three files (`%(at` at 8+6+2 sites); regions 1,281 -> 1,230 (two worklist walkers merged) |
| 2.6 backend (generate, cache, emit, format, diagnostics) | 4,141 | 4,000 | cache-id collection and header reference rewrite fold into emit (src/cache.x:504-558, 588-634 shrink); partition marker lists become per-node destinations (src/generate.x:567-602, 684-694); emit gains ~30; -141 |
| 2.7 driver | 6,045 | 6,045 | as today |
| 2.8 values | 11,454 | 11,454 | as today |
| 2.9 match (match, match-recursive, match-machine, split, regex; machine.x counted in 2.4) | 4,692 | 4,692 | as today |
| 2.10 runtime infrastructure | 7,638 | 7,638 | as today |
| 2.11 services | 4,953 | 4,953 | as today |
| 2.13 types, protocols, translation state | 7,492 | 7,150 | compiler.x 3,905 -> ~3,560: one top-level classifier for the shallow loop and `parse_top_level` (src/compiler.x:1669-1744 vs src/parse.x:1953-2032, map says 140 duplicated), struct regrouping and reset (-90), `fixed` and its memo (-15), freeze/thaw shared with `.xi` (-20); type.x and protocol.x unchanged |
| lib/ residual (23 files) | 1,773 | 1,773 | as today |
| total | 80,404 | 79,137 | -1,267 (1.6%) |

The before column sums to the map's 80,404. Reference implementations
for the estimates: the fused driver is the shape of `_rewrite` in
src/cleanup.x:640-731 (one match with region cases and child recursion,
about 90 lines) plus the head-stable loop; the adapter helper's scope is
the map's own 150-250 estimate for six identical compute-key/check/build/
queue/store sequences; the cache fold is bounded by the 130 lines of
src/cache.x:504-558 and 616 that exist only to find ids after the fact.
A credible range for the total is 78,600 to 79,400; the point estimate is
the middle of what the cited deletions support.

## 6. Performance ledger

| dimension | expected change | payoff | measured by |
|---|---|---|---|
| compile throughput (build-cost score) | -5% to -12% per unit | removes k-1 transform confirmation walks, the early-declaration rounds, the cleanup walk, two cache walks, and the header reference rewrite; the fixed point alone was recorded at ~0.1 s per unit (architecture-salvage.md, Declined) against ~1 s for a heavy unit (meta-functions.md:476) | `make bm-build-scaling` cycles per line against unittest/benchmarks/build-scaling-baseline.json (464,833 at b8d9c452); translation CSV (`unittest/benchmarks/run-compiler-translation.sh`, which translates transform.x, emit.x, expressions.x, generate.x, parse.x, type.x, tokenizer.x) |
| where it is not faster | 0 | per-node rewrite work is unchanged: the same helpers run on the same nodes; regions still walks the typed unit; the volatile analysis still walks every function that opens a `try`; the label pre-scan stays; partition's typedef lookahead is the same quadratic scan over top-level items | same instruments; a unit with no `try`, no lambda, and no literal cache should show the largest gain, a macro-heavy unit the smallest |
| macro expansion time | 0 | untouched | lisp-auto benchmark, unchanged |
| generated-code speed | 0 | the emitted C constructs are the same; only lambda sibling placement and possibly declaration order of cache slots change | shootout, bm-all; stage 0-3 comparison is self-consistency, not equality with today's C |
| runtime hot paths (Var ops, Match, Scope/Pool, errors) | 0 | lib/ untouched | bm-all |
| memory | slightly lower | no `fixed` map, no re-cons of anchors per round, no header/source cache-id arrays | build-scaling peak RSS if recorded; otherwise not measured |
| build orchestration | 0 | untouched | clean four-stage build time |

No regression is expected; a regression of any size on the build-cost
score would be a defect of the implementation, not a design trade.

## 7. Bootstrap plan

This is an in-place restructuring of src/, compiled by the checked-in
bootstrap at every step; no language transition, no intermediate
compiler. Each step is one gate round with the stage comparison and
`make verify-fixtures`; the steps that change generated C regenerate the
`.transform`, `.c`, `.h` fixtures they touch and review the diff.

1. Local fixed point. Replace the `while (newast != ast)` loop and the
   early-declaration rounds (src/transform.x:1776-1801) with head-stable
   re-dispatch inside `_node` and sibling placement beside the function.
   Delete `fixed`. Generated C is expected byte-identical except lambda
   sibling order; the 38 `.transform` and the lambda fixtures
   (`lambda-lowering`, `captured-lambda-lowering`, `callback-adapt`)
   move.
2. Fold cleanup. Move the region stack, exit splicing, and label
   ancestry into the same driver; keep the volatile analysis as the
   per-function post-step. Fixtures: `goto-cleanup-regions`,
   `defer-try-cleanup`, `defer-only-cleanup`, `cleanup-loop-boundary`,
   `catch-filter-arms`, `defer-inside-try-exit`, and the `.diagnostics`
   fixtures pinning the two goto errors (src/cleanup.x:221-236).
   Generated C is expected byte-identical.
3. One adapter helper in lambda.x. Byte-identical C expected; the six key
   namespaces must not collide (map 2.5 open question), checked by the
   adapter fixtures under unittest/compiler-fixtures and the self-host
   comparison.
4. Cache materialization into emit; partition before lowering.
   Fixtures: `literal-cache-init`, `promoted-string-cache`,
   `cache-reachability`, `conditional-private-split`,
   `header-typedef-after-function`, `class-header-placement`, the 76 `.h`
   fixtures, and `run-header-cache.sh`. Declaration order of cache slots
   may change; review.
5. One top-level classifier for collection and parse; freeze/thaw as the
   one serialization; `.xi` byte identity checked by
   `tools/check-cold-collection.sh` (proof-cold-collection in
   agent-pr-check) and `unittest/probes/run-header-cache.sh`.
6. Compiler struct regrouping. No output change.

Order matters only in that 1 precedes 2 (the driver must exist before
cleanup's cases join it) and 5 is independent of the rest. Self-hosting is
continuous: every step is compiled by stage 0 and must reproduce itself at
stage 3.

## 8. Language changes

None.

## 9. Risks and unknowns

- Not measured: the share of translation time in the transform
  confirmation walks, cleanup, and cache walks on current dev. The 0.1 s
  per unit figure is from the 2026-09-17 record, not a fresh measurement;
  the thesis's performance claim is refuted if the translation CSV shows
  under 3% after step 1-2.
- Head-stable re-dispatch assumes helpers are confluent under any order,
  which the unit-wide fixed point already assumes; a helper that relied on
  a *sibling* or *ancestor* having been rewritten in an earlier round
  would break. `_rewrite_defer_list` reads siblings (src/transform.x:
  1311-1342) but runs at the block, before children, as today
  (1754-1758). No other sibling dependence was found; the fixtures in
  step 1 would show one.
- The `.transform` and `.ast` fixtures pin intermediate shapes
  (unittest/compiler-fixtures/README.md), so this design changes 38
  `.transform` expectations by construction. The brief allows fixtures
  that pin wording to change; whether an intermediate dump is "wording"
  is Gary's call. The 181 `.c`, 76 `.h`, 393 `.stdout`, and 406 `.status`
  fixtures are the behavior pins and are expected to hold except for the
  ordering noted above.
- The volatile rule is a whole-body analysis after regions are placed; a
  miss is a miscompilation visible only under optimization
  (emit-cleanup-lowering.md, Risks). This design keeps it as a separate
  per-function step precisely so it is not fused; the `$let` inside `try`
  fixture must stay in view.
- Partition before lowering assumes lowering never changes a top-level
  node's destination. `generate_protocol_adapters` inserts native aliases
  at the visibility boundary (src/protocol.x:2327-2328) before lowering
  today, and lifted siblings are static, so they are source-only; a
  lowering that produced a public top-level node would break the
  assumption. None was found.
- The struct regrouping touches every `c.field` spelling in src/ (a
  mechanical rename with `delegate`), which is a large diff for a small
  saving; it can be dropped without affecting the walks.
- What would refute the thesis: a measured fixed-point cost under 3% of
  translation, or a fixture showing a rewrite that depends on an earlier
  round having rewritten a different node.

## 10. Claims

1. The transform driver re-walks the whole unit until List identity, and
   again for each batch of early declarations: src/transform.x:1780-1784,
   1787-1796; cleanup runs once after: 1800; the `fixed` memo exists to
   make confirmation walks cheap: src/compiler.x:110-113,
   src/transform.x:1601-1617.
2. Helpers rewrite only their current node and the dispatcher recurses
   into returned children: src/transform.x:1586-1589; re-transforming
   transform output at the unit level is idempotent, and the extra
   per-function transform cost 0.5 ms a function: plans/archive/
   meta-functions.md:470-476.
3. The fixed point was recorded at about 0.1 s per unit and an ordered
   pass list was declined for moving ordering constraints, not for cost:
   plans/archive/architecture-salvage.md, "Declined, with reasons".
4. cleanup.x is a separate whole-unit walk (`_units` src/cleanup.x:762-773,
   `_function` 735-760, `_rewrite` 640-731) that needs label ancestry
   before gotos (167-207) and a whole-body volatile analysis (242-624).
5. Cache materialization walks header and source after partition:
   src/generate.x:1232-1238; src/cache.x:533-542 (`_cache_ids_in`),
   696-702 (both regions), 545-558 and 616 (header reference rewrite).
6. `convert_expression` is an operation, not a pass: 69 call sites across
   expressions.x (23), transform.x (30), lambda.x (8), protocol.x (3),
   literals.x (2), macros.x (1), comptime.x (1) (grep); it recurses into
   ternary and generic arms because only one arm runs
   (src/expressions.x:4086-4103, 4112-4119).
7. Partition reads only top-level heads, types, bindings, and binding
   facts: src/generate.x:604-695; its lookahead is over typedef spellings:
   491-524, 529-565; 76 `.h` fixtures pin it (find count).
8. freeze/thaw (src/compiler.x:1274-1343) and `_write_datum`
   (src/collect.x:979-1001) encode the same canonical data; `.xi` replay
   is pinned by unittest/probes/run-header-cache.sh and
   tools/check-cold-collection.sh; the runtime prelude is replayed from
   its interface at src/collect.x:584.
9. Regions runs on the typed unit before lowering (src/transform.x:
   1777-1779; src/regions.x:1207-1225) to a unit-wide summaries fixpoint
   (1200-1204), hard-errors only for meta (1237-1256), and is consumed by
   commands/graph/x2c-graph.x:2605 through `audit_regions`.
10. Fixture counts on dev: 873 `.phases`, 43 `.ast`, 38 `.transform`,
    16 `.tokens`, 11 `.symbols`, 181 `.c`, 76 `.h`, 413 `.diagnostics`,
    393 `.stdout`, 406 `.status` (find under unittest/compiler-fixtures);
    the runner is unittest/compiler-fixtures/run.sh and the phase list is
    documented in its README.md.
11. main.x stops on parse errors before the transform runs
    (src/main.x:126-129) and on transform errors before generation
    (74-81), which is why parse and lower stay two walks.
12. `Compiler.emit` is already one bottom-up pass over its list
    (src/emit.x:1457-1459) and the Emitter already records per-emission
    statics (src/emit.x:22-29, 301-421).
13. `Compiler.transform` has one caller, src/main.x:76; `mark_cleanup_regions`
    one, src/transform.x:1800; `check_regions` one, src/transform.x:1779.
14. Lambda siblings are appended after the unit today
    (src/transform.x:1785-1797); placing them beside the function changes
    only their position: plans/archive/meta-functions.md:473-475.
15. The Compiler struct declares about 115-119 field names in
    src/compiler.x:71-184; `full_parse` resets twenty of them at
    2000-2028; `SymTxn` snapshots the fields listed at 2538-2543 only.
16. Phase 2 (shared exit blocks) and Phase 3 (initializer guards) of
    cleanup lowering were measured and declined on 2026-09-24
    (plans/archive/emit-cleanup-lowering.md); this design proposes neither.
