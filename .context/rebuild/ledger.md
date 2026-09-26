# Rebuild ledger: verdicts, reconciled lines, trades, experiments

Research spike, 2026-09-26. Advice to Gary; nothing here is a decision.
Inputs: .context/rebuild/design-synthesis.md (round 1, subtractive), the
five greenfield designs (design2-values, -infra, -engines, -front, -back),
the 23 claim verdicts on the synthesis, and current source read where the
two estimates disagree. `file:line` cites current `dev`; counts are `wc -l`.

On-disk today: src/ 41,950; lib/ 35,878; etc/ hand-authored 2,585 (11,819
minus the generated builtin-macros.xlisp 8,770, lisp-bindings.xlisp 229,
init.xlisp 235); total 80,413. The map's 80,404 is used as the base of every
table below so the three estimates share one denominator.

## 1. Synthesis claims: verdicts and their effect

| id | verdict | correction that matters | effect on the synthesis |
|---|---|---|---|
| C1 | partly | src/comptime.x:70-3089 holds 140 function heads, 133 lowering, 7 other (not 117/112/5); the two omitted entry points have external callers: `Compiler.lowered_meta_regions` (src/regions.x:1239) and `Compiler.lower_meta_initializer` (src/macros.x:1578) | stage.x's reset entry must own `meta static` initializers, which comptime.x:3089 lowers and macros.x:1578-1580 evaluates and `C.mgdefine`s today; +30 to the stage.x budget (500 -> 530). The retained kernel (3130-3435: lifting, `check_meta_call` 3311-3321, layouts) is as cited |
| C2 | partly | three region boundaries wrong or gapped (lib/lisp.x:301-548 struct and canonical-name block, 1091-1109 helpers, 1815-1831); "survivor 2,000; drop ~1,500" does not sum to 3,190 | re-derived by subtraction: 3,190 - AUTO 655 (2303-2957) - bridge 194 (107-300) - speculation 56 (1855-1910) - slots and typedefs ~50 - comptime natives 167 (1104-1270) - frame bookkeeping ~40 - hand rows 100..150 + memo 25 + trampoline 60 = 1,930-2,010. The "~1,500 drop" was AUTO across lisp.x and lisp-machine.x (1,190 + 480). Band across designs: 1,750 (engines, rows generated) to 2,400 (kernel, rows kept). No change to the total |
| C3 | holds | - | stage-0 rule and the step-0 prerequisite stand |
| C4 | partly | ranges are 3311-3321 and 1945-1984 | none |
| C5 | partly | native-meta rows are written by `Compiler.record_native_meta_effect` (src/macros.x:1617-1626) from src/compiler.x:1217 and :1231, not parse.x:1993/2010 | the step-0 flag edits `_shallow_finish_declaration` for the row and parse.x:2018 for the runtime form; still ~20 lines, different file |
| C6 | partly | fork and child loop are src/main.x:243-248 | none |
| C7 | holds | - | reset design, platform drop, linked route stand |
| C8 | holds | - | the per-unit reset is a documented obligation |
| C9 | refuted | `check_meta_regions` (src/regions.x:1237-1256) also carries the lowering-cache preamble (1238-1246), seeds `.summaries` from the cross-session `c.meta_regions` map (src/compiler.x:140; written at comptime.x:2970, macros.x:1931, compiler.x:343/2004) and reports only `w.warnings[0]` | description corrected, lines unchanged: the replay (1239-1243, comptime.x:3018-3024) goes (-15, already booked); the summary map stays because macros.x:1931's native-meta summary path fills it for native rows, which is the linked-or-staged case |
| C10 | holds | - | native raises reach `_evaluate_meta_value`'s catch |
| C11 | partly | 156/133, not 157/132 | none |
| C12 | partly | "82" does not reproduce: this pass counts 88 fixture sources with a bodied non-native `meta` (18 of them `comptime-declines-*`), 2 `meta native`; cold cost at the design's own 100-200 ms per group is 8-17 s, not 12-20 | performance row only |
| C13 | refuted | the cited shares are an unmerged branch's "now" column; current dev matches the "before" column: compile-time Lisp 4.1% (src) / 3.8% (lib), macro expansion 11.1% / 14.6%, Match 10.5% / 10.4% (plans/archive/comptime-x2c-generalization.md:1033-1036) | (a) the steady-state win of native execution is understated, not overstated: the Lisp share that goes native is ~4%, not ~2%; (b) the AUTO-off rope trade's worst case is 2 x 4.1% = +8% src, +7.6% lib, not +3%/+2%; (c) the "re-adopting quasiquote" objection is moot: the synthesis deletes the lowering and vetoes the quasiquote refold (section 5) |
| C14 | holds | - | the settling measurement is migration step 1 |
| C15 | holds | - | the +25 memo pays for itself |
| C16 | holds | - | AUTO's 3.4x was measured on lowered x2c |
| C17 | partly | `_finish` (src/transform.x:1524-1536) and its call at 1767 fall outside the citation | the one-walk design must carry the `_finish`/`_children`/`_sequence` descent; back B1 does (transform.x:1487-1801, 315 lines); none on lines |
| C18 | holds | - | `x2c_comptime_lower` withdrawal needs no migration |
| C19 | holds | - | lib/lisp-init.x plus ~27 bind rows keeps the runtime vocabulary |
| C20 | partly | src/lambda.x:236-249 is 14 lines; the 5-8 line idiom is at 496-503 | E stays -60: the memo idiom is ~8 lines at six sites; the 14-line site's extra lines are facts and `add_early` |
| C21 | partly | filter at src/macros.x:1066-1068; path selection is `_native_meta_targets` 536-554 (543); five aliases in etc/builtin-core.xlisp:27-33, the sixth at 34 | none; U7 still bounds the hand-row saving |
| C22 | partly | src/editor.x has no "group-hash argument" | the editor row's dependency is uncited; the cache keying of a unit's meta group needs its own citation (src/cache.x, generate.x) before it sequences editor work |
| C23 | partly | `with` is src/statements.x:571-614 + 522-530 = 53 lines | none; `with` stays kernel |

Corrected synthesis total: 73,118 + 30 (stage.x reset entry) = about
73,150, band 72,900-73,500 from the lisp.x row alone. The verdicts corrected
citations and characterizations; none moved a ledger row by more than the
row's own precision. Every verdict's substance (the second backend is
deletable, its retained kernel is ~300 lines, the region hard error stays)
survived.

## 2. Reconciled line ledger by map subsystem

Columns: current (map), round-1 synthesis (subtractive), greenfield (the
five designs mapped back onto the map's subsystems; autodiff relocated,
match-recursive as the engine, every rope trade taken). The judgment column
gives the number this ledger finds credible and why.

Mapping of greenfield areas onto subsystems: front K1-K12 -> 2.1, 2.2,
2.13; back B1-B16 -> 2.3, 2.5, 2.6, 2.7; engines -> 2.4 (lisp, etc/,
x2c-payload.x 348 unchanged), 2.9; values -> 2.8 plus dispatch.x (2.10) and
eleven small lib files ("other"); infra -> 2.10 minus dispatch, 2.11, ten
small lib files. etc/init.x (166, map 2.3) is replaced by ~100 Lisp lines
inside engines' init-core (2.4). "other" is the 1,773 lines of lib files the
map assigns to no subsystem (system-macros.xmacro 146, private-keywords 5,
and 21 small files); the map's 1,792 differs by its 43-line overcount.

| subsystem | current | synthesis | greenfield | judgment |
|---|---:|---:|---:|---|
| 2.1 front end | 5,341 | 5,291 | 4,450 | credible 4,950. Named greenfield cuts: tokenizer loop fold -30, frontend glue -60, `_write_datum` -20, T3 parse-then-bind -150 (src/parse.x:2059-2265 the one installer), name slots -40, shared top-level dispatch -60; the rest of collect.x 1,053 -> 870 is unnamed. The chibicc anchor (~900 lines for C11 declarations) has no install path; x2c's `bind_syntax` (parse.x:2343-2560) is the part no comparable implements |
| 2.2 syntax | 6,618 | 6,580 | 4,930 | credible 5,880. K7 expressions 4,388 -> 3,000 is the softest number in the spike: parser -170 (the design's own Pratt count is -35, expressions.x:952-970, 2470-2523); resolver -450 of which -150 is the 33 `<macro-expr>` sites (verified: 33 expressions.x, 10 macros.x, 4 literals.x, 1 parse.x) and -300 unnamed; conversion -175 from one 325-line function (4053-4378) whose predicates a rule list keeps; initializers -330 from helpers 3419-3823 (~400 lines) that mix layout, ordinal, scalar-row and adapter concerns; printf/iter/slices -180 unnamed. Credit -540 (K7 3,850), K6 650, K8 1,120, K9 260 |
| 2.3 macros and comptime | 8,818 | 5,420 | 5,283 | credible 5,330; the two agree within 140 (stage.x 500 -> 530 after C1, macros.x 3,750 in both, builtins 717 vs 723). Both rest on L2 and U1. init.x moves to 2.4 |
| 2.4 Lisp | 5,338 | 3,210 | 2,958 | credible 3,200: lisp.x 1,950 (band 1,750-2,010, section 1 C2), etc/ 900 (init-core 280, lisp-values 350 with the meta-row derivation gated on U7, lisp-bindings 190, forwarding 90), x2c-payload.x 348. Both assume AUTO off (U2) and native meta (U1) |
| 2.5 transforms | 5,542 | 5,157 | 4,470 | credible 5,150. The 687 gap is B1: lambda.x 1,679 -> 1,050 with only -85 named (memo -60: the six sites are src/lambda.x:236-249 (14), 496-503 (8), 577-633 (~57, memo 8), 641-671, 703-715, 786-804; nested walker -25). The rope table's "-1,000 skeletons" is B1's whole delta; the skeletons are ~275 lines (transform.x:1471-1536, `_node` 1590-1774, 1776-1801) plus ~180 (cleanup.x:126-150, 494-512, 640-780) replaced by ~250: -200. Frames as templates +180 arrive from emit.x. regions.x 1,281 -> 1,206 (walker merge -60, replay -15) in both |
| 2.6 backend | 4,141 | 3,985 | 3,617 | credible 3,650. Beyond the synthesis's -141 (cache-id walks, partition markers) the greenfield moves the try/defer/vcompound emitters (src/emit.x:511-712, 1300-1325, -230) to lower.x (+180) and drops `DiagnosticsHold` (77-108, -35) with the eager session; net -100 more |
| 2.7 driver | 6,045 | 6,020 | 5,223 | credible 5,770. cli.x 1,232 -> 850 is not in the file: the 81 rows (104-266), the byte-pinned help (312-620, unittest/probes/run-cli-boundary.sh) and response files (627-800) stay; `_apply_option` 894-984 (90 -> 40) and the package switch 1013-1032 are the named cuts (-65). build.x one fingerprint (-60), project.x field table (-40), main.x restart (-55) are plausible; +60 for the staged-module cache in both |
| 2.8 values | 11,454 | 11,449 | 8,704 | credible 10,000. The greenfield's 30-file 13,214 -> 10,010 carries ~1,100 lines the brief excludes: comment shortening in string.x (-300) and list.x (-170), and unexplained deltas (var.x -331 with -103 named; common.x -254 with -90 named; var-tags "tighten comments" -45). The mechanism that is real is C8: array.x:64-460 (25 methods) and map.x:114-445 (22 methods) twin `$array.typed.family` (lib/array-generics.xmacro:345-641) and `$map.typed.family` (map-generics.xmacro:325-573); instantiating them with three hooks is worth about -1,000 if the hooks inline (experiment E5). Format table, dispatch folds, Bytes twins add ~-300. The synthesis's -5 is too low: it never read string.x, array.x or map.x (its own note in 2.8) |
| 2.9 match | 5,232 | 4,567 | 2,329 | credible 4,570 unmeasured; 2,330 if E4 and E9 pass. The whole gap is two rope trades: the recursive engine (-2,750 including MatchLower 1047-1667, 621 lines; match-machine 541; machine 540; relocation 445) and the plan table (-480). No recorded recursive-vs-machine translation factor exists in plans/ or unittest/benchmarks; the `recursive` lane of match-capture-benchmark.x measures it per family but stores nothing |
| 2.10 runtime infrastructure | 7,638 | 7,562 | 5,887 | credible 6,400. Verified in source: one Scope plus two Pools per error record (lib/error.x:579-585), five value-walk copies (error.x:605, 751; logger.x:549; context.x:267; list.x:95), the two-stack reconciliation functions (error.x:358-417, 1041-1086, 1346; exception.x:92-115). The one-Pool record and the walk are concrete (-300 with comments); the frame-chain merge (ErrorHandler, ExceptionFrame, X2CCleanup into one chain) is a design whose only proof is a prototype against test-error and test-exception. Credit error group 1,719 -> 1,150, region.x merges -200, logger -100, context -150, dispatch 932 -> 760 (values C3) |
| 2.11 services | 4,953 | 4,918 | 3,242 | credible 4,440 with autodiff kept as one mode-parameterized walker (1,150, the map's own rebuild note); 3,290 if relocated to packages/ (its only runtime reference is the include at lib/lisp.x:36; the consequence is that its fixtures leave `make check`). Services trim 3% (-95) |
| 2.13 types, protocols, compiler.x | 7,492 | 7,167 | 5,890 | credible 6,700. Frames for SymTxn (compiler.x:2545-2661, ~120 lines of copy-on-begin) -100 credited at -70 (tombstones, `_replace_transaction_map` 2605-2614); one typedef walker over 3557-3790 -35; shallow loop 1669-1744 deleted -130 credited at -100 (T7 renumbers fixtures); K11 -508 of which -300 is unnamed "spelling folds" (34 uses of `_type_spelling`/`_member_spelling`/`_base_name`) credited at -250; K12 -235 credited at -115 |
| other | 1,792 | 1,792 | 1,576 | credible 1,640: varops.xmacro -79 (values C2), error-private and error_init folded into error.x -55; list-selectors -63 and the TagId checks -45 need the front end to collect macro-generated declarations in the shallow pass (cross-area, unbooked) |
| total | 80,404 | 73,118 | 58,559 | credible 67,680 |

Reading of the table. The synthesis and the greenfield agree on the one
engine deletion (2.3, 2.4) and on the driver being near its floor (2.7).
They disagree where the greenfield's number comes from an outside anchor
plus unnamed folds (2.2 expressions, 2.13 protocols, 2.5 lambda.x, 2.7
cli.x), where the greenfield counted comment compaction (2.8), and where it
took a rope trade the synthesis declined (2.9). The credible column credits
every named deletion with a file:line, halves unnamed folds, excludes
comment compaction, and books no unmeasured trade.

## 3. Rope trades across all designs

Every trade proposed anywhere, ranked by lines saved per unit of risk. Risk
is the worst-case regression the design itself bounds on its own
instrument, in percent of whole translation where the trade touches the
compiler, floored at 0.5 for "expected faster"; the score is lines / risk.
Lines in parentheses are this ledger's credible figure where it differs.

| rank | trade (design) | lines | expected factor | what it buys | measurement | risk | score |
|---:|---|---:|---|---|---|---:|---:|
| 1 | native meta execution: staged or linked bodies replace comptime lowering (synthesis L2, back trade 4, engines "under native meta") | 2,935 stage.x + 604 comptime.xlisp and natives + generated 9,234 not counted | shipped bodies 1.0x; first `$name(...)` of an edited user group 100-300 ms vs ~1 ms; REPL submission 100-300 ms (past the rope for that consumer); cold verify-fixtures +8-17 s per stamp; steady state -1 to -4% (C13 corrected) | one execution model, no subset, no second backend, no wordcode for Lisp | E1 (U1), unittest/probes/run-native-modules.sh, cold/warm `x2c translate examples/programs/magic/meta-functions.x` | 3 | 1,180 |
| 2 | Array and Map as typed-family instantiations with three hooks (values 2) | 840 (1,000) | 1.0x; map-get above 1.1x is a defect | one public layer for five families | E5: `make bm-var` map-get, `make bm-varops`, hash-table/direct/compare.py | 1 | 840 |
| 3 | no Lisp wordcode tier: AUTO, lisp-machine.x, machine.x's Lisp half go (engines 2, synthesis U2) | 2,070 | 1.1-2x per hot lambda; whole translation <= +8% src, +7.6% lib at the corrected 3.8-4.1% share, less under native meta; embedded runtime Lisp 1.1-1.5x; comptime-heavy units 1.5-3x only if lowering is kept | one evaluator, no speculation, slots, guards | E2, run-lisp-auto-benchmark.sh evaluator-hit vs prepared-hit | 4 (8 if lowering kept) | 520 |
| 4 | eager parent Lisp session; `<lisp-late>` restart, lifecycle flags, DiagnosticsHold go (back 3, synthesis J) | 320 | 1.0-1.1x on a small unit (a few ms of fill, ~650 Lisp lines under native meta) | a constructor instead of restart-by-exception | E12 | 1 | 320 |
| 5 | one lowering walk with a per-node fixed point (back 2, synthesis passes) | 250 skeleton (B1 books 990) | expected faster: removes k-1 unit walks, sibling rounds, the cleanup walk, two cache-id walks | walk-owned cleanup state, no `c.fixed` | E7, `make bm-build-scaling` | 0.5-1 | 250-500 |
| 6 | initializer subobject cursor (front T5) | 330 (150) | 1.0x | one cursor | initializer-* fixtures | 1 | 330 |
| 7 | runtime-pattern plans in a private direct-mapped table (engines 3) | 480 | <= 1.1x hit lane, <= 1.3x cold, < 1% translation (31 of 1,254 arms are dynamic, verified) | no LRU, leases, generations, memos; contradicts the measured memo decline (2.35x) with a new argument: the hit is the memo, the walk runs only on a miss | E9 | 2 | 240 |
| 8 | recursive Match engine instead of wordcode (engines 1) | 2,750 | 1.3-2.0x per structural match; +4 to +12% whole translation at the 10.4-12.5% share | one engine that is its own reference; no capacity fences | E4 | 12 | 229 |
| 9 | environment frames replace copied semantic transactions (front T1) | 100 | < 1.0 (O(1) begin vs O(scope) map copy, compiler.x:2565-2572) | frames | E8 | 0.5 | 200 |
| 10 | conversion as an ordered rule list (front T4) | 175 (60) | 1.0x | documented order made explicit | c/h fixtures | 1 | 175 |
| 11 | one top-level classifier with skip-body mode (front T7) | 130 | 1.0x; collection still token-skips bodies | one dispatcher, drift closed | E10, run-header-cache.sh, run-symbol-snapshot.sh | 1 | 130 |
| 12 | `$native.update` through ordinary crossings (values 3) | 114 | 1.0x once `$type.var` is inline; 1.5x on 14 adapters if boxing stays variadic | no 14-row boxer table | E11 plus a varops-hot-paths row | 1 | 114 |
| 13 | parse-then-bind declarations (front T3) | 150 | <= 1.05x on declaration-heavy units | one installer | translation CSV on src/parse.x, lib/x2c.x | 2 | 75 |
| 14 | templates as unresolved syntax, `<macro-expr>` dropped (front T2) | 190 (60 if the macros design disagrees) | <= 1.2x macro expansion x 11-15% share = +2.2-3% | no deferred typing state | `make bm-build-scaling`, typed-array.x vs emit.x wall | 3 | 63 |
| 15 | Buffer lazy line state (values 1) | 60 | <= 2x buffer-indent-80; emitter flat | one representation of line state | E14 | 1 | 60 |
| 16 | protocol resolution as ranked clauses (front T6) | 55 | 1.0x (cached per participant/member) | reads like protocols.md:233-241 | `--dump-conformance lib/x2c.x` identical | 1 | 55 |
| 17 | Pool depot removal (infra optional) | 50 | <= 1.1x pool-malloc-free and raise-catch; frees 50 MB retained backing | one storage path | E15 | 1 | 50 |
| 18 | try/defer/vcompound frames as ordinary AST printed by the general emitter (back 1) | 50 net (-230 emit, +180 lower) | 1.05-1.15x emission, < 2% per unit | one grammar for scaffolding | E13 | 2 | 25 |
| 19 | tail-call trampoline in `_call_lambda_slots` (engines 4) | -60 (addition) | neutral to faster | `(cd 100000)` in one frame without the machine; mandatory if lowering is kept | test-lisp-auto.x:938 | 0.5 | - |

Declined in the designs and recorded so they are not re-proposed: Pool
slabs as header-linked Scope allocations (350 lines; 1.3-2x list-cons-miss,
gives up pool.x:96-99 and 136-147); one engine for Regex and List.match
(would grow, engines 2.5); numeric operators through descriptor rows
(costs the i32/f64 fast lanes); dropping the 256-byte intern probe (25
lines; 1.5-2x intern-duplicate); dropping `Var.equal`'s row shortcut and
`Var.hash`'s unbox; `$map.var.family` key fast paths (map section 6 "must
preserve"); parsing bodies during collection (~3x collection cost).

Two consumer regressions ride on rank 1 and need Gary's yes independent of
any measurement: REPL submission latency 100-300 ms against ~1 ms, and the
AUTO fields of `:stats verbose` (commands/repl/repl.x:126-140, 369-371).

## 4. Experiments to run now against builds/0

Ranked by the ledger lines each decides. Each names the patch in a scratch
copy or worktree, what to time, and the number that decides it. Baselines
come first on the unpatched tree; the build-cost score's repeat noise is
about 4 points (agents/performance-checkpoints.md:49-51), the translation
CSV's a few percent.

E1. Settling probe U1 (decides ~5,500 lines: stage.x replacement 2,935,
comptime.xlisp and natives 604, the precondition of E2, and the generated
9,234). In a worktree, spell the row-lookup helpers of lib/var-tags.xmacro
that reach no x2c_* operation `meta native` (candidates: `_tag_rows` 145,
`_tag_id`..`_tag_unsigned` 152-161, `_tag_numeric_rows` 205,
`_tag_decode_rows` 254; first confirm their runtime forms are linked:
`nm builds/0/libx2c.a | grep -i tag_rows`); `make build-safe` in that
worktree. Time `builds/0/x2c translate --out-dir /tmp/lib-x lib/*.x` in one
process, five runs, baseline and probe, plus `SAMPLES=7
unittest/benchmarks/run-compiler-translation.sh` medians. Decides: probe
median <= baseline keeps the thesis; any slowdown refutes native execution
for the ledger scan and the design reduces to about 77,700. The plan's
3.07 s figure is stale; the baseline is re-measured, not quoted.

E2. AUTO off, whole translation (decides 2,070 hand lines plus 995 of
test-lisp-auto.x). Patch src/macros.x: delete `(void) shared.auto_prepare();`
at 1198, call `shared.auto_disable(1)` after `Lisp.kernel()` at 1163 and
`_.macro_lisp.auto_disable(1)` after the adopt at 1257 (`_auto_apply` reads
the evaluating session, lib/lisp.x:2836-2843). Rebuild stage 0. Time:
run-compiler-translation.sh (SAMPLES=7), `time builds/0/x2c translate
--out-dir /tmp/lib-x lib/*.x`, `time builds/0/x2c translate --out-dir
/tmp/ad unittest/test-autodiff.x`, and `unittest/benchmarks/
run-lisp-auto-benchmark.sh` for evaluator-hit against prepared-hit.
Decides: src/lib medians <= 1.05 and lib/ wall <= 1.08 take the trade; the
autodiff ratio (expected 1.5-3x while lowering exists) says whether E3 must
land before native meta does.

E3. Expansion memo (decides the +25 line addition and the E2 autodiff
regression). Prototype in `_apply_lambda` (lib/lisp.x:2166-2174): a Map from
raw-form identity to expansion, guarded by lambda identity, cleared on `def`
and `set_global`. Repeat E2's timings; time the comptime-autodiff fixture
(753 ms recorded); run `x2c script examples/programs/check-reference-lisp
--build` and unittest/test-lisp.x. Decides: the 505 -> 186 ms case
reproduces and the checker stays byte-identical.

E4. Recursive Match engine, whole translation (decides 2,750). Patch
`MatchPlan._capture` (lib/match.x:1786-1793) to call
`match_recursive_try_capture(m.layout, input, captures)` and include
lib/match-recursive.x; `make build-safe` in a worktree. Time: SAMPLES=7
run-compiler-translation.sh in both trees, `make bm-build-scaling`,
`unittest/benchmarks/run-match-capture-benchmark.sh` for the per-family
recursive-vs-prepared ratios it already produces. Decides: translation
median <= 1.12 keeps the trade (an upper bound: the patched engine still
copies 2.3 KB states, match-recursive.x:107-115, 143-163); above 1.3 the
engine needs fused head and scan loops (~120 lines) or the trade is dead.

E5. Array and Map hook inlining (decides ~1,000). Scratch lib/array.x:
replace lines 64-460 with `$array.typed.family(Array, Var, void, "Array")`
plus three hook functions (validity, missing answer, slot update); build
with builds/0/x2c; run test-array, test-atomic-container, test-index-slice
through unittest/Makefile; `make bm-varops` (array-existing-update). Same
for lib/map.x:114-445 with `$map.typed.family` and the void-answer and
numeric-`+` hooks; test-map, test-atomic-container;
`unittest/benchmarks/hash-table/direct/compare.py --baseline-binary
<frozen builds/0 binary> --candidate-binary <scratch>`. Decides: all cases
pass, checksums equal, map-get and slot updates within noise (<= 1.1x).

E6. One-Pool error record, then the frame chain (decides ~730 of the
error group). Four-line patch to lib/error.x:570-585 (`region.strings =
region.lists`, `values` = the pool's Scope). Build
`unittest/benchmarks/exception-hot-paths.x` as run-scope-hot-paths.sh does
(`builds/0/x2c translate --out-dir unittest/build/exc ...; cc -O2 -iquote
include/x2c -iquote builds/0/src ... -Lbuilds/0 -lx2c -lm`); five samples of
try-normal and raise-catch; run the error, exception, context, thread and
func suites. Decides: raise-catch faster (predicted 1.3-2x), suites green.
The chain merge itself is decided only by a prototype passing
`error_handler_head_survives_transfer` and
`error_dispatch_firewall_skips_active_handler`.

E7. Fixed-point rounds and the score (decides B1's -250..-990 and U5).
Temporary counter of `_sequence` rounds in `Compiler.transform`
(src/transform.x:1780-1784) printed per unit over `src/*.x` and `lib/*.x`;
`make bm-build-scaling` for the baseline score. Decides: rounds per unit
(>= 3 typical means the local fixed point buys time as well as lines);
confluence (U5) is settled only by the `.c` fixture run after B1 lands.

E8. Transaction copy share (decides T1 and the K3 frames, ~350).
`perf record -g builds/0/x2c translate --out-dir /tmp/t lib/typed-array.x;
perf report --stdio | grep -E 'Map_copy|begin_semantic_transaction'`.
Decides: >= 1% of samples makes frames a speedup; < 0.5% makes them lines
only.

E9. Plan table (decides 480). Replace lib/match.x:2002-2460 with the
256-entry direct-mapped table; run
`unittest/benchmarks/run-match-cache-benchmark.sh` (six-family gate,
hit/cold/product-warm/product-cold lanes); add two exit-printed counters in
`x2c_match_try_capture` and `x2c_match_site_try_capture` over
`builds/0/x2c translate src/*.x`. Decides: hit lane <= 1.1x, cold <= 1.3x,
dynamic share < 3%.

E10. Collection share (decides T7's 130 and the shallow-loop deletion).
`time builds/0/x2c translate --dump-symbols src/expressions.x >/dev/null`
against the full translate; after K3/K4, `X2C=builds/0/x2c
unittest/probes/run-header-cache.sh` and `run-symbol-snapshot.sh`. Decides:
the collection share bounds what one classifier can cost; both probes pass.

E11. Inline scalar boxing (decides C1's -90 and trade 12's 114; a speedup).
Change `$scalar` (lib/common.x:583-608) to emit the `$var.immediate` body
instead of `Var.new`; rebuild; test-var, test-varops; `make bm-var` with a
box-int row; run-compiler-translation.sh. Decides: box-int drops from a
variadic call plus SymbolSet lookup to a few instructions; the CSV moves
only if boxing was measurable (1,188 `int_var(` sites in bootstrap C).

E12. Eager parent session (decides 320). `time builds/0/x2c translate
--out-dir /tmp/o examples/foreach.x` with `-j 1` (deferred today) and with
`-j 2 examples/foreach.x examples/foreach.x` (preloads today). Decides: the
fill cost in ms on a small unit; under native meta the fill is ~650 Lisp
lines, not 9,900.

E13. Emission share (decides the net -50 of frames as AST). `time
builds/0/x2c translate --dump-code src/parse.x >/dev/null` against
`--dump-transforms`, five runs each. Decides: the emission share bounds the
1.05-1.15x.

E14. Buffer lazy line state (60). Scratch lib/buffer.x (122-170 and
`_recompute_line_state`); test-buffer (`buffer_unwrite_crosses_lines`,
`buffer_self_alias_growth_preserves_line_state`); `make bm-block-buffer`;
the CSV. Decides: indent-80 <= 2x, CSV flat.

E15. Pool depot (50). `unittest/benchmarks/run-scope-hot-paths.sh` all six
rows plus E6's benchmark; reject above 1.1x on pool-malloc-free or
raise-catch.

E16. Autodiff isolation (1,566 relocation; no performance risk).
`grep -rn 'ad_\|AdTape\|\$ad\.' src commands lib --include='*.x'
--include='*.xmacro' | grep -v lib/autodiff` must show only lib/lisp.x:36
and comments; build with that include removed; run
unittest/compiler-fixtures/comptime-autodiff.x. Decides: whether the
compile-time session needs the `<adnode>` descriptor.

E17. Line-count check. `wc -l` on every scratch file from E5, E6, E11 and
E14 against the per-file estimates in the design ledgers; the first
prototype that lands within 10% of its estimate calibrates the unnamed
folds in section 2.

Order: E1 first (it can refute the thesis), then E2 and E4 in parallel
worktrees (each one patch and one rebuild), E5 and E6 as scratch runtime
builds needing no compiler rebuild, then E7-E13 as timing-only probes.

## 5. Drops proposed anywhere

| design | drop | justification | lines |
|---|---|---|---:|
| synthesis, back | the compile-time subset and its rejection table (meta-functions.md:948-963; language.md:1717-1723); 18 `comptime-declines-*` fixtures become acceptances | its only consumer is the deleted lowering; no program that compiles today changes meaning | the value of L2, ~5,300 incl. stage.x and comptime.xlisp |
| synthesis | `x2c_comptime_lower` (lib/meta.x:315; src/macros.x:956) and tools/gen-lisp-init.py | three callers, all generators (etc/init.x:9, lisp-bindings.x:11, builtin-macros.x:9); one doc paragraph | 30 + 53 |
| synthesis, engines | the AUTO tier and API (`auto_prepare/disable/instrument/stats`, `Lisp.program`), lisp-machine.x, machine.x's Lisp half, test-lisp-auto.x | contract is transparency; gate promises only prepared/evaluator <= 0.90; the 3.4x was measured on lowered x2c | ~2,070 hand + 995 test; gated on U2 |
| synthesis, back | Lisp call budget arms for meta bodies (src/macros.x:2194-2201) | a native body is not preemptible, as `meta native` is not today | 10 |
| synthesis | user-defined bodied meta functions on hosts without `dlopen` | every documented build path is unaffected (the APE seed delegates; Windows is WSL2) | 0 |
| synthesis | reference matcher's module page; match-recursive.x relocated to unittest/ | consumers are test-support.x, test-match-plan.x, the benchmark | 445 leave lib/ (0 under engines, where it is the engine) |
| back | `<lisp-late>` restart and held diagnostics (macros.x:1221-1244, main.x:107-118/174-182/371-379, diagnostics.x:77-108) | premise: the parent session is built eagerly | ~110 |
| back | meta import replay (macros.x:1350-1365) | lowered definitions are no longer session-bound | 20 |
| back | `lowered_meta_regions` replay (regions.x:1239-1243, comptime.x:3018-3024) | the lowering cache goes | 15 |
| back | `fixed` memo (compiler.x:110-113, transform.x:1601-1610) | dead once a node is visited once | 15 |
| back | 13 `.transform` sidecars change shape | internal dump, not behavior | 0 |
| engines | match-machine.x, machine.x, MatchLower (match.x:1047-1667), MachineStats | one engine that is its own reference; counter contracts of test-match-plan.x become construction facts | ~1,700; gated on E4 |
| engines | `INELIGIBLE`, the `<size-limit>` fence raise (match.x:1668-1690), lib/error.x `fenced_arm` (12 sites) | they pin wordcode capacity limits (test-match-plan.x:383-509), a limitation not a behavior; `(!quote A B)` becomes MALFORMED | ~60 + 12 sites |
| engines | public MatchCache/MatchLease API (LRU, leases, generations, pins, pressure, both memos) | consumers outside the module are the benchmark and test-match-cache.x only; replaced by an 80-line private table | ~480 net; gated on E9 |
| engines | etc/init.x, gen-lisp-init.py, init.xlisp | replaced by ~100 Lisp lines in init-core | 219 -> 100 |
| engines | etc/comptime.xlisp and the comptime natives (lisp.x:1104-1270 plus frames) | their client is lowered x2c | 604; only under native meta |
| engines | derivable `meta` rows of etc/lisp-values.xlisp | generated from the native-meta target table by `_meta_lisp_name` | ~165; bounded by U7 (the certifier, macros.x:1926-1939) |
| infra | autodiff.xmacro and autodiff.x to packages/autodiff | no consumer in src/, lib/, commands/ except the include at lib/lisp.x:36; already optional (lib/Makefile:7-10) | 1,566 leave lib/; fixtures leave `make check` (Gary's call) |
| infra | `ScopeStats.largest_request`, `.peak_live_requested_bytes` (scope.x:134-152) | two CAS loops on the malloc path; documented fields with no reader | 20 |
| infra | `Logger.error_handler` as an observer and `Error.note_rendered` | replaced by one render hook; one `<err-report>` per error preserved; the public name survives | 60 |
| infra | `Pool.child_capacity` heuristic | changes `pool_reuses_child_table_capacity`; needs Gary's yes | 10 |
| values | `Var.parse` (var.x:1235-1281) | consumers are var.x and three tests; the tokenizer and scan.x have readers | 48 |
| values | `x2c_register_descriptor`/`try_` collapse; `x2c_register_tagged_descriptor` into its try form (dispatch.x:136-207) | the no-result forms discard a status the caller can ignore | ~50 |
| values | `Var.fallback_*` and `Var.wide_hash/equal/compare` become private | no consumer outside dispatch.x and varops.x | ~70 of doc surface |
| values | `$var.tag.id.checks` and the hand TagId enum (var-tags.xmacro:353-370, var.x:62-82) | once the shallow pass collects macro-generated declarations; otherwise kept | 45, cross-area |
| values | `List.subseq` alias of `getslice`; `Array.indexof` alias of `find` | two names for one operation; module pages change | ~25 |
| front | none recommended; candidates D1 host-preprocessor modes (-100, the only oracle of run-symbol-snapshot.sh), D2 `--dump-conformance` (-64, documented), D3 SymbolSet perfect hash at init time (-130, a language change), D4 `_attribute_since` linear scan (-10) | listed as the brief requires | 0 booked |
| language changes | L1 legacy macro body forms (fixtures only); L3 quoted `%[...]`/`%{...}` (held on one fixture check) | mechanical migration; L2 is the engine deletion above | 35; 80 optional |

## 6. How much smaller can the tree get

Three numbers on the map's 80,404 base (80,413 on disk today).

1. Verified-subtractive: about 73,150 (-9.0%), band 72,900-73,500. This is
   the round-1 synthesis after the verdicts: consolidate's counted removals,
   passes' local fixed point, and the one engine deletion. It assumes L2 is
   licensed, E1 (U1) is positive, E2 (U2) is positive, the REPL latency
   regression is accepted, and match-recursive.x's 445 lines count as a
   deletion when relocated. Without L2 the tree stops at consolidate's
   ceiling, about 77,700 (-3.4%).

2. Greenfield-central: about 67,700 (-15.8%); 66,500 with autodiff in
   packages/. This is section 2's credible column: the same L2/U1/U2
   assumptions, plus Array and Map as family instantiations (E5), the
   one-Pool error record and a frame chain that survives its prototype (E6),
   frames instead of copied transactions, one classifier, one installer,
   the initializer cursor and rule-list conversion at half their claimed
   savings, every named fold with a file:line, no comment compaction, and
   no Match rope trade. It is a from-scratch tree that keeps every
   documented feature and spends none of the 2x rope on throughput except
   the AUTO tier.

3. Greenfield-with-every-rope-trade: about 58,500 (-27%); 59,650 with
   autodiff kept as one walker. This is the five designs as written: the
   recursive Match engine (+4 to +12% translation), the plan table,
   AUTO off, T2 and T3, Buffer lazy state, the depot, frames as AST, all
   unnamed folds realized, comment shortening in string.x and list.x,
   match-recursive.x as the engine, autodiff relocated. It assumes every
   trade measures inside its own bound and that nothing in the unread
   regions (macros.x's use of Sym beyond three sites, match.x:2260-2677,
   lambda.x's binding-fact keys) pushes back.

What no design found: a compiler pass that shrinks by moving behind the
macro or meta boundary. Every reduction above is a deleted second
implementation (the lowering backend, the Lisp wordcode tier, a hand-written
public layer over a generated family, a copied walk), a table replacing a
hand expansion, or a walk with one skeleton instead of several. The
survivors the five designs list at the floor total about 36,000 lines
(values ~5,200, infra ~8,600, engines ~3,450, front ~2,600 named plus its
grammar, back ~11,900), which is why the third number does not fall further:
the floor under these designs is roughly 55,000-58,000, and the honest
central estimate sits 10,000 above it because half of the difference is
unmeasured trades and the other half is folds that have not been written.
