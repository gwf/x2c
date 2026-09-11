# Classes and System Macros

The compiler ships a small set of macros for declaring ordinary types and
managing block lifetimes. They use the same methods, protocols, allocation,
and `defer` rules as handwritten x2c. Their definitions are available without
an import; runtime operations still require their ordinary declarations,
usually supplied by `#include "x2c.x"`.

| Facility | Availability | Purpose |
| --- | --- | --- |
| `class` | Shipped keyword alias | Declare a type and its applicable defaults |
| `$scope` | Shipped decorator | Retain a region or select a Scope destination |
| `$let` | Shipped decorator | Temporarily replace one captured storage location |
| `$lock` | Shipped decorator | Hold a Mutex while a statement runs |
| `$auto` | Shipped expression macro | Attach cleanup to an initialized local |
| `foreach` | Shipped keyword alias | Traverse through the ordinary Iter protocol |
| `with` | Contextual grammar | Substitute a source expression within a block |
| Project macros | Explicit import | Supply project-specific syntax and policy |

Only `class` and `foreach` have bare keyword aliases. Use the `$` spelling for
`$scope`, `$let`, `$lock`, and `$auto`. For authoring your own macros, continue
with [Compile-time Macros](macros.md).

## Classes are ordinary named types

Use `class` to give a named type the supporting operations you would otherwise
write yourself: construction, conversion to and from `Var`, comparison and
hashing, and readable output. These operations let your values work with
generic containers and protocol-based code. You choose the representation;
the class supplies applicable defaults, which explicit methods can replace.

For example, a small value record can be constructed, used as a Map key, and
printed without writing its constructor, converters, hash, or printer:

```x2c
class Point { int x; int y; };
~int main(void) {
Point point = Point.new(3, 4);
Map labels = $auto(%{});
labels[point] = "origin";
printf("%s: %s\n", point.repr(), labels[Point.new(3, 4)].str());
~  return 0;
~}
```

### Which methods does a class supply?

For a class named `T`, the possible defaults are listed below. A new class
means one declaring a representation, rather than an alias of an existing
named type. Defaults depend on that representation; not every class generates
every method.

| Method | Default behavior and applicability |
| --- | --- |
| `T.new` | Constructs a scalar, value record, or pointer object. An alias forwards the applicable constructor of its underlying named type. Some layouts require an explicit constructor or `init`, as described below. |
| `T.free` | Releases a new pointer class's Scope allocation early. It does not free fields recursively. |
| `T.cleanup` | Calls the selected `free` for a new pointer class and supplies `Cleanup` participation for `$auto`. |
| `T.var` | Converts a new class to `Var`: a scalar uses its underlying representation, a pointer boxes identity, and a value record boxes a Scope-owned copy. |
| `Var.t` | Converts a `Var` back to the new class; for example, `Var.point` for `Point`. |
| `T.equal`, `T.hash` | Use identity for new pointer classes and fields for supported flat value records. Other value records require compatible explicit methods. |
| `T.str`, `T.repr` | Provide string output for new pointer and record classes. Pointer `str` shows identity; value-record `str` delegates to `repr`. Record `repr` shows fields. |
| `T.write_str`, `T.write_repr` | Write the corresponding output into a Buffer for new pointer and record classes. |

Scalar classes retain their underlying type's comparison, hashing, and output
operations. Aliases of existing named types inherit supporting operations,
including cleanup, rather than generating a second implementation. Explicit
methods replace applicable defaults; the output methods can be customized
independently, as described under [Boxing and readable output](#boxing-and-readable-output).

`init` is **not generated**. Some constructors require you to supply it.
Generated cleanup releases the object's allocation; ownership of resources
stored in its fields requires your own cleanup code.

### Choose a representation

The name comes first. The remaining declaration specifies its representation:

```x2c
class Count int;
class IntPointer int *;
class ValuePointer Var *;
class Values Array;
class Point { int x; int y; };
class HeapPoint struct { int x; int y; } *;
~int main(void) {
~  Point point = Point.new(3, 4);
~  return point.x == 3 && point.y == 4 ? 0 : 1;
~}
```

`Point` is a value aggregate; the short braces abbreviate a struct definition.
`HeapPoint` explicitly names a pointer representation. A value may live in a
local, a field, an array, or allocated storage. `Values` follows the existing
Array type chain and constructor; it does not acquire a second allocation
layout. A forward declaration such as `class Point;` reserves the identity
until its visible definition supplies the representation.

### Construction and early release

A scalar class constructor accepts its scalar value. A class pointing to an
eligible value allocates and copies one pointee. A flat record of supported
value fields accepts positional arguments in field order:

```x2c
class Point { int x; int y; };
class HeapPoint struct { int x; int y; } *;
~int main(void) {
Point value = Point.new(3, 4);
HeapPoint object = HeapPoint.new(3, 4);
printf("%d %d\n", value.x, object.y);
object.free();
~  return 0;
~}
```

The heap constructor allocates in the current Scope. Its generated `free`
allows early release; otherwise the Scope reclaims that allocation. Generated
cleanup does not recursively free fields and is not a Scope finalizer.
Positional fields include native numeric values and enums, Symbol, Var/Atom,
String, List, and their aliases. Var slots are shallow copies.

A record containing a mutable handle such as Array, Map, Iter, or another
heap class instead gets a no-argument constructor that zeroes the object and
calls its required `init` method. Nested records and arrays also use this
branch. Heap initialization receives the handle; value initialization receives
its address:

```x2c
class History struct { int count; Array items; } *;
void History.init(History self) {
  self.items = %[];
}
void History.free(History self) {
  self.items.free();
  Scope.free(self);
}
~int main(void) {
History history = $auto(History.new());
history.items.push(42);
~  return history.count == 0 ? 0 : 1;
~}
```

An explicit `new` replaces the default and may take different arguments. It
also replaces the default constructor's obligation to call `init`. Explicit
methods can appear later in the owning source; only the selected default or
explicit method is emitted. Two ordinary definitions still conflict, and an
importing consumer cannot replace a provider's defaults.

Derived classes forward an existing parent's constructor with its arguments
and retain parent cleanup. For example, Array's constructor still chooses
storage for Var elements. A variadic parent requires an explicit constructor
when its arguments cannot be forwarded by an existing facility. A custom
constructor that changes a heap class's allocation contract must also supply
compatible cleanup. A failed `init` returns no object; it does not roll back
arbitrary side effects inside the initializer.

### Boxing and readable output

Heap classes box the existing object identity. A copied value aggregate boxes
a Scope-owned copy and unboxes by value. The box never points at the original
local's stack storage:

```x2c
class Point { int x; int y; };
~int main(void) {
Point point = Point.new(3, 4);
Var first = point, second = Point.new(3, 4);
Map labels = $auto(%{});
labels[first] = "origin";
printf("%s\n", labels[second].str());
~  return labels.contains(second) ? 0 : 1;
~}
```

Supported value fields receive compatible field-based equality and hashing,
so independently boxed equal values work as the same Map key. Opaque layouts
require explicit compatible methods. Equal values must have equal hashes.
Heap classes retain identity equality and hashing.

`str` and `repr` are independently replaceable. A heap object's default `str`
prints pointer identity. A new value aggregate's `str` delegates to `repr`;
scalar and derived value classes retain their parent's printing. Record
`repr` visits fields in declaration order, using readable value output and an
address fallback for opaque fields. It does not dereference unknown pointers.

Nested Array, Map, List, and class rendering shares an active rendering path.
A repeated identity on that path prints its pointer form; a repeated reference
outside the active path prints fully again. Custom printers that recurse
outside these operations must manage their own recursion. Readable output
containing addresses is not a serialization format.

Class boxing uses the existing Var descriptor registry: it has 32 custom rows
and freezes when worker startup freezes registration. Class tags derive from
the canonical source file and full name, keeping private classes in different
files distinct. Tags use deterministic compact spellings, while diagnostics
retain the full name.
Registration failure and tag collisions are errors; classes do not remove
these runtime limits.

## Retain or select a Scope

Without an argument, `$scope()` retains one region around the following
statement. Its expansion deliberately keeps the body inside the deferred
release:

```x2c
~int main(void) {
$scope() { Array values = %[]; values.push(1); }
~  return 0;
~}
```

The block placement is equivalent to:

```x2c
~int main(void) {
{
  Scope.retain();
  {
    defer Scope.release();
    { Array values = %[]; values.push(1); }
  }
}
~  return 0;
~}
```

Place the decorator around a loop for one region, or around its body for one
region per iteration. No hidden loop changes the meaning of `break` or
`continue`:

```x2c
~int main(void) {
$scope() for (int i = 0; i < 3; i++) { Scope.malloc(8); }
for (int i = 0; i < 3; i++) $scope() { Scope.malloc(8); }
~  return 0;
~}
```

With one Scope-pointer argument, `$scope` evaluates the argument once, pushes
that destination, and restores the previous destination on exit:

```x2c
~int main(void) {
Scope destination = $auto(Scope.new());
$scope(&destination) { Scope.malloc(8); }
~  return 0;
~}
```

The corresponding body placement is:

```x2c
~int main(void) {
~Scope destination = $auto(Scope.new());
{
  Scope.push(&destination);
  {
    defer Scope.pop();
    { Scope.malloc(8); }
  }
}
~  return 0;
~}
```

`pop` restores the destination; it does not release the selected Scope.
`return` and error transfer use the ordinary defer boundaries in both forms.

## Temporarily change one location

`$let(place, value)` captures the address of an assignable place, saves its
previous value, installs the new value, and restores that same storage on
exit. Both locating the place and computing the new value happen once:

```x2c
~int main(void) {
int levels[2] = { 1, 2 }, index = 0;
$let(levels[index++], 7) {
  printf("%d\n", levels[0]);
  index = 1;
}
~  return levels[0] == 1 && levels[1] == 2 ? 0 : 1;
~}
```

Changing `index` does not redirect restoration. The place's storage must
outlive the body. Ordinary typing rejects const assignment or taking a
bitfield's address. By comparison, `with` substitutes its source expression
on each use and creates no temporary; it is not a saved-value binding.

## Hold a Mutex

`$lock(mutex)` evaluates one Mutex expression, acquires it, and defers unlock
until the decorated statement exits. Unlock is registered only after lock
succeeds:

```x2c
~int main(void) {
Mutex mutex = $auto(Mutex.new());
$lock(mutex) { printf("held\n"); }
~  return 0;
~}
```

This preserves Mutex's error behavior. It does not replace descriptor locks,
file-stream locks, or a project's conditional-acquisition policy. Logger's
private synchronized decorator keeps its own policy.

## Clean up an initialized local

`$auto` is the complete initializer of an ordinary local declaration:

```x2c
~int main(void) {
Array items = $auto(%[]);
Buffer text = $auto(Buffer.new(0));
items.push(42);
text.write(items.repr());
printf("%s\n", text.str());
~  return 0;
~}
```

Each declaration lowers to the original initialization followed by
`defer local.cleanup()` in the same enclosing block. The initializer runs
once, and cleanup is registered only after it succeeds. Compound declarations
preserve acquisition order, with each successful acquisition protected before
the next initializer runs. Cleanup runs in reverse registration order.

`Cleanup(T)` declares `void T.cleanup(T)`. Participation is explicit, follows
the existing typedef/protocol ancestry, and keeps ordinary method precedence:

| Types | Cleanup action |
| --- | --- |
| Block, Bytes, Array, typed Arrays | Release the backing Block allocation |
| Map and typed Maps | Release the record and both backing Blocks |
| Buffer, Mutex | Their existing `free` operation |
| File, Context | Their existing `close` operation |
| Scope, Lisp | Their existing `destroy` operation |
| Generated heap classes | Their selected `free` operation |
| Other types | An explicitly adopted compatible cleanup method |

The deferred call observes the binding at cleanup time. For example, assigning
a new Array to an `$auto` local does not free the earlier Array:

```x2c
~int main(void) {
Array current = $auto(%[]);
Array earlier = current;
current = %[];
earlier.free();
~  return 0;
~}
```

The second Array is cleaned up at block exit. Returning or storing an alias
does not cancel cleanup; the caller must choose an appropriate lifetime.
There is no move or recursive ownership system. Var itself has no owning
cleanup contract, and Pool's `free` operation requires a separate allocation
argument.

Only an initialized automatic local that is a compound-statement item accepts
`$auto`. Parentheses and macro construction preserve that position. Static or
threaded storage, fields, assignment, returns, call arguments, for-header
declarations, and wrappers nested inside arithmetic or conditionals do not
supply this enclosing-block lifetime.

## A complete resource-using program

This program collects line lengths from a file. The retained region owns all
allocations; the managed locals close the file and release the mutable history
before that region ends. The History method makes ownership of its Array
explicit.

```x2c
class History struct { Array lengths; } *;

void History.init(History self) {
  self.lengths = %[];
}

void History.free(History self) {
  self.lengths.free();
  Scope.free(self);
}

int main(int argc, char **argv) {
  if (argc != 2) return 0;
  $scope() {
    History history = $auto(History.new());
    File input = $auto(File.open(argv[1], "r"));
    for (String line; (line = input.readline()) != NULL; )
      history.lengths.push(line.len());
    printf("%s\n", history.lengths.repr());
  }
  return 0;
}
```
