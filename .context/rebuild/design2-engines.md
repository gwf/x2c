# Greenfield estimate: execution engines (map 2.4, 2.9)

Area: lib/match.x, match-recursive.x, match-machine.x, machine.x, split.x,
regex.x, lisp.x, lisp-machine.x, and the hand-authored etc/ compile-time
environment of map 2.4 (init-core.xlisp, init.x with tools/gen-lisp-init.py,
comptime.xlisp, lisp-values.xlisp, lisp-bindings.x/.xmacro/-core.xlisp,
builtin-core, compiler-sdk, lisp-extras, lisp-io). Current total: 10,441
hand-authored lines (`wc -l`, dev 8fe1a0c, 2026-09-26); generated
init.xlisp (235) and lisp-bindings.xlisp (229) are not counted.
etc/builtin-macros.x and its artifact belong to map 2.3; this design fixes
only the interface they call (2.4).

Headline: 4,940 lines from scratch (53% less) when bodied meta functions
execute natively as design-synthesis section 3 proposes, or 5,544 (47%
less) if src/comptime.x keeps lowering x2c to Lisp. The reduction is two
engines removed: `List.match` becomes the recursive matcher that is today
the test oracle (lib/match-recursive.x, 445 lines), and compile-time Lisp
becomes one evaluator with no wordcode tier. Both are rope trades under
the brief's 2x (sections 4 and 7). regex.x and split.x are survivors.

## 1. Feature and contract inventory

Map section 4 rows owned here, with the contract each must keep:

- match statement / pattern matching / typed captures (match.x,
  match-machine.x, machine.x): the vocabulary of language.md:3005-3047 and
  guide/match.md: `?`/`*`, `?IDENT`/`*IDENT` with the C identifier grammar
  (`_binder_kind`, lib/match.x:354-376), repeated-binder equality, nested
  sublists, `!or !and !not !set !quote !is` with an optional leading binder
  normalized to `(!set B (OP ...))` (332-344), `!quote` opacity,
  definite/possible sets for arm proofs (498-555; src/compiler.x:
  2442-2444), `x2c-dyn` (449, 512), leftmost-shortest star split
  (lib/match-recursive.x:117-133), `*name` on typed nil binds an empty
  List, interned operator heads, the malformed categories (556-604).
- transformation over lists (match.md): `List.match/try_match/search/
  try_search/match_replace/try_match_replace/search_replace/replace`
  (lib/match.x:717-1040); search visits car, cdr, node and prepends;
  explicit nil is a node, a proper List's terminal cdr is not (860-940);
  search_replace rewrites leaves upward; template rules (730-760,
  774-810); `%(())` for a binder-free `List.match` (724-728); `try_*`
  outputs unchanged on failure.
- compiler-owned sites (ABI): `x2c_match_site_try_capture` and the seven
  `x2c_match_site_*` entries src/emit.x:425-432, 464, 801 emit;
  `MatchCaptureSite` static storage bound permanently by its first
  admissible pattern (lib/match.x:83-92, 2576-2620); `MatchCaptureBuffer`
  published atomically with presence separate from `void` (63-70;
  agents/x2c-philosophy.md:165-185); `x2c_match_pattern_retainable`,
  `x2c_match_site_prepare` and `MatchPlan.prepare` for catch arms
  (lib/error.x:123-127, 146); `MatchCaptureLayout.analyze/index/
  definite_list/possible_list/free`; the four `Var.is_*binder*` predicates
  (src/compiler.x:2390-2453; src/literals.x:155-228).
- lifetime: a site borrows only outermost-pool values
  (`_pattern_borrowable`, lib/match.x:1970-1997); the default cache is
  Context-local or else thread-local (2517-2525; lib/context.x:116, 132,
  354), released before the thread's Scope (lib/thread-state.x:30),
  invalidated on `Pool.epoch()` change (2054-2066); shutdown frees site
  plans (2540-2575).
- reference matcher and wordcode machine (match-recursive.md, machine.md):
  consumers are tests and benchmarks only (unittest/test-support.x:60-78,
  match-capture-benchmark.x:4, test-machine.x); the "engines semantically
  identical" contract (lib/match.x:14-27) is met by having one.
- Lisp runtime (lisp.md; language.md:1379-1636): reader with quote,
  quasiquote, unquote, splice, comments, compact Symbols and
  case-sensitive `<lsym>` names, cursor advance, `<incomplete>`,
  `<malformed>` with line and column, depth fence 1024 (lib/lisp.x:
  549-830); evaluator: nil the only false, eager left-to-right, macros get
  raw forms and their expansion is evaluated in the caller's environment,
  free-name capture at creation through quasiquote depth (1978-2021), a
  `let` name invisible in its initializer, `eval` in globals, `apply`,
  `bind`, `import` via `_x2c.import-hook`, rest parameters, specials
  shadowable and aliasable by identity, exact error shapes the
  differential checker compares byte for byte
  (examples/programs/check-reference-lisp:1-80, 183 cases); sessions
  kernel/new/adopt/freeze/destroy with a child never writing its parent
  and `def` on an inherited or frozen name raising `bad-state`
  (2195-2214); sticky call budget per public entry and depth 1024
  (2099-2110, 2919, 3051); `void` through raw cells (1104-1130); Func,
  callback and Iter adapters sharing the entry budget and session
  (1344-1600; test-lisp.x:1436-1438).
- AUTO (lisp.md `auto_prepare/auto_stats/auto_instrument/auto_disable`,
  `Lisp.program/resolve/step/reslot/precall/immediate/evaluate/expanded`;
  guide/repl.md:117): an internal tier whose documented property is
  transparency (test-lisp-auto.x:1-9). Dropped, section 8.
- etc/ environment: the vocabulary of init-core.xlisp plus the algorithms
  init.x lowers, comptime.xlisp's `C.*` runtime for lowered x2c,
  lisp-values' `Type.method` rows, `$lisp.bind/binding/install`, and six
  forwarding files, all evaluated into every compiler session
  (src/macros.x:1054-1060).
- Regex (regex.md; guide/scripting.md:432-533): the syntax table (sets,
  classes, anchors, boundaries, greedy and lazy bounded repetition,
  alternation, numbered and named captures, `(?:)`, `(?i)(?m)(?s)`),
  `match/match_from/find_all/split/replace/replace_all/replace_fn/escape/
  capture_names/capture_count/pattern`, `RegexMatch` as an immutable List
  indexed by number or name, `<bad-arg>` with offset, `<size-limit>` past
  2,000 group repetitions (lib/regex.x:401-413).
- Split (split.md): `String.split/split_n/split_lines/words/lines/splits`,
  `Split.try_next` with a caller-owned cursor, `Split.iter`, `<split>` boxing.

## 2. The design, component by component

### 2.1 match.x: one recursive engine over a canonical layout

A pattern is prepared once into a `MatchPlan` holding what the compiler and
catch sites already consume: the `MatchCaptureLayout` (slots in preorder,
definite/possible bitsets, malformed status) and the normalized pattern.
There is no program. Execution is the matcher of
lib/match-recursive.x:184-214 with three changes:

1. State sized by `layout.binder_count` and undo by journal, not struct
   snapshot. `_star_candidate`, `_any` and `_none` copy the whole
   `RecursiveMatchState` (about 2.3 KB) per attempt
   (lib/match-recursive.x:107-115, 143-163); a 5,000-cell anchored miss
   would copy 11 MB. The engine journals `(slot, prior)` on each bind and
   rolls back to a mark as the machine does (lib/match-machine.x:53-72);
   about 25 lines.
2. Spans stay borrowed `(begin, end, length)` until the whole match
   succeeds, as `_bind_span` and `_try_capture` do (38-68, 241-249); a
   final star binds the input suffix itself (70-76): the "zero losing-span
   materialization, direct suffix sharing" contract of
   test-match-plan.x:227-241, kept by construction.
3. A binder-free literal sublist compares by canonical identity before
   descending (`input.u64 == pattern.u64`), the fast path of
   lib/match.x:1642-1652.

Public operations are the current ones over the plan: `try_match` runs the
engine and publishes from the buffer (`_capture_publish`, 699-708);
`search`, `try_search` and `search_replace` keep the loop-over-cdr walks
with an explicit spine (866-990) so a long List costs one frame
(test-match.x:584); `replace` and the capture template (730-810) are
unchanged.

Sites: `MatchCaptureSite` keeps its permanent plan, lock, registry and
shutdown hook (2540-2640); preparation is now a layout walk, but a compiler
arm runs millions of times, so a per-site plan still pays. Runtime patterns
go to a private direct-mapped table of 256 `(key, plan)` entries per thread
or Context: a hit is the admission memo (an entry exists only because
`_cache_keyable` admitted its pattern at insertion), a miss walks
`_pattern_borrowable` once and replaces the slot or uses a transient plan;
the table clears on a `Pool.epoch()` change. No leases, pins or
generations: nothing reenters Match while a match runs (the engine's only
callbacks are the four binder predicates, lib/match.x:378-400), and the
table is per thread, so a replaced plan is never under execution.
`MatchCache.context_open/context_close/flush_default` and
`x2c_match_thread_release` keep their signatures.

Status: `PREPARED` and `MALFORMED` stay. `INELIGIBLE` and the `<size-limit>`
raise (1668-1690) exist because wordcode has fixed capacities (`frame-depth`,
`code-capacity`, `segment-width`, `guard-width`; 1085-1108, 1200-1215); a
recursive engine has none. `(!quote A B)` becomes `MALFORMED("quote-arity")`
and lib/error.x's `fenced_arm` (12 references) goes.

### 2.2 lisp.x: one evaluator

Reader (549-830) unchanged: it already reads elements in a loop and is the
contract twelve test-lisp.x cases pin. Evaluator: the rules at 1832-2303
and 2958-3037 minus speculation (`_expansion_*`, 1855-1910, hooks at 2110,
2186, 2960, 3022) and `_auto_apply`, plus two additions:

- A tail-call trampoline in `_call_lambda_slots`: a body's tail form (a
  `cond` result, the last form) is evaluated in the caller's C frame after
  the frame Scope is released, so `(cd 100000)` still runs in one frame
  (test-lisp-auto.x:938) and comptime-lowered loops, which
  src/comptime.x:5-16 turns into self tail calls, do not hit
  `LISP_CALL_DEPTH_MAX` (1024 at about 2 KB per level, 2320-2326). About
  60 lines. Without native meta execution this is mandatory: the wordcode
  tier is what keeps lowered loops flat today (`MW_LTAILCALL`).
- A per-call-site macro expansion memo: `_apply_lambda` re-expands on
  every call (2166-2174); measured 505 ms against 186 ms on one function
  (plans/archive/x2c-lowers-to-lisp.md:755-783). A 25-line Map from raw
  form identity to expansion, guarded by the macro's identity and cleared
  on `def` and `set_global`, serves `match-case`, `let`, `and`, `or` and
  every user macro.

Natives (833-1100) and adapters (1344-1600) survive. The machine bridge
(85-300), slots (410-430), `LispLower` and `_auto_*` (2303-2957), the AUTO
API (2898-2956), and the Lisp half of machine.x (`LispFrame`, `LispMachine`,
`MW_L*`, `MACHINE_LOCAL_*`, `MACHINE_CALL_RESERVE`, `MACHINE_VALUE_MAX`) go.
The target table (1607-1815) is generated from lisp.x's own `meta native`
declarations through `_x2c.native-meta.declared` (src/macros.x:1121), as
`$compiler.targets()` does; the three override rows stay by hand.

The comptime natives `lisp_cell/address/load/store/bytes/at/zero/copy/
record_result/session_copy/box/peek/poke/array/source_function/unwind`
(1104-1270) and the `automatic_owner/result_owner` bookkeeping are the
runtime of lowered x2c: under native meta execution they have no client
(-205); if lowering is kept they survive unchanged.

### 2.3 The etc/ environment

- init-core.xlisp stays the standard source. The algorithms etc/init.x
  writes in x2c and lowers with `x2c_comptime_lower` (etc/init.x:8-14,
  28-166) are written in Lisp inside init-core, three to six lines each;
  literate-lisp.x defines the same vocabulary in 107 lines of Lisp
  (examples/programs/literate-lisp.x:714-820). init.x, gen-lisp-init.py
  and init.xlisp go; `$lisp._standard.source()` embeds init-core.
- lisp-values.xlisp: rows binding a `meta`-declared operation under its
  `Type.method` name are derived by `_meta_lisp_name` (src/macros.x:
  1081-1088); the 132 non-meta rows and 25 adapting `defun`s stay
  (design-synthesis section 3). 465 -> about 300.
- comptime.xlisp: 0 under native meta; 399 unchanged otherwise.
  lisp-bindings .x/.xmacro/-core (190) and the four forwarding files (90)
  unchanged; the generated lisp-bindings.xlisp goes under native meta.

### 2.4 The interface to builtin macros (map 2.3)

This area promises `Lisp.eval/apply/eval_string`, `set_global/bind/
try_get`, `adopt/freeze`, the call budget, `List.match` and `search_replace`
under their Lisp names (etc/init-core.xlisp:23-26), and `_x2c.import-hook`.
`Lisp.auto_prepare` at src/macros.x:1198 goes.

### 2.5 regex.x and split.x stay separate

Regex matches bytes with a continuation-passing backtracker over a node
tree (lib/regex.x:387-530); `List.match` matches cells with binders and
spans. Sharing an engine needs a String-as-List view or a byte mode in the
List matcher, each larger than the 150-line regex core it would replace.
Split is `strstr` and line scans with caller-owned cursors (lib/split.x:
52-85, 152-190). Both are at the floor (section 5).

## 3. Line ledger

Current, by file (10,441):

| file | lines | doc lines |
|---|---|---|
| lib/match.x | 2,677 | 358 |
| lib/match-recursive.x | 445 | 74 |
| lib/match-machine.x | 541 | 0 |
| lib/machine.x | 540 | 0 |
| lib/lisp.x | 3,190 | 356 |
| lib/lisp-machine.x | 480 | 0 |
| lib/regex.x | 746 | 55 |
| lib/split.x | 283 | 118 |
| etc/: init-core 176, init.x + gen-lisp-init.py 219, comptime 399, lisp-values 465, lisp-bindings .x/.xmacro/-core 190, builtin-core + compiler-sdk + lisp-extras + lisp-io 90 | 1,539 | |

Greenfield, by component, with the anchor for each estimate. Doc density
is kept: the module pages are generated from these comments.

| component | lines | anchor and accounting |
|---|---|---|
| match: classification, normalization, capture layout | 300 | lib/match.x:323-660 is 338 lines for the same contract |
| match: recursive engine (bind, spans, star, guards, `!is`) with journal undo | 260 | lib/match-recursive.x:16-253 is 238; +25 journal, -10 fixed arrays |
| match: replace, capture template, three walks in loop form | 230 | lib/match.x:730-1040 is 310; `MatchWalk`'s machine fields go |
| match: plan prepare/free, sites, thread and Context state, direct-mapped table, shutdown | 260 | lib/match.x:1693-1745 (50) + 2460-2640 (180) + table 80; LRU, leases, generations, pressure, memos (2002-2460, about 480) not carried |
| match: public entries (`List.*` 8, `x2c_match_site_*` 8, try_capture, retainable, site_prepare, `MatchPlan.*` 7) with docs | 250 | lib/match.x:134-320 is 186 for the site entries alone; `MatchCache.*` adapters (2339-2460) go |
| lisp: session struct, canonical names, kernel/new/adopt/freeze/destroy | 200 | lib/lisp.x:383-545 + 689-800 is 280 minus AUTO fields, slots, stats |
| lisp: reader | 280 | lib/lisp.x:549-830 unchanged |
| lisp: evaluator (lookup chain, capture, quasiquote, lambda/macro, specials, apply, budget) + trampoline + memo | 540 | 1832-2303 (470) - speculation 70 + 2958-3037 (80) + 60 + 25; literate-lisp.x:102-410 does the rules in 250 code lines without sessions, budgets or void |
| lisp: natives (predicates, arithmetic, chains, strings, match glue, typed conversions) | 280 | lib/lisp.x:833-1100 (267) + 344-381 (38) |
| lisp: Func, callback and Iter adapters, void cells | 260 | lib/lisp.x:1344-1600 (256) + 1104-1130 |
| lisp: target table | 60 | 1607-1815 is 208; rows generated as at src/macros.x:1064-1066 |
| lisp: public API (eval, apply, eval_string, eval_file, try_get, set_global, bind, call_budget, read) | 130 | 3064-3190 (126) |
| lisp: comptime natives and source-function frames (only if lowering is kept) | 0 / 205 | 1104-1270 (165) + frame bookkeeping in 2099-2160 (40) |
| etc: init-core with the standard algorithms in Lisp | 280 | 176 + init.x's 166 lines as about 100 Lisp lines; literate-lisp.x:714-820 is 107 |
| etc: lisp-values | 300 | 465 minus 157 derivable meta rows |
| etc: comptime.xlisp | 0 / 399 | deleted under native meta; else unchanged |
| etc: lisp-bindings .x/.xmacro/-core | 190 | unchanged |
| etc: builtin-core, compiler-sdk, lisp-extras, lisp-io | 90 | unchanged |
| regex.x | 746 | survivor; Cox's re1 backtracker is about 250 C lines with numbered captures only, no bounded repetition, named groups, replace or split |
| split.x | 283 | survivor |

Totals: 10,441 current; 4,940 with native meta execution (53% less);
5,544 with comptime lowering kept (47% less). Files: match.x 1,300,
lisp.x 1,750 (1,955), regex.x 746, split.x 283, etc/ 860 (1,259);
match-recursive.x, match-machine.x, machine.x and lisp-machine.x do not
exist.

## 4. Rope trades (the brief's 2x)

Every dimension here is compile throughput; nothing in this area is on a
generated-code path, and the runtime hot paths it owns (`List.match` in
user programs, Regex, Split) either keep their engine or are priced in
trade 1.

1. **Recursive Match engine instead of wordcode.** Expected 1.3-2.0x per
   structural match (fused `EQ_HEAD_CONST`/`SCAN`/inline descend,
   lib/match-machine.x:243-310, 393-430, against one recursive call per
   element with a journaled bind). Match is 9.7-12.5% of translate
   samples and `MatchMachine_step` 11.1% of self time
   (plans/archive/comptime-x2c-generalization.md:1030-1041); 444 of the
   1,254 compiler `case` arms are flat shapes emit.x compiles to direct C
   checks that never reach the runtime (src/emit.x:722-750, 786-791;
   plans/archive/fixed-shape-match-experiment.md). Whole translation: +4%
   to +12%. Buys 2,750 lines (lowering 620, match-machine 541, machine
   540, cache apparatus 480, oracle duplication 445, statistics) and one
   engine that is its own reference. Measure: experiment 1.
2. **No Lisp wordcode tier.** Expected 1.1-2x per hot lambda call (the
   AUTO gate requires only prepared/evaluator <= 0.90,
   unittest/benchmarks/run-lisp-auto-benchmark.sh:8-9, 60-75). Whole
   translation: compile-time Lisp is 2.7% of src/ and 1.7% of lib/
   samples (comptime-x2c-generalization.md:1036-1038), so at 2x the bound
   is +3% src, +2% lib. The declined 3.4x in map section 6 (10.48 s
   against 3.07 s on lib/, comptime-x2c-generalization.md:462-476) was a
   lowered x2c table walk against handwritten Lisp with AUTO on in both
   arms: it measured the cost of lowered x2c, not the machine's benefit,
   and native meta execution removes that workload. What regresses is a
   comptime-heavy unit such as unittest/test-autodiff.x (6.2x faster from
   the engine work, ibid.:1018-1020): up to 2-3x if lowering is kept, 0
   under native meta; the expansion memo (505 -> 186 ms) offsets part.
   Buys 2,070 lines and the speculation, rewind, slot and guard machinery
   (map 2.4 note 4). Measure: experiment 2.
3. **Direct-mapped plan table without LRU, leases or memos.** The declined
   memo removal (2.35x literal, 1.63x star miss, 1.61x guards, 1.41x
   hits, 1.29x nested, plans/overengineering-candidates.md:34) bypassed
   the memos while keeping the admission walk and the LRU table; here a
   hit is the memo, so the walk runs only on a miss. Expected <= 1.1x on
   the hit lane, up to 1.3x cold. Whole translation below 1%: dynamic
   patterns are 31 of 1,254 compiler arms and 17 of 107 `List.match`-family
   calls (`grep` of `case %(` with `$` in src/); every literal pattern
   uses its site. Buys about 480 lines. Measure: experiment 4.
4. **Tail trampoline.** Expected neutral to faster (no C frame per
   iteration); +60 lines, listed because it is the one addition.

Declined, so it is not re-proposed: one engine for Regex and List Match.

## 5. Survivors

Already at the floor, kept with their lines: lib/regex.x (746: parser about
300, backtracker 150, captures and replace/split API 150, docs 55),
lib/split.x (283; 118 doc lines over 11 operations), the layout analysis
(lib/match.x:323-660, 300), replace and the walks (730-1040, 230), the
recursive matcher's core (lib/match-recursive.x:16-253, now the engine),
site permanence and borrowability (1970-1997, 2540-2640), the Lisp reader
(549-830), evaluator rules (1832-2303 minus speculation), natives
(833-1100), adapters (1344-1600), the session API (3064-3190),
etc/init-core.xlisp (176), the forwarding files (90), lisp-bindings
.xmacro and -core (53), and literate-lisp.x as the oracle (not counted).
About 3,450 of the 4,940 lines are survivors; the rebuild is the
1,500-line engine consolidation.

## 6. Hard cases and how the design handles each

1. Leftmost-shortest star with a linear anchored miss (test-match.x:580;
   test-match-plan.x:374-376 pins `scan_cells <= 5001`, `cons_requests
   == 0` on 5,000 cells). Split lengths shortest first as `_star` does
   (lib/match-recursive.x:119-133); an anchored tail fails at its first
   element; the journal makes a failed attempt O(1) instead of a 2.3 KB
   snapshot; no cons on a miss because spans stay borrowed.
2. Repeated binders across value and span kinds: `%(?x ?x)`,
   `%(*same pivot *same)`, a final star repeating an interior span
   (test-match.x:582; test-match-plan.x:281-297). `_bind_span` and
   `_bind_final` compare in place and memoize a proven suffix as a value
   (lib/match-recursive.x:38-103), kept verbatim.
3. Direct suffix sharing and empty spans (test-match-plan.x:227-241,
   322-324): a final `*rest` binds the suffix without copying, an empty
   span publishes nil, a proper prefix conses once on success (70-76,
   241-249). `!not` never publishes; `!or` and membership `!set` restore
   after each miss; `(!set ?b PAT)` is bind-and-test (143-163, 199-202);
   rollback-to-mark replaces the snapshots.
4. Definite/possible sets, `!quote` opacity, `x2c-dyn`, reserved `!is`
   names, the three malformed categories: the layout analysis is kept
   (lib/match.x:405-604) and src/compiler.x:2442-2444 keeps its consumer.
5. Search visits explicit nil but not the terminal cdr, prepends hits, and
   walks a long cdr chain without recursion (test-match.x:570, 584): the
   spine-loop walks (866-990) are kept. Template rules
   (test-match-plan.x:1011; test-match.x:583): `_replace` and
   `_capture_replace` unchanged (730-810).
6. Site permanence and pool lifetime: a site borrows for the process, so
   only outermost-pool values are admissible; a table entry borrows until
   its level is released, so the table resyncs on `Pool.epoch()`
   (1970-1997, 2054-2066). Both walks stay; the memo goes.
7. Filtered catch binds arms through `x2c_match_site_prepare` and copies
   committed captures into the Error region before `siglongjmp`
   (lib/error.x:110-160; philosophy.md:181-185). Unchanged; `fenced_arm`
   goes.
8. Thread and Context ordering (lib/thread-state.x:30; lib/context.x:116,
   354): same entry points. Deep nesting: the engine recurses on pattern
   nesting as `_match` and the walk's car descent do today
   (lib/match.x:872); the `frame-depth` fence at 126 frames (1085-1092)
   is replaced by the C stack.
9. Lisp lexical capture through quasiquote depth, caller bindings
   invisible (language.md:1408-1422; check-reference-lisp cases
   `capture`, `dynamic-caller`, `macro-introduced-name`): `_free_names`
   and `_capture` (lib/lisp.x:1978-2021) unchanged.
10. `def` on inherited or frozen names, `x2c.` protection, child isolation
    (2195-2214; test-lisp-auto.x:970): the session chain is kept;
    freezing no longer guards compiled constants, only ownership.
11. Sticky budget and depth limit (test-lisp.x:1398-1399; 2320-2326):
    unchanged; the trampoline means a self tail call no longer consumes
    depth, which is what the machine gave lowered loops (`(cd 100000)`,
    test-lisp-auto.x:938).
12. `void` transport through raw cells (1104-1130; test-lisp.x:1394) and
    Iter callbacks sharing the entry budget and session (1455-1485;
    test-lisp.x:1436-1438): `lisp_active` and the adapters are kept.
13. Macro re-expansion: memoized per raw-form identity, guarded by macro
    identity, invalidated on `def` and `set_global`, which covers the
    plan's caveat on redefinition and mutable globals
    (x2c-lowers-to-lisp.md:782-786); the memo stores the expansion form,
    not a value. Exact error shapes and reprs (check-reference-lisp:1-80):
    the raise sites in `_apply_special`, `_bind_params`, `_apply` stay.
14. Regex: group repetition `<size-limit>` at 2,000, empty-iteration
    termination (`pos == last_start`), lazy/greedy order, capture restore
    on backtrack (lib/regex.x:401-530). Split: CRLF as one ending, no
    trailing empty line, empty `sep` yields the String once, empty input
    yields nothing (lib/split.x:52-85, 100-125). Survivors.

## 7. Experiments

All against builds/0 on the calibrated host; each names the command and
the number it produces.

1. Recursive engine, whole translation (trade 1). Patch
   `MatchPlan._capture` (lib/match.x:1786-1793) to call
   `match_recursive_try_capture(m.layout, input, captures)` and include
   lib/match-recursive.x; `make build-safe` in a worktree. In both trees:
   `SAMPLES=7 unittest/benchmarks/run-compiler-translation.sh` (median of
   the `seconds` column over seven src/lib units) and
   `make bm-build-scaling`. Per-family ratios come free from
   `unittest/benchmarks/run-match-capture-benchmark.sh`, whose `recursive`
   lane already runs the oracle against the machine
   (match-capture-benchmark.x:103-173). Estimate 1.04-1.12 on the
   translation median; the patched engine still snapshots, so this bounds
   the journaled one from above.
2. No wordcode tier, whole translation (trade 2). Call
   `Lisp.auto_disable(shared, 1)` after `Lisp.kernel()` at
   src/macros.x:1163 and on the unit session at src/macros.x:1256, delete
   `shared.auto_prepare()` at src/macros.x:1198 (`_auto_apply` reads the
   evaluating session's field, lib/lisp.x:2843). Rebuild stage 0, then
   `unittest/benchmarks/run-compiler-translation.sh`,
   `time builds/0/x2c translate --out-dir /tmp/lib-x lib/*.x` in one
   process (the instrument of the declined 3.4x, comptime-x2c-
   generalization.md:468-470), and `time builds/0/x2c translate --out-dir
   /tmp/ad unittest/test-autodiff.x`. Expected: src/lib within 1.05;
   autodiff 1.5-3x. Per-call lanes: `run-lisp-auto-benchmark.sh` reports
   `evaluator-hit` against `prepared-hit`.
3. Expansion memo. Prototype the 25 lines in `_apply_lambda`
   (lib/lisp.x:2166-2174), repeat experiment 2's timings; the fixture
   `comptime-autodiff` took 753 ms (comptime-x2c-generalization.md:
   1046-1048). Correctness: `x2c script examples/programs/
   check-reference-lisp --build` and unittest/test-lisp.x.
4. Plan table (trade 3). Replace lib/match.x:2002-2460 with the table and
   run `unittest/benchmarks/run-match-cache-benchmark.sh`: its six-family
   gate (run-match-cache-benchmark.sh:6-9) and the `hit`, `cold`,
   `product-warm`, `product-cold` lanes (match-cache-benchmark.x:493-604)
   give the memo comparison. Count the dynamic share with two counters in
   `x2c_match_try_capture` and `x2c_match_site_try_capture`, printed at
   exit, over `builds/0/x2c translate src/*.x`; estimate under 3%.
5. Trampoline and acceptance. test-lisp-auto.x:938 (`(cd 100000)`) and
   test-lisp.x's budget cases, then experiment 2's autodiff timing;
   unittest/test-match*.x, test-regex.x, test-split.x, test-lisp.x
   unchanged with test-match-plan.x's parity cases made exact;
   `make verify-fixtures` for the match-*, lisp-*, macro-lisp-template
   and comptime-* fixtures; the stage 0-3 comparison.

## 8. Drops (each with justification and lines)

- lib/match-machine.x, lib/machine.x, `MatchLower` (lib/match.x:1047-1667)
  and `MachineStats`: 1,700 lines. One engine that is its own reference;
  the counter contracts test-match-plan.x pins become the construction
  facts of 6.1-6.3 (a timing test if Gary wants them pinned).
- `INELIGIBLE`, the `<size-limit>` fence raise and lib/error.x's
  `fenced_arm`: about 60 lines plus 12 error.x sites. They pin a capacity
  limit of the wordcode representation (test-match-plan.x:383-509), a
  limitation rather than behavior a program relies on; `quote-arity`
  moves to `MALFORMED`.
- The public `MatchCache/MatchLease` API (new/acquire/release/dispose, six
  `try_*` adapters, generations, pins, pressure, LRU, both memos): about
  560 lines replaced by an 80-line private table. Consumers outside the
  module are match-cache-benchmark.x and test-match-cache.x only;
  `context_open/close/flush_default` and `x2c_match_thread_release` stay.
- match-recursive.x as a separate module: 0 net (its core becomes the
  engine, its eight wrappers go).
- lib/lisp-machine.x, the Lisp half of machine.x, and in lisp.x the bridge
  (85-300), slots (410-430), speculation (1855-1910), `LispLower` and
  `_auto_*` (2303-2957), the AUTO API (2898-2956): about 2,070 lines.
  Consumer change: commands/repl reads `auto_stats` and `auto_instrument`
  (commands/repl/repl.x:126-140, 369-371; guide/repl.md:117); those
  fields go, which constraint 4 reserves to Gary. test-lisp-auto.x (995)
  and the machine cases of test-machine.x (464) test the tier.
- etc/init.x, tools/gen-lisp-init.py and init.xlisp: 219 hand lines
  replaced by about 100 Lisp lines in init-core.
- etc/comptime.xlisp and the comptime natives: 604 lines, only under
  native meta execution (their client is lowered x2c).
- The derivable rows of lisp-values.xlisp: about 165 lines.

## 9. Risks

1. No recorded compiled-versus-recursive translation factor. Experiment 1
   is one patch and one run; above 1.3 on the translation CSV the trade is
   still inside the rope on a 12% share, but the engine should then gain
   fused head-element and anchored-scan loops (about 120 lines) rather
   than a program.
2. The journal changes failure cost, not success cost, bounded by 64
   binders; and no reentrancy during a match rests on the engine calling
   only the four binder predicates, so a future `!is` predicate calling
   user code would need the pins back (documented in the table's header).
3. Without native meta execution the evaluator must carry the trampoline
   or lowered loops past 1,024 iterations fail with `call-stack`, and
   comptime-heavy units regress 1.5-3x. The primary figures assume
   design-synthesis section 3.
4. The expansion memo freezes the first expansion of a macro that reads a
   mutable global while expanding; invalidation on any `def` or
   `set_global` is coarse but correct (experiment 3 checks it).
5. `MatchCaptureBuffer` and `MatchCaptureLayout` are ABI for emitted C
   (src/emit.x:835-843) and lib/error.x and are kept byte for byte;
   `MatchPlan` loses `program`, which consumers touch only via `status`.
6. REPL `:stats verbose` and `:lowered` (guide/repl.md:84-117) shrink; the
   CLI surface survives, the fields do not. Needs Gary.
7. literate-lisp.x is the evaluator's oracle but has no sessions, budgets,
   `void` cells or adapters; unittest/test-lisp.x alone pins those.
