# Greenfield estimate: runtime infrastructure and services (map 2.10, 2.11)

Area: lib/error.x, error-macros.xmacro, error-private.xmacro, error_init.x,
exception.x, scope.x, pool.x, logger.x, context.x, thread.x, thread-state.x,
mutex.x, func.x, iter.x, protocols.x, lib.x, file.x, path.x, process.x,
json.x, scan.x, args.x, diff.x, digest.x, static-init.x, clibc.x, cmath.x,
scripting.x, autodiff.x, autodiff.xmacro. Current total: 12,410 lines
(`wc -l`, 2026-09-26). Comment lines are 35-45% of every file in the
group (error.x 361/1356, scope.x 395/1026, iter.x 388/878); the estimates
below keep documentation at the same density, because the module pages
under docs/src/library/modules are generated from those comments and count
as hand-authored.

Headline: this area is mostly at its floor. The from-scratch design lands
at about 9,200 lines with autodiff moved to a package, or 10,350 with it
kept. The savings are four structural facts, not compaction: (1) error
records own three regions where one suffices; (2) `Error` keeps two
parallel stacks (handlers and exception frames) and spends ~400 lines
reconciling them; (3) one "copy a value graph into another owner" walk is
written five times; (4) autodiff is a source transform nothing in the
runtime, compiler, or commands consumes.

## 1. Feature and contract inventory

Map section 4 rows owned here, with the contract each must keep:

- raise, filtered catch, finally, defer (lib/exception.x, lib/error.x):
  `%(CODE @DETAIL)` selection with Match binders; arms prepared once per
  process for literal patterns and per registration for `$` patterns
  (language.md:3070-3080); selected arm consumes the slice since its
  registration; the registration is removed before the arm runs; every
  shared cause in error-macros.xmacro never returns (language.md:3084);
  cleanup runs before the arm, LIFO, at most once per exit path; a raise in
  a finalizer replaces the pending Error and reaches the enclosing frame
  (exceptions.md "Raising during cleanup"); return expressions evaluate
  before cleanup; `break`/`continue` stop at their loop; volatile locals are
  the compiler's job (language.md:3108-3116). Emitter contract: one
  `ExceptionFrame` per `try`, `X2CCleanup` per defer region, static
  `ErrorCatchSite` per filtered try (src/emit.x:590-635, 520-540).
- handler stack and accumulated errors (lib/error.x): observers see errors
  since registration, innermost first; `<handled>`/`<declined>`/`<fatal>`;
  observers cannot consume a non-returning cause; policies `<abort>`,
  `<log>`, `<collect>`, `<ignore>` for user codes only; `Error.snapshot`
  copies into the caller's outermost owners; `Error.since(mark)`; bound;
  per-record independent storage so closing a handler reclaims its slice
  without touching application pools (error.md:634-639); allocation-free
  floor (error.x:13-14); thread policy capture/adopt (error.x:790-870).
- transfer frames (lib/exception.x): 10 documented `x2c_*` entry points
  listed in x2c-c-api.md:15-39; nine more for error catch sites and raise.
- Scope (lib/scope.x, memory.md): retain/release nesting with abort on
  imbalance; push/pop slots; `_in` allocators with lazy slot fill; free,
  realloc, move (pointer-stable, follows finalizer), memdup; finalizers run
  exactly once, LIFO, may allocate scratch into the dying scope, must not
  raise; named scopes and the exit leak report; `Scope.stats` fields
  (scope.md); destroy refuses root, pushed slot, attached lower region;
  shutdown hooks reverse order; per-thread release.
- Pool (lib/pool.x, memory.md "Bounding temporary canonical Lists"):
  outward-shadowing intern chain with one canonical pointer per equal
  value; `Pool.open/close/detach/current`; promotion is pointer-stable and
  recursive (`List.promote`); `Pool.is_permanent`; `Pool.epoch` for Match
  caches (match.x:2055); lock elision until `Pool.thread_start`
  (pool.x:136-147, measured: locking added a seventh to translation);
  `Pool.stats`.
- Context (lib/context.x, contexts-and-threads.md): owns Scope, Error
  state, Match state; isolated adds a pool; failed open restores everything
  (context.x:75-98); export moves Array/Map/Block/Buffer/wide boxes
  identity-preserving, recanonicalizes private String/Atom/List, walks
  cycles, rolls back a container's owner on failure, calls
  `T.export_context` for custom values; `void` exports as `void`; typed
  containers follow (typed-array.x, typed-map.x, outside this area).
- Thread (lib/thread.x): copies input bytes at max_align_t; isolated
  Context per worker; sealed result pool and Scope until join; `<join-fail>`
  carries the worker's captured errors; policy adoption; 8 MiB stack;
  shutdown rejects unjoined workers; descriptor freeze at first start;
  `Pool.thread_start` before `pthread_create`.
- Mutex, static-init (language.md:2284-2300: once, retry after Error,
  cross-thread cycle detection, `threaded` per thread), Logger (levels,
  ordered sinks, reentrancy, memory sink retention across a Context close,
  one `<err-report>` per `<abort>`/`<log>` error, shutdown replay), Func
  (17 ops; the adapter readers the compiler emits), Iter (28 ops;
  caller-owned storage; no `void`), the protocol declarations, DisjointSet.
- Services: File (stdio 1:1, file.x:30-53), Path (absent removal
  succeeds, glob grammar), Process (runs once, reaped with its Scope), Json
  (last key wins, byte-ordered keys), scan (allocation-free tokenizer
  scanners), Args (`<bad-arg>` not exit), Diff (Myers, 2,000-edit limit),
  Digest (SHA-256), clibc/cmath (`meta` prototypes), scripting.x.
- autodiff: `$ad.dual`, `$ad.forward()`/`$ad.reverse()` over the typed
  AST, runtime tape fallback (autodiff.xmacro:1-23, autodiff.x:1-12).

## 2. The design, component by component

### 2.1 error.x: one frame chain, one record region, one render sink

Thesis: a raise needs one per-thread chain of frames, ordered by
registration, where each frame is a cleanup record, a finally landing, a
filtered catch, an observer, or a Context overlay. Today the chain is split
across `ErrorHandler` (heap, error.x:2-14 of error-private.xmacro),
`ExceptionFrame` (C stack, exception.x:34-45) and `X2CCleanup`, and the
split costs: `error_handler_head`, `error_landing_head`,
`error_dispatch_depth`, `error_stack_height` on every frame
(exception.x:92-115); `Error.handler_head`, `unwind_head`,
`restore_landing`, `trim`, `restore` (error.x:341-397); `_chain_contains`,
`_handler_at_depth`, `_unwind_to`, `_reclaim_hidden` and the `running_top`
chain for detached arms (error.x:993-1085, 279-320); the frame `target`
pointer stored in the handler and validated again at unwind
(exception.x:118-136).

Greenfield `struct ErrorFrame { prev; Symbol kind; int watermark; ... }`
with a per-kind payload. `try` emits one frame holding the `sigjmp_buf`,
the site pointer, the selected arm, the retained records, and the capture
block; a defer region emits a `<cleanup>` frame with `fn`/`env`; `Error.push`
allocates an `<observer>` frame in the error Scope; `Context` pushes an
`<overlay>` frame that carries the policy Map and bound and replaces
`ErrorContextState` (error.x:463-466, 1112-1160). Dispatch walks the chain
from the top, skipping non-handler kinds; while a callback runs, a
per-thread `dispatch_floor` points at it so a nested raise starts at
`floor.prev` (this replaces hiding the chain by truncation,
error.x:1230-1236, and therefore the saved-chain restore at landing).
Unwind walks the true chain from the top to the selected frame, running
`<cleanup>` frames (unlinked first, growth discarded after, as
exception.x:225-243), landing `<finally>` frames that have not claimed,
popping `<observer>` and `<overlay>` frames (an overlay closed by an
unwind keeps records, as context.x:342), and abandoning frames whose
finalizer raised (exception.x:127-131). Landing sets the top to the
selected frame; nothing needs restoring. Detach-before-arm becomes
`frame.state = <landed>`: the frame stays on the chain but dispatch skips a
landed frame, and `x2c_error_catch_close` on leave frees its retained
records. Shutdown from `exit()` inside an arm or callback walks one chain
(error.x:1050-1064 goes away).

Records: `ErrorRecord { Pool pool; List entry; }`. One Pool per record
replaces the Scope plus two Pools of `ErrorRegion` (error-private.xmacro:
7-11, error.x:530-545): String and List already share one pool stack
(pool.x:16-17; `Error.snapshot_in` passes one pool for both,
error.x:711-712), and `Pool.malloc` above 512 bytes uses the pool's own
Scope (pool.x:864), so wide boxes go there. Per-record independence
(error.md:634-639) and out-of-order retained records (`_catch_retain`,
error.x:1166-1180) are kept at a third of the construction cost.

Copying detail and snapshots uses the shared value-transfer walk (2.4)
with an `admissible` mode that reaches the floor for identity-bearing
values (error.x:597-618). `_record` and `_record_n` (error.x:643-690)
become one builder over a cursor that reads either a List or a va_list.

Rendering: `Error` owns one render hook, defaulting to the two-line stderr
fallback (error.x:509-514). `Logger.initialize` installs its renderer; the
hook is invoked once per unhandled `<abort>`/`<log>` record, which removes
`rendered[]`, `Error.note_rendered` (error.x:322-330), the observer that
`Logger` registers (logger.x:826-846), the second `Error.push` in every
worker (thread.x:178-179), `logger_error_mark`, and the shutdown replay of
collected root errors (logger.x:857-872): the hook renders collected
records at shutdown through the same call. Answer to the brief's question:
error, exception, and logger share one frame and one sink; the logger
keeps its own sink list because sinks are the logger's feature.

Kept as today, each a documented hard case: static versus transient
catch-site binding under a recursive mutex (error.x:62-134), fence
reporting at registration (error.x:194-203), policy capture/adopt, the
bound, the floor, `Error.since_in`/`snapshot_in` for sealed worker
storage. The catch-site and logger mutexes become one
`Mutex.recursive_static` primitive in mutex.x (map rebuild note).

### 2.2 region.x: Scope and Pool with one lifecycle and two storages

Answer to the brief's question: they can share one file and one lifecycle,
but not one storage strategy. Scope allocations must be individually
freeable, resizable, finalizable, and movable pointer-stably to any scope
(memory.md "Moving a value out of a scope"), which needs the intrusive
header and links (scope.x:66-94). Pool values are bulk-released and
promoted only to the parent, which is what the slab bitmap and block
transfer express (pool.x:369-425); a slab slot cannot be moved to an
arbitrary scope without copying, so putting Scope's small allocations in
slabs would break `Scope.move`. Conversely, putting cons cells through the
header path costs a malloc per cell and 32 header bytes; the build-cost
score moved 128 -> 176 on the Pool.promote regression
(agents/performance-checkpoints.md:52-56), which shows how sensitive
translation is to this path. So: header storage for Scope, slab storage
for Pool, as today, both at their floor.

What merges: the per-thread active slot/stack, the `_lock`/`_unlock`
wrapper quartet (pool.x:158-190 plus scope.x:113-121) become one
`$region.locked` decorator; names become a `const char *name` field on the
region plus one intrusive list of named regions under the existing
metadata mutex (replaces `ScopeName` registry, scope.x:96-100, 232-270);
`ScopeRetain` records (scope.x:102-105, 272-300) become a `slot` field on
the region written at retain and checked at release, which gives the same
"release from a different pushed slot aborts" diagnostic (memory.md);
`Pool.child_capacity` (pool.x:45, 467-471, 528-532) goes; the two
shutdown and thread-release paths become one; `PoolStats` and `ScopeStats`
stay as documented snapshots over one counter block. `struct Pool` embeds
`struct Region`, so `Scope` keeps its 24-byte size and the retain/release
loop is unchanged. Pool's depot, page index, intern chain, `Pool.own`,
`promote`, `epoch`, `is_permanent`, `detach` survive unchanged (see 4 for
the depot as an optional trade).

### 2.3 context.x: an aggregate, with export as the shared walk

Answer to the brief's question: export is not a property of the allocator,
because it is selective (unexported values are reclaimed,
contexts-and-threads.md:5-7) and because private canonical values change
pointer when they meet an equal value in the destination chain. Merging a
child pool wholesale into its parent is exactly `Pool.promote` applied to
every value and would keep garbage alive. What export is, is the same walk
as `List.promote` (list.x:86-124) generalized to mutable containers, and
that walk already exists five times (2.4). Context becomes the aggregate
`open`/`close` (context.x:100-136, 322-350) plus `owns`,
`move_allocation`, `export_destination` for custom exporters, and
`export`/`export_nested`/`export_scope` as three entry points into the
walk with mode `<move-if-owned>`. About 200 lines.

### 2.4 One value-transfer walk (var.x addition, ~100 lines)

Five copies of "switch on tag; scalars pass; wide boxes clone or move into
a Scope; String/Atom copy or promote into a pool; List recurse and cons in
a pool; containers move or reject": error.x:597-618 (`_copy_value`),
error.x:743-770 (`_snapshot_value`), logger.x:536-563
(`_memory_retain_value`), context.x:186-284 (`_export_*`), list.x:90-102
(`_promote_node`). One `Var.transfer(Var, Pool dest, Scope *values,
Symbol mode)` with modes `<copy>` (error records, snapshots),
`<copy-if-foreign>` (logger memory sink), `<move-if-owned>` (Context
export, Thread join), `<promote>` (List/String promote to parent). The
`admissible` check for error detail is a mode flag; container arms are
taken only in `<move-if-owned>`. This deletes about 210 lines and adds
about 100. Map cycle handling stays where it is (`Map.export_to`,
map.x:464) and is called from the container arm.

### 2.5 logger.x

Keeps levels, sink list, reentrant text sink with per-depth scratch
buffers (logger.x:361-390), color rendering, memory sink, the twelve
generated level functions. Loses its recursive-mutex block, its value
walk, `Logger.error_handler` as an observer, and the shutdown replay. The
public `Logger.error_handler` symbol survives as the installed render hook
so logger.md and test-error `error_logger_handler_is_registered` still
have a referent.

### 2.6 thread.x, thread-state.x, mutex.x

Thread keeps its shape; `_run` pushes one `<observer>` frame instead of
two, and `_capture_errors` and `Thread.join` call the walk. mutex.x gains
the shared static recursive primitive (~25 lines).

### 2.7 func.x, iter.x, protocols.x, lib.x

Survivors. Func's readers are the emitted adapter contract
(func.x:114-243). Iter's 28 operations are each a `_next` callback and a
constructor; a `$iter.stage(name, state-init, next-body)` macro for the
eight single-state stages (enumerate, repeat, head, accumulate, scan,
unique, chain, filter) removes the repeated `Iter.init` scaffolding, about
80 lines, without changing the emitted code.

### 2.8 Services

All twelve are thin over the host or over one algorithm and are survivors
with 3-7% trims from one shared host-error helper (`_error(operation,
errno)` exists at thread.x:83, mutex.x:36, and file.x:91).

### 2.9 autodiff: a package

Nothing in src/, commands/, or lib/ consumes `$ad.*` or `AdTape`; the only
runtime reference is `#include "autodiff.x"` at lib/lisp.x:36 with no
named use. Both files are already optional (lib/Makefile:7-10), and the
transform depends only on the public meta surface (meta.x:157). As a
package it keeps its guide chapter, examples, and fixtures the way
packages/torch does. If Gary keeps it in lib/, the map's rebuild note
applies: one mode-parameterized statement walker for forward and reverse
(autodiff.xmacro:466-630 versus 660-900), about 1,150 lines.

## 3. Line ledger

Current, by file (12,410):

| group | files | lines |
|---|---|---|
| error | error.x 1356, error-macros 41, error-private 28, error_init 27, exception.x 267 | 1,719 |
| regions | scope.x 1026, pool.x 965 | 1,991 |
| logger | logger.x | 859 |
| context | context.x | 370 |
| threads | thread.x 309, thread-state.x 32, mutex.x 99 | 440 |
| callables | func.x 443, iter.x 878, protocols.x 85, lib.x 93 | 1,499 |
| services | file 591, path 544, process 578, json 570, scan 749, args 312, diff 171, digest 130 | 3,645 |
| small | static-init 147, clibc 27, cmath 129, scripting 18 | 321 |
| autodiff | autodiff.xmacro 1402, autodiff.x 164 | 1,566 |

Greenfield, by component, with the anchor for each estimate:

| component | lines | anchor and accounting |
|---|---|---|
| error.x (frames, records, dispatch, sites, policy, floor) | 950 | error.x+exception.x code is 1,038 of 1,623; deletions itemized in 2.1 total ~390 code lines (two-stack reconciliation 150, running/hidden chains 70, context state 30, three-owner regions 30, two value walks 80, rendered/note 15, record builders 40); 650 code + 300 comments. Comparable scope: lib/match-recursive.x, 445 lines, is one matcher with captures; a frame chain with five kinds and a match-driven selector is about twice that |
| error-macros.xmacro | 40 | unchanged |
| region.x (Scope + Pool) | 1,550 | 1,201 code lines today; merges in 2.2 remove ~200 (retain records 45, name registry 35, lock wrappers 25, child_capacity 10, duplicated lifecycle 40, stats plumbing 20, shared host-error helper 25); 1,000 code + 550 comments over 35 documented operations |
| value-transfer walk (in var.x) | 100 | one switch of ~12 arms with four modes; the largest current copy, context.x:186-284, is 100 lines for one mode |
| context.x | 200 | open/close/failure rollback (context.x:100-136, 322-350) is 90 code lines and survives; export becomes three one-line entries |
| logger.x | 720 | 595 code today; minus walk 30, mutex block 30, error handler and replay 60, host-error 10 |
| thread.x, thread-state.x, mutex.x | 410 | thread 260 (one observer, walk for snapshots), thread-state 32, mutex 120 |
| func.x | 430 | survivor; `_reference_argument` and its two wrappers fold |
| iter.x | 800 | survivor; `$iter.stage` for eight stages |
| protocols.x, lib.x | 178 | unchanged |
| services (eight files) | 3,500 | survivors; shared host-error helper and json reader/writer share `_write_line`; scan.x belongs to the front-end ledger but is counted here at 720 |
| static-init, clibc, cmath, scripting | 321 | unchanged |
| autodiff | 0 (package) / 1,150 (kept) | 2.9 |

Totals: 12,410 current; 9,199 with autodiff as a package (26% less);
10,349 with autodiff kept (17% less).

## 4. Rope trades (the brief's 2x)

None of the changes in section 2 trade speed for size; each is expected
neutral or faster, and section 7 names the measurement that confirms it.
Two optional trades exist and are listed so Gary can decline them:

- Pool depot removal (pool.x:298-360 depot half of `_block_lease` and
  `_block_return`, `PoolStats` depot fields, `POOL_DEPOT_COUNT`): saves
  ~50 lines and the process-lifetime 50 MB retained backing measured in
  plans/archive/memory-retention.md:36-45. Cost: one `malloc`/`free` per
  4 KiB block per bracket. Expected factor: at most 1.1x on
  `pool-malloc-free` and `raise-catch` (each raise opens a bracket,
  error.x:1206), unchanged on `list-cons-miss`. Measure with
  unittest/benchmarks/run-scope-hot-paths.sh and the exception benchmark
  in section 7 before and after; reject if either exceeds 1.1x.
- Scope stats CAS loops (scope.x:134-152): dropping `largest_request` and
  `peak_live_requested_bytes` saves ~20 lines and speeds `malloc-free`; a
  drop (section 8), not a slowdown, listed here because it changes a
  documented struct.

Declined, recorded so it is not re-proposed: replacing Pool slabs with
header-linked allocations would save ~350 lines (pool.x:60-130, 200-425)
at an expected 1.3-2x on `list-cons-miss`, visible on the translation
CSV, and gives up the measured registry-walk fix (pool.x:96-99).

## 5. Survivors

Already at the floor, kept with their lines: func.x (430 of 443),
iter.x (800 of 878; the trim is scaffolding), protocols.x 85, lib.x 93,
file.x (~570; the `protocol FILE *(T)` table is the smallest stdio
binding), path.x (~520), process.x (~550), json.x (~530), scan.x (~720),
args.x (~300), diff.x 171, digest.x 130, static-init.x 147 (cross-thread
cycle detection is the documented hard case, language.md:2289-2291),
clibc.x 27, cmath.x 129, scripting.x 18, thread-state.x 32,
error-macros.xmacro 41. Inside the redesigned files these regions survive
unchanged: catch-site binding (error.x:62-134), policy capture/adopt
(error.x:790-870), the floor (error.x:500-514), the Scope allocation core
and finalizers (scope.x:318-380, 730-1000), Pool slab storage, depot, page
index, intern chain, promotion (pool.x:60-130, 200-425, 640-965), Logger
rendering (logger.x:280-390), Thread start/join/free (thread.x:225-309).
About 8,600 of the 9,200 estimated lines are survivors; the rebuild of
this area is the 1,700-line error/context/walk core.

## 6. Hard cases and how the design handles each

Named by the pinning test in unittest/.

1. `raise_in_finalizer_reaches_outer_frame`, `frame_cleanup_claims_once`:
   a `<finally>` frame that claimed (exception.x:167-171) is skipped by
   unwind and abandoned; the replacement Error's transfer discards the
   frame's carried records at leave, as `_frame_trim` does.
2. `cleanup_chain_unlinks_before_callback`, `cleanup_chain_reads_latest_
   value_before_jump`: a `<cleanup>` frame is popped before `fn(env)`; the
   env is the emitter's pointer struct (emit.x:520-540), unchanged.
3. `error_dispatch_firewall_skips_active_handler`, `error_handler_head_
   survives_transfer`: `dispatch_floor` starts a nested raise at
   `floor.prev`; unwind always walks from the true top, so cleanups
   registered above the running handler still run. This is the case the
   current `dispatch_saved`/`unwind_head` pair exists for.
4. `filtered_catch_relabels_privately`, `error_catch_arm_leaves_its_
   registration`: a landed frame is skipped by dispatch; a raise inside
   the arm walks past it to the outer frames.
5. `filtered_catch_binder_survives_transient_pools`, `error_regions_do_not_
   capture_application_pools`, `filtered_catch_binder_survives_callee_
   scope`: captures are copied into the record's own Pool (2.1) before the
   arm runs and the record moves to the frame's retained block; closing the
   try body's `Pool.open` bracket cannot reach them.
6. `context_preserves_unhandled_error_for_outer_catch`: an `<overlay>`
   frame popped by unwind keeps records; popped by `Context.close` in
   normal flow it truncates to its watermark.
7. `thread_workers_bind_one_catch_site`: site binding under the recursive
   static mutex, unchanged; the atomic state field is read by every
   registration (error.x:106-134).
8. `error_snapshot_wide_fills_an_empty_slot`, `_snapshot_wide`
   (error.x:723-733): the walk's `<copy>` mode with a NULL `values` slot
   allocates through the slot and writes back the created Scope, as
   `Error.snapshot_in` documents.
9. `thread_errors_stay_private_until_join`, `thread_error_wide_values_
   survive_until_join`: `_capture_errors` copies into the sealed result
   pool and its Scope through the walk; join exports with
   `<move-if-owned>` from that pool.
10. `logger_memory_sink_outlives_registration_context`: the memory sink's
    `<copy-if-foreign>` mode interns into the pool captured by
    `Logger.new`; wide values keep the private Scope moved on retirement
    (logger.x:610-617).
11. `scope_release_requires_matching_retain`, `_release_wrong_slot`,
    `scope_destroy_detached_contract`: the region's `slot` field replaces
    the retain array; release checks `top.slot == active`; destroy still
    refuses root, a pushed slot (stack scan), and `up != NULL`.
12. `scope_finalizer_*`, `pool_promote_*`, `pool_release_and_parent_
    allocation_do_not_deadlock`, `logger_recursion_and_locked_sink_list`,
    static-init cross-thread cycle: the storage, lock order (storage,
    child, parent), emission depth, and guard code are unchanged.
13. `context_exports_cyclic_arrays_and_maps`, `context_failed_export_
    restores_container_owner`: the container arm of the walk moves the
    identity first and restores the owner on failure (context.x:220-256),
    unchanged in substance, moved into the walk.
14. `exit()` from an arm or observer callback (error.x:1050-1064): shutdown
    walks the single chain from the top, freeing every frame kind; no
    hidden span exists.

## 7. Experiments

All against builds/0, each with a baseline run on current dev first.
1. Frame-chain cost: translate and run unittest/benchmarks/
   exception-hot-paths.x exactly as run-scope-hot-paths.sh does
   (`builds/0/x2c translate --out-dir unittest/build/exc
   unittest/benchmarks/exception-hot-paths.x`, then `cc -O2 -iquote
   include/x2c -iquote builds/0/src unittest/build/exc/exception-hot-paths.c
   -Lbuilds/0 -lx2c -lm`), 5 samples of `try-normal` and `raise-catch`.
   Prediction: try-normal within noise, raise-catch 1.3-2x faster from the
   one-Pool record (three region constructions become one).
2. One-Pool record alone, before any other change: a 4-line patch to
   error.x `_region_new`/`_region_destroy` (region.strings = region.lists,
   values = pool.scope) and the same benchmark; this isolates the record
   saving from the frame merge and runs `make check` on the error, exception,
   context, thread, and func suites.
3. Region merge: unittest/benchmarks/run-scope-hot-paths.sh, all six rows,
   before and after. Prediction: `malloc-free`, `retain-release`,
   `push-malloc-free-pop`, `malloc-in-free`, `list-cons-miss` within noise;
   `pool-malloc-free` within noise (depot kept).
4. Value walk: `grep -n "is <lsym>" lib/error.x lib/logger.x
   lib/context.x lib/list.x` finds 5 copies today and one in var.x after.
   Run the error, exception, context, thread, logger, list, string, and
   pool suites and examples power/contexts, power/threads,
   power/shared-threads, programs/mandelbrot (examples/manifest.txt:38-56).
5. Render hook: unittest/probes/run-error-floor and error-fatal.x, plus
   test-logger `logger_error_handler_renders_only_selected_newest` and
   test-thread `thread_memory_sink_retains_worker_events`; the expected
   stdout files pin the single `<err-report>` per error.
6. Autodiff isolation: `grep -rn 'ad_\|AdTape\|\$ad\.' src commands lib
   --include='*.x' --include='*.xmacro' | grep -v 'lib/autodiff'` must be
   empty except lib/lisp.x:36 and the comments at lib/lisp.x:2323,
   lib/meta.x:157; then build with the include removed and run
   unittest/compiler-fixtures/comptime-autodiff.x to learn whether the
   compile-time session needs the `<adnode>` descriptor.
7. Depot trade (only if taken): experiments 1 and 3; reject above 1.1x on
   `pool-malloc-free` or `raise-catch`. After the area lands, `make
   bm-build-scaling` (agents/performance-checkpoints.md:37-45); a rise past
   the 4-point noise band is a regression to find with 1 and 3.

## 8. Drops (each with justification and lines)

- autodiff.xmacro and autodiff.x out of lib/ into packages/autodiff:
  1,566 lines leave the runtime tree; the feature, guide chapter,
  examples, and fixtures move with it. Justification in 2.9: no consumer in
  src/, lib/, or commands/, already optional, depends only on the public
  meta surface. Consequence: packages are outside `make check`
  (AGENTS.md repo map), so the fixtures under unittest/compiler-fixtures/
  autodiff-*.x would need a package-local check or a documented exception.
- `ScopeStats.largest_request` and `.peak_live_requested_bytes`: 20
  lines and two CAS loops on the malloc path; documented fields, no test or
  runtime reader (`grep -rn largest_request src lib commands unittest`
  finds only scope.x and the doc). Behavior pinned: none.
- `Logger.error_handler` as an observing `Error` handler and
  `Error.note_rendered`: 60 lines across logger.x, error.x, thread.x;
  replaced by the render hook (2.1). The observable behavior (one
  `<err-report>` event per unhandled `<abort>`/`<log>` record; worker
  `<log>` causes pass through the global Logger; collected root errors
  reported at shutdown) is preserved; the public function name survives.
- `Pool.child_capacity` heuristic: 10 lines; the child table starts at the
  last released child's capacity to avoid rehash. Behavior pinned by
  `pool_reuses_child_table_capacity`; that test would change, so this drop
  needs Gary's yes and is the smallest item here.
Not dropped: `x2c_error_catch_push` (five tests, e.g. test-error.x:103,
test-func.x:674; documented C API), `Error.since_in`/`snapshot_in`,
`Pool.detach`, `Pool.epoch`, `Context.export_scope`, the Scope `_in`
variants, the leak-report names, Logger color, Iter unzip. Each is
documented and has a consumer in thread.x, match.x, or the book.

## 9. Risks

- The frame-chain merge touches every emitted `try`, `defer`, and `raise`;
  the 19 `x2c_*` names in x2c-c-api.md:15-39 are documented, so the design
  keeps names and signatures (an `ExceptionFrame` gains the fields
  `ErrorHandler` had). packages/libcurl, libuv, and torch call only
  `Error.snapshot` and `Context.open`; not verified whether any package
  emits frames by hand.
- The `dispatch_floor` scheme must reproduce `error_handler_head_survives_
  transfer`; the comment at error.x:1226-1231 describes the subtle case (a
  handler that raises must still hand every registration to the cleanups
  between the raise and the landing). A prototype against test-error and
  test-exception is the only proof; the estimate assumes it succeeds.
- One Pool per record still pays one recursive mutex init per raise
  (pool.x:483-492), down from two; a lock-free pool is not proposed.
- The value walk carries four modes in one function; if the modes diverge
  in ways I did not read (typed-map key collapse lives in typed-map.x and
  is untouched), the walk stays at 100 lines but the deletions shrink.
- Git history is squashed (single 2026-09-24 commits for pool.x and
  error.x), so the measurements behind the slab, page index, and lock
  elision are known only from source comments (pool.x:96-99, 136-147,
  660-666) and the build-cost note; the declined slab trade rests on
  those and on experiment 3.
- scan.x is counted here at 720 but is the tokenizer's dependency; the
  front-end ledger must not count it twice.
