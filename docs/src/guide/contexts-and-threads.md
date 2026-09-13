# Contexts and Threads

A `Context` gives a task its own `Scope`, `Error` state, and `Match` state. An
isolated `Context` also gives it child `String` and `List` pools. Closing the
`Context` restores the state that was active before it opened and reclaims
everything that was not exported.

If opening a `Context` cannot finish, the partial `Scope`, pools, `Error`
state, and `Match` state are closed before the failure reaches an outer
`catch`. A failed open therefore never changes `Context.current()` or leaves
one of its pools active.

A `Thread` runs a callback in an isolated `Context` on a native worker thread.
The worker may read parent values and may access shared mutable objects. The
program is responsible for keeping those objects alive and coordinating any
access that could race.

## Use a Context for bounded work

`Context.open` and `Context.open_named` inherit the current `String` and `List`
pools. They are useful when the work needs fresh `Scope`, `Error`, and `Match`
state but its canonical immutable values should have the same lifetime as their
caller.

`Context.open_isolated` and `Context.open_isolated_named` add child `String`
and `List` pools. New temporary `String`s and `List`s can then be reclaimed
when the `Context` closes. Values already present in a parent pool remain
visible and keep their identity.

The following program builds a cyclic mutable result around a private `String`,
exports it, and closes the `Context`. `Context.export` moves the `Array` and
`Map` storage into the caller's `Scope`, copies the private immutable values
into the caller's pools, and preserves the cycle:

```x2c
#include <stdio.h>

int main(void) {
  Context input = Context.open_isolated_named("input file");
  String temporary = String.new("temporary text");
  Array values = %[];
  values.push(temporary);

  Map result = %{};
  result[<values>] = values;
  result[<self>] = result;

  result = input.export(result);
  input.close();

  printf("%s\n", result[<values>].array()[0].string());
  return 0;
}
```

Always use the value returned by `Context.export`. Mutable `Array`s, `Map`s,
`Block`s, `Buffer`s, and wide scalar boxes retain their identity when their
storage can be moved. Private `String`s, `Atom`s, and `List`s are canonicalized
in the destination pools, so their pointers may change. Export walks nested
`Array`s, `Map`s, and `List`s, including repeated references and `Array`/`Map`
cycles. A registered custom value can provide its own `Context` exporter.
`void` exports as `void`.

The six packed `Array`s from `typed-array.x` and the three packed `Map`s from
`typed-map.x` follow the same rule. A container owned by the source `Context`
keeps its pointer while its header and backing storage move together. A
borrowed container is returned untouched. `MapIntInt` and `MapLongDouble`
retain their native entries and continue growing in the destination `Scope`.
`MapStringString` canonicalizes every key and value in the destination `String`
pool before it moves; `String` pointers may therefore change. If unusual input
contains two keys that become the same destination `String`, the entry visited
later in source bucket order replaces the earlier one. `Map` traversal order
remains unspecified.

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

`Thread.start` copies the input structure's bytes. It does not copy anything
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
    raise %(bad-arg (owner "count worker"));

  for (int i = 0; i < work.iterations; i++) {
    work.mutex.lock();
    (*work.counter)++;
    work.mutex.unlock();
  }
  return work.iterations;
}

int main(void) {
  int counter = 0;
  Mutex mutex = Mutex.new();
  Work work = { 1000, &counter, mutex };
  Thread first = Thread.start(count, &work, sizeof(work));
  Thread second = Thread.start(count, &work, sizeof(work));

  first.join();
  second.join();
  first.free();
  second.free();
  mutex.free();
  return counter == 2000 ? 0 : 1;
}
```

Each worker gets private `String` and `List` pools, so it can create large
amounts of temporary immutable data without retaining that data for the process
lifetime. A result cannot be exported before the join. The callback returns
one `Var`; when the caller invokes
`Thread.join`, the runtime waits for the worker and exports that result into
the joining `Scope` and active `String` and `List` pools. Returned immutable
values remain in sealed worker-private pools until the join, even after the
callback finishes. Once the native join succeeds, the `Thread` consumes that
sealed storage even if exporting the result raises. Call `Thread.free` after
`Thread.join` returns or after catching an `Error` raised by the join; the
failed export cannot be retried.

Process shutdown rejects every started `Thread` until its native join succeeds,
even when its callback has already finished. This ensures that the worker's
result `Scope` and pools are reclaimed before the runtime shuts down.

An `Error` that reaches the callback's outer `catch` makes `Thread.join` raise
`<join-fail>` with the worker's captured errors. That `raise` does not return
to the joiner. `Thread.join` yields the worker's exported result or transfers.
A callback that returns `void` joins as `void`; a handled failure transfers
instead of returning a sentinel. The outer `catch` runs before the worker's
default `Error` policy, so even `<collect>`, `<log>`, and `<ignore>` errors
that reach it end the callback. Catch or otherwise handle a resumable `Error`
inside the callback when execution should continue. Captured values use the
same sealed worker storage as an ordinary result and enter the joining pools
only during `Thread.join`. A worker `Error` whose policy is `<log>` also passes
through the global `Logger` error handler. `Logger` serializes its sinks; in
particular, a memory sink copies worker-private `String`s and `List`s into the
pools captured when its `Logger` was created, so logged entries remain valid
after the worker exits or a registration `Context` closes.

The more complete `examples/power/threads.x` uses two workers, parent
`String`s, private temporary `List`s and `String`s, a shared counter protected
by a `Mutex`, joined `Map` results, and a global memory `Logger` sink.

All type and protocol registration must finish before the first successful
`Thread.start`. Starting native execution freezes descriptor registration. A
worker cannot observe a partially changed dispatch table.

`Thread.start` also turns on locking for the `String` and `List` interning
pools. A process that has never started a worker needs no locks for those
pools. Create native threads through `Thread`; one made by calling
`pthread_create` directly can share interned values with no lock protecting
them.
