# Scopes and Lifetime

C makes you answer one question about every allocation: who frees this?
x2c does not take that question away. There is no garbage collector and no
reference counting. x2c gives you a place to put the answer. A *scope* holds
a group of allocations and frees them together, and some values keep their
storage for the life of the process, so not every value needs a matching
free.

The [standard library overview](../library/overview.md) links to the detailed
API reference.

## What actually owns the storage

A `Var` is eight bytes. Integers that fit, doubles, pointers, `Symbol`s,
`Null`, and `void` are stored in those bytes and allocate nothing. The wide
scalars do not fit alongside a tag: `long`, `unsigned long`, `long long`,
`unsigned long long`, and `long double`. Those go in an immutable box that
the allocator owns, and the `Var` holds its address:

```x2c
Var small = 42;
long huge = 1L << 60;
Var boxed = huge;
printf("%ld %ld\n", small.integer(), boxed.integer());
```

Both `Var`s are eight bytes; only the second one allocated. A boxed `Var`
is valid while the scope that allocated the box is alive. See
[Values and Var](values.md) for the encoding itself.

Canonical values are the other case. A non-empty `String` and every `List` cell
built by `cons` are interned: equal content becomes one canonical pointer. By
default those values stay valid for the rest of the process. You do not free
them, and you do not have to keep a scope alive to hold them. They are held in
canonical interning pools. The `List` pool calls described below give temporary
`List` structure a shorter lifetime.

That leaves mutable storage: `Block`, `Array`, `Buffer`, wide `Var` boxes,
and anything you request with `Scope.malloc`, `Scope.calloc`, or
`Scope.memdup`. All of it belongs to a scope.

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
`Scope.release`, and a nested region is the normal way to say "these
temporaries are freed before the surrounding work finishes."

The active slot tracks the match. An empty retained region still releases
normally, but an extra release, or a release from a different pushed slot,
aborts instead of destroying the surrounding process root.

Storage returned by these calls is managed memory. `Scope.realloc` grows or
shrinks it in place, and `Scope.free` ends its life early without waiting
for the release. `Scope.free` shortens a lifetime. Most storage does not
need it, because the release frees the region.

For work with a longer life, hold a scope in a variable of type `Scope` and
allocate into it directly. `Scope.malloc_in`, `Scope.calloc_in`, and
`Scope.memdup_in` take the slot's address and leave the active scope alone,
so intervening allocations cannot be redirected by accident.
`Scope.destroy` ends such a scope:

```x2c
Scope work = Scope.new_named("request");
char *copy = Scope.memdup_in(&work, "payload", 8);
puts(copy);
Scope.destroy(work);
```

`Scope.new_named` copies a diagnostic name. Give one to anything
long-lived. At exit the allocator reports what is still alive, and the name
tells you which scope. Drop the `Scope.destroy` line
above and the program prints this on standard error before it ends:

```text
Scope leak detected:
	live_scopes: 1
	live_allocations: 1
	scope "forgotten": 1 allocations
	live_backing_allocations: 2
```

The last line counts the allocator's own bookkeeping, such as the record
holding that name. `Scope.stats` reports the same counters on demand, so
you can check that a routine leaves no allocations behind.

When several operations should allocate in the same scope without passing a
slot to every call, `Scope.push` makes a slot active and `Scope.pop`
restores the previous one. `Scope.destroy` refuses a scope that is still in
use: the active root, a slot still on the pushed stack, or a region with
another region attached below it. Those cases print a diagnostic and abort
instead of corrupting the allocation lists. A mismatched push/pop or a
double destroy aborts with a diagnostic.

## Bounding temporary canonical Lists

Canonical identity does not require every `List` in a batch or request to stay
alive until process exit. When a body of work builds substantial `List`
structure and no `List` from that work escapes, bracket it with the `List` pool
calls:

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
  List.pool_retain();
  defer List.pool_release();

  List temporary = %($input ${build_left(input)} ${build_right(input)});
  return temporary_score(temporary);
}
```

Every `cons` inside the bracket remains canonical. `List.pool_release`
reclaims cells created in the innermost pool and forgets their identities.
Calls nest, and every successful `List.pool_retain` requires one matching
release. Use `defer` when an error or early return can cross the boundary.

If a `List` must survive, call `List.promote` before release. Promotion is
pointer-stable and recursively preserves nested `List`s, interned `String`
cars, and long `Atom` payloads:

```x2c
~
~static List build_result(void) {
~  return %(result);
~}
~
~static List promoted_result(void) {
List.pool_retain();
List result = build_result();
result.promote();
List.pool_release();
return result;
~}
```

An unpromoted `List` dangles after the release. Use these calls when a task
creates substantial temporary `List` structure. Small amounts of data and
values needed for the rest of the process can stay in the default pool.

## Moving a value out of a scope

Sometimes a temporary region computes one result that has to survive it.
`Scope.move` relinks a single allocation onto another scope without copying
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

Use this instead of letting a pointer escape. A `String` or a `List` needs
no move; canonical values outlive the scope that was active when they were
built.

## `Block` and `Buffer`

`Block` is the fixed-width storage primitive. A `Block` owns a contiguous run
of elements of one width, chosen at construction, and tracks their length and
capacity. Its backing store comes from the active scope, so a
`Block` created inside a retained region dies with that region even if you
never call `Block.free`.

```x2c
Block ids = Block.new(sizeof(int));
for (int i = 0; i < 4; i++) ids.push(&i);
int *values = ids.bytes;
printf("%zu of %zu, last %d\n", ids.len(), ids.capacity(), values[3]);
ids.free();
```

Look at where `values` is read. Growth reallocates, so the `bytes` pointer
moves; a copy of it taken before an append can be stale afterwards. The `Block`
handle stays valid across growth, so pass the handle around. If you work
through the raw `Bytes` pointer, use the forms that hand the pointer back,
`Bytes.append` and `Bytes.reserve`, or recover the handle with `Bytes.block`.
`Block.append` and `Block.reserve` raise `<bad-arg>` on a bad argument; the
storage is unchanged and the `raise` does not return to the call. Capacity and
allocation failures raise `<size-limit>` and `<alloc-fail>`, which do not
return to the raising call. `Array` is a `Block` whose element width is
`sizeof(Var)`; see [Strings, Lists, Arrays, and Maps](collections.md).

`Buffer` is a text builder layered on `Block`. It rejects an embedded NUL,
because it builds canonical `String`s, and it tracks the byte position and
leading indentation of the current line for `push`, `pop`, `indent`, and
`newline_indent`. Use `Block` for checked storage of some element type, and
`Buffer` for assembling text.

```x2c
Scope.retain();
Buffer out = Buffer.new(0);
out.write("case ").printf("%d", 7).write(":").newline_indent();
String text = out.str();
out.free();
Scope.release();
puts(text);
```

`Buffer.str` interns the accumulated text, so `text` is canonical. It is
still valid after the `Buffer.free` and the `Scope.release` that disposed of
every byte the builder used. Most x2c code is written this way: mutable
storage in a scope, canonical result outside it.

## `defer` for cleanup

`defer statement` schedules a statement for the exit of the enclosing block.
It runs on normal exit, on `return`, on `break`, and when an `Error`
passes through; multiple `defer` statements run last-in, first-out.

```x2c
FILE *log = fopen("/dev/null", "a");
if (log) {
  defer fclose(log);
  fprintf(log, "started\n");
}
```

Keep the deferred statement small. A `defer` should release something the
block owns, and it puts the release next to the acquisition, where a reader
can check them against each other.

Do not use `defer` to swallow failures. Let `Error`s propagate and keep
expected absence, exhaustion, and parse outcomes in the return value. The
interaction with `raise`, `try`, filtered `catch`, and `finally` is described
in [Errors and Cleanup](exceptions.md), and the exact statement rules in [the
language reference](../reference/language.md).

## Choosing when to free storage

Free storage when the work that needs it is finished: a request has ended, a
file has been parsed, or temporary values have been combined into one result. A
scope wrapped around canonical values that already outlive it buys nothing and
adds a release you can forget.

A scope does not prevent dangling pointers. This translates without a
diagnostic:

```x2c
static char *leaked_label(void) {
  Scope.retain();
  char *label = Scope.memdup("temporary", 10);
  Scope.release();
  return label;
}
```

`Scope.release` freed that storage. The returned pointer is dangling, and
every use of it afterwards is undefined behavior: reading stale bytes,
corrupting the allocator, or appearing to work until it does not.
`Scope`s make lifetimes explicit and cheap to end. They do not check that a
value has stopped being used. The same applies to a boxed wide `Var`: if you
keep the `Var`, you must keep the scope that allocated the box.

Three habits keep this out of your code. Return a canonical value, a
`String`, a `List`, or a `Symbol`, when a result must cross a scope boundary.
Use `Scope.move` when a mutable allocation has to survive. When in doubt,
let the caller create the scope and pass the slot down, so the lifetime is
visible where it was chosen.

## Ordinary C storage still works

x2c is a superset of C, and it does not change automatic or static storage.
Locals, arrays, and `struct` values still live on the stack and die at the
closing brace; `static` and file-scope objects still last for the program.
`Scope`s govern only what you explicitly allocate through them.

Many library types take the address of caller-owned state instead of
allocating, so a loop can iterate without touching the allocator:

```x2c
~List items = %(1 2 3);
struct Iter storage;
Iter walk = items.iter(&storage);
Var value;
while (walk.try_next(&value)) printf("%ld\n", value.integer());
```

`storage` is an automatic variable. Nothing here needs freeing or a scope;
see [Iteration](iteration.md) for the protocol. An automatic local or
parameter you assigned directly keeps its value when an `Error` carries
control away, and your source needs no optimization-specific qualifiers for
that.

## Where to look next

Read the [standard library overview](../library/overview.md) and the
[language reference](../reference/language.md) for the rules.
[Idioms](idioms.md) shows how scopes combine with other x2c features.
