# Greenfield estimate: compiler back half and driver (map 2.3, 2.5, 2.6, 2.7)

Area: src/transform.x, lambda.x, cleanup.x, regions.x, cache.x, generate.x,
emit.x, format.x, diagnostics.x, main.x, cli.x, build.x, project.x,
toolchain.x, report.x, bootstrap.x, install.x, script.x, editor.x, utils.x,
macros.x, comptime.x, lib/meta.x, etc/builtin-macros.x and .xmacro.
Current total 24,389 lines (`wc -l`, dev, 2026-09-26). etc/init.x (166) is
costed in design2-engines.md and is not counted here.

Headline: 18,590 lines from scratch (-5,800, -24%). 2,935 of that is the
round-1 conclusion taken as given (comptime.x replaced by a ~500-line
staging module); the design of this area on its own removes 2,865 more
(-14% of the remaining 20,954). Half the area is at the floor and is listed
as survivors in section 5. The one structural change is that lowering,
lambda lifting and cleanup-region wiring become one walk with a per-node
fixed point whose output is ordinary C-shaped AST, so emit.x stops owning
`try`, `defer`, `vcompound`, `vpostfix`, `vseqcall` and `dstrvalue`. The
two-file output model, the region analysis, the macro expander's hygiene and
capture machinery, and the fingerprint build are kept, for reasons that are
fixtures and documented contracts rather than taste.

## 1. Feature and contract inventory

Map section 4 rows owned here, with the contract that fixes their size:

- Lowering of typed forms to C (transform.x, lambda.x): every row from
  "scalar declarations" through "protocol-backed direct updates" that names
  transform.x; Var boxing and operator dispatch through protocol members
  (transform.x:587-940); string interpolation (1055-1100); destructuring
  (408-550); printf-family Var lowering, documented at language.md:2571-2580
  with 9 fixtures (`printf-var-*`); `with`; `match`/`catch` case records.
- Lambdas, captures, typed callback adapters, Func bridges (lambda.x):
  language.md:2003-2028 (one thunk per source/target pair, reused per unit),
  language.md:2778-2886; cell allocation order (lambda.x:1309-1340), adapter
  argument materialization order (389-414); 35 lambda fixtures, 40
  adapter/func fixtures, unittest/test-lambda.x (705), test-func.x (799).
- Errors and cleanup (cleanup.x, transform.x:1123-1342, emit.x:511-712):
  language.md:3049-3120: try exit order catch-close -> finalizer ->
  frame-leave (cleanup.x:100-121); `break`/`continue` stop at the loop or
  switch; `return` saves its value first (628-640); goto into or across a
  region rejected (216-240); label in `finally` rejected (660-667);
  volatile qualification of locals a protected body writes, by name or
  through a held pointer (242-624; fixture let-volatile-address); 53
  cleanup/defer/goto/try fixtures, test-defer.x (389).
- Region warnings (regions.x): three codes at language.md:3401-3418;
  the model, exemptions and "How the check works" in guide/regions.md
  (per-unit summary fixpoint, `&box->value` borrows, `$let` write-back,
  typed-conversion copies); `check_meta_regions` hard error (regions.x:
  1237-1256); the audit surface commands/graph consumes (x2c-graph.x:2605,
  lifetime.x:78,225-414: `audit_regions`, `region_result`,
  `region_wrapper`, `has_region_row`); 6 `region-*` diagnostics fixtures.
- Backend: header/source visibility rules (generate.x:369-460; language.md
  "Source files and pragmas"), typedef promotion after a function
  (491-527), conditional-group balancing (569-602), aggregate typedef
  forwards (529-567), type-owned initialization and shutdown
  (language.md:3122-3162; generate.x:244-318), static prototypes and
  forward dependencies (1090-1127), definition rows for the editor and
  x2c-graph (765-878); literal cache with identity across header and source
  (cache.x:9-13), static-initializer ordering and cycle report (352-449);
  `#line` mapping (format.x:55-90); diagnostics de-duplication, limit
  notice, JSON Lines across forked workers (diagnostics.x:146-216).
  Pinned by 181 `.c`, 76 `.h`, 40 `.emit` and 413 `.diagnostics` sidecars.
- Driver: 11 commands and 81 option rows (cli.x:79-266), response files
  with UTF-8 validation and cycle detection (627-800), removed `-o` and
  one-dash diagnostics (270-282, 1052-1062), 12 help outputs pinned byte
  for byte by unittest/probes/run-cli-boundary.sh (1,660 lines);
  fingerprints with build-start race check and atomic publication
  (build.x:75-181, 855-896; probes run-build-recovery, run-artifact-
  atomicity); parallel workers by fork (main.x:226-275, utils.x:371-406);
  manifests, profiles, lockfile, `x2c new` (project.x); bootstrap payload
  verification (bootstrap.x:81-147; etc/cosmopolitan/verify-ape.sh);
  install bundle guard (install.x:166-181); script cache (script.x,
  build.x:1010-1127); editor one-shot query (editor.x:160-210).
- Macros and meta (macros.x, lib/meta.x, etc/builtin-macros.*): the whole
  of language.md:783-1400 and 1863-2028: 13 hole kinds, 7 result kinds,
  local definitions with captured binding identities, sequence holes,
  hygiene (1308-1378: fresh binding per expansion, file-scope spelling
  names the unit and outermost invocation, tag locals, `using`, `x2c.ident`
  completion of a same-scope prototype), decorators, keyword aliases,
  `$(import)` with cycle detection, native modules, the 48 `x2c_*`
  operations lib/meta.x declares, expansion limits (64, 10,000, identical
  recursion), the constructible forms (`named-type`, `declaration-bundle`,
  `default`, `declaration-recipe`, `default-forward`, `syntax-recipe`,
  `managed-init`, `falias`, `tadapt`). Pinned by 185 `macro-*`, 28
  decorator, 99 comptime/meta and 47 system-macro fixtures.

## 2. The design, component by component

Representation is unchanged: `Ast` is `List`, bindings are `(binding id
name)` rows, facts live in `semantic_binding_facts`. Every component here
is a kernel operation: each reads binding identity, types, lifetimes or
emission order. Nothing moves behind the macro boundary, for the reason
design-synthesis section 2 gives (the dispatcher is already one-line
delegations; a macro cannot ask for protocol resolution without lib/meta.x).

B1 lower.x (3,270): one walk `_lower(Walk, node)` replacing `_node`,
`_finish`, `_children`, `_sequence`, `_op_chain`, `Compiler.transform`
(transform.x:1487-1801, 315 lines), cleanup's `_rewrite`, `_bounded`,
`_inside`, `_transfer`, `_unwind`, `_function`, `_units` (cleanup.x:
126-150, 494-512, 640-781) and `_lower_nested_lambdas` (lambda.x:
1416-1436). At each node: apply the helper for its head until the result
is the same List (today's identity test, transform.x:1605-1617, now local),
then descend. Rewrites are strictly reducing (each removes an x2c head), so
the per-node loop terminates for the reason the unit loop did. The walk
carries cleanup's state (`regions`, `break_stop`, `continue_stop`,
`labels`, `return_type`, cleanup.x:36-42); a `try`, a rewritten `defer` or
a `localinit` pushes its record binding and leave-statements, `return`,
`break`, `continue` and `goto` splice the unwind exactly as cleanup.x:
640-731 does. Per function: pre-scan labels (167-207; a forward `goto`
needs the label's ancestry before the label is reached), prepare lambda
cells (lambda.x:1309-1360), lower the body, run the volatile analysis
(242-624, unchanged) over the region-marked body, then run the frame
sweep: `try`, `defer`, `vcompound`, `vpostfix`, `vseqcall`, `dstrvalue`
become ordinary AST (`declare`, `if`, `call`, `op &`, static declarations)
with templates in `%(...)` that spell what emit.x:511-712 and 1300-1325
spell as token lists today. `sigsetjmp`, `x2c_exception_push`,
`__builtin_unreachable` are calls; `static MatchCaptureSite arms[n]` is a
declaration. Lambda siblings queue in `Out.siblings` and are lowered after
the unit's forms, as `early_decls` are today (transform.x:1787-1797), so
generated names keep today's order (section 6, case 11). Helpers kept
verbatim: printf scanner (73-289), operators and protocol updates
(587-940), literals, segments, destructuring, raise, cast, defer thunk
capture (1123-1310), lambda lifting and cells, one adapter bridge (see
below), the volatile analysis, static regions (cleanup.x:390-420).
Adapters: the six compute-key/check/build/queue/store sequences under
`names.adapters` (lambda.x:236-246, 496-502, 578-633, 646-671, 707-715,
789-804) become one `_bridge(key, build)` memo plus one signature-
substitution template, the map's 150-250 estimate; argument
materialization order (389-414) is inside the template.

B2 regions.x (1,200): as today with the two worklist walkers merged
(`_scan` 821-892 and `_walk` 1093-1147 share the `at`/`expr`/`declare`/
`cons` cases) and `lowered_meta_regions` replay (1239-1243) gone.
The question asked: can regions.x be the coarser correctness-bearing
analysis, with certify kept honest as `incomplete`? No, and the reason is
the consumer set, not caution. The correctness-bearing case is only
`check_meta_regions` (a compile-time body returning the address of a
call-scope allocation hands the compiler a dangling pointer, regions.x:
19-21, 1237-1256). Everything else is warnings, but they are documented
warnings: `after-free` and `bad-free` need the `dead`/`ending` facts and the
`_end` path (795-820, 894-903); "a caller of a function that returns
`&box->value` sees its own borrow come back" (guide/regions.md "How the
check works") needs the `points`/`place` facts and the unit fixpoint
(1167-1210); the `$let` write-back exemption needs `restored`
(1001-1055). Removing any of them changes the 6 `region-*` diagnostics
fixtures and the guide. certify is already honest: `proved` requires every
reachable operation to be in the modeled subset (x2c-graph.x:2940-2968,
README:365-372), and map section 6 forbids broadening it. A coarser
compiler pass would shrink what certify can prove and would still need the
summary shape (`audit_regions` returns summaries the next project round
seeds, 1263-1275). So regions.x is a survivor at about its current size.
Go's escape analysis (cmd/compile/internal/escape, several thousand lines
by memory) is the nearest comparable and is larger.

B3 emit.x (1,250): the one bottom-up token printer, minus the frame and
dynamic-update emitters that B1 lowers (511-712, 1300-1325: -230), plus
one case: printing `(cache id)` records the id in the Emitter (+15), which
replaces cache.x's two after-the-fact id walks. Declarators (31-133),
precedence (1041-1160), match sites (423-490, 714-862; they read
`match_pattern_is_static` and are fine either side), local static once-init
(301-421) and the initializer-macro path stay. chibicc's codegen.c is about
1,500 lines for C to x86-64; emit.x prints C plus x2c's match and static
forms at the same order of size and is at its floor.

B4 generate.x (1,150): the two-file partition survives. The alternative
(a thin header of prototypes and typedefs, bodies in one source, or a
unity build) changes every one of the 76 `.h` sidecars, the headers that
commands/ and packages/ include, and the per-unit C compile that the
fingerprint build parallelizes (build.x:678-737). The rules it implements
are the documented ones (public objects `extern` in the header, defined in
the source, 419-431; tagged bodies published with an `extern` object,
405-422; static and post-definition items private, 604-695). What shrinks:
the `(pending ...)`/`(conditional ...)` marker lists (485-602) become a
per-node destination decided in one pass with the group rule "a group's
directive goes to each file holding one of its items" (-60); the cache id
walks move to B3 (-50); `_file_init` (244-318), `_static_prototypes`
(1090-1127), forward dependencies (880-1010) and definition rows
(699-878) stay.

B5 cache.x (600): `_collect_cache_ids`, `_cache_ids_in`,
`_rewrite_header_cache_refs` (508-558) go; the header prefix becomes the
header emitter's spelling of the ident. Static-initializer queues, the
deferred-kind rule and the cycle report (280-476) stay; they are documented
static-init ordering.

B6 format.x (187): survivor; the map calls it the model of minimal
machinery and nothing here disagrees.

B7 diagnostics.x (430): text and JSON renderers share one field pass
(232-291, -30); `DiagnosticsHold` (77-108) goes with the `<lisp-late>`
restart (section 8). De-duplication, limit notice and the JSON Lines
append-write contract stay.

B8 cli.x (850): one table. Each `CliOption` row gains a `kind` (flag,
string, path-list, cc-arg, ld-arg, cpp-and-cc, dump, count) and a field
selector, so `_apply_option` (894-984, 90 lines) becomes a 40-line kind
dispatch and `cli_package_options`' third switch (1013-1032) becomes a
masked walk over the same table. The help renderers (312-620) are mostly
literal text that the probe pins byte for byte; they survive at ~280.
Response files (627-800, 175) and the command parser (1064-1160, 100)
survive. lib/args.x (312) is the in-tree anchor for a declarative option
spec with a parser; cli.x's table, apply and parse total about 350 on top
of the pinned text.

B9 build.x (1,000): one incremental system, and it is build.x's. The
"second" one, etc/x2c.mk:62-82, is 20 lines of make that batch stale
sources into one translate call by timestamp; builds/stage.mk:122-175
repeats those rules for the two stage directories. Neither is x2c and
neither computes a fingerprint; making stage.mk include x2c.mk saves make
lines, not hand-authored x2c. Inside build.x the four fingerprint
spellings (`_translation_fingerprint` 315-340, `_compile_fingerprint`
582-591, `_action_fingerprint` 551-563, `_script_fingerprint` 1010-1038)
become one `_fingerprint(kind, rows)` over `_state_base` (-60), and the
identity hash duplicated in utils.x:287-294 is shared (-15). `_write_entry`
(450-470), which writes x2c source text for a module entry, is reused by
B14 for staging. Atomic publication, receipts and the script cache stay.

B10 project.x (720): the manifest reader (78-320) is a sectioned key=value
subset with multi-line arrays; lib/json.x at 570 is the anchor for a full
reader-writer, so 240 for this grammar is about right. The three
`_set_*_field` switches (219-290) become one field table keyed by section
(-40); lockfile, globbing, target requests and `new` stay. The map's
"three structured-text readers" are not one grammar: `install_rows`
(install.x:113-120) is 8 lines of split-and-filter and `_marker_string`
already reads JSON through lib/json.x; nothing to unify.

B11 toolchain.x (400), report.x (245), bootstrap.x (345), install.x
(400), script.x (113), editor.x (210), utils.x (380): survivors, each a
thin owner of one documented contract (map 2.7 "Must preserve"). utils.x
loses the duplicated hash (-15) and the root-discovery retry folds (-15).

B12 main.x (560): the `<lisp-late>` restart path (`_compile_file` 174-182,
held diagnostics 107-118, `macro_library_defer` branch 371-379) goes when
the parent Lisp session is built eagerly in `Frontend.open` (design-
synthesis section 3, "Shared session"); dumps, workers, chunks, package
module preload and external command dispatch (606-642) stay.

B13 macros.x (3,750): the expander's hygiene and capture rules are the
documented ones and nothing more; that was checked rule by rule. Hygiene
(2439-2576): fresh identity per expansion and file-scope spellings that
name the unit and outermost invocation (`_file_scope_name`, 2439-2463;
language.md:1310-1316), tag locals and provisional tags (2545-2576;
1319-1326), `using` fresh holes and the local-binder projection
(2499-2543; 1345-1352). Captures (2578-2840): the source/value/expression/
splice projections exist because `x2c.source.text` is defined only for a
complete captured argument (language.md:1868-1871) and a forwarded hole
retains its kind (1715-1717); the `construction` row carries Unit
requirements. Expansion (3757-3870): the three limits and identical-
recursion check are language.md:1359-1362; the semantic transaction
(3872-3885) is "a failed expansion leaves no provisional symbols". Hole
parsing, definition parsing, invocation argument parsing and target
definitions are grammar for 13 hole kinds and 7 positions. What goes: the
shared-library lifecycle flags and restart (1000-1050, 1185-1245: filling,
restartable, settled, imports, definitions, `shared_definition`) collapse to
a constructor that fills, freezes and adopts (-170); the meta import replay
(1350-1365, needed only because lowered Lisp definitions are session-bound;
-20); `install_meta_function`'s lowering branch and `x2c_comptime_lower`
(2045-2075, 956-963; -60); the `$compiler.targets` filter and lisp-bindings
glue (88-107, 1063-1075; -40); the two `call-stack` arms (2194-2201; -10).
Everything else, 3,750 lines, survives. No small reference implementation
exists for this contract; rustc's `macro_rules!` expander (compiler/
rustc_expand/src/mbe, on the order of 4,000 lines by memory, unverified)
handles fewer positions and no typed holes.

B14 stage.x (500): taken from design-synthesis section 3 as given:
retained lifting, folding and layouts (comptime.x:3130-3435, ~300),
comptime-only reachability (~60), staging through `_write_entry`, the
script-cache-shaped module cache, load, per-unit `x2c_module_reset`
(~110), REPL submissions (~30). `check_meta_regions` stays as the hard
error (B2).

B15 lib/meta.x (310): 48 `meta` declarations and their documentation
(56 comment lines); `x2c_comptime_lower` (315) goes. Survivor.

B16 src/builtins.x + etc/builtin-macros.xmacro (723): the foreach
(etc/builtin-macros.x:43-232) and class (233-694) expanders and
`builtin_scope_expand` (29-41) are ordinary x2c already, decorated by the
`$builtin.emit` collector (1-27) that exists only to feed comptime lowering
and goes (-27). The bodyless prototypes at 43-53 and 233-239 are today
Lisp helpers in etc/builtin-core.xlisp; as `meta native` x2c they cost
about +40. The .xmacro (57) gains the six alias rows (+6).

## 3. Line ledger

| component | current (files) | greenfield | anchor and reasoning |
|---|---:|---:|---|
| B1 lower.x | transform 1,801 + lambda 1,679 + cleanup 781 = 4,261 | 3,270 | driver: union of `_node` (185) and `_rewrite` (92) with one traversal skeleton, 250; helpers 1,300 kept by accounting above; lambda 1,680 -> 1,050 (adapter memo -200, nested walker -25, folds); volatile 380 and labels/static regions 110 kept; frames as templates +180 |
| B2 regions.x | 1,281 | 1,200 | walkers merged -60, replay -15; survivor otherwise |
| B3 emit.x | 1,469 | 1,250 | frame/dynamic-update emitters -230 to B1, cache recording +15; chibicc codegen.c ~1,500 comparable |
| B4 generate.x | 1,278 | 1,150 | markers -60, id walks -50, misc -20 |
| B5 cache.x | 709 | 600 | 508-558 and header rename -100 |
| B6 format.x | 187 | 187 | survivor |
| B7 diagnostics.x | 498 | 430 | hold -35, one field pass -30 |
| B8 cli.x | 1,232 | 850 | table+apply 350 (lib/args.x 312 anchor), help 280, response 175, misc 45 |
| B9 build.x | 1,138 | 1,000 | one fingerprint spelling -60, hash -15, misc -60 |
| B10 project.x | 815 | 720 | field table -40, folds -55; lib/json.x 570 anchor |
| B11 seven driver files | 2,171 | 2,093 | survivors; utils -30, install -24, toolchain -23 |
| B12 main.x | 689 | 560 | restart -40, deferred diagnostics -15, folds -70 |
| B13 macros.x | 4,160 | 3,750 | -300 lifecycle/lowering glue, -110 folds; the rest is documented rules |
| B14 stage.x | comptime 3,435 | 500 | given (design-synthesis section 3) |
| B15 lib/meta.x | 315 | 310 | survivor |
| B16 builtins.x + .xmacro | 694 + 57 = 751 | 723 | collector -27, Lisp helpers as x2c +40, aliases +6, fold -47 |
| total | 24,389 | 18,593 | -5,796 (-23.8%) |

Credible range 18,000 to 19,300. The wide items are B1 (helpers may fold
further or the frame templates may cost more than 180) and B13 (if the
capture projections could be reduced to two, another -100).

## 4. Rope trades (the brief's 2x)

| trade | expected factor | what it buys | measurement |
|---|---|---|---|
| Frames lowered to ordinary AST and printed by the general emitter instead of hand token lists | emission of `try`/`defer` units 1.05-1.15x; emission is a small share of translation, so <2% per unit | -230 lines in emit.x, one grammar for generation scaffolding, `--dump-transforms` shows C-shaped output | `time builds/0/x2c translate --dump-code src/parse.x >/dev/null` minus `--dump-transforms` time, before and after; translation CSV |
| Per-node fixed point in one walk | faster, not slower: removes k-1 unit walks, the sibling rounds, the cleanup walk and two cache walks | -1,000 lines of traversal skeletons | `make bm-build-scaling` against unittest/benchmarks/build-scaling-baseline.json; a regression is a defect, not a trade |
| Eager parent Lisp session | `x2c translate hello.x` 1.0-1.1x (a few ms of Lisp evaluation that today is deferred for units that never need it) | -210 lines of lifecycle flags, restart, held diagnostics | `time builds/0/x2c translate --out-dir /tmp/o examples/foreach.x` with `-j 1` (deferred today) and `-j 2` on one file (preloads today) |
| Native meta staging (given) | first `$name(...)` of an edited user meta group 100-300 ms instead of ~1 ms of lowering; shipped bodies linked, 0 | -2,935 | `unittest/probes/run-native-modules.sh` timing; `time builds/0/x2c translate examples/programs/magic/meta-functions.x` cold then warm cache |
| Regions, CLI, build, project, backend partition | 1.0 | lines only | build-cost score unchanged |

No trade here approaches 2x; the design does not spend the rope.

## 5. Survivors

At the floor, kept with their current lines (about 11,900 of the 18,593):

- regions.x core: types, runtime table (97-226), birth/flow/borrow
  (488-760), fixpoint (1149-1210), entry points; documented warnings and a
  consumer surface.
- cleanup.x volatile analysis (242-624): C's `siglongjmp` rule for
  automatic state, including writes through held pointers.
- transform.x printf scanner (73-289): documented feature with 9 fixtures.
- transform.x defer thunk capture (1123-1310): hoistable-type rule and the
  landing-frame fallback for transfers inside a finalizer.
- lambda.x cells (955-1360) and captured-lambda lowering (1474-1620).
- emit.x declarators, precedence, match sites, local static once-init.
- format.x whole; diagnostics.x report/limit/JSON contract.
- generate.x visibility partition rules, `_file_init`, static prototypes,
  forward dependencies, definition rows.
- cli.x help renderers and response-file reader; build.x publication,
  receipts, script cache; project.x manifest reader and lockfile;
  toolchain.x, report.x, bootstrap.x, install.x, script.x, editor.x.
- macros.x hygiene (2439-2576), capture patterns (2578-2840), hole and
  definition parsing (2839-3460), invocation and expansion (3535-3890),
  target definitions (3887-4160), SDK bodies (128-600), embed (807-960),
  native modules (1637-1830).
- lib/meta.x; the foreach and class expanders in etc/builtin-macros.x.

## 6. Hard cases and how the design handles each

1. try exit order (cleanup.x:100-121): the region record pushed on the
   walk carries its leave-statements in that order; the frame sweep spells
   them once per exit, as today.
2. break/continue barriers and `matchcases` (640-731): `break_stop`/
   `continue_stop` on the walk state, set by loop, switch and matchcases
   cases; unchanged logic, now inside the lowering walk.
3. return value saved before cleanup (628-640): same rewrite; the saved
   declaration uses `type.declaration_parts()`.
4. goto into a region or a sibling region (216-240) and forward goto:
   the per-function label pre-scan runs before the body is lowered, so a
   `goto` sees its label's ancestry; rejected as today.
5. label inside `finally` (660-667): checked when the `try` case runs.
6. volatile qualification (242-624): runs after lowering and before the
   frame sweep, because `_collect_preserved` recognizes `(try ...)` and the
   `written` list of `(defer ...)` (435-455) to know what a protected body
   writes. Ordering is a design invariant: lower -> volatile -> frame sweep.
7. defer capture thunks (transform.x:1123-1310): unchanged; the thunk is a
   sibling in `Out.siblings`, and `defer-ownr` facts keep the owner name.
8. lambda cell allocation order (lambda.x:1309-1340): the per-function
   entry step, before the body is lowered, as `prepare_lambda_cells` is
   called today from `_node`'s function case (transform.x:1631-1636).
9. adapter argument materialization order (389-414): inside the one bridge
   template; the memo key is the same (source, target) pair.
10. fixed-point termination and the `fixed` memo (transform.x:1601-1617):
    a node is visited once; the per-node loop stops at identity; `fixed`
    goes.
11. same C, same names: `fresh_name` counts per stem (compiler.x:633-640),
    so interleaving cleanup and lowering allocations does not renumber as
    long as each stem's order is preserved. Three stems need care. (a)
    `defer_env` is used both for the typedef at lowering time
    (transform.x:1257) and for the local at emit time (emit.x:519); today
    all typedefs of a unit are numbered before any local. The frame sweep
    therefore runs as one sweep over the whole unit after every function
    and sibling is lowered, at the point emit runs today; `builds/0/src`
    has 35 units and 10 of them contain `_x2c_defer_env_1` or higher, so
    the difference would show in real output. (b) `catch_arms`,
    `catch_site`, `catch_patterns`, `catch_pattern` are allocated in
    emit after the body and cleanup are emitted (emit.x:597-620), so a
    nested `try` numbers before its parent; the sweep allocates them
    post-order. (c) siblings are lowered after the unit's forms, as
    `early_decls` are today, so `lambda_*` and `defer_*` stems keep their
    numbers. With those three rules the 181 `.c` sidecars are unchanged;
    without them the change is a mechanical renumbering.
12. `.transform` sidecars: 38 fixtures declare the `transform` phase and
    13 of them contain `defer` or `try` forms; their dumps change from the
    private 5- and 6-field forms to C-shaped AST. These pin an internal
    dump, not behavior, and are updated with `make verify-fixtures-update`.
13. Header identity: `.h` output is byte-identical because partition
    rules, typedef promotion and forward insertion keep their logic; only
    the marker representation changes. unittest/probes/run-header-cache.sh
    (1,087 lines) pins the header cache and is unchanged.
14. Parallel workers and JSON Lines (diagnostics.x:206-216): untouched.
15. Regions before lowering: `check_regions` still runs on the typed unit
    (transform.x:1777-1779) before the one walk, and reads `$scope`,
    `$auto` and the `defer` beside them.
16. Editor and REPL consumers: `definition_rows`, `display_path`,
    `print_diagnostic`, `origin_location`, `audit_regions`, `region_*`,
    `has_region_row` and `lower_repl` are the back-half entry points
    commands/ uses (counted by grep over commands/*/*.x); all survive,
    `lower_repl` in B14's REPL path.

## 7. Experiments

1. Name-order rules (case 11): `builds/0/x2c translate --out-dir /tmp/o
   unittest/compiler-fixtures/defer-try-cleanup.x` and compare
   `_x2c_defer_env_*` and `_x2c_catch_*` numbering with the sidecar; then
   `grep -c 'defer_env_[1-9]' builds/0/src/*.c` to size real exposure.
2. Emission share (trade 1): `time builds/0/x2c translate --dump-code
   src/parse.x >/dev/null` versus `--dump-transforms`, five runs each; the
   difference bounds what the ordinary-AST frames can cost.
3. Walk count payoff (trade 2): `make bm-build-scaling` on the current
   tree for the baseline score, repeated after B1 lands.
4. Eager parent (trade 3): `time builds/0/x2c translate --out-dir /tmp/o
   examples/foreach.x` with `-j 1` and with `-j 2 examples/foreach.x
   examples/foreach.x` (the latter preloads the parent today).
5. Region equivalence: `make verify-fixtures` restricted to `region-*`,
   then `builds/0/libexec/x2c-graph certify --root certify_safe
   commands/graph/tests/fixtures/certify.x` must still exit 0 (`proved`).
6. Header and CLI pins: `unittest/probes/run-header-cache.sh`,
   `unittest/probes/run-cli-boundary.sh`, `make verify-fixtures` (76 `.h`,
   181 `.c`).
7. Transform sidecars (case 12): `grep -l 'defer\|try'
   unittest/compiler-fixtures/*.transform` lists the 13 to regenerate.
8. Fixed-point rounds today: count `_sequence` iterations per unit with a
   temporary counter in transform.x:1780-1784 over `src/*.x` to size what
   trade 2 removes (the archive notes ~0.1 s per unit for the fixed point).

## 8. Drops

Each is machinery, not a documented feature; no map section 4 row drops.

- `<lisp-late>` restart and held diagnostics: macros.x:1221-1244, main.x:
  107-118 and 174-182 and 371-379, diagnostics.x:77-108, ~110 lines.
  Premise: the parent session is filled eagerly (design-synthesis J).
- comptime.x lowering: 2,935 net, given.
- meta import replay, macros.x:1350-1365: ~20; lowered definitions are no
  longer session-bound.
- Lisp step and depth budget arms for meta calls, macros.x:2194-2201: ~10;
  a runaway native body hangs as `meta native` does today (synthesis).
- `lowered_meta_regions` replay, regions.x:1239-1243 and comptime.x:
  3018-3024: ~15.
- `fixed` memo and its reset, compiler.x:110-113 and transform.x:1601-1610:
  ~15 (counted in front/state, noted here because B1 makes it dead).
- 13 `.transform` sidecars change shape; 0 lines, no feature.

## 9. Risks

- Name reproduction (case 11) is the largest risk to "same C": if the
  three stem rules are not enough, the .c sidecars renumber; the stage 0-3
  comparison is unaffected because it compares the new compiler with
  itself, but reviewing a 181-file renumbering is real cost.
- The volatile analysis must run on region-marked forms; putting the frame
  sweep earlier silently loses `volatile` and the fixture
  let-volatile-address would catch only one shape of it.
- B13's count assumes the capture projections (four per hole) are all
  load-bearing; if forwarding could be expressed with two, macros.x drops
  another ~100, but the `Function` hole's return/declarator projections
  (macros.x:2606-2616) argue against it.
- B14 is given; if staging needs more than the ~110 lines the synthesis
  allots (module reset for `meta static`, hash-gated linked rows), B14
  grows, not this area's other components.
- The per-node fixed point assumes every helper is idempotent on its own
  output at the node; today's unit-wide loop tolerates a helper that needs
  a sibling's rewrite first. Nothing read suggests such a helper, but a
  hidden one shows up as non-termination or wrong C and would be found by
  the fixture run, not by reading.
- Not verified: the outside sizes quoted from memory (chibicc codegen.c,
  rustc mbe, Go escape); in-tree anchors carry the estimates.
