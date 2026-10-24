# c2x2c continuation

> Status: done, 2026-10-24.
> The saved tutorial and tooling were delivered through `e2a78078e`.
> Later thread and Channel work supersedes the implementation described here.

## Closeout

Checked against `7e9fd0178`. Commit `2d6ef8746` changed ParallelMap results
to borrowed values with reducer-controlled ownership transfer. Public
Channel and cooperative `Thread.stop` now exist. Use the current
[thread guide](../../docs/src/guide/contexts-and-threads.md),
[Channel guide](../../docs/src/guide/channels.md), and
[ownership closeout](../detached-channel-ownership.md).

The material below records the original checkpoint. Its automatic export
description, absent-Channel claim, and publication waiver are historical;
they do not describe current behavior or authorize future gate exceptions.

## Historical delivery record

The following status was recorded before this closeout:

> Historical status: reference. Saved on 2026-10-21, then prepared for direct delivery to
> origin/dev at Gary's explicit request. He waived broad publication gates for
> this delivery. The record below distinguishes the original checkpoints from
> subsequent bootstrap and focused checks. Thread/channel redesign remains
> open and is not part of this delivery.

## Saved work and dependencies

The work branch is `codex/tutorial-diff-viewer`. Its starting revision is
`a9bcd6aa81d588c7bab36d6411bee1e69dec014f`. The first checkpoint is
`f72329be` (`add map combination and reusable parallel workers`). The following
checkpoint saves the tutorial, viewer, fixture, manifest entries, and this note.
Keep the commits in that order: tutorial versions 6-7 depend on the first.
Those two commits were initially local checkpoints. The following delivery
commit adds the refreshed bootstrap and this updated record. Publication state
must be checked against the remote; checkpoint creation alone is not evidence.

Canonical sources are `examples/c2x2c/words-v0.c` and `words-v1.x` through
`words-v7.x`. All eight preserve the final prototype bytes. The example README
records stage changes, commands, ordering differences, and count assumptions.
`examples/c2x2c/versions.json` names canonical files for the reusable viewer
under `tools/version-viewer`. Its payload is generated, not an independent
source owner. No external package or JavaScript installation is needed.

The original ignored `.context/tutorial-diff-viewer` directory retains old
provenance, screenshots, and intermediate drafts. `debug/tutorial-viewer`
retains full build and focused-check logs. Those local files are not part of
the checkpoints and are not needed to run the saved examples or viewer.

Packaging checks compared all eight canonical files with their final prototype
bytes and compared the generated payload with those canonical files. The
documented Version 0, 5, and 7 commands compiled and matched their fixture
output. JavaScript syntax checks passed, and all seven adjacent comparisons
retained their added/deleted counts. HTTP index and payload bytes matched the
saved viewer. No new browser session or broad check ran for packaging.

## Current APIs

- `Self Map.merge_with(Self map, Self other, Func combine)` mutates and
  returns the destination. Only collisions call `combine(destination, source)`.
  Disjoint keys are copied. Self-merge combines each entry once. Null behavior
  delegates to existing `Map.merge`. Ordinary `Map.merge` still overwrites.
  Callback failure preserves completed changes; there is no transaction.
- `typedef Var (*ThreadValueFn)(Var input)` is the normal worker callback.
  `Thread Thread.start(ThreadValueFn function, Var value)` copies Var bits.
  It does not clone or transfer the referenced input graph.
- `Thread Thread.start_raw(ThreadFn function, const void *input,
  size_t input_size)` preserves the former fixed-size byte-copy API.
  `ThreadFn` remains `Var (*)(const void *, size_t)`. Live raw callers in
  examples, tests, documentation, site slides, and libuv were migrated by
  matching the receiver and three-argument call shape. Historical plans and
  generated bootstrap sources were not rewritten.
- `Thread Thread.wait_any(Array pending)` removes and returns a finished
  handle without joining. If several are ready, current Array order wins.
  Null/empty input returns NULL. Entries must be unique and exclusively owned.
- `Var Thread.finish_any(Array pending)` waits, joins, and frees one handle.
  Consuming join failures still free it; native join failure retains it for
  retry. Null/empty input returns void.
- `void Thread.finish_all(Array pending)` attempts every join and frees all
  consumed handles, including already-joined handles. It reports captured
  failures after cleanup. During an existing Error unwind, it emits a native
  diagnostic and preserves the primary Error. Native join failures retain
  their handles. The Array and handles require exclusive ownership.
- `ParallelMap Iter.parallel_map(Iter source, ThreadValueFn function,
  int workers)` allocates a Scope-owned description and starts no workers.
- `Var ParallelMap.foldl(ParallelMap map, Var seed, Func accumulate)` consumes
  the description with at most `workers` persistent native threads. A void
  seed takes the first result as accumulator; void worker results raise
  `void-op`. Empty input returns the seed. This is a consuming fold API,
  not arbitrary pull iteration.

## Borrowing, result ownership, and cleanup

Thread inputs borrow referenced storage, including wide boxed scalars. The
input graph and callback code must stay alive while workers use them. Inputs
are read-only. A borrowed Map must not receive worker-private values; return
a fresh Map instead. `Context.export` moves storage; it is not a general
deep-copy operation. Borrowed Maps are not recursively cloned by exporting.

Each ParallelMap job uses Thread's existing isolated work Context and a fresh
result Scope and pool. The worker detaches the result stores and publishes
its handle to a bounded FIFO. The worker then waits. The consumer exports the
result and releases the sealed stores before assigning another input to that
same native thread. A per-job result envelope is not nested under a persistent
callback Context, so reused workers do not retain private canonical ancestors.

The existing process-wide Thread completion mutex and condition variable
protect assignment, stop state, and the ready queue. The queue reserves one
slot per worker. Each worker has one outstanding job or unread result. There
is no eager result Array and no per-file native-thread creation after startup.
Only the consuming thread traverses the source and calls the accumulator.
Queue order records result publication under that mutex, not callback return
timestamps or source order.

The fold's defer signals stop before joining all workers. Idle workers exit;
busy workers finish their accepted jobs and then exit. Cleanup waits and does
not cancel a callback. Source, worker, export, or accumulator failure triggers
the same stop/join path. Ordinary Thread.join/free semantics remain intact.

Source Iter storage must outlive the fold. Temporary chains work only when
the description and fold remain in one full expression. A saved description
needs named Iter storage. `src/transform/expressions.x` adds
`Iter_parallel_map` to the existing temporary-Iter consumer list so the exact
V7 chain compiles. This is a narrow integration, not a general ownership
proof for saved descriptions. Do not infer that a saved temporary chain is
safe merely because the compiler accepts it.

## Focused evidence and limits

Before checkpointing, the final persistent-worker implementation passed:

- `thread_parallel_map_suite`, `thread_start_suite`,
  `thread_finish_any_suite`, and `thread_finish_all_suite`: 13 tests,
  77 assertions. Log: `debug/tutorial-viewer/persistent-workers-tests.log`.
- The four ParallelMap tests account for 47 assertions. Sixteen inputs produce
  sixteen exported Map/String results, four distinct native thread identities,
  and a per-thread job counter above one. This proves actual thread reuse,
  rather than relying on possible reuse of OS thread identifiers.
- A gate holds job 0 while job 1 completes. The first accumulator call must
  receive job 1 before releasing job 0. This verifies ready-result progress
  while earlier work is blocked. Simultaneously queued FIFO order was reviewed
  in source, not separately forced by a test.
- Worker concurrency stays within the requested bound. Results remain readable
  after job envelopes and native threads are released. Worker, source, and
  accumulator failures finish all accepted jobs and preserve primary errors.
- V7 matches V6 and independently calculated output on 17 nested files and an
  empty directory. Both return 0 with empty stderr. V7 remains 37 lines.
  Log: `debug/tutorial-viewer/persistent-workers-v6-v7.log`.
- Earlier `thread_wait_any_suite`: 3 tests, 15 assertions. Earlier Map suite
  including merge_with: 28 tests, 4769 assertions. These were not rerun after
  the persistent-worker change. Logs: `wait-any-tests.log` and
  `merge-with-tests.log` under the same debug directory.

Expected failing-worker diagnostics appear during failure tests. Native
pthread join failures were not fault-injected. Optional libuv caller migrations
were not executed. There is no broad thread-suite, full unit-suite, stage-3,
full self-host comparison, performance checkpoint, or publication-gate claim for
this final tree. Saved source bytes do not imply those checks passed.

## Build state and restart commands

The original worktree completed `make build-safe` before API work; its log
is `debug/bootstrap.log`. Subsequent `make build` calls rebuilt the local
compiler/runtime. The last persistent-worker build passed, and the local
`builds/0/x2c` compiled V7. Generated API docs were refreshed through
`make doc-generate`; `git diff --check` passed before the first checkpoint.
The original checkpoint did not refresh `bootstrap/`. For the authorized
delivery, `make bootstrap-refresh` regenerated bootstrap through its owner
and compiled it. `make rebuild-from-bootstrap` then rebuilt the compiler and
runtime from that refreshed bootstrap. All six changed bootstrap C/H files
match their counterparts regenerated by the rebuilt compiler. This is a
focused comparison of the changed outputs, not a full stage comparison.

The rebuilt compiler compiled V7, whose fixture output matched with exit 0
and empty stderr. The four focused Thread/ParallelMap suites passed again:
13 tests, 77 assertions. Logs are `c2x2c-bootstrap-refresh.log`,
`c2x2c-rebuild-from-bootstrap.log`, `c2x2c-delivery-v7-build.log`, and
`c2x2c-delivery-focused-tests.log` in `debug/tutorial-viewer`. No authored
compiler/runtime change was needed because origin/dev still matched the
starting revision when fetched. Generated bootstrap deltas and the complete
authored diff were reviewed; `git diff --check` passed.

In the existing worktree, use its current `builds/0/x2c` for focused work.
In a fresh worktree, follow the existing setup requirement first:

```sh
mkdir -p debug
make build-safe >debug/bootstrap.log 2>&1
```

Useful focused restart commands, from the repository root:

```sh
make build >debug/c2x2c-build.log 2>&1
make -C unittest test-all >debug/c2x2c-tests-build.log 2>&1
unittest/test-all thread_parallel_map_suite thread_start_suite \
  thread_finish_any_suite thread_finish_all_suite

builds/0/x2c build examples/c2x2c/words-v7.x \
  --output /tmp/c2x2c-v7 --build-dir /tmp/c2x2c-v7-build
/tmp/c2x2c-v7 examples/c2x2c/input

python3 tools/version-viewer/refresh-snapshots.py
python3 -m http.server 8765 --bind 127.0.0.1 \
  --directory tools/version-viewer
```

Open `http://127.0.0.1:8765/?tutorial=ready`. Check whether the owned local
server is already running before starting another. The generator embeds a
content hash in the snapshot script URL. Append its printed hash to the page
URL as `&v=HASH` if HTML is cached. Do not clear browser storage.

## Unresolved design and later integration

The general thread/channel API remains open. No public Channel, scheduler,
cancellation API, generic pull-based parallel iterator, or input deep-cloning
facility has been decided or implemented. The saved private completion queue
serves ParallelMap.foldl. It is not approval for a general channel design.
Any replacement should reassess that private mechanism and the narrow compiler
chain integration against the intended design, rather than preserve both by
default. No new thread design is authorized by this packaging checkpoint.

Gary explicitly selected direct delivery into origin/dev after the two local
checkpoints. That instruction supersedes the original publication deferral.
The delivery uses the focused evidence above and skips the full publication
gate, broad suites, stage-3 checks, and performance checkpoint at his request.
The existing push hook remains enabled; no hook or rejecting review is bypassed.
Push destination is `HEAD:refs/heads/dev`, without force or any main update.

Future work must inspect then-current source and instructions. This one-time
validation waiver is not a new standing publication policy. No gate, recurring
test, process step, or threading redesign is added by this delivery.
