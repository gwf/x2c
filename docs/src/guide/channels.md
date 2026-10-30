# Channels

A Channel communicates non-void `Var` values between threads. Ordinary `send`
and receive preserve borrowed payload ownership. `send_owned` explicitly hands
off one exclusively owned storage subtree. The application remains responsible
for independent nested lifetimes, aliases, and coordinated mutable access.

## Send, close, and drain

`send` blocks until the channel accepts a message. `receive` blocks until a
message is available, or returns `void` after normal closure and draining.
Iteration receives until that exhaustion. Null and nil remain ordinary data.

The sender explicitly closes a stream when no more messages will arrive. With
several senders, a coordinator closes after all senders finish. Closing is
idempotent, rejects new sends, wakes waiters, and preserves accepted messages
for draining. It does not acknowledge that consumers finished using a payload.

```x2c
int main(void) {
  Channel numbers = auto Channel.new(<i32>, 2);
  int total = 0;

  Thread.run([
    %!(void) => {
      for (int i = 1; i <= 4; ++i) numbers.send(i);
      numbers.close();
    },
    %!(void) using &total => {
      foreach (int value in numbers) total += value;
    }
  ]);

  printf("%d\n", total);
  return 0;
}
```

```text
10
```

## Choose capacity and message constraint

| Constructor | Behavior |
| --- | --- |
| `Channel.new()` | Any non-void Var, rendezvous. |
| `Channel.new(4)` | Any non-void Var, at most four buffered messages. |
| `Channel.new(<map>)` | Exact Map tag, rendezvous. |
| `Channel.new(<i32>, 4)` | Exact signed 32-bit integer tag, four buffered messages. |
| `Channel.new(<var>, <unbounded>)` | Any non-void Var, no configured buffer bound. |
| `Channel.new(<unbounded>)` | The same unrestricted unbounded channel. |

Rendezvous capacity is zero: send and receive commit together when matched.
Positive integer capacity bounds accepted queued messages. Unbounded channels
can still fail allocation. Capacity does not bound storage retained by messages
or canonical pools.

A constraint is an existing exact Var tag, not a conversion request. For example,
`<i32>` accepts an int; a long has a different tag. `<var>` removes the constraint.
A correctly tagged null handle is accepted by its constraint. `void` is always
rejected because it denotes exhausted reception. Unknown tags and invalid
capacities raise `bad-arg`; mismatched messages raise `bad-types`.

Buffered messages retain FIFO queue order. No fairness order is promised among
competing senders or receivers. Successful send means acceptance, not completed
processing.

## Borrow or hand off storage

Ordinary `send(value)` copies Var representation bits. The sender keeps its
storage ownership, and the application keeps storage alive for every borrower.
It can send
the same parent-owned Map to several readers without transferring it, while
preventing writes until those readers finish. Send acceptance is not evidence
that any borrower has finished using the object.

Use `send_owned` when a worker produces a Map whose storage must survive worker
exit. Ordinary Maps and Arrays start with records and buffers in their current
allocation owner and no owned-content scope. The send creates a transport Scope
only for that handoff and moves the record, buffers, and any existing owned
contents into it:

<!-- ignore: illustrative worker fragment with caller-supplied Channel and Map -->
```x2c,ignore
Map part = word_count(filename);
results.send_owned(part);
```

This is physical storage movement, not traversal of keys, elements, or referenced
objects. The transport scope remains detached while queued. Queue records contain
only the Var bits and an owned flag; the object's existing allocation header
recovers that scope. Workers never adopt into a shared Channel scope.

On failed send, ordinary container records, buffers, and owned contents return
to their original allocation owner. An existing owned-content scope also regains
its exact original parent, including a deliberately separate or detached owner.
The empty transport Scope is destroyed before the error is raised. Failures
before preparation leave ownership unchanged.

On successful acceptance, the sender relinquishes access and cleanup. A subtree
must not be sent twice. Do not leave a separate initializer `auto` or deferred cleanup armed
for it; sending cannot disarm existing cleanup. Unrelated aliases do not disappear
when ownership changes.

Receipt moves ordinary Map or Array storage into the receiver's private active
Scope and destroys the empty transport Scope before returning. The receiver may
clean up the container directly or move its complete storage to another owner.
If the receiver fails, private-scope teardown reclaims the received storage.

The automatic path handles ordinary Map and Array tags. Existing typed containers
and custom roots require a caller-prepared exclusive inactive subtree containing
their complete physical storage. For example, prepare a packed ArrayInt using
its existing move:

<!-- ignore: illustrative fragment with optional typed-array.x and a Channel -->
```x2c,ignore
ArrayInt values = ArrayInt.new();
values.push(17);
Scope transport = Scope.new();
values.move_to(&transport);
results.send_owned(values);
```

Until acceptance the caller owns this prepared scope. Failure restores its
original parent; a prepared detached scope remains detached and caller-owned.
After acceptance it belongs to the queue, then joins the receiver's private
scope as a child. A custom root must
be a live nonnull Scope allocation whose existing allocation owner is that
exclusive inactive subtree. The operation does not discover pointer provenance
or validate an object graph. Canonical Strings/Lists, ordinary scalars, borrowed
buffers, and interior pointers do not meet that custom-root contract.

Nested mutable values retain independent ownership unless explicitly moved into
the container's owned contents before handoff. Calling `scope()` creates that
owned-content scope lazily; it does not group the record or buffers. Move a nested
container's complete storage with `move_to`, rather than moving only its content
scope. Private-pool String keys do not become safe when their Map moves. Shared
process-pool Strings remain borrowable because the pool outlives all jobs.

A Channel's own storage scope, returned by `channel.scope()`, owns its native
queue mutex. Independent Channels do not share that mutex. Managed Threads
keep a private wait mutex and condition through join; unmanaged blocking calls
use temporary native wait resources. Queue nodes use native allocation independently of Scope
allocation lists. Allocation/tree metadata belongs to exclusive private owners;
no Scope or replacement tree mutex coordinates senders through a Channel.

Finish every user and waiter before freeing a Channel or destroying its owner.
Cleanup explicitly destroys undelivered owned subtrees and frees native queue
nodes outside the queue mutex. It never destroys ordinary borrowed payloads.
Initializer `auto` closes and frees the Channel; it does not join its users. `Thread.run`
finishes every participant before surrounding Channel cleanup on success or
failure. Parent-scope destruction uses the same native-resource finalizer.

## Failure and cooperative stopping

A Channel has no task-failure state. `Thread.run` observes a failed job, stops
all remaining jobs before joining them, and preserves the triggering error.
Blocked Channel operations wake on their own Thread's stop request and unwind
after releasing queue locks. They do not report successful exhaustion.

Acceptance and delivery have synchronized commitment points. A committed send
or receive succeeds despite a later stop. A pending stop before commitment
prevents that operation and raises the Thread stop cause. A stopped rendezvous
participant cannot be matched by another operation.

Thread stopping does not close Channels or stop unrelated users. Computation
and arbitrary native I/O remain cooperative. A cancelled client's request bytes
must stay alive until the actual service borrower finishes. Keep them under an
owner that survives the whole batch when that is the simplest arrangement.

Batch jobs use the shared process canonical pool by default. Interned Strings
there outlive the jobs, but stay until process shutdown. Explicit private pools
retain their own lifetime obligations. Transport and wakeups use raw storage
and native synchronization; they do not require interning.
