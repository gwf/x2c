# Private Task.run prototype - 2026-10-30

Status: testable local prototype on `codex/async-task-prototype`. No push or
shared-branch integration is authorized. The dev/main validation hold remains.
The [owning specification](../async-execution-stacks.md) records semantics.

## Implemented behavior

Task.run executes zero-argument jobs on its calling native thread. Existing
Channels support native and parked task waiters with the same commitment,
ownership, closure, and drain rules. Jobs borrow caller Scope/Pool, copy
policies/bound, and start with fresh activations and no current Context.
Ordinary Array returns keep identity and allocation ownership.

The prototype includes stable base slots, boundary state exchange, removal of
Scope.up, and the Scope.open/close migration. Authoritative compiler producers,
callers, docs, and handwritten C ABI consumers were migrated. Bootstrap and
nine affected fixture sidecars were regenerated through existing targets.
No old Scope API aliases were added.

The pinned dependency and its local adaptations are documented in
[lib/task/README.md](../../lib/task/README.md). Metadata is separate from the
8 MiB default guarded stack. Minicoro C symbols have local linkage; assembly
entries use an x2c prefix. ASan annotations pair across actual switches and
restore native caller bounds, including final task exit.

## Try it

From the worktree root:

```sh
./x2c run -q examples/power/channel-task-service.x
(cd unittest && X2C_SCOPE_ACCOUNTING=1 ./test-all task_suite)
```

The example prints FIRST and SECOND. Set X2C_TASK_STACK_BYTES before running
to select another usable capacity; the minimum is 32 KiB and pages round up.
This prototype's supported execution evidence is macOS arm64 only.

## Validation evidence

Host: macOS 15.7.9 arm64, Apple clang 17.0.0, optimized ordinary build.

| Check | Result |
| --- | --- |
| Guarded adapter probe | 1,000 switches preserve local addresses, ordinary and ASan/UBSan builds. |
| Full ordinary unit suite | 1,148 passed, 99,489 assertions. |
| Fully instrumented ASan/UBSan unit suite | 1,148 passed, 99,489 assertions; leak detection disabled as in the existing script. |
| Instrumented task suite with stack-use-after-return detection | 13 passed, 57 assertions. |
| Compiler fixture check | 1,352 fixtures passed, 2,988 artifacts, plus the target's existing boundary/meta probes. |
| Request/reply example | FIRST and SECOND. |
| Focused strict translation | Passed in the 2026-10-31 follow-up below. |

The task cases cover Channel request/reply, buffered/rendezvous behavior,
ordinary Array identity/ownership, service and callback failure, stable Context
export destinations, initial inheritance, both cleanup forms, owner Thread
cancellation, committed owned payloads, uncommitted owned-send rollback, and
native-producer/task-consumer notification stress.

Two integration defects were found and corrected: repeated native notifications
could requeue an already selected task, and the original dependency sanitizer
hooks left ASan using task bounds on the native stack during Error transfer.
The ready queue now distinguishes parked from selected tasks. The optional
completion-callback shorthand uses the same rewrite as Thread.run and is
exercised by the Channel-drain test. Correct ASan
boundary pairing replaces the upstream annotations; instrumentation remains
active throughout runtime, tests, and adapter.

The original sanitizer failure remains in debug/async-sanitizer.log. The
successful full instrumented run is debug/async-full-sanitizer-final.log.
The existing sanitizer script built the instrumented archive/tests; changed
Task, native adapter, and task-test objects were rebuilt incrementally and the
complete binary rerun after the fixes. Other logs remain under debug/async-*.

## First local performance comparison

This is a Channel-only integer request/reply workload. Each client performs
4,096 exchanges through one service. Five independent processes per row are
reported as medians; mode order alternates. Process CPU and wall time cover
batch startup, execution, and shutdown. Peak RSS uses getrusage after the batch
and includes the whole process. These are not blocked-task memory samples,
network results, or retired-instruction measurements.

| Clients | Requests | Mode | Process CPU seconds | Wall seconds | Peak RSS MiB |
| ---: | ---: | --- | ---: | ---: | ---: |
| 1 | 4,096 | thread-baseline | 0.022711 | 0.021512 | 1.765625 |
| 1 | 4,096 | thread | 0.022867 | 0.021666 | 1.781250 |
| 1 | 4,096 | task | 0.001015 | 0.001014 | 1.593750 |
| 8 | 32,768 | thread-baseline | 0.147666 | 0.046566 | 2.015625 |
| 8 | 32,768 | thread | 0.150670 | 0.047345 | 2.093750 |
| 8 | 32,768 | task | 0.006401 | 0.006400 | 1.734375 |
| 64 | 262,144 | thread-baseline | 1.286345 | 0.381908 | 3.437500 |
| 64 | 262,144 | thread | 1.296016 | 0.386416 | 3.437500 |
| 64 | 262,144 | task | 0.049340 | 0.049340 | 2.843750 |

The baseline is the pre-task Channel runtime from the isolated owner-state
checkpoint `142a3496bd452728615d3860636b2776fb65d747`. It contains dormant
owner-state exchange helpers but no task Channel bridge or Scope layout/API
migration. Current Thread and Task rows use the same prototype executable.
This separates the execution comparison from a limited native-path regression
comparison. It is not a full original-HEAD performance checkpoint.

At 64 clients, the task backend reserves 520 MiB of usable virtual stack for
65 jobs (service plus clients), plus guards and metadata. The measured RSS is
physical residency and must not be confused with that reservation. Each
request sum is checked; job results are immediate integers, so the native
baseline does not return temporary boxed storage.

The existing Scope hot-path benchmark also ran five samples on both builds:

| Operation | Baseline ns/op | Prototype ns/op |
| --- | ---: | ---: |
| malloc/free | 17.019 | 16.483 |
| region open/close | 20.216 | 19.633 |
| push/malloc/free/pop | 21.289 | 20.657 |
| explicit-slot malloc/free | 16.170 | 16.641 |
| Pool malloc/free | 8.208 | 7.962 |
| List cons miss | 46.330 | 47.295 |

These short timing samples do not establish instruction costs or accept
small regressions. Ordinary allocation still reads the installed TLS slot
directly. Wider representative performance evidence remains outstanding.

Raw workload source, 45 final samples, earlier exploratory samples, baseline
Scope log, and medians remain locally in .context/async-task-prototype/.
That directory is ignored; the executable tests and example are authoritative
tracked source. Binary/archive hashes are retained in its provenance.json.

## Remaining limits and delivery hold

The initial prototype produced four conservative lifetime diagnostics from
the command below:

```sh
./x2c translate --fatal-warnings --out-dir /tmp/x2c-async-strict-2104 lib/task.x lib/channel.x
```

The sites are Task.run's stack-local batch record passed to shutdown and ready
helpers, its stack-local Channel notification link, and Channel's stack-local
rendezvous record. Their valid lifetimes are bounded by completion/unlinking.

The 2026-10-31 follow-up fixed pointer-field provenance and applied Gary's
selected analysis boundary: unknown-lifetime raw stores of frame addresses
remain audit findings and meta errors, while ordinary translation relies on
the owning C lifetime contract. Known retaining operations remain checked
through helper summaries. No runtime lifetime machinery was added.

Focused fatal-warning translation now passes. All 1,355 compiler fixtures
passed (2,994 artifacts), and the optional graph audit checks passed.
`make stage-2` passed; stage 1 and stage 2 generated identical output across
333 C/H files. The final publication gate remains outstanding. See the
[lifetime follow-up](../async-execution-stacks.md#lifetime-analysis-follow-up-2026-10-31)
for the selected boundary and compatibility cost.

The ordinary unit suite was rerun from unittest/ and passed all 1,148 tests
and 99,489 assertions. The stage-two compiler ran the request/reply example
and printed FIRST and SECOND. Documentation drift checks passed. An initial
root-directory unit invocation failed to find ../etc/init.xlisp; both the
preceding checkpoint and this tree pass the Lisp suite from unittest/.

Linux arm64/x86_64 and macOS x86_64 execution, other compiler/ABI/hardening
combinations, TSan, actual network/timer workloads, and broader performance
checkpoints remain unvalidated. Cleanup suspension and nested Task.run are
unsupported by the first API. Explicit Channel operations in cleanup retain
stop checks; there is no general cancellation-masking API.

This session did not advance dev or main, and no push occurred. Passing these
local checks does not accept remaining regressions or lift Gary's required
consent before any push.
