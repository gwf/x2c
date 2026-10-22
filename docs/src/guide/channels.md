# Channels

A Channel communicates non-void `Var` values between threads. Sending and
receiving copy representation bits without copying, adopting, or exporting
referenced storage. The application keeps that storage alive and coordinates
mutable access.

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
  Channel numbers = $auto(Channel.new(<i32>, 2));
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

## Storage ownership

A Channel has its own attached storage scope, returned by `channel.scope()`.
The scope owns native synchronization and queue storage. It also owns any
payload scopes explicitly transferred beneath it:

<!-- ignore: illustrative worker fragment with caller-supplied Channel and Map -->
```x2c,ignore
part.scope().transfer(results.scope());
results.send(part);
```

Transfer is separate from communication. It changes lifetime ownership, not
aliases or access permissions. Nested mutable values retain their independent
owners unless explicitly adopted. Private-pool String keys do not become safe
when their containing Map moves.

A consumer can merge a transferred Map and call `part.free()`. A failed send
does not undo a preceding transfer. An undelivered adopted Map stays beneath
the Channel's scope until explicitly moved or freed, or until scope destruction.
A plain borrowed payload is never recursively freed by Channel cleanup.

Finish every user and waiter before freeing a Channel or destroying its scope.
`$auto` calls Channel cleanup, which closes and frees it; cleanup does not join
its users. `Thread.run` completes its jobs before returning, so surrounding
Channel cleanup runs after batch teardown on both success and failure. Scope
owner destruction also releases the Channel's native resources.

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
