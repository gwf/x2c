# Scopes and Lifetime

x2c has no garbage collector and no reference counting. As in C, you
decide when each allocation is freed. x2c storage is of three kinds:

- Small values stored inside a `Var` allocate nothing.
- Canonical `String` and `List` values belong to an interning pool. By
  default they last until the process exits.
- Mutable storage belongs to a *scope*. A scope frees its allocations
  together.

The [system macros](system-macros.md) provide `$scope()` for a retained
region, `$scope(pointer)` for a temporary destination, and `$auto` for an
explicitly owned local. Classes can also supply early `free` operations.
The [standard library overview](../library/overview.md) links to the detailed
API reference.

## Where each value is stored

A `Var` is eight bytes. Integers that fit, doubles, pointers, `Symbol`s,
`Null`, and `void` are stored in those bytes and allocate nothing. The wide
scalars do not fit alongside a tag: `long`, `unsigned long`, `long long`,
`unsigned long long`, and `long double`. Those go in an immutable box
allocated in the active scope, and the `Var` holds its address:

```x2c
Var small = 42;
long huge = 1L << 60;
Var boxed = huge;
printf("%ld %ld\n", small.integer(), boxed.integer());
```

Both `Var`s are eight bytes; only the second one allocated. A boxed `Var`
is valid while the scope that allocated the box is alive. See
[Values and Var](values.md) for the encoding itself.

A non-empty `String` and every `List` cell built by `cons` are interned:
equal content becomes one canonical pointer. An interning pool holds these
values. By default they stay valid for the rest of the process.
You do not free them, and you do not keep a scope alive to hold them. The
`Pool` calls described below give temporary `String` and `List` structure a
shorter lifetime.

All other storage is mutable and belongs to a scope: `Block`, `Array`,
`Buffer`, wide `Var` boxes, and anything you request with `Scope.malloc`,
`Scope.calloc`, or `Scope.memdup`.

## A scope is a group of allocations

`Scope.retain` opens a new region on the currently active scope slot;
`Scope.release` frees everything allocated inside it. Between them, the
allocation calls go into the retained region:

```x2c
Scope.retain();
char *line = Scope.malloc(32);
snprintf(line, 32, "%d bytes", 32);
puts(line);
Scope.release();
```

Retained regions nest. Each `Scope.retain` must be paired with exactly one
`Scope.release`. Use a nested region to free temporaries before the
surrounding work finishes.

The runtime checks each release against the active slot. An empty retained
region releases normally. An extra release, or a release from a different
pushed slot, raises `<bad-state>` and leaves the active region intact.
A matching `catch` can handle the error. Without one, the default policy
aborts the program.

Storage returned by these calls is managed memory. `Scope.realloc` grows or
shrinks it in place, and `Scope.free` frees it before the release. Most
storage does not need `Scope.free`, because the release frees the whole
region. `Scope.malloc_finalized`
allocates storage that runs a function of your choice when it is reclaimed;
see [attaching a finalizer](#attaching-a-finalizer).

For storage that must outlive the current region, hold a scope in a variable
of type `Scope` and allocate into it directly. `Scope.malloc_in`,
`Scope.calloc_in`, and `Scope.memdup_in` take the slot's address. They do
not make the slot active, so other allocations still go to the active
scope.
`Scope.destroy` ends such a scope:

```x2c
Scope work = Scope.new_named("request");
char *copy = Scope.memdup_in(&work, "payload", 8);
puts(copy);
Scope.destroy(work);
```

`Scope.new_named` copies a diagnostic name. Name every long-lived scope.
At exit the allocator reports each scope that is still alive, by name.
Without the `Scope.destroy` line above, the program prints this on standard
error before it ends:

```text
Scope leak detected:
	live_scopes: 1
	live_allocations: 1
	scope "request": 1 allocations
	live_backing_allocations: 2
```

The last line counts the allocator's own bookkeeping, such as the record
holding that name. `Scope.stats` reports the same counters on demand, so
you can check that a routine leaves no allocations behind.

When several operations should allocate in the same scope without passing a
slot to every call, `Scope.push` makes a slot active and `Scope.pop`
restores the previous one. `Scope.pop` with no push outstanding raises
`<bad-state>`. `Scope.destroy` raises the same cause when the scope is still
in use: the active root, a slot still on the pushed stack, or a scope that a
later `Scope.retain` layered another region on top of. The scope is left
intact. Uncaught, `<bad-state>` aborts the program.

To release a region on every exit from a block, write it as `$scope()` or put
the release in a `defer`. [Errors and
Cleanup](exceptions.md#finally-and-defer) gives the exit rules.

## Bounding temporary canonical Lists

`Pool.open` and `Pool.close` give canonical values a shorter lifetime.
Bracket work with them when it builds many `List` cells and uses none of
them afterwards. `String` and `List` share one canonical pool, so the
bracket bounds both:

```x2c
~
~static Var build_left(int input) {
~  return input - 1;
~}
~
~static Var build_right(int input) {
~  return input + 1;
~}
~
~static int temporary_score(List values) {
~  return values.len();
~}
~
static int evaluate(int input) {
  Pool.open();
  defer Pool.close();

  List temporary = %($input ${build_left(input)} ${build_right(input)});
  return temporary_score(temporary);
}
```

Every `cons` inside the bracket remains canonical. `Pool.close`
reclaims cells created in the innermost pool and forgets their identities.
Calls nest, and every successful `Pool.open` requires one matching
`Pool.close`. Use `defer` when an error or early return can cross the
boundary. `Pool.open_named` gives the bracket a name that appears in `Scope`
diagnostics, and `Pool.current` returns the active pool.

If a `List` must outlive the bracket, call `List.promote` before
`Pool.close`. Promotion is
pointer-stable and recursively preserves nested `List`s, interned `String`
cars, and long `Atom` payloads:

```x2c
~
~static List build_result(void) {
~  return %(result);
~}
~
~static List promoted_result(void) {
Pool.open();
List result = build_result();
result.promote();
Pool.close();
return result;
~}
```

An unpromoted `List` dangles after `Pool.close`. Small amounts of data,
and values needed for the rest of the process, can stay in the default
pool.

### Pools and Contexts

A pool bracket frees only canonical values. A `Context` frees more: one
open `Context` owns a `Scope`, `Error` state, `Match` state,
and, when it is opened isolated, a canonical-value pool of its own.
`Context.open_isolated` calls `Pool.open_named` to get that pool, and
`Context.close` closes it. Use `Pool.open` when only canonical `String` and
`List` structure must be freed. Use a `Context` when the `Scope`, the
`Error` state, and the `Match` state must also end with it. See
[Contexts and Threads](contexts-and-threads.md).

## Moving a value out of a scope

When a region computes one result that must outlive it, use `Scope.move`.
It relinks a single allocation onto another scope without copying
it. The pointer does not change:

```x2c
Scope keep = Scope.new_named("results");
Scope.retain();
char *text = Scope.memdup("survivor", 9);
Scope.move(text, &keep);
Scope.release();
puts(text);
Scope.destroy(keep);
```

A `String` or a `List` needs no move, because canonical values
outlive the scope that was active when they were built.

## Attaching a finalizer

A record that holds a resource outside the allocator, such as a handle
from a C library, can release it when the record is reclaimed.
`Scope.malloc_finalized` takes the function to run:

```x2c
~#include <stdio.h>
~typedef struct feed_parser feed_parser;
~static feed_parser *feed_open(void) { return (feed_parser *) 1; }
~static void feed_close(feed_parser *parser) { (void) parser; }
typedef struct Feed { feed_parser *native; } *Feed;

static void _feed_drop(void *ptr) {
  Feed feed = ptr;
  if (feed.native) feed_close(feed.native);
  feed.native = NULL;
}

Feed Feed.open(void) {
  Feed feed = Scope.malloc_finalized(sizeof(struct Feed), _feed_drop);
  feed.native = feed_open();
  return feed;
}
~int main(void) {
~  Scope.retain();
~  Feed feed = Feed.open();
~  Scope.release();
~  return 0;
~}
```

The finalizer runs exactly once with the record's pointer: on `Scope.free`,
on a `Scope.realloc` to size zero, when the owning scope is released or
destroyed, or when shutdown releases its owning root region. A detached
`Scope` that is still live at shutdown is reported as a leak, and its
finalizers do not run. The finalizer follows the record through `Scope.move`,
and `Scope.realloc` keeps it and passes the resized pointer.
Records are reclaimed most recent first, so a finalizer can still read older
records in the same scope.

A finalizer has three rules. The record is already unlinked when its
finalizer runs, so the finalizer must not free or move the record itself.
It must not raise. It may allocate into other scopes, and into the scope
being destroyed only for scratch that the same destruction reclaims.

A wrapper can also release the native handle early. If its own `free`
method clears the native field, the finalizer has nothing left to do.

## `Block` and `Buffer`

`Block` is the fixed-width storage primitive. A `Block` owns a contiguous run
of elements of one width, chosen at construction, and tracks their length and
capacity. Its backing store comes from the active scope, so a
`Block` created inside a retained region is freed when that region ends,
even if you never call `Block.free`.

```x2c
Block ids = Block.new(sizeof(int));
for (int i = 0; i < 4; i++) ids.push(&i);
int *values = ids.bytes;
printf("%zu of %zu, last %d\n", ids.len(), ids.capacity(), values[3]);
ids.free();
```

The example reads `values` after the last push. Growth reallocates and
moves the `bytes` pointer, so a copy taken before an append can be stale
afterwards. The `Block` handle stays valid across growth, so pass the handle
around. If you work
through the raw `Bytes` pointer, use the forms that return the pointer,
`Bytes.append` and `Bytes.reserve`, or recover the handle with `Bytes.block`.
`Block.append` and `Block.reserve` raise `<bad-arg>` on a bad argument and
leave the storage unchanged. Capacity and allocation failures raise
`<size-limit>` and `<alloc-fail>`. None of these raises returns to the
call. `Array` is a `Block` whose element width is
`sizeof(Var)`; see [Strings, Lists, Arrays, and Maps](collections.md).

`Buffer` is a text builder built on `Block`. It rejects an embedded NUL,
because it builds canonical `String`s, and it tracks the byte position and
leading indentation of the current line for `push`, `pop`, `indent`, and
`newline_indent`. Use `Block` for checked storage of some element type, and
`Buffer` for assembling text.

```x2c
String text;
$scope() {
  Buffer out = $auto(Buffer.new(0));
  out.write("case ").printf("%d", 7).write(":").newline_indent();
  text = out;
}
puts(text);
```

The `String` destination calls `Buffer.str`, which interns the accumulated
text, so `text` is canonical. It stays valid after the `Buffer` cleanup and
the region release free every byte the builder used. Most x2c code follows
this pattern: mutable storage inside a region, a canonical result outside
it.

## Choosing when to free storage

Free storage when the work that needs it is finished: a request has ended, a
file has been parsed, or temporary values have been combined into one result.
Do not wrap a scope around canonical values that already outlive it. That
scope frees nothing and adds a release you can forget.

A scope does not prevent dangling pointers:

```x2c
static char *leaked_label(void) {
  Scope.retain();
  char *label = Scope.memdup("temporary", 10);
  Scope.release();
  return label;
}
```

`Scope.release` freed that storage. The returned pointer is dangling, and
every later use of it is undefined behavior. A use can read stale bytes,
corrupt the allocator, or seem to work for a while.
`Scope`s make lifetimes explicit and cheap to end. They do not check at
runtime that a value has stopped being used. The same applies to a boxed wide
`Var`: if you keep the `Var`, you must keep the scope that allocated the box.

The compiler warns about this example because the escape is visible in the
source: `label` is allocated between a retain and its release and read after
it.

To avoid dangling pointers:

- Return a canonical value (a `String`, a `List`, or a `Symbol`) when a
  result must cross a scope boundary.
- Use `Scope.move` when a mutable allocation must outlive its region.
- When unsure, let the caller create the scope and pass the slot down. The
  lifetime is then chosen where the caller can see it.

## Lifetime warnings

Every allocation in this chapter belongs to a region: a part of the program
that owns storage and ends at a known point. Regions are `$scope()` blocks,
`Scope.retain` and `Scope.release` pairs, `$scope(&slot)` pushes, `$auto`
locals, `Scope` locals that `Scope.destroy` ends, `Pool.open` brackets, and
the function's own locals and parameters.

The rule is: a value allocated inside a region must not be reachable after
that region ends. `Scope.move`, `Context.export`, `List.promote`, and
returning a canonical value all follow the rule, because each gives the
storage an owner that outlives the region.

Translation warns when code breaks the rule. The warning includes the
value's name and the way it leaves, and a note gives the line that opened
the region. A value leaves when it is:

- returned;
- assigned to a local declared outside the region;
- stored through a parameter, through an unknown pointer, or into a static;
- stored into an object that belongs to another region;
- held by a List cell, as in `cons(a, rest)` or `%($a)`, or captured by a
  closure that leaves;
- handed to a function in the same unit, or to a runtime operation such as
  `Array.push`, that stores it in one of those places.

The address of a local or parameter is reported the same way when it
outlives the function. Two more warnings come from the same check.
`after-free` reports a local read after `Scope.free`, `Scope.realloc`, or
`Array.list_free` consumed it. `bad-free` reports `Scope.free` or
`Scope.realloc` given a literal, a local's address, or other storage no
`Scope` allocator returned. In a `meta` function, each of these findings is
an error; see [Meta Functions](meta-functions.md).

Code that follows the patterns in this chapter compiles without warnings:

```x2c
~typedef struct Entry { int id; } *Entry;
~int main(void) { Scope keep = NULL; Scope.push(&keep); Entry e = adopt(&keep);
~  Scope.pop(); Scope.destroy(keep); return e != NULL && !label().len(); }
static Entry adopt(Scope *keep) {
  $scope() {
    Entry entry = Scope.calloc(1, sizeof(struct Entry));
    Scope.move(entry, keep);
    return entry;
  }
  return NULL;
}

static String label(void) {
  $scope() {
    Buffer out = Buffer.new(0);
    out.write("ready");
    return out;
  }
  return NULL;
}
```

`Scope.move` moves the storage into a scope the caller owns. The `String`
return destination calls `Buffer.str`, which produces a canonical `String`
that its pool owns.

A warning does not stop translation. When a warning describes a lifetime
you arranged another way, you may keep the code. The warnings cover one
lexical pattern. [The Region Model](regions.md) lists what they do not
cover, the exemptions, and how the check works. To observe a dangling read
at run time, link the program against `libx2c.a` and compile with
`cc -fsanitize=address,undefined`.

## Ordinary C storage still works

x2c is a superset of C, and it does not change automatic or static storage.
Locals, arrays, and `struct` values still live on the stack and end at the
closing brace; `static` and file-scope objects still last for the program.
`Scope`s govern only what you explicitly allocate through them.

Many library types store their state in memory the caller provides, so a
loop can iterate without calling the allocator:

```x2c
~List items = %(1 2 3);
struct Iter storage;
Iter walk = items.iter(&storage);
Var value;
while (walk.try_next(value)) printf("%ld\n", value.integer());
```

`storage` is an automatic variable. Nothing here needs freeing or a scope;
see [Iteration](iteration.md) for the protocol. An automatic local or
parameter you assigned directly keeps its value when a `raise` transfers
control to a `catch`. Your source needs no optimization-specific qualifiers
for that.

## Where to look next

Read the [standard library overview](../library/overview.md) and the
[language reference](../reference/language.md) for the rules.
[Idioms](idioms.md) shows how scopes combine with other x2c features.
[The Region Model](regions.md) covers the lifetime check: its guarantees,
its limits, and how it compares with the checks in other languages.
