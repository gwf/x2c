# Contexts and Threads

A `Context` gives a task its own `Scope`, `Error` state, and `Match` state. An
isolated `Context` also gives it a child canonical-value pool, which its
`String`s and `List`s share. Closing the `Context` restores the state that was
active before it opened and reclaims everything that was not exported.

If opening a `Context` fails, the parts already opened are closed before the
failure reaches an outer `catch`. A failed open does not change
`Context.current()` or leave a pool active.

`Thread.start` and `Thread.start_raw` run callbacks in isolated `Context`s on
native worker threads. `Thread.run` uses the shared process canonical pool
for its jobs, as described below.
The worker may read parent values and may access shared mutable objects. The
program must keep those objects alive and coordinate any access that could
race.

## Use a Context for bounded work

`Context.open` and `Context.open_named` use the current canonical-value
pool. Use them when the work needs fresh `Scope`, `Error`, and `Match` state
and its `String`s and `List`s should live as long as the caller's.

`Context.open_isolated` and `Context.open_isolated_named` add a child pool.
New temporary `String`s and `List`s are then reclaimed when the `Context`
closes. Values already in a parent pool stay visible and keep their
identity. The name given to a `_named` form appears only in `Scope` leak
diagnostics.

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
`Block`s, `Bytes`, `Buffer`s, and wide scalar boxes retain their identity when their
storage can be moved. Private `String`s, `Atom`s, and `List`s are canonicalized
in the destination pool, so their pointers may change. Export walks nested
`Array`s, `Map`s, and `List`s, including repeated references and `Array`/`Map`
cycles. A registered custom value can provide its own `Context` exporter.
`void` exports as `void`.

The seven packed `Array`s from `typed-array.x` and the four packed `Map`s
from `typed-map.x` follow the same rule. A container owned by the source
`Context` keeps its pointer, and its header and backing storage move
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
`Scope` or immutable pool must manage that lifetime itself; returning such a
value as though the `Context` owned it is undefined behavior.

The complete program is in `examples/power/contexts.x`.

## Pass shared values to a worker

`Thread.start(function, input)` calls a `Var`-to-`Var` function with one input.
The input bits are copied, while referenced storage stays with its caller.
Keep the input graph alive and read-only until join. This includes a Map's
contents and the storage of wide boxed scalars. Join returns result bits without
exporting or transferring storage. Preserve worker-created mutable output
explicitly before the callback exits. Each concurrent worker needs exclusive
access to its output owner; do not allocate into a shared caller scope.

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

`Thread.start_raw` copies the input structure's bytes. It does not copy anything
reached through pointers in that structure. A pointer, `String`, `List`, `Map`,
or other handle therefore refers to the same parent object in the worker. The
copied bytes have `max_align_t` alignment, matching ordinary allocation; do not
pass a structure that requires extended alignment beyond that.

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

Workers start with the shared process canonical pool, so canonical Strings
and Lists survive callback exit. Explicit private pools retain their own
lifetime rules. Mutable callback storage is temporary. A callback that returns
a Map, Array, boxed number, or custom allocation must explicitly preserve its
storage before returning. A borrowed result retains its existing owner.

`Thread.join` waits for the worker and returns its result bits. It does not
walk references or transfer ownership. A failed native join can be retried;
a successful join consumes the handle even if reporting a captured Error
raises. Call `Thread.free` after join returns or its Error is caught.

Join every started Thread before process exit. `Thread.stop` requests
cooperative stopping; it does not forcibly interrupt native I/O or computation.
Shutdown aborts if a worker remains unjoined. Join releases captured Error
storage, but leaves developer-owned results alone.

A worker uses the starting thread's `Error` policy. A cause whose policy is
`<collect>`, `<log>`, or `<ignore>` returns to its `raise` inside the
callback, as it does on the starting thread. A cause whose policy is
`<abort>` leaves the callback. That includes every shared cause and every
code that no policy names. `Thread.join` then raises `<join-fail>` with the
worker's captured errors, and that `raise` does not return to the joiner.
So `Thread.join` either returns the worker's result bits or transfers.
A callback that returns `void` joins as `void`.

Captured Error allocations have separate storage until join. Their canonical
values use the shared pool. Join preserves the captured errors for its caller. A worker `Error` whose policy is `<log>`
also passes through the global `Logger` error handler. `Logger` serializes
its sinks. A memory sink copies worker `String`s and `List`s into the pool
captured when its `Logger` was created, so logged entries stay valid after
the worker exits.

The more complete `examples/power/threads.x` uses two workers, parent
`String`s and `List`s, a shared counter protected by a `Mutex`, explicitly
owned Map results, and a global memory `Logger` sink.

All type and protocol registration must finish before the first successful
`Thread.start` or `Thread.start_raw`. Starting native execution freezes
descriptor declaration.
Boxing is not frozen: a worker may box the first value of a declared class,
and every thread then reads that class's complete row.

`Thread.start` also turns on locking for the canonical-value pools. A process
that has never started a worker does not lock them. Create native threads
through `Thread`; one made by calling `pthread_create` directly can share
interned values with no lock protecting them.

## Run cooperating jobs as one batch

`Thread.run(jobs, completed)` accepts an Array of zero-argument `Func` values.
It starts native workers and owns every handle until all jobs finish. Each
successful joined result reaches `completed` on the calling thread. The
callback is optional: `Thread.run(jobs)` discards result bits after joining. A void job result is also a successful completion.

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

Keep the jobs, their captures, callback code, and borrowed objects alive through
`Thread.run`. Capturing a Map copies its handle; its contents can be changed by
one designated writer while the caller waits. Changing a captured variable's
binding itself requires `using &name`. The completion callback must perform
short coordination and must not wait on participant progress.

Each job has bounded mutable work storage but starts with the shared process
canonical pool active. Interned Strings and Lists therefore survive job exit.
They remain until process shutdown, so bounded communication does not bound
canonical-pool memory. Opening an explicit private pool retains the usual
lifetime rules; explicitly preserve survivors before closing it. Ordinary
Thread callbacks also use the shared pool. ParallelMap borrows each result
until its reducer returns.

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

## Cooperative stopping

`thread.stop()` records a persistent stop request and wakes the Thread's
registered Channel or completion wait. It does not close a Channel, transfer
payload ownership, interrupt arbitrary native I/O, or forcibly terminate code.
A blocked operation leaves its queue locks before raising
`(bad-state (operation "Thread.stop") (cancelled 1))`. Ambient resumable Error
policies cannot suppress this shared cause. Explicit catches can handle it,
so code that ignores stopping can delay batch cleanup indefinitely.

A Channel insertion, dequeue, or rendezvous that already committed succeeds
even when a stop arrives before that operation returns. A later operation
observes the pending stop. A stopped receive raises; it is not successful EOF.
The normal application protocol still closes Channels and drains accepted data.

A batch can stop only its own jobs. It does not acquire cancellation authority
over independently owned services or everyone using a borrowed Channel. A
stopped client is not evidence that a service finished reading borrowed request
bytes. Keep those bytes under an owner that survives actual borrower completion,
including failure cleanup. Services shared outside the batch need an explicit
failure-reply or dependency protocol.

### Parallel mapping and explicit ownership

`source.parallel_map(callback, workers).foldl(seed, reducer)` reuses bounded
workers and invokes the reducer on the caller in completion order. Each worker
keeps its callback storage alive until the reducer returns. Returning a value
or inserting it into a container does not transfer ownership. The reducer must
explicitly transfer any worker-owned storage it retains, using the existing
`move_to` operations. Untransferred storage is reclaimed by the worker.
References can form cycles without changing this rule.

With a `void` seed, the first result becomes the accumulator without a reducer
call. Use that form only when the result survives worker cleanup independently.
For worker-owned results, supply a seed and transfer storage in the reducer.
Canonical values use the shared pool; explicitly opened private pools retain
their own lifetime rules. On failure, the fold requests stop on all workers
before joining them. Channel waits cooperate; arbitrary native I/O does not.
