# From C to x2c

Start with the C representation you would normally choose. Add an x2c feature
where it simplifies repeated declarations, traversal, cleanup, allocation
lifetimes, or dynamic data. You can use each feature without converting the
whole program to a new object model.

| If the C program needs... | Use... |
| --- | --- |
| one of several runtime value kinds | `Var` |
| canonical text with interpolation | `String` |
| persistent heterogeneous sequence data | `List` |
| a growable indexed collection | `Array` |
| a growable collection of key/value pairs | `Map` |
| an already-linked native call | `Func` |
| code evaluated at run time | `Lisp` and `$lisp.bind` |
| structural `List` cases | `match` |
| traversal without exposing representation | `foreach` or `Iter` |
| a grouped allocation lifetime | `Scope` |
| bounded temporary work with isolated runtime state | `Context` |
| a native worker with isolated x2c state | `Thread` and `Mutex` |
| cleanup on every exit path | `defer` |
| structured failure across frames | `raise` / `try` / filtered `catch` |
| an interface shared by concrete types | `protocol` and adoption |
| methods forwarded to a contained value | a `delegate` field |
| repeated declarations or expressions | a compile-time `macro` or `Decorator` |

## What x2c adds

The additions fall into five groups:

1. **C foundation.** Native types, layout, preprocessing, calls, and libraries
   keep their ordinary meaning.
2. **Runtime values.** `Var`, the standard collections, and embedded Lisp
   provide dynamic data and evaluation without requiring every value to be
   boxed.
3. **Control and lifetime.** `foreach`, `match`, `Scope`, `Context`, `Thread`,
   `defer`, and `Error` replace common code for traversal, pattern matching,
   cleanup, worker state, and error propagation.
4. **Driver and project model.** `translate` exposes generated C; `build`,
   `run`, project manifests, and `bootstrap` also handle native compilation
   and execution.
5. **Compile-time extension.** Protocols adapt types to explicitly adopted
   interfaces. Macros and decorators generate checked source before C emission.

The source tells you when these features apply. Assigning to `Var` boxes a
native value. `translate` leaves native compilation to an external C build.
Protocol adoption works at compile time without creating a runtime interface
object. Macros also run at translation time.

## Keep C where C is already clear

Native declarations, expressions, structs, unions, enums, pointers, headers,
and libraries remain available:

```x2c
typedef struct Point {
  double x;
  double y;
} Point;

double length_squared(Point point) {
  return point.x * point.x + point.y * point.y;
}
```

Nothing is boxed and no runtime collection is involved.

## Cross into Var deliberately

Box when a value is dynamic:

```x2c
Var value = 42;
value = "forty-two";

if (value is String)
  printf("%s\n", value.string());
```

Heterogeneous `List`s, `Array`s, and `Map`s box their elements automatically.
Conversions back to native types depend on the source and target types; not
every pair can be converted.

## Choose collection identity, not just syntax

- `List` and `String` are canonical values.
- `Array` and `Map` are mutable identity-bearing objects.
- Empty `List` and `String` use null native representations but remain typed
  data.
- Empty `Array` and `Map` are fresh allocated objects.
- `void` represents missing or exhaustion and is not collection data.

These differences determine equality, lifetime, mutation, and the correct
missing-value API.

## Check whether the operation succeeded

When failure or absence is expected, use the operation that reports it
separately:

```x2c
Map settings = %{theme: "dark"};
Var found;
if (settings.try_get(<theme>, &found))
  printf("theme=%s\n", found);

long number;
if (!%"not a number".try_long(&number))
  printf("invalid integer\n");
```

Use a convenience adapter when you know its precondition holds and do not
need the information it omits.

## Choose who owns the native build

The driver has four commands:

```sh
x2c translate --out-dir generated src/main.x
x2c build --output build/app src/main.x
x2c run src/main.x -- argument
x2c.com bootstrap --prefix /usr/local
```

Use `translate` when Make, Ninja, CMake, or another native build owns
compilation and linking. Use `build` or `run` when the x2c driver can do
that itself. Describe reusable projects with several targets in `x2c.toml`.
The driver builds them the same way as targets named on the command line.
The Cosmopolitan `bootstrap` command is an experiment for fun only; use the
full repository for normal development. See [Bootstrap a native
installation](../reference/cli.md#bootstrap-a-native-installation) for its
limited contents.

## Extend types through explicit contracts

A protocol declares the relationship once, and a separate adoption says which
concrete type participates:

```x2c
~
~typedef struct Reading {
~  int value;
~} *Reading;
~
~typedef struct Gauge {
~  Reading reading;
~} *Gauge;
~
protocol Reading(T) {
  int T.value(T);
}

Reading Gauge.reading(Gauge gauge) {
  return gauge.reading;
}

int Reading.value(Reading reading) {
  return reading.value;
}

protocol Reading(Gauge);
~
~int main(void) {
~  Reading reading = Scope.malloc(sizeof(struct Reading));
~  reading.value = 42;
~  Gauge gauge = Scope.malloc(sizeof(struct Gauge));
~  gauge.reading = reading;
~  return gauge.value() == 42 ? 0 : 1;
~}
```

The compiler resolves each adopted member and generates any required adapters.
A method with the same name but an incompatible signature is an error.
Matching names alone do not make a type participate.

Use a protocol when several types should satisfy one contract. Do not
introduce one to rename a single helper or hide a C call.

Private records can also adopt a protocol without exposing the type or its
adapters:

```x2c
~#pragma private
~
~typedef struct LocalJob {
~  int id;
~} *LocalJob;
~
static inline Var LocalJob.var(LocalJob job) {
  return Var.new(<localjob>, job);
}

static inline LocalJob Var.localjob(Var value) {
  return (LocalJob) value.pointer();
}

protocol Var(LocalJob);
~
~int main(void) {
~  LocalJob job = Scope.malloc(sizeof(struct LocalJob));
~  job.id = 7;
~  Var stored = job;
~  LocalJob restored = stored;
~  return restored.id == 7 ? 0 : 1;
~}
```

Because the participant is private, its generated adapters stay in its C file.
The public `Var(T)` protocol does not make `LocalJob` or its converters appear
in the generated header.

## Forward through composition

To forward a type's method calls to one of its fields, mark that field
`delegate`:

```x2c
typedef struct Reading {
  int value;
} Reading;

typedef struct Gauge {
  delegate Reading reading;
} Gauge;

int Reading.value(Reading reading) {
  return reading.value;
}

int gauge_value(Gauge gauge) {
  return gauge.value();
}
```

The final call is a direct `Reading_value(gauge.reading)` call. `Gauge` does
not become a `Reading` and does not adopt any protocol. Use a delegate field
for this contained-value forwarding; use a protocol when `Gauge` must
explicitly participate in a shared contract, as in the `Reading(Gauge)`
example above.

## Remove repeated source with typed macros

Macros match parsed, typed source positions. Their hole declarations make the
bindings visible:

```x2c
~
macro Expression $minutes(Expr $value) => ($value * 60)
~
~int main(void) {
~  int seconds = $minutes(2);
~  return seconds == 120 ? 0 : 1;
~}
```

Here `$minutes` is the qualified macro name, `Expr $value` declares one
expression hole, and `$value` inserts the caller's expression into the
replacement. Other result kinds cover statements, fields, enum members,
translation-unit items, and decorators.

Use a macro when its invocation is smaller and clearer than the source it
replaces, and its meaning is obvious. Keep a function when runtime
evaluation and a function signature already express the job.
See [Compile-time Macros](macros.md) for the grammar.

## Guide chapters

- [Values and Var](values.md): dynamic values, boxing, conversion, arithmetic.
- [Symbols and Atoms](symbols.md): compact tags versus exact names.
- [Collections](collections.md): text and collection construction/mutation.
- [Pattern Matching](match.md): structural `List` decisions.
- [Iteration](iteration.md): `foreach` and lazy pipelines.
- [Scopes and Lifetime](memory.md): grouped allocation ownership.
- [Contexts and Threads](contexts-and-threads.md): bounded work, native
  workers, result export, and shared-memory rules.
- [Errors and Cleanup](exceptions.md): transfer and guaranteed cleanup.
- [Protocols](protocols.md): explicit adoption, adapters, punctuation, boxed
  behavior.
- [Compile-time Macros](macros.md): typed templates, imports, decorators, and
  when to use them.
- [Idioms](idioms.md): putting those facilities together.
