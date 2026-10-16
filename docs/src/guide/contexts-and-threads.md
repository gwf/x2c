# Contexts and Threads

A `Context` gives a task its own `Scope`, `Error` state, and `Match` state. An
isolated `Context` also gives it a child canonical-value pool, which its
`String`s and `List`s share. Closing the `Context` restores the state that was
active before it opened and reclaims everything that was not exported.

If opening a `Context` fails, the parts already opened are closed before the
failure reaches an outer `catch`. A failed open does not change
`Context.current()` or leave a pool active.

A `Thread` runs a callback in an isolated `Context` on a native worker thread.
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

Each worker gets a private canonical-value pool, so its temporary
`String`s and `List`s are not kept for the life of the process. The
callback returns one `Var`. `Thread.join` waits for the worker and exports
that result into the joining `Scope` and active pool. Until the join, the
result stays in the sealed worker pool, even after the callback finishes.
Once the native join succeeds, the `Thread` consumes that storage, even if
exporting the result raises. A failed export cannot be retried. Call
`Thread.free` after `Thread.join` returns or after catching an `Error`
raised by the join.

A `Thread` cannot be detached or cancelled. Join every started `Thread`
before the process exits. If a worker is
still unjoined at shutdown, even one whose callback has finished, the
runtime prints a message and aborts. The join reclaims the worker's result
`Scope` and pool.

A worker uses the starting thread's `Error` policy. A cause whose policy is
`<collect>`, `<log>`, or `<ignore>` returns to its `raise` inside the
callback, as it does on the starting thread. A cause whose policy is
`<abort>` leaves the callback. That includes every shared cause and every
code that no policy names. `Thread.join` then raises `<join-fail>` with the
worker's captured errors, and that `raise` does not return to the joiner.
So `Thread.join` either returns the worker's exported result or transfers.
A callback that returns `void` joins as `void`.

Captured errors stay in the sealed worker storage and enter the joining
pool only during `Thread.join`. A worker `Error` whose policy is `<log>`
also passes through the global `Logger` error handler. `Logger` serializes
its sinks. A memory sink copies worker `String`s and `List`s into the pool
captured when its `Logger` was created, so logged entries stay valid after
the worker exits.

The more complete `examples/power/threads.x` uses two workers, parent
`String`s, private temporary `List`s and `String`s, a shared counter protected
by a `Mutex`, joined `Map` results, and a global memory `Logger` sink.

All type and protocol registration must finish before the first successful
`Thread.start`. Starting native execution freezes descriptor declaration.
Boxing is not frozen: a worker may box the first value of a declared class,
and every thread then reads that class's complete row.

`Thread.start` also turns on locking for the canonical-value pools. A process
that has never started a worker does not lock them. Create native threads
through `Thread`; one made by calling `pthread_create` directly can share
interned values with no lock protecting them.
