# x2c subsystem map for the rebuild research spike

Synthesized from 15 reader reports (front, syntax, macros, lisp, transforms,
backend, driver, values, match, infra, services, features, harness, history,
commands). Read-only research; no source was edited. Every file:line citation
below comes from a reader report and was not re-verified by this synthesis
unless marked. Line counts are `wc -l` on current dev (2026-09-26).

Totals (hand-authored .x/.xmacro, plus etc/ Lisp):

| tree | lines | note |
|---|---|---|
| src/ (.x + .xmacro) | 41,951 | 36 files; largest expressions.x 4388, macros.x 4160, compiler.x 3905, comptime.x 3436 |
| lib/ (.x + .xmacro) | 35,878 | 60 files; largest lisp.x 3190, match.x 2677, string.x 1771, autodiff.xmacro 1402 |
| etc/ (.x + .xmacro + .xlisp) | 11,758 | 17 files; 8,719 of these are the generated etc/builtin-macros.xlisp |
| etc/builtin-macros.xlisp (generated) | 8,719 | lowered from 684-line etc/builtin-macros.x (~12.7x) |
| etc/ including .mk/.py/.sh | 13,055 | build fragments and tools |

Hand-authored compiler + runtime + compile-time library (src + lib + etc minus
generated .xlisp): about 41,951 + 35,878 + (11,758 - 8,719 - 235 - 229) =
80,404 lines. Non-code inventories in scope: unittest/test-*.x 25,403 lines
(58 suites), examples/manifest.txt 64 entries, commands/ ~14,900 lines.

---

## 1. Overview: how the pieces make the language possible

x2c is a superset of C whose compiler is an x2c program. Six mechanisms
interlock; the data-flow story from source text to C follows.

**The x2c base types are the universal representation.** `Var` (lib/common.x,
lib/var.x) is an 8-byte NaN-boxed union carrying every scalar, pointer, and
boxed kind. `List` (lib/list.x) is a cons chain of Var. There is no separate
AST type and no separate Lisp datum type: `Ast` is `typedef List` (src/ast.x),
the compile-time Lisp evaluator's values are Var/List/String/Map/Array
(lib/lisp.x), match patterns are Lists (lib/match.x), and the runtime's
generic containers hold Var. One representation is therefore shared by the
parser, the macro expander, compile-time Lisp, the wordcode machines, and
generated C at runtime. The tag layout is authored once as a meta-time ledger
(lib/var-tags.xmacro `_tag_groups`) and projected into both the runtime decode
tables (lib/var-ledger.x) and the compiler's type table (src/type-ledger.x).

**C is both the target and the substrate.** Every x2c construct lowers to C
(src/emit.x, src/format.x). Runtime semantics that C lacks (regions, raise/
catch, Var dispatch, Func closures, match) are ordinary C library code in
lib/. The compiler's own source is compiled through that same runtime, so
runtime cost bounds compiler throughput (lib/scope.x, lib/pool.x are the
allocator under every compiler pass).

**Macros are AST templates over canonical syntax.** A `macro` definition
(src/macros.x:3153 parse_macro_definition) is a hygienic List template plus an
invocation-match pattern. The parser calls into macro dispatch at every syntax
position (unit, block, field, enumerator, map-entry, expression; MacroPos
table in src/macros.x) and expansion is `template.replace(...)`
(src/macros.x:3839-3862). Hygiene is applied at definition time by renaming
template-local binders (src/macros.x:2499-2576). Because ordinary compiler
operations accept forms by structure without authenticating origin
(docs/src/reference/language.md "Macro-visible syntax", line 1863), any
canonical List reaching resolve_expression is legal syntax, whether typed by
hand, produced by a macro, or built by compile-time Lisp.

**Meta functions bridge x2c and compile-time Lisp.** A `meta`-tagged x2c
function is lowered once by src/comptime.x (`Compiler.lower_comptime`,
src/comptime.x:2912) into Lisp s-expressions that the compile-time session
evaluates. lib/meta.x declares bodyless `meta` prototypes (x2c_ident,
x2c_type_fields, x2c_expr_call, ...) that name compiler-native operations;
src/macros.x:147-961 supplies their native implementations, bound into the
Lisp session under a name-mangling convention (`_meta_lisp_name`,
src/macros.x:1077-1083). A meta function that transitively reaches such an
operation gets no runtime body (lib/meta.x:16-21; src/comptime.x:47,365-367,
2897). The self-hosting loop closes here: etc/builtin-macros.x and etc/init.x
are ordinary x2c meta functions lowered at build time (via `$builtin.emit` /
`$init.emit` decorators and tools/gen-lisp-init.py) into
etc/builtin-macros.xlisp and etc/init.xlisp, so the compiler's own built-in
macros (foreach, class, scope, let, lock, auto) are authored in x2c, not
hand-written Lisp. Runtime-facing meta lowering reads the pre-transform AST
only; the post-transform tree has erased lambdas and interpolation
(plans/archive/meta-functions.md, M3 declined).

**Compile-time Lisp is the macro-time execution engine.** lib/lisp.x is a
tree-walking evaluator with lexical free-name capture, macros as
unevaluated-argument lambdas, and a session hierarchy (parent/adopt/freeze,
lib/lisp.x:770-799) that lets one preloaded library session (init, lisp-values,
comptime, compiler-sdk, builtin-macros; src/macros.x:1155
open_macro_library/publish_macro_library) be shared read-only by every
translation unit. etc/comptime.xlisp supplies the `C.*` runtime (C.true?,
C.conv, C.compare, C.peek/poke) so lowered x2c keeps C semantics inside Lisp.
etc/init.xlisp is embedded verbatim in lib/lisp.x (lib/lisp.x:85-86,383) and
loaded by every `Lisp.new` at runtime too (lib/lisp.x:752-756), so compile-time
and runtime Lisp are one engine.

**The wordcode machine is a narrow shared VM.** lib/machine.x defines one
8-byte MachineWord encoding, MachineBuilder/MachineProgram/MachineView, and
both MatchMachine and LispMachine state structs. Two backtracking interpreters
use it: lib/match.x's MatchLower compiles a normalized List pattern to
wordcode run by lib/match-machine.x, and lib/lisp.x's AUTO tier
(`_auto_apply`, lib/lisp.x:2836; LispLower at 2332) promotes a twice-called
Lambda to wordcode run by lib/lisp-machine.x, crossing back to the evaluator
only at fixed points (lib/lisp-machine.x:114,132,146,169,238,264,326,336,367,
375,380,388). Only MW_JUMP and the status vocabulary are shared between the
two decoders (lib/machine.x:9-10). The `match` statement lowers to
List.match calls; the machine is not a general execution substrate.

**Data flow, source to C:**

1. Bytes (disk, SourceView overlay, or CPP-preprocessed buffer) ->
   `Tokenizer.scan` (lib/tokenizer.x:793) -> stable Token array, optionally
   rewritten by the `#pragma indent` layout pass (lib/tokenizer.x:624-629,766).
   The tokenizer has a mode family (x2c/list/array/map/string/symbol-set/
   macro-lisp) so Lisp source and Lisp data literals share one Atom scanner
   (lib/tokenizer.x:484-550).
2. Shallow collection: `Compiler.collect_symbols` (src/collect.x:567) walks the
   include graph once with the declaration-only dispatch `_shallow_parse_loop`
   (src/compiler.x:1669), populating a process-wide cache keyed by canonical
   path, replaying `.xi` interface files when valid. A unit macro met during
   collection is expanded once via the full parser inside a semantic
   transaction and its declaration bundle is frozen as portable Lisp data
   (`_shallow_parse_unit_macro`, src/compiler.x:1650; freeze/thaw at
   src/compiler.x:1270-1343).
3. Full parse: `Compiler.full_parse` (src/compiler.x:1999) drives
   `Compiler.parse_top_level` (src/parse.x:1953) -> statements.x /
   expressions.x / literals.x build untyped canonical Lists; macro and
   decorator invocations are claimed at each position (src/macros.x:4154
   try_parse_macro_target_at) and expanded via `expand_macro_invocation_node`
   (src/macros.x:3757). Meta function bodies run in the shared Lisp session.
4. Resolution: `resolve_expression` / `_resolve_content`
   (src/expressions.x:2447-2454, 2041-2434) attaches types bottom-up, producing
   `(expr TYPE VALUE)`; `convert_expression` (src/expressions.x:4053-4366)
   inserts C-visible conversions (Var boxing, Func lifting, compound literal
   placement). Protocol members resolve through src/protocol.x; Var tag facts
   through src/type.x and the ledger.
5. Region analysis before lowering: `Compiler.check_regions`
   (src/regions.x:1212, called at src/transform.x:1779) walks the still-lexical
   AST to a per-unit fixpoint and warns on escaping values; the meta variant
   (`check_meta_regions`, src/regions.x:1237) hard-errors because a compile-time
   call's locals are freed on return.
6. Transform: `Compiler.transform` (src/transform.x:1776) runs a fixed-point
   rewrite (identity termination via c.fixed, src/transform.x:1605-1617) lowering
   Var operators, printf Var inference, interpolation, destructuring, raise,
   defer, and lambdas (src/lambda.x: lower_lambda_expr at 1648, adapters at
   153/429/573/641/780). Then `mark_cleanup_regions` (src/cleanup.x:781, called
   at src/transform.x:1800) names defer/try regions, attaches unwind statements
   on every exit, and applies sigsetjmp volatile rules (src/cleanup.x:242-624).
7. Backend: src/cache.x materializes literal constants preserving identity
   across header and source (src/cache.x:9-13, 52-66); src/generate.x
   partitions the unit into .h/.c honoring C visibility and typedef order
   (src/generate.x:357-602) and writes files (`generate_code`,
   src/generate.x:1228); `Compiler.emit` (src/emit.x:1449) lowers each node to a
   flat token List (declarators 31-133, local statics 301-421, match/try/raise
   423-862, precedence 1041-1160); `code_pretty_string` (src/format.x:90)
   renders tokens with #line remapping in one pass. src/diagnostics.x
   accumulates and streams diagnostics (report at 171; JSON Lines at 212).
8. Native: src/build.x compiles the C through src/toolchain.x with
   content-addressed fingerprints (src/build.x:75-181) and publishes artifacts
   atomically. Generated code links against lib/: scope/pool allocation,
   error/exception unwinding driven by cleanup.x's emitted calls, Func
   adapters from lambda.x, match plans bound per call site
   (x2c_match_site_*), and dispatch descriptors for Var operators.

---

## 2. Subsystems

### 2.1 Front end (lib/tokenizer.x, src/parse.x, src/frontend.x, src/collect.x, src/deps.x, src/sourceview.x)

Lines: tokenizer 843, parse 2830, frontend 400, collect 1053, deps 139,
sourceview 76 (total 5,341; plus the shallow loop and freeze/thaw living in
src/compiler.x 3905).

Purpose: bytes -> stable tokens -> source-ordered declaration environment
(without body parsing) -> full AST. frontend.x is the only place that
sequences these per unit and owns the native-preprocessor bridge and the
one-time lib/meta.x preload into the shared Lisp session.

Key types: Token, Tokenizer (mode stack; tokens pointer-stable only after
scan, lib/tokenizer.x:9-11, 788-792), Frontend (session-scoped: CliRequest,
include dirs, Toolchain), ParsedUnit (start->collect->parse->close),
process_cache (src/collect.x static Map: canonical path -> `(ordered-parts
content-hash definitions dependencies)`), SourceView.

Entry points: Frontend.open / open_session (src/frontend.x:376);
Compiler.collect_symbols (src/collect.x:567); Compiler.shallow_parse /
shallow_parse_overlay (src/compiler.x:1747); Compiler.full_parse
(src/compiler.x:1999); Compiler.parse_top_level (src/parse.x:1953);
Tokenizer.scan (lib/tokenizer.x:793).

Coupling: src/compiler.x owns Compiler state, the shallow dispatch loop, and
freeze/thaw; parse.x includes statements/expressions/literals/macros/protocol;
frontend.x uses build.x's CliRequest and toolchain preprocess; collect.x reaches
into Tokenizer internals to shift token line/pos for spliced segments
(src/collect.x:255-259); imports lib/private-keywords.xmacro and
ast-rewrite.xmacro.

Must preserve: token pointer stability; first cold walk fixes a file's cache
contribution (src/collect.x:523-533, 399-407); `.xi` replay reproduces exact
rows with deterministic binding renumbering (src/collect.x:963-973, 1003-1036);
package `name__` prefix rule only under the package root (src/collect.x:637-643);
`#pragma private` visibility across include boundaries (src/collect.x:286-289,
_keep_published_rows); script-unit implicit main agreement between passes
(src/parse.x:1768-1802); Tokenizer.next EOF idempotence (lib/tokenizer.x:826-829);
layout rewrite indistinguishable from braces (lib/tokenizer.x:624-629, 766).

Rebuild notes: (1) Collapse the two top-level dispatchers (`_shallow_parse_loop`
src/compiler.x:1669-1744 vs `parse_top_level` src/parse.x:1953-2032) into one
classification step with two continuations (skip body vs parse body). (2)
The freeze/thaw encoding (src/compiler.x:1270-1343) and the `.xi`
`_write_datum`/`_interface_load` encoding (src/collect.x:979-1036) look like
two independently maintained canonical-Lisp serializations; one primitive may
serve both. (3) tokenizer.x's `_operator` dispatch (lib/tokenizer.x:153-209)
is already tight; keep. (4) Re-examine `_require_retained(...)` calls
(src/collect.x:370-374, 391-394, 501-513) against any redesigned cache scope
discipline; not verified whether try_own() can fail there today.

### 2.2 Syntax (src/ast.x, src/literals.x, src/expressions.x, src/statements.x)

Lines: ast 277, literals 1253, expressions 4388, statements 700 (total 6,618).

Purpose: tokens -> canonical AST Lists for literals, expressions, and
statements; ast.x supplies binding identity, preproc-arm tracking,
`Ast.never_returns` (src/ast.x:228), and `Ast.rewrite_children`
(src/ast.x:170), the generic fixed-point child rewrite used by transform.x.

Key types: Ast (typedef List), AstPos (unit/block/field/enumerator/map-entry/
statement/expression), binding node (spelling + positive compiler-issued
identity, src/ast.x:32-62).

Entry points: parse_governed (src/statements.x:70); parse_variable
(src/expressions.x:2624); parse_primary (src/expressions.x:2721);
resolve_expression (src/expressions.x:2454); convert_expression
(src/expressions.x:4053); func_call_parts (src/expressions.x:1747).

Data flow: literals.x folds pure literal ASTs into cache entries as it parses
(Compiler.cache/cache_cons_cell), so caching interleaves with parsing.
Macro-invoke, macro-slot, and meta-call cases sit as ordinary match
alternatives in `_resolve_content` (src/expressions.x:2062-2081); meta syntax
gets no parallel resolver. statements.x threads preprocessor directive
placement through parse_governed (src/statements.x:70-96).

Must preserve: never_returns' three terminal forms (src/ast.x:222-227,
_Noreturn contract); no origin-authenticating validator (per
agents/replacing-manual-ast-walks-with-match.md:134-141); binding identity
contract; preproc_track_arms innermost-first ordering (src/ast.x:96-120).

Rebuild notes: split `_resolve_content` (src/expressions.x:2041-2434, ~30
cases) into per-family dispatchers; factor the repeated
is_var_type-then-box-or-convert idiom shared by src/literals.x:75-97 and
src/expressions.x:2109-2129; let the ternary case in `_resolve_content`
(2371-2372) own per-arm conversion instead of `convert_expression` recursing
(4088-4100); collapse `_parse_postfix_dot` (636) / `_parse_postfix_arrow` (654)
over the shared `_parse_field_name` (620). Any split of convert_expression
needs generated-C verification because sequential precedence among its six
conversion families may be load-bearing.

### 2.3 Macros and comptime (src/macros.x, src/comptime.x, lib/meta.x, etc/builtin-macros.x, etc/builtin-macros.xmacro, etc/init.x)

Lines: macros 4160, comptime 3436, meta 315, builtin-macros.x 684,
builtin-macros.xmacro 57, init.x 166 (total 8,818).

Purpose: parse `macro` definitions into hygienic templates, match and expand
invocations at every syntax position, give macro/meta bodies a compiler-native
surface (lib/meta.x), and lower x2c meta functions to Lisp (comptime.x) so the
built-in macro algorithms and standard Lisp library are authored in x2c.

Key types: Lowering (per-function env/locals/cells/arrays/records/callees maps,
loop continuations, declined/meta_only/uncallable flags), LowerCleanup (one
active defer wrapper during lowering), macrodef (List: name, kind, target
kind, holes, fresh-rename rows, captures, match pattern, template), MacroPos /
macro_position_info.

Entry points: parse_macro_definition (src/macros.x:3153);
expand_macro_invocation_node (src/macros.x:3757); try_parse_macro_target_at /
try_parse_macro_expression (src/macros.x:4154); install_meta_function /
install_native_meta_function (src/macros.x:2045); lower_comptime
(src/comptime.x:2912); open_macro_library / publish_macro_library
(src/macros.x:1155); x2c_comptime_lower (src/macros.x:956; lib/meta.x:315).

Data flow: invocation recognition (src/macros.x:699-805 _peek_invocation /
_claims) -> capture rows with source/value/expression/splice projections
(src/macros.x:2590-2773) -> match against macrodef pattern -> template.replace
(src/macros.x:3839-3862). Comptime: `_lower_scan` (src/comptime.x:421-471)
classifies locals as cell-needing; `_lower_place/_lower_operands/_lower_call`
(src/comptime.x:812-1150+) substitute Lisp per construct; tail calls stay in
one Lisp frame; C facts thread through `_lower_pointer_tag`, `meta_type_layout`,
`C.at/peek/poke` (src/comptime.x:94-131, 716-734).

Coupling: parse.x/expressions.x/statements.x call macro_starts_target_at etc.;
comptime.x and macros.x call sym.resolve_key/field_order/
protocol_members_for in type.x/protocol.x; lib/meta.x is the matched
interface for src/macros.x:147-961; etc/*.xlisp libraries are loaded by
_ensure_lisp/_eval_library; regions.x's check_meta_regions is called from
comptime.x.

Features: typed result kinds (Expression, Statement, Block, Field, Enumerator,
Unit, NamedType, Decorator); keyword aliasing; decorators; sequence holes and
projections; hygiene; `$(import ...)` with cycle detection and replay; dlopen
native modules; meta functions; comptime lowering with tail-call loops and
Func/native adapter conventions; shared parent session with `<lisp-late>`
restart; recursion guards (identical recursive expansion rejected, 64 deep,
10000 count, src/macros.x:3775-3805); system macros ($scope, $let, $lock,
$auto, $x2c.foreach, $class) as ordinary macros.

Must preserve: hygiene (src/macros.x:2499-2576; e.g. foreach iterator names
in etc/builtin-macros.xmacro:14-23); meta-only diagnosis (lib/meta.x:16-21;
src/comptime.x:47,365-367,2897); expansion guards; byte-identical .xlisp
regeneration from identical x2c source (bootstrap/ depends on it).

Rebuild notes: keep the meta/macro split (lib/meta.x as native surface,
ordinary x2c for the rest). Collapse the duplicated emit/write collector in
etc/builtin-macros.x:1-25 and etc/init.x:1-25 (~20 lines). The shared-library
lifecycle flags (library_filling/restartable/settled/imports/definitions/
session/scope, src/macros.x:1000-1281) plus the raise-`<lisp-late>` restart
(src/macros.x:1229-1281, only reachable when a unit's session request races
the parent fill, 1244-1281) could collapse to one boolean and a sequential
preload if driver ordering guaranteed the parent library exists before any
unit starts; that changes src/utils.x/frontend orchestration. The
native-meta inventory machinery (src/macros.x:478-568) has no confirmed
external consumer beyond lib/lisp.x's target generation. Remaining ~2100
lines of comptime.x (statement lowering, loops, cleanup) were not fully read.

### 2.4 Compile-time Lisp and the wordcode machine (lib/lisp.x, lib/lisp-machine.x, lib/machine.x, etc/*.xlisp)

Lines: lisp 3190, lisp-machine 480, machine 540, init.xlisp 235 (generated),
init-core.xlisp 176, comptime.xlisp 399, lisp-values.xlisp 465,
lisp-bindings.xlisp 229 (generated), lisp-bindings.x 137,
lisp-bindings.xmacro 20, builtin-core.xlisp 34, compiler-sdk.xlisp 23,
lisp-extras.xlisp 28, builtin-macros.xlisp 8719 (generated). Not inspected:
etc/lisp-bindings-core.xlisp 33, etc/lisp-io.xlisp 5, etc/x2c-payload.x 348.

Purpose: embeddable Lisp (reader lib/lisp.x:560-829; evaluator `_eval`
lib/lisp.x:723-737 with env chain locals -> captures -> globals -> reserved,
lib/lisp.x:391-395, 1845-1960) used for macro expansion, meta functions, and
the bootstrap-built library; AUTO tier compiles hot Lambdas to wordcode.

Key types: Lisp (session: globals/reserved, parent/freeze chain, AUTO stats,
machine-slot free list), Lambda (params, body, captures, macro flag, AUTO
status/program), LispEnv, LispLower (lib/lisp.x:2332), LispExpansion
(dependencies of a speculative macro pre-expansion), MachineBuilder /
MachineProgram / MachineView, LispMachine / LispFrame.

Entry points: Lisp.new / Lisp.kernel (lib/lisp.x:720); Lisp.eval / apply /
eval_string (lib/lisp.x:765); `_auto_apply` (lib/lisp.x:2836, from `_apply`
at 2960); Lisp.auto_prepare (lib/lisp.x:2944); LispMachine.step / run
(lib/lisp-machine.x:308).

Data flow: AUTO promotion on second call -> `_auto_analyze` (lib/lisp.x:2703)
-> `_auto_lower` (2600) -> LispLower emits MW_* words, constant-folding quote/
cond/quasiquote, inlining immediate-lambda lets into frame slots
(MW_LBIND/MW_LUNBIND), speculatively pre-expanding macros whose expansion
depended only on frozen-ancestor values (`_expansion_*`, lib/lisp.x:1855-1905;
guard at 469-477 and lib/lisp-machine.x:378-385). Native bridge:
lisp_native_targets (lib/lisp.x:1607-1819) merges hand rows, the
compiler-generated `_x2c.native-meta.targets` list (line 1803), and an
override tail.

Features: reader with quote/quasiquote/unquote/splice; free-name lexical
capture; macros as unevaluated-argument lambdas; reserved specials shadowable
by globals; session hierarchy with freeze; bounded wordcode JIT with tail-call
frame reuse; speculative macro pre-expansion with rewind; and a second
independent x2c-to-Lisp backend (x2c_comptime_lower).

Must preserve: only nil is false (lisp_truth, lib/lisp.x:833-838); macros get
raw forms, calls evaluate left to right (`_apply_lambda`, lib/lisp.x:2166-2174);
free-name capture, no self-recursion by let-bound name
(docs/src/reference/language.md:1408-1422; lib/lisp.x:1978-2021); `def` on an
inherited name raises `(bad-state (why "inherited"))`
(docs/src/reference/language.md:1424-1432; lib/lisp.x:2195-2214, 1923-1927);
AUTO transparency; the differential checker
`x2c script examples/programs/check-reference-lisp --build`; generated .xlisp
never hand-edited.

Rebuild notes: (1) unify src/comptime.x's x2c_comptime_lower and lib/lisp.x's
LispLower on one expression-walking core parameterized by output (text vs
wordcode); both recognize cond, immediate-lambda apply, quote/quasiquote,
calls. (2) emit quasiquote for `%(...)` templates instead of cons/quote
chains: etc/builtin-macros.x:65-66 becomes 5 lines at
etc/builtin-macros.xlisp:206-215; the 12.7x expansion traces to this choice.
(3) fold the three car/cdr-family definitions (lib/lisp.x:378-381;
etc/init.x:83-105 -> etc/init.xlisp; etc/comptime.xlisp:126-130, 226-393).
(4) benchmark whether excluding globally-dependent macros from AUTO
eligibility costs more than the speculate-and-rewind apparatus. (5) extend
the generated native-meta target table to remove hand rows in
lib/lisp.x:1607-1808.

### 2.5 Transforms (src/transform.x, src/lambda.x, src/cleanup.x, src/regions.x)

Lines: transform 1801, lambda 1679, cleanup 781, regions 1281 (total 5,542).

Purpose: lower the typed AST to emitter-ready form by fixed point; lambda/
closure/adapter synthesis; defer/try region wiring; region/lifetime warnings.

Key types: PrintfLength; cleanup Walk (open regions, break/continue depths,
labels, return type); regions.x Region (scope/pool/slot/auto/local/frame),
Fact (per-local depth, origin, born-storage bits, owning regions, points-to),
Walk (summaries, sinks, warnings, meta/audit flags); the declarative
`runtime` Map (src/regions.x:97-226) mapping ~150 native C names to tagged
lifetime-effect forms read by match (src/regions.x:249-256, 398-408).

Entry points: Compiler.transform (src/transform.x:1776); mark_cleanup_regions
(src/cleanup.x:781); check_regions (src/regions.x:1212); check_meta_regions
(src/regions.x:1237, from comptime.x); audit_regions (src/regions.x:1263,
external audit tool); lower_lambda_expr (src/lambda.x:1648);
lift_func_expression (src/lambda.x:853); lower_typed_adapter_expr
(src/lambda.x:153, from src/transform.x:1567, 1710); maybe_adapt_func_arg
(src/lambda.x:532, from src/transform.x:306).

Coupling: reads/mutates Compiler (sym, fn_name, origin,
semantic_binding_facts, early_decls, names.adapters); Ast.rewrite_children;
type.x predicates; protocol.x resolve_protocol_member/operator_member/
protocol_update_helper; emits calls to lib/func.x (Func_new, Func_new_context,
x2c_func_*) and lib/exception.x (x2c_exception_leave/claim,
x2c_error_catch_close, x2c_cleanup_leave); emit.x consumes (defer ...),
(try ...), (vcompound ...), (vpostfix ...).

Must preserve: fixed-point identity termination (src/transform.x:1605-1617);
try exit ordering catch-close -> finalizer -> frame-leave (src/cleanup.x:95-121);
goto-into-region rejection (src/cleanup.x:216-240) and label-in-finalizer
rejection (src/cleanup.x:660-667); volatile qualification (src/cleanup.x:242-624);
check_meta_regions hard error (src/regions.x:20-21); lambda cell allocation
order (src/lambda.x:1309-1340); adapter argument materialization order
(src/lambda.x:389-414).

Rebuild notes: keep the fixed-point driver; factor adapter construction into
one "synthesize-and-cache a static bridge" helper replacing six key
namespaces (src/lambda.x lines 236, 496, 577, 645, 703, 786), plausibly
150-250 lines; merge `_symbol_expression` (src/transform.x:39-40) and
`_adapter_symbol_literal` (src/lambda.x:295-296); replace the general escape
analysis with a coarser check restricted to the correctness-bearing case
(address of a value from a definitely-closed Scope/Pool), keeping the meta
path; question the ~235-line printf scanner (src/transform.x:52-287); merge
the two worklist walkers `_scan` (src/regions.x:815-890) and `_walk`
(src/regions.x:1093-1143).

### 2.6 Backend (src/generate.x, src/cache.x, src/emit.x, src/format.x, src/diagnostics.x)

Lines: generate 1278, cache 709, emit 1469, format 187, diagnostics 498
(total 4,141).

Purpose: typed/transformed AST -> C header/source pair; literal constant
materialization; diagnostic accumulation and streaming.

Key types: Diagnostics (bounded chronological entries), DiagnosticsHold,
Emitter (fresh-name counters, static_objects, origin tracking), Compiler
(id_keys, origins, diagnostics, root_dir).

Entry points: generate_code (src/generate.x:1228); Compiler.emit
(src/emit.x:1449); code_pretty_string (src/format.x:90); definition_rows /
dump_definitions (src/generate.x:765, editor/tooling); Diagnostics.report /
print_diagnostic (src/diagnostics.x:171); diagnostics_write_json
(src/diagnostics.x:212).

Data flow: cache.x `_generate_cache_val` rewrites (cache id) nodes to inline
references or materialized statics; generate.x `_header_and_source`
partitions (src/generate.x:369-443 visibility; 485-565 typedef forwards;
567-602 conditional balancing); emit.x lowers nodes (declarators 31-133;
local static once-init with acquire/commit 301-421; match/try/raise 423-862;
precedence 1041-1160); format.x renders with #line (src/format.x:90-187).

Coupling: type.x accessors (src/generate.x:376-443, src/emit.x:333-392);
cache.x calls transform_array_literal/transform_map_literal
(src/cache.x:60-66); lib/logger.x is documented as the separate general
logger (agents/logger-and-diagnostics-guide.md:1-15); main.x calls
generate_code and Compiler.emit.

Must preserve: report de-duplication and limit semantics
(src/diagnostics.x:144-189); visibility rules (src/generate.x:369-443, pinned by
fixtures); cache identity across header/source (src/cache.x:9-13); #line
remapping; JSON Lines contract across forked workers (src/diagnostics.x:206-216).

Rebuild notes: the biggest architectural lever is whether to keep C's
two-file output model; ~245 lines of generate.x (357-602) exist only for it.
A unity build or always-forward-declared thin header could halve that, at a
measured cost to incremental parallelism. format.x is a model of minimal
machinery. cache.x and `_local_static` (src/emit.x:301-421) solve different
problems and should stay separate. The JSON and text diagnostic renderers
(src/diagnostics.x:232-283) could share one field-to-Var pass.

### 2.7 Driver (src/main.x, cli.x, build.x, project.x, toolchain.x, report.x, bootstrap.x, install.x, script.x, editor.x, utils.x, Makefile, etc/*.mk)

Lines: main 689, cli 1232, build 1138, project 815, toolchain 423, report
245, bootstrap 345, install 424, script 113, editor 210, utils 411 (src total
6,045); Makefile 542, etc/x2c.mk 89, etc/build-config.mk 56,
etc/make-command.mk 25.

Purpose: argv -> CliRequest -> translate/build/run plan -> native toolchain
with content-addressed incremental caching; plus install, bootstrap, script,
editor, and terminal reporting.

Key types: CliRequest, CliOption / CliCommand tables, Build, Project /
ProjectTarget / ProjectProfile / ProjectDependency, ProjectBuild, Toolchain /
ToolAction / ToolRun, Bootstrap, CcJob, ReportState.

Entry points: main (src/main.x:642); cli_parse (src/cli.x:1162);
CliRequest.prepare (src/build.x:210); Build.finish (src/build.x:813);
project_plan (src/project.x:730); bootstrap_materialize / _run_bootstrap
(src/bootstrap.x / src/main.x:148); install_command / install_require
(src/install.x:332); script_prepare / script_run (src/script.x:70);
editor_request (src/editor.x:160).

Data flow: cli_parse expands @response files and validates per-command masks;
`_run_build` uses inputs or project_plan; CliRequest.prepare resolves the
Toolchain; `_translate_units` forks workers (worker_fork/worker_wait_any in
utils.x); Build.finish compiles with FNV fingerprints against `.x2c-state`,
archives/links, stages and renames. bootstrap.x shells to the freshly built
compiler. script.x fingerprints and execs a cached executable. editor.x stops
before code generation and answers one query as JSON.

Interplay: build.x `_write_entry` hand-writes x2c source text containing
`$(lisp.native.targets ...)` for native module entry units (string
generation, not constructed AST). Compile-time Lisp and the machine appear
only incidentally.

Must preserve: content-addressed fingerprints with build-start-time race
check; atomic publication (src/build.x:855-896, install.x `_publish`,
utils.x file_publish); CLI compatibility diagnostics for removed `-o` and
one-dash long options (src/cli.x:270-282, 1050-1062); bootstrap payload
size+FNV verification and marker identity; bundle version guard
(src/install.x:166-175); script cache fingerprint covering every search
directory (src/build.x:1036-1067).

Rebuild notes: replace the CliOption table (src/cli.x:104-266) plus the
parallel `_apply_option` switch (src/cli.x:894-984) and cli_package_options'
third inline switch (line 1013) with one table carrying setters; unify the
three structured-text readers (src/project.x:308-416, src/install.x:113-120,
src/install.x:157-164); pick one incremental system (src/build.x:75-181 vs
etc/x2c.mk:62-82) and have the other delegate; share the identity hash
helper (src/utils.x:287-294 vs src/build.x:99-119).

### 2.8 Values (lib/var.x, varops.x, varconvert.x, var-tags.xmacro, atom.x, symbol.x, symbolset.x, string.x, list.x, array.x, map.x, typed-array.x, typed-map.x, array-generics.xmacro, map-generics.xmacro, buffer.x, block.x, common.x)

Lines: var 1281, varops 585, varconvert 298, var-tags 415, atom 230, symbol
281, symbolset 130, string 1771, list 1033, array 831, map 722, typed-array
191, typed-map 401, array-generics 840, map-generics 860, buffer 359, block
322, common 904 (total 11,454).

Purpose: the NaN-boxed Var model, boxed collections, interning, and the
generic-macro families that instantiate both boxed and typed variants from
one body. The tag ledger is authored once (var-tags.xmacro) and projected
into runtime (lib/var-ledger.x) and compiler (src/type-ledger.x, 42 lines).

Key types: Var (lib/common.x), TagId (lib/var.x, ledger order),
X2CVarNumericInfo / X2CVarNumeric (lib/varconvert.x), Symbol, List, String,
Array, Map.

Entry points: Var.convert (lib/varconvert.x); `$native.update`
(lib/varops.x, per-type compound update); `_tag_groups`
(lib/var-tags.xmacro, used by lib/var-ledger.x and src/type-ledger.x).

Data flow: varconvert decodes to X2CVarNumeric, masks widths, promotes by
rank, re-boxes; varops decodes both operands, delegates conversion, applies
the operator; native lvalue compound updates are failure-atomic. Collections
store Var; typed variants instantiate the same macro bodies with native
types. buffer.x/block.x supply growable storage.

Must preserve: single ordered tag source (lib/var.x:63-65 check); Var.convert
wrap/truncate/own-tag contract; `$native.update` failure atomicity;
map-generics key fast paths for List and String (lib/map-generics.xmacro:17-30).

Rebuild notes: push further in the same direction: express Block/Buffer
growth as one more generics family; embed X2CVarNumericInfo as the first
member of X2CVarNumeric (lib/varconvert.x:19-21, 28-31). string.x (1771) was
only skimmed; its overlap with Buffer/Block is unaudited.

### 2.9 Match (lib/match.x, match-recursive.x, match-machine.x, machine.x, split.x, regex.x)

Lines: match 2677, match-recursive 445, match-machine 541, machine 540,
split 283, regex 746 (total 5,232).

Purpose: structural List pattern matching in three layers: normalize
(`_normalize_pattern` rewrites `(OP BINDER PAT...)` to `(!set BINDER (OP
PAT...))`), layout (`_layout_collect/_layout_analyze_pattern` assign binder
slots and definite/possible bitsets), lower (`MatchLower._compile_value` to
wordcode; stars/guards/quoted literals get frames, plain nested sublists
descend inline), freeze, execute (MatchMachine with capture journal and
rollback), publish (`_capture_publish`, `_replace`). Literal call-site
patterns bind a MatchPlan permanently to a MatchCaptureSite; runtime patterns
go through a Context-local LRU MatchCache. split.x and regex.x are unrelated
matchers in the same directory.

Key types: MatchCaptureLayout, MatchPlan (PREPARED/INELIGIBLE/MALFORMED),
MatchCache / MatchCacheEntry / MatchLease, MatchMachine, RecursiveMatchState,
MachineWord / MachineBuilder / MachineProgram / MachineView, Regex /
_RegexNode.

Entry points: List.try_match / match / search / match_replace /
search_replace (lib/match.x); x2c_match_site_try_capture and x2c_match_site_*
(compiler-owned per-callsite plans); MatchMachine.step / run
(lib/match-machine.x); match_recursive_* (oracle only).

Must preserve: recursive and compiled engines semantically identical
(lib/match.x:14-27); MatchCaptureSite permanent first-pattern binding
(lib/match.x:83-92, 150-156); leftmost-split star semantics (`_star` in
match-recursive.x, `_lower_search_star` in match.x); !quote opacity and
definite/possible rules under !or/!set/!not; no instruction calls the
recursive matcher or Lisp evaluator (lib/machine.x:9-10); Match admission
memos (lib/match.x:2017-2079) are a measured negative control (see section 6).

Rebuild notes: keep compile-then-interpret; move match-recursive.x under
unittest/ as test-only; reconsider MatchCache generality (lib/match.x:2002-2260+)
in favor of a plan cache keyed by pattern pointer plus a small direct-mapped
table, unless eviction pressure is demonstrated; question whether Match and
Lisp need textually-shared machine.x versus two purpose-built VMs given
their disjoint register files (lib/machine.x:262-292; opcode enum 67-123;
fences 29-47). Lines 2260-2677 of match.x were not fully read.

### 2.10 Runtime infrastructure (lib/error.x, error-macros.xmacro, exception.x, scope.x, pool.x, logger.x, context.x, thread.x, mutex.x, dispatch.x, func.x, iter.x, lib.x)

Lines: error 1356, error-macros 41, exception 267, scope 1026, pool 965,
logger 859, context 370, thread 309, mutex 99, dispatch 932, func 443, iter
878, lib 93 (total 7,638).

Purpose: raise/catch, unwinding, Scope regions, Pool small-object allocation,
Context export across ownership domains, threads, mutex, logging, Var
descriptor dispatch, Func values, pull iterators.

Key types: Error / ErrorHandler / ErrorCatchSite; ExceptionFrame / X2CCleanup;
Scope / ScopeAlloc / ScopeStats; Pool / PoolBlock / PoolStats; Logger /
LogSink / LogEvent; Context; Thread; Mutex; VarDescriptor / VarMethods /
RenderPath; Func / FuncArg; Iter / UnzipShared.

Entry points: x2c_error_raise / _raise_n (lib/error.x:309, 333);
x2c_error_catch_push / catch_close (lib/error.x:216); x2c_exception_push /
leave (lib/exception.x:92); Scope allocation helpers (lib/scope.x:182);
Context.export / close (lib/context.x:308); Thread.start / join
(lib/thread.x:221); x2c_register_descriptor / Var.try_dispatch_binary
(lib/dispatch.x:107); Iter.filter/map/zip/zip_with/map2 (lib/iter.x:345).

Data flow: a raise appends to the innermost ErrorHandler's List (own Scope +
pools); exception.x unwinds to the catch running X2CCleanup records;
ErrorCatchSite/MatchPlan (compiled lazily under the recursive catch_site_mutex)
select arms via ordinary Match machinery (lib/error.x:53-56, 127, 146). Scope
owns doubly-linked allocation lists and a per-thread stack (lib/scope.x:98-110);
Pool layers size classes and a depot, lock-elided until Pool.thread_start
(lib/pool.x:143-190, 149-152). Context `_export_value` switches per Var kind
(lib/context.x:257-278) and falls back to try_export_context. Thread uses a
fixed 8MiB stack (lib/thread.x:73) and funnels errors through join
(lib/thread.x:123-141, 159-220, 277-303).

Must preserve: handlers see only errors since registration, innermost-first
(lib/error.x:5-7); per-handler independent Scope and pools (lib/error.x:9-14);
allocation-free error floor (lib/error.x:13-14); static-vs-transient catch site
rule (lib/error.x:64-69, 113-134); Pool.thread_start before pthread_create
(lib/pool.x:141-147); Context export defer rollback (lib/context.x:225-227,
244-247, 296-298); pull-based Iter (lib/iter.x:358-361).

Rebuild notes: collapse the three pthread_once recursive-mutex blocks
(lib/error.x:76-104, lib/logger.x:109-137, lib/dispatch.x:254-282) into one
primitive next to lib/mutex.x, recursive only where documented
(lib/error.x:74-75); scope.x:119-133 and pool.x:128-190 already show the
lighter PTHREAD_MUTEX_INITIALIZER form. Fold block/bytes/buffer export arms
(lib/context.x:271-284) and share the array/map rollback shape
(lib/context.x:230-256). Do not add abstraction layers; validation here is
already at documented failure points. lib/error-private.xmacro (imported at
lib/error.x:60) was not read.

### 2.11 Services (lib/file.x, path.x, process.x, json.x, scan.x, args.x, autodiff.xmacro, x2c.x)

Lines: file 591, path 544, process 578, json 570, scan 749, args 312,
autodiff.xmacro 1402, x2c.x 43 (generated prelude), plus lib/autodiff.x 164
(total 4,953).

Purpose: OS-facing I/O and processes; JSON and CLI-spec parsers over the
shared scanner; compile-time source-to-source autodiff; the generated prelude
aggregate.

Key types: File (FILE*), Path (class Path String), Job, JsonBool, _Spec /
_Option, AdTape / AdNode.

Entry points: File.open/read/copy; Path.join/dirname/glob/walk; List.job /
Job.run / Job.wait; Json.parse / Var.json; Args.parse / Args.usage;
`$ad.dual` (lib/autodiff.xmacro:33); `$ad.forward()` / `$ad.reverse()`
(meta decorators reading a typed double function's AST and emitting `_dot` /
`_grad` siblings via ~90 `meta static List ad_*` helpers starting at
lib/autodiff.xmacro:150; registries at 341-352).

Coupling: json.x calls scan_ascii_digit (lib/json.x:139,162,187); all raise
shared causes from error-macros.xmacro; path/process/json/args include x2c.x
directly (opt-in, not prelude members); autodiff.x is the runtime fallback.

Must preserve: stdio 1:1 semantics for File; Path removal of an absent path
succeeds (lib/path.x:6-8); Job runs once and is reaped when its Scope ends
(lib/process.x:9-10, 26-27); JSON last-key-wins and byte-ordered keys
(lib/json.x:9-10); `<bad-arg>` rather than exit (lib/args.x:9-10); autodiff
differentiates double arithmetic only (lib/autodiff.xmacro:18-19), nested
order as distinct C type (14-16); x2c.x is Makefile-generated.

Rebuild notes: the five thin wrappers are near minimal. Unify the forward
(ad_fwd_*, lib/autodiff.xmacro:466-630: ad_fwd_decl 466, ad_fwd_body 495,
ad_fwd_item 503, ad_forward 608) and reverse (ad_local/ad_push/ad_pop/
ad_triple 708/ad_exit 720, ~660-900+) walkers around one mode-parameterized
statement walker; lines past ~900 were not read.

### 2.12 External commands (commands/graph, commands/lint, commands/repl)

Lines: graph 5,958 (x2c-graph.x 3252, flows 944, lifetime 1011,
loop-allocations 339, clones 328, targets 84); lint 2,623 (x2c-lint.x 160,
tokens 417, declarations 341, structure 361, validation 452, comments 284,
idioms 154, lint.x 304, fix 66, format 84); repl 2,730 (main 43, repl 461,
repl-session 521, repl-input 1705); manifest.txt 3.

Purpose: consumers of the public CliRequest/Frontend/Compiler surface. graph
does call/flow/lifetime/loop-allocation/clone analyses; lint does style
checks with `--fix`; repl keeps one persistent isolated compile-time session
across submissions using comptime/parse/scope directly.

Entry points: graph main (commands/graph/x2c-graph.x:3168); lint main
(commands/lint/x2c-lint.x:125); repl main (commands/repl/main.x:9); repl_run
(commands/repl/repl.x).

Must preserve: CliRequest.command=<translate> as the external batch shape;
the Compiler surface graph depends on (diagnostics(), own_diagnostics(),
print_diagnostic(), display_path(), origin_location(),
emitted_binding_name(), semantic_binding_facts(), audit_regions(),
Compiler.has_region_row/region_result/region_wrapper); repl's incremental
session path.

Rebuild notes: keep two entry shapes (batch and incremental); route
CliRequest construction through cli_request() (commands/repl/main.x:31)
instead of hand-rolled calloc in commands/graph/x2c-graph.x:3168 and
commands/lint/x2c-lint.x:125; question lint `--fix` shelling out
(commands/lint/x2c-lint.x:132-156). Whether graph's helpers duplicate
src/regions.x is tracked in section 6 (C04-C06, C13).

# x2c subsystem map addendum: types, protocols, translation state

Read-only research for the rebuild spike. Every file:line citation below was
read directly in current `dev` during this pass (line counts are `wc -l`,
2026-09-26). Section 2.1-2.3 of `.context/rebuild/map.md` already covers
`compiler.x`'s shallow-parse dispatch loop and declaration freeze/thaw in
detail; this section cross-references those instead of repeating them, and
treats `lib/var-tags.xmacro` only at the point where `type-ledger.x` projects
it (the ledger itself is `.context/rebuild/map.md` section 2.8).

### 2.13 Types, protocols, and translation state (src/type.x, src/type-ledger.x, src/protocol.x, src/compiler.x)

#### Lines

type.x 987, type-ledger.x 42, protocol.x 2558, compiler.x 3905 (total 7,492).
`lib/var-tags.xmacro` (415 lines, mapped in section 2.8) supplies the two
tables `type-ledger.x` projects; no line count is double-counted here.

#### Purpose

`type.x` defines `Type` as canonical `List` syntax (declarator modifiers plus
a base) and gives it structural predicates, canonicalization, and the C
declarator round-trip (`Type` <-> `(declare ...)` AST). `type-ledger.x` is a
42-line adapter: the one compiler unit that imports the shared `Var` tag
ledger, so every other unit that only needs `Type` predicates avoids that
meta-time cost. `protocol.x` turns parsed protocol bodies and adoptions into
per-unit registries, resolves each participant's members against a protocol's
declared signatures, and generates the adapters, native aliases, and `Var`
descriptor thunks those resolutions require. `compiler.x` declares the
`Compiler` struct that every phase (tokenizer, parser, macro expander,
comptime lowerer, protocol resolver, transform, generator) shares, plus the
`Sym` symbol table, semantic transactions, and the freeze/thaw encoding that
lets a declaration be parsed once and replayed from cache or a `.xi`
interface. Together the four files are the compiler's one notion of "what a
name means here and now": `type.x` says what a type is, `protocol.x` says
which methods a type answers to, and `compiler.x` says where both are stored
per translation unit and how that state is checkpointed.

#### Key types

| Name | File | Role |
| --- | --- | --- |
| `Type` (`typedef List`) | type.x:17 | canonical semantic type: modifiers + base |
| `Compiler` (struct, ~110 fields) | compiler.x:71-184 | one translation unit's mutable state, shared via pointer |
| `Sym` | compiler.x:231-236 | scope stack + globals + statics + binding_facts, owns a back-pointer to `Compiler` |
| `SymScope` | compiler.x:56-58 | one lexical scope's three mutable maps (symbols, bindings, enumerators) plus local macros |
| `SymTxn` | compiler.x:2526-2536 | reversible snapshot of one semantic scope plus counters/statics/facts/layouts |
| `GenNames` | compiler.x:46-49 | unit-shared fresh-name counters and the live binding-number cursor |
| `ScriptUnit` | compiler.x:29-32 | shebang-script identity shared by collection and full parse |
| `protocol-record` (List) | protocol.x:387,2549 | `(base binder (associated ...) (members ...))`, one per declared protocol body |
| `adopt` (List) | protocol.x:148-155 | `(adopt base participant storage [representation|tag] location)` |
| `protocol-conformance` (List) | protocol.x:867-870,1075-1078 | resolved `(base participant forward reverse variables bindings (members rows))` |

#### Entry points

| Name | File:line | Called from | Role |
| --- | --- | --- | --- |
| `Type.canonicalize` / `Type.declared` | type.x:674,680 | expressions.x, protocol.x, comptime.x, transform.x | strip storage/qualifiers for identity vs. keep declared qualifiers |
| `Type.var_tag` / `Type.fixed_var_tag` | type.x:608,597 | expressions.x:156, comptime.x (6 sites), compiler.x:3746 | unit-local then process-lifetime `Var` tag lookup |
| `List.type_from_ast` | type.x:983 | protocol.x (member signatures), Sym.declare (compiler.x:3204) | AST declarator -> semantic `Type` |
| `Type.declaration_ast` / `.parameter_ast` | type.x:72,188 | protocol.x adapter generation, generate.x | semantic `Type` -> synthesized declarator AST |
| `Type.builtin_var_tags` / `Type.var_tag_rows` | type-ledger.x:39,42 | type.x:521,601,535 (forward-declared there) | process-lifetime ledger projections |
| `Compiler.publish_protocol_node` | protocol.x:513 | parse_protocol_declaration (protocol.x:2483,2487) | validates+installs one parsed protocol/adopt node |
| `Compiler.resolve_protocols` | protocol.x:1089 | Compiler.full_parse (compiler.x:2026) | resolves every visible adoption for the unit |
| `Compiler.protocol_members_for` | protocol.x:1318 | resolve_protocol_member, dump_conformance, macros.x, comptime.x | cached per-(base,participant) conformance row, resolves on first ask |
| `Compiler.resolve_protocol_member` | protocol.x:1723 | expressions.x (dot calls, punctuation), comptime.x | `(binding signature)` for one member name, or null |
| `Compiler.generate_protocol_adapters` | protocol.x:2295 | main.x:148, before `_transform_ast` | emits adapters/thunks/native aliases into the AST |
| `Compiler.rebuild_protocols` | protocol.x:261 | Compiler.full_parse (compiler.x:2016), `_install_import_protocols` (protocol.x:1310) | rebuilds protocols/adoptions/proto_cache from a symbol map |
| `Compiler.full_parse` | compiler.x:1999 | frontend.x/main.x per unit | drives the whole parse; resets and rebuilds protocol/type unit state |
| `Compiler.begin_semantic_transaction` / `SymTxn.commit` / `.rollback` | compiler.x:2545,2582,2639 | macros.x speculative expansion, comptime.x, parse.x recovery | reversible symbol/statics/facts/layout snapshot |
| `Sym.declare` / `Sym.bind_identity` | compiler.x:3187,3244 | parse.x, statements.x, macros.x | install a new vs. an already-identified binding's type |
| `Sym.resolve_key` / `Sym.next_typedef` | compiler.x:3572,3584 | expressions.x, transform.x, protocol.x indirectly | walk a typedef chain to its declared form |
| `Sym.var_tag_for_type` | compiler.x:3771 | expressions.x:4283 (non-Var -> Var boxing) | walks typedefs to the first type with a registered `Var` tag |

#### Data flow

Per unit, `Compiler.full_parse` (compiler.x:1999-2110) resets `sym`, protocol
maps, and meta caches to empty, then calls `rebuild_protocols(globs)`
(compiler.x:2016) to install every protocol/adopt row already visible in the
global symbol map (source-declared and replayed-from-cache alike), then
`resolve_protocols()` (compiler.x:2026) to resolve every visible adoption
before any body is parsed. The parse loop itself (parse.x/expressions.x/
statements.x, cross-referenced in map.md 2.1-2.2) reads `Type`s off `Sym` and
calls `Compiler.resolve_protocol_member` while resolving dot calls and
operators; a declared `Var T.var(T)` signature is captured as a side effect
of `Sym.define`/`Sym.declare` via `_seed_declared_var_tag`
(compiler.x:2880-2892, 2898), populating `type.x`'s per-unit
`declared_typetags` table with no separate protocol-adoption step. After
`unit.parse()` returns, `main.x:148` calls `generate_protocol_adapters`
once over the whole AST (adding early declarations/inits via
`Compiler.add_early`/`add_init`) before the fixed-point `transform` pass
begins; only then do lambda lowering, cleanup, and emission see the
generated adapters as ordinary AST nodes.

The `Compiler` struct's ~110 fields (compiler.x:71-184) group by owning
phase:

- **Session/unit identity** (frontend.x, shared with child compilers on
  `_new(owner)`, compiler.x:348-369): `filename`, `text`, `root_dir`,
  `package*` (5 fields), `include_dirs`, `names` (GenNames), `sources`,
  `source_map`, `unit_script`, `script`.
- **Token navigation** (parse.x/tokenizer.x): `token`, `input_boundary`,
  `tokenizer`, `directives_taken`, `braces`.
- **Preprocessor/collection** (collect.x, cross-ref map.md 2.1):
  `object_macros`, `arms`, `arm_stacks`, `layout_marks`, `packed_marks`,
  `kw_seen`, `open_linkage`, `layout`, `runtime_inc`, `runtime_hdrs`,
  `collect_protocols`, `shallow`, `source_private`.
- **Symbol/type state** (this section, compiler.x/type.x): `sym` (Sym),
  `aggregate_type`, `params`, `key_ids`, `fixed` (transform fixed-point map,
  owned by transform.x but stored here), `declaration_effects`.
- **Protocol registries** (this section, protocol.x): `protocols`,
  `conforms`, `protocol_helpers`, `proto_cache`, `adoptions`,
  `import_protocols`, `in_proto`.
- **Macro/comptime state** (map.md 2.3): `macros`, `kw_aliases`,
  `macro_stack`, `macro_holes`, `local_macro_captures`,
  `local_macro_capture_scopes`, `macro_count`, `imports`, `macro_lisp`,
  `import_src`, `borrowed_lisp`, `inherited_lisp`, `builtin_defs`,
  `meta_defs`, `meta_comptime`, `meta_regions`, `meta_values`,
  `meta_layouts`, `native_meta`, `meta_body`, `declaration_projection`,
  `declaration_produced`, `runtime_literals`.
- **Lambda/match/region** (map.md 2.4-2.5): `lambda_scopes`, `match_types`,
  `match_is`, `in_pattern`, `needs_exception`.
- **Generation/init** (generate.x/cache.x): `init_tokens`,
  `static_init_deps`, `fn_defs`, `id_keys`, `inits`, `init_fn`, `fini_fn`,
  `early_decls`, `prelude`, `inline_header`.
- **Diagnostics/origin** (diagnostics.x): `fn_name`, `diagnostics`,
  `import_stack`, `origins`, `origin`, `recovery_depth`.
- **Editor/source facts** (src/editor.x, sourceview.x): `source_facts`,
  `source_primary`, `source_occurrences`, `source_definitions`,
  `source_declarations`, `source_texts`.

`Sym` (compiler.x:231-236) is the actual mutable symbol table underneath
`compiler.sym`: a `Block` of `SymScope` plus `globals`/`statics`/
`binding_facts` maps. `SymTxn` (compiler.x:2526-2536, `begin/commit/
commit_transient/rollback` at 2545-2661) is the one reversible-write
primitive that macro expansion trial, comptime lowering, and protocol
adoption resolution during a speculative parse all build on; it snapshots
the active scope's three maps, `sym.statics`, `sym.binding_facts`,
`compiler.meta_layouts`, `names.counters`, `names.next_binding`,
`sym.local_macro_names`, `init_fn`/`fini_fn`, and (conditionally)
`source_definitions`/`source_occurrences` -- explicitly not parser position
or any other compiler field (doc comment, compiler.x:2538-2543).

#### Coupling

`protocol.x` includes `compiler.x` (protocol.x:11) and is itself included by
`compiler.x` (compiler.x:202), so the two are one mutual-recursion unit at
build time; `type.x` sits below both (compiler.x:17, protocol.x transitively).
`type-ledger.x` is the only unit that imports `lib/var-tags.xmacro`
(type-ledger.x:12; comment at type.x:519 and lib/var-tags.xmacro:9-13), so
`type.x`'s two forward-declared functions `Type.builtin_var_tags`/
`Type.var_tag_rows` (type.x:520-521) are defined only where `type-ledger.x`
is separately linked in; every other of the ~20 src/ units that `#include
"type.x"` (expressions.x, cleanup.x, diagnostics.x, transform.x, cache.x,
comptime.x, regions.x, parse.x, literals.x, lambda.x -- grepped list) pays
only `type.x`'s cost. `macros.x` and `comptime.x` call
`sym.resolve_key`/`field_order`/`protocol_members_for` (already noted in
map.md 2.3's coupling); `cleanup.x` calls `type.x`'s `ast_direct_identifier`/
`ast_indirect_identifier`/`ast_addressed_identifier` (type.x:78-150,
consumers at cleanup.x:434-550) to find the single name an error-transfer
`volatile` qualifier must reach. `main.x` is the only caller of
`generate_protocol_adapters` and `dump_conformance` (protocol.x:2295,1437;
main.x:145,148), making protocol-adapter generation a driver-level phase
boundary rather than something `compiler.x`'s own pipeline sequences.

#### Features implemented

Protocol declaration and bodyless adoption, `static`/`meta` adoption
modifiers, `as R` representation reuse and `tag <sym>` explicit `Var` tags
(docs/src/guide/protocols.md "Declaration and adoption"); associated types
with signature unification (protocol.x:588-650, doc "Associated types");
member resolution order (participant method, then nearest inherited
ancestor, then ordinary base default; doc "Member resolution", protocol.x:
901-993 `_resolve_members`); native protocols mapping members straight to C
functions with `_Generic`/`_Static_assert` checks (doc "Native protocols",
protocol.x:812-873, 1998-2008); operator/punctuation dispatch tables
(protocol.x:1378-1401, doc "Punctuation"); protocol-backed direct compound
updates (`Compiler.protocol_update_helper`, protocol.x:1740, doc
"Protocol-backed direct updates"); temporary-argument `discard` helpers
(protocol.x:1818-1890, doc "Punctuation" discard paragraph); `Var` descriptor
registration and boxed dispatch thunks (protocol.x:2051-2287); dynamic
numeric conversion's compile-time half (`Type.numeric_literal`,
`.numeric_literal_value`, type.x:411-497, doc "Dynamic numeric conversion");
scalar canonicalization and usual-arithmetic-conversion selection
(`Type.scalar`, `.promote`, `.widest`, type.x:292-335,787-831, doc "Types and
conversions"); named-type substitution rules for `Var` aliases and typedef
ancestry (doc "Types and conversions" paragraphs 3-4, `Sym.resolve_key`/
`local_type`, compiler.x:3572-3683); function prototype/definition contract
matching across conditional arms (`_function_completion_contract`,
compiler.x:3286-3408, doc "Host preprocessing" conditional-arm rules).

#### Interplay

**Meta/comptime**: `comptime.x` calls `Type.scalar_tag`/`is_enum`/
`fixed_var_tag` at 8+ sites to translate x2c numeric operations into Lisp
with C's exact width/sign rules, and reads `compiler.meta_layouts` (a
`Compiler` field, rolled back by `SymTxn`) as the compile-time struct-layout
cache. **Macros**: a macro's expansion runs inside a `SymTxn`-guarded trial
so a declined expansion (meta-only diagnosis, hygiene failure) leaves no
protocol or type-tag residue in the committed scope; `_declaration_macro`/
freeze/thaw (compiler.x:1218-1343, map.md 2.1) can retain a `(adopt ...)` or
`(protocol ...)` node as portable data across a cached declaration bundle.
**Lisp**: none of `type.x`/`protocol.x` calls into `lib/lisp.x` directly;
the crossing is one level up, through `comptime.x`'s Lisp lowering, which is
where `Type` facts become `C.*` runtime calls. **The machine**: no
interplay -- the wordcode machine (map.md 2.4) serves match and Lisp AUTO,
neither of which types are involved. **C**: native protocol adoption emits
literal `#define`/`_Generic` aliases (protocol.x:1998-2008); ordinary
adapters and `Var` thunks are synthesized function ASTs
(`_generate_protocol_function`, protocol.x:1927-1971) that the ordinary
emitter (map.md's `Compiler.emit`) lowers like any other function, so no
special-cased C ever bypasses `generate.x`/`emit.x`. **Var/List**: `Type`
*is* `List` (type.x:17); the `Var(T)` protocol is the compile-time mirror of
the runtime `Var` tag/descriptor system from `lib/var-tags.xmacro`
(map.md 2.8) and `lib/var.x`'s `VarMethods` descriptor struct -- a
participant's adopted member becomes a `VarMethods` field
(`_generate_descriptor_registration`, protocol.x:2051-2120) only when
`compiler.sym.lookup_field(%(struct "VarMethods"), member)` says the runtime
struct has that slot, so the boxed-dispatch surface is bounded by a single
runtime declaration, not duplicated in the compiler.

#### Parallel implementations

| est lines | what | file:line evidence |
| --- | --- | --- |
| ~35 | four separate hop-budgeted typedef-chain walkers, each re-deriving "canonicalize, check typedef, fetch target via `_typedef_target`/`sym.get`, replace base, recurse, error past budget" | `_resolve_key_helper` compiler.x:3557-3569; `Sym.next_typedef` compiler.x:3584-3591; `_normalize_declared_type` compiler.x:3724-3737; `_var_tag_for_type_helper` compiler.x:3743-3764 |
| ~20 | `Sym.declare` and `Sym.bind_identity` duplicate their typedef-binding-facts block (`ntype`/`emitted` local-typedef naming) and their automatic-local binding-facts block almost verbatim | compiler.x:3213-3229 vs 3250-3258; compiler.x:3230-3239 vs 3260-3263 |
| ~10 | three public accessors (`Type.scalar_tag`, `.var_numeric_extractor`, `.var_numeric_update_helper`) each independently recompute `_scalar_row` (itself `type.scalar()` + a map lookup) for the same `type`, so a caller wanting two facts about one type pays the lookup twice (seen back-to-back at expressions.x:4224-4226) | type.x:356-378; caller expressions.x:4222-4227 |
| ~15 | the freeze/thaw declaration-syntax encoding (compiler.x:1274-1343, already flagged in map.md 2.1 against collect.x's `.xi` encoding) also independently re-encodes the same `(adopt ...)`/`(protocol ...)` List shapes that `protocol.x` already treats as canonical data; no protocol-specific case exists in freeze/thaw, but every adoption/record shape must survive its generic List-and-token walk unchanged | protocol.x:148-155,387-395,2549-2553 (shapes) vs compiler.x:1286-1306 (generic walk) |

None of these looks like dead machinery; each is a plausible single-helper
consolidation, not a deletion candidate.

#### Suspect abstractions

| name | location | claimed purpose | consumers | why suspect | est lines |
| --- | --- | --- | --- | --- | --- |
| `declared_typetags` unit-local static map | type.x:526,547-556 | let a source `T_var` converter register a `Var` tag without a process-wide table entry | `Type.register_var_tag/_adoption`, `Type.var_converter/var_tag` (type.x:564-615) | lives outside `Compiler`/`Sym` entirely as a file-static, so it is invisible to `SymTxn` snapshot/rollback (compiler.x:2526-2661 does not mention it) even though `meta_layouts`, a peer per-unit cache, is explicitly rolled back; not confirmed to cause an observable bug (see Open questions) | ~30 |
| `_adoption_row`/path-keyed static adoptions | protocol.x:177-220,292-320,464-504 | let a `static protocol` adoption stay invisible outside its declaring file even inside one multi-file collected unit | `_install_protocol_adoption`, `_publish_protocol_adoption`, `resolve_protocols` | every call site branches on `storage == <static>` to pick a 2- or 3-element map key, and `_adoption_visibility`/`_visible_adoption_row` (188-211) then re-derive which of up to two stored rows (external, local) is the effective one; workable but the two-key map plus separate visibility resolver is more moving parts than a single row carrying its own visibility, and I did not find a case needing more than the external/local pair | ~90 across the cited spans |

Both are borderline: they implement a specific documented rule (translation-
unit-local adoption privacy; unit-scoped `Var` tags) rather than solving a
problem nobody asked for, so I would confirm the rule is still wanted before
touching either in a rebuild, not delete them outright.

#### Must preserve

- Member resolution order -- participant method, then nearest inherited
  ancestor, then ordinary base default, `Var(T)` normally exact except
  `as R` -- docs/src/guide/protocols.md "Member resolution" and "`Var(T)`
  normally remains exact" paragraph; implemented protocol.x:936-945,
  273-278; pinned by `unittest/compiler-fixtures/relative-adoption*`,
  `tag-scope-a/b.x` probes.
- A generated method cannot have both local and external linkage, and two
  ordinary defaults for one member is a hard error naming both protocols --
  docs/src/guide/protocols.md lines 153-156, 371-378; implemented
  `_generated_owner`/`_report_generated_collision` protocol.x:1563-1652;
  pinned by the `*protocol-conflict*` and `macro-protocol-*` fixtures under
  `unittest/compiler-fixtures/`.
- `resolve_protocol_member` returns null for the member's own implementation
  (guarded by `compiler.fn_name`, protocol.x:1723-1732) so a generated call
  never dispatches back into the body currently being compiled; this is the
  documented "the member's own body keeps the native operation" contract in
  the same doc comment.
- The forward converter is a total view; a default returning `T` needs the
  reverse conversion; compound parameter/result types are rejected --
  docs/src/guide/protocols.md "Conversions are demanded by adapters";
  implemented `_conversion_requirement`/`_ordinary_requirement`/
  `_descriptor_requirement` protocol.x:995-1049; pinned by
  `macro-protocol-representation-non-var.x`, `converter-count.x` probes.
- Semantic transactions snapshot exactly the fields listed in their own doc
  comment (compiler.x:2538-2543) and nothing else; macro-expansion trial and
  comptime speculative lowering rely on rollback leaving parser position
  and untouched compiler fields alone.
- `TagId` order matches the ledger's row order -- enforced by
  `$var.tag.id.checks()`'s `_Static_assert` (lib/var-tags.xmacro:355-370,
  emitted where lib/var.x uses it); `type-ledger.x`'s `varrows`/`typetags`
  must stay derived from the same `_tag_rows()` the runtime decoder uses
  (type-ledger.x:16-42) -- pinned by the `retired-var-tag-*` fixtures.
- `unittest/test-protocols.x` pins base-default reach-through (`Block`
  members reached via `Array`'s and `Bytes`'s storage-view converters) and
  boxed-dispatch through a registered custom-tag descriptor
  (`ArrayInt`/`<arrayint>`); both would silently regress if base-default
  resolution or descriptor registration changed shape.

#### Rebuild notes

**Representation**: keep `Type` as canonical `List` syntax -- it is already
the same representation as AST, macro templates, and Lisp data (map.md
section 1), so a rebuild gains nothing by inventing a distinct type
descriptor struct, and would lose the free structural `match` support
`type.x` and `protocol.x` both lean on throughout (e.g. protocol.x's dozens
of `match (row) case %(...)` member-row destructurings). Consolidate the
four typedef-walkers (Parallel implementations, row 1) into one
`_walk_typedef(sym, type, stop, origin, hops, on_hit)` continuation-style
helper; `resolve_key`, `next_typedef`, `normalize_declared_type`, and
`var_tag_for_type` each become a thin wrapper supplying their own stop
predicate/hit callback. Fold `Sym.declare`/`Sym.bind_identity`'s duplicated
binding-facts blocks into one `_install_local_typedef_facts`/
`_install_automatic_binding_facts` pair (Parallel implementations, row 2).

**Protocol resolution as data**: the member-resolution decision table in
docs/src/guide/protocols.md ("Member resolution") is already exactly what
`_resolve_members` computes row by row (protocol.x:901-993); a rebuild could
make that table's five outcomes (`implemented`/`native`/`base-default`/
`no-member`/`sig-conflict`) an explicit ranked list of match clauses over
`(participant-has-member, ancestor-has-member, base-has-default)` rather
than the current sequential `if`/`foreach`-with-`break` construction, which
would read closer to the doc it implements. Native alias generation is
already close to table-driven (`_native_requirement`, protocol.x:772-810,
is one function of position/content checks); ordinary-adapter generation
(`_generate_protocol_function`, protocol.x:1927-1971) is more naturally
templated because it builds an AST from a signature triple
(target/source/template) -- a rebuild could express it as one `match_replace`
template parameterized by direction (forward/reverse/thunk) instead of the
current three call sites (`_generate_ordinary_protocol_adapters`,
`_generate_protocol_thunk`, `install_generated_protocol_symbols`) that each
assemble the same three-way substitution by hand. Conversion requirement
checking (`_conversion_requirement`, `_descriptor_requirement`,
`_ordinary_requirement`, protocol.x:995-1049) is small enough that
table-driving it would add a table-interpretation layer for little gain;
leave it as direct code.

**compiler.x, state vs. logic**: of 3905 lines, the struct declaration and
pure lifecycle/plumbing (constructor at compiler.x:325-399, borrow/take/
close helpers 246-322, add_early/add_init 2459-2469, freeze/thaw 1274-1343,
semantic transactions 2545-2661) total roughly 350-400 lines -- under 10%.
The remainder is algorithmic: the `Sym` symbol-table implementation
(scopes, typedef resolution, binding identity, field order, package
spelling -- roughly compiler.x:2470-3905, ~1400 lines) is a real, non-trivial
piece of the type system that happens to live in the file named for shared
state rather than in `type.x`. A rebuild should either (a) keep `compiler.x`
as "the shared struct plus its own scope/lookup implementation" as now, or
(b) split `Sym` (and its ~50 methods) into its own unit and let `compiler.x`
hold only the struct, lifecycle, transactions, and the parse-loop dispatch
that map.md 2.1 already describes. Given how much of `type.x`/`protocol.x`
calls `Sym.resolve_key`/`local_type`/`var_tag_for_type` directly, (b) mostly
just renames a file; it would not shrink total lines, but it would make "is
this state or logic" answerable by filename rather than by reading 3905
lines.

**Ledger indirection**: `type-ledger.x`'s 42-line existence purely to keep
one meta-time import (`lib/var-tags.xmacro`) out of every other unit
(type-ledger.x:5-8) is a real and working cost-isolation pattern, not
overhead to remove; a rebuild should keep a single ledger source with
exactly this "one importer, two forward-declared consumer functions" shape.

#### Open questions

- Does a rolled-back `SymTxn` (e.g. a declined macro expansion or a comptime
  lowering that raises) ever leave a stray row in `type.x`'s
  `declared_typetags`, since that map is not part of the transaction
  snapshot (compiler.x:2526-2536) even though `Type.register_var_tag`/
  `register_var_adoption` (type.x:564-584) can be reached from code that
  runs under a transaction? I did not find or construct a reproduction; the
  asymmetry with `meta_layouts` (which *is* snapshotted) is the only
  evidence, and it may be intentional because `declared_typetags` rows are
  idempotent ("the first row for a canonical Type wins", type.x:561) so a
  stray extra row would harmlessly lose a race rather than corrupt state.
- Is the `(base participant path)` vs `(base participant)` two-shaped
  adoption key (protocol.x:177-220) still needed for every caller, or would
  a single row that carries its own `(storage, path)` pair and lets
  `_adoption_visibility` scan a short list (rarely more than 2: one static,
  one external) simplify every call site that currently branches on
  `storage == <static>` to build the key? Not verified against a case with
  more than two rows for one `(base, participant)` pair.
- `install_generated_protocol_symbols` (protocol.x:1117-1147) and
  `generate_protocol_adapters` (protocol.x:2295-2343) both iterate
  `c.conforms` and re-derive "is this native, is this base-default, is it
  externally visible"; whether they could share one classification pass was
  not checked against why the driver calls them at different times
  (`full_parse` for the symbols, `main.x` for the AST-mutating generation).

---

## 3. Parallel implementations and suspect abstractions

Sorted by estimated lines descending. "est" is the reader's estimate of
lines implicated, not a guaranteed saving.

| est | kind | what | evidence |
|---|---|---|---|
| 8719 | representational | comptime lowering emits cons/quote chains instead of quasiquote for `%(...)` templates; 684 -> 8719 lines (12.7x) | etc/builtin-macros.x:65-66 vs etc/builtin-macros.xlisp:206-215; etc/init-core.xlisp:41-42 uses backtick |
| 1281 | suspect | regions.x escape analysis as a whole: ~1300-line abstract interpreter whose only hard-error consumer is the meta path | src/regions.x entire; check_regions 1212, check_meta_regions 1237, audit_regions 1263 |
| 2700 | parallel (open) | graph tool re-implements call-target recognition, location formatting, lifetime/escape analysis owned by src/regions.x | tools/x2c-graph/lifetime.x:34-66,118-128,169-182,268-273; targets.x:29-63; x2c-graph.x:190-199; src/regions.x:83-116 (C04-C06); loop-allocations.x:190-216 calling lifetime.x:797-859 (C13, 63 lines) |
| 450 | parallel (deliberate) | recursive reference matcher duplicates the compiled Match engine, kept as oracle in production tree | lib/match.x:1027-2677, lib/match-machine.x:1-541, lib/match-recursive.x:1-446; headers lib/match.x:14-27, match-recursive.x:1-9 |
| 390 | suspect | `_resolve_content`: one ~30-case match mixing macro/meta, literals, interpolation, cons/append, slice, destructuring, sizeof, ternary | src/expressions.x:2041-2434 |
| 310 | suspect | `convert_expression`: six conversion families behind sequential early returns; ternary branch recurses | src/expressions.x:4053-4366; 4088-4100 vs 2371-2372 |
| 260 | suspect | MatchCache LRU + generation counters + admission/refusal memo tables (note: admission memos measured load-bearing, section 6) | lib/match.x:2002-2260+ |
| 245 | suspect | header/source partitioning and typedef-forward ordering exist only for C's two-file model | src/generate.x:357-602 |
| 235 | suspect | hand-rolled printf conversion-spec scanner in a lowering pass | src/transform.x:52-287 (used at 317) |
| 220 | suspect | shared macro-library lifecycle flags and `<lisp-late>` restart-by-exception | src/macros.x:1000-1281; 1229-1281; race window 1244-1281 |
| 200 | suspect | lisp.native.target.rows three-way merge of hand rows around generated list | lib/lisp.x:1607-1808 (generated list at 1803) |
| 150 | suspect | AUTO speculative macro pre-expansion guard/rewind | lib/lisp.x:1855-1905, 2110-2112, 2186, 2836-2944; lib/lisp-machine.x:378-385 |
| 150-250 | parallel | five adapter synthesis paths, six cache-key namespaces, same compute-key/check/build/queue/store shape | src/lambda.x:153-251 (tadapt), 429-504 (fadapt), 573-639 (findirect), 641-720 (fhandle/fgetter), 780-812 (fpointer-factory); keys at 236, 496, 577, 645, 703, 786 |
| 140 | parallel | two hand-ordered top-level dispatch loops (shallow vs full) over the same construct kinds | src/compiler.x:1669-1744 vs src/parse.x:1953-2032 |
| ~120 | parallel | two independent x2c-shaped-logic-to-Lisp lowerings (comptime text vs AUTO wordcode) | etc/builtin-macros.x:8-14; lib/lisp.x:2332, 2600, 2703; src/comptime.x |
| 90 | suspect | native-meta target inventory machinery with ad hoc exceptions and no confirmed external consumer | src/macros.x:478-568 |
| 87 | parallel | three line-for-line recursive pthread_once mutex blocks (only error.x documents reentrancy) | lib/error.x:76-104, lib/logger.x:109-137, lib/dispatch.x:254-282; lighter form at lib/scope.x:119-133, lib/pool.x:128-190 |
| 60 | suspect | per-field manual manifest setters | src/project.x:219-275 |
| 60 | suspect | combined Match+Lisp MachineOp enum and shared capacity fences | lib/machine.x:67-123, 29-47; separate layouts 262-292 |
| 60 | parallel | two independent incremental-rebuild fingerprint systems | src/build.x:75-181 vs etc/x2c.mk:62-82 |
| 58 | suspect | recursive-mutex boilerplate copied without documented need | lib/logger.x:109-137; lib/dispatch.x:254-282 |
| 50 | parallel | JSON Lines and text diagnostic renderers extract the same fields separately | src/diagnostics.x:212-284; 236-246 vs 274-283 |
| 50 | parallel | freeze/thaw declaration syntax vs `.xi` `_write_datum`/`_interface_load`: two canonical-Lisp serializations | src/compiler.x:1270-1343; src/collect.x:979-1036 |
| ~50 | parallel | two worklist walkers over region facts | src/regions.x:815-890 (_scan), 1093-1143 (_walk) |
| 40 | suspect | CliOption table plus parallel `_apply_option` switch plus cli_package_options switch | src/cli.x:104-266, 894-984, 1013 |
| 40 | suspect | Context `_export_*` per-kind switch; block/bytes/buffer identical, array/map same rollback shape | lib/context.x:194-278; 271-284; 230-256 |
| ~40 | parallel | car/cdr family defined three times | lib/lisp.x:378-381; etc/init.x:83-105; etc/comptime.xlisp:126-130, 226-393 |
| ~40 | parallel | three structured-text readers (manifest, index rows, JSON markers) | src/project.x:308-416; src/install.x:113-120; src/install.x:157-164 |
| ~30 | parallel | cons-cell construction with Var boxing and cache_cons_cell twice | src/literals.x:75-97; src/expressions.x:2109-2129 |
| 27 | suspect (open ledger) | `_lower_content` duplicates `_lower_expr` productions | src/comptime.x:1500-1506 (region 1380-1510); vs 1370-1375; plans/overengineering-candidates.md |
| 25 | suspect | `_translation_chunks` slicing heuristic with a second policy at 383 | src/main.x:325-347, 383 |
| ~25 | parallel | forward vs reverse autodiff statement walkers | lib/autodiff.xmacro:466-630 vs ~660-900+; registries 341-352 |
| 20 | parallel | duplicated emit/write collector headers | etc/builtin-macros.x:1-25 vs etc/init.x:1-25 |
| 20 | suspect | `_attribute_since` manual binary search over parity-encoded intervals | src/parse.x:517-533 |
| 20 | parallel | two identity-hash helpers | src/utils.x:287-294; src/build.x:99-119 |
| 15 | suspect | ad_forward_siblings / ad_reverse_siblings dual registries | lib/autodiff.xmacro:341-352, ad_register 345, ad_call_tangent 356 |
| ~15 | parallel | three near-identical postfix member parsers | src/expressions.x:636, 654, 620 |
| 11 | parallel (declined C12) | compiler-side typed Match guard sugar re-derives lib/match.x facts | src/compiler.x:2012-2022; lib/match.x:332-344, 686-690, 1342-1351 |
| 10 | parallel | hand-rolled CliRequest in graph and lint vs cli_request() | commands/graph/x2c-graph.x:3168; commands/lint/x2c-lint.x:125; commands/repl/main.x:31 |
| 10 | parallel | X2CVarNumericInfo / X2CVarNumeric repeat five fields | lib/varconvert.x:19-21, 28-31 |
| ~10 | parallel | number lexing in json.x vs scan.x | lib/scan.x:1-60; lib/json.x:139, 162 |
| 4 | parallel | `_symbol_expression` and `_adapter_symbol_literal` verbatim | src/transform.x:39-40; src/lambda.x:295-296 |
| n/a | parallel (deliberate) | cache.x compile-time dedup vs emit.x runtime once-init | src/cache.x:1-14; src/emit.x:301-421 |
| n/a | parallel (deliberate) | diagnostics.x vs lib/logger.x | agents/logger-and-diagnostics-guide.md:1-15; src/diagnostics.x:60-99 |
| n/a | parallel | three independent backtracking matchers (List match, Lisp machine, regex) | lib/regex.x:20-532; lib/machine.x LispMachine |
| n/a | parallel | lint `--fix` shells out to x2c translate while holding an in-process Frontend | commands/lint/x2c-lint.x:132-156 |
| n/a | parallel (resolved) | builtin tag rows listed in compiler and ledger (C01, fixed by 02fa85d6) | src/type.x:528-557 (pre-fix); lib/var-tags.xmacro:70-131 |
| n/a | parallel (resolved) | Lisp signature serialization vs literal cache (C02) | etc/lisp-bindings.xlisp:6-21 (removed); src/compiler.x:1905-1941 |
| n/a | parallel (resolved) | pattern-graph recovery up to four times per arm (C11, 8fd9c740) | src/compiler.x:1956-2049; src/emit.x:717-783 |

---

## 4. Feature inventory (checklist -> implementing modules)

Sourced from docs/src/internals/implementation-map.md ("Feature ownership"),
docs/src/reference/language.md (3418 lines), docs/src/library/overview.md, the
51 module pages under docs/src/library/modules/, and the 24 guide chapters.
Nothing here may drop from a rebuild without explicit justification.

Language surface:

- [ ] C foundation, expression-bodied functions: src/parse.x, src/generate.x
- [ ] scalar declarations, literals, arithmetic: src/parse.x, src/literals.x, src/expressions.x, src/type.x, src/transform.x, lib/var.x, lib/scope.x
- [ ] collection and string literals (percent literals, quote, unquote): src/literals.x, src/transform.x, src/cache.x, lib/list.x, lib/array.x, lib/map.x, lib/string.x
- [ ] string interpolation ($name, ${expr}): src/literals.x, src/expressions.x, src/transform.x, lib/string.x, lib/var.x
- [ ] symbol and atom literals: lib/tokenizer.x, lib/scan.x, src/literals.x, src/emit.x, lib/symbol.x, lib/atom.x
- [ ] indexing and slicing: src/expressions.x, src/type.x, src/transform.x, lib/common.x
- [ ] method-style calls: src/expressions.x, src/type.x, src/transform.x
- [ ] postfix chains, unary, sizeof, offsetof, _Generic, va_arg, casts, designated initializers, compound literals: src/expressions.x
- [ ] generic selection: src/expressions.x
- [ ] mixed declaration rows: src/parse.x
- [ ] C initializers and static assertions: src/parse.x, src/emit.x
- [ ] exact Var-tag tests (is / is not): src/expressions.x, src/type.x, src/transform.x, src/emit.x, lib/var.x, lib/common.x
- [ ] membership with in: src/expressions.x, lib/dispatch.x
- [ ] list destructuring (flat): src/parse.x, src/statements.x, src/type.x, src/transform.x, lib/list.x
- [ ] Var boxing, conversion, operators, dispatch: src/type.x, src/compiler.x, src/statements.x, src/expressions.x, src/transform.x, src/emit.x, src/literals.x, lib/common.x, lib/var.x, lib/scope.x, lib/varconvert.x, lib/varops.x, lib/dispatch.x
- [ ] dynamic numeric conversion: lib/varconvert.x
- [ ] dynamic truthiness and binary operators: lib/varops.x, lib/dispatch.x
- [ ] protocol-backed direct updates / dynamic compound assignment: lib/varops.x, src/protocol.x
- [ ] lambdas (expression and block bodies, typed/bare params): src/literals.x, src/lambda.x, src/transform.x, src/expressions.x, lib/func.x
- [ ] typed callback adapters: src/lambda.x, lib/func.x
- [ ] control flow: if/while/for/do/switch/goto/labels: src/statements.x
- [ ] foreach and iterator destination omission: src/macros.x, etc/builtin-macros.xmacro, etc/builtin-macros.xlisp, src/transform.x, src/emit.x, lib/iter.x
- [ ] with statement (scoped resource acquisition): src/statements.x, src/transform.x
- [ ] match statement / pattern matching / typed capture patterns: src/statements.x, src/literals.x, src/transform.x, src/emit.x, lib/match.x, lib/match-machine.x, lib/machine.x, lib/list.x
- [ ] raise, filtered catch, finally, defer: src/statements.x, src/transform.x, src/cleanup.x, src/emit.x, lib/exception.x, lib/error.x
- [ ] reference parameters: src/type.x, src/transform.x
- [ ] delegate fields: src/type.x, src/generate.x
- [ ] protocols (declaration, adoption, conversions, member resolution, punctuation): src/protocol.x
- [ ] checked foreign aliases: src/type.x, src/macros.x
- [ ] type-owned initialization: src/parse.x, src/generate.x, src/cache.x
- [ ] type-owned shutdown: src/statements.x, src/generate.x, src/transform.x
- [ ] managed-initializer syntax: src/macros.x, src/generate.x
- [ ] named types, declaration production, class declarations: src/macros.x, lib/meta.x
- [ ] compile-time macros and decorators (local definitions, holes/sequences, result kinds, hygiene, keyword aliasing): src/macros.x, src/comptime.x, lib/meta.x, etc/compiler-sdk.xlisp
- [ ] meta functions (compile-time introspection, dual-form, constant folding): src/comptime.x, lib/meta.x
- [ ] inline Lisp bindings ($lisp.bind/$lisp.binding/$lisp.install): src/macros.x, etc/lisp-bindings.xmacro, etc/lisp-bindings.xlisp, lib/lisp.x, lib/func.x
- [ ] compile-time Lisp import ($(import ...)), native module loading: src/macros.x
- [ ] system macros ($scope, $let, $lock, $auto, $class, $switch, $dedent, $todo, $unreachable, $time, $assert): etc/builtin-macros.xmacro, lib/system-macros.xmacro
- [ ] package imports and with-names, `name__` prefixing: src/parse.x, src/compiler.x, src/collect.x, src/project.x, src/build.x, src/toolchain.x
- [ ] source files, pragmas (private/public), script units (#!): src/frontend.x, src/script.x, src/parse.x
- [ ] indentation syntax (#pragma indent): lib/tokenizer.x
- [ ] host preprocessing (C preprocessor boundary, --cpp-symbols/--live-symbols/--dump-cpp): src/utils.x, src/frontend.x
- [ ] region model and lifetime warnings, optional lifetime proof: src/regions.x (guide/memory.md, guide/regions.md, guide/verification.md)
- [ ] structured diagnostics (text and JSON Lines): src/diagnostics.x, src/report.x
- [ ] two-pass compilation, `.xi` interface cache, dependency files: src/collect.x, src/deps.x
- [ ] editor source overlays and one-shot semantic queries: src/sourceview.x, src/editor.x
- [ ] stable x2c_* native C entry points: src/utils.x and lib/*.x

Runtime library (one line per module page):

- [ ] args parsing against declarative spec: lib/args.x
- [ ] dynamic contiguous arrays; counted construction (Array.update_n/push): lib/array.x, src/emit.x
- [ ] canonical exact names (Atom): lib/atom.x
- [ ] reverse-mode autodiff on runtime tape: lib/autodiff.x; forward/reverse source-to-source: lib/autodiff.xmacro
- [ ] checked dynamic storage (Block): lib/block.x
- [ ] growable text buffer (Buffer): lib/buffer.x
- [ ] shared Var union and core operations: lib/common.x
- [ ] Context boundaries and value export: lib/context.x
- [ ] line differences (diff): lib/diff.x
- [ ] SHA-256 digests: lib/digest.x
- [ ] typed descriptors for runtime Var behavior: lib/dispatch.x
- [ ] handler stack and accumulated errors: lib/error.x
- [ ] transfer frames for unwinding/cleanup: lib/exception.x
- [ ] File I/O: lib/file.x
- [ ] Func generic native binding: lib/func.x
- [ ] single-pass pull iterators: lib/iter.x
- [ ] JSON encode/decode: lib/json.x
- [ ] disjoint sets: lib/lib.x
- [ ] Lisp runtime (reader, session, evaluator, AUTO): lib/lisp.x, lib/lisp-machine.x
- [ ] compound List selectors: lib/list-selectors.x
- [ ] linked List with Var elements: lib/list.x
- [ ] Logger: lib/logger.x
- [ ] wordcode machine: lib/machine.x
- [ ] Map (status-bearing get/del, void sentinel, cursor invalidation): lib/map.x, src/emit.x, lib/dispatch.x
- [ ] reference matcher: lib/match-recursive.x
- [ ] pattern matching/transformation over lists: lib/match.x, lib/match-machine.x
- [ ] compiler surface for meta functions: lib/meta.x
- [ ] Mutex: lib/mutex.x
- [ ] Path: lib/path.x
- [ ] Pool: lib/pool.x
- [ ] Process (commands/pipelines without a shell): lib/process.x
- [ ] Regex over String bytes: lib/regex.x
- [ ] Scope: lib/scope.x
- [ ] script-unit modules: lib/scripting.x
- [ ] Split cursors: lib/split.x
- [ ] byte classification: lib/string-classify.x
- [ ] numeric parsing: lib/string-number.x
- [ ] String: lib/string.x
- [ ] Symbol, SymbolSet: lib/symbol.x, lib/symbolset.x
- [ ] Thread (Context-backed workers): lib/thread.x, lib/thread-state.x
- [ ] typed Array / List / Map instantiations: lib/typed-array.x, lib/typed-list.x, lib/typed-map.x, lib/array-generics.xmacro, lib/list-generics.xmacro, lib/map-generics.xmacro
- [ ] Var, tags, adapters, unbox: lib/var.x, lib/var-tags.xmacro, lib/var-adapters.xmacro, lib/var-ledger.x, lib/var-unbox.xmacro
- [ ] Var numeric conversion policy: lib/varconvert.x
- [ ] boxed Var operators, updates, truthiness: lib/varops.x, lib/varops.xmacro
- [ ] static-init ordering, clibc, cmath, native scalar types, integer ops: lib/static-init.x, lib/clibc.x, lib/cmath.x, lib/native-scalar-types.xmacro, lib/integer-ops.xmacro

Tooling and packaging:

- [ ] CLI parsing, response files, help: src/cli.x
- [ ] x2c.toml manifests, targets, profiles, dependency graph, `x2c new`: src/project.x
- [ ] content-addressed incremental native build, atomic publish: src/build.x, src/toolchain.x, src/utils.x
- [ ] parallel translation worker pool: src/main.x, src/utils.x
- [ ] package install/remove/list, pinning, movable native bundles: src/install.x, src/project.x, src/build.x, src/toolchain.x
- [ ] bootstrap from embedded APE payload: src/bootstrap.x, etc/x2c-payload.x
- [ ] build-once script execution: src/script.x
- [ ] terminal progress and receipts: src/report.x
- [ ] REPL (session, inspection, editing, completion): commands/repl
- [ ] graph analyses and `x2c-graph certify`: commands/graph
- [ ] lint with --fix: commands/lint
- [ ] torch package (tensors, autograd, TorchScript, devices): packages/torch (outside make check)

---

## 5. Acceptance harness summary

Correctness gates (agent-pr-check for code; doc-check for docs; the only two
in tools/gate-state.py GATES):

- Unit suites: 60 unittest/test-*.x files, 25,403 lines, 58 suites registered
  by `$test.suite` in unittest/test-all.x (130 lines); a test fails on a
  failed assertion, zero assertions, or leaked scope state (unittest/AGENTS.md).
- Compiler fixtures: 11 directories, 3,888 files with `.phases` sidecars;
  `make verify-fixtures` never rewrites, `verify-fixtures-update` does;
  generated C must compile warning-free unless `cc-stderr` is declared.
  Fixture kinds pin macro embedding/import, meta-capture, header-packed
  attributes, keyword aliasing.
- Probes: 45 files under unittest/probes (27 top-level shell probes: CLI
  boundary, native modules, package install, full sanitizer, suite coverage,
  scope shutdown).
- Executable examples: examples/manifest.txt, 64 entries (58 showcase diffed
  against expected/*.stdout, 4 external-input build-only, 1 optional).
- Self-host convergence: stage-diff-all / stage-3 / proof-cold-collection
  compare generated C/H byte-for-byte across stages 0-3. `make precommit` =
  bootstrap refresh + safe stage-0 rebuild + stage 2 + stage compares
  (Makefile:188); `make agent-pr-check` = precommit + proof-cold-collection +
  extended checks (Makefile:196); `make verify` at 130, `examples` at 140,
  `check` at 170, `doc-check` at 298.
- Lisp differential checker: `x2c script examples/programs/check-reference-lisp
  --build` against the reference recursive interpreter.
- tools/gate-state.py (396 lines, FORMAT=6) hashes the git-visible tree plus
  tool/config identity into debug/gate-state.json and reuses green results
  for an unchanged tree.

Performance (advisory, never gating): unittest/benchmarks (64 files) via
`make performance-snapshot` / `bm-all` / `bm-build-scaling`; the build-cost
score (median CPU cycles per source line against
unittest/benchmarks/build-scaling-baseline.json) is explicitly designed to
separate "compiler got slower" from "more/less code", which is the right
instrument for the "keep performance close" requirement.

For a rebuild: the suites, fixtures, examples, stage comparison, and Lisp
differential checker are the re-runnable definition of "same observable
behavior"; gate-state.py carries over unchanged. unittest/STATUS.md (221
lines, known skips) was not read.

---

## 6. Decisions already made or declined (with source)

Measured declines (do not re-propose without new measurement,
plans/README.md):

- M3 declined: lowering meta functions from the transformed tree; the
  transform erases lambdas into static Funcs and interpolation into C text
  (plans/archive/meta-functions.md). `_lower_coerce`'s three type-pair
  conversions (Array<->List, Symbol->String) stay a closed list.
- M4 declined ("Do not build this"): serializing word-compiled Lisp
  (MachineWord) across sessions saves 0.7% of translation (6.8ms of 970ms)
  and constants hold live process addresses (21.4% of a 106-function corpus)
  (plans/archive/meta-functions.md). Ship lowered Lisp forms if a portable
  artifact is ever needed.
- M5 shipped: constant-argument folding with exact substitutable-type rules
  (plans/archive/meta-functions.md).
- Cache node shape stays `(cache ?id)` with an accessor; `(cache id key)`
  measured ~10% permanent translation cost and touches 8+ match sites
  (plans/archive/x2c-lowers-to-lisp.md).
- `case`/pattern literals not made fully structural (runtime_literals=1):
  ~5% permanent cost over 8,000,000 matches
  (plans/archive/x2c-lowers-to-lisp.md).
- Var tag row lookup stays in Lisp: a full x2c port of lib/var-tags.xmacro
  measured 3.4x slower translating lib/ (10.48s vs 3.07s); only ledger
  projections were ported (plans/archive/comptime-x2c-generalization.md;
  consolidation-catalog C01, commit 02fa85d6).
- Match admission memos (lib/match.x:2017-2079, ~4KiB) kept: A/B removal
  made literal matches 2.35x slower, star misses 1.63x, guards 1.61x, cache
  hits 1.41x, nested 1.29x over 21 paired processes
  (plans/overengineering-candidates.md calibration case).
- C10 declined: primitive String display keeps its second tag-to-format
  switch (would add an allocation and change NULL handling)
  (plans/consolidation-catalog-f28fc36.md).
- C08 partially shipped, per-binding localinit follow-up declined as not a
  net deletion (plans/consolidation-catalog-f28fc36.md).
- C12 declined 2026-09-24: shared typed Match guard interpretation touches
  the hot path with an open design (plans/consolidation-catalog-f28fc36.md).
- C13 open: loop-allocation runs the full escape analysis for return facts;
  no shared-owner design (plans/consolidation-catalog-f28fc36.md).
- $table and $show macros rejected: real tables hold Symbols, enum constants,
  bitwise expressions, address-of, delimiter strings
  (plans/macro-sdk-and-system-macros.md Phase 4).
- SDK naming: strict `x2c.<noun>.<verb>` public surface; shipped-macro
  helpers (foreach.*, class.*, scope.*) leave the x2c. namespace
  (plans/macro-sdk-and-system-macros.md).
- `x2c-graph certify` must never broaden `proved` by giving unmodeled
  operations trusted rows; prefer honest `incomplete`
  (plans/lifetime-proof-followup.md).
- Delivered consolidations: C01 (02fa85d6), C02 (2026-09-24), C05, C06, C11
  (8fd9c740) (plans/consolidation-catalog-f28fc36.md).

Standing repository contracts relevant to a rebuild (AGENTS.md,
docs/src/reference/language.md line 1863, docs/src/internals/implementation-map.md):

- Compile-time Lisp may construct any canonical AST List; no origin tracking
  or second validator.
- Every shared Error cause in lib/error-macros.xmacro transfers or terminates;
  never returns to the raising call.
- One numeric conversion implementation for all 15 numeric tags; long/llong/
  ldouble name native families.
- Sentinel (void) contract: equality/identity/is-void/rendering inspect void;
  hashing, ordering, truthiness, iteration, conversion, arithmetic, updates
  keep `<void-op>`.
- Map cursor invalidation on structural mutation; counted Array construction
  accepts raw Null, rejects void.
- Rebinding car/cdr/cons in Lisp does not change generated helpers; native
  operations register after libraries load so builtin-macro wrappers defer
  lookup to expansion.
- Region invariant and documented exemptions (docs/src/guide/regions.md lines
  3, 20, 66).
- Process ceiling: no added gates or precommit cost without removing
  comparable cost (AGENTS.md).

---

## 7. Open questions

Front end:
- Have the shallow and full dispatchers drifted (skip_linkage_brace and
  script-statement handling appear only in the shallow loop)?
- Is `_attribute_since`'s binary search (src/parse.x:517-533) warranted by
  layout_marks/packed_marks sizes?
- Can freeze/thaw (src/compiler.x:1270-1343) and `.xi` serialization
  (src/collect.x:979-1036) share one primitive?
- Can `_require_retained` calls in collect.x actually fail under current
  invariants?

Syntax:
- Is the cons/append boxing duplication (literals.x vs expressions.x)
  intentional given different cache_cons_cell invariants?
- Is convert_expression's family ordering load-bearing? Needs generated-C
  verification before any split.

Macros / Lisp:
- Is the `<lisp-late>` restart path (src/macros.x:1229-1281) ever taken under
  current driver sequencing?
- Does any native module in packages/ exercise src/macros.x:478-568?
- Can src/comptime.x target quasiquote cleanly, and how far does that ripple?
- What is the measured cost/benefit of `_expansion_*` speculative expansion?
- comptime.x lines ~1300-3436 and match.x lines 2260-2677 were not fully read.

Transforms:
- How often does regions.x's warning-only analysis catch real bugs?
- Is Compiler.audit_regions (src/regions.x:1263) referenced by a shipped
  tool, or is audit-only Walk state dead weight on every compile?
- Could the six adapter-cache key namespaces collide if unified? Check
  against unittest/compiler-fixtures.
- Should printf lowering delegate to a shared format-spec walker (none exists)?

Backend:
- Is src/cli.x the only caller of diagnostics_write_json, and is renderer
  consolidation format-safe?
- Are `_aggregate_typedef_forwards` / `_resolve_typedef_markers`
  (src/generate.x:491-565) covered by fixtures?
- Could `_local_static` (src/emit.x:318-421) and cache.x share a primitive, or
  does thread safety force separation?

Driver:
- Is the CliOption/_apply_option split deliberate? Ask Gary before unifying.
- Are both incremental systems (build.x and etc/x2c.mk) load-bearing?
- Root Makefile (542) was enumerated by target only; no tests for build.x
  fingerprinting were examined.

Values / infra / services:
- Do Buffer/Block/String share real growth-and-bounds duplication with
  array-generics.xmacro? string.x (1771) only skimmed.
- Do logger.x and dispatch.x mutexes need PTHREAD_MUTEX_RECURSIVE?
- Can Context's Array/Map rollback share a helper without hurting the raw
  array fast path?
- lib/error-private.xmacro not read.
- Can ad_forward_siblings/ad_reverse_siblings merge into one Map-backed
  registry? Reverse-mode helpers past ~line 900 not read.

Match:
- Does MatchCache see eviction pressure (MATCH_CACHE_PRESSURE) in real src/
  or lib/ workloads?
- How much of machine.x's generality (MACHINE_LOCAL_MAX, MACHINE_CALL_RESERVE,
  LispFrame) is Match-only vs Lisp-only?

Features / docs:
- Verification (docs/src/guide/verification.md) has no dedicated module; it
  appears to live in src/regions.x but was not traced function-by-function.
- docs/src/guide/overview.md, advanced-topics.md, index.md do not exist; the
  library/ versions were used.
- packages/torch implementing files were not enumerated.

History / commands:
- Do the open ledger items (_lower_content) and declined items (C10, C12,
  C13) still hold against current dev? Reconfirm against live source.
- x2c.diagnostic.fail/.warn location mapping and x2c.type.members consumers
  remain unbuilt (plans/macro-sdk-and-system-macros.md).
- Does graph's ~2700 lines of helpers recompute what src/regions.x already
  computes? Cross-check with C04-C06, C13.
- Why does lint `--fix` shell out instead of reusing the in-process compiler?
- commands/lint has no README.md; commands/README.md does not exist.

---

## Coverage critique

Checked every hand-authored `.x`/`.xmacro`/`.xlisp` file under src/, lib/,
and etc/ (excluding generated lib/x2c.x and etc/builtin-macros.xlisp)
against this map's text. Method: `wc -l` per file, then grepped this map
for each filename.

### (a) Files the map does not mention

- `lib/protocols.x` (85 lines) -- not mentioned anywhere. Declares the
  built-in `Cleanup`/`Block`/`Iter`/`Var`-boxing protocol contracts for
  runtime types (Block storage views, Iter traversal). This is exactly the
  kind of file section 2.10 (runtime infrastructure) or the protocol
  discussion should own; it is currently invisible to the inventory.
- `lib/error_init.x` (27 lines) -- not mentioned anywhere. Its header
  states it is deliberately kept outside error.x "so the compiler does not
  insert initialization into `Error.ready` or the emitter-facing raise
  entry point" -- a load-bearing initialization-ordering fact that section
  2.10's "must preserve" list omits.
- `src/protocol.x` (2,558 lines) -- referenced three times only as a
  cross-reference target ("src/protocol.x" appears at map.md:130, 288, 408,
  810, 820) but has no subsystem section of its own anywhere in section 2,
  and its line count is folded into no per-subsystem total. It is the
  6th-largest file in src/ (larger than src/collect.x, src/build.x,
  src/cli.x, src/literals.x, src/generate.x, src/regions.x), yet the map's
  12 subsystem write-ups (2.1-2.12) never account for it as a subsystem in
  its own right, so its size, key types, and rebuild notes are missing from
  the map even though "protocols (declaration, adoption, conversions,
  member resolution, punctuation)" is listed as a feature it alone owns
  (map.md:820).

All other hand-authored files under src/, lib/, and etc/ (including small
ones such as lib/mutex.x, lib/lib.x, lib/thread-state.x, etc/lisp-io.xlisp,
src/ast-rewrite.xmacro) are mentioned by name somewhere in the map.

### (b) Documented features the map's inventory lacks

Comparing docs/src/reference/language.md's 60 section/subsection headings
against the "Language surface" checklist in section 4: every heading has a
corresponding bullet except that the checklist does not separately call out
`Var`, Null, and `void` as a foundational literal/type triple (language.md
line 2378, "### `Var`, Null, and `void`"). The map's closest bullets --
"Var boxing, conversion, operators, dispatch" (map.md:807) and the
sentinel-contract note in section 6 (map.md:1010-1012) -- cover its
consequences but never cite the section that introduces Null and void as
values in their own right, so a rebuild checklist item for "Null/void as
first-class Var values" is missing from section 4's language-surface list.

No gap was found in the module-catalog coverage: all 47 module pages under
docs/src/library/modules/ (48 files minus index.md) correspond to a
runtime-library bullet in section 4, and all 24 guide chapters are
implicitly covered by the feature bullets they document.

### (c) Claims refuted by reading the cited source

1. **map.md:788** claims "51 module pages under docs/src/library/modules/".
   `ls docs/src/library/modules | wc -l` gives 48 files, one of which
   (`index.md`) is a table of contents, not a module page -- so the correct
   count is 47 module pages (48 files total).
2. **map.md:914** claims "Compiler fixtures: 11 directories". `find
   unittest/compiler-fixtures -mindepth 1 -maxdepth 1 -type d | wc -l`
   gives 10 (macro-import-sub, packages, include-trailing-comment,
   unit-static-call, class-adoptions-included, meta-header-packed,
   meta-capture-definition, keyword-alias-included,
   header-aggregate-attributes, macro-embed-text-definition). The
   accompanying "3,888 files" figure in the same line is correct.
3. **map.md:919** claims "Probes: 45 files under unittest/probes (27
   top-level shell probes: ...)". The 27 top-level-file count is correct
   (`find unittest/probes -maxdepth 1 -type f | wc -l` = 27), but the total
   file count is not 45: `find unittest/probes -type f | wc -l` gives 70
   (including the `protocol/`, `fixtures/`, `packages/`, and
   `expression-bodied-functions/` subdirectories' fixture data), or 63 if
   the `fixtures/` and `packages/` subdirectories are excluded. No
   plausible subset of unittest/probes files totals 45.
4. **map.md:14** claims "lib/ (.x + .xmacro) | 35,878 | 60 files". A direct
   `find lib -maxdepth 1 -type f \( -name '*.x' -o -name '*.xmacro' \) !
   -name x2c.x | wc -l` gives 72 hand-authored files (including
   lib/protocols.x and lib/error_init.x from (a)), not 60 -- a 12-file
   undercount. The paired line total is close but also off: `wc -l` over
   those 72 files gives 35,835, not 35,878 (43 lines high). Whatever
   selection produced 60 files, it dropped at least 12 real files while
   landing within 0.1% of the correct line total, which means the two
   numbers in that table cell were not computed from the same file list.

All other spot-checked citations were accurate: the section-1 data-flow
function/line citations (parse_macro_definition src/macros.x:3153,
Compiler.lower_comptime src/comptime.x:2912, Compiler.transform
src/transform.x:1776, Compiler.check_regions src/regions.x:1212,
Compiler.emit src/emit.x:1449, generate_code src/generate.x:1228,
Compiler.code_pretty_string src/format.x:90) each land on the named
declaration; the Makefile target line numbers (130, 140, 170, 188, 196,
298) match current `Makefile`; `tools/gate-state.py` is 396 lines;
`unittest/test-all.x` is 130 lines with 58 `$test.suite` registrations;
`docs/src/reference/language.md` is exactly 3,418 lines; and the src/
hand-authored total (41,951 lines across 36 files) matches current `wc -l`
on dev as of 2026-09-26. The lib/ total does not match; see (c)4 above.
