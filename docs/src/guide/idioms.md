# Programming Idioms

These idioms combine the features introduced in the guide.

## Keep native values native

Use C scalar, pointer, struct, union, and enum types when the value's type is
known at compile time. Use `Var` where the value is dynamic: heterogeneous
collection elements, dynamic arithmetic, generic callbacks, or interchange
data.

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
macro Statement $guard(Expr $condition) => {
  if (!$condition) return 0;
}
~
~int positive(int value) {
~  $guard(value > 0);
~  return value;
~}
```

Prefer a function when the job is runtime computation. Prefer direct source
when a macro needs substantial compile-time Lisp or AST manipulation to save a
few tokens. The macro body, imports, and generated declarations are part of the
maintenance cost.

## Choose collections by mutation and identity

Use `List` for immutable sequences that share structure, `Array` for mutable
indexed sequences, and `Map` for mutable key/value pairs. Build text with
`Buffer` when repeated concatenation would create unnecessary intermediate
`String`s.

```x2c
List syntax = %(call print "hello");
Array work = %[1, 2, 3];
Map index = %{name: "x2c"};

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
Map map = %{"name": "x2c"};
Var key = "name";
Var value;
if (!map.try_get(key, &value))
  printf("missing\n");
```

Sentinel-returning adapters are concise only when the sentinel is impossible
in the result domain and the caller does not need a failure reason.

## Put cleanup beside acquisition

`Scope` groups allocations by lifetime. `defer` runs cleanup when control
leaves a block:

```x2c
Scope.retain();
defer Scope.release();

String path = "/tmp/x2c-idioms.txt";
File output = File.open(path, "w");
defer output.close();
```

The deferred actions run on ordinary block exit and early transfer. Keep the
acquisition and its cleanup close enough to review together.

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
- compatibility adapters with a preferred replacement;
- runtime-internal callables documented only for source readers.

Start with primary APIs; use the others when you need their specific behavior.
