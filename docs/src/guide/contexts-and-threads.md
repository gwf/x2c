# Contexts and Threads

A `Context` runs a piece of work with its own `Scope`, `Error` state, and
`Match` state, and reclaims what that work allocated when it closes. A
`Thread` runs a function on another native thread. This chapter covers
bounded work in a `Context`, starting and joining threads, running batches
of jobs on threads or as `Channel` tasks on one thread, stopping jobs, and
mapping over data in parallel.

## Use a Context for bounded work

Open a `Context`, do the work, export the values that must survive, and close
the `Context`. Closing it restores the state that was active before it opened
and reclaims everything that was not exported.

`Context.open` and `Context.open_named` use the current canonical-value
pool. Use them when the work needs fresh `Scope`, `Error`, and `Match` state
and its `String`s and `List`s should live as long as the caller's.

`Context.open_isolated` and `Context.open_isolated_named` add a child pool.
New temporary `String`s and `List`s are then reclaimed when the `Context`
closes. Values already in a parent pool stay visible and keep their
identity. The name given to a `_named` form appears only in `Scope` leak
diagnostics.

If opening a `Context` fails, the parts already opened are closed before the
failure reaches an outer `catch`. A failed open does not change
`Context.current()` or leave a pool active.

The following program builds a cyclic mutable result around a private `String`,
exports it, and closes the `Context`. `Context.export` moves the `Array` and
`Map` storage into the caller's `Scope`, copies the private immutable values
into the caller's pool, and preserves the cycle:

```x2c
#include <stdio.h>

int main(void) {
  Context input = Context.open_isolated_named("input file");
  String temporary = String.new("temporary text");
  Array values = [];
  values.push(temporary);

  Map result = {};
  result[<values>] = values;
  result[<self>] = result;

  result = input.export(result);
  input.close();

  printf("%s\n", result[<values>].array()[0].string());
  return 0;
}
```

Always use the value returned by `Context.export`. Mutable `Array`s, `Map`s,
`Block`s, `Bytes`, `Buffer`s, and boxed wide numbers such as `long` retain
their identity when their storage can be moved. Private `String`s, `Atom`s,
and `List`s are canonicalized in the destination pool, so their pointers may
change. Export walks nested `Array`s, `Map`s, and `List`s, including repeated
references and `Array`/`Map` cycles. A registered custom value can provide
its own `Context` exporter. `void` exports as `void`.

The seven packed `Array`s from `typed-array.x` and the four packed `Map`s
from `typed-map.x` follow the same rule. A container owned by the source
`Context` keeps its pointer, and its record and backing storage move
together. A borrowed container is returned unchanged. The numeric families
keep their native entries and continue growing in the destination `Scope`.
`ArrayString` canonicalizes its elements, `MapStringString` its keys and
values, and `MapStringInt` its keys, in the destination pool before the
container moves, so their `String` pointers may change. If two keys become
the same destination `String`, the entry visited later in source bucket
order replaces the earlier one. `Map` traversal order is unspecified.

A custom `protocol Var(T)` participant may implement `T.export_context` to
move its mutable storage into another `Context`. The member is optional, like
the other `Var` methods. Its implementation recursively exports nested values
and moves its owned allocations through the `Context` helpers; application code
still calls `Context.export` on the complete value.

Export covers values allocated through the active `Context` and values
inherited or borrowed from its caller. Code that manually creates an unrelated
`Scope` or canonical-value pool must manage that lifetime itself; returning
such a value as though the `Context` owned it is undefined behavior.

The complete program is `contexts.x` in the x2c home's `examples/power/`
directory.

## Pass shared values to a worker

`Thread.start(function, input)` runs a `Var`-to-`Var` function on a new
native worker thread and returns a `Thread` handle. Keep everything the input
refers to alive and unchanged until the worker is joined. Preserve any
mutable output explicitly before the function returns.

```x2c
static Var twice(Var input) => (int) input * 2;

int main(void) {
  Array pending = [Thread.start(twice, 21)];
  printf("%s\n", Thread.finish_any(pending));
  return 0;
}
```

```text
42
```

`Thread.finish_any` waits until a thread in the `Array` has finished, joins
it, removes it from the `Array`, frees its handle, and returns its result.

The worker runs inside a `Context` that is not isolated. It gets fresh
`Scope`, `Error`, and `Match` state and uses the shared process pool, as
[Interned values outlive workers](#interned-values-outlive-workers)
describes.

The input bits are copied, while referenced storage stays with its caller. Keep
the input graph alive and read-only until join. This includes a Map's contents
and the storage of boxed wide numbers. Join returns result bits without
exporting or transferring storage.

For mutable output, supply an owner that only this worker uses until join:

```x2c
static Var make_answer(Var destination) {
  Scope output = destination;
  Map result = {answer: 42};
  result.move_to(&output);
  return result;
}

int main(void) {
  Scope output = Scope.child();
  Thread worker = Thread.start(make_answer, output);
  Map result = worker.join();
  worker.free();
  printf("%d\n", result[<answer>].int());
  output.destroy();
  return 0;
}
```

```text
42
```

Each concurrent worker needs its own output scope. Destroy these scopes only
after all their users have finished, including when a worker fails. A transfer
moves the Map's record, buffers, and explicitly owned contents; it does not
follow references or adopt inserted members.

`Thread.start_raw` copies the input structure's bytes. It does not copy
anything reached through pointers in that structure. A pointer, `String`,
`List`, `Map`, or other handle therefore refers to the same parent object in
the worker. The copied bytes have `max_align_t` alignment, matching ordinary
allocation; do not pass a structure that requires extended alignment beyond
that.

Parent immutable `String`s and `List`s can be read directly. Shared mutable
objects can also be read or changed, but normal C data-race rules apply: a read
is safe only when no thread can write at the same time, and coordinated writes
need a `Mutex` or another suitable mechanism. Every referenced parent object,
including the `Mutex`, must remain alive until all workers using it have
joined.

```x2c
typedef struct Work {
  int iterations;
  int *counter;
  Mutex mutex;
} Work;

static Var count(const void *input, size_t input_size) {
  const Work *work = input;
  if (input_size != sizeof(Work))
    raise %(bad-arg (operation "count worker"));

  for (int i = 0; i < work.iterations; i++) {
    $lock(work.mutex) (*work.counter)++;
  }
  return work.iterations;
}

int main(void) {
  int counter = 0;
  Mutex mutex = Mutex.new();
  Work work = { 1000, &counter, mutex };
  Thread first = Thread.start_raw(count, &work, sizeof(work));
  Thread second = Thread.start_raw(count, &work, sizeof(work));

  first.join();
  second.join();
  first.free();
  second.free();
  mutex.free();
  return counter == 2000 ? 0 : 1;
}
```

Mutable callback storage is temporary. A callback that returns a Map, Array,
boxed number, or custom allocation must explicitly preserve its storage before
returning. A borrowed result retains its existing owner. Interned `String`s
and `List`s need no preservation; see
[Interned values outlive workers](#interned-values-outlive-workers).

`Thread.join` waits for the worker and returns its result bits. It does not
walk references or transfer ownership. A callback that returns `void` joins
as `void`. A failed native join can be retried; a successful join consumes
the handle even if it then raises the worker's error. Call `Thread.free`
after join returns or after its `Error` is caught.

Join every started Thread before process exit. Shutdown aborts if a worker
remains unjoined. `Thread.stop` requests [cooperative
stopping](#cooperative-stopping); it does not forcibly interrupt native I/O
or computation.

A worker uses the starting thread's `Error` policy, described in
[Handlers and policy](exceptions.md#handlers-and-policy). A cause whose
policy is `<collect>`, `<log>`, or `<ignore>` returns to its `raise` inside
the callback, as it does on the starting thread. A cause whose policy is
`<abort>` ends the callback instead. That policy applies to every code with
no policy set and to every [shared cause](exceptions.md#one-error-protocol),
the built-in codes that always abort. `Thread.join` then raises `<join-fail>`
with the worker's captured errors, and that `raise` does not return to the
joiner. Catch `<join-fail>` around the join to handle a failed worker.

Join preserves the captured errors for its caller. A worker `Error` whose
policy is `<log>` also passes through the global `Logger` error handler.
`Logger` serializes its sinks. A memory sink copies worker `String`s and
`List`s into the pool captured when its `Logger` was created, so logged
entries stay valid after the worker exits.

The more complete `threads.x`, in the same `examples/power/` directory, uses
two workers, parent `String`s and `List`s, a shared counter protected by a
`Mutex`, explicitly owned Map results, and a global memory `Logger` sink.

Finish all type and protocol registration before the first successful
`Thread.start` or `Thread.start_raw`. After that, registering another type
or protocol raises `<bad-state>`. Boxing is not restricted: a worker may box
the first value of a type that was declared before the start.

`Thread.start` also turns on locking for the canonical-value pools. A process
that has never started a worker does not lock them. Create native threads
through `Thread`; one made by calling `pthread_create` directly can share
interned values with no lock protecting them.

## Interned values outlive workers

Workers started by `Thread.start`, `Thread.start_raw`, and
[`Thread.run`](#run-cooperating-jobs-as-one-batch), and the callbacks of
the ordinary [`parallel_map`](#parallel-mapping-and-explicit-ownership), begin
with the shared process pool active. This is the root canonical-value pool
that every thread starts in. A `String` or `List` that a worker interns there
stays valid after the worker exits, so it needs no export or move.

Those values also stay until process shutdown. Ending a job does not reclaim
them, and a `Channel`'s capacity does not bound them. To bound that memory,
open an isolated `Context` or a pool inside the job. An explicitly opened
pool keeps its usual rule: export or copy the values that must survive before
closing it.

## Run cooperating jobs as one batch

`Thread.run(jobs, completed)` accepts an Array of zero-argument `Func` values.
It starts native workers and owns every handle until all jobs finish. Each
successful joined result reaches `completed` on the calling thread. The
callback is optional: `Thread.run(jobs)` discards result bits after joining. A
void job result is also a successful completion.

Capturing lambdas already produce `Func` values. Bind a direct function or a
noncapturing lambda to `Func` before putting it in an Array. This uses the
ordinary callable conversion rather than a separate batch calling convention.

```x2c
static int answer(void) => 42;

int main(void) {
  Func job = answer;
  Thread.run([job], %!(Var result) => {
    printf("%ld\n", result.integer());
  });
  return 0;
}
```

```text
42
```

Keep the jobs, their captures, callback code, and borrowed objects alive
through `Thread.run`. Capturing a Map copies its handle; its contents can be
changed by one designated writer while the caller waits. Changing a captured
variable's binding itself requires `using &name`. The completion callback must
perform short coordination and must not wait on participant progress.

Each job's temporary mutable storage is reclaimed when the job exits. Its
interned `String`s and `List`s use the shared process pool, as described in
[Interned values outlive workers](#interned-values-outlive-workers).

Completion callbacks run after job temporary storage has been reclaimed. Jobs
must explicitly preserve any returned mutable storage before exit, for example
by moving it into a separate output scope supplied for that job. Inserting a
reference into a Map or Array does not preserve its owner. The developer owns
output cleanup on both success and failure; Thread.run neither adopts nor
destroys those output scopes.

On startup, job, completion-callback, or coordinator-stop failure,
`Thread.run` stops all remaining jobs before joining any of them. It preserves
the triggering error, invokes no completion callbacks during failure cleanup,
and waits for every started worker before returning control through the error.
This includes partial startup and nested batches. Cleanup joins cannot be
interrupted by a pending stop. A native join failure that prevents establishing
safe completion aborts rather than return with live borrowers.

## Run Channel jobs on one native thread

A [`Channel`](channels.md) passes `Var` values between threads or tasks.
`Task.run(jobs, completed)` runs a batch of jobs, called tasks, on the calling
native thread. When a task waits on a `Channel`, it is suspended so another
task can run. Each task has its own native stack, so its pending `catch`
handlers and cleanup stay in place while it waits. Tasks do not provide CPU
parallelism. A blocking native call or computation that never waits delays
every job in the batch.

Use the same Channel operations and completion callback shape as `Thread.run`.
The callback runs after job cleanup, under restored caller state, and must
not wait for participant progress. The executable `channel-service.x`, in the
x2c home's `examples/power/` directory, shows request/reply and closes
requests after both clients finish.

Each task allocates in the caller's active `Scope` and uses the caller's
canonical-value pool for the whole batch. Its own `Scope.push` and
`Scope.pop` calls affect only that task. A task starts with no current
`Context`. It copies the caller's `Error` policies and error bound, but it
starts with no `Error.push` handlers, no recorded errors, and no pending
cleanup of its own. Opening a Context inside a job remains explicit. An
ordinary Array return retains its owner and aliases; no implicit export or
ownership transfer occurs.

Keep all borrowed owners, Channels, jobs, and captures alive through
`Task.run`. The call returns or raises only after all participants finish
cleanup. Job or completion-callback failure stops unfinished jobs and preserves
the primary failure. Escaping job Errors are raised as `<join-fail>`, as
`Thread.join` raises them. Calling `Thread.stop` on the `Thread` that runs
`Task.run` requests that the batch stop. A `Channel` message already accepted
stays accepted; an owned send that was not yet accepted returns its storage
to the sender.

Cleanup code in a job, such as a `defer` or `finally` body, must not suspend.
`Channel.close` does not wait and is suitable for cleanup; other Channel
operations can wait or be stopped as usual. Stop is cooperative, and catching
it can delay shutdown. `Task.run` does not support nested calls; a nested call
raises `<bad-state>`.

Tasks run on macOS and Linux on arm64 and x86_64. Each task uses
an 8 MiB usable, demand-paged stack plus a guard page. Set
`X2C_TASK_STACK_BYTES` before the call to select another capacity of at least
32 KiB; capacity rounds up to the native page size. Smaller stacks can exhaust
space sooner. `Regex` compiling and matching, `Json` reading and writing, the
Lisp reader, and Lisp evaluation stop before the stack runs out and raise
their usual depth errors, so they allow less nesting on a small stack. Other
overflow is a native failure, without guaranteed cleanup.
Tasks stay on their original native thread. On other targets, `Task.run`
raises `<bad-state>`.

## Cooperative stopping

`thread.stop()` asks a `Thread` to stop; it does not interrupt the thread. The
request persists. It wakes the Thread if it is waiting on a `Channel` or for
job completion, and any later such wait observes it. Computation and native
I/O that never wait keep running. Stopping does not close a Channel, transfer
payload ownership, or forcibly terminate code.

A stopped operation releases its queue locks and then raises
`(bad-state (operation "Thread.stop") (cancelled 1))`. This is a
[shared cause](exceptions.md#one-error-protocol), so no `Error` policy can
make it resume. An explicit `catch` can handle it, so code that ignores
stopping can delay batch cleanup indefinitely.

A Channel insertion, dequeue, or rendezvous that already committed succeeds
even when a stop arrives before that operation returns. A later operation
observes the pending stop. A stopped receive raises; it is not successful EOF.
The normal application protocol still closes Channels and drains accepted data.

A batch can stop only its own jobs. Stopping it does not stop independently
owned services or other users of a borrowed Channel. A stopped client is not
evidence that a service finished reading borrowed request bytes. Keep those
bytes under an owner that survives actual borrower completion, including
failure cleanup. A service shared outside the batch needs an explicit way to
learn that a client failed, such as a failure reply.

## Parallel mapping and explicit ownership

`source.parallel_map(callback, workers)` describes mapping `callback` over the
iterator `source` with at most `workers` threads. Nothing runs until
`.foldl(seed, reducer)` consumes it. The reducer runs on the caller in
completion order. If the reducer keeps worker-owned storage, it must move
that storage to its own owner with a `move_to` operation.

`source.parallel_map(callback, workers).foldl(seed, reducer)` reuses bounded
workers. Each worker keeps its callback storage alive until the reducer
returns. Returning a value or inserting it into a container does not transfer
ownership. Untransferred storage is reclaimed by the worker. References can
form cycles without changing this rule.

With a `void` seed, the first result becomes the accumulator without a reducer
call. Use that form only when the result survives worker cleanup independently.
For worker-owned results, supply a seed and transfer storage in the reducer.
`source.parallel_map_in(pool, callback, workers)` selects a borrowed
String/List pool during callbacks. The caller keeps that pool and its ancestors
alive until the fold finishes, including worker shutdown on failure. Workers
restore their previous pool and never release the borrowed pool. Source
traversal and the reducer continue in the caller's active pool. A shared
temporary pool can thus collect worker text while the reducer interns surviving
words in the caller's pool. All temporary canonical values remain until the
caller closes that pool. Workers may intern into it concurrently.

The ordinary `parallel_map` uses the shared process pool, as described in
[Interned values outlive workers](#interned-values-outlive-workers). On
failure, the fold requests stop on all workers before joining them. A stop
wakes a worker waiting on a Channel; it does not interrupt native I/O.

## Where to go next

- [Explicit Storage Ownership](storage-ownership.md) moves storage between
  owners and threads.
