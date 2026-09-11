# Core adoption of classes and system macros

> Status: done
> Compatible adoption implemented, 2026-09-11: 46 managed locals,
> 30 restoration regions (27 here, three in parent cleanup 58c99b0), and
> nine destination regions. One template-staging exclusion remains explicit.
> Error-path changes and class conversions remain deferred.
> Inventory baseline 8eb27f4; measurement baseline 1d2c938; integrated parent
> cleanup 58c99b0. Closed by the delivery commit containing this archive.

## Recommendation

Replace the earlier narrow shortlist with the complete compatible set below.
The first pass selected small obvious examples; it was not a complete adoption
inventory. This revision examines handwritten equivalents, long regions,
nonadjacent cleanup, native aliases, macro templates and helper-mediated state.

| Pattern | src | lib, including templates | Compatible total |
| --- | ---: | ---: | ---: |
| `$auto`, initialized local owners | 18 | 28 | 46 |
| `$let`, state-override regions | 26 | 4 | 30 regions / 40 restored places |
| `$scope(&owner)`, destination regions | 0 | 9 | 9 |
| `$scope()`, existing retained regions | 0 | 0 | 0 remaining |
| `$lock`, ordinary Mutex pairs | 0 | 0 | 0 |

Counts are authored sites, not generated instantiations or runtime frequency.
One multi-field `$let` region may use several decorators. Related `$auto` and
`$let` sites can share one block; do not sum columns into independent rewrites.

There is also a substantial separate opportunity to strengthen failure cleanup:
30 more `$let` regions (52 places), 12 destination regions, eight compiler
Arrays in four acquisition pairs, twelve library scratch locals, and six
prioritized compiler locals with duplicated explicit frees. Those are listed
as consequential candidates, not quietly included as equivalent replacements.
They can restore state or free scratch on paths that currently leave it to
another owner. Decide that policy explicitly before implementing those sites.

The evidence is split for review:

- [Complete inventory](core-system-macro-inventory.md): every state/destination
  region, raw cleanup census by area, alias/helper tracing, and exclusions.
- [Every defer audit](core-system-macro-defer-audit.md): **all 189 executable
  defer statements**, individually inspected: 81 src and 108 lib/templates.
  Each has a source location, action/owner and concrete `$auto` disposition.
  Compound defers count once; compiler AST tags and documentation do not count.

## Current adoption and semantic owners

The [guide](../../docs/src/guide/system-macros.md),
[archived implementation plan](system-macros-and-classes.md),
[built-in macros](../../etc/builtin-macros.xmacro), and
[construction helpers](../../etc/builtin-macros.xlisp) own feature contracts.
Ordinary binding, Cleanup protocols, defer lowering and Scope own execution.

SourceView is the only actual class declaration in src/lib. Its explicit init
creates two Maps in the request Context. List already uses a retained region,
managed zip/rendering scratch and temporary padding; Context manages export
scratch; Lisp selects three destinations and manages Array/MachineBuilder
scratch; Array/Map renderers manage Buffers. These existing adoptions are
excluded from additional-opportunity counts. No ordinary `$lock` use exists.

## Compatible implementation scope

### 1. All thirty compatible `$let` regions

Use every C row in the inventory's L01-L79 ledger, including whole-function
and snapshot regions. The largest useful deletion is `_eval_template_form`'s
six SDK-global saves, deferred restores, and duplicate explicit restoration
before error reporting. Other additions include declaration production and
selection, whole bind_syntax/effect evaluation, borrowed diagnostic callbacks,
projection depth, and Logger/Lisp recursive depth counters.

```x2c
// Before
List previous = compiler.aggregate_type;
compiler.aggregate_type = context;
{
  defer compiler.aggregate_type = previous;
  macro = compiler.try_parse_macro_target_at(AST_FIELD);
}
// After
$let(compiler.aggregate_type, context) {
  macro = compiler.try_parse_macro_target_at(AST_FIELD);
}
```

Snapshot-only regions may use `$let(e.native_aliases, e.native_aliases)` around
mutating work. This removes the named save/defer while adding one redundant
plain assignment; prefer the explicit defer if that spelling obscures intent.
Keep that compatible possibility visible rather than omitting it from census.

Preserve restoration order, not just final field values. Reverse decorator
nesting where several fields restore in written order; compute effectful
replacement expressions first in their original context. In declaration
production, thaw construction before installing privacy. In SDK evaluation,
keep failure message/notes outside and restore all globals before reporting.
Preserve symbol pop, diagnostic callback, free and rollback positions relative
to field restores. An addressed field must remain alive throughout its body.

Parent cleanup review accepted simpler nesting for L19/L20: stack outer,
privacy inner. Their adjacent restoration stores have no intervening observer
or callback, so reversing those two plain stores changes no behavior; thawing
still occurs under the original context. The parent owns and validates these
three declaration regions. This does not relax observable resource cleanup or
callback ordering elsewhere.

### 2. All forty-six compatible `$auto` locals

The defer audit identifies seventeen complete src defers plus captures cleanup
inside `_match_case`'s compound defer. The library has twenty-eight: the prior
twenty List/Array/File sites, five Lisp Scope/File/Block owners, and three
shared map-template sites. No Cleanup adapter or representation change is
needed. Preserve acquisition order, block lifetime and final-binding semantics.

The overlooked map-growth pattern already uses disarming by zero:

```x2c
// Before
Bytes staged_hashes = Bytes_new(sizeof($hash_cell));
defer Bytes_free(staged_hashes);
// After
Bytes staged_hashes = $auto(Bytes_new(sizeof($hash_cell)));
```

Keep pointer reassignment after Bytes_append, ownership moves, old-storage
frees, and `staged_hashes = 0` after publication. Cleanup sees the final zero
and does nothing. Count the two growth temporaries and comparison scratch
Scope as three template sites, not once per map family.

For nonadjacent Lisp.read cleanup, move acquisition into the EXISTING block:

```x2c
Symbol status;
{
  Scope tokens_scope = $auto(Scope.new_named("Lisp tokens"));
  Tokenizer tokenizer = _scan_lisp_tokens(source + base, &tokens_scope);
  status = _read_tokenizer(tokenizer, source, base, cursor, out);
}
return status;
```

Keep `_match_case`'s Array cleanup after both compiler-field restorations.
Array.sort_with's swapped locals must clean the final bindings, not captured
initial handles. Canonical List/String results copy out of scratch storage;
Var payloads retain their original owners. Independent Scope destruction is
not interchangeable with an ambient retained region or destination selection.

### 3. All nine compatible destination regions

Eight existing deferred regions: `_scan_lisp_tokens`, `_call_lambda`,
`_auto_analyze`; two Logger allocation regions; three Match cache/site
preparation regions.

Execution corrected one inventory assumption: nested `$scope` inside
`$lisp.entry` evaluates the outer `$function` SDK forms before substitution.
Hoisting its argument leaves the same problem in the body splice. Retain the
original explicit push/defer; a canonical-AST workaround compiled but added
more machinery than it removed. This is a staging exclusion, not permission
to change macro expansion rules. The other nine sites remain compatible.

The ninth is Pool.retain_named: replace only table construction's
push/map/pop region with `$scope(&pool.scope)`, deleting the `pushed` flag and
conditional rollback pop. The existing outer rollback still conditionally
destroys the initialized native mutex, then the independent Scope. Nested
pop runs first on failure, preserving the existing destruction order.

```x2c
Map table;
$scope(&pool.scope) { table = Map.new_capacity(capacity); }
pool.table = table;
```

No allocation changes owner. Pop frees nothing. Do not widen Match's boundary
past rejection/publication or Logger's boundary past handle insertion. Keep
Lisp MachineBuilder cleanup before destination pop. Preserve remaining Pool
`mutex_ready`/`finished` guards and recursive lock policy.

## Consequential candidates and rejected patterns

The inventory classifies every one of 79 state regions and 30 destination
regions. All Scope operation kinds were examined, including native template
aliases, explicit `_in` allocation, owner queries, moves, destruction and hooks.
There are no remaining executable retain/release pairs; scope.x contains
three documentation examples, which are not migration opportunities.

High-value separate changes include Emitter's five cleanup-barrier regions.
Their paired helpers can disappear if explicit saved barriers become nested
lets. Capture cleanups.length once, preserve switch's unchanged continue
barrier, and preserve type-emission ordering in `_function`. Current helpers
restore only on normal exit; the new defers add error restoration. Parser
lookahead, capture construction, declaration recovery and cache allocation
regions have similar distinctions, recorded per site.

The eight paired compiler Arrays allocate both resources before either defer.
`$auto` protects the first if the second acquisition raises; that is different
failure reclamation. The six prioritized explicit-free compiler locals are
initializer_functions.functions, _initializer_layout.children,
_initializer_adapters.prepared, _lower_callable_defer.records, and the two
per-loop _target_sources.expanded locals. They delete duplicated success/failure
cleanup, but add Error-path cleanup and sometimes require a narrow block to
preserve the early release point.

The raw census found 446 compiler cleanup/consuming call expressions and 213
library cleanup/helper screening entries. These use different documented raw
units and are not additive adoption counts. Most `list_free`/`str_free` calls
already provide protected consuming conversion. Replacing them usually deletes
no statement and changes failure registration or release timing.

Keep conditional transfer guards, consuming parameters, parent-aware Compiler
close_child, staged ParsedUnit/Context lifetimes, SymTxn rollback, Map
presence-sensitive restoration, native allocator contracts, callback-destructor
policy, and cleanup that writes results rather than restores state. Keep Pool,
Logger, descriptor and FILE locks: they are not ordinary Mutex pairs. Scope
moves and shutdown/finalizer registration cannot become lexical cleanup.

## Class decision remains separate

ToolAction is the strongest class candidate: retain its four-argument public
wrapper and forward to generated positional construction with explicit
inherit_stdio=0 and report=1. It deletes seven allocation/assignment/return
statements. Layout and borrowed List ownership remain, but new/free/cleanup,
boxing/printing and one eager custom Var registry row are added. The registry
has 32 custom rows. Do not bundle that additive API into the macro-only set.

AdTape saves little after adding its required explicit init and would gain
nonrecursive free/boxing. Compiler's shared-owner construction, stack-backed
Emitter, contextual GenNames/Project state, and custom runtime allocators are
not useful class substitutions. Generated init is not provided; generated free
is not recursive and is not a Scope finalizer. Source sketches and consequences
remain in the inventory.

## Execution result

The local authored patch changes 24 files, removing 142 physical lines and
142 lines from the existing core-code metric. Parent cleanup adds five
physical authored lines and three core-code lines relative to 1d2c938, so the
combined result is 61,346 -> 61,209 authored physical lines (-137, -0.223%)
and 46,099 -> 45,960 core-code lines (-139, -0.302%). The latter existing
metric includes the unchanged 42-line generated runtime aggregate; generated
bootstrap and symbol artifacts are reported separately.

The integrated safe rebuild passed. The existing focused run passed 335 tests
with 8,059 assertions across Scope, Context, Mutex, Pool, Block, defer, Map,
List, File, Array, typed containers, Lisp, Lisp auto, Match cache, Logger,
lambda and diagnostics. Nine compiler fixtures passed unchanged: managed
initializers, Lisp templates/errors/slots, source parity, callback adaptation
and typed Match success/conflict. No new tests or recurring gate were added.

Independent compiler/library review found no remaining behavior mismatch.
Generated pattern-capture code restores match_types, then in_pattern, then
frees captures. The first build exposed the lisp.entry staging exclusion;
restoring that short explicit region fixed focused translation and the full
build without a compiler change. Header symbols and API references were
regenerated through `make hdr-sync` and `make doc-generate`: their reviewed
deltas are source fingerprints and coordinates only.

Publication proof is `tools/gate-state.py ensure agent-pr-check`; full output
and subsequent matched-power measurements are retained under
`debug/adoption-execution/`. Error-path expansion and classes remain separate
future decisions; this archive does not authorize them.

## Evidence, execution and delivery

Execution is authorized as one compatible adoption campaign. Before production
edits, the baseline at 1d2c938 passed the existing metric and benchmark commands.
Raw outputs, command records, environment and process snapshots are retained in
`debug/adoption-execution/baseline/`. A one-off orchestration script in
`.context/adoption-execution/snapshot.py` repeats these same commands for the
after snapshot; it is not a new repository gate.

- `make stats STATS_COLOR=never`, `tools/repo-metrics.py --json` and
  `--summary-json`: 46,099 code lines, including 26,802 src and 15,919 lib.
- `/usr/bin/time -lp make build-safe`: 6.38 seconds wall; optimize build,
  native artifacts rebuilt, filesystem/compiler caches warm, no cache purge.
- `make list-benchmark` and `make scope-benchmark`: existing five-sample defaults.
- `SAMPLES=3 bash unittest/benchmarks/run-compiler-translation.sh`: stage 0 only,
  existing warmup and three samples in default and live-symbol modes.
  Median aggregate translation times: 1.605487 and 3.779326 seconds.
- Stage 0 executable: 1,674,656 bytes; runtime archive: 1,093,440 bytes.

The host is macOS 15.7.9 arm64, Mac16,5, 16 CPUs, 128 GiB RAM, Apple clang
17.0.0, GNU Make 3.81 and Python 3.14.5. Parent/scanner heavy jobs were held
during the baseline. Background application activity remains uncontrolled, so
these are bounded local observations, not an isolated performance claim.
Power source was not captured in this first run; it may have used AC while
later work used battery. Preserve those results but do not attribute their
difference to the rewrite.

The final comparison repeats baseline 1d2c938 in an isolated checkout and the
integrated tree under the same recorded power source and profiles, without
changing settings. Each side uses one untimed build-safe warmup, three timed
build-safe repetitions, the existing five-sample list/scope checks, and the
same stage-0 compiler warmup plus three samples per mode. Per-command power
and clock checks reject changed power or a suspension gap. The final before/
after timing includes the parent cleanup; static counts separately identify
its authored delta and this campaign's delta. Matched raw records are saved
under `debug/adoption-execution/baseline-matched/` and `after-matched/`.
Generated bootstrap C/H and symbol snapshots are counted separately from
hand-authored source; their baseline counts come from immutable git blobs.


The fresh baseline build and existing focused run passed: 188 tests and 1,589
assertions across defer, mutex, list, array, file, Lisp, Lisp auto, Match cache
and Logger. These establish current contracts, not unimplemented migrations.
The earlier ToolAction-shape/lifetime probe also passed.

For this expanded audit, a temporary copy of map-generics changed ONLY the
three candidate initializers. An isolated typed-map probe compiled and passed
2,000-entry growth, retrieval, equal/unequal comparison and restoration of
Scope live-allocation count. This verifies macro/native-alias binding and
successful transfer cleanup for that copy. It does not inject allocation
failure or prove whole-tree migration parity. Artifacts and setup limitation
were recorded in the inventory before the production migration.

Authorized implementation sequence:

1. Recheck listed owners against then-current main. Implement the compatible
   C set above, keeping each ledger's precise boundaries. Additional E rows
   require an explicit failure-cleanup/restoration scope decision.
2. Use existing focused runtime suites plus macro/lambda/declaration/source-map
   compiler fixtures. Include existing Pool, typed-map, Scope and Context
   coverage for the expanded owners; inspect generated map cleanup ordering.
   Resolve any uncertain callback/rollback boundary with a focused temporary
   probe, not a new recurring test requirement.
3. Review and fix the completed authored diff: trusted producer facts, exact
   cleanup order, alias escape, preserved public APIs, and meaningful deletion.
4. Fetch/integrate current origin/main, review generated deltas, run
   git diff --check, and `tools/gate-state.py ensure agent-pr-check` on the
   final tree. Regenerate through existing owners and re-ensure after changes.
   Delivery follows AGENTS.md and the approved compatible scope.

## Plan review

Existing acquisition, canonical conversion, live-field and Scope boundaries
establish ownership/type facts; no proposed consumer revalidates them. The
compatible set reuses shipped macros and Cleanup implementations, deleting
save/restore locals, explicit defers and destination plumbing. The separate
Emitter proposal deletes both barrier helpers instead of adding a framework.

No new helper, representation, traversal, cache, validator, dedicated
diagnostic, negative fixture or recurring gate is proposed. All 189 defers
have an individual disposition; macro expansions and raw repeated cleanup
calls do not inflate counts. Error-path changes, custom locks and nonrecursive
class cleanup are explicit boundaries. Independent review checked the
complete defer accounting, macro-template coverage, cleanup boundaries and
evidence attribution. Its corrections to table formatting, template metadata
and paired-acquisition wording are incorporated.
