# Explicit storage ownership

Each thread has a root Scope. Retained regions provide shorter allocation
lifetimes. A Map or Array record and its backing allocations belong to the
scope active at construction. Growth replaces buffers under the record's
current allocation owner without changing the container handle.

`container.scope()` explicitly acquires a separate scope for owned contents.
That scope is created lazily beneath `Scope.owner(container)`. The container
record and buffers stay outside it. Ordinary construction, copying, slicing,
and insertion do not create an owned-content scope or adopt referenced values.

## Adopt a container

Move the inner container into the outer container's owned-content scope:

```x2c
Map parent = {};
Array child = [];
Scope contents = parent.scope();
child.move_to(&contents);
parent["items"] = child;
child.push(42);
parent.cleanup();
```

`move_to` moves the child's record, backing buffers, and any owned-content
scope together. The insertion stores a reference. These are separate
operations. Destroying the parent now destroys the child as well. Do not
schedule another cleanup through an alias to that child. Every pointer into
either destroyed container becomes invalid.

`container.move_to(&destination)` preserves addresses and moves a fixed
number of allocation records plus any owned-content scope. The destination
slot acquires a Scope if empty. Container cleanup destroys nullable owned
contents, then frees its buffers and record. Unadopted referenced values
retain their independent owners.

`scope.transfer(destination)` reparents a complete ownership subtree. It
changes a fixed number of ownership links without copying elements or walking
descendants. Destruction still visits and frees the adopted storage.

`scope.transfer(NULL)` detaches that subtree from its parent. The subtree
survives destruction of its former parent. Its allocations retain their
existing owning scopes, so `Scope.owner(pointer)` still works. Reattach with
another transfer, or destroy the detached scope explicitly.

Transfers require exclusive access to the source and affected ownership
lists. Concurrent adoption into a shared parent is unsupported. The source
must not be active on an allocation stack. A nonnull destination must be live
and must not be the source or its descendant. The runtime does not prove
graph lifetimes or revoke aliases. Transferring storage does not grant
exclusive access to referenced values.

Converting a container to Scope calls `scope()` and can allocate its owned
contents scope. Moving that scope alone moves only those contents; it does
not move the container's record or buffers. Use `move_to` for the complete
container. `scope.parent()` returns the lifetime parent. `Scope.owner(pointer)`
reports an individual managed allocation's owner without acquiring any scope.

## Give graph nodes a common owner

Object references may form cycles. The lifetime hierarchy must not.

```x2c
Scope graph = $auto(Scope.new());
Array first = [], second = [];
first.move_to(&graph);
second.move_to(&graph);
first.push(second);
second.push(first);
```

Both vertices belong to `graph`. Its cleanup destroys both vertices without
following their edges. Neither vertex individually owns the other. To add a
sibling later, move a new vertex to `Scope.owner(first)`. A node reference
alone does not grant authority to destroy the common owner.

To protect a referenced object from a container's destruction, keep its
ownership separate. Its independent owner must remain alive while borrowers
use the reference. Copying and slicing a container creates independent storage
with shallow references; it does not clone or adopt nested objects.

## Share references between threads

Channels carry non-void Vars. Ordinary `send` borrows references without
transferring, cloning, or recursively exporting storage. A parent can send
one Map to several workers, keep it alive, and refrain from writing until
their reads finish.

`Channel.send_owned` explicitly groups a private container's record, buffers,
and owned contents for transfer. A failed send restores its original owner.
After acceptance, the Channel holds the detached payload without adopting it
as a child. The receiver recovers its scope from the existing allocation
header and moves the container into its private current scope before returning.
Abandoned queued owned payloads are
explicitly destroyed after all Channel users finish. See
[Channels](channels.md) for the transport contract.

The developer coordinates reads, writes, and destruction, including allocation
and ownership links. Scope operations do not lock those links. A thread must
have exclusive access while allocating, resizing, freeing, or transferring
that storage. Sending successfully does not mean a borrower has finished.

## Canonical values have separate owners

Strings and cons cells belong to canonical pools. Moving a Map cannot
extend the lifetime of keys in a private pool. An immutable cons cell can also
reference a mutable object whose lifetime remains independent.

Batch execution selects the process canonical pool for ordinary job interning.
Those values outlive jobs and returned Maps, with retention until process
shutdown. Deliberately shorter-lived pools remain the developer's responsibility.
Channel capacity does not bound canonical-pool retention.

Explicit `Context.export` retains its recursive semantics: it exports private
canonical values, preserves container identities, and keeps explicitly adopted
children under their parent when both participate in the same root export.
Reference traversal order does not change that adoption. Exporting only a child
can move it independently. The export memo breaks reference cycles and records
storage moves; root export commits the moves after recursive value export.
This operation is separate from both Scope transfer and channel transport.

Blocks remain type agnostic. `Block.new` creates ordinary managed handle and
backing allocations. `Block.scope()` lazily acquires an owned-content scope
without inspecting the fixed-width elements. Arrays use the same storage.
