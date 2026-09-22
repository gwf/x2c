# Meta Functions

x2c extends C. The subset that a `meta` function can execute during
compilation cuts across both C features and x2c additions: integer loops,
local pointer indirection, structs, collection literals and method calls
can work; a union or an otherwise ordinary library call can stop it.
There are three separate questions:

1. **Can the body execute?** Its syntax and values need compile-time
   representations. This includes parameters, locals, mutation and returns.
2. **Can each operation execute?** Every resolved call needs a compile-time
   binding. Having a supported receiver type does not expose its entire API.
3. **Can the answer become program code?** Returning a value to another
   meta function, inserting it with `$helper(...)`, and folding an ordinary call
   have different limits.

`meta` is not a purity annotation. A body can mutate locals, arrays, maps
and structs, and pass local addresses to other meta functions. Its
compile-time objects belong to the evaluator; they are not the objects the
eventual program allocates.

Start with an ordinary function. This one takes an integer and returns an
integer, using the same braces, `return`, and arithmetic as C:

```x2c
int poly(int n) {
  return n * n + 3 * n + 1;
}
```

Calling `poly(7)` gives 71. Now put `meta` before its definition:

```x2c
meta int poly(int n) {
  return n * n + 3 * n + 1;
}
```

The body has not changed. `meta` makes it available to the compiler during
translation as well as to the finished program. You can use it for an
ordinary calculation; it does not have to inspect types or generate code.

## Call it in the program

An ordinary call uses parentheses and commas, just as before. Here the
argument is a local variable:

```x2c
meta int poly(int n) {
  return n * n + 3 * n + 1;
}

int main(void) {
  int n = 7;
  printf("%d\n", poly(n));
  return 0;
}
```

```text
71
```

This uses the function's run-time form. The compiler emits C for the body,
and the finished program calls it.

## Ask the compiler to calculate it

Use `$poly(7)` to call the same function during translation:

```x2c
meta int poly(int n) {
  return n * n + 3 * n + 1;
}

int main(void) {
  printf("%d\n", $poly(7));
  return 0;
}
```

```text
71
```

The `$` prefix requires the compiler to run the function and insert its
result. The call uses the same parentheses and commas as an ordinary x2c
call. Here it inserts the integer 71 before the program is built.

The optional Lisp equivalent is `$(poly 7)`. It calls the same implementation;
use it when working with Lisp code already in the compiler session.

These are the two forms of a `meta` function: one runs in your program,
and one runs in the compiler. Both come from the same body. Functions that
need compiler queries, explicit compile-time calls or source-template
construction are exceptions: they only run during translation. We will reach those after ordinary calculations.

## Compute the arguments too

An explicit call can calculate its arguments before invoking the function:

```x2c
meta int twice(int n) => n * 2;

int main(void) {
  printf("%d\n", $twice(3 + 4));
  return 0;
}
```

```text
14
```

The arguments must be resolvable during compilation. They may be computed
expressions and calls to other meta functions, rather than only literals.
An unresolved runtime input is an error; the explicit call cannot fall back
to runtime execution. An existing macro with the same name takes precedence.
Inside an executing meta body, arguments use that evaluation's current values.

## Dynamic runtime calls

A meta function can be stored in a `Func` and called with runtime arguments:

```x2c
meta int poly(int n) => n * n + 3 * n + 1;

int main(void) {
  Func calculate = poly;
  printf("%d\n", calculate(7));
  return 0;
}
```

```text
71
```

This dispatches the compiled implementation. It does not select the
interpreted body used during compilation. An embedding program can apply an
interpreted callable through the Lisp evaluator API, but converting a meta
function to `Func` does not export that interpreted callable automatically.

## Constant calls are folded

An ordinary call with literal arguments can also be calculated during
translation. You do not have to prefix the name with `$` to benefit from it:

```x2c
meta int poly(int n) {
  return n * n + 3 * n + 1;
}

int main(void) {
  int n = 7;
  printf("constant %d\n", poly(7));
  printf("local    %d\n", poly(n));
  return 0;
}
```

```text
constant 71
local    71
```

The generated C shows the difference:

```text
printf("constant %d\n", 71);
printf("local    %d\n", poly(n));
```

Here `poly(7)` becomes 71, while `poly(n)` remains a call. This automatic
substitution is called folding. It is an optimization intended to preserve
the runtime answer; the capability catalog below records current differences.
`$poly(7)` requires compile-time evaluation; `poly(7)` leaves folding to the
compiler.

## Use x2c conveniences

The body can also use familiar x2c conveniences. An expression-bodied
function uses `=>` in place of braces and `return`:

```x2c
meta int poly(int n) => n * n + 3 * n + 1;
```

A `String` parameter gives access to string operations through dot syntax:

```x2c
meta static int width(String text) => text.len() * 2;

int main(void) {
  printf("%d\n", $width("abcd"));
  return 0;
}
```

```text
8
```

`static` follows `meta` and keeps its usual meaning for the emitted
function. A body can use local variables, ordinary control flow, `foreach`,
and `String`, `List`, `Array`, and `Map` operations with compile-time
bindings. The restrictions below describe where this stops.

## When `meta` is a keyword

`meta` is contextual. Besides functions, it can mark the file-static values
and type declarations described below. Outside those declaration forms it
remains an ordinary identifier:

```x2c
List meta = %(a b);

struct MetaHolder { int meta; };

int main(void) {
  meta = %(a b c);
  struct MetaHolder holder = { .meta = 3 };
  printf("%d %d\n", meta.len(), holder.meta);
  return 0;
}
```

```text
3 3
```

A bodyless `meta` prototype declares a native C function for compile-time
code. [Native C functions](#native-c-functions) below describes which
functions the compiler provides.

At file scope, `meta` can also advertise one initialized static value to
compile-time code:

```c
meta static const double pi = 3.1415;
meta static int compile_counter = 0;
```

The emitted program keeps the ordinary C declarations and initializers.
Compile-time code gets separate per-translation-unit values built from the
same source initializers, so compile-time mutation never changes the
eventual program's object. A function that reaches either a const or mutable
meta value is conservatively not folded; an explicit dollar call can still
run it during translation. Each value lives in bytes the compile-time session
owns, so taking its address and reading or writing through a correctly typed
pointer has the same aliasing effect as in C. `const` prevents compile-time
writes.

`meta` marks functions and values, not types. Compile-time code can use any
type the compiler sees: scalars, typedefs, classes with a `Var`
representation, and any complete struct, including an anonymous inline
`struct { ... } value`. A struct keeps its C layout; see
[C objects during compilation](#c-objects-during-compilation). Elsewhere
`meta` remains an ordinary identifier.

A type's methods are not callable at compile time on their own. Each
function needs its own `meta`:

```x2c
struct Cell { int value; };
typedef struct Cell Cell;

meta int Cell.twice(Cell cell) => cell.value * 2;

meta static int doubled(void) {
  Cell cell = { 21 };
  return cell.twice();
}

int main(void) {
  printf("%d\n", $doubled());
  return 0;
}
```

```text
42
```

Without `meta` on `Cell.twice`, the definition of `doubled` reports
`no binding for Cell_twice`.

## Native C functions

A bodyless `meta` prototype binds to the function of the same name that the
compiler itself links:

```x2c
meta double sin(double);
```

Compile-time code that calls `sin` runs the compiler's native copy. The
declared signature must match that function exactly. A mismatch is reported
at the declaration:

```text
sample.x:1:1: type: native meta function declaration does not match its target
  meta float sin(double);
  ^^^^
  note: name: sin signature: ((func ((double))) float)
```

The compiler links every function declared in `lib/cmath.x` and
`lib/clibc.x`. Both are part of the implicit prelude, so their functions need
no declaration of your own:

- `lib/cmath.x` declares all of C99 `<math.h>`, in both the `double` and
  `float` forms. This includes functions that return a second result through
  a pointer, such as `frexp`, `modf` and `remquo`.
- `lib/clibc.x` declares `abs`, `labs`, `llabs`, `atoi`, `atol`, `atoll`,
  `atof`, `strcmp`, `strncmp` and `timespec_get`.

The `<ctype.h>` functions are not included, because a C library may define
them as macros. A compile-time `String` passes to a `const char *` parameter,
so `$atoi("42")` answers 42.

A pointer argument can be the address of a compile-time local. The native
function writes through it, and the caller reads the result afterward:

```x2c
meta static double parts(double x) {
  int exponent;
  double mantissa = frexp(x, &exponent);
  return mantissa + exponent;
}

int main(void) {
  printf("%g %g\n", $parts(8.0), $sin(0.0));
  return 0;
}
```

```text
4.5 0
```

A prototype for a function the compiler does not link is accepted. A meta
function that calls it is diagnosed where it is defined:

```text
sample.x:2:1: macro: this function cannot run at compile time
  meta static int roll(void) => rand();
  ^^^^
  note: reason: no binding for rand
```

Other native functions will come from native extensions, which are not
available yet.

A native function binds into the compile-time session the first time
compile-time code calls it. An ordinary call to a native meta function is
never folded: `sin(1.0)` stays a call in the generated C. Write `$sin(1.0)`
to compute the value during translation.

## C objects during compilation

Compile-time code keeps C objects the way C does. Every struct local, and
every local whose address is taken, lives in native bytes. The compiler lays
out a struct in natural C layout, with the field order, sizes and alignment
from its own type information. The bytes belong to the running function's
frame and are released when that function returns, normally or by an error.

Field reads and writes, `&x`, `&s.f`, `p->f` and `*p` operate on those bytes.
Struct assignment copies bytes into the destination's existing storage, so an
address taken earlier stays valid. Passing a struct by value gives the callee
its own copy. Returning a struct copies it into the caller's storage before
the callee's storage ends:

```x2c
struct Pair { int x; int y; };

meta static struct Pair pair(int x) {
  struct Pair p = { x, x + 1 };
  return p;
}

meta static void bump(struct Pair *p) { p->x += 10; }

meta static int spare(struct Pair p) {
  p.x = 0;
  return p.y;
}

meta static int pairs(void) {
  struct Pair a = pair(1);
  int *ax = &a.x;
  a = pair(5);
  bump(&a);
  return *ax * 100 + spare(a) + a.x;
}

int main(void) {
  printf("%d %d\n", $pairs(), pairs());
  return 0;
}
```

```text
1521 1521
```

`ax` still points into `a` after the assignment, so `*ax` reads 15. `spare`
changes its own copy and returns 6, and `a.x` is still 15.

A pointer is a real address. Passing `&value` to a native function lets the
native code fill the object in place:

<!-- ignore: struct timespec needs the --system-headers translation option -->
```x2c,ignore
#include <time.h>

meta static long seconds_now(void) {
  struct timespec now;
  timespec_get(&now, 1);
  return now.tv_sec;
}
```

Compile-time code cannot read the `TIME_UTC` macro, so the sample passes its
value, which is 1 on the supported hosts. A struct from a system header needs
the `--system-headers` option, so that the compiler sees its declaration.
Without it, the definition reports that a struct or union has no
compile-time representation.

A pointer into a local whose function has returned is dangling, as in C;
using it is undefined behavior. A struct inside a `meta static` value, or in
a value that persists across REPL submissions, lives in storage the
compile-time session owns.

A struct result stays inside compile-time code. Inserting one into the
program with `$pair(3)` is diagnosed, because the compiler cannot write a
struct value as code.

These C shapes are not available at compile time:

- Unions.
- Structs with bitfields, array members or anonymous members. A meta function
  that uses one reports `a compile-time struct with no host layout`.
- Structs with alignment attributes.
- Structs under `#pragma pack`. The compiler does not detect packing and
  would lay such a struct out with natural alignment, so do not pass one to a
  native function from compile-time code.
- Arrays of structs, which a meta function reports as `an array of
  structs`, the address of an array element, and pointer arithmetic.
- `sizeof`, which is not evaluated at compile time. The parser does not
  accept `_Alignof`.

## When folding applies

Where both forms agree, the compiler may answer a call from the
compile-time form and put the answer in the call's place. A call is answered
this way only when all of the following hold.

- The callee is a `meta` function this unit defines. An imported one keeps
  the run-time call to the unit that emits it.
- Every argument has a value available to the constant reader: a literal,
  literal template, previously cached constant, or supported conversion of
  one. This optional path does not evaluate every resolvable expression;
  use an explicit dollar call when compile-time execution is required.
- Every argument already has its parameter's declared type.
- The result can be represented as typed program code: a scalar, String,
  Symbol, immutable List of representable elements, or boxed value.

This is an optimization, so you do not need to arrange for it. Its
equivalence depends on staying within the supported operation semantics;
see the missing-value differences below. Mutable Array and Map results,
callable values and arbitrary native addresses keep their calls. Immutable Lists are rebuilt through ordinary cons expressions;
String and boxed results use ordinary expression conversion and ownership.
This restriction on folding does not restrict internal meta return types.

## The compile-time subset

The following tables separate supported values, available operations and
current refusals. They catalog the implemented surface and known differences;
untested combinations are identified explicitly rather than implied to work.

### Values, declarations and mutation

The table describes current support, not a promise that every C operation
on a listed type works. The operation inventory below further limits calls.

| Value or construct | Construction, parameters and returns | Reads and changes during compilation |
| --- | --- | --- |
| Native integers, including `char`, narrow, unsigned and wide types | Numeric literals and typed locals; values can pass between meta functions and return from them. Width alone is not a prohibition. | Arithmetic, comparisons, casts, assignment and local compound updates. Source numeric literals use the shared scanner and type conversion rules, including integer base prefixes and `U`, `L` and `LL` suffixes. |
| `float`, `double` | Literals, locals, parameters and returns work, including `f`/`F` floating suffixes. | Arithmetic and scalar conversions work. Floating results can also be inserted as typed expressions. |
| `long double` | Typed parameters, returns and `L`-suffixed floating literals work. | Decimal and hexadecimal floating literals use the declared numeric precision. The focused checks do not establish parity for every extended-precision calculation. |
| `void` return | A meta helper may return true no-value, including a helper writing through an out-parameter. Bare return and fallthrough preserve that result. | Raw evaluator slots, `Var` parameters and `Var` results transport `void` without changing it to an empty List. Concrete typed value parameters and ordinary collections still reject it. |
| `String`, `Symbol` | String/symbol literals, computed strings and interpolation; parameters and returns. | String indexing reads character codes. Bound string methods work; indexed string writes do not. Symbols have the small method surface listed below. |
| `List` | Templates, braced/list-compatible initialization, conversion from `Array`; parameters and returns. | Index/association reads, traversal, matching and bound methods. No indexed assignment; build a new List instead. A returned data List is not automatically an expression. |
| `Array` | `[]`, `[a, b]`, `Array.new()`, conversion from `List`; parameters and returns. | Indexed reads/writes and the bound mutating methods. Contents can mix represented values and nest collections. |
| `Map` | `{}`, keyed literals, `Map.new()`; parameters and returns. | Keyed reads/writes and bound methods; represented collections and callable values can be stored inside it. |
| `Var` | Boxes represented numbers, strings, symbols, collections and callable values. | Only the exposed operations below. Compile-time `void` and an empty List remain distinct. Lisp conditions treat both as false; x2c runtime `Var.truth` still raises on `void`. |
| `Func` | Lambdas with typed or bare parameters, captures and references to available functions; parameters and returns between meta functions. | Dynamic calls and storage in collections work. This does not expose arbitrary native function-pointer calls. |
| C-style array declarations | A literal-sized one-dimensional array, such as `int a[3] = {1, 2};`, has compile-time storage. Omitted elements are filled with zero-like values. | Indexing and simple assignment work; passing the array to an indexed pointer parameter works in the tested case. At compile time the array is a dynamic Array of Var values, not native bytes; the running program uses native C array storage. See element/dimension limits below. |
| Pointers to locals | `int *p = &n;`, copying that pointer, and passing it to another meta function or a native function work. A local whose address is taken lives in native bytes, and the pointer is its real address. | `*p` reads and `*p = value` writes the local. Pointer arithmetic and the address of an array element are not supported. |
| Structs | Named, inline and nested locals; initialization, assignment, by-value arguments and returns, with C copy behavior. | Fields and addresses refer to native bytes in C layout. Assignment keeps existing field addresses; storage ends when the function returns. See [C objects during compilation](#c-objects-during-compilation). |
| Native functions | The functions in `lib/cmath.x` and `lib/clibc.x`, which the compiler links. | Explicit dollar evaluation and meta bodies can call them, including through output pointers. Ordinary calls are not folded. See [Native C functions](#native-c-functions). |
| System-header structs | `--system-headers` supplies the header declarations. A local `struct timespec` can be passed to `timespec_get`. | Unions and structs with bitfields, array members, anonymous members or alignment attributes are not available. |
| `File`, buffers and other resource types | No general compile-time constructor/operation surface is installed for these types. A declaration or opaque type name alone does not make the resource usable. | For example, `File.open` has no binding. Use the compiler's explicit text-embedding operation for source-dependent text. |

Collections hold values, not arbitrary native memory. Nested collections keep
references to their contained objects; mutating a shared `Array` or `Map`
changes that object.

Native array coverage is narrower than C's array model. Integer arrays have
fixture coverage; focused probes also cover `double` and `String` elements.
A dimension such as `1 + 1` is rejected even though C can compute it, and a
nested braced initializer for `int a[2][2]` is rejected. The implementation
stores a C-style array in a dynamic container, using its first declared
dimension; this is not general multidimensional or native-layout support.
Element initialization applies the declared scalar conversion. For example,
`unsigned char a[1] = { n }; return a[0];` with 257 returns 1 both during
compilation and at runtime. Signed-byte, float-rounding and floating-to-integer
initialization also have differential checks. Other element types, array
decay/alias combinations and every zero-initialization case remain coverage
gaps.

A null-pointer constant such as `(char *) 0` can supply the default character
set for `String.strip`. The preprocessor name `NULL` is not resolved by the
compile-time expression reader; using that name alone still reaches the
file-scope-state restriction. This does not imply a native pointer dereference
or arbitrary address support.

These two functions demonstrate a supported address and a supported chain:

```x2c
meta static void meta_set(int *out) { *out = 9; }

meta static int meta_address(void) {
  int n = 1;
  meta_set(&n);
  return n;
}

meta static int meta_parts(String path) => path.split(".").len();

int main(void) {
  printf("%d %d\n", $meta_address(), $meta_parts("a.b.c"));
  return 0;
}
```

```text
9 3
```

The chain calls `String.split`, then `List.len`.

### Which library operations are available

A method uses its ordinary resolved call, so `text.len()` and
`String.len(text)` reach the same operation. Chaining adds no separate
restriction: every call in the chain must be available.

The [complete API coverage report](meta-api-coverage.md) lists every exported
operation on String, List, Array, Map, Symbol and Var, including generated
methods and advanced internals. It records signatures, binding locations,
verified examples, reproduced failures and untested operations separately.
The optional inventory tool reads every standard compiler session layer;
searching only one binding file misses operations such as `List.car`,
`List.cdr` and `Var.cons`.

A recent batch added 19 bindings; it did not complete the API surface.
The ordinary `List` and `Var` selectors `caar`, `cadr`, `cddr` and `caddr`
reuse those same operations. `String`, `List`, `Array` and `Map` expose their
`str` and `repr` rendering; `Symbol` also exposes `repr` and `compare`, and
`Var.kind` reports a value's kind. These calls use the existing value
implementations rather than a separate formatting or comparison algorithm.

Iterator producers and functional collection operations are also available in
x2c-style meta functions. Omit the native destination argument when an
iterator is consumed by the same expression. The compile-time binding allocates
the iterator in the session `Scope`; it still uses the native lazy producer and
borrows its source and any callback.

```x2c
meta int key_count(Map values) => values.keys().count();

meta List shifted(int amount) {
  List result = range(1, 3, 1)
    .map(%!(Var value) => value + amount);
  return result;
}
```

`List`, `Array` and `String` mapping and filtering use the same native
operations with an adapter for the interpreted callback. Lazy `Iter` mapping,
filtering, pairing and collection work the same way. Calls made as Lisp treat
nil and `void` as false; callbacks in x2c-style meta functions retain ordinary
`Var` truth.

A binding name alone is not proof of runtime-equivalent behavior. A missing
binding also does not explain why it was omitted. Some operations need only an
adapter over existing values; others need native pointer arguments or resource
ownership. Explicit caller-supplied `struct Iter` storage remains a runtime
contract and has no compile-time representation. Use the destination-free form
inside a meta function. `List`, `Array` and `Iter` folds preserve a true `void`
no-seed argument. Empty or exhausted `Iter.next`, `find`, `min` and `max` calls
return true runtime `void`, distinct from Lisp nil.

Other installed meta functions and the compiler operations declared in
`meta.x` extend this surface; including a normal function declaration does
not install its body for compile-time execution.

Missing List/Array/Map lookups and removals preserve runtime `void`; they no
longer become an empty List in the evaluator. This covers List `getindex`,
`last`, `assoc`, `get`, `caar`, `cadr` and `caddr`; Array `getindex`, `setindex`,
`take_last`, `shift`, `remove` and `insert`; and Map `get`, `getindex` and `del`.
`caar` stops when either selection is absent. Ordinary Lists, Arrays and Maps
still reject `void` as an element, key or value, so a rest call cannot pack it
into its argument List.

Status operations with output parameters receive the addresses of
compile-time locals. `String.try_long`, `String.try_double`,
`String.try_next`, the three `List.try_*` match operations, `Map.try_get`,
`Map.try_del` and `Symbol.try_new` are the native operations themselves,
writing through those addresses as they do at run time. A failed call
therefore leaves every output unchanged; `String.try_next` and
`List.try_search` write their paired outputs together.

`Array.heap_pop`, `Map.get_hashed`, `Var.getindex` and `Var.null` preserve
their native `void`-versus-`Null` results. `Var.clone_wide` creates a fresh
session-`Scope` box for a wide value and returns true `void` for a nonwide
value.

Lisp conditions treat `void` as false while the normal x2c `Var.truth` contract
still raises `<void-op>`; compare explicitly with `void` when both forms must
agree.
The compiler loads several binding layers, including `etc/init.xlisp`,
`etc/lisp-values.xlisp` and `etc/comptime.xlisp`; supported body forms live in
`src/comptime.x`.

### Control flow and current rejections

`if`, conditional expressions, short-circuit boolean operations, `while`,
`for`, `do`, `break`, `continue`, recursion, `foreach`, `match`, templates,
lambdas and destructuring have compile-time support. A `switch` may share
labels and its final arm may end normally; an earlier arm must not execute
through to the next one. Recursive calculations remain subject to the
compiler's evaluation limits.

Some combinations still decline: `switch` with a subject needing a temporary
binding on a loop path; destructuring a source needing such a binding on a
loop path; and taking the address of a destructured local. Match patterns
must fold at lowering time, so a pattern interpolating a local value is not
generally supported. These are binding/lowering gaps, not fundamental
restrictions on loops, destructuring or pattern matching.

Mutation is position-sensitive. `n++` as a statement is supported, but
`return n++;` is not. `a[i] = a[i] + 1;` and `*p = *p + 1;` are supported
shapes; `a[i] += 1;` and `(*p)++;` are not. An assignment used as an
expression is not a general substitute for a statement.

The table separates present restrictions from design assessment. "Gap"
means feasible in principle, not scheduled or promised support.

| Currently unsupported | What would be needed; fundamental or gap? |
| --- | --- |
| `goto`, switch fallthrough | **Gap:** control-flow lowering that preserves the transfer. |
| Postfix expression values, compound updates to indexed/dereferenced places | **Gap:** preserve the old result and evaluate the destination once. |
| Computed native-array dimensions, general multidimensional arrays and missing element conversions | **Gap:** extend the represented array shape and typed operations. |
| Structs with bitfields, array members, anonymous members or layout attributes; arrays of structs | **Gap:** compute a layout for these shapes. Other structs use native bytes in C layout. |
| Unions, pointer arithmetic and addresses of array elements | **Gap:** model overlapping storage and arrays in native bytes. A pointer to an actual future runtime object cannot be dereferenced during compilation; that is a **phase boundary**. |
| `defer` | **Gap** for deferred execution in general. Explicitly freeing evaluator-owned objects conflicts with the **current ownership model**; it is not an argument that all deferred actions are impossible. |
| `try`, `catch`, `finally`, `raise` in a meta body | **Gap:** exception transfer and cleanup need compile-time modeling. Evaluation failures can still become compiler diagnostics. |
| Missing library/resource operations, including `File.open` | **API gap:** implement bindings and appropriate resource lifetimes. Compile-time file I/O is possible in principle; it is not prohibited by the phase boundary. |
| Loop-path temporary bindings, address-taken destructured locals, nonfolded match patterns | **Gap:** preserve required bindings and support pattern evaluation at the appropriate time. |
| Native `sizeof` expressions | **Gap:** provide the compile-time value of the queried layout; `sizeof(int)` currently declines as an unsupported expression. |
| Named enum values | **Gap:** make the enumerator's numeric value available to the lowerer. |
| Reading future runtime mutable state | **Fundamental phase boundary:** that program state does not exist yet. Separate compile-time state is possible but is not the same state. |
| Mutable container and callable result insertion | **Gap:** preserve ownership, mutability and identity when constructing a runtime value. See the next section. |

For example, these are rejected definitions:

<!-- ignore: a union has no compile-time representation -->
```x2c,ignore
union Bits { int i; float f; };

meta int meta_union(void) {
  union Bits bits = { 1 };
  return bits.i;
}
```

<!-- ignore: compound update of an indexed destination is unsupported -->
```x2c,ignore
meta int meta_update(void) {
  int values[2] = { 1, 2 };
  values[0] += 1;
  return values[0];
}
```

Their diagnostic reasons identify the union and the unsupported indexed
update respectively.
The compiler checks the body when installing the meta definition, so an
unused function or an untaken branch does not hide an unsupported construct.

### Lifetime and state

Compile-time allocations belong to the evaluator session. Do not free,
close, or otherwise take over evaluator-owned objects: the ordinary resource
cleanup API is not available, and `defer` is rejected. A returned collection
can be consumed by another meta function while the session is alive; it does
not become a pointer to the eventual program's heap. Struct locals and
address-taken locals are released when their function returns, as described
in [C objects during compilation](#c-objects-during-compilation). A local
address is useful within the calculation, not a portable constant address to
embed in C.

The emitted runtime function still follows the runtime's ownership rules.
Evaluator cleanup does not add cleanup to that function. In particular,
allocating scratch collections in a dual-form body does not by itself prove
that repeated runtime calls have the desired lifetime behavior.

Ordinary file-scope variables remain unavailable, directly or through another
function. Mark one `meta static` when compile-time access is intended. Its
evaluator instance uses a separate per-unit table and does not expose future
runtime state. Compiler-only functions that reach compiler operations use the
same isolated table.

## Results: compute, insert, or fold

A meta function can pass and return numeric, collection and callable values
inside the evaluator. Inserting a result into the program adds a separate
requirement: the compiler must construct code representing that value.

| Result | Explicit `$helper(...)` insertion | Automatic ordinary-call folding |
| --- | --- | --- |
| Native integers and floating values | Preserves the numeric Var family, including width, signedness and floating precision. | Uses the declared result type. |
| Computed string | Inserts a quoted C string literal. | Constructs a String expression when the declared result is String. |
| `Symbol` | Inserts a Symbol literal. | Constructs a Symbol expression. |
| Identifier or nonempty code `List` | Binds the returned code through normal compiler binding and typing. A data List is not automatically an expression. | A declared List result is reconstructed as data through ordinary cons expressions if every element is representable. |
| Boxed `Var` | Insertion follows the contained value. | Converts a representable contained value to Var. |
| `Array` or `Map` with immutable representable descendants | Constructs a fresh mutable root through the ordinary literal constructors. | Keeps the call. |
| Struct value | Diagnosed; the compiler cannot write a struct value as code. | Keeps the call. |
| Nested mutable collections, `Func` or arbitrary native address | No direct materialization of the evaluator object. | Keeps the call. |

An inserted Array or Map is a snapshot of the compile-time result. Each runtime
execution of that expression allocates a fresh root in the current Scope, just
like `[]` or `{}`; assigning it to another variable still aliases that root.
Array order and element types are preserved. Map keys use their ordinary runtime
key semantics, but reconstruction does not promise the same traversal order.
A boxed Var may contain the resulting root.

Elements, keys and values may contain scalars, Strings, Symbols, or immutable
Lists of those values. Nested mutable objects, including mutable objects hidden
inside Lists, remain unsupported. That restriction prevents silently copying
shared objects or cyclic graphs. Ordinary calls returning mutable containers
remain runtime calls; explicit insertion does not authorize that optimization.

The same functions can be called during compilation or with ordinary C-style
calls at runtime:

```x2c
meta static double meta_half(double n) => n / 2.0;
meta static int meta_whole(void) => (int) meta_half(9.0);
meta static String meta_label(String stem) => stem.upper() + "!";

int main(void) {
  printf("%.1f %d %s\n", $meta_half(9.0), $meta_whole(),
    $meta_label("ready"));
  printf("%d %s\n", meta_whole(), meta_label("ready").str());
  return 0;
}
```

```text
4.5 4 READY!
4 READY!
```

Scalar conversion is shared by explicit evaluation and eligible folding.
Floating constants retain their binary value using hexadecimal literals;
nonfinite values use the native compiler's infinity/NaN expressions.
The remaining container work must account for identity, shared references,
mutation and ownership. A pointer into the evaluator is never a valid address
to embed in the future program.

## Compile-time arithmetic and evidence

Native scalar conversions are applied at typed declarations, assignments,
casts, arguments between meta functions and returns. Array/List and
Symbol/String conversions also have explicit support. This does not make
all casts meaningful: pointer arithmetic and reinterpreting an address are
not supported.

The `meta-differential` compiler fixture checks selected narrow/unsigned
arithmetic, wide intermediate values, floating operations and conversions
against runtime calls. The `comptime-lowering`, `meta-import` and
`meta-cursors` fixtures cover collections, callable values, local addresses,
method chaining and iteration. They do not prove every operation/type
combination equivalent. The `meta-records` and `meta-record-*` fixtures
cover struct layout, copies and addresses, and the `meta-native-*` fixtures
cover native calls. The `meta-numeric-lowering` fixture checks numeric
suffixes and array element conversions against runtime results. Other array
conversions, extended-precision parity, all callback signatures and resource
lifetimes are not covered. This catalog covers the installed operation
surface and identified lowering boundaries, not an exhaustive proof of every
combination of C and x2c syntax.

## From values to code

So far we have passed values in and calculated values out. A macro works
with the code being compiled. A `meta` function can take that code as a
`List`, inspect it, and return new code for the compiler to insert.

For this part, read [Compile-time Macros](macros.md) first. The macro declares
what code to capture; the `meta` function implements the transformation
in x2c. Include `meta.x` to use the compiler's `x2c_*` operations.

## Calling a meta function from a macro body

A macro body can call a meta helper with `$helper(args)`. Passing a captured
hole directly supplies its code to the helper; it does not evaluate the
future runtime expression. This form works for code transformations such as
the field query below. Complete captures also retain their source information
for text and location queries; constructed subtrees do not acquire it.

```x2c
#include "x2c.x"
#include "meta.x"

typedef struct Point { int x, y, z; } Point;

meta static List field_count(List receiver) =>
  x2c_literal_int(x2c_type_fields(x2c_syntax_type(receiver)).len());

macro Expression $probe.count(Expr $value) => $field_count($value);

int main(void) {
  Point p = { 1, 2, 3 };
  printf("count %d\n", $probe.count(p));
  return 0;
}
```

```text
count 3
```

The macro body is one call and nothing else. That is the usual shape: the
macro declares the holes and the result kind, and the `meta` function does
the work.

What the function returns decides what the expansion is. A `List` one of the
compiler operations built represents code. `x2c_literal_int`, `x2c_literal_string`
and `x2c_literal_symbol` each return an expression holding a value.

## Source templates from meta functions

A Unit or Statement macro used as an expression inside a meta function
constructs a deferred template invocation. Its arguments are values computed
by the meta function. The returned code expands when inserted into the
program, using ordinary macro substitution, scope and binding rules.
Expression macros retain their usual expansion behavior.

```x2c
macro Unit $make_function(Name $name, Expr $result) {
  int $name(void) { return $result; }
}

meta static List build_function(String name, int n) {
  List node = $make_function(name, n * 2);
  return %($node);
}

macro Unit $make_answer() { $build_function("answer", 21)... }

$make_answer();
int main(void) {
  printf("%d\n", answer());
  return 0;
}
```

```text
42
```

The constructor returns one code node. The helper wraps it in a List because
`...` inserts a sequence of nodes. It does not return an already expanded
function declaration for the helper to inspect. Name, Type, parameter and
statement captures still follow the source macro's declared hole kinds.

The reverse gradient generator in `lib/autodiff.xmacro` uses this pattern.
Its `ad_reverse_function` returns an invocation of the `ad.gradient` source
macro. The macro contains the generated function declaration, tape storage,
reverse-pass label and cleanup. Meta helpers compute the parameter and
statement sequences. The macro owns the fresh scratch names and passes those
same names to the fragment helpers, keeping all generated references in the
intended function scope.

## What the compiler answers

`lib/meta.x` declares the compiler operations a `meta` function can call.
Each is a plain function whose name is the compile-time Lisp name with `_`
for `.`, so `x2c.type.fields` is `x2c_type_fields` from x2c. They are grouped
here by the task, not by signature; the
[module reference](../library/modules/meta.md) lists every declaration, and
the [language reference](../reference/language.md#the-same-operations-from-x2c)
gives their semantics.

The code builders are `meta` bodies in `lib/meta.x`. The Lisp functions
call those same implementations. The three literal-building functions also
check their Lisp arguments. Builders that only assemble Lists can also run in a
linked program; `x2c_expr_field` and `x2c_expr_cast` still need compiler
queries and therefore remain compile-time only. The same is true of
`x2c_decl_make`, `x2c_param_make` and `x2c_type_members`;
`x2c_stmnt_make`, `x2c_stmnt_return` and `x2c_block_make` only assemble
code.

**Building identifiers, literals and expressions.** `x2c_ident` checks a
name and returns identifier code. `x2c_literal_int`,
`x2c_literal_string` and `x2c_literal_symbol` return an expression holding
a value. `x2c_expr_ident`, `x2c_expr_field`, `x2c_expr_index`,
`x2c_expr_call`, `x2c_expr_composite` and `x2c_expr_cast` assemble the
six expression shapes a generator needs. Compose them rather than writing
node shapes by hand, so the compiler binds and types the result:

```x2c
#include "x2c.x"
#include "meta.x"

meta static List call_of(String callee, List argument) =>
  x2c_expr_call(x2c_expr_ident(x2c_ident(callee)), %($argument));

macro Expression $probe.twice(Expr $value) => $call_of("twice", $value);

static int twice(int n) => n * 2;

int main(void) {
  int n = 21;
  printf("twice %d\n", $probe.twice(n));
  return 0;
}
```

```text
twice 42
```

**Asking about types and fields.** `x2c_syntax_type` answers the canonical
`Type` of an expression or binding. `x2c_type_fields` answers the named
fields of a struct or union `Type`, each as a metadata row whose first
element is the field name. `x2c_type_layout`, `x2c_type_parts`,
`x2c_type_resolve` and `x2c_type_value` answer the remaining
generated-code questions. `x2c_method_resolve` answers which operation a
member call selects. These answers live in the compiler's symbol table, so
a macro body cannot derive them from the code it captured.

**Source text and location.** `x2c_source_text` returns the text the
developer wrote for a captured hole. `x2c_binding_spelling` returns the
name a binding was declared with. `x2c_invocation_file`,
`x2c_invocation_line` and `x2c_invocation_column` give the site of the
macro invocation. `x2c_embed_text` reads a file beside the source and
records it as a translation dependency.

**Failing with a diagnostic.** `x2c_diagnostic_fail` reports a message at
the invocation and stops the expansion. It does not return. Use it when the
argument is wrong in a way the macro can see:

```x2c
#include "x2c.x"
#include "meta.x"

meta static List one_word(Var node) {
  String text = x2c_source_text(node);
  if (text.contains(" "))
    x2c_diagnostic_fail("this argument must be one word", %());
  return x2c_literal_string(text);
}

macro Expression $probe.word(Expr $value) => $one_word($value);

int main(void) {
  int seconds = 90;
  printf("word %s\n", $probe.word(seconds));
  return 0;
}
```

```text
word seconds
```

The helper receives the complete capture, including the source information
required by `x2c_source_text`. A computed subtree is code data, not a new
source capture.

Writing `$probe.word(seconds * 2)` instead reports the message at that
invocation:

```text
sample.x:15:23: macro: this argument must be one word
  printf("word %s\n", $probe.word(seconds * 2));
                      ^
```

Two signatures differ from the corresponding Lisp functions.
`x2c_expr_call` takes its arguments as one `List`, and `x2c_type_value`
returns `int`.

## Functions that need the compiler

Compiler queries exist only inside a compiler. A `meta` function that
calls one, directly or through another `meta` function, therefore has no
valid runtime form, and the compiler emits no definition for it. A body
containing an explicit dollar-prefixed meta call or a source-template
constructor is also compile-time-only, as are its meta callers. A call to
one from a runtime body is diagnosed where it is written. Calling
`field_count` from an earlier section at run time gives:

```text
sample.x:19:22: macro: 'field_count' can only be called at compile time
    int n = field_count(point);
                       ^
  note: reason: it reaches a compiler operation, so no unit emits a
  definition for it; call it from a macro or another meta function
```

In the complete shape example below, the generated C mentions none of `shape_fields`,
`shape_names` or `shape_reads`.

A `meta` function that needs no compiler query, like `poly` above,
keeps both forms and is emitted normally.

## A complete example

Two files. The first is a `.xmacro` holding the `meta` functions and the
macros that call them. `shape_fields` asks the compiler what a struct holds.
`shape_names` and `shape_reads` turn that answer into code.

<!-- ignore: shape.xmacro is the external file being illustrated -->
```x2c,ignore
/* The named fields of a struct-typed expression, in declaration order. */
meta static List shape_fields(List receiver) =>
  x2c_type_fields(x2c_syntax_type(receiver));

/* One `String` literal holding those field names, comma separated. */
meta static List shape_names(List receiver) {
  Array names = [];
  foreach (List field, shape_fields(receiver)) names.push(field.car());
  return x2c_literal_string(String.join(", ", names));
}

/* `{ p.x, p.y, p.z }`, built from the fields rather than written out. */
meta static List shape_reads(List receiver) {
  Array reads = [];
  foreach (List field, shape_fields(receiver))
    reads.push(x2c_expr_field(receiver, field.car()));
  return x2c_expr_composite(reads);
}

macro Expression $shape.names(Expr $value) => $shape_names($value);

macro Expression $shape.reads(Expr $value) => $shape_reads($value);
```

The second file imports it and uses the macros. Imports still use the
compiler's `$(import "...")` form; this is a loading operation, not a meta
function call.

<!-- ignore: this program imports the shape.xmacro file above -->
```x2c,ignore
#include "x2c.x"
#include "meta.x"

$(import "shape.xmacro")

typedef struct Point { int x, y, z; } Point;

int main(void) {
  Point p = { 2, 3, 4 };
  int reads[3] = $shape.reads(p);
  printf("names %s\n", $shape.names(p));
  printf("reads %d %d %d\n", reads[0], reads[1], reads[2]);
  return 0;
}
```

```text
names x, y, z
reads 2 3 4
```

The field names never appear in the program. The compiler supplied them, and
the `meta` functions built `"x, y, z"` and `{ p.x, p.y, p.z }` from them.

## Sharing a `meta` function between units

A `meta` function written in a `.x` file belongs to that unit. Including that
file elsewhere shares its declaration, the way including any `.x` file does,
and the declaration alone has no compile-time form: another unit can call it
at run time, and cannot call it during translation.

To share one, put it in a `.xmacro` that each unit imports. A `.xmacro` file
may hold `meta` functions beside the macros that call them, and importing it
installs their compile-time forms in the importing unit. The unit that imports
the file includes `meta.x`, because a `.xmacro` borrows the consuming unit's
symbol table:

```text
#include "x2c.x"
#include "meta.x"

$(import "shape.xmacro")
```

Importing the same file twice contributes one copy of each definition. A
`.xmacro` may import another `.xmacro`, and a `meta` function two levels
down reaches the consuming unit the same way.

The run-time forms are separate from this. A unit emits a definition only
for the `meta` functions it calls at run time. The storage class says what
it emits: `static` gives that unit its own copy, and a public name is the
one copy the program links, exported by the reaching unit's header.

## Lisp interoperability

Use the x2c calls above for ordinary meta work. The following notes apply
when importing or calling Lisp helpers, or working with the compiler session.

The compiler loads Lisp support into an embedded evaluator. Some loaded files
are generated output: `etc/builtin-macros.xlisp` comes from
`etc/builtin-macros.x` and `etc/builtin-core.xlisp` through
`tools/gen-lisp-init.py`. Seeing Lisp in that generated file does not mean the
algorithms still need a separate handwritten Lisp implementation. The support
layer and the generated functions have different source owners.

### Names the compile-time library already defines

A unit's compile-time session inherits the compiler's own Lisp library and
cannot replace one of its definitions. A macro file or a `$(...)` form that
defines an inherited name reports:

```text
sample.x:2:1: macro: compile-time Lisp evaluation failed
  $(defun filter (a b) 42)
  ^^
  note: form: (defun filter (a b) 42) error: (bad-state (operation "def")
  (why "inherited") (name filter))
```

The library holds many ordinary words, so the name to avoid is often one you
would reach for first: `filter`, `last`, `map`, `search`, `len` and `apply`
are all defined. Give your own definition a different name, or a prefix of
your own.

### `eval` reads globals only

A lambda's body reads its captures and then the session's globals. `eval`
is an ordinary procedure, so the form it is given is evaluated in the
globals alone and does not see the bindings around the call:

```text
(let ((z 7)) (eval (quote (add z 1))))   error: (unbound (name z))
```

Pass the value instead of the name: `(eval (list (quote add) z 1))`.

A `let` binding is not visible inside its own initializer, so a helper that
calls itself by name must be a `defun`:

```text
(let ((h (lambda (n) (h n)))) (h 3))   error: (unbound (name h))
(defun h (n) (h n))                    reads its own name
```
