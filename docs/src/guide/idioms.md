# Programming Idioms

Use the shipped [classes and system macros](system-macros.md) where they
express a complete constructor or block lifetime: `$auto` for an owned local,
`$scope` for a region, `$let` for saved storage, and `$lock` for a Mutex.

These idioms combine the features introduced in the guide.

## Keep native values native

Use C scalar, pointer, struct, union, and enum types when the value's type is
known at compile time. Use `Var` where the value is dynamic: heterogeneous
collection elements, dynamic arithmetic, generic callbacks, or interchange
data.

## Use values for local state and references for updates

Declare a record as a value when it belongs to one operation and needs no
retained identity. A method that updates that record takes a reference:

```x2c
class Counter { int value; };

static void Counter.step(Counter &c, int amount) => c.value += amount;

int main(void) {
  Counter counter = Counter.new(2);
  counter.step(3);
  Counter copy = counter;
  copy.step(1);
  printf("%d %d\n", counter.value, copy.value);
  return 0;
}
```

```text
5 6
```

`counter` holds the record directly; constructing it needs no allocation for
the record. `step` changes the caller's object, and its call needs no `&` or
explicit dereference. Copying the record creates a separate Counter. Pass a
small record by value when reading a copy is the intended contract.

`class` adds constructors, boxing, and other methods to the declared
representation. Use an ordinary value typedef for a context that
does not need that bundle. In either case, pass its mutable state through
`T &` helpers instead of introducing a pointer typedef and a second local
whose only purpose is taking the context's address.

A trailing `*` selects a pointer representation:
`class Node { int value; } *;`. Its bare `Node` name is already a pointer,
and its methods take that handle. Choose it when shared or retained identity
is useful. The spelling `struct` before the braces is optional; short braces
work for both representations. See
[Choose a representation](system-macros.md#choose-a-representation).

Representation and storage location are separate choices. A value can be a
local, a field, an array element, or part of allocated storage. A reference
borrows one live caller object for a call; it does not own or extend its
lifetime. Record copies are shallow: a copied Array, Buffer, or pointer field
still reaches the same backing object. Keep cleanup with the owner of those
resources, including when the record itself is a value.

An active transaction or builder has one owner even when its record is a
value. Copying it shares the saved maps or backing arrays; the copy is not a
second transaction or an independently owned builder. Borrow the original
through reference methods. `SymTxn` and `MachineBuilder` use this pattern;
use their begin or `new` operation to prepare active storage. A `Job` keeps a
shared handle because its recorded run and Scope finalizer must reach the
same job, while its launch options live directly inside that job.

## Borrow required and optional outputs

Use a reference when a result must update a caller's existing object:

```x2c
static int take(int &remaining, int &item) {
  if (!remaining) return 0;
  remaining--;
  item = remaining;
  return 1;
}

int main(void) {
  int remaining = 2, item;
  while (take(remaining, item)) printf("%d\n", item);
  return 0;
}
```

```text
1
0
```

Use `T &?` when supplying the object is optional, and test its presence before
using it. A required reference takes an addressable value, not a pointer or
NULL. An existing pointer `p` supplies its object as `*p`. Keep pointers for
buffers and arrays, retained addresses, nullable links, native signatures,
and callback state. A nested context that borrows its mutable parent needs a
pointer field so both contexts reach the same parent. See
[Reference parameters](../reference/language.md#reference-parameters).

## Adopt a protocol for one real contract

Adopt a protocol when a concrete type should support a shared interface.
Define the required conversions beside the type. Similar method names are
not enough: the operations must have the meanings the protocol requires.

Implement a member directly when the type already provides that operation.
Use a base default when every participant value converts to a valid base
value and the forwarded operation has the required meaning. Before extending
a protocol, use `--dump-conformance` to check its existing participants.

## Box private records through `Var(T)`

A type does not need to become public because internal code stores it in a
`Var`, `List`, `Array`, or `Map`. Put both conversions beside the private type
and adopt the public `Var(T)` protocol there. Typed arguments, results,
assignments, and initializers then box and unbox it without repeated casts.

Keep an explicit `value is Type` check when a `Var` came from mixed or
untrusted data. Protocol adoption supplies the conversions; it does not check
the dynamic type of an arbitrary value.

## Make macro calls easier to read than their expansions

A macro should replace repeated source with a call whose meaning is obvious:

```x2c
~
macro Stmt $sample.guard(Expr $condition) {
  if (!$condition) return 0;
}
~
~int positive(int value) {
~  $sample.guard(value > 0);
~  return value;
~}
```

Prefer a function when the job is runtime computation. Prefer direct source
when a macro needs substantial compile-time Lisp or AST manipulation to save a
few tokens. The macro body, imports, and generated declarations are part of the
maintenance cost.

## Write generated code as the code it builds

A `meta` function that returns code should show that code. A quotation
shows the C that will land; a `%(...)` List of node tags hides it. Choose the
first row that fits. [Meta Functions](meta-functions.md#quoting-code-with-)
explains each form with examples.

| To build | Write |
| --- | --- |
| Code with one shape at several sites | a named macro, applied from the function as in [source templates](meta-functions.md#source-templates-from-meta-functions) |
| Code that one function builds | a quotation: `$!( expression )`, `$!{ statements }`, or `$!Unit{ ... }` |
| Code that uses a field, an element, or a call result | a [`${expression}` hole](meta-functions.md#holes-that-name-an-expression), evaluated once where the quotation is written |
| Code in which separate quotations share one name | `List name = x2c_ident("total");`, then `$name` in each quotation |
| An expression whose type is read before it lands | a [typed quotation](meta-functions.md#code-that-knows-its-type), such as `$!double{ $value * 2 }` |
| Code the function inspects before it returns | a typed quotation, which builds the code where it is written |
| A pattern, a data row, or a form with no source spelling | a `%(...)` List |

A name that a quotation declares is private to it, so another quotation
cannot refer to it. An `x2c_ident` hole declares and refers to one exact
name.

When a `meta` function builds one statement, the macro can hand it the work
in one line. Write the `Stmt` macro with an arrow body and return the
statement itself:

```x2c
#include "meta.x"
meta static List traced(List body) =>
  $!{ { puts("enter"); $body puts("leave"); } };

macro Stmt $sample.trace(Stmt $body) => $traced($body);
~
~int main(void) {
~  $sample.trace(puts("work"););
~  return 0;
~}
```

Keep the braced `{ @helper(...) }` form for a function that returns
several block items as a `List`.

## Choose collections by mutation and identity

Use `List` for immutable sequences that share structure, `Array` for mutable
indexed sequences, and `Map` for mutable key/value pairs. Build text with
`Buffer` when repeated concatenation would create unnecessary intermediate
`String`s.

```x2c
List syntax = %(call print "hello");
Array work = [1, 2, 3];
Map index = {name: "x2c"};

work.push(4);
index[<count>] = work.len();
```

For a closed vocabulary of `Symbol`s that needs membership tests, a dense
index, or ordered iteration, declare a `SymbolSet` literal once and let its
perfect-hash `index` replace a hand-written switch; see
[Ordered Symbol sets](collections.md#ordered-symbol-sets) for the literal
and its operations.

## Destructure small fixed results

Flat `List` destructuring is clearest when a producer returns a few values in
fixed positions:

```x2c
List bounds = %(0 10 2);
int (start, stop, step) = bounds;

List record = %(7 2.5 "ready");
(int id, float score, String state) = record;
```

Assignment destructuring returns its source unchanged, so one result can feed
several flat views without another call or copy:

```x2c
Var left_a, left_b, right_a, right_b;
List values = (left_a, left_b) = %(1 2);
(right_a, right_b) = values;
```

Use `match` for conditional or nested shapes. Use named accessors when only one
position matters.

## Let collection methods express collection work

Use `foreach` when the operation is naturally sequential or can stop early.
Use `map`, `filter`, and folds for direct transformations:

```x2c
List values = %(1 2 3 4);
List squares = values.map(%!(item) => item * item);
Var sum = values.foldl(0, %!(total, item) => total + item);
```

Choose an explicit `Iter` pipeline when values must stream without first
materializing a collection.

## Keep lambdas small

An expression lambda is ideal for a short operation with a few captured
values. Use a block lambda when the operation needs local declarations,
branches, or `defer`:

```x2c
~List values = %(1 -2 3);
List magnitudes = values.map(%!(Var item) => {
  int value = item.int();
  if (value < 0) return -value;
  return value;
});
```

Captured scalars are read-only snapshots by default. Use `using &name` in
each lambda that needs to share the binding, including readers and enclosing
lambdas. Use a named function and an explicit state object when the operation
grows beyond one local task. The collection methods above accept `Func`, including capturing
lambdas. APIs that explicitly take C function pointers still require a
noncapturing lambda; see [Lambdas](../reference/language.md#lambdas).

## Separate absence from data

Prefer `try_*` operations when the full value domain includes `Null` or when a
fallback would lose information:

```x2c
Map map = {"name": "x2c"};
Var key = "name";
Var value;
if (!map.try_get(key, value))
  printf("missing\n");
```

Sentinel-returning adapters are concise only when the sentinel is impossible
in the result domain and the caller does not need a failure reason.

## Put cleanup beside acquisition

`Scope` groups allocations by lifetime and `$scope()` retains one region
around a statement. `$auto` attaches an owned local's cleanup to its
declaration, so the acquisition and its release are one line:

```x2c
$scope() {
  String path = "/tmp/x2c-idioms.txt";
  File output = $auto(File.open(path, "w"));
  output.puts("ready\n");
}
```

Both lower to `defer`, which runs on ordinary block exit and on early
transfer. Reach for `defer` directly where no macro fits: a native release,
a conditional rollback, a consuming parameter, or cleanup that writes a
result rather than releasing storage.

```x2c
~int main(void) {
int *buffer = malloc(64);
defer free(buffer);
~  return buffer ? 0 : 1;
~}
```

`$auto` requires the type to participate in `Cleanup(T)`; the runtime's owning
types already do.

## Raise failures; return ordinary outcomes

Do not turn EOF, a missing `Map` key, or numeric parse failure into an `Error`.
Those operations already report those outcomes in their results. Use `raise`
for a failure cause that may cross several frames, and put a filtered `catch`
where recovery or reporting belongs. Every intermediate resource owner must
have `defer` or `finally` cleanup in place.

## Prefer the primary API tier

The generated [module reference](../library/modules/index.md) separates:

- primary operations for ordinary programs;
- advanced storage, ABI, embedding, and diagnostics APIs;
- convenience adapters with a preferred operation;
- runtime-internal callables documented only for source readers.

Start with primary APIs; use the others when you need their specific behavior.
