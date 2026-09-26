# Design: same pipeline, ruthless consolidation

Research spike, 2026-09-26. Stance assigned: keep the current phase
structure and representations, delete everything the map's section 3 table
and section 2 rebuild notes call parallel, derived, defensive, or unearned,
plus what a fresh reading finds. This is the conservative bound the other
designs must beat. Read-only; nothing under src/, lib/, etc/, docs/, plans/
was edited. Line counts are `wc -l` on current dev; citations are file:line
in this tree or in .context/rebuild/map.md.

Scope of the count: every hand-authored .x/.xmacro under src/ and lib/
(x2c.x excluded) plus the hand-authored etc/ files. On disk today that is
41,950 + 35,835 + 2,585 = 80,370 lines (map.md says ~80,400; the 12-file
lib/ undercount in map.md's table is corrected here, see map.md:1555-1563).

## 1. Thesis

Consolidation without an architectural change removes about 1,200
hand-authored lines (1.5%), or about 2,700 (3.4%) if every measurement-
gated candidate comes out favourably, because the tree's size is not
duplication: it is features, each already implemented once, plus three
performance tiers (the compiled Match engine, the Lisp wordcode tier, the
Match plan cache) that were kept by measurement (map.md section 6). Reading
the candidates in source shrinks most of them. The two largest section-3
entries evaporate: the 8,719-line item is a generated artifact, and its
hand-authored cause is a four-line case in src/comptime.x:1500-1503 whose
quasiquote replacement adds lines; the 1,281-line regions.x item is one
analyzer shared by the warning, meta-error, and certify audit entry points
(src/regions.x:1212, 1237, 1263), so "reducing it to the correctness-bearing
case" keeps the analyzer and deletes about 70 lines of audit branches. The
three recursive mutexes are all load-bearing (section 5), the two
serializations are complementary layers, and the six adapter namespaces
share a seven-line memo idiom, not 150-250 lines. What a same-pipeline pass
does buy is real but small: one test-only oracle out of lib/, one mutex
primitive, one top-level dispatcher, one typedef walker, one adapter memo,
one CLI table, one protocol-adapter template, and a 3x smaller generated
Lisp library that loads faster at every compiler start. The number this
produces says an architectural rebuild is the only route to a substantially
smaller tree, and that the rebuild must delete an engine or a tier, not
reorganize passes; design-kernel.md's 71,900 (11%) is exactly a deleted
engine.

## 2. Architecture

Unchanged. `Ast`, `Type`, Lisp data, match patterns, and runtime containers
stay `List` over NaN-boxed `Var` (map.md section 1). The pass order from
source to C stays as map.md:104-158 describes it:

1. Tokenizer.scan (lib/tokenizer.x:793) -> token array.
2. Collection: one top-level classifier (section 5, removal C) run with
   `c.shallow` set, replaying `.xi` interfaces (src/collect.x:567).
3. Full parse through the same classifier with bodies parsed
   (src/parse.x:1953); macros and meta functions expand in the shared
   Lisp session (src/macros.x:3757).
4. Resolve and convert (src/expressions.x:2447-2454, 4053-4366).
5. Region analysis, unchanged (src/regions.x:1212).
6. Transform fixed point, lambda lowering, cleanup regions
   (src/transform.x:1776; src/cleanup.x:781).
7. Backend: cache, generate, emit, format (src/generate.x:1228,
   src/emit.x:1449, src/format.x:90).
8. Native build (src/build.x).

Kernel operations, meaning operations that need facts only the compiler
has: binding and scopes (Sym, src/compiler.x:2470-3905), typing and
conversion (src/type.x, src/expressions.x), protocol member resolution
(src/protocol.x:1723), layout (src/comptime.x:94-131 meta_type_layout),
lifetimes (src/regions.x, src/cleanup.x), placement and emission order
(src/generate.x:357-602, src/emit.x, src/cache.x). Macro or meta over
canonical syntax: foreach, scope, let, lock, auto, class, and the other
system macros (etc/builtin-macros.x, lib/system-macros.xmacro), callback
adapters' Lisp-side conventions, autodiff (lib/autodiff.xmacro), `$class`
declaration production, the Var-tag ledger projections (lib/var-tags.xmacro),
and the generics families (lib/array-generics.xmacro,
lib/map-generics.xmacro, lib/list-generics.xmacro). Nothing moves between
the two columns in this design.

## 3. Compile-time execution model

Every component survives; two change shape.

- src/comptime.x survives. One change: `_lower_content`'s `(cons ?head
  ?tail)` and `(append ?head ?tail)` cases (src/comptime.x:1500-1503) refold
  a right-nested cons/append chain into one `(quasiquote ...)` form, with
  constant heads left literal, `Var`-boxed heads as `,(List_var x)`, and
  `append` heads as `,@x`. The parser already lowers `%(...)` into cons
  cells (src/literals.x:75-97; src/expressions.x:2109-2129), the evaluator
  already implements quasiquote (lib/lisp.x:2027-2046), the AUTO lowerer
  constant-folds it (lib/lisp.x:2424, 2622), and etc/init-core.xlisp:41-49
  already writes backtick forms by hand. Hand-authored cost: about +36
  lines. Generated effect: etc/builtin-macros.xlisp shrinks from 8,770 to an
  estimated 3,000 (builtin_foreach_declare goes from the 20-plus lines at
  etc/builtin-macros.xlisp:218-235 to about eight); the exact figure is
  unverified (section 9). tools/gen-lisp-init.py regenerates the file from
  etc/builtin-macros.x deterministically, so byte-identical regeneration
  (map.md:304-305) is preserved by construction.
- lib/lisp.x survives whole, AUTO tier included; lib/lisp-machine.x and
  lib/machine.x survive. Deleting the AUTO tier is the one large candidate
  this stance could take under the 2x allowance and it is listed as
  measurement-gated (section 9), not assumed.
- lib/match-machine.x survives; lib/match-recursive.x moves to unittest/
  (removal A).
- The shared library session survives with the `<lisp-late>` restart
  removed (removal J): src/main.x:371-379 preloads the parent
  unconditionally instead of deferring for sequential, non-dump
  translations, so `library_restartable`/`library_settled`
  (src/macros.x:1001-1002), `macro_library_defer`/`macro_library_pending`
  (1229-1236), the raise at 1248, and the catch at src/main.x:177-180 go.
  `$(import ...)` cycle detection and replay, dlopen native modules, hygiene
  (src/macros.x:2499-2576), `$lisp.bind`, and the native-meta inventory are
  unchanged; the inventory (src/macros.x:478-568) has live consumers
  (unittest/compiler-fixtures/meta-protocol-adoption.x:25,
  meta-protocol-default.x:21, lib/lisp.x:1803, src/build.x:462), so map.md's
  "no confirmed external consumer" is refuted and it stays.
- etc/builtin-macros.x:1-25, etc/init.x:1-25, and etc/lisp-bindings.x's
  copy of the emit/write collector become one `etc/lisp-emit.xmacro`
  (removal R).

## 4. Feature coverage

Every row of map.md section 4 keeps its owner; the disposition column uses
the brief's five words.

Language surface, all "kernel" unless noted:
- C foundation, expression-bodied functions; scalar declarations and
  arithmetic; collection and string literals; interpolation; symbol and
  atom literals; indexing and slicing; method-style calls; postfix chains,
  unary, sizeof, offsetof, _Generic, va_arg, casts, designated
  initializers, compound literals; generic selection; mixed declaration
  rows; C initializers and static assertions; exact Var-tag tests;
  membership with in; flat list destructuring; Var boxing, conversion,
  operators, dispatch; reference parameters; delegate fields; checked
  foreign aliases; type-owned initialization and shutdown; managed
  initializer syntax; named types and class declarations; package imports
  and `name__` prefixing; source files, pragmas, script units; indentation
  syntax; host preprocessing; structured diagnostics; two-pass compilation
  and `.xi`; editor overlays and one-shot queries; stable x2c_* entry
  points: kernel, as today.
- dynamic numeric conversion; dynamic truthiness and binary operators;
  protocol-backed direct updates: runtime as today (lib/varconvert.x,
  lib/varops.x, lib/dispatch.x) with the compiler half in src/protocol.x.
- lambdas and typed callback adapters: kernel (src/lambda.x with removal
  E) plus runtime as today (lib/func.x).
- control flow; with; match statement; raise/catch/finally/defer: kernel,
  with lib/match.x (removal N) and lib/error.x/exception.x runtime as
  today.
- foreach and iterator destination omission; system macros ($scope, $let,
  $lock, $auto, $class, $switch, $dedent, $todo, $unreachable, $time,
  $assert): macro/meta, as today, with the smaller generated library.
- protocols: kernel (src/protocol.x with removals X1-X2).
- compile-time macros and decorators; meta functions; inline Lisp
  bindings; compile-time import and native modules: kernel plus the Lisp
  runtime as today.
- region model and lifetime warnings: kernel, unchanged (section 5, G).

Runtime library: every module page row is "runtime as today" except:
- reference matcher (lib/match-recursive.x): drop (justified) as a shipped
  library module; the code moves to unittest/ as the differential oracle
  and its module page leaves the book. 445 lines leave lib/.
- Mutex: runtime redesigned only by adding the shared static recursive
  primitive (removal B); `Mutex` itself is unchanged.
- pattern matching (lib/match.x): runtime redesigned in the plan cache's
  eviction structure only (removal N); admission memos stay (map.md:1349).
- Context: runtime as today with the three Block-view export arms folded
  (removal P).
- Logger, dispatch, error: as today over the shared primitive.
- typed Array/List/Map instantiations, Var/tags/adapters, numeric
  conversion (one struct embed, removal V), operators, static-init, clibc,
  cmath, scalar types, integer ops, args, atom, autodiff (removal V), block,
  buffer, common, diff, digest, exception, file, func, iter, json, lib.x,
  Lisp runtime, list-selectors, list, machine, map, meta, path, pool,
  process, regex, scope, scripting, split, string-classify, string-number,
  string, symbol, symbolset, thread: runtime as today.

Tooling and packaging: CLI (removal I), manifests (removal T), incremental
native build, worker pool (removal J changes preload timing only), package
install, bootstrap payload, script execution, terminal reporting: kernel,
as today. REPL, graph, lint, torch: consumers, untouched; the graph tool's
duplicate lifetime analysis is reported in section 5 outside the count.

## 5. Line ledger

### Removals

Each row: what, lines it deletes net of what replaces it, and the test that
pins the behavior it must keep. "est" means a counted-in-source estimate.

| id | what | net | pinned by |
|---|---|---|---|
| A | lib/match-recursive.x -> unittest/support; its only consumers are unittest/test-support.x:5,58-78, unittest/test-match-plan.x:805, and unittest/benchmarks/match-capture-benchmark.x:4 | -445 | test-match*.x differential cases through test_match_oracle_*; docs/src/SUMMARY.md:62 page removed |
| B | one static recursive mutex primitive in lib/mutex.x replacing lib/error.x:76-104, lib/logger.x:109-137, lib/dispatch.x:254-282 (29 lines each, 87 total; replacement ~25 plus 1-2 per site). All three stay recursive: `Var.register_object_tag` locks then calls `x2c_descriptor_registration_frozen()` which locks again (lib/var.x:372-375, lib/dispatch.x:302-306); `Logger.free` calls `clear_sinks` under its own lock and `log_event` calls `Logger.log` (lib/logger.x:662-666, 759-760, 788-799, 817-838); error.x documents its reentrancy (74-75) | -56 | test-error.x, test-logger.x, test-thread.x, test-mutex.x, unittest/probes/run-full-sanitizer.sh |
| C | one top-level classifier: `_shallow_parse_loop` (src/compiler.x:1669-1744, 76 lines) and `parse_top_level` (src/parse.x:1953-2032, 80 lines) test the same eight forms in the same order (skip_linkage_brace, static assert, `$(`, import, protocol, keyword definition, macro definition, unit macro); the shallow-only steps (script statement skip, `collect_protocols` expansion, `_shallow_finish_declaration`) become the `c.shallow` continuation of the declaration tail | -45 est | run-header-cache.sh, run-symbol-snapshot.sh, proof-cold-collection, stage compares, fixtures class-adoptions-included and unit-static-call |
| D | `_write_datum` (src/collect.x:979-1002) delegates text to `List.repr` (lib/list.x:960, documented as the re-readable `%(...)` spelling) and keeps only its admissibility predicate. freeze/thaw (src/compiler.x:1274-1343) is a different layer (tokens and origins to portable Lists) and stays; map.md:206-209's "two serializations" is one serializer over one portability transform | -10 | run-header-cache.sh (.xi replay), proof-cold-collection |
| E | one `_memo_adapter(c, key, build)` for the six `names.adapters` sites (src/lambda.x:236, 496, 577, 645, 703, 786); each site's try_get/build/store/add_early block is 5-8 lines and the two bridge-function sites (703, 786) share the `function ("Func") (bind $bridge ...) (block (stmnt (return X)))` shape | -60 est | 56 callback-adapt-*/func-adapt-*/native-binding-* fixture files, test-func.x, test-lambda.x |
| G | regions.x: no change in the base ledger. The analyzer (Walk, Fact, `_scan`, `_walk`, `_fixpoint`, the `runtime` table at 97-226) is shared by check_regions, check_meta_regions, and audit_regions; audit-only branches are 11 sites (238, 380, 399, 438, 494, 833, 855, 1032, 1058, 1263-1267). `_scan` (815-890) is an expression worklist and `_walk` (1093-1143) a statement recursion, not two walkers of one thing | 0 | region-* (24 files), comptime-declines-*/meta-*-regions (89 files), commands/graph/tests/certify.sh |
| H | quasiquote refold in `_lower_content` (src/comptime.x:1500-1503) | +36 est | test-lisp.x quasiquote cases, byte-identical .xlisp regeneration through tools/gen-lisp-init.py, stage compares, check-reference-lisp |
| I | CLI: the ~40 single-assignment cases of `_apply_option` (src/cli.x:894-984) become setter columns of `cli_options` (104-266); the value-shaped cases (color, include, define/undefine, xcc, lib-dir/library, rpath, pthread, framework/xlinker, dump family) stay as code; cli_package_options' admission switch (1013-1020) becomes a mask bit | -45 est | unittest/probes/run-cli-boundary.sh; compatibility diagnostics src/cli.x:270-282, 1050-1062 |
| J | `<lisp-late>` restart and the two lifecycle flags it needs (src/macros.x:1001-1002, 1229-1236, 1248; src/main.x:171-181, 371-379): the driver preloads once, as the parallel and dump paths already do | -50 est | examples/manifest.txt run entries, run-cli-boundary.sh, stage compares |
| N | MatchCache: replace the LRU list, generation counters, and relink-per-hit (lib/match.x:2115-2260 region) with a direct-mapped two-way table keyed by canonical pattern identity, keeping pin counts so eviction never frees a leased plan and keeping the admission memos (measured, map.md:1349-1352) | -80 est | test-match-cache.x, test-match-plan.x, bm-all match benchmarks |
| O | one typedef walker for `_resolve_key_helper`, `Sym.next_typedef`, `_normalize_declared_type`, `_var_tag_for_type_helper` (src/compiler.x:3557-3569, 3584-3591, 3724-3737, 3743-3764); one binding-facts installer for `Sym.declare`/`Sym.bind_identity` (3213-3239 vs 3250-3263); `_scalar_row` returned once to callers that want two facts (src/type.x:356-378; src/expressions.x:4222-4227) | -65 est | test-var.x, test-protocols.x, retired-var-tag-* fixtures, tag-scope-a/b probes, stage compares |
| P | Context export: block/bytes/buffer arms (lib/context.x:271-284) become one Block-view move; array and map rollback share one owner-restoring wrapper (230-256) | -20 | test-context.x, test-thread.x |
| Q | diagnostics: `_write_json` (src/diagnostics.x:232-246) builds one Map and writes `Var.json` of it; text renderer unchanged | -15 | test-diagnostics.x, run-cli-boundary.sh (--diagnostics-file) |
| R | one emit/write collector macro for etc/builtin-macros.x:1-25, etc/init.x:1-25, etc/lisp-bindings.x | -40 | byte-identical regeneration of etc/init.xlisp, builtin-macros.xlisp, lisp-bindings.xlisp |
| S | car/cdr family: etc/comptime.xlisp:126-130, 226-229 alias the etc/init.x definitions instead of redefining `List_caar`/`List_cadr`/`List_caddr`; lib/lisp.x:378-381 stays (native adapters) | -10 | test-lisp.x, check-reference-lisp |
| T | manifest setters (src/project.x:219-275) become a `(key kind offset)` table over `offsetof` with one setter; the three "structured-text readers" (map.md:522-523) read three formats (sections, six-field rows, JSON markers) and stay | -30 est | examples with x2c.toml manifests, run-package-install.sh |
| U | one identity hash helper (src/utils.x:287-294 vs src/build.x:99-119) | -10 | run-build-recovery, run-artifact-atomicity |
| V | small pairs: `_parse_postfix_dot`/`_arrow` over `_parse_field_name` (-10); `_symbol_expression`/`_adapter_symbol_literal` (-3); cons-cell boxing shared by src/literals.x:75-97 and src/expressions.x:2109-2129 (-15); `_attribute_since` linear scan (-10); autodiff `ad_forward_siblings`/`ad_reverse_siblings` one Map and the forward/reverse item walkers sharing the declaration and update cases (-35); `_lower_content`'s duplicated `_lower_expr` productions (src/comptime.x:1500-1506, open ledger, -27); X2CVarNumericInfo embedded in X2CVarNumeric (lib/varconvert.x:19-31, -5) | -105 | test-autodiff.x and the two autodiff examples, test-varops.x, test-var.x, stage compares |
| X1 | protocol adapter generation as one direction-parameterized template for `_generate_ordinary_protocol_adapters`, `_generate_protocol_thunk`, `install_generated_protocol_symbols` (src/protocol.x:1117-1147, 1927-1971, 2295-2343), and one classification pass shared by the symbol and AST phases | -70 est | test-protocols.x, *protocol-conflict*, macro-protocol-*, relative-adoption* fixtures, run-protocol-boundaries.sh |
| X2 | `_adoption_row` single row carrying `(storage path)` in place of the two-shaped key plus `_adoption_visibility` (src/protocol.x:177-220, 292-320, 464-504) | -30 est | tag-scope-a/b probes, relative-adoption* fixtures |
| X3 | printf scanner (src/transform.x:52-287): conversion letters and length modifiers as one table row each instead of the enum plus switch | -50 est | test-interpolation.x, test-var.x printf cases, fixtures with printf Var diagnostics |

Not removed after reading, with the reason:

- native-meta inventory (map.md:1120): live consumers, section 3.
- two incremental systems (map.md:1124): etc/x2c.mk is Make, outside the
  hand-authored count, and serves the repository build; src/build.x serves
  `x2c build`. Different consumers.
- lisp.native.target.rows hand rows (lib/lisp.x:1607-1808): an export list
  that must exist somewhere; generating it moves it.
- header/source partition (src/generate.x:357-602): the two-file model is
  architecture, out of this stance.
- machine.x shared enum and fences: splitting into two VMs adds a second
  builder; keep.
- `declared_typetags` (map.md:960): documented unit-scoped tags; open
  question, not a deletion.
- cache.x vs `_local_static`, diagnostics vs logger: deliberate
  (map.md:1147-1148).

Outside the count: commands/graph/lifetime.x (1,011 lines) keeps its own
region table and summary fixpoint (commands/graph/lifetime.x:165-185,
795-860) beside `Compiler.audit_regions`, which certify already calls
(commands/graph/x2c-graph.x:2605). Routing loop-allocation and lifetime
through the audit summaries would delete an estimated 700 lines of
commands/, which is C13 (map.md:1360-1361) and is not in the 80,370.

### By subsystem

| map section | files | before | after | reasoning |
|---|---|---|---|---|
| 2.1 front end | tokenizer, parse, frontend, collect, deps, sourceview | 5,341 | 5,321 | D (-10), `_attribute_since` (-10) |
| 2.2 syntax | ast, literals, expressions, statements, ast-rewrite | 6,637 | 6,609 | V postfix, symbol literal, cons cell (-28) |
| 2.3 macros/comptime | macros, comptime, meta, builtin-macros.x/.xmacro, init.x | 8,827 | 8,746 | H (+36), J (-50), `_lower_content` (-27), R (-40) |
| 2.4 Lisp and machine | lisp, lisp-machine, machine, hand-authored etc/*.xlisp, lisp-bindings.x/.xmacro | 5,530 | 5,510 | S (-10), R's third copy (-10) |
| 2.5 transforms | transform, lambda, cleanup, regions | 5,542 | 5,432 | E (-60), X3 (-50), G (0) |
| 2.6 backend | generate, cache, emit, format, diagnostics | 4,141 | 4,126 | Q (-15) |
| 2.7 driver | main, cli, build, project, toolchain, report, bootstrap, install, script, editor, utils, x2c-payload.x | 6,393 | 6,308 | I (-45), T (-30), U (-10) |
| 2.8 values | var family, string, list, array, map, typed-*, generics, buffer, block, common, and the 14 small modules map.md omitted | 12,443 | 12,438 | V varconvert (-5) |
| 2.9 match | match, match-recursive, match-machine, split, regex | 4,692 | 4,167 | A (-445), N (-80) |
| 2.10 runtime infra | error family, exception, scope, pool, logger, context, thread, mutex, dispatch, func, iter, lib, protocols.x, static-init, system-macros, scripting | 8,121 | 8,045 | B (-56), P (-20) |
| 2.11 services | file, path, process, json, scan, args, autodiff.xmacro/.x, diff, digest | 5,211 | 5,176 | V autodiff (-35) |
| 2.13 types/protocols/state | type, type-ledger, protocol, compiler | 7,492 | 7,282 | C (-45), O (-65), X1 (-70), X2 (-30) |
| total | | 80,370 | 79,160 | -1,210 (1.5%) |

machine.x is counted once, in 2.4. The 2.8 figure includes var-adapters,
var-ledger, var-unbox, varops.xmacro, list-generics, list-selectors,
typed-list, string-classify, string-number, native-scalar-types,
integer-ops, clibc, cmath, private-keywords (989 lines) that map.md's 2.8
total left out; 2.10 likewise adds error-private, error_init, thread-state,
protocols.x, static-init, system-macros, scripting (483 lines).

### The ceiling

Measurement-gated candidates, none in the base total:

| candidate | lines | gate |
|---|---|---|
| delete the AUTO tier (LispLower lib/lisp.x:2332-2960, lib/lisp-machine.x, the Lisp half of machine.x) and run the evaluator only | -1,260 | macro expansion time must stay under 2x; plans/archive/x2c-lowers-to-lisp.md:632-636 says the machine runs "essentially all" lowering calls, so this is likely over 2x and not admissible |
| drop AUTO speculative macro pre-expansion (lib/lisp.x:1855-1905, 2836-2944; lib/lisp-machine.x:378-385), excluding globally-dependent macros from AUTO | -150 | map.md:379-380's benchmark |
| drop lifetime warnings and the certify audit, keeping the meta error | -70 | not worth a documented-feature drop; listed for honesty |

With every gate passing the tree reaches about 77,700 (3.4%). The kernel
design reports 71,900 (11%) by deleting the comptime engine; a rebuild
that keeps every engine and tier cannot get near that, and a rebuild that
deletes the compiled Match engine in favour of the 445-line recursive
matcher would change the compiler's hottest path by more than 2x (the
admission memos alone measured 2.35x on literal matches, map.md:1349-1352).
The number therefore says: an architectural rebuild is justified only as an
engine deletion, and only where the deleted engine's measured speedup is
under 2x or is recovered elsewhere; reorganizing passes is not it.

## 6. Performance ledger

Instruments: build-cost score, shootout, bm-all, translation CSV
(agents/performance-checkpoints.md).

| dimension | expected change | payoff | measured by |
|---|---|---|---|
| compile throughput, parallel and dump paths | none: they already preload the library (src/main.x:376-378); all consolidations are call-structure changes over the same algorithms | smaller source | build-cost score before/after each batch |
| compile throughput, sequential translation of a Lisp-free unit | + one library preload per process (removal J); unmeasured today, bounded above by what the parallel path pays now, reduced by H's 3x smaller library | one lifecycle instead of a restart-by-exception | translation CSV on `x2c translate` of a single small unit |
| library load time at every compiler start | faster: reading ~3,000 generated lines instead of 8,770 (removal H) | direct | translation CSV, startup column |
| macro expansion time | equal or faster: AUTO folds constant quasiquote (lib/lisp.x:2622) and the evaluator walks one quasiquote instead of N `cons` calls; AUTO tier kept | direct | bm-all macro benchmarks, meta-functions timings |
| generated-code speed | none: emission unchanged; X1's template must reproduce byte-identical C, checked by the stage compares | none | stage-diff-all, shootout |
| Var ops | none | none | bm-all |
| Match hit path | equal or faster: no LRU relink per hit (removal N); eviction under pressure changes policy from LRU to two-way direct-mapped | smaller cache | test-match-cache.x pressure cases, bm-all match rows |
| Scope/Pool | none | none | bm-all |
| errors, logger, dispatch locking | none: same pthread calls behind one primitive (removal B) | one primitive | run-full-sanitizer.sh, test-thread.x |

No dimension is expected to regress toward the 2x limit; the one
unexplained-regression risk is J, which is why it carries its own row.

## 7. Bootstrap plan

Every removal is consumable by the checked-in bootstrap: no syntax changes,
no new runtime contract the generated C depends on. The order below keeps
each batch independently gated with `tools/gate-state.py ensure
agent-pr-check`, and is also the migration order if the work were staged:

1. lib-only batch: A (move the oracle, delete the module page), B, N, P,
   V's varconvert embed. Bootstrap unaffected; stage compares prove the
   compiler's own generated C is unchanged.
2. compiler consolidations that keep generated C byte-identical: C, D, E,
   O, X1, X2, X3, V's remaining pairs, Q, U, T, I. Each is verified by
   stage-diff-all plus the fixtures named in section 5.
3. H plus R plus S: change src/comptime.x, run tools/gen-lisp-init.py with
   builds/0 to regenerate etc/init.xlisp, etc/builtin-macros.xlisp,
   etc/lisp-bindings.xlisp, then `make build-safe`: lib/lisp.x embeds
   etc/init.xlisp verbatim (lib/lisp.x:85-86, 383), so bootstrap/ refreshes
   through the publication command. The differential checker must pass on
   the regenerated library forms (section 9).
4. J last, because it changes driver sequencing that repl, editor, and
   graph share (commands/repl/repl.x:353, src/editor.x:182,
   commands/graph/x2c-graph.x:3173 already preload unconditionally).

Self-hosting is unaffected: the current compiler is stage 0 throughout and
each batch's stage 1-3 comparison is the acceptance.

## 8. Language changes

None.

## 9. Risks and unknowns

- H's generated size (about 3,000 lines) is an estimate from the foreach
  examples; the cond/lambda wrappers around each lowered function remain.
  Refuted if the regenerated builtin-macros.xlisp is not under 4,000 lines.
- H requires examples/programs/literate-lisp.x's reader and evaluator to
  accept every quasiquote form the lowering emits, including splices; the
  differential checker runs on showcase.xlisp, not on the generated
  library, so a new checker input may be needed.
- J's preload cost for sequential single-unit translation is unmeasured;
  if it exceeds what a small script's whole translation costs, keep the
  deferral and drop J (the ledger loses 50 lines).
- N assumes test-match-cache.x pins eviction safety, not LRU order; if it
  pins order, the fixture changes and Gary decides.
- C's estimate assumes the shallow-only steps fit as a continuation; the
  drift map.md:1401-1403 asks about (skip_linkage_brace and script
  statements) is visible in both loops read here (src/compiler.x:1676-1683,
  src/parse.x:1958) and is not drift.
- X1 and X3 are the least certain estimates (-70, -50): template
  equivalence must be shown byte-identical on the stage compares, and the
  printf table must keep every diagnostic the fixtures pin.
- The thesis is refuted if a same-pipeline pass finds more than about
  3,000 lines; the reading here covered every section-3 row and the
  rebuild notes of every 2.x section, but string.x (1,771), the second
  half of match.x (2260-2677), and comptime.x's statement lowering
  (~1300-3435) were skimmed as map.md says, so an undiscovered duplicate
  there is the way the number moves up.

## 10. Claims

1. Hand-authored total is 80,370: src 41,950, lib 35,835 (72 files),
   etc 11,819 minus generated 8,770 + 235 + 229. (`wc -l`, 2026-09-26.)
2. lib/match-recursive.x is consumed only by unittest/test-support.x:5,
   58-78, unittest/test-match-plan.x:805, and
   unittest/benchmarks/match-capture-benchmark.x:4; lib/Makefile:8 lists it
   as optional; lib/match.x:26 calls it the optional reference. (grep.)
3. The three recursive-mutex blocks are lib/error.x:76-104,
   lib/logger.x:109-137, lib/dispatch.x:254-282, each 29 lines; scope.x
   uses PTHREAD_MUTEX_INITIALIZER at 122-133.
4. dispatch.x needs recursion: lib/var.x:372-375 holds the lock through
   `x2c_descriptor_thread_start_begin` then calls
   `x2c_descriptor_registration_frozen`, which locks (lib/dispatch.x:302-306).
5. logger.x needs recursion: `Logger.free` (synchronized, 662) calls
   `clear_sinks` (synchronized, 305) at 666; `log_event` (759) calls
   `Logger.log` (683) at 760; `Logger.shutdown` (817) calls `log` at 824 and
   `free` at 838.
6. regions.x has three entry points over one Walk: check_regions 1212,
   check_meta_regions 1237, audit_regions 1263; audit-only branches at 238,
   380, 399, 438, 494, 833, 855, 1032, 1058; consumers src/transform.x:1779,
   src/macros.x:2048, commands/graph/x2c-graph.x:2605.
7. `%(...)` reaches comptime as `(cons ...)`/`(append ...)` cells
   (src/literals.x:75-97, src/expressions.x:2109-2129) and comptime mirrors
   them one to one (src/comptime.x:1500-1503); the evaluator implements
   quasiquote at lib/lisp.x:2027-2046 and AUTO folds it at 2424 and 2622.
8. builtin_foreach_declare is 6 source lines (etc/builtin-macros.x:69-75)
   and 20 or more generated lines (etc/builtin-macros.xlisp:218-235).
9. The `<lisp-late>` path is taken only for sequential non-dump
   translations (src/main.x:371-379) and caught at src/main.x:177-180;
   editor, repl, and graph preload unconditionally.
10. The six adapter memo sites are src/lambda.x:236, 496, 577, 645, 703,
    786, each a 5-8 line try_get/build/store block.
11. `_shallow_parse_loop` (src/compiler.x:1669-1744) and `parse_top_level`
    (src/parse.x:1953-2032) test the same eight forms in the same order.
12. `_write_datum` (src/collect.x:979-1002) writes reader text and
    `List.repr` (lib/list.x:960) is documented as the re-readable spelling;
    freeze/thaw (src/compiler.x:1274-1343) transforms tokens and origins
    into portable Lists and never writes text.
13. `_apply_option` (src/cli.x:894-984) has about 40 cases that assign one
    field or push one flag.
14. The native-meta inventory has consumers at
    unittest/compiler-fixtures/meta-protocol-adoption.x:25,
    meta-protocol-default.x:21, lib/lisp.x:1803, src/build.x:462.
15. Four typedef walkers: src/compiler.x:3557-3569, 3584-3591, 3724-3737,
    3743-3764; duplicated binding-facts blocks 3213-3239 vs 3250-3263.
16. Region behavior is pinned by 24 region-* fixture files, 89
    comptime-declines-*/meta-*-regions files, and
    commands/graph/tests/certify.sh.
17. tools/gen-lisp-init.py regenerates each etc/*.xlisp from etc/{name}.x
    and etc/{core}.xlisp deterministically (tools/gen-lisp-init.py:23-46).
18. The reference implementation for the ceiling comparison is
    design-kernel.md's 71,900-line total from deleting the comptime engine.
19. plans/archive/x2c-lowers-to-lisp.md:632-636: the wordcode machine runs
    50,308 of 72,044 evaluator invocations in the lowering workload, so
    deleting the AUTO tier is not presumed to fit the 2x allowance.
