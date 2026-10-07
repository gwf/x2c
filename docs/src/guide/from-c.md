# From C to x2c

This is a working reference for someone who already knows C. Read it for the
places where x2c adds syntax or changes what familiar source means.

x2c translates to C and uses the native compiler, linker, object layout, and
calling conventions. Scalars, aggregates, pointers, arrays, and ordinary
functions remain useful representations. Each `.x` unit also loads the
standard runtime prelude. `Var`, collections, protocols, and closures add
operations where you use them. Memory ownership remains explicit: there is
no garbage collector or reference counting.

## Files, visibility, and the native build

| Write or run | Meaning |
| --- | --- |
| `module.x` | A unit containing declarations and definitions; translation produces a C source and header |
| `#include "module.x"` | Make that unit's public declarations and compile-time definitions visible |
| `#include "native.h"` | Read native declarations and preserve the native include in generated C |
| `static` | Private function/object; also permitted on a type declaration to control its publication |
| `import "geo" as g with Vec;` | Import a registered package; use `g.Vec` or the selected bare name `Vec` |
| `x2c translate --out-dir generated main.x` | Let an existing native build compile and link the output |
| `x2c build --output app main.x helper.x` | Let x2c own compilation and linking; list the local implementation units |
| `x2c run main.x -- argument` | Build and execute |

Declarations are public by default. Public objects get one definition and an
`extern` declaration; public functions get prototypes. Types needed by a
public interface are published even if initially marked private. Including a
local `.x` exposes its declarations; an ordinary build must also link its
implementation. Package imports add a namespace and package-prefixed C names.

Runtime-valued file-scope initializers use generated unit initialization.
Optional `void T.initialize(void)` and `void T.shutdown(void)` hooks have
[lazy initialization and shutdown rules](../reference/language.md#type-owned-initialization).
See [units and visibility](../reference/language.md#source-files-and-visibility)
for publication and include details.

A first-line `#!/usr/bin/env -S x2c script` selects a script unit. Without an
explicit `main`, its top-level executable statements form the program body;
`args` is a List of argument Strings. Functions cannot see those body locals.
`x2c script` builds and links included local modules. An explicit `main`
restores ordinary file-scope rules. See [scripting](scripting.md).

Braces and semicolons work throughout this page. Optional `.xp` files, or
`#pragma indent` before code, use indentation, colons, and line endings to
supply block and statement tokens. This changes source spelling, not the
later grammar. Use spaces for indentation; ordinary C `for` headers retain
their parentheses. See [indentation syntax](indentation.md).

## Types, methods, and references

A method is a function with a type-qualified name. Dotted calls select it
from the receiver's **static type** and pass the receiver as the first argument.

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

Reference parameters lower to C pointers. They neither own storage nor extend
its lifetime. Pass `*p` to borrow the object addressed by a pointer. References
are supported on parameters, not locals, fields, globals, or return types.
An optional-reference presence test asks whether storage was supplied, not
whether the stored integer or pointer is nonzero.

Use `->` where x2c cannot see the aggregate definition and inside native
preprocessor text. Delegation forwards methods, not fields or operators, and
creates no subtype or implicit protocol adoption. Ambiguous forwarding is an
error. Details: [C foundation](../reference/language.md#c-foundation).

Typedef chains participate in method and converter lookup. Sibling typedefs
can require a conversion even when their C representations coincide. Some
pointer mismatches that C diagnoses as warnings are x2c errors. A cast still
expresses deliberate reinterpretation; it does not validate the object.

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

Methods can replace the defaults. Resource-containing fields need an explicit
initialization/cleanup design; the generated methods do not infer field
ownership. Copying a record with an Array or pointer field still shares that
backing object. See [classes and system macros](system-macros.md).

A protocol declares an explicit compile-time contract. Adoption asks the
compiler to resolve its members and any required adapters:

```x2c
~typedef struct Reading { int value; } Reading;
~typedef struct Gauge { int value; } Gauge;
protocol Reading(T) {
  int T.value(T);
}

int Gauge.value(Gauge gauge) => gauge.value;
protocol Reading(Gauge);
```

Matching method names alone do not adopt a protocol. Associated types and
member aliases describe richer contracts. Adoption itself creates no runtime
interface object. `Var(T)` additionally connects a type to boxing and runtime
operations; that is a distinct choice. See [protocols](protocols.md).

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

Initializers, assignments, typed arguments, and returns can call converters.
For example, `Var v = 42;` boxes, while a supported typed destination unboxes
or converts. This is not a promise that every pair converts or that extraction
validates a custom value. Test dynamic tags with `is` when the input is mixed.
Explicit `.str()` renders a value; extracting a String payload is different.

Three distinctions matter immediately:

- `NULL`, an empty typed String/List, and expression `void` are different.
  Empty Strings/Lists have null native representations but retain their tags
  when boxed. Empty Arrays/Maps are allocated objects.
- Expression `void` means absence or exhaustion. Collections exclude it.
  Equality/tag tests accept it; arithmetic, conversion, and truth-testing it
  raise an error. Prefer `try_get`/`try_next` when presence must be separate
  from the payload.
- Conditions on runtime values use their truth operation. Empty containers
  are false even when allocated; ordinary pointers retain pointer truth.
  `&&` and `||` still short-circuit.

See [values and Var](values.md) for tags, conversion, and numeric behavior.

## Literals: evaluated expressions versus quoted data

```x2c
int n = 4;
Array evaluated = [n, n + 1];
List quoted = %(n $n ${n + 1});
Map settings = {mode: "fast", count: n};
String message = %"count=$n next=${n + 1}";
```

The Array contains `4, 5`. The List contains the Atom `n`, then `4, 5`.
The Map's bare keys are Atoms; `{(name): value}` uses a variable as its key.

| Form | Contents |
| --- | --- |
| `[expressions]`, `{key: expression}` | Evaluate expressions; nested bare collections do likewise |
| `%(items)` | Whitespace-separated List data; bare names are Atoms |
| `%[items]`, `%{key: value}` | Array/Map with quoted contents; commas separate entries |
| `%"text $name ${expression}"` | Interpolated String |
| `%<<ready busy done>>` | Immutable ordered SymbolSet; literal members only |
| `$name`, `${expression}` inside quoted data | Insert one evaluated value |
| `@name`, `@{expression}` inside a quoted List | Splice a List's elements; Arrays/Maps do not support this splice |

Bare `{}` depends on its destination: it can build a Map or Array, or zero
initialize a native object. Braces in an argument or return can also construct
the destination type. Ordinary C compound literals and designated
initializers remain available. Collection entries and interpolations evaluate
once each, left to right; ordinary function arguments keep C's evaluation
order rules.

Percent literals change the reader. Inside `%()`, commas and apostrophes are
Lisp reader punctuation, not list separators and C character quotes. Insert a
C character with `${'x'}`. Lisp reader `'`, backquote, `,`, and `,@` construct
quote/unquote forms; constructing a List does not evaluate it as Lisp.
Strings nested in quoted data also interpolate. Escape a literal dollar
in percent text as `\$`.

Keep an opener's characters adjacent. After a cast's closing `)`, `%(`,
`%{`, and `%!` can read as modulo: write `(List) (%(a b))` or
`(Func) (%!(x) => x)`. Binary `%` remains modulo. Numbers accept `0o` explicit octal and
`0b` binary (also in C23). Signs belong to numeric tokens in some data modes,
but remain operators in code. See [literal rules](../reference/language.md#percent-literals-quote-and-unquote).

## Operators, indexing, and small declaration additions

| Spelling | Meaning |
| --- | --- |
| `a == b`, `a != b` | May use a type's equality operation; not necessarily a pointer comparison |
| `a === b`, `a !== b` | Identity tests; for `Var`, compare tagged representation |
| `value is Type`, `value is not Type` | Require a Var left operand; test its exact tag, not ancestry or convertibility; a tag Symbol may replace `Type` |
| `item in collection` | Membership; Maps test keys, Strings test substrings; negate with `!(item in collection)` |
| `a @ b`, `a @= b` | Call the participating type's `matmul` operation; `@=` updates its left operand |
| `items[-1]`, `items[start:stop:step]` | Negative indexing and slicing on Array/List/String; omitted bounds are allowed, zero step is invalid |
| `int i, float x;` | Restart declaration specifiers after a comma |
| `Var (a, b) = values;` | Destructure a List into new bindings |
| `(int a, String b) = values;` | Destructure into separately typed new bindings |
| `(a, b) = values;` | Destructure into existing simple identifiers |
| `threaded` | Spelling of C thread storage; `_Thread_local` and `thread_local` also work |

Other operators may also call protocol members. String `+` concatenates;
String comparisons use content. A C string literal opposite a String in a
comparison converts to String, while other C pointer expressions retain
native behavior. Native-only numeric expressions retain C arithmetic; dynamic
`Var` arithmetic has its own promotion and failure rules.

Array/List out-of-range reads and missing Map keys produce `void`; an
out-of-range String index produces `-1`, and a successful String index is a
byte integer. Array/Map elements support writes and compound updates;
String/List elements are immutable. Native pointers and arrays still have
native bounds behavior. Optional packed typed collections have their own
[indexing contracts](../reference/language.md#indexing-and-slicing).

Destructuring evaluates its List once, ignores extra elements, and supplies
`void` for missing ones before destination conversion. Targets are flat
identifiers. Even `(a) = values` destructures the first element. Mixed-type
rows do not extend `for` initializers. Ordinary calls allow a trailing argument
comma; meta calls do not. See [declarations](../reference/language.md#mixed-declaration-rows)
and [operator precedence](../reference/syntax/grammar.md#expression-contracts).

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

`foreach (declaration in expression)` evaluates its source once; a comma can
replace `in`. `foreach (Var (key, value) in map)` destructures entries.
Matching evaluates its subject once and selects the first successful arm.
`?name` binds one Var, `*rest` binds a List subsequence, and bare `?`/`*` discard
those captures. Typed `?(T name)` checks an exact tag before binding; it does
not convert. Guards run after binding. `break` exits the match; `continue`
targets an enclosing loop. See [iteration](iteration.md) and [patterns](match.md).

```x2c
int total = 1;
Func snapshot = %!() => total;
Func add = %!(int n) using &total => total += n;
total = 10;
Var old = snapshot();            // 1
Var next = add(2);               // 12; total becomes 12
```

Lambdas use `%!(parameters) => expression` or `=> { statements }`. Bare
parameters are Vars. Unlisted captured locals are read-only snapshots of the
binding; a pointer snapshot still shares its pointee. `using &name` shares a
binding for writes. Captures follow Scope lifetime and do not keep borrowed
objects alive or synchronize threads.

A supported noncapturing lambda can become a C function pointer. A capturing
`Func` cannot fit a context-free callback ABI. Calls through Func return Var;
an effect-only result is `void`. See [lambdas](../reference/language.md#lambdas).

## Ownership, cleanup, and errors

C allocations still need their ordinary owner. Runtime mutable allocations
and wide Var boxes belong to a `Scope`; releasing a region frees its storage.
Canonical String/List storage normally lasts for the process; explicit Pool
or Context lifetimes can shorten that. Canonical structure does not extend
the lifetime of mutable objects stored inside it.

```x2c
~int main(void) {
$scope() {
  File file = $auto(tmpfile());
  file.puts("hello\n");
  Array scratch = [1, 2, 3];
}
~return 0;
~}
```

`$scope()` brackets a retained allocation region. `$auto(initializer)` attaches
an adopted `Cleanup` operation to that local's enclosing block. Ordinary
braces do neither automatically. `$auto` does not transfer ownership on return,
and reassigning its binding does not dispose of the old value. Use these forms
only with a clear owner. `$lock(mutex)` and `$let(location, value)` provide
scoped locking and temporary replacement through the same cleanup machinery.

`defer statement;` schedules block-exit work in reverse registration order.
Cleanup runs on normal exit and the supported transfers: return, outward
goto, break/continue leaving the region, and Error transfer. A return value is
saved before cleanup. Jumping into a protected cleanup region is rejected.

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

An Error has a Symbol cause and structured immutable details. Here `$n`
inserts the variable; bare `n` would be an Atom. Details cannot hold arbitrary
objects or mutable containers. Filters use List patterns; `catch:` is the final catch-all.
Intervening cleanup runs before the selected catch arm. Catch details are
borrowed; take an `Error.snapshot` to retain them. Shared runtime error causes
do not return to the raising call. A `try` needs a catch, finally, or both.

A Context groups allocation, Error, and Match state. A Thread runs a callback
in an isolated Context on a native thread. Export retained results before
closing an isolated Context; synchronize shared mutable data. See
[lifetime](memory.md), [cleanup and errors](exceptions.md), and
[contexts and native threads](contexts-and-threads.md).

## Compile-time code and source substitution

```x2c
macro Expression $twice(Expr $value) => $value + $value;
~int main(void) {
int result = $twice(3);
~return result == 6 ? 0 : 1;
~}
```

Macros consume parsed source positions. `Expr`, `Stmt`, `Type`, `Decl`, and
other hole/result kinds describe the grammar they accept and produce.
Bindings declared by a template are hygienic. Expression substitution can
repeat evaluation: `$twice(f())` above calls `f()` twice. Save a value when
single evaluation matters.

| Spelling | Purpose |
| --- | --- |
| `$name(arguments)` in code | Invoke a macro or visible meta function |
| `$!(expression)`, `$!{ statements }`, `$!Unit{ ... }` | Quote source as syntax for compile-time construction |
| `$(...)` | Evaluate compile-time Lisp |
| `meta` function | Expose a function to compile-time calls; `meta native` declares a callable supplied by the compiler or a loaded native module |
| `keyword` | Give a macro a source keyword alias; shipped `class` and `foreach` use this mechanism |
| Decorator macro | Consume and transform the following statement, function, or named type |

A sequence hole such as `Expr $args...` captures syntax for `$args...`
expansion in supported positions. This differs from `@` splicing in quoted
Lists. A `meta` function can also be called at runtime; `$f(...)` selects
compile-time execution. Neither form implies purity. `$` means interpolation inside quoted data and
macro/meta invocation in source code. Runtime Lisp evaluation is a separate
explicit library operation. See [macros](macros.md) and [meta functions](meta-functions.md).

`with expression as name { ... }` is lexical expression substitution; the
name defaults to `_`. Each use evaluates the expression again. It creates
neither a saved temporary nor a cleanup frame. Declare a local for single
evaluation; use `$auto` or a block decorator for managed lifetime.

## Before bringing over a C source file

x2c reads source grammar before ordinary host preprocessing. Most conditional
branches must therefore parse, including branches the native build disables.
Recognized exclusions include C++/MSVC-only guards and `#if 0`; platform rules
also apply. Native declaration-prefix/attribute macros have supported forms,
but a C macro that supplies missing grammar may need an x2c macro or rewritten
call site. See [host preprocessing](../reference/language.md#host-preprocessing).

Keep these boundaries in mind:

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
  A computed format does not; respect the native variadic ABI.

For the complete inventory, use the [x2c syntax map](x2c-syntax-map.md).
For exact productions and lexical decisions, use the
[syntax specifications](../reference/syntax/index.md). The
[language reference](../reference/language.md) owns the detailed contracts;
[idioms](idioms.md) shows how to combine them in working code.
