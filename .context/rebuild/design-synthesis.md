# Design synthesis: one architecture (key: synthesis)

Research spike, 2026-09-26. Advice to Gary; nothing here is a decision.
Read-only: nothing under src/, lib/, etc/, docs/, plans/ was edited. Every
`file:line` below was read in current `dev` during this pass unless it says
"(map)" or names a plan record. Line counts are `wc -l`.

Starting point. The judges' totals rank consolidate first (116), then lisp
(108), passes (106), language (105), kernel (100). Consolidate's own
closing argument is that a same-pipeline pass reaches 1.5-3.4% and "only an
engine deletion reaches ~10%", and the judge who ranked it first grafted
language's L2 (native meta execution) as the only route past that ceiling.
So this synthesis starts from consolidate's verified base and refutations,
adds the one engine deletion that lisp, kernel and language share, and
takes passes' walk consolidation, which is independent of the engine.
Where designs disagreed on a fact the source was read; section 9 carries
every judge doubt that could not be closed.

## 1. Thesis

The tree is features, not duplication: reading consolidate's candidates in
source shrinks most of them, and the same-pipeline ceiling is about 2,700
lines. The one deletable engine is the second backend that lets x2c run
inside the compiler without being compiled by it: src/comptime.x lowers a
`meta` body to Lisp (117 function heads in 70-3089, 112 of them lowering;
C1), etc/comptime.xlisp re-implements C semantics for it, the AUTO tier of
lib/lisp.x (2310-2957) plus lib/lisp-machine.x word-compile the result to
win back speed, and tools/gen-lisp-init.py turns the built-in macro
algorithms into a 12.7x generated artifact loaded by every process. Every
speedup that justified those tiers was measured on lowered x2c (the 3.4x
machine figure, plans/archive/x2c-lowers-to-lisp.md:739-744), which native
execution removes; the one decline that kept a ledger in Lisp (3.07 s vs
10.48 s on lib/) was evaluator execution of a 104-row scan at 13 ms per
scan (plans/archive/comptime-x2c-generalization.md:495-531), microseconds
when compiled. So a `meta` body is compiled by the one C backend, linked
into the compiler when it ships with it and built once into a content-
addressed module when a user defines it; comptime.x, comptime.xlisp,
lisp-machine.x, the Lisp half of machine.x, the AUTO and speculation
tiers, the generated .xlisp files and their generator go; Lisp shrinks to
the glue evaluator that `$(...)`, templates and `$lisp.bind` need. On top
of that, consolidate's counted removals and passes' local fixed point.
Honest total: 80,404 to about 73,100 hand-authored lines (-9.1%), 445 of
them relocated rather than deleted; ceiling with every gated candidate
about 72,400 (-9.9%). No reading found a compiler pass that shrinks by
moving behind the macro boundary; section 12 says why.

## 2. Architecture

Representation is unchanged: `Ast` is `List` (src/ast.x), `Type` is `List`
(src/type.x:17), Lisp data, match patterns and runtime containers are
`List` over NaN-boxed `Var` (map section 1). Components in pass order:

| component | owns | kind |
|---|---|---|
| lib/tokenizer.x | bytes -> Token array, modes, `#pragma indent` | runtime, as today |
| collect + parse (src/collect.x, parse.x, statements.x, expressions.x, literals.x) | untyped then typed canonical AST; one top-level classifier with skip-body/parse-body continuations (consolidate C) | kernel |
| src/macros.x | macro definitions, invocation claiming at every MacroPos, hygiene (2499-2576), `$(...)` slots, the x2c_* SDK bodies (147-961), native module loading (1645-1750), meta-call evaluation (2173-2225) | kernel |
| src/stage.x (new, ~500, replaces comptime.x) | reachability of compiler operations, constant-argument resolution and result lifting (today comptime.x:3130-3310), group extraction, emit through the backend, `Build.module_entry`, load, bind, per-unit reset, REPL submissions | kernel |
| src/builtins.x (new, from etc/builtin-macros.x, init.x, lisp-bindings.x) and src/linked-meta.x (new, ~40) | the foreach/scope/class expanders, `$lisp.bind` builders and `lisp.native.targets` registered under derived Lisp names; the imported bodies of lib/var-tags, autodiff, system-macros, varops, var-unbox, native-scalar-types .xmacro, lib/protocols.x and lib/meta.x's builders, emitted with a table of content hashes | meta, compiled into the compiler |
| lib/lisp.x (reader, evaluator, natives, session API) | `$(...)`, `.xlisp` imports, `defun`/`defmacro`, per-call-site macro memo; no wordcode | runtime, redesigned |
| src/type.x, type-ledger.x, protocol.x, compiler.x | `Type`, `Sym`, `SymTxn`, protocols; one typedef walker (O), one adapter template (X1) | kernel |
| src/lower.x = transform.x + lambda.x + cleanup.x; src/regions.x | one local post-order fixed point per node with the cleanup region stack as walk state, volatile qualification a per-function post-step; region warnings with `check_meta_regions` kept (section 3) | kernel |
| src/cache.x, generate.x, emit.x, format.x, diagnostics.x | constants (ids recorded as emit prints them), .h/.c partition before lowering, C tokens, `#line`, diagnostics | kernel |
| src/build.x, toolchain.x, main.x, cli.x, project.x, ... | fingerprints, workers, publication, plus the staged-module cache in the script cache's shape (src/script.x:70-110) | driver, as today |

Pass order per unit: tokenize; collect; full parse with macro expansion,
where `$name(...)` binds to a native `Func` (linked or staged) and its
result is lifted by the retained `_meta_data` rules; protocol adapters;
regions; partition; lower (one walk); emit; format.

Kernel versus macro/meta. Every typed lowering reads facts only the
compiler has: interpolation boxes segments by type (src/transform.x:
1055-1100), destructuring reads element types (408-550), `match` declares
typed capture locals with compiler-issued identity (src/statements.x:
246-425), defer/try wire cleanup regions and `volatile` rules (src/cleanup.x:
242-624), lambda lifting needs capture analysis over binding identity
(src/lambda.x:1309-1340), Var operators resolve protocol members
(src/transform.x:587-940). The dispatcher (src/transform.x:1707-1766) is
already a switch of one-line delegations to match-and-template helpers, so
moving them behind a `meta` marker relocates lines. Kernel's rule driver
was read and declined: its output would have to be rebound through
`_resolve_content`, whose only typed pass-through is `case %(!set ?inner
(expr ? ?))` (src/expressions.x:2048-2049), with no case for `vcompound`,
`vpostfix`, `vseqcall` or `dstrvalue` (src/emit.x:1311-1325). The boundary
stays where the map draws it: binding, types, layout, lifetimes and
emission order are kernel; the system macros, callback adapters, foreign
aliases, autodiff, the tag ledger projections and the generics families
are macros or meta functions, now compiled instead of interpreted. `with`
stays a parse-time binding (src/statements.x:571-600 records the
expression, not a temporary; 45 lines); language's local-macro relocation
would add a bare-invocation kind to delete them and is declined.

## 3. Compile-time execution model

**One meaning for `meta`.** A bodied `meta` function is ordinary x2c
compiled by the C backend, dual-form as documented (language.md:
1683-1692): the program links its own copy; the compiler runs a linked or
staged copy. `meta native` becomes a redundant spelling and stays accepted.
The compile-time-only inference stays: a body that reaches a bodyless
compiler operation, an explicit `$` call or a template constructor has no
runtime form (language.md:1785-1793; today src/parse.x:2018 via
`meta_is_comptime_only`, src/comptime.x:3077-3083), decided by a callee
scan over the typed body (~60 lines). The parser installs every bodied
`meta` function as a native-meta row (today only `meta native` and
bodyless prototypes are rows: src/parse.x:1993, 2010; `_native_meta_rows`,
src/macros.x:484-506) with the FNV hash of its definition's source span
(`_definition_source`, src/parse.x:2022-2023).

**Linked or staged.** Binding is by name with the documented precedence
(meta-functions.md:508-511): the compiler's linked inventory, then modules
named by option or manifest, then imported packages. New: a linked row
binds only when its recorded hash equals the imported definition's; a
mismatch (an edited `.xmacro`) stages the file's group on demand. Staging
emits the group as one unit through the ordinary backend, writes the entry
with `_write_entry` (src/build.x:450-466, exporting the rows of
`_x2c.native-meta.declared`, src/macros.x:556-568; bodied meta rows now
qualify), compiles it, caches it under the script cache root keyed by
content hash plus `build_module_stamp()` (src/utils.x:358), and loads it
with `Compiler.load_native_module` (src/macros.x:1723-1735). A unit's own
meta bodies stage at the first `$name(...)` that needs them, batching every
definition parsed so far (the documented source order, meta-functions.md:
42-66). Modules resolve runtime symbols from the compiler binary, which
links its whole archive with `-rdynamic` or `-force_load`
(builds/stage.mk:47-57).

**`meta static`.** Documented as "separate per-translation-unit values
built from the same source initializers" (meta-functions.md:246-247). A
module's C statics are per process, modules load `RTLD_LOCAL` and are never
unloaded (src/macros.x:1699-1710), and a worker translates a slice of units
(src/main.x:230-245; `_translation_chunks` at 335-347 gives one slice per
worker, `slices == total` only for `x2c build`). So every module entry
exports a generated `x2c_module_reset()` that re-runs the group's `meta
static` initializers in a per-unit meta `Scope` opened at unit start and
destroyed at unit close (the role `C._meta_globals` plays today,
src/macros.x:1047-1051). Language's claim 11 and lisp's claim 13 ("fork
per unit") are wrong as stated; the reset is required.

**Calls, results, errors.** `$name(args)` resolves constant arguments and
lifts the result with the retained rules (comptime.x:3130-3310
`_meta_value_type`, `_meta_immutable`, `_meta_refuse_address`,
`_meta_data`, plus the layout helpers at 3330-3435 a struct result needs).
The call runs inside a kernel-owned `$scope()`; the lifted syntax is built
before the scope pops, as `_meta_data` does today. A raise inside a
compiled body transfers through the compiler's own runtime (a module "uses
the compiler's own runtime, not a copy", meta-functions.md:516-517) to the
existing `catch %(?code *detail)` in `_evaluate_meta_value` (src/macros.x:
2202-2203), which reports it at the call site. The two `call-stack` arms
there (2194-2201: step budget, depth) no longer fire for native bodies; a
runaway meta body hangs the compiler as a runaway `meta native` body does
today. Listed as a drop in section 4.

**Regions.** `check_meta_regions` stays. Its only behavioral difference
from the warning walk is `case %(alloc final) if (w.meta): return w.frame`
(src/regions.x:498) plus error-not-warning at 1249-1255, and its
justification, "a compile-time call frees its locals when it returns"
(19-21), is exactly the call-scope discipline above: a body returning the
address of a call-scope allocation hands the compiler a dangling pointer,
corrupted state, not a performative check. Kernel claim 9 and language R5
are refuted here (judge 3's reading holds); only `lowered_meta_regions`,
the lowering-cache replay at 1239-1243, goes.

**`$(...)` Lisp, `$lisp.bind`, imports, hygiene.** Unchanged in surface.
The evaluator is lib/lisp.x's reader (549-830), evaluator (1832-2303) and
session API (3064-3190), plus one 25-line per-call-site memo of `defmacro`
expansions (`_apply_lambda` re-expands on every call, lib/lisp.x:2166-2174;
measured 505 ms -> 186 ms, x2c-lowers-to-lisp.md:755-783). Natives bind
through the target table; the hand rows at lib/lisp.x:1607-1808 shrink
where a `meta native` spelling on the definition lets
`_x2c.native-meta.targets` generate the row (the lifetime certifier,
src/macros.x:1911-1943, rejects only unowned handle-in/handle-out shapes).
`$lisp.bind`, `$lisp.binding`, `$lisp.install` keep etc/lisp-bindings.
xmacro; their algorithms (etc/lisp-bindings.x) compile into src/builtins.x,
so `$(import "../etc/lisp-bindings.xlisp")` at lib/lisp.x:1606,
src/macros.x:1063 and src/build.x:462 goes. `$(import "x.xmacro")` parses
definitions as today and binds the file's meta group linked-or-staged.
Hygiene is definition-time renaming (src/macros.x:2499-2576) and `using`
binders, unchanged; no origin validator is added (language.md:1863).

**Shared session.** Today the parent is filled from five files (~9,900
Lisp lines, src/macros.x:1054-1060) plus a parse of lib/meta.x to lower its
builders (src/frontend.x:288-320), deferred for sequential translations and
recovered by the `<lisp-late>` restart (src/main.x:170-181, 371-379;
src/macros.x:1229-1281). With ~650 lines to evaluate, the parent is built
eagerly in `Frontend.open`, frozen, and adopted per unit (lib/lisp.x:
783-799); the lifecycle flags and restart (src/macros.x:1000-1281) collapse
to a constructor (consolidate J). `def` on an inherited name still raises.

**Built-in expanders.** etc/builtin-macros.x's algorithms are already
ordinary functions, not `meta` (`List builtin_scope_expand(...)`,
etc/builtin-macros.x:29), decorated by `$builtin.emit()` whose body calls
`x2c_comptime_lower` (line 9); they reference x2c_* 86 times, and a runtime
call to a bodyless x2c_* prototype is not diagnosed (`check_meta_call`,
src/comptime.x:3311-3320, reports only names in `meta_comptime`, populated
at comptime.x:2969, frontend.x:307 and macros.x:2064, never by
`_bind_native_meta`, src/macros.x:1945-1988). So src/builtins.x is those
functions spelled `meta native`, compiled by any stage-0 compiler and
registered through `$(lisp.native.targets (_x2c.native-meta.declared
'("src/builtins.x")))`, the mechanism of `$compiler.targets()` (src/macros.x:
1064-1066) minus its `x2c_` filter, under `_meta_lisp_name` names
(1077-1083). The six alias rows of etc/builtin-core.xlisp:27-33 become
template renames in etc/builtin-macros.xmacro.

**Runtime Lisp.** `Lisp.new` evaluates the embedded etc/init.xlisp
(lib/lisp.x:85-86, 383, 752-756). etc/init.x's algorithms (etc/init.x:
28-166) become lib/lisp-init.x, `meta native` functions in the runtime
archive, and etc/init-core.xlisp gains ~25 `(def init_not (bind "init_not"
nil))` rows beside the aliases it already carries (etc/init.xlisp:225-229,
`(def not init_not)` and friends). Embedding programs keep the same
vocabulary; the differential checker gains init-core plus lisp-values as
standing inputs, since every session evaluates them.

**REPL.** commands/repl/repl-session.x:490-507 lowers a submission with
`Compiler.lower_repl`, evaluates the forms in `c.macro_lisp`, and deletes
`C._globals` cells on failure; repl.x:140 and 368-371 read AUTO stats and
set the call budget. Under this design each submission is staged as a
module linked with `DT_NEEDED` on the modules of the submissions it
references: an earlier definition resolves by ordinary dynamic linking, a
redefinition is a new symbol in a new module that later submissions link
against (`-Bsymbolic` keeps a module's own definitions first), and
persistent values live in the module that declared them. `:lowered` shows
C; `:stats` loses the AUTO fields; no call budget; latency rises from
~1 ms to 100-300 ms. A consumer change that constraint 4 reserves to Gary:
the CLI surface survives, the implementation does not.

**Editor.** src/editor.x:182-185 answers one query per process; a unit's
meta group is keyed by the hash of its emitted C, so keystrokes outside
meta bodies hit the cache and an edit inside one pays ~150 ms.

**Platform.** Native modules are compiled out under `__COSMOPOLITAN__`,
`_WIN32` and `__CYGWIN__` (src/macros.x:1712-1716; meta-functions.md:532).
The APE seed compiles bootstrap C and delegates every translation to the
installed native compiler (src/bootstrap.x:221-244; etc/cosmopolitan/
verify-ape.sh never translates with the seed), and Windows is documented as
WSL2 (docs/src/guide/installation.md:98-100). Shipped meta bodies are
linked, so every documented build path keeps working; a user-defined bodied
meta function on a host without `dlopen` is the one regression, a drop in
section 4.

Survivors, merges, replacements:

| module | disposition |
|---|---|
| src/comptime.x (3,436) | replaced by src/stage.x (~500): retained lifting, folding and layouts ~300, reachability ~60, staging and reset ~110, REPL ~30 |
| etc/comptime.xlisp (399), builtin-core (34), the generated .xlisp files, tools/gen-lisp-init.py | deleted |
| lib/lisp.x (3,190) | ~2,000: AUTO 2310-2957 (-650; `Lisp.call_budget` 2919 and `_open_call_budget` 3051 stay), machine bridge 107-300 (-195), speculation 1857-1910 (-55), the AUTO typedefs (-50), comptime-only natives 1110-1270 (-160), hand target rows partly generated (-100), memo (+25) |
| lib/lisp-machine.x (480) | deleted; lib/machine.x (540) becomes Match-only ~400 (`LispFrame` 216-226, `LispMachine` 282-, `MACHINE_CALL_RESERVE`, `MACHINE_LOCAL_*`, `MW_L*` go); lib/match-machine.x and lib/match.x unchanged (Match is 9.7-12.5% of translate samples), MatchCache eviction narrowed (N) |
| lib/match-recursive.x (445) | relocated under unittest/ as the oracle (consumers: test-support.x:5,58-78, test-match-plan.x:805, match-capture-benchmark.x:4) |
| etc/init-core.xlisp (176), etc/lisp-values.xlisp (465) | kept; init-core gains 25 bind rows; of lisp-values' 289 bound C names 157 are `meta` declarations and 132 are not, plus 25 adapting defuns, so deriving the 157 is an optional -150 |
| examples/programs/literate-lisp.x | the kernel's differential oracle, unchanged in role |

## 4. Feature coverage

Every row of map section 4 plus the `Var`/Null/`void` triple (coverage
critique b). "Kernel" needs binding, types, layout, lifetimes or emission
order.

Language surface, kernel as today: every row from "C foundation" through
"stable x2c_* entry points" that the next groups do not name, plus `Var`,
Null and `void` as values. Consolidation rows attach without changing
behavior: lambdas and typed callback adapters (one adapter memo, E);
protocols (one adapter template X1, one adoption row X2); region model and
lifetime proof (analyzer unchanged, G); structured diagnostics (one field
pass, Q); two-pass compilation and `.xi` (one datum writer, D); generic
selection, mixed rows, designated initializers and `with` stay as they are.

Language surface, macro/meta, now compiled: foreach and iterator
destination omission; the system macros; class declarations; callback-
adapter and foreign-alias decorators; `$lisp.bind` and friends; autodiff
source-to-source; the tag ledger projections; the generics families.
Kernel redesigned: compile-time macros and decorators keep src/macros.x
with the legacy body forms retired (L1); meta functions (introspection,
dual form, constant folding) move from lowering to linked-or-staged native
execution; `$(...)`, `$(import ...)` and native modules use one loader.

Runtime library: every module page row is "runtime as today" except: Lisp
runtime, redesigned (AUTO dropped, memo added, init algorithms bound as
natives); wordcode machine, Match-only; reference matcher, relocated to
unittest/ (its page leaves the book); Mutex gains the one shared recursive
primitive (B; all three users stay recursive: lib/var.x:372-375 ->
lib/dispatch.x:302-306; `Logger.free` -> `clear_sinks`, lib/logger.x:
662-666); pattern matching keeps the admission memos (measured, map section
6) and narrows the MatchCache eviction structure (N); Context folds its
Block-view export arms (P); varconvert embeds X2CVarNumericInfo (V);
lib/meta.x loses `x2c_comptime_lower`.

Tooling and packaging: CLI (I), manifests (T), incremental build, worker
pool, install, bootstrap payload, script execution, reporting, graph, lint,
torch: as today. REPL: implementation changes (section 3).

Drops, each justified, with the lines it saves:

- The compile-time subset and its rejection table (meta-functions.md:
  948-963; language.md:1717-1723): unions, `goto`, static arrays, `try`/
  `raise`, `File.open` in a meta body now compile; the 18 `comptime-
  declines-*` fixtures change to acceptances; no program that compiles
  today changes meaning. This lapse is what the engine deletion is worth:
  ~5,300 lines.
- `x2c_comptime_lower` (language.md:1767-1770; lib/meta.x:315;
  src/macros.x:956): its only callers are the three generators
  (etc/init.x:9, etc/lisp-bindings.x:11, etc/builtin-macros.x:9). ~30 lines
  plus the 53-line tool.
- The AUTO tier and its API (`Lisp.auto_prepare`, `auto_disable`,
  `auto_instrument`, `auto_stats`, `Lisp.program`; docs/src/library/
  modules/lisp.md:44, 357-360, 542-550, 671), test-lisp-auto.x (995 lines)
  and its benchmark: the contract is transparency, the gate guarantees
  prepared/evaluator <= 0.90 (run-lisp-auto-benchmark.sh:7-9), the 3.4x
  was measured on lowered x2c. ~1,500 lines. Gated on U2.
- The Lisp call budget for meta bodies (repl.md:184-185 wording): a native
  body is not preemptible, as `meta native` bodies are not today. 0 lines.
- User-defined bodied meta functions on hosts without native modules; every
  documented build path is unaffected. 0 lines; the price of one model.
- The reference matcher's module page (the code moves): 445 lines leave lib/.

## 5. Line ledger

Base: the map's subsystem totals with lib/machine.x counted in 2.9 and the
1,792 unmapped lib files as "other", summing to 80,404 (consolidate's
on-disk 80,370 differs by the map's 43-line lib/ overcount). References:
the native-module path (src/macros.x:1645-1750, src/build.x:450-520) and
the script cache (src/script.x:70-110) for stage.x; etc/builtin-macros.x
for src/builtins.x; consolidate's per-row counts; passes' driver shape.

| subsystem | now | after | reasoning |
|---|---:|---:|---|
| 2.1 front end | 5,341 | 5,291 | D: `_write_datum` delegates to `List.repr` (-10); `_attribute_since` linear scan (-10); lisp-late glue and `collect_forget_preload_entries` (src/frontend.x:288-339) (-30) |
| 2.2 syntax | 6,618 | 6,580 | postfix parsers, symbol literal, cons-cell boxing shared (V, -28); `lift_macro_lisp_expression` trim (-10) |
| 2.3 macros and comptime | 8,818 | 5,420 | comptime.x 3,436 -> stage.x 500; macros.x 4,160 -> 3,750 (lifecycle and restart 1000-1281 -220, comptime install/evaluate plumbing -150, legacy bodies L1 -35, +10 hash compare); meta.x 315 -> 310; builtin-macros.x 684 -> 660 as src/builtins.x (collectors 1-25 and `$builtin.emit` markers go); .xmacro 57; init.x 166 -> 140 as lib/lisp-init.x. The inventory (478-568) stays: consumers at meta-protocol-adoption.x:25, src/build.x:462, lib/lisp.x:1803 |
| 2.4 Lisp (hand-authored, machine.x in 2.9) | 5,338 | 3,210 | lisp.x 3,190 -> 2,000 (section 3 table); lisp-machine 480 -> 0; comptime.xlisp 399 -> 0; builtin-core 34 -> 0; compiler-sdk 23 -> 10; lisp-values 465; init-core 176 -> 200; lisp-bindings.x 137 -> 110 (collector gone; counted here though it moves to src/); lisp-bindings.xmacro 20; lisp-extras 28; lisp-bindings-core 33 -> 20; lisp-io 5; x2c-payload.x 348 |
| 2.5 transforms | 5,542 | 5,157 | driver 330 -> 180 (local post-order fixed point; `_sequence`/`_finish`/`_children` fold, src/transform.x:1471-1801) (-150); cleanup skeleton `_units`/`_function`/`_rewrite` region cases join the driver (src/cleanup.x:626-781) (-100); adapter memo E (-60; six sites of 5-8 lines, src/lambda.x:236-249 is one); nested-lambda walker (-25); printf table X3 (-50). regions.x: `lowered_meta_regions` replay goes, analyzer and meta variant stay (0) |
| 2.6 backend | 4,141 | 3,985 | cache-id collection and header reference rewrite fold into emit (src/cache.x:504-558, 588-634), partition markers become per-node destinations (-141, passes); JSON renderer builds one Map (Q, -15) |
| 2.7 driver | 6,045 | 6,020 | staged-module cache over the script cache shape (+60); CLI setter columns I (-45); manifest setter table T (-30); one identity hash U (-10) |
| 2.8 values | 11,454 | 11,449 | X2CVarNumericInfo embed (-5); Block/Buffer growth family not booked (string.x unaudited, map 2.8) |
| 2.9 match (with machine.x) | 5,232 | 4,567 | machine.x 540 -> 400 (-140); match-recursive relocated (-445); MatchCache N (-80) |
| 2.10 runtime infrastructure | 7,638 | 7,562 | one recursive-mutex primitive B (-56); Context export arms P (-20) |
| 2.11 services | 4,953 | 4,918 | autodiff registries and shared item cases (V, -35); the mode-parameterized walker is not booked (lines past ~900 unread, map 2.11) |
| 2.13 types, protocols, compiler.x | 7,492 | 7,167 | one classifier C (-45); typedef walkers and declare/bind facts O (-65); adapter template X1 (-70); adoption row X2 (-30); `meta_layouts` and its SymTxn row, lowering caches (-40); `fixed` memo (-15); struct regrouping into Unit/Parser/Sym/Meta/Out/SourceFacts (-60) |
| other | 1,792 | 1,792 | unchanged |
| total | 80,404 | 73,118 | -7,286 (9.1%); -6,841 (8.5%) if the 445 relocated lines are not counted; plus 9,234 generated lines and the 53-line generator deleted |

Per-file check of the two largest deletions. comptime.x: the 117 heads in
70-3089 are lowering (112 named `_lower*`/`Lowering`/`LowerCleanup`) plus
five entry points the staging replaces; 3089-3435 hold two lowering
entries (go), the lifting rules (~180, stay), `check_meta_call` (20, stays)
and the layouts (~100, stay in part). lib/lisp.x: the function map (C2)
leaves the reader, natives, adapters, evaluator and API, about 2,000
lines, not lisp's 1,300 (a rewrite estimate) nor kernel's 2,400 (which
keeps the hand rows).

Measurement-gated candidates outside the total: L3 (-80); deriving
lisp-values' 157 prototype rows (-150); generating the remaining hand
target rows (-80); match lowering emitting ordinary AST instead of the
private emitter cases (0 to -65: the C-text cases at src/emit.x:717-862
become AST construction of about the same size); Block/Buffer growth as one
generics family (-100); autodiff on one walker (-200). Ceiling ~72,400.
Vetoed by consolidate's reading and not booked: regions.x as "1,281 lines
whose only hard-error consumer is the meta path" (one analyzer, three
entries, ~70 audit lines); the native-meta inventory (live consumers);
adapter synthesis at 150-250 (the memo idiom is ~60); the two
serializations (layers); de-recursing any mutex; the quasiquote refold H
(+36 hand lines for an artifact that no longer exists).

## 6. Performance ledger

Instruments: build-cost score (baseline 464,833 cycles/line at b8d9c452),
translation CSV, shootout, bm-all, sample share table.

| dimension | expected change | payoff | measured how |
|---|---|---|---|
| build-cost score, clean stage | 0 to +3%: shipped bodies are linked, so a stage build compiles no module; the compiler gains ~1,500 lines of C (builtins, linked-meta) | one execution model | `make bm-build-scaling`; repeat scores span ~4 points, so this sits at the noise floor |
| build-cost score, steady state | -1% to -3%: compile-time Lisp is 1.7-2.7% of translate samples and macro expansion 9.6-13.1% (comptime-x2c-generalization.md:1031-1036); the per-process fill of ~9,900 Lisp lines and the lib/meta.x preload parse go; an imported `.xmacro` costs a hash compare instead of lower-and-evaluate (0.3 ms per declaration per importing unit, same plan 497-503) | faster incremental builds | translation CSV per unit; the src/ and lib/ columns moved ~4% at the last engine change (same plan 1010-1018), so language's -15% is unsupported |
| compile-time execution of meta code | 10-100x faster: a 104-row ledger scan costs ~13 ms through the evaluator (same plan 507-509); the 3.07 s vs 10.48 s decline was evaluator cost and does not apply to native execution | ledger and autodiff at C speed; meta code written naturally | the settling measurement the plan names (525-527): re-port the var-tags row lookup natively and translate lib/ against a re-measured baseline; migration step 1 |
| macro expansion time | share 9.6-13.1% -> ~7-10%: the `$(foreach.expand ...)` glue call becomes a native call; template.replace, invocation match and bind_syntax dominate and are unchanged | same | sample share table; marginal cost of 100 foreach expansions |
| user Lisp `defmacro` bodies | 2.7x faster on the measured case with the memo (505 -> 186 ms); without AUTO, hand-Lisp derivations 21 -> 28 ms (1.33x) | replaces what AUTO bought on hand Lisp | x2c-lowers-to-lisp.md:739-783 cases re-run |
| per-unit cold cost, user meta bodies | +100-200 ms per changed group per compiler stamp (in-process translate ~10-30 ms plus `cc -O1 -fPIC -shared` ~60-150 ms); 82 fixture sources define bodied non-native meta functions, 1 example, 0 unit suites, so a cold `verify-fixtures` pays ~12-20 s once per builds/0 rebuild; stage builds pay 0 | full x2c at compile time | wall time of `make verify-fixtures` cold vs warm; the AGENTS.md process-ceiling item: no new gate, one measured cost |
| editor query latency | unchanged unless the edited text is inside a meta body (then +~150 ms) | same | time `x2c editor` on a unit with a meta body |
| generated-code speed | 0: same backend, same runtime | - | shootout, stage comparison |
| runtime hot paths (Var ops, Match, Scope/Pool, errors) | 0: varops, match-machine, admission memos, scope, pool, error untouched; MatchCache N changes eviction structure only | - | bm-all; test-match-cache.x pressure cases |
| runtime Lisp in embedding programs | 1.1x-1.5x slower on hot lambdas (the gate guarantees >= 1.11x; hand-Lisp derivation 1.33x); the memo offsets macro-heavy code | -1,500 lines, one execution model | evaluator arm of run-lisp-auto-benchmark.sh vs today's prepared arm; U2 |
| process startup | -5 to -15 ms of 29 ms (no five-file fill, no lib/meta.x parse) | - | startup lane (lisp-to-x2c-migration.md:132) |
| REPL submission | +100-300 ms against ~1 ms: past the 2x rope for that consumer | full x2c in the REPL, no subset | timed submission script; Gary's decision |
| build orchestration | unchanged fork-per-slice model; one more cache kind | - | clean four-stage wall time |

## 7. Bootstrap plan

The stage-0 rule. The checked-in compiler emits no runtime body for a
bodied `meta` function that reaches a compiler-supplied operation
(src/parse.x:2018 -> `meta_is_comptime_only`, populated at src/macros.x:
2064 when lowering reached a native the `<compiler>` supplier holds;
`supplies_native_meta`, src/macros.x:1829-1834, is name-based). (a)
src/builtins.x is unaffected: today's expander algorithms are not `meta`
and calling x2c_* from an ordinary body is not diagnosed (section 3), so
stage 0 compiles and links them; `meta native` on them binds nothing in
stage 0 (`_bind_native_meta` returns when neither the compiler nor a module
supplies the name, src/macros.x:1960-1966) and everything in stage 1. (b)
src/linked-meta.x is affected: lib/var-tags.xmacro (26 x2c_* references),
varops.xmacro (7), system-macros.xmacro (5) and autodiff.xmacro (1) hold
bodied `meta` functions that stage 0 lowers and suppresses; language's step
2 fails as written for this reason, and `_write_entry` would export nothing
for them.

Prerequisite (step 0, in the current tree, ~20 lines): a request flag
`--link-meta` under which a bodied `meta` definition keeps its runtime form
(parse.x:2018) and is also installed as a native-meta row (parse.x:2010)
while still being lowered for stage 0's own use. Published and bootstrap-
refreshed, it becomes stage 0: the "explicit intermediate validation"
AGENTS.md asks for. Kernel's alternative needs no prerequisite (stage 1
stages lib/*.xmacro on demand, stage 2 links them) but converges only
after two refreshes and needs `dlopen` during the stage build; fallback.

Stages. Stage 0 builds stage 1 with `--link-meta` on src/linked-meta.x;
stage 1 has linked builtins and shipped bodies and no lowering; its linked
hashes match the tree, so it translates the tree into stage 2 without
building a module; stages 2 and 3 compare byte for byte. The APE seed keeps
compiling bootstrap C (now with builtins.c and linked-meta.c) and delegating.

Migration order if staged on the current tree, each step gated by
`tools/gate-state.py ensure agent-pr-check` and, where named, the
differential checker or a measurement:

1. Settling probe, no engine change: spell the row-lookup helpers of
   lib/var-tags.xmacro that reach no x2c_* operation `meta native` (their
   runtime forms are already emitted through lib/common.x and linked into
   the compiler), rebuild one stage, translate lib/ with it against a
   re-measured baseline. Refutes the thesis if native lookup is slower.
2. L1 (-35) and the per-call-site memo (+25); check-reference-lisp and
   test-lisp.x gate.
3. src/builtins.x from etc/builtin-macros.x, init.x, lisp-bindings.x, with
   lib/lisp-init.x; keep the generated .xlisp files for one refresh (an
   imported definition shadows the native harmlessly), then delete them,
   the generator and the `bootstrap-refresh` line (Makefile:229).
4. Step 0 prerequisite flag; bootstrap refresh.
5. src/linked-meta.x; hash-compared binding; `x2c_module_reset` and the
   per-unit meta Scope; staged modules for user units and imports;
   `$name(...)` prefers the native binding while comptime.x still exists
   (the documented precedence). Run suites, fixtures and examples both
   ways: this validates the thesis on autodiff, class, var-tags and the 82
   meta-bearing fixtures before anything is deleted (language's 7c).
6. Delete comptime.x's lowering (stage.x keeps lifting, folding, layouts,
   `check_meta_call`), comptime.xlisp, the comptime-only natives, the
   lifecycle and restart, `meta_layouts`; update the 18 declines fixtures
   and the subset chapter; withdraw `x2c_comptime_lower`; port the REPL
   (Gary's decision first).
7. Measure U2; drop AUTO, lisp-machine.x, machine.x's Lisp half,
   test-lisp-auto.x, the AUTO API and its doc rows.
8. Consolidations that keep generated C byte-identical: A, B, C, D, E, I,
   N, O, P, Q, T, U, V, X1, X2, X3, in consolidate's batches.
9. Local post-order fixed point (delete `fixed` and the confirmation
   walks), cleanup cases into the driver, cache-id collection into emit,
   partition before lowering. Gate: byte-identical C except lambda sibling
   placement (plans/archive/meta-functions.md:470-478: re-transforming
   transform output is idempotent and moves only the sibling); the 38
   `.transform` fixtures are regenerated and reviewed.
10. Compiler struct regrouping (no output change).

## 8. Language changes

This synthesis inherits language's license.

**L1, adopted.** Retire the legacy macro body forms `=> { ... }` and the
unterminated `=> (...)` (language.md:808-820; src/macros.x:3073-3096,
3277-3288, 3337-3341). Uses: fixtures and the grammar test only
(macro-using-conflict.x:3, macro-result-missing-kind.x:3, three more).
Migration: one sed pass. Buys ~35 lines and two fixtures.

**L2, adopted, the change that licenses the deletion.** A `meta` body
executes natively, linked or staged. Visible consequences: `x2c_comptime_
lower` withdrawn; the compile-time subset lapses; compile-time objects are
ordinary Scope allocations of the compiler process under the call-scope
rule; `meta static` keeps one instance per translation unit through the
reset entry; `$(name args)` from Lisp keeps working; the AUTO API leaves
the Lisp module page; the REPL's `:lowered` shows C. Migration: none for
user programs. The measured decline does not apply because it compared
lowered x2c against hand Lisp and attributed the cost to evaluator
execution of the scan (comptime-x2c-generalization.md:495-512); native x2c
is the option it did not measure.

**L3, optional, not in the total.** Drop the quoted `%[...]`/`%{...}`
forms (language.md:2120-2125): 9 and 19 uses in src/lib/etc, 90 and 102 in
the tree, mechanical rewrite by the documented element rule (2136-2158);
~80 lines (src/literals.x:631-645, 691-729, the tokenizer array/map modes).
Held until one check passes: the typed-family rule is stated for the
percent forms (2127-2132) and language.md:2063-2064 says a declared typed
family "builds its own" from the evaluated forms too; a fixture translating
`TypedArray a = %[1, 2]` and `= [1, 2]` to identical C settles it.

Evaluated and declined, from language's list, so nothing is re-litigated:
unify `$(...)` and `$name(...)` (~0 lines; 410 of 615 raw `$(` forms are
Lisp programs); Lisp as data notation only; mixed declaration rows (~50
lines, ~300 uses); generic selection (~60 lines, no mechanical migration);
designated initializers (~80 lines, not meaning-preserving); unity build
(src/generate.x:357-602 implements `#pragma private` visibility and
typedef order that any header model needs; whole-program recompiles break
the 2x budget on incremental edits).

## 9. Risks and unknowns

Judge doubts resolved by reading: lisp.x survivor 1,300 (refuted, ~2,000);
lisp-values 465 -> 40 (refuted: 132 of 289 bound names are not `meta`
declarations, 25 defuns adapt); stage.x 300 (a floor; 500 booked);
language's -5% to -15% warm build cost (unsupported; -1% to -3% booked);
"fork per unit" (refuted, src/main.x:230-245, 335-347; the reset is
required); deleting the meta hard error (refuted, src/regions.x:19-21,
498; kept); kernel's -320 emit.x and 1,970 rule lines (no reference
implementation; not booked); the cold population (82 fixtures, 1 example,
0 suites); the `x2c_` filter (true; a path-selected table); init.x's home
(lib/lisp-init.x, aliases already in init-core); APE/Windows/Cygwin (the
seed delegates, Windows is WSL2; the drop is user bodies on non-dlopen
hosts); error transfer and the budget (src/macros.x:2194-2203);
consolidate H and R (moot with no generated .xlisp); passes' -5% to -12%
(not booked; `c.fixed` already makes the confirmation walks map lookups,
so the single walk is taken for clarity and lines with a <3% bar).

Carried as unknowns:

- U1 (refutes the thesis): the settling measurement. If lib/ translation
  with native row lookups is slower than the Lisp ledger baseline, native
  execution does not pay and the design reduces to consolidate plus passes
  (about 77,700).
- U2: AUTO's real speedup on a Lisp program, not the microbenchmark. If a
  real embedding workload is more than 2x slower without AUTO, keep the
  tier and forgo ~1,500 lines.
- U3: the REPL redesign (DT_NEEDED chaining, redefinition, persistent
  values, `:inspect` accounting) is a sketch the repl probes decide; the
  latency is a consumer regression Gary must accept or refuse.
- U4: runtime-header coupling. A staged module for a tree `.xmacro` is
  compiled against the tree's generated headers but runs in a compiler
  linked with its own runtime; the stamp (src/macros.x:1673-1697) keys on
  compiler identity, not header identity. Lowered code already embeds the
  tree's tag ids and layouts while calling the compiler's natives, so the
  exposure is not new, but it widens when a body reads a runtime struct
  field directly. Mitigation if it bites: compile staged modules against
  the headers the running compiler was built from, so a mismatch is a C
  error, not corruption. Probe: edit a `Var` accessor in lib/common.x and
  translate lib/ with builds/0 under the staged path.
- U5: confluence of the local post-order fixed point. Today the driver is
  pre-order per round (src/transform.x:1590-1618, 1707-1766) and the
  unit-wide loop revisits a parent after its children lowered; post-order
  gives the parent lowered children on its first visit, so a helper
  matching a child's unlowered shape would produce different C
  (`_rewrite_defer_list` at the block, 1754-1758, is the only sibling
  dependence found). Refuted if a `.c` fixture changes.
- U6: `x2c_module_reset` re-running `meta static` initializers whose
  values allocate: the per-unit meta Scope must outlive every call in the
  unit; lib/static-init.x's guards and lib/error_init.x's placement (5-7)
  are untouched; the reset must not re-run a module's constructor.
- U7: `_certify_native_meta` may reject some lisp.x natives spelled `meta
  native`, bounding the hand-row saving; -100 is booked, -180 the maximum.
- U8: the module cc cost per group (60-150 ms) is from cc timings of small
  files, not measured on this tree.
- U9: comptime.x 1300-3089 was classified by function head, not read line
  by line; a retained behavior hidden there (`_lower_coerce`'s closed
  conversion list, M3) would need a native equivalent in stage.x.
  lib/string.x and match.x 2260-2677 remain unread (where consolidate's
  number could move up).

Refutation of the thesis as a whole: U1 negative, or a meta-* fixture that
depends on lowered-Lisp semantics native execution cannot reproduce (none
of the 873 `.phases` files names lowered output and no fixture mentions
`:lowered` or `lisp.native.targets`, so none is known).

## 10. Claims

C1. src/comptime.x is lowering except a retained kernel: 117 function
heads in 70-3089, 112 named `_lower*`/`Lowering`/`LowerCleanup`, the other
five being `lower_declined`, `inherit_shared_meta`, `install_comptime`,
`lower_reached_meta`, `meta_is_comptime_only`; 3130-3310 lift values, 3311
checks calls, 3330-3435 compute layouts. Depends: stage.x at 500.

C2. lib/lisp.x regions: machine bridge 107-300, reader 549-830, natives
836-1090, comptime-only natives 1110-1270 (`_cell` ... `lisp_unwind`),
adapters 1272-1600, target rows 1607-1815, evaluator 1832-2303, AUTO
2310-2957 (`LISP_AUTO_*` ... `Lisp.auto_prepare`), `_apply` 2958, `_eval`
3021, budget 2919/3051, API 3064-3190. Depends: survivor 2,000; drop ~1,500.

C3. Stage-0 rule: src/parse.x:2018 returns NULL for a lowered function
`meta_is_comptime_only` reports; `meta_comptime` is set at src/macros.x:
2064 when `lower_reached_meta`, which `supplies_native_meta` (src/macros.x:
1829-1834) drives by name from the `<compiler>` supplier map. Depends: the
step-0 prerequisite; language's step 2 fails without it.

C4. etc/builtin-macros.x's algorithms are ordinary functions (line 29
`List builtin_scope_expand`) decorated by `$builtin.emit()`, whose body
calls `x2c_comptime_lower` (line 9); they reference x2c_* 86 times;
`check_meta_call` (src/comptime.x:3311-3320) diagnoses only names in
`meta_comptime`, populated at comptime.x:2969, frontend.x:307, macros.x:
2064, never in `_bind_native_meta` (src/macros.x:1945-1988). Depends:
src/builtins.x links under any stage 0 with no compiler change.

C5. `_write_entry` (src/build.x:450-466) exports the rows of
`_x2c.native-meta.declared`; `_native_meta_targets` (src/macros.x:531-556)
reads `(native-meta name signature)` symbol rows, which today only `meta
native` definitions and bodyless prototypes produce (parse.x:1993, 2010).
Depends: bodied `meta` must become inventory rows.

C6. Workers take slices: `_translate_workers` forks per chunk and runs
`foreach (String input, slice) _compile_file(...)` in the child
(src/main.x:230-245); `_translation_chunks` gives one slice per worker,
`slices == total` only for builds (335-347); `parallel` needs `jobs > 1 &&
total > 1` and no dump or inspect (368-369). Depends: the reset entry.

C7. Modules load `RTLD_NOW | RTLD_LOCAL` and are never unloaded
(src/macros.x:1699-1710); `X2C_NATIVE_MODULES` is 0 under
`__COSMOPOLITAN__`, `_WIN32`, `__CYGWIN__` (1712-1716); the stamp is
checked before any code runs (1673-1697, 1723-1735); builds/stage.mk:47-57
links the whole archive with `-rdynamic` or `-force_load`; the APE seed
delegates translation to `$prefix/bin/x2c` (src/bootstrap.x:221-244;
verify-ape.sh never translates with the seed). Depends: the reset design;
the platform drop; symbol resolution of staged modules; every documented
build path surviving the linked route.

C8. `meta static` is documented as per-translation-unit values built from
the source initializers (docs/src/guide/meta-functions.md:246-247).
Depends: the reset is a documented obligation.

C9. `check_meta_regions` differs from `check_regions` only by `.meta = 1`
(src/regions.x:1249), which changes one branch, `case %(alloc final) if
(w.meta): return w.frame` (498), and by reporting an error (1255); the
justification is 19-21. Depends: keeping it costs ~25 lines and prevents
a dangling pointer inside the compiler.

C10. A module uses the compiler's own runtime and can call any runtime
function (meta-functions.md:516-517, 529-531); `_evaluate_meta_value`
(src/macros.x:2173) catches two `call-stack` arms (2194-2201) and `%(?code
*detail)` (2202-2203). Depends: native raises reach the diagnostic; the
budget is a listed drop.

C11. etc/lisp-values.xlisp binds 289 distinct C names, 157 declared
`meta` in lib/, 132 not (Array_capacity ... Iter_foldl), plus 25 defuns
(lines 18, 206-273). Depends: 465 kept; -150 optional.

C12. 82 fixture sources define a bodied non-native `meta` function (grep
`^\s*meta\s+(static\s+)?...\)\s*(\{|=>)` over unittest/compiler-fixtures),
2 define `meta native`, 18 are `comptime-declines-*.x`, 0 unit suites and
1 example define one, 0 `.phases` files name lowered output. Depends: cold
cost ~12-20 s per builds/0 stamp; 18 wording fixtures change.

C13. Compile-time Lisp is 1.7-2.7% and macro expansion 9.6-13.1% of
translate samples (plans/archive/comptime-x2c-generalization.md:1031-1036).
Depends: the warm build-cost band of -3% to +3%.

C14. The var-tags decline: 3.07 s vs 10.48 s on lib/, ~13 ms per 104-row
scan through the evaluator, and "Re-porting lib/var-tags.xmacro and
translating lib/ is the measurement that would settle it" (same plan
462-531). Depends: reopening the decline; migration step 1.

C15. `_apply_lambda` re-expands a `defmacro` on every call (lib/lisp.x:
2166-2174); memoizing recovers 335 ms of a 505 ms case (x2c-lowers-to-
lisp.md:755-783). Depends: the +25-line memo pays for itself.

C16. AUTO is worth 3.4x on lowered x2c (2.90 s vs 9.83 s) and 1.33x per
hand-Lisp derivation (21 vs 28 ms) (x2c-lowers-to-lisp.md:739-747); the
gate is prepared/evaluator <= 0.90 (run-lisp-auto-benchmark.sh:7-9).
Depends: the runtime-Lisp row stays inside the rope.

C17. The transform driver is pre-order per round (`_node` rewrites, then
`_finish` descends, src/transform.x:1590-1618, 1707-1766), re-walks to
List identity plus early-declaration rounds and one cleanup walk
(1776-1801), memoizes anchored statements in `c.fixed` (src/compiler.x:
110-113), and `transform`, `mark_cleanup_regions`, `check_regions` have one
caller each (src/main.x:76; transform.x:1800, 1779). Depends: the local
fixed point deletes `fixed` and the k-1 walks.

C18. `x2c_comptime_lower` has three callers, all generators (etc/init.x:9,
etc/lisp-bindings.x:11, etc/builtin-macros.x:9), and one doc paragraph
(language.md:1767-1770). Depends: withdrawal needs no user migration.

C19. `Lisp.new` evaluates the embedded etc/init.xlisp (lib/lisp.x:85-86,
383, 752-756); etc/init.xlisp:225-229 alias lowered names (`(def not
init_not)`). Depends: lib/lisp-init.x plus ~25 bind rows keep the runtime
vocabulary.

C20. Consolidate's refutations hold: lib/var.x:372-375 holds the
descriptor lock and calls `x2c_descriptor_registration_frozen`, which locks
(lib/dispatch.x:302-306); `Logger.free` (662) calls `clear_sinks` (666);
the inventory has consumers at meta-protocol-adoption.x:25, src/build.x:
462, lib/lisp.x:1803; regions.x has three entries over one Walk (1212,
1237, 1263); an adapter memo site is 5-8 lines (src/lambda.x:236-249).
Depends: B keeps recursion, the inventory stays, regions is 0, E is -60.

C21. `$compiler.targets()` filters rows to `x2c_` (src/macros.x:
1064-1066); `_x2c.native-meta.declared` selects rows by declaring path
(556-568); `_meta_lisp_name` maps `_` to `.` (1077-1083); etc/builtin-
core.xlisp:27-33 holds the six `scope.expand`-style aliases;
`_certify_native_meta` (1926-1943) rejects a prototype only when a
parameter and the result are both unowned handles (`_native_meta_summary`,
1911-1924). Depends: builtins register with no new binding mechanism and
`meta native` on them and most lisp.x natives passes; U7 bounds the rest.

C22. commands/repl/repl-session.x:490-507 calls `lower_repl` and
`lower_declined`, evaluates in `macro_lisp`, deletes `C._globals` cells on
failure; repl.x:140, 368-371 read AUTO stats and set the call budget;
src/editor.x:182-185 preloads once and answers one query per process.
Depends: the REPL is a consumer change; the editor's group-hash argument.

C23. Legacy macro bodies are src/macros.x:3073-3096 with branches at
3277-3288, 3337-3341, used by fixtures only; `with` records the source
expression and substitutes it at each use (src/statements.x:571-600,
522-530), 45 lines. Depends: L1 is -35 and safe; `with` stays kernel.

## 11. Comparison of the five designs

| design | thesis | lines after | judge total | taken into the synthesis |
|---|---|---:|---:|---|
| consolidate | keep the pipeline; delete only what reading confirms | 79,160 (ceiling 77,700) | 116 | the base: removals A, B (recursive), C, D, E (~60), I, J, N, O, P, Q, T, U, V, X1, X2, X3 with their pinned tests; the refutations as vetoes (regions.x, inventory, mutexes, serializations, adapter estimate); the frame "only an engine deletion reaches ~10%" |
| lisp | the better compiler for compile-time x2c is the x2c compiler | 72,439 | 108 | the engine deletion and staging model (stage.x, `Build.module_entry`, per-unit reset), the citation list refuting hypothesis 1, the performance ledger shape (clean-stage +, steady-state -, startup, REPL named), no generated .xlisp, the checker as the kernel's oracle; rejected: 1,300-line lisp.x, 40-line lisp-values, deleting the inventory, src/builtins.x holding runtime init algorithms |
| passes | fewest walks; local fixed point; walk-owned state | 79,137 | 106 | the local post-order fixed point deleting `fixed` and the confirmation walks, cleanup cases into the driver, cache-id collection into emit, partition before lowering, the Compiler struct regrouping, and the reasoning for keeping parse, regions and lowering separate; rejected: the -5% to -12% expectation |
| language | delete the second backend under a licensed change; two small syntax retirements | 71,887 | 105 | L2 as the licensing change with `x2c_comptime_lower` withdrawn and the subset lapsed, L1, the with/without framing, the declined list, survivor sizes (lisp.x ~1,900, ~350 retained folding), step 7c as the validating step; rejected: linking shipped units under stage 0 as written, fork-per-unit, deleting the meta region variant, `with` as a local macro, -5% to -15% |
| kernel | small kernel plus a rule table of compiled meta functions | 71,882 | 100 | the stage-0 spelling trap and the prerequisite it implies, the per-call-site macro memo, the flag-guarded byte-identical migration, volatile qualification as one kernel pass, the emit.x private-node inventory as a gated later target; rejected: the rule driver (rebinding through `_resolve_content`), -320 emit.x, -330 protocol.x, deleting the meta hard error, new SDK surface (Rest capture, `x2c.function.current`, `x2c.unit.memo`) |

## 12. Answers

**What would change, and how.** The compiler keeps its representation
(canonical Lists over Var), its parser, type system, protocols, typed
lowering passes, backend and runtime, and loses its second backend: a
`meta` body is compiled by the same C backend as everything else, linked
into the compiler when it ships with it and built once into a cached module
when a user defines it. comptime.x, comptime.xlisp, AUTO, the Lisp machine,
the generated Lisp artifacts and the library lifecycle go; Lisp is the glue
evaluator over the same Var/List data. With consolidate's counted removals
and passes' single lowering walk: 80,400 to about 73,100 hand-authored
lines, 9,234 generated lines deleted, one execution model, no subset.

**Do small language changes alter the answer.** One does. Without any
licensed change the tree reaches consolidate's ceiling, about 77,700
(-3.4%), because the engine cannot be deleted while `x2c_comptime_lower`
is documented and the subset is the specification of compile-time x2c. L2
withdraws one operation only the generators call and turns a rejection
table into acceptances; it is worth about 5,000 lines and every program
that compiles today keeps its meaning. L1 is free; L3 is 80 lines with one
open check; the syntax-level candidates were declined for cause.

**Is a meta+macro duality more elegant and Lisp-like.** The duality
already exists and is the right one: a macro is a hygienic List template
over canonical syntax, a meta function is x2c over Lists, and the compiler
walks its own AST with the same `match` templates. What is not Lisp-like
today is that meta x2c is re-interpreted by a second compiler inside the
first. The Lisp property worth having is that the language at macro time
is the language itself with `eval` at hand; here `eval` is the compiler
plus `dlopen`, obtained by deleting the interpreter, not adding one. Lisp
remains the notation where a data notation with quasiquote is what a
template wants, checked at literate-lisp scale.

**The unnecessary abstractions.** The second backend and its runtime
(`C.true?`, `C.conv`, peek/poke over compile-time bytes); the AUTO tier
with speculative pre-expansion and machine slots, whose gate promises 10%;
the Lisp half of a machine only Match needs; a 12.7x generated artifact and
its generator, which exist because the lowering emits cons chains;
lifecycle flags and a restart-by-exception for a parent session that can
be built eagerly; a hand table restating 157 `meta` prototypes; a per-round
unit re-walk plus a memo to make it cheap; two after-the-fact cache-id
walks; three recursive-mutex blocks, four typedef walkers, two top-level
dispatchers, six adapter memos. Equally important is what reading showed
is not one: regions.x, the native-meta inventory, the admission memos
(measured 2.35x), the two serializations, and the meta hard error, which
guards the compiler's own memory.

**How code quality over safety shapes it.** Kept because it prevents wrong
output, corrupted state or an unsafe crossing: the compile-time-only
inference (an emitted body would be an undefined symbol), the meta region
error (a dangling pointer inside the compiler), the module stamp (loading
runs code), the native-meta lifetime certifier, `volatile` qualification
across `sigsetjmp`, the expansion guards, hygiene. Dropped as performative:
the subset's rejection table and its 18 fixtures, the Lisp-boundary
argument checks in compiler-sdk.xlisp (a native signature checks itself),
the `<lisp-late>` restart, the AUTO transparency API, the call budget for
native bodies, `:lowered` as Lisp. No origin tracking, no second validator.

**The auto-research task.** Acceptance: `make verify` (58 suites); `make
verify-fixtures` with the 18 `comptime-declines-*` expectations and any
`.diagnostics` that mention lowering allowed to change and every `.c`,
`.h`, `.stdout`, `.status` fixture held; examples/manifest.txt; stage-diff-
all; check-reference-lisp with showcase.xlisp plus init-core and
lisp-values; the REPL, native-module, package, sanitizer and cli-boundary
probes; `git diff --check`. Metrics and bounds: build-cost score within +3%
clean and <= 0 steady; lib/ translate wall within the re-measured Lisp
baseline (U1, the first checkpoint); expansion share from the sample
table; bm-all Lisp rows <= 1.5x; REPL latency reported, pending Gary; cold
verify-fixtures within +20 s; hand-authored lines at 73,100 +/- 700.
Ordering is section 7. A drop is justified only when its sole consumer is
the deleted engine (AUTO API, `x2c_comptime_lower`, `:lowered`, the subset
table, the budget for native bodies) or an ordinary mechanism reproduces
its observable behavior, with the lines saved stated; never when it changes
an existing program's generated C, a runtime module's documented contract,
or a consumer's command-line surface without Gary's decision.

**How meta, macro, C, base types, Lisp and the word machine interact.** C
is the substrate and the target: every construct lowers to C, and runtime
semantics C lacks are C library code in lib/. `Var` and `List` are the one
representation for the AST, the match patterns, the macro templates, the
Lisp data and the runtime containers, so a meta function, a macro template
and the compiler's own passes compute over the same values with the same
`match`. A macro is a template with hygiene, expanded by `template.replace`
at every syntax position. A meta function is x2c over those Lists,
compiled to C, linked into the compiler or staged into a module, called
through a `Func`; it asks the compiler questions through the x2c_*
operations and answers with syntax the binder accepts by structure. Lisp
is the glue notation and evaluator for `$(...)`, `$lisp.bind`, imports and
template splices, binding natives through one generated table, checked
against the reference interpreter. The word machine serves Match only, the
runtime hot path where compile-then-interpret is measured to pay.
