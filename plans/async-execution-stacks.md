# Execution stacks across async suspension

> Status: active - private prototype implemented; validation hold remains.
> Requested 2026-10-30. Records the per-execution stack model discussed with
> Gary. Scope layout, naming, and boundary state installation are selected.
> Lifetime decision: rely on borrowed-owner lifetimes; no parked-slot pins,
> destruction preflight, or retained-branch count.
> Scope decisions: remove up without replacement; rename retain/release to
> open/close, preserving their behavior and void return types.
> Installation: boundary save/restore, a stable Scope base slot, and direct
> TLS allocation access. First native backend: stable, nonmoving task stacks.
> Stacks: configurable 8 MiB usable default, demand-paged and guarded.
> Targets: macOS/Linux on arm64/x86_64; no task thread migration.
> First API: Task.run batches using existing Channel operations and native
> Thread cancellation. Source cleanup does not suspend.
> Initial state: borrow caller Scope/Pool, copy effective Error policies/bound,
> start with no current Context and fresh Error/Match activation state.
> Switching dependency: pinned minicoro, with guarded-layout and ASan
> boundary adaptations recorded in lib/task/README.md.
> Source baseline: `1355503543801f6565150a00c779668ab1d2d1bb`.
> Scope: Scope, Context, Pool, Match, Error, and cleanup across suspension.
> Gary authorized the private prototype after selecting this design.
> No push or shared-branch advancement is authorized.
> Implementation stays off dev and main until validated and observed
> regressions are eliminated or mitigated; remaining tradeoffs need Gary's
> explicit acceptance. Pushing still requires his consent.

## Goal and boundary

Allow many waiting clients to share one native event-loop thread without
changing ordinary x2c allocation, borrowing, return, or cleanup semantics.
Suspension must preserve the logical execution that will later resume.

The [runtime spike](reference/async-channel-runtime-spike-2026-10-30.md)
establishes useful CPU and memory benefits for its explicit resumable model.
It does not establish general async-function semantics. Its private task
allocation Scopes and other experimental choices are not language decisions.
Those measurements do not quantify this execution-stack representation or
the retention costs of ordinary caller-owned allocation lifetimes.

This plan selects Task.run as the first batch API, using existing Channel
operations. It does not select general async syntax, individual task handles,
await multiplicity, detached tasks, a new channel type, or a general awaitable
protocol. The first native backend uses stackful execution with stable,
nonmoving task stacks.

## Selected semantic model

A logical execution is one sequential call chain that can suspend and resume.
It has its own stack of active runtime regions. Ordinary nested calls remain
in that execution; suspending a helper does not itself start concurrent work.
Independently started concurrent work needs a separate logical execution.

The stack describes active bindings and obligations. Scope and Pool objects
continue to own storage. A stack entry can refer to an existing owner without
copying its allocations, transferring ownership, or granting destruction
rights. Several executions can refer to the same live owner on one executor.
Their nested activations remain distinct.

Opening a region extends the execution's stack. Actual scope exit removes the
region and performs its established cleanup. Suspension parks the execution
with its stack intact; it is neither scope exit nor cleanup. Resumption
restores that execution's active view before any of its code runs.

This is one nesting model, not a requirement for one new uniform record type.
Existing per-module records may implement it. A new public Context abstraction
or a second hierarchy duplicating existing ownership is not selected.

## Required behavior

### Allocation, return, and slots

Ordinary allocations use the caller-selected active Scope unless the program
explicitly changes that destination. An Array return copies the handle and
preserves its allocation owner and aliases. Await does not implicitly export,
move, copy, or adopt the returned object.

Execution storage and user allocation ownership are separate. Reclaiming a
completed execution must not destroy ordinary allocations in an inherited
owner. Discarding an unobserved result must not invent a new Array destructor.
Existing explicit free, auto, defer, Context export, and ownership-transfer
operations retain their contracts.

Slots referenced by Scope operations, Context export, or cleanup must retain
stable addresses throughout their logical lifetimes. Suspending must not
invalidate Scope.top pointers or redirect explicit slot-targeted allocation.
The compiler must preserve locals whose addresses remain referenced, including
references introduced by generated runtime operations.

Slot identity within one execution must survive suspension. Each Task.run job
starts with its own stable base cell containing the caller's active Scope
value. It does not share the caller's slot identity or pushed-slot records.

### Task lifetime and destruction

The allocation owner must outlive every task using its borrowed storage.
Completion or joining establishes when that use ends; requesting cancellation
does not. Program structure and the selected task-lifetime contract establish
this relationship. The public start/join interface remains open; it does not
create a separate obligation for Scope to prove that every borrow has ended.

A task unwinds its own regions and execution storage. Cleanup stops at its
inherited, borrowed base; it does not destroy that base. The original owner
ends the borrowed Scope only after its users have finished. Explicit chain
destruction likewise requires the caller to have the right to destroy the
chain and owned storage being reclaimed.

Explicitly destroying a Scope while another task still uses it violates the
lifetime contract. The async runtime need not detect that violation or promise
bad-state rejection, just as an Array alias does not prevent explicit free.

Existing useful ordinary Scope checks can remain, but this design does not
extend them into a cross-task destruction guarantee. In particular, it does
not add parked-slot pins, saved pin values, scans of parked tasks, global
lifetime bookkeeping, or a destruction preflight over shared chains and
owned descendants. It does not restrict writes to parked activation cells
merely to maintain such bookkeeping. Existing lifetime and exclusive-access
obligations still apply to explicit slot aliases and writes.

### Scope nesting

Each execution has independent push/pop and open/close nesting. A retained
region in A must not become B's active region merely because B runs next.
Closing A's region must not alter B's nesting or destroy their shared base.

Each retained region keeps its persistent down link to its predecessor. The
execution's active slot selects the head. A shared allocation owner has no up
link identifying a single active child. Neither task modifies its shared
base's region links when it opens or closes its own region.

The required result is correct nesting and cleanup for programs that obey
their lifetime contracts. Shared-owner misuse detection is not a reason to
add a new representation, counter, traversal, registry, or slot API.

A retained chain may outlive Scope.pop and later be destroyed through its
head. Keep down for this operation. That does not grant a task ownership of
its inherited base.

Remove up without a replacement count, pin, compatibility mirror, or reserved
field. Its current only read rejects destruction of an attached lower Scope;
the lifetime contract makes that misuse check unnecessary. Allocation,
predecessor navigation, and ownership transfer do not use it.

Preserve operations that depend on retained ancestry, including Error's
outermost-owner snapshots and Context's retained-region ownership checks.
They must use the applicable logical nesting rather than another task's
currently installed native-thread state.

### Selected Scope layout and API

Keep first, down, parent, children, previous, and next in their current order.
Keep the private ScopeRecord name pointer and the existing originating-slot
records used to match region closure. No new per-Scope object or counter is
needed. Boundary installation selects execution-specific state as specified
below; it does not add a lookup to each allocation.

The calculated layout on the current 64-bit target is:

| Field | Current byte offset | Selected byte offset |
| --- | ---: | ---: |
| first | 0 | 0 |
| down | 8 | 8 |
| up | 16 | Removed |
| parent | 24 | 16 |
| children | 32 | 24 |
| previous | 40 | 32 |
| next | 48 | 40 |
| Public Scope size | 56 | 48 |
| Private ScopeRecord size, including name pointer | 64 | 56 |

ScopeRetain records remain two pointers: Scope and originating slot, 16 bytes
on this target. Per-allocation metadata and ownership headers are unchanged.
These are control-record sizes, not measured native allocator footprints or
RSS savings.

Rename only the active-region API:

| Current API | Selected API | Behavior |
| --- | --- | --- |
| void Scope.retain(void) | void Scope.open(void) | Open a new region in the active slot. |
| void Scope.release(void) | void Scope.close(void) | Close the matching region and restore its predecessor. |

Both operations keep their meta native availability and void return types.
Scope.new/destroy and Scope.push/pop keep their names and meanings. Context
and Pool keep their existing APIs, including Pool's lower-level retain/release
operations for explicitly selected pools. This is not a broad rename of every
retain or release operation. No aliases for the old Scope names are selected.

| Operation after migration | Selected change |
| --- | --- |
| Scope.open | Keep allocation and originating-slot registration; set new.down and update the active slot. Remove the write to previous.up. |
| Scope.close | Keep matching-region validation; restore the slot from top.down, detach top.down, and destroy that region's storage. Remove the clearing of previous.up. |
| Scope.push/pop/top | Preserve real writable slots, stable addresses, and pop freeing nothing. Use the installed active pointer; pop falls back to the stable base slot. |
| Scope.destroy | Remove the up check; keep useful current-execution root/pushed-slot checks. The caller must have the right to destroy the chain and its owned storage. Add no preflight or cross-task scan. |
| Task cleanup | Unwind only the execution's own regions and stop at its borrowed base. |
| Allocation, free, realloc, owner lookup, and ownership movement | Preserve the allocation representation and ownership rules. |

### Selected compatibility changes

Removing up changes the public layout and later field offsets. Renaming the
two operations changes the public x2c API and generated C symbols. The Scope
handle remains pointer-sized, but this does not make old and new runtime
layouts binary-compatible. Layout-dependent native clients must be rebuilt
against matching headers and libraries.

Implementation must migrate Scope-specific declarations, resolved calls,
macros, generated-code producers, docs, and affected test expectations. Do not
use unrestricted retain/release replacement: Pool and other owners keep their
operations. Regenerate bootstrap and derived artifacts through existing
repository targets; never hand-edit them.

The documented bad-state rejection for destroying an attached lower Scope is
withdrawn, including in ordinary synchronous code. Such destruction remains
invalid; it is not newly safe or defined. Remove the guard-specific rejection
expectation in unittest/test-scope.x rather than replacing it with a new guard
or a fixture that asserts behavior after invalid destruction. The matching
open/close checks and retained ordinary root/pushed-slot checks remain.

Valid allocation and return behavior, popped-chain destruction, and existing
finalizer scratch-allocation behavior remain unchanged. Do not add destruction
markers or callback restrictions to compensate for the removed misuse check.

### Selected active-state installation

Keep the existing module-owned TLS records as the installed runtime view.
Each logical execution has backing storage for the mutable records, handles,
and counts that must follow it. At an actual execution boundary:

1. Save the caller/executor's installed state.
2. Install the selected execution's saved state consistently.
3. Resume its code using the ordinary runtime operations.
4. Save its updated state when it suspends or finishes.
5. Restore the caller/executor's state, including on failure paths.

The installed view is authoritative while the execution runs; its saved view
is authoritative while parked. Copy record values and handles, not the
contents of allocation lists, push arrays, Contexts, Pools, Error buffers, or
caches. Their existing storage remains live under its existing owners.

An awaited helper in the same logical execution needs no separate state
installation. Initialize independent jobs using the selected inheritance
contract below; installation does not implicitly clone all subsystems.

Use private owner-specific save/install support called at the boundary. Do
not introduce a public execution-context API, a generic TLS registry, or an
active-task/state-pointer lookup in every runtime accessor. Installation
must not expose partially installed state to user code or callbacks. Prepare
any fallible initialization before entering the state-exchange sequence.

### Stable Scope base slot

The default Scope cell must live in stable native-thread or execution backing
storage, outside the TLS record overwritten by installation. The installed
Scope state contains:

| Field | Meaning |
| --- | --- |
| base_slot | Address of the current execution's stable default Scope cell. |
| active | Address of its currently selected Scope cell. |
| stack and its counts | Handles for its existing pushed-slot array. |
| retains and its counts | Handles for its existing matching-region records. |

Replace the installed inline root value with base_slot. Preserve the original
caller-provided cells for explicit pushes. Scope.top returns active as before;
pop with no remaining pushes restores active to base_slot. The current-root
destruction check reads the value in base_slot. The native default execution
has a stable root cell too; initialization and native release/reset must use
that cell consistently.

This is a storage-location change for a Scope variable, not a new allocation
owner, managed slot type, pin, or write interceptor. A task's base cell
initially names its selected borrowed owner and changes normally as regions
open/close. Task completion does not call native-thread shutdown or destroy
that borrowed owner.

Context captures Scope.top as its export destination. Consequently, saving a
pointer to the old overwritten TLS root field would redirect A's destination
when B is installed. The stable base cell removes that aliasing hazard. Other
slots whose addresses survive suspension remain stable under their existing
logical lifetimes, as required above.

### Owner-specific state and costs

| Owner | Installed state to preserve | Existing paths affected |
| --- | --- | --- |
| Scope | base_slot, active, pushed-slot and region-array handles/counts. | Root-slot initialization, pop fallback, current-root check, native release/reset. Allocation keeps direct TLS active access. |
| Context | current_context pointer. | Private boundary exchange; Context objects and captured destinations remain intact. |
| Pool | Current Pool handle. | Reuse the existing current-Pool exchange behavior. |
| Match | Default-cache handle and Context-state head. | Exchange the active bindings; keep caches and leases in place. |
| Error | Mutable Error state and a consistent x2c_error_runtime_ready flag. | Private boundary exchange; reuse existing policies, handlers, records, and dispatch. |
| Exception | Native exception-frame and cleanup heads for each execution's live invocations. | Save/install the heads at execution boundaries; retain the native frames and cleanup environments on the task's stable stack. |

The inspected Error uses of its TLS scope-cell address and Match uses of its
default-cache-cell address are temporary inside synchronous calls. No
persistent capture like Context's Scope destination was found in those paths.
Respect the existing synchronous-runtime boundary rather than copying raw TLS
and assuming all embedded pointers remain valid. User threaded variables,
process-wide Logger state, and native-thread-only scratch storage retain
their existing meaning.

| Ordinary synchronous path | Expected installation-related effect |
| --- | --- |
| Scope.malloc/calloc and allocation through the active slot | Same direct TLS active lookup; no active-task lookup or async-mode branch. |
| Explicit slot allocation, free, owner lookup, and movement | No installation-related lookup added. |
| Scope.top | Return the installed active pointer as before. |
| Scope.pop falling back to the default slot | Load base_slot instead of taking the address of the inline root field. |
| Current-root destruction check | Read through base_slot; an additional dependent load may be required. |
| Other Context, Pool, Match, and Error operations | Continue reading their installed module-owned TLS fields. |

Do not claim zero synchronous overhead. The root-slot paths change and need
stable-cell storage. The async path also pays for backing records,
initialization, and state exchange at actual execution switches. Generated
code and comparable measurements must establish the cost; no timing or
instruction-count result isolating installation exists yet. Local prototype
request/reply and Scope timing evidence is linked in the implementation record.

### Context, Pool, and Match

An opened Context remains the same object while its execution is suspended.
Its allocation Scope, export destination, Error overlay, Match state, and
optional canonical Pool remain live. Suspension does not close and reopen it.

Restoration must make those components agree before user code, cleanup, or
runtime callbacks execute under that execution. Context.current and allocation
must not identify different executions. Context.close retains its existing
nesting, export, lease, and teardown behavior.

Opening a Context or Pool stays explicit. No fresh Context, Context policy
overlay, private Pool, or eagerly allocated Match cache is required merely
because an execution exists. A task's base Error policy Map implements its
selected independent copy of effective dispositions; it is not a Context
overlay.
Pool release and promotion retain their identity and lifetime contracts.
Existing cache and lease owners remain authoritative; execution switching
does not flush or duplicate them without a demonstrated lifetime need.

Process-wide Logger state, runtime initialization, and ordinary user threaded
variables retain their current meaning. This work does not virtualize all
native thread-local storage. Logger's observing Error registration must still
work when logical Error state is restored; its global registration and marks
are an affected consumer to trace, not a reason to create task-local Loggers.

### Error state and cleanup

An execution's registered handlers, accumulated records and marks, running
catch arms, policy overlays, and cleanup obligations survive suspension.
Another execution must not dispatch through those registrations or contribute
records to those marks. Shared immutable catch-site definitions can remain
shared.

A suspended catch arm is still logically active. Its borrowed captures do not
require snapshots solely because it suspended. Snapshot detail when it must
outlive its actual owning arm, handler, or execution, using existing Error
operations and admissible-value rules.

Cleanup follows actual logical exits in the existing order and runs once.
Cancellation does not authorize bypassing accepted message ownership or
destroying borrowed storage still used by another task. Ordinary Channel
commitment, failed-send rollback, and quiescent destruction remain premises.

Suspension switches away without returning the task's live C invocations.
Their exception landings and cleanup environments remain on its stable stack.
Parking does not call normal exception-frame leave, trim registrations, or
perform exits. Resume restores the execution's installed state and continues
on that same stack. Reuse existing Error matching, snapshots, and synchronous
dispatch instead of creating a parallel Error interpreter.

This work introduces no suspension inside synchronous runtime transitions or
Error callbacks. An execution switch must not expose partly installed state.
Source cleanup bodies do not suspend in the first API. Use immediate
operations such as Channel.close for cleanup communication. Batch shutdown
may drive unfinished tasks internally; that does not require source cleanup
to await. General suspension from cleanup is deferred.

### Selected first native backend

Use one stable, nonmoving native stack for each independently started task.
Ordinary nested calls, including awaited helpers, stay on that task's stack.
Keep the stack alive through actual completion and all required cleanup.
Do not relocate, copy, grow, or segment task stacks in this first backend.

This preserves the live C invocations used by sigsetjmp/siglongjmp, local
ExceptionFrame records, cleanup environments, and address-taken locals.
Keep existing try/catch lowering, both defer paths, lexical-transfer cleanup,
and volatile/escape preservation. Stackful execution does not replace those
operations or remove their existing requirements.

Add private stack allocation, switching, and release support, task entry and
completion handling, and suspension at the selected await boundaries. Combine
switching with the selected owner-specific TLS save/restore, including native
exception and cleanup heads. Ordinary synchronous calls need no new exception
representation or per-operation task lookup.

An Error escaping a task must reach its task-entry boundary and become an
explicit task outcome; it must never jump into another stack or the executor.
Reuse ordinary Error policies: a returning collect/ignore policy does not
become task failure merely because a task boundary exists. Task.run observes
outcomes as specified below and copies effective policies at batch entry.

Cooperative cancellation resumes the task on its own stack and performs its
required exits there. A cancellation request cannot free a parked stack with
cleanup still owed. The scheduler does not inject another cancellation while
source cleanup is running. Explicit Channel calls retain their existing stop
checks; Channel.close does not request a wait or test stop. Preserve the
primary batch outcome while finishing participants. Source cleanup does not
suspend in the first API; no general cancellation-masking API is introduced.

The selected stack sizing, targets, and compatibility requirements follow
below. The switching dependency is selected below. The source
baseline has no task-stack switching backend; macOS's deprecated ucontext
routines are not an assumed solution.

Stackless execution would require persistent logical locals, protected regions,
cleanup state, and live landing reconstruction across returned C invocations.
It remains a possible later backend, not part of this first implementation.
Stable native stacks are selected because they preserve the existing Error
and cleanup representation with fewer compiler changes. Their memory and
platform costs still require validation under the delivery hold below.

### Selected stack sizing and platform support

Reserve an anonymous virtual-memory mapping with 8 MiB of usable stack by
default, plus an inaccessible guard page at the overflow end. Make usable
capacity configurable before task creation. The exact configuration surface
belongs with the eventual task/executor API. Respect native page size and ABI
alignment; the guard page and metadata do not subtract from usable capacity.

Physical pages are supplied on demand as code touches the mapping. This does
not change its address or capacity and requires no application fault handler.
Do not eagerly touch the entire stack or add custom growth, relocation,
segmentation, stack pooling, or page reclamation in this first backend.
Release the mapping after cleanup completes and control returns to the
executor, even if the task outcome remains available for observation.

The 8 MiB default preserves the current native worker stack budget. It does
not guarantee that every program fits. Smaller configured stacks can reach
the limit sooner with existing recursion or large local variables. Overflow
remains a native failure, without a promise of catchable Error or cleanup.
A guard page provides ordinary overflow protection, not guaranteed detection
of every large stack-pointer jump. Add no signal-based recovery machinery.

| Live tasks at the default capacity | Usable virtual stack reservation |
| ---: | ---: |
| 64 | 512 MiB |
| 1,024 | 8 GiB |
| 10,000 | 78.125 GiB |

These figures exclude guards and metadata and are not RSS estimates. Physical
cost depends on touched pages, retained call chains, and OS behavior. Touched
pages may remain resident after calls return. Mapping and page-table overhead,
OS accounting limits, and stack allocation/release calls also matter. Measure
actual stack use, resident memory, reservation, allocation cost, and switch
cost against a named baseline. The resumable spike establishes none of these
costs for this backend.

| Target | First native backend scope |
| --- | --- |
| macOS arm64 | Support, subject to validation. |
| macOS x86_64 | Support, subject to validation. |
| Linux aarch64 | Support, subject to validation. |
| Linux x86_64 | Support, subject to validation. |
| WSL2 | Use the corresponding supported Linux target. |
| MSYS2/native Windows, WebAssembly, and other targets | Defer async backend support; preserve existing synchronous support. |

These are the four existing native release targets, not a claim of validated
async support. Diagnose a request for the unavailable async backend on an
unsupported target. Do not add an automatic stackless fallback or prevent
ordinary synchronous programs from building there.

Keep each task on its original executor thread for its entire execution.
Suspension and resumption do not migrate it between native threads. Existing
native TLS and foreign-library thread affinity retain their meaning.

The selected switching implementation must account for each target's ABI,
supported compiler options, Error transfers, sanitizer integration, and
relevant debugging tools. Prefer a small pinned C implementation behind
private runtime functions, using the selected pin below.

Stack-bound consumers must use the actual executing stack. In particular,
[Lisp's stack allowance](../lib/lisp/evaluate.x) currently queries pthread
bounds. Supply installed task bounds while a task runs and retain the native
thread path otherwise. Validate [Regex recursion](../lib/regex.x) against the
selected capacity. Foreign libraries that inspect pthread bounds may require
specific adaptation or restrictions; a task mapping is not a pthread stack.
No per-operation task lookup is needed in ordinary allocation or Error paths.

## Selected first task lifecycle and API

Use Task.run(jobs, completed), modeled on Thread.run. Jobs are existing
zero-argument Func values returning Var. The operation returns void after all
jobs complete, or raises after failure/cancellation shutdown completes. An
absent completion callback discards successful result handles without
inventing ownership cleanup. Empty jobs complete without callbacks.

Call Task.run from ordinary native execution. Nested task batches, public
start/stop/join handles, a separate await operation, and general async syntax
are deferred. This batch API does not require every future task API to use
the same lifetime or failure policy.

Prepare and queue the jobs before dispatching user job code. Initial dispatch
uses submission order; ready tasks use a FIFO queue. Do not run jobs inline
during setup or promise preemption or an ordering of simultaneous external
events. A job runs until it waits or finishes. Ordinary Channel send,
send_owned, receive, iteration, and close retain their public contracts.
Waiting parks a task; native Thread callers retain their native wait path.

Each successful job, including one returning void, becomes ready for one
completion callback after its cleanup finishes. Restore the caller's runtime
state before invoking completed. The callback must not wait for participant
progress, as with Thread.run. It may record results and close Channels.
Release a finished task's stack after returning to the executor; retaining a
result does not retain that stack or change the result's allocation owner.

The caller keeps jobs, captures, Channels, borrowed Scopes and Pools, and
referenced storage alive through the call. Ordinary results keep their
ordinary owners and aliases. Jobs must explicitly preserve values created
inside regions they close. Neither task completion nor an unobserved result
destroys caller-owned allocations.

### Batch failure and cancellation

Follow Thread.run's batch policy: an observed job failure, completion-callback
failure, or setup failure stops unfinished participants and finishes their
cleanup before Task.run raises. Setup failure releases prepared execution
storage; jobs not yet dispatched owe no user cleanup. Report escaping job
Errors through the existing captured-Error/join-fail convention. Returning
collect, ignore, and log policies retain their ordinary behavior.

Preserve the primary failure during shutdown using the existing batch Error
rules. Do not add a new error aggregation scheme or invoke further success
callbacks after the coordinator begins failure shutdown. Stop-on-failure is
selected for Task.run, not a universal automatic sibling-cancellation rule.

For this first API, Thread.stop on the native Thread running Task.run requests
cancellation of the batch. The coordinator stops unfinished jobs, wakes
parked waits, and continues execution until their required cleanup finishes.
It then reports cancellation. No public Task.stop handle is required yet.

Channel waits and scheduler boundaries observe stop. A committed operation
still succeeds and retains its ownership effects; cancellation never retracts
an accepted message. Stop of an uncommitted owned send preserves ordinary
rollback. Arbitrary computation, blocking native I/O, or explicitly catching
cancellation can delay completion. Never forcibly free a live task stack.
Channel.close ends sends and permits draining; it does not stop participants
or establish that their borrows have ended.

Task.run returns or raises only after every participant has finished cleanup
and cannot access caller-borrowed storage. Restore caller runtime state on
both paths. The caller may then free Channels and end their owners. Normal
shutdown is application-directed Channel closure; failure/cancellation
shutdown requests stop before waiting for completion.

### First request/reply acceptance example

Reuse [channel-service.x](../examples/power/channel-service.x): a service,
two clients, a request Channel, and one reply Channel per client. The caller
owns all Channels, job captures, and the answers Array through Task.run.

1. The service waits for requests. Each client sends a request and waits for
   its reply, using ordinary Channel operations.
2. The service replies; clients return ordinary results. Each client's cleanup
   finishes before completed records its result.
3. After both clients finish, completed closes requests. The service drains
   accepted requests and exits; Task.run then returns.
4. If the service fails with a client waiting, failure observation stops all
   unfinished jobs. Waits wake, cleanup finishes, and Task.run reports failure.
5. If the owner Thread is stopped, distinguish cancellation before commitment
   from cancellation after commitment. Preserve Channel ownership rules on
   both paths and finish all users before freeing Channels.

The existing native-thread-local Channel waiter cannot represent several
parked tasks. Give each parked task live waiter storage and scheduler-aware
wakeups while retaining Channel synchronization, commitment, and native
Thread interoperability. Do not introduce a separate task Channel type.

## Selected initial task state

Capture initial values at Task.run entry, before dispatch. The caller remains
parked except for completion callbacks; callbacks do not change the already
established initial state of other jobs.

| State | Selected initialization |
| --- | --- |
| Scope | Each task gets its own stable base cell containing the caller's active Scope value. Start with empty task-owned push/region records; borrow the owner through Task.run. |
| Context | Start with no current Context. Do not copy the caller's current pointer or implicitly open a new Context. Explicit task-local Contexts work normally. |
| Pool | Borrow the caller's current Pool, including a private Pool, through the batch. No new pool, promotion, or fallback to the process root is implicit. |
| Error policies and bound | Copy effective dispositions and the current bound at entry. Later policy changes stay local to the execution making them. |
| Error records, marks, handlers, and exception/cleanup heads | Start fresh. Install only the task's own outcome boundary and existing observer behavior, not the caller's catch targets or borrowed handler environments. |
| Match | Start with no inherited Context-state head and an empty lazy default-cache binding. Do not duplicate caller caches or eagerly allocate a task cache. |

Scope and Pool provide borrowed storage/identity. Context provides mutable
nesting, export destination, and teardown authority, so sharing its active
record is a different operation. Under this contract Context.current
is NULL at job entry even when Task.run was called inside a Context. Opening
a task Context creates its own region and exports back to the task's base
slot; the borrowed caller Scope and Pool remain live. An explicitly captured
caller Context does not become current merely because its handle is passed.

Reuse Error.policy_capture/adopt for effective dispositions and Error.bound
for the bound. The current policy capture does not include that bound. Reuse
existing Error initialization and outcome capture without Thread's implicit
callback Context, which would replace ordinary caller-owned allocation with
private task allocation. Reuse current-Pool exchange for the borrowed Pool.
An awaited helper within one task inherits that task's active state normally;
these initialization rules apply only to independently started jobs.

## Selected switching dependency

Vendor minicoro at revision
`02dad0f8b7cbb12fe6e216ae7a76db15ca55cd7b` behind private runtime functions.
The private prototype implements this pin; validation currently covers macOS
arm64, not all four selected targets.
Its [source at that revision](https://github.com/edubart/minicoro/blob/02dad0f8b7cbb12fe6e216ae7a76db15ca55cd7b/minicoro.h)
provides a single C header, assembly paths for x86_64/AArch64 with Apple
handling, and sanitizer hooks. Use only those native assembly paths, without
automatic ucontext, fiber, or WebAssembly fallbacks.

Keep Task.run scheduling, Channel waits, TLS exchange, outcomes, and cleanup
in x2c. The dependency supplies coroutine initialization, resume, yield, and
release. Use the selected stack capacity and guarded mapping, not upstream
defaults or its optional value-passing storage API. Preserve upstream license
notices; add no build-time network dependency.

The current layout places control records before the stack in one allocation.
A custom mmap allocator alone cannot put the guard immediately below usable
stack without leaving metadata in the overflow path. A narrow layout
adaptation separates metadata from the guarded stack boundary. The adapter
also pairs ASan fiber annotations on the actual switch boundaries, including
return to the native caller and final task exit. Both adaptations are recorded
in [the dependency notes](../lib/task/README.md).

Among the reviewed candidates, this is the smallest practical fit for all four
targets. [libaco](https://github.com/hnes/libaco) documents Intel386/x86_64
Sys V support, leaving the selected ARM targets uncovered.
[Boost.Context](https://www.boost.org/doc/libs/latest/libs/context/doc/html/context/architectures.html)
covers the target architectures but brings a broader build/integration surface.
This comparison does not claim minicoro is the smallest library that exists.

The first experiment established repeated switching, stable local addresses,
Error transfer after resume, and both cleanup forms on macOS arm64, including
instrumented sanitizer runs. This is bounded evidence, not a new recurring
gate. Validate remaining targets and compiler/ABI combinations before claiming
support. Rejecting a tested integration does not reject the stackful design
or justify an unapproved fallback architecture.

## Worked execution

A and B are established before A opens C. They use the same executor and
borrow a live allocation owner S.

1. A opens Context C and a retained region, changes a user-defined Error
   policy in C, registers a handler, and records an Error mark.
2. A suspends. C, its region, handler, captures, and mark remain live. No
   Context.close, Scope.close, handler pop, or deferred cleanup runs.
3. B runs with B's active nesting. B does not allocate into A's private region,
   see C through Context.current, or dispatch through A's handlers.
4. B may retain its own region over its selected owner without overwriting
   A's nesting. B's collected errors do not change A's Error.since result.
5. A resumes on its retained native stack with the same C, region, mark,
   registrations, live C landings, and cleanup environments.
6. A's normal exit or Error transfer performs its established cleanup once.
   S remains owned by its original owner. Ordinary results allocated in S
   remain valid until S ends or code explicitly frees them.
7. The owner of S waits for both A and B to finish before ending S. If it
   requests cancellation, it still joins completion before releasing S.

The example specifies isolation and lifetime within each execution. A and B
start with the selected initial state; A's later Context and policy changes
do not alter B's inherited policy values or current Context.

## Existing owners and required changes

| Owner | Established behavior to reuse | Suspension-related change to design |
| --- | --- | --- |
| [Scope state and layout](../lib/scope/scope.x) and [regions](../lib/scope/regions.x) | Allocation ownership, explicit slots, valid region operations, and caller-selected lifetimes. | Remove up, rename the region API, and install active state with a stable base slot; preserve direct TLS allocation and cleanup to the borrowed base. |
| [Context](../lib/context.x) | Existing records, exports, dependency ownership, close order. | Restore current Context and related active bindings without reconstructing it. |
| [Pool threads](../lib/pool/threads.x) | Current-Pool exchange, nested levels, explicit lifetime and promotion. | Select the appropriate existing chain for the resumed execution. |
| [Match cache](../lib/match/cache.x) | Context-local defaults, lazy caches, pinned leases. | Preserve the applicable active Context state and all live leases. |
| [Error state](../lib/error/error.x), [policy](../lib/error/policy.x), [records](../lib/error/records.x), and [handlers](../lib/error/handlers.x) | Policies, marks, admissible snapshots, matching, registrations. | Separate mutable logical state and preserve registrations across parking. |
| [Exception runtime](../lib/exception.x), [try lowering](../src/components/try-catch.x), and [cleanup](../src/cleanup/cleanup.x) | Synchronous dispatch, live C landings, cleanup ordering, and captured local addresses. | Retain frames on stable task stacks; exchange exception/cleanup heads and contain escaping task Errors at task entry. |
| [Thread-state lifecycle](../lib/thread-state.x) and [Logger](../lib/logger.x) | Native-thread release order and existing logging behavior. | Distinguish execution completion from native-thread shutdown; preserve Error observer integration. |

At the source baseline, Scope.retain writes both new.down and previous.up.
Scope.release clears previous.up, and Scope.destroy tests up. Removing those
three accesses and the field eliminates the single-child conflict; each
retained region still records its own predecessor. No replacement branch
counter is needed for valid operations. Execution-specific active slots and
push/region records must still be restored correctly across suspension.

The known dependent readers are Scope's own operations, Context._owns_scope,
Error._snapshot_wide, and unittest/test-support.x's region-balance checks.
This is a current bounded inventory. The selected layout, names, and dropped
misuse diagnostic are the compatibility changes authorized for the design;
they do not authorize implementation or unrelated contract changes.

## Remaining validation before delivery

| Item | Constraint and next work |
| --- | --- |
| Strict-build lifetime diagnostics | The pointer-field provenance fix and selected audit boundary are implemented. The merged tree passes the strict stage-two build; the earlier three temporary-borrow diagnostics are resolved. |
| Remaining native targets | Establish Linux arm64/x86_64 and macOS x86_64 ABI, compiler, sanitizer, and Error compatibility. Only macOS arm64 has execution evidence. |
| Regression coverage | Local Channel and Scope timings are bounded evidence. Network/timer workloads, broader performance checkpoints, and final publication validation remain outstanding. |

These are consequential choices. The selected stack model does not authorize
resolving them through incidental implementation changes. It also does not
select individual-task eager starts, single-consuming await, mandatory task
groups for future APIs, or separate public channel types. The selected batch
owns its jobs through completion and stops unfinished jobs on failure.

## Implementation outline

1. Use the selected contracts and pinned dependency. Record implementation
   findings and evidence; surface any consequential change before expanding
   the architecture.
2. Remove Scope.up and its three accesses. Rename Scope.retain/release to
   Scope.open/close with unchanged behavior and return types. Migrate their
   authoritative consumers and the selected compatibility changes above.
   Preserve down, allocation owners, stable slots, and cleanup boundaries;
   rely on the task lifetime contract instead of adding replacement guards.
3. Add only the private restoration support needed by Context, Pool, Match,
   Error, and Scope. Implement boundary save/restore and stable base slots;
   keep ordinary allocation on its direct TLS path. Update root-specific
   initialization, pop, checking, and native release/reset. Keep user
   allocation ownership and native lifecycle separate.
4. Implement configurable, guarded, demand-paged task stacks with an 8 MiB
   usable default on the four selected native targets. Keep tasks on their
   original executor threads. Update Lisp stack-bound queries and affected
   stack consumers. Add task entry/completion and await suspension; retain existing
   native exception frames and cleanup paths. Contain escaping task Errors and
   unwind cancellation on the task's stack. Reuse ordinary compiler operations
   and canonical AST lowering; do not add another parser, ownership inference
   engine, or Error interpreter. Add Task.run, Channel task wait/wakeup support,
   native-owner Thread cancellation, and complete batch shutdown. Preserve
   existing Thread callers and prohibit source cleanup suspension.
5. Verify the focused behaviors below and examine relevant performance costs.
   Review and fix the complete authored diff before any later publication
   validation. Keep implementation isolated under the delivery hold below.

## Validation scope

These are behavioral scenarios for later authorized work, not new recurring
gates or an expanded precommit sequence. Reuse existing suites and the retained
spike workload where appropriate.

| Scenario | Observable behavior protected |
| --- | --- |
| Two executions allocate in inherited S and return Arrays. | Same allocation owner and identity before/after suspension; no implicit move or early destruction. |
| A and B open regions over a shared base. | Independent down links; closing either region does not overwrite nesting or destroy the shared base. |
| A pushed slot opens two regions, is popped, and its detached chain is destroyed. | Both regions and allocations are reclaimed through the preserved down chain. |
| A keeps pushed slots and Context exports across suspension. | Stable addresses and correct destinations; B cannot redirect A's allocation. |
| A Context captures the default base slot, B runs, and A resumes and exports. | A's saved destination still names A's stable cell, not overwritten TLS storage. |
| An execution grows its push/region arrays, then switches away and back. | Updated handles and counts are saved; no copied array contents or stale backing pointers. |
| Resume exits normally or fails, then the executor runs another callback. | Caller/executor state and Error readiness are restored consistently. |
| A and B borrow S; the owner joins them before ending S, including after cancellation. | Task cleanup releases its own regions without destroying S; owner cleanup happens after actual completion. |
| A opens Context/Pool, changes policy, and holds Match state. | B observes its own bindings; A resumes unchanged; close/export/release order remains valid. |
| A marks/collects errors or suspends inside a catch arm. | B cannot contaminate marks or consume handlers; captures remain live through actual arm exit. |
| Synchronous callees raise inside a resumed protected region. | Correct live landing, selected catch, cleanup order, and original error detail. |
| Normal exit, replacement Error, and cancellation cross cleanup regions. | Each cleanup runs once in the correct execution; no stale frame or double free. |
| A task Error escapes its outermost protected region. | Task entry contains the transfer; no jump reaches the executor or another task's stack. Returning Error policies retain their behavior. |
| A suspended task retains address-taken locals and both defer forms. | Native addresses and cleanup environments remain valid until actual exit; stack release follows final cleanup. |
| A task suspends and resumes repeatedly. | It remains on its original executor thread with stable stack addresses. |
| Lisp and Regex run within a task. | Lisp uses task stack bounds; existing recursion behavior is validated against the selected usable capacity. |
| Programs use the default or a configured stack capacity. | Usable capacity excludes the guard; allocation/release and Error behavior work on the selected targets. |
| The channel-service batch succeeds, fails with clients waiting, or receives owner Thread stop. | Callback behavior, committed ownership, stop/wakeup, and full shutdown follow the selected Task.run contract. |
| Task.run begins inside a Context with a private Pool and Error overrides. | Jobs borrow the caller Scope/Pool, start without a current Context, copy effective policies/bound, and do not inherit marks, catches, cleanup, or Match activations. |
| One job changes policy or opens a Context; completed later changes caller policy. | Other jobs retain their initial policy values and independent activations; completed runs in restored caller state. |
| A synchronous program builds on a target without the async backend. | Existing synchronous support remains; requesting the unavailable backend produces a clear diagnostic. |
| Valid return/free/region operations without async execution, using the renamed API. | Existing value, lifetime, matching-region, Error, and native-thread lifecycle behavior remains intact, with the selected layout and diagnostic changes above. |

These scenarios assume valid lifetime and exclusive-access contracts. No
fixture should require detection of premature cross-task destruction.

Performance evidence must distinguish switch work, allocation traffic,
retained storage, native stack reservation and resident use, and costs imposed
on synchronous code. Use comparable
workloads and raw evidence. No universal speedup is required or claimed.
Follow existing performance and publication instructions if implementation
and delivery are later authorized; do not add new gates for this plan.

## Implementation isolation and delivery hold

Implement and validate on a private work branch or worktree. Keep the changes
off dev and main, locally and remotely, until
the completed implementation is validated and observed regressions have been
eliminated or mitigated. Record any remaining regression or tradeoff and obtain
Gary's explicit acceptance before advancing either shared branch.

Passing correctness checks alone does not accept performance or retention
regressions. Compare the final implementation with a named baseline, using
the existing relevant checks and workloads. Include synchronous allocation,
root-slot operations, execution switching, and the request/reply behavior.
Include task-stack allocation, reservation, resident use, and relevant runtime
recursion workloads for the selected stack size and platforms.
Record measurements and coverage limits; do not claim every possible
regression has been excluded.

This hold overrides default direct delivery and automatic shared-integrator
publication. Do not enroll the work for automatic integration while the hold
applies. Validation or acceptance does not itself authorize a push; Gary's
consent is still required. No new recurring gate or precommit requirement is
created. Gary authorized private implementation and testing; publication and
pushing remain unauthorized.

## Private implementation record

The first Task.run prototype, Scope migration, state exchange, Channel task
waits, and guarded native adapter are implemented on codex/async-task-prototype.
The request/reply example is executable. This session has not advanced dev
or main.

See [the prototype report](reference/async-task-prototype-2026-10-30.md) for
commands, test counts, measured workloads, dependency adaptations, and limits.
This evidence does not lift the delivery hold or accept remaining regressions.

### Lifetime analysis follow-up, 2026-10-31

Independent source review found no runtime borrow-end gap in the four original
sites. Task.run finishes participants before its frame exits; both waiter
registrations unlink before their frames return, under the same mutex used
by native notifiers. No extra runtime allocation or lifetime tracking is
needed to establish those contracts.

The analyzer did have a provenance bug: indexing through a pointer field
could inherit the containing record's frame or parameter identity. A local
fix keeps untracked pointee storage distinct from its containing record.
Inline arrays and the pointer field's own address retain frame provenance.
The new region-pointer-fields fixture covers both distinctions. All 1,353
compiler fixtures pass with this fix alone.

The three remaining diagnostics result from summaries meaning "ever stored"
rather than "retained after return". Inferring intrusive-list unregistration
and cleanup would require a broader analysis model. Gary selected defining
the analysis boundary before adding that machinery.

Gary selected the following diagnostic policy. It is implemented locally:

| Case | Ordinary translation | Existing audit mode | Meta functions |
| --- | --- | --- | --- |
| Returned frame address or direct static store | Keep warning. | Keep finding. | Keep error. |
| Known retaining storage and established ended regions | Keep existing checks. | Keep findings. | Keep errors. |
| Possible frame escape through raw pointer storage whose destination lifetime is unknown | Leave to the owning C lifetime contract. | Keep possible-escape finding. | Keep existing error. |

This reuses the existing ordinary/audit/meta distinction. It adds no borrow
syntax, runtime state, function allowlist, blanket region-warning disable, or
general pointer-analysis engine. Summaries distinguish raw C stores from
known retaining operations, including through helper calls. Protocol index
stores retain their existing checks.

The compatibility cost is real: the existing ordinary warning for
stored_through_parameter in region-local-escapes moved to audit mode.
Such stores can still be wrong; ordinary translation no longer claims
to determine their lifetime from the store alone. Return/static checks,
known retaining-storage checks, and meta errors remain protected. Focused
strict translation of lib/task.x and lib/channel.x now passes under the
selected policy. Validation below does not lift the delivery hold.

Validation on macOS arm64:

- All 1,355 compiler fixtures passed, with 2,994 checked artifacts. The only
  changed existing diagnostic is the selected raw parameter-store warning.
- New fixtures retain known container warnings through multiple helpers and
  unknown targets, protocol index-store warnings, ended-region warnings,
  and meta raw-store errors.
- The optional graph audit tests passed, including both raw-store findings.
  Unknown-pointer coverage remains incomplete, as before; its finding is
  preserved as a review obstacle rather than a proved violation.
- `make stage-2` passed with the existing fatal x2c and C warning settings.
  Stage 1 and stage 2 generated identical output across all 333 C/H files.
- The full ordinary unit suite passed from unittest/: 1,148 tests and 99,489
  assertions. The stage-two compiler ran the request/reply example and
  printed FIRST and SECOND. Documentation drift checks passed.

No other native target, wider workload, or publication gate is validated by
this follow-up. The existing dev/main and push hold remains in force.

### Broader validation, 2026-10-31

See [the broader validation report](reference/async-validation-2026-10-31.md)
for comparison with the full pre-async baseline, synchronous cost probes,
program footprint, blocked-task memory, stack-capacity checks, and fresh
instrumented results. The existing full check target exposes a native-file
copy omission in cold collection and four lint findings. Paired runtime,
representative translation, and normalized build-cost measurements are now
complete. Allocation, comparable compiler translation, and whole-build cost
are close to baseline; native buffered Channels have a local measured cost.
An apparent compiler slowdown was traced to unequal compiler-source interface
caches and withdrawn after a comparable rerun. No regression or retention
tradeoff has been accepted, and no push is authorized.

### In-process Notes comparison, 2026-10-31

The [Notes Thread.run / Task.run report](../examples/apps/notes/bench/reports/2026-10-31-inprocess/interpretation.md)
records five paired samples at 1, 8, and 64 clients. Both modes use one native
SQLite owner and the same SQL, row conversion, JSON, and logging. At 8 and 64
clients, Task increases lookup throughput and reduces CPU/request. One client
is approximately unchanged. Peak RSS is higher for Task at 8 and 64 clients;
latency storage prevents attributing that difference to stacks alone.
Response checks, existing HTTP regression checks, and 22 fresh instrumented
normal/failure checks pass. This is not an HTTP performance result or a new
runtime implementation. The existing validation, dev/main, and push hold remains.

### Private dev integration, 2026-10-31

Merged dev at `ffd915bd0` into the private async branch, starting from
`d2a9df314`. This incorporates 62 upstream commits, including constant-List
pattern matching, dedent folding, auto-region simplifications, and benchmark
development. Upstream auto cleanup supersedes the corresponding explicit
Scope rename edits. The extracted Notes database worker retains upstream SQL
formatting without restoring a duplicate worker in the HTTP program.

Bootstrap was regenerated through `make bootstrap-refresh`. The merged tree
passes `make build-safe`, `make stage-2`, and all 1,150 unit tests with 99,495
assertions. Constant-List equality and dedent fixtures pass. The task-service
example and 64-client Notes normal/failure checks pass in both modes.
The Notes HTTP API, recovery, and queued-shutdown regression checks also pass.
Earlier performance results describe their recorded pre-merge revisions;
normal benchmark comparisons remain deferred while that suite develops.
The final publication gate and remaining publication work are still pending.
This integration advances only the private branch; no push is authorized.

### Merged-diff review and gate repairs, 2026-10-31

The [merged review](reference/async-merged-review-2026-10-31.md) records the
native-file copy repair, four lint corrections, documentation cleanup, and
two newly reproduced suspension defects. Lisp active-session state and the
recursive rendering path still need execution-boundary isolation before
publication. Existing suite success does not cover those cases. The review
also records the full local check attempt and its follow-up checks. No
runtime state design was extended during this gate-repair pass.

## Plan review

Scope establishes allocation ownership; Pool establishes canonical identity
and lifetime; Context owns its existing dependencies; Error establishes
matching and detail lifetime; Channel establishes commitment and explicit
transport ownership. The new consumer relies on these contracts rather than
rechecking them or inferring object graphs.

The task lifetime contract establishes that borrowed Scopes remain alive
until their users finish. The design relies on that premise instead of adding
lifetime tracking or destruction validation to Scope.

The execution stack serves the concrete need to preserve nested activations
while one native thread runs another execution. Persistent execution records
serve suspended locals and cleanup, not a new user allocation domain. Reuse
existing owner records and operations; no uniform frame hierarchy, duplicate
policy/cache instances, or public execution-context framework is selected.
The selected representation keeps down for valid retained ancestry and
removes up and its misuse check without replacement. The API rename aligns
active-region names with Context and Pool without changing region behavior.
Boundary save/restore reuses module-owned TLS views and records; the stable
Scope base cell preserves captured destinations without an allocation-path
task lookup. No new public state framework or deep-copy mechanism is needed.
Stable, nonmoving task stacks preserve native landings, local addresses, and
existing cleanup paths instead of adding stackless lifetime reconstruction.
They add stack storage, switching, platform support, and a task-entry boundary.
The configurable 8 MiB default preserves the current worker budget. Guarded,
demand-paged mappings provide stable storage without custom growth or fault
recovery. The four native release targets bound platform work; thread affinity
avoids migration machinery. Stack-bound consumers use actual task bounds.
Local prototype timings and peak RSS are recorded below the delivery hold;
isolated switching costs and wider platform/performance effects remain open.
Review the complete change for Scope-specific migration and unchanged Pool
operations, rather than retaining two authorities or adding compatibility
machinery without a selected need.

Generated suspension code should remain ordinary x2c control flow using the
existing runtime owners and compiler lowering operations. Public validators
selected here: none. The dedicated diagnostic identifies an unavailable async
backend on unsupported targets. Focused scenarios above
protect lifetime, state isolation, and live native crossings; they do not add
origin checks, graph validation, or a recurring validation requirement.

The Scope layout, naming, boundary installation, first native stackful backend,
stack sizing, platform scope, and prohibition on thread migration are selected.
The Task.run lifecycle, batch cancellation/shutdown, and synchronous source
cleanup and initial task inheritance are selected. The inheritance contract
reuses caller-owned storage and identity while keeping mutable activations
independent; it adds no implicit Context, pool, or eagerly allocated cache.
The switching dependency and guarded-layout integration are selected and
implemented privately. The first API and strict build have local execution
evidence. Remaining target coverage, performance and retention acceptance,
and final publication proof remain unresolved. Further architecture,
publication, or pushing is not
authorized by successful prototype tests. Delivery retains the explicit hold.
