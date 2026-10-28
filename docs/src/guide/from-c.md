# From C to x2c

This chapter lists where x2c syntax or meaning differs from C. Each section
links to the chapter that explains it.

x2c translates to C and uses the native compiler, linker, object layout, and
calling conventions. Scalars, aggregates, pointers, arrays, and ordinary
functions remain useful representations. Each `.x` unit also loads the
standard runtime prelude. `Var`, collections, protocols, and closures add
operations where you use them. Memory ownership remains explicit: there is
no garbage collector or reference counting.

## Files, visibility, and the native build

The commands below use an installed compiler on `PATH`. From the repository
root, use `./x2c` to select the current development build instead.

| Write or run | Meaning |
| --- | --- |
| `module.x` | A unit containing declarations and definitions; translation produces a C source and header |
| `#include "module.x"` | Make that unit's public declarations and compile-time definitions visible |
| `#include "native.h"` | Read native declarations and preserve the native include in generated C |
| `static` | Private function/object; also permitted on a type declaration to control its publication |
| `import "geo" as g with Vec;` | Import a registered package; use `g.Vec` or the selected bare name `Vec` |
| `x2c translate --out-dir generated main.x` | Let an existing native build compile and link the output |
| `x2c build -o app main.x helper.x` | Let x2c own compilation and linking; list the local implementation units |
| `x2c run main.x -- argument` | Build and execute |

Declarations are public by default. A type that a public declaration needs
becomes public; its body is published only when the interface needs the
layout. Including a local `.x` exposes its declarations, and the build must
also link its implementation. See
[units and visibility](../reference/language.md#source-files-and-visibility)
and [type-owned initialization](../reference/language.md#type-owned-initialization).

A first-line `#!/usr/bin/env -S x2c script` makes a script unit, whose
top-level statements form the program body. See [scripting](scripting.md).

An `.xp` file, or `#pragma indent` before code, uses indentation in place of
braces and semicolons. The parser then reads the same tokens as the brace
form. See [indentation syntax](indentation.md).

## Types, methods, and references

A method is a function with a type-qualified name. Dotted calls select it
from the receiver's static type and pass the receiver as the first argument.

```x2c
typedef struct Counter { int value; } Counter;

void Counter.add(Counter &counter, int amount) => counter.value += amount;
int Counter.get(Counter counter) => counter.value;

~int main(void) {
Counter count = {0};
count.add(3);
printf("%d\n", count.get());
~return 0;
~}
```

| Spelling | Rule |
| --- | --- |
| `int T.f(T value, int n)` | Defines `T.f`; generated C uses a function such as `T_f` |
| `object.field` | Also works through one pointer level when x2c knows the aggregate layout; `->` remains valid |
| `T &value` parameter | Borrows the caller's addressable `T`; call with `value`, not `&value` |
| `T &?value` parameter | Also accepts `NULL`; test presence before using the borrowed object |
| `Self` in a method signature | Preserves the original receiver's static typedef at the marked parameter/result positions |
| `delegate T field;` | Forwards otherwise unresolved dotted method calls through that field |
| `result_type f(...) => expression;` | A one-expression function body; a `void` function executes it without returning a value |

Reference parameters lower to C pointers and are allowed only on
parameters. Use `->` where x2c cannot see the aggregate definition. Some
pointer mismatches that C only warns about are x2c errors. The
[C foundation](../reference/language.md#c-foundation) gives the rules for
references, delegation, typedef chains, and conversions.

## What `class` and `protocol` mean

`class` is a shipped declaration macro. The declaration chooses an ordinary
C representation and supplies applicable constructors, conversions,
comparison, hashing, and printing defaults:

```x2c
class Point { int x; int y; };
class Node { int value; } *;
class Count int;

~int main(void) {
Point p = Point.new(3, 4);       // record value
Node n = Node.new(7);           // pointer; default allocation uses Scope
Point copy = p;                 // ordinary shallow record copy
n.free();
~return 0;
~}
```

Methods can replace the defaults. Copying a record with an Array or pointer
field shares that backing object. See
[classes and system macros](system-macros.md).

A protocol declares a compile-time contract. On adoption, the compiler
resolves the protocol's members and any adapters they need:

```x2c
~typedef struct Reading { int value; } Reading;
~typedef struct Gauge { int value; } Gauge;
protocol Reading(T) {
  int T.value(T);
}

int Gauge.value(Gauge gauge) => gauge.value;
protocol Reading(Gauge);
```

A type participates only through an explicit adoption. `Var(T)` also
connects a type to boxing and runtime operations. See
[protocols](protocols.md).

## Runtime values and implicit operations

| Type | Representation and consequence |
| --- | --- |
| Native C type | Keeps native storage and arithmetic unless an x2c conversion or protocol operation applies |
| `Var` | Eight-byte tagged value; supported values box/unbox at typed boundaries; wide scalars and some custom values require allocated boxes |
| `String` | Immutable canonical text; equal content shares storage |
| `List` | Immutable canonical cons structure; elements are `Var` values |
| `Array`, `Map` | Mutable objects with identity; copying their handles shares the object |
| `Symbol` | Encoded 64-bit tag, written `<ready>`; source spelling must fit exactly |
| `Atom` | Exact name of arbitrary length, used by quoted data; compact names use Symbol representation |
| `Func` | Callable runtime handle, possibly with captures; calls through it return `Var` |

Initializers, assignments, typed arguments, and returns can call converters:
`Var v = 42;` boxes, and a typed destination unboxes. Some pairs have no
converter. `NULL`, an empty `String` or `List`, and `void` are three
different values, and a condition on a runtime value uses its truth
operation, so an empty `Array` is false. See [values and Var](values.md).

## Literals: evaluated expressions versus quoted data

```x2c
int n = 4;
Array evaluated = [n, n + 1];
List quoted = %(n $n $(n + 1));
Map settings = {mode: "fast", count: n};
String message = %"count=$n next=$(n + 1)";
```

The Array contains `4, 5`. The List contains the Atom `n`, then `4, 5`.
The Map's bare keys are Atoms; `{(name): value}` uses a variable as its key.

| Form | Contents |
| --- | --- |
| `[expressions]`, `{key: expression}` | Evaluate expressions; nested bare collections do likewise |
| `%(items)` | Whitespace-separated List data; bare names are Atoms |
| `%[items]`, `%{key: value}` | Array/Map with quoted contents; commas separate entries |
| `%"text $name $(expression)"` | Interpolated String |
| `%<<ready busy done>>` | Immutable ordered SymbolSet; literal members only |
| `$name`, `$(expression)` inside quoted data | Insert one evaluated value |
| `@name`, `@(expression)` inside a quoted List | Splice a List's elements; Arrays/Maps do not support this splice |

Bare `{}` depends on its destination: it builds a `Map` or `Array`, or zero
initializes a native object. Inside `%()`, commas and apostrophes are Lisp
reader punctuation. After a cast's closing `)`, `%(` reads as modulo, so
write `(List) (%(a b))`. Numbers also accept `0o` octal and `0b` binary. See
[collections](collections.md) and the
[literal rules](../reference/language.md#percent-literals-quote-and-unquote).

## Operators, indexing, and small declaration additions

| Spelling | Meaning |
| --- | --- |
| `a == b`, `a != b` | Uses the type's equality operation when one exists; two `Var` numbers compare as their C values do |
| `a === b`, `a !== b` | Identity tests; two `Var` numbers are identical with the same type and bits |
| `value is Type`, `value is not Type` | Require a Var left operand; test its exact tag, not ancestry or convertibility; a tag Symbol may replace `Type` |
| `item in collection` | Membership; Maps test keys, Strings test substrings; negate with `!(item in collection)` |
| `items[-1]`, `items[start:stop:step]` | Negative indexing and slicing on Array/List/String; omitted bounds are allowed, zero step is invalid |
| `int i, float x;` | Restart declaration specifiers after a comma |
| `Var (a, b) = values;` | Destructure a List into new bindings |
| `(int a, String b) = values;` | Destructure into separately typed new bindings |
| `(a, b) = values;` | Destructure into existing simple identifiers |
| `threaded` | Spelling of C thread storage; `_Thread_local` and `thread_local` also work |

Other operators may call protocol members: `String` `+` concatenates, and
`String` comparison uses content. The reference gives the rules for
[indexing](../reference/language.md#indexing-and-slicing),
[declaration rows](../reference/language.md#mixed-declaration-rows),
[destructuring](../reference/language.md#flat-list-destructuring), and
[operator precedence](../reference/syntax/grammar.md#expression-contracts).

## Iteration, matching, and closures

```x2c
List rows = %((add 2) (add 5));
foreach (List row in rows) {
  match (row) {
    case %(add ?(int amount)) if (amount > 0):
      printf("%d\n", amount);
    default: break;
  }
}
```

`foreach` evaluates its source once. `match` tries its arms in order:
`?name` binds one element, `*rest` binds the remaining elements, and
`?(T name)` also checks the tag. See [iteration](iteration.md) and
[pattern matching](match.md).

```x2c
int total = 1;
Func snapshot = %!() => total;
Func add = %!(int n) using &total => total += n;
total = 10;
Var old = snapshot();            // 1
Var next = add(2);               // 12; total becomes 12
```

Lambdas use `%!(parameters) => expression` or `=> { statements }`. Captured
locals are read-only snapshots unless `using &name` shares them. Only a
noncapturing lambda can become a C function pointer. See
[lambdas](../reference/language.md#lambdas).

## Ownership, cleanup, and errors

C allocations still need their ordinary owner. Runtime mutable allocations
and wide `Var` boxes belong to a `Scope`, and canonical `String` and `List`
values normally last for the process. See [scopes and lifetime](memory.md).

```x2c
~int main(void) {
auto {
  File file = auto tmpfile();
  file.puts("hello\n");
  Array scratch = [1, 2, 3];
}
~return 0;
~}
```

`auto` retains an allocation region around a statement, and initializer
`auto` releases the acquired value at block exit. `$lock` and `with` give
scoped locking and temporary assignment. See
[classes and system macros](system-macros.md). `defer statement;` runs the
statement at block exit, in reverse order of registration.

```x2c
int n = -1;
try {
  if (n < 0) raise %(bad-arg (value $n));
}
catch %(bad-arg *details): {
  printf("bad argument: %s\n", details.repr());
}
finally {
  puts("finished protected work");
}
```

An `Error` has a `Symbol` cause and immutable details. Here `$n` inserts
the variable; a bare `n` would be an `Atom`. See
[errors and cleanup](exceptions.md). A `Context` bounds allocation and error
state for a task, and a `Thread` runs one on a native thread. See
[contexts and threads](contexts-and-threads.md).

## Compile-time code and source substitution

```x2c
macro Expression $twice(Expr $value) => $value + $value;
~int main(void) {
int result = $twice(3);
~return result == 6 ? 0 : 1;
~}
```

A macro takes parsed source. Its hole kinds, such as `Expr` and `Stmt`,
state what each argument accepts. An argument used twice is evaluated
twice: `$twice(f())` calls `f()` twice.

| Spelling | Purpose |
| --- | --- |
| `$name(arguments)` in code | Invoke a macro or visible meta function |
| `$!(expression)`, `$!{ statements }`, `$!Unit{ ... }` | Quote source as syntax for compile-time construction |
| `meta` function | Expose a function to compile-time calls; `meta native` declares a callable supplied by the compiler or a loaded native module |
| `keyword` | Give a macro a source keyword alias; shipped `class` and `foreach` use this mechanism |
| Decorator macro | Transform the following expression, statement, field, function, named type, or unit item |

A `meta` function can also be called at runtime; `$f(...)` runs it at
compile time. `alias name to expression;` (also `alias expression as name;`)
substitutes the expression at
each use of `name`. See [macros](macros.md),
[meta functions](meta-functions.md), and
[generating code](generating-code.md).

## Before bringing over a C source file

x2c parses source before host preprocessing, so most conditional branches
must parse, including ones the native build disables. A C macro that
supplies missing grammar may need an x2c macro or a rewritten call site. See
[host preprocessing](../reference/language.md#host-preprocessing).

- Use `(void)` for an ordinary no-argument function declaration. Do not assume
  every C dialect, wide/UTF literal spelling, or identifier spelling is accepted;
  identifier scanning is ASCII. The [lexical specification](../reference/syntax/lexical.md)
  records the exact boundaries.
- `_Static_assert`, designated initializers, `_Generic`, GNU attributes, and
  statement expressions are supported native forms. `_Generic` has no x2c
  result type until a cast supplies one, so it cannot directly drive boxing
  or method lookup.
- `in` and `match` remain ordinary identifiers outside their contextual forms.
  Other new keywords can collide with C names. Check the
  [keyword inventory](../reference/syntax/lexical-data.md#keywords).
- Literal printf-family formats can trigger conversions of Var arguments.
  A computed format with a Var argument is rejected. For native arguments,
  respect the native variadic ABI.

The [x2c syntax map](x2c-syntax-map.md) lists every addition. The
[syntax specifications](../reference/syntax/index.md) give the exact
productions, and the [language reference](../reference/language.md) states
the exact rules. [Idioms](idioms.md) shows how to combine them.
