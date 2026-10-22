# Explicit storage ownership

Each thread has a root Scope. Retained regions provide shorter allocation
lifetimes. Maps and Arrays have private storage scopes beneath the scope
active at construction. A container's scope holds its stable handle and all
of its backing allocations. Growth can replace backing storage without
changing the container handle or its storage scope.

The storage scope does not own referenced values automatically. Inserting a
Map into another Map, or pushing an Array into an Array, copies the reference.
Nested objects keep their existing owners until an explicit transfer.

## Adopt a container

Transfer the inner container's scope beneath the outer container's scope:

```x2c
Map parent = {};
Array child = [];
child.scope().transfer(parent);
parent["items"] = child;
child.push(42);
parent.cleanup();
```

The transfer adopts the child's storage scope. The insertion stores a
reference. These are separate operations. Destroying the parent now destroys
the child as well. Do not schedule another cleanup through an alias to that
child. Every pointer into either destroyed container becomes invalid.

`scope.transfer(destination)` reparents a complete ownership subtree. It
changes a fixed number of ownership links without copying elements or walking
descendants. Destruction still visits and frees the adopted storage.

Transfers require live scopes and exclude concurrent destruction. The source
must not be active on an allocation stack, and the destination must not be
the source or its descendant. The runtime does not prove graph lifetimes or
revoke aliases. Transferring storage does not grant exclusive access.

`object.scope()` returns its storage scope. A Scope destination accepts a
container through that converter, so `child.scope().transfer(parent)` uses
the parent's scope. `scope.parent()` returns the lifetime parent. The existing
`Scope.owner(pointer)` query reports an individual managed allocation's owner;
it is not the lifetime-parent query.

## Give graph nodes a common owner

Object references may form cycles. The lifetime hierarchy must not.

```x2c
Scope graph = $auto(Scope.new());
Array first = [], second = [];
first.scope().transfer(graph);
second.scope().transfer(graph);
first.push(second);
second.push(first);
```

Both vertices are children of `graph`. Its cleanup destroys both vertices
without following their edges. Neither vertex individually owns the other.
To add a sibling later, transfer a new vertex beneath the existing vertex's
`scope().parent()`. A node reference alone does not grant authority to destroy
the common owner.

To protect a referenced object from a container's destruction, keep its
ownership separate. Its independent owner must remain alive while borrowers
use the reference. Copying and slicing a container creates independent storage
with shallow references; it does not clone or adopt nested objects.

## Share references between threads

Channels carry non-void Vars. Sending and receiving do not transfer, clone,
or recursively export referenced storage. A parent can send one Map to several
workers, keep it alive, and refrain from writing until their reads finish.

When a worker wants a result to survive its own scope, it can explicitly
transfer the result's storage scope into a longer-lived owner before sending.
A failed send does not undo that earlier transfer. Sending successfully also
does not mean the receiver has finished borrowing the value.

The developer coordinates reads, writes, and destruction. Metadata operations
synchronize ownership links so independent workers can adopt different child
scopes into one live owner while another thread destroys completed children.
Those internal locks do not synchronize access to Map entries or Array elements.

## Canonical values have separate owners

Strings and cons cells belong to canonical pools. Moving a Map scope cannot
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

Raw Blocks remain type agnostic. `Block.new` creates ordinary managed handle
and backing allocations. `Block.new_owned` groups that storage beneath a child
Scope, without inspecting the fixed-width elements. Arrays use grouped storage.
