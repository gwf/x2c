# Explicit Storage Ownership

Explicit storage ownership lets one container own the storage of others, so
destroying the owner destroys everything it adopted. Use it when nested
containers or graph nodes should share one lifetime, or when a container's
storage moves to another thread.

A `Map` or `Array` has a record, the fixed structure its handle points to,
and backing buffers that hold its entries. Both belong to the scope that was
active when the container was built, called its allocation owner. Growth
replaces buffers under that owner without changing the container handle.

`container.scope()` returns a separate scope for the container's owned
contents. It creates that scope on first use, beneath the container's
allocation owner, `Scope.owner(container)`. The container record and buffers
stay outside it. Ordinary construction, copying, slicing, and insertion do
not create an owned-content scope or adopt referenced values.

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

`cleanup` destroys the container and everything it owns.

`move_to` moves the child's record, backing buffers, and any owned-content
scope together. The insertion stores a reference. These are separate
operations. After the move, destroying the parent destroys the child as well.
Do not schedule another cleanup through an alias to that child. Every pointer
into either destroyed container becomes invalid.

`container.move_to(&destination)` preserves addresses and moves a fixed
number of allocations plus any owned-content scope. The destination
slot acquires a `Scope` if empty. Container cleanup destroys the
owned-content scope, if the container has one, and then frees its buffers and
record. Unadopted referenced values keep their independent owners.

`scope.transfer(destination)` reparents a complete ownership subtree. It
changes a fixed number of ownership links without copying elements or walking
descendants. Destruction visits and frees the adopted storage.

`scope.transfer(NULL)` detaches that subtree from its parent. The subtree
survives destruction of its former parent. Its allocations keep their owning
scopes, so `Scope.owner(pointer)` continues to report them. Reattach with
another transfer, or destroy the detached scope explicitly.

Transfers require exclusive access to the source and affected ownership
lists. Concurrent adoption into a shared parent is unsupported. The source
must not be the active scope or pushed with `Scope.push`. A nonnull
destination must be live and must not be the source or its descendant. The
runtime does not prove graph lifetimes or revoke aliases. Transferring
storage does not grant exclusive access to referenced values.

Converting a container to `Scope` calls `scope()` and can allocate its owned
contents scope. Moving that scope alone moves only those contents; it does
not move the container's record or buffers. Use `move_to` for the complete
container. `scope.parent()` returns the lifetime parent. `Scope.owner(pointer)`
reports an individual managed allocation's owner without acquiring any scope.

A `Block` follows the same rules. It stores fixed-width elements as bytes
and does not know their type. `Block.new` allocates its handle and backing
storage like any other managed container. `Block.scope()` creates an
owned-content scope on first use without inspecting the elements. Arrays use
the same storage.

## Give graph nodes a common owner

Object references may form cycles. The lifetime hierarchy must not.

```x2c
Scope graph = auto Scope.new();
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

Channels carry non-void `Var` values. Ordinary `send` borrows references
without transferring, cloning, or recursively exporting storage. A parent can
send one `Map` to several workers, keep it alive, and refrain from writing
until their reads finish.

`Channel.send_owned` explicitly groups a private container's record, buffers,
and owned contents for transfer. A failed send restores its original owner.
After acceptance, the payload belongs to the `Channel` until a receiver takes
it. On receipt, ordinary `Map` and `Array` storage moves into the receiver's
active `Scope`. A typed container or custom value sent with a scope the
caller prepared keeps that scope, which becomes a child of the receiver's
active `Scope`. Abandoned payloads are destroyed after all `Channel` users
finish. See [Channels](channels.md) for the transport contract.

The developer coordinates reads, writes, and destruction, including allocation
and ownership links. `Scope` operations do not lock those links. A thread must
have exclusive access while allocating, resizing, freeing, or transferring
that storage. Sending successfully does not mean a borrower has finished.

## Canonical values have separate owners

Strings and cons cells belong to canonical pools. Moving a `Map` cannot
extend the lifetime of keys in a private pool. An immutable cons cell can also
reference a mutable object whose lifetime remains independent.

Batch jobs intern into the shared process pool, so those values outlive jobs
and returned `Map` values. [Interned values outlive
workers](contexts-and-threads.md#interned-values-outlive-workers) states that
rule and how to bound the memory it retains.

Explicit `Context.export` is recursive: it exports private
canonical values, preserves container identities, and keeps explicitly adopted
children under their parent when both participate in the same root export.
Reference traversal order does not change that adoption. Exporting only a child
can move it independently. This operation is separate from both `Scope`
transfer and `Channel` transport.

## Where to go next

- [Channels](channels.md) covers owned sends between threads.
