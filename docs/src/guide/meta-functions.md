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
   meta function and inserting it with `$helper(...)` have different limits.

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

## Typed Func calls during compilation

Inside a meta body, a `Func` retains its callable signature through parameters,
returns and collection storage. Lambdas and available named functions use the
same argument checks as native calls. For example, an `unsigned char`
parameter receives 1 from 257, and a `float` parameter rounds 16777217 to
16777216. A typed result converts before it is boxed as `Var`.

The callee is evaluated once. Arity is checked before argument evaluation;
arguments are prepared once from left to right, then the adapter checks and
converts them in that order. A reference parameter takes the live address of
the caller's object without reading it, including an output-only local:

```x2c
meta int write_answer(int n) {
  int output;
  Func write = %!(int &value) => value = 41;
  (void) write(output);
  return output + n;
}
```

`$write_answer(1)`, `write_answer(1)` and a runtime call with argument 1 all
produce 42. References to locals, fields, dereferenced pointers and C-array
elements share the original storage. Passing one object twice or forwarding a
reference preserves immediate aliasing. Leading qualifiers may be strengthened;
the remaining source type must match exactly. An invalid lvalue, null address,
different underlying type or discarded qualifier raises `bad-types`. A
concrete typed value parameter refuses `void`; a `Var` parameter transports it.

## Ordinary calls run in the program

A call without `$` always calls the compiled function, even when every
argument is a literal. `poly(7)` stays a call in the generated C; write
`$poly(7)` to have the compiler calculate it.

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
and protocol adoptions described below. Outside those declaration forms it
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
eventual program's object. An explicit dollar call reads and writes the
compile-time values; an ordinary call reads the program's. Each value lives in bytes the compile-time session
owns, so taking its address and reading or writing through a correctly typed
pointer has the same aliasing effect as in C. `const` prevents compile-time
writes.

A function-local `static` has no compile-time lowering, so a meta function
that declares one declines like any other unsupported form.

`meta` marks functions, values and protocol adoptions, not types.
Compile-time code can use any type the compiler sees: scalars, typedefs,
classes with a `Var` representation, and any complete struct, including an
anonymous inline
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

Two kinds of function follow a rule. An iterator operation takes its
destination last: its last parameter and its result are `Iter`. Compile-time
code may omit that destination; the call then allocates one with `Iter.new`
before calling the native operation. A declared `Func` parameter matches any
`Var` parameter of the compiler's target, which receives the compile-time
callable and adapts it.

A `meta` protocol adoption, such as `meta protocol Iter(List);`, declares each
witness of that conformance the way a bodyless prototype would.

The compiler checks a `meta` body's storage against what each native callee
allocates and keeps; see [Regions](regions.md). The runtime's own functions
state this in a table. For any other native function, the compiler infers
it from the signature, where a handle is any type other than a scalar,
`Var`, `Symbol`, `String`, `List`, `Array`, `Map` or `Func`. A parameter
that points at one of those, such as a `const char *` or an `int *` result,
is not a handle.

The compiler links every function declared in `lib/cmath.x` and
`lib/clibc.x`. Both are part of the implicit prelude, so their functions need
no declaration of your own:

- `lib/cmath.x` declares all of C99 `<math.h>`, in both the `double` and
  `float` forms. This includes functions that return a second result through
  a pointer, such as `frexp`, `modf` and `remquo`.
- `lib/clibc.x` declares `abs`, `labs`, `llabs`, `atoi`, `atol`, `atoll`,
  `atof`, `strcmp` and `strncmp`.

The `<ctype.h>` functions are not included, because a C library may define
them as macros. A compile-time `String` passes to a `const char *` parameter,
so `$atoi("42")` answers 42.

The compiler also links the pure text operations of three optional modules:
`Json.parse`, `Diff.lines`, `Diff.unified`, and `Path.join`, `dirname`,
`basename`, `extension` and `stem`. Include `json.x`, `diff.x` or `path.x`
to call them from a `meta` body. They give the same results as at run time.
The Path operations that read the filesystem are not available.

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

Your own native functions come from a
[native module](#native-modules).

A native function binds into the compile-time session the first time
compile-time code calls it. `sin(1.0)` stays a call in the generated C;
write `$sin(1.0)` to compute the value during translation.

## Native modules

A native module lets compile-time code call functions from your own
project. Declare each function with a bodyless `meta` prototype and define
it as usual:

```x2c
meta int triple(int);

#pragma private

int triple(int x) { return 3 * x; }
```

Save that as `helpers.x` and build it as a module:

```sh
x2c build --kind meta-module --output helpers.so helpers.x
```

The module contains every function that a bodyless `meta` prototype in its
own sources declares. Code that includes the prototype can call the
function during translation when the compiler loads the module:

<!-- ignore: the sample needs helpers.x and the module built from it -->
```x2c,ignore
#include <stdio.h>
#include "helpers.x"

meta static int nine(void) => triple(3);

int main(void) {
  printf("%d %d\n", $nine(), triple(5));
  return 0;
}
```

```sh
x2c run --native-module helpers.so helpers.x main.x
```

```text
9 15
```

`$nine()` runs the module's `triple` during translation. The ordinary call
`triple(5)` uses the copy linked into the program, so `helpers.x` is also
one of the program's sources. `--native-module` works with `translate`,
`build`, `run`, and `repl`, and the REPL accepts the same bodyless
prototype.

A module function may take or return a handle:

- A returned handle is a fresh allocation in the active `Scope`. Allocate it
  with `Scope.malloc`, so that compile-time code can release it with
  `Scope.free` or hold it in an `$auto` local.
- A handle argument is borrowed for the call. Keeping it after the call
  returns is not supported.
- A handle whose type is a runtime class, or adopts `Var` or `Cleanup`, is
  owned by its cleanup wherever it appears.
- A function that takes a handle and returns one, when neither is owned by
  its cleanup, might return or keep its argument. Its ownership cannot be
  inferred, so its prototype is rejected:

```text
helpers.x:3:1: type: unproved native meta lifetime
  meta Widget widget_wrap(Widget inner);
  ^^^^
  note: name: widget_wrap signature: ((func ((* struct "Widget"))) * struct "Widget") it might return or keep its argument; ownership cannot be inferred
```

The compiler loads a module only when an option or a manifest names it.
Without `--native-module`, `nine` reports `no binding for triple`. In a
manifest, a target lists the module targets its translation loads:

```toml
[target.helpers]
kind = "meta-module"
sources = ["helpers.x"]

[target.app]
sources = ["helpers.x", "main.x"]
native-modules = ["helpers"]
```

A module target builds before the targets that load it, and a changed
module retranslates them. A target binds only the modules it names, even
when an earlier target in the same build loaded others.

A module's functions bind like the functions the compiler links. The
prototype's signature must match the one the module was built from, and a
mismatch is reported at the declaration. A function the compiler links
takes precedence, and the prototype reports a warning that the compiler's
own function hides the module's. When two named modules define the same
name, the one named first supplies it, and the prototype reports a
warning.

A module runs inside the compiler and uses the compiler's own runtime, not
a copy of it. Only the compiler that built a module can load it, so a
module must be rebuilt after the compiler changes. The compiler checks this
before it loads any of the module's code:

```text
x2c: error: native module 'helpers.so' was built by another compiler; rebuild it
```

Every function the module exports needs a bodyless `meta` prototype in the
module's sources, and a module whose sources declare none fails to build.

A module can call most of the runtime, because the compiler links every
runtime module that registers no `Var` class of its own. This holds for a
compiler built from a checkout and for one `x2c bootstrap` installs. The compiler
leaves out the modules whose classes would take up rows of the fixed
32-row class registry at startup: Automatic Differentiation, `Regex`,
typed Arrays and Maps, `Thread` and `Mutex`, the scripting library, and
the modules that need them. A module that calls one of their functions
fails to build on macOS, and the link error names each missing symbol:

```text
Undefined symbols for architecture arm64:
  "_Regex_compile", referenced from:
      _groups in rx-634299d6.o
```

On Linux the same module builds, and loading it fails with an error that
names the missing symbol. A loaded module stays loaded until the compiler
exits. Native modules work on macOS, Linux and WSL. On other platforms,
loading one reports that native modules are not supported.

## C objects during compilation

Compile-time code keeps C objects the way C does. Every struct local, and
every local whose address is taken, lives in native bytes. C arrays use
contiguous native element storage as well. The compiler lays
out a struct in natural C layout, with the field order, sizes and alignment
from its own type information. The bytes belong to the running function's
frame and are released when that function returns, normally or by an error.

Field reads and writes, `&x`, `&s.f`, `p->f`, `*p` and `p[i]` operate on
those bytes. A `bool` field is one byte, and a value reaching `bool` becomes 0
or 1; it reads as the int C promotes it to. An enum field is an `int` when
the enum is not packed and every enumerator initializer has an integer type
no wider than `int`, or names the enum itself. Any other enum may be wider
or narrower in C, so it has no compile-time layout. Compile-time code reads
every enum value as a signed `int`. Clang and GCC make an enum with no
negative enumerator an `unsigned int`, so a negative value stored in such an
enum compares differently: at compile time it stays negative, and at run
time it is a large unsigned value.
A pointer parameter can also receive a local C array,
which `p[i]` indexes the same way. A pointer compares with `NULL` by address
and tests false at the null address.
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
native code fill the object in place. Only a struct defined in an x2c unit has
a compile-time layout; a struct declared in a C header, such as
`struct timespec`, is declined in compile-time code.

A compile-time call frees its locals and parameters when it returns. A
`meta` function whose body lets the address of one outlive the call is
rejected where it is defined, with an error at the statement where the
address leaves: a `return`, a store into a `meta static`, or a store through
a parameter or through a pointer whose target the compiler cannot identify.
A local array counts as the address of its first element. The check follows
the address through pointer locals, either arm of `?:`, and the `meta`
functions defined before the caller:

<!-- ignore: the definition of leak is rejected on purpose -->
```x2c,ignore
struct Box { int value; };

meta static int *field_of(struct Box *box) { return &box->value; }

meta static int *leak(int seed) {
  struct Box box = { .value = seed };
  return field_of(&box);
}
```

`field_of` is accepted, because the object it borrows from belongs to its
caller. `leak` is rejected at its `return`, because `field_of` hands back an
address inside `box`.

The check is the region check of ordinary code, and every finding it makes
in a `meta` body is an error, including a value from a `Scope` region that
outlives the region. In ordinary code the same findings are warnings; see
[The Region Model](regions.md).

The check does not yet follow every path an address can take. These still
translate, and using the address after the call returns is undefined
behavior, as in C:

- an address stored in a field of a local struct that is then returned by
  value or assigned to a `meta static` struct;
- an address computed with pointer arithmetic or a cast;
- an address passed to a native function that keeps it.

A struct inside a `meta static` value, or in a value that persists across
REPL submissions, lives in storage the compile-time session owns.

A struct result stays inside compile-time code. Inserting one into the
program with `$pair(3)` is diagnosed, because the compiler cannot write a
struct value as code.

These C shapes are not available at compile time:

- Unions.
- Structs with bitfields, array members, anonymous members, or an enum field
  whose initializers do not all have `int`-range types. A meta function that
  uses one reports `a compile-time struct with no host layout`.
- Structs declared in C headers. A meta function that uses one reports
  `a compile-time struct with no host layout`.
- A `packed` attribute on a struct x2c parses is a compile error.
  `#pragma pack` passes through to the C compiler, and an unused
  packed-attribute macro does not fail translation. Layout attributes,
  including `aligned`, `mode` and `vector_size`, leave a struct without a
  provable compile-time layout. A meta function that uses such a struct
  reports `a compile-time struct with no host layout`. A field whose typedef
  has a layout attribute is also declined.
- Structs with field alignment the compiler cannot prove, such as a field
  declared `_Alignas`, have no compile-time layout. Do not pass one to a
  native function from compile-time code.
- Local arrays of structs, which a meta function reports as `an array of
  structs`, and static arrays. An array of structs on the heap works; see
  [Heap objects during compilation](#heap-objects-during-compilation).
- `sizeof` of an array type, or of a type with no compile-time layout,
  which a meta function reports as `sizeof a type with no layout`. The
  parser does not accept `_Alignof`.

## Heap objects during compilation

`Scope.malloc`, `Scope.calloc`, `Scope.memdup`, `Scope.realloc`, and
`Scope.free` are bound for compile-time calls, and `sizeof` answers from
the same layout the compiler gives each struct and scalar. A meta function
can therefore build structs on the heap: a linked list, an array of
structs, or a buffer that grows. `p->f`, `p.f`, `*p`, and `p[i]` read and
write the heap bytes, and a pointer plus or minus an integer moves by whole
elements, as in C.

```x2c
struct Node { int value; struct Node *next; };

meta static struct Node *push(struct Node *head, int value) {
  struct Node *node = Scope.malloc(sizeof *node);
  node->value = value;
  node.next = head;
  return node;
}

meta static long heap_sum(int count) {
  struct Node *head = NULL;
  for (int i = 1; i <= count; i++) head = push(head, i);
  long *squares = Scope.calloc(1, sizeof(long));
  int size = 0;
  for (struct Node *at = head; at; at = at->next) {
    squares = Scope.realloc(squares, (size + 1) * sizeof *squares);
    squares[size] = at->value * at->value;
    size += 1;
  }
  long total = 0;
  for (long *at = squares + size - 1; at >= squares; at = at - 1)
    total += *at;
  Scope.free(squares);
  while (head) {
    struct Node *next = head->next;
    Scope.free(head);
    head = next;
  }
  return total;
}

int main(void) {
  printf("%ld %ld\n", $heap_sum(4), heap_sum(4));
  return 0;
}
```

```text
30 30
```

The heap belongs to the compiler while it translates. A heap pointer can
pass between meta functions, but it is not a value the program can hold:
inserting one with `$make()` reports `compile-time result is a compiler
address`. Return a value computed from the heap objects instead.

The [region check](regions.md) treats `Scope.realloc` as the end of the
pointer it is given, as `Scope.free` is. In a `meta` body, a read through a
pointer after `Scope.free` or `Scope.realloc` ended it is an error, and so
is freeing or reallocating a literal, a local's address, or other storage
no Scope allocator returned.

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
| `Func` | Expression-bodied lambdas with typed or bare parameters, captures and references to available functions; parameters and returns between meta functions. | Dynamic calls retain the typed signature, convert value parameters and results, and alias reference arguments in place. Storage in collections works. Block-bodied lambdas have no compile-time lowering. This does not expose arbitrary native function-pointer calls. |
| C-style array declarations | A literal-sized one-dimensional automatic array, such as `int a[3] = {1, 2};`, has compile-time storage. Omitted elements are filled with zero-like values. Static arrays have no compile-time lowering. | Indexing, assignment, addresses of elements and reference arguments share contiguous native storage. Passing the array to a pointer parameter preserves that storage. See element/dimension limits below. |
| Pointers to locals | `int *p = &n;`, copying that pointer, and passing it to another meta function or a native function work. A local whose address is taken lives in native bytes, and the pointer is its real address. | `*p` and `p[i]` read, and `*p = value` and `p[i] = value` write, the bytes as C does. Addresses such as `&a[i]` work, and a pointer plus or minus an integer moves by whole elements. |
| Structs | Named, inline and nested locals; initialization, assignment, by-value arguments and returns, with C copy behavior. | Fields and addresses refer to native bytes in C layout. Assignment keeps existing field addresses; storage ends when the function returns. See [C objects during compilation](#c-objects-during-compilation). |
| Native functions | The functions in `lib/cmath.x` and `lib/clibc.x`, the pure Json, Diff and Path operations, the iterator producers marked `meta` in `lib/iter.x`, `lib/map.x` and `lib/dispatch.x`, and the witnesses of `meta protocol` adoptions, all of which the compiler links. | Explicit dollar evaluation and meta bodies can call them, including through output pointers. See [Native C functions](#native-c-functions). |
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

A null-pointer constant such as `NULL` or `(char *) 0` can supply the default
character set for `String.strip`, and `true` and `false` are 1 and 0. Any
other preprocessor name has no compile-time value; a meta function that uses
one reports `a name with no declaration`.

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

The rest of this section lists the library operations meta functions can
call. The ordinary `List` and `Var` selectors `caar`, `cadr`, `cddr` and `caddr`
reuse those same operations. `String`, `List`, `Array` and `Map` expose their
`str` and `repr` rendering; `Symbol` also exposes `repr` and `compare`, and
`Var.kind` reports a value's kind. These calls use the existing value
implementations rather than a separate formatting or comparison algorithm.

Iterator producers and functional collection operations are also available in
x2c-style meta functions. `lib/protocols.x` marks the `Array`, `List`, `Map`
and `String` Iter adoptions `meta protocol`, so their `iter` methods are
available. `range` and the `Iter` producers are `meta` prototypes in
`lib/iter.x`; `Map.keys`, `Map.enumerate` and `Var.iter` are marked beside
their definitions in `lib/map.x` and `lib/dispatch.x`. A `File` is not
iterable at compile time. Omit the native destination argument when an
iterator is consumed by the same expression; the call then allocates the
iterator with `Iter.new`. Either way it uses the native lazy producer and
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
ownership. A local `struct Iter` passed as the destination lives in native
bytes, as other compile-time C objects do, and ends with its function.
`List`, `Array` and `Iter` folds preserve a true `void`
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
| Postfix increment expression values, compound updates to indexed/dereferenced places | **Gap:** preserve the old result and evaluate the destination once. Prefix increments on locals and reference arguments are supported. |
| Static arrays, computed native-array dimensions, general multidimensional arrays and missing element conversions | **Gap:** extend the represented array shape and typed operations. |
| Structs with bitfields, array members, anonymous members or layout attributes other than `packed`; arrays of structs | **Gap:** compute a layout for these shapes. Packing is unsupported and causes a compile error. Other structs use native bytes in C layout. |
| Unions | **Gap:** model overlapping storage in native bytes. A pointer to an actual future runtime object cannot be dereferenced during compilation; that is a **phase boundary**. |
| `try`, `catch`, `finally`, `raise` in a meta body | **Gap:** exception transfer needs compile-time modeling. An error raised by a called operation still runs pending cleanups and becomes a compiler diagnostic. |
| Missing library/resource operations, including `File.open` | **API gap:** implement bindings and appropriate resource lifetimes. Compile-time file I/O is possible in principle; it is not prohibited by the phase boundary. |
| Loop-path temporary bindings, address-taken destructured locals, nonfolded match patterns | **Gap:** preserve required bindings and support pattern evaluation at the appropriate time. |
| Named enum values | **Gap:** make the enumerator's numeric value available to the lowerer. |
| Reading future runtime mutable state | **Fundamental phase boundary:** that program state does not exist yet. Separate compile-time state is possible but is not the same state. |
| Callable result insertion | **Gap:** preserve identity when constructing a runtime value. See the next section. |

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

A block that holds a cleanup keeps its C meaning in a meta body. `defer`,
`$scope`, and `$let` run their cleanup when the block ends and on every
exit through it:

- A `return` computes its value first, then runs every pending cleanup,
  innermost first, then returns.
- A `break` or `continue` runs the cleanups between it and its loop.
- An error raised inside the block, such as a failed compiler query, runs
  the cleanup before it becomes the diagnostic for the explicit call.

```x2c
meta static int closed = 0;

meta int exits(int n) {
  int total = 0;
  for (int i = 0; i < n; i++) {
    defer closed += 1;
    if (i == 1) continue;
    if (i == 3) break;
    total += 10;
  }
  {
    defer total += 1;
    if (n > 5) return total * 100;
  }
  $let(total, 0) total = 7;
  $scope() {
    Array scratch = [total];
    total += (int) scratch.len();
  }
  return total;
}

meta int closed_count(void) => closed;

int main(void) {
  printf("%d %d %d\n", $exits(2), $exits(9), $closed_count());
  return 0;
}
```

```text
12 2000 6
```

`$exits(2)` runs both turns, adds 1 as its block ends, restores `total` after
`$let`, and adds the one element counted in `$scope`. `$exits(9)` leaves the
loop at the `break` after four cleanups. Its `return` computes 2,000 before
the block's cleanup adds 1 to `total`. A loop with a cleanup on its
iteration path still runs each turn in constant space.

A scratch collection that only builds the result takes `$auto`. The
return converts the Array to a new List first, then the cleanup frees the
Array:

```x2c
meta static List evens(int n) {
  Array out = $auto([]);
  for (int i = 0; i < n; i++) out.push(2 * i);
  return out;
}

int main(void) {
  List values = $evens(4);
  printf("%s\n", values.repr().str());
  return 0;
}
```

```text
(0 2 4 6)
```

Meta code manages lifetimes with the same operations as native code.
`$auto` works on an `Array`, a `Map`, or a `Scope`, and `Array.free`,
`String.free`, `Scope.new`, `Scope.new_named`, `Scope.destroy`,
`Context.open`, `Context.export`, `Context.close`, and `List.promote` are
bound for compile-time calls. `Scope.retain`, `Scope.release`, `Scope.push`,
`Scope.pop`, `Scope.move`, and `Context.export` act on the session's user
allocations. Compile-time
allocations belong to the evaluator session. The evaluator keeps its own
bindings, automatic storage, and session state in a separate Scope, so a
release in meta code frees only what meta code allocated. A returned
collection can be consumed by another meta function while the session is
alive; it does not become a pointer to the eventual program's heap. Struct
locals and address-taken locals are released when their function returns,
as described in [C objects during compilation](#c-objects-during-compilation).
A local address is useful within the calculation, not a portable constant
address to embed in C.
A `Job` that meta code starts with `List.job` or `Job.start` belongs to
the function that started it, even inside an inner `$scope` block. It ends
when that function returns or raises: a job still running is terminated and
reaped, so a meta function cannot return its `Job`.
As in C, a value built inside a region must not be kept, in a meta global
or a Lisp definition, after that region is released.

The emitted runtime function still follows the runtime's ownership rules.
Evaluator cleanup does not add cleanup to that function. In particular,
allocating scratch collections in a dual-form body does not by itself prove
that repeated runtime calls have the desired lifetime behavior.

Ordinary file-scope variables remain unavailable, directly or through another
function. Mark one `meta static` when compile-time access is intended. Its
evaluator instance uses a separate per-unit table and does not expose future
runtime state. Compiler-only functions that reach compiler operations use the
same isolated table.

## Results: compute or insert

A meta function can pass and return numeric, collection and callable values
inside the evaluator. Inserting a result into the program adds a separate
requirement: the compiler must construct code representing that value.

| Result | Explicit `$helper(...)` insertion |
| --- | --- |
| Native integers and floating values | Preserves the numeric Var family, including width, signedness and floating precision. |
| Computed string | Inserts a quoted C string literal. |
| `Symbol` | Inserts a Symbol literal. |
| Identifier or nonempty code `List` | Binds the returned code through normal compiler binding and typing. A data List is not automatically an expression. |
| Boxed `Var` | Insertion follows the contained value. |
| `{}` stored in a `Var` | A fresh empty Map, as in compiled code; inserted like any other Map. |
| `Array` or `Map`, nested at any depth | Constructs fresh collections through the ordinary literal constructors. |
| Struct value | Diagnosed; the compiler cannot write a struct value as code. |
| `Func` or arbitrary native address | No direct materialization of the evaluator object. |

An inserted Array or Map is a snapshot of the compile-time result. It becomes
an ordinary `[...]` or `{...}` literal, so each runtime execution of the
expression allocates fresh collections in the current Scope, at every depth;
assigning the result to another variable still aliases it. Array order and
element types are preserved. Map keys use their ordinary runtime key
semantics, but reconstruction does not promise the same traversal order.
A boxed Var may contain the result.

Scalars, Strings, Symbols, and Lists that hold no Array or Map are immutable
and are emitted once as constants, as the same values written in source
would be. A List inside a result is data. A List that holds an Array or Map
is built at runtime like one written in source.

Each Array and Map in a result must appear once. A result that contains
itself, or holds the same collection in two places, is diagnosed rather than
copied, because the inserted code would build separate collections.

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

Floating constants retain their binary value using hexadecimal literals;
nonfinite values use the native compiler's infinity/NaN expressions.
The remaining container work must account for identity, shared references,
mutation and ownership. A pointer into the evaluator is never a valid address
to embed in the future program.

## Compile-time arithmetic and evidence

Native scalar conversions are applied at typed declarations, assignments,
casts, arguments between meta functions and returns. Array/List and
Symbol/String conversions also have explicit support. This does not make
all casts meaningful: reinterpreting an address is not supported. A pointer
plus or minus an integer moves by whole elements.

The `meta-differential` compiler fixture checks selected narrow/unsigned
arithmetic, wide intermediate values, floating operations and conversions
against runtime calls. The `comptime-lowering`, `meta-import` and
`meta-cursors` fixtures cover collections, callable values, local addresses,
method chaining and iteration. They do not prove every operation/type
combination equivalent. The `meta-records` and `meta-record-*` fixtures
cover struct layout, copies and addresses, `meta-heap-objects` covers
`sizeof` and heap structs, and the `meta-native-*` fixtures
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
`x2c_type_resolve` and `x2c_type_is_value` answer the remaining
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

The compiler binds each of these under its x2c name and derives the Lisp
name from it: `_` becomes `.`, and a predicate `x2c_type_is_X` becomes
`x2c.type.X?`. Only `x2c.type.tag-name` and `x2c.type.reverse-name`, which
carry a hyphen, are listed by hand. Two signatures differ from the
corresponding Lisp functions. `x2c_expr_call` takes its arguments as one
`List`, and `x2c_type_is_value` returns `int`.

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

Besides `meta` functions and bodyless `meta` prototypes, a `.xmacro` may
hold `meta static` values. Each importing unit gets its own compile-time
copy of a value, initialized from the declaration, so state that helpers
keep there never carries from one unit to the next. A unit that defines a
variable of the same name reports a redefinition. Automatic
Differentiation keeps its registries of differentiated functions and its
reverse-mode working state this way.

The run-time forms are separate from this. A unit emits a definition only
for the `meta` functions it calls at run time, and a declaration only for
the values and prototypes its run-time code uses. The storage class says
what it emits: `static` gives that unit its own copy, and a public name is
the one copy the program links, exported by the reaching unit's header.

## Lisp interoperability

Use the x2c calls above for ordinary meta work. The following notes apply
when importing or calling Lisp helpers, or working with the compiler session.

The compiler loads Lisp support into an embedded evaluator. Some loaded files
are generated output: `etc/builtin-macros.xlisp` comes from
`etc/builtin-macros.x` and `etc/builtin-core.xlisp` through
`tools/gen-lisp-init.py`. Seeing Lisp in that generated file does not mean the
algorithms still need a separate handwritten Lisp implementation. The support
layer and the generated functions have different source owners.

### One table for compiled code and Lisp

Compile-time Lisp calls a `meta` function by its name. A table kept as a
`meta` function therefore serves both an inserted value and a Lisp helper
that reads it during expansion, without a second copy of its rows:

```x2c
meta static Map widths(void) => { %(char): 1, %(short): 2, %(int): 4 };

macro Expression $width(Type $type) =>
  $(x2c.literal.int (Map.getindex (widths) $type));

static Map table = $widths();

int main(void) {
  printf("%d %d\n", $width(short), table[%(int)].int());
  return 0;
}
```

```text
2 4
```

`lib/native-scalar-types.xmacro` keeps the compiler's exact C scalar table
this way: `src/type.x` inserts it, and the `lib/lisp.x` access records read
their tags from it.

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
