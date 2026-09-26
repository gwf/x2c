# Meta Functions

x2c extends C. A `meta` function is compiled by the same backend as the
rest of the program and runs as native code inside the compiler, so its
body is ordinary x2c: anything the unit can compile, it can run during
translation. Two questions remain, both at the boundary between the
program and compile-time code:

1. **Can the arguments cross?** A `$helper(...)` call passes constants,
   captured syntax, or the results of other `$` calls.
2. **Can the answer become program code?** Returning a value to another
   meta function and inserting it with `$helper(...)` have different limits.

`meta` is not a purity annotation. A body can mutate locals, arrays, maps
and structs, and pass local addresses to other meta functions. Its
compile-time objects belong to the compiler; they are not the objects the
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

A `meta` function with a body lives in a `.xmacro` file that the program
imports, apart from the program's own code; see
[Sharing a `meta` function between units](#sharing-a-meta-function-between-units).
The samples in this chapter show the definition beside the code that calls
it so that each fits in one block.

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
construction are exceptions: they only run during translation. We will
reach those after ordinary calculations.

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

This dispatches the program's compiled implementation, not the copy the
compiler runs during translation.

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
code, and `meta native` before a definition does the same for the function
it defines. [Native C functions](#native-c-functions) below describes which
functions the compiler provides.

At file scope, `meta` can also advertise one initialized static value to
compile-time code:

```c
meta static const double pi = 3.1415;
meta static int compile_counter = 0;
```

The emitted program keeps the ordinary C declarations and initializers.
Compile-time code gets separate per-translation-unit values built from the same
source initializers, so compile-time mutation never changes the eventual
program's object. An explicit dollar call reads and writes the compile-time
values; an ordinary call reads the program's. Each value lives in bytes the
compile-time session owns, so taking its address and reading or writing through
a correctly typed pointer has the same aliasing effect as in C. `const`
prevents compile-time writes.

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

### Native definitions

A function that has an x2c body can be declared native where it is defined.
Write `native` after `meta`:

```x2c
/** Returns the number of set bits in `value`. */
meta native int bits(unsigned value) {
  int count = 0;
  for (; value; value &= value - 1) count++;
  return count;
}
```

This means the same as a bodyless `meta` prototype followed by the ordinary
definition. The body is compiled for the program and never staged with the
unit's `meta` group. Compile-time code that calls the function runs
the compiler's native copy, and the signature must match that copy just as a
prototype's must. `native` applies only to functions; before any other
declaration it is an error:

```text
sample.x:1:1: parse: a native meta declaration must be a function
  meta native static int value = 3;
  ^^^^
```

`native` is a marker only directly after `meta` and before a declaration.
Elsewhere, including as a type name after `meta`, it is an ordinary
identifier.

Keep the bodyless prototype for a function that has no x2c body, such as
`sin` from the C library.

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

A bodied `meta` function is compiled into a module automatically, as
[How a meta function runs](#how-a-meta-function-runs) describes. A native
module built ahead of time lets compile-time code call functions from your
own project without compiling them during translation, and share them
between projects. Define each function with `meta native`:

```x2c
meta native int triple(int x) { return 3 * x; }
```

Save that as `helpers.x` and build it as a module:

```sh
x2c build --kind meta-module --output helpers.so helpers.x
```

The module contains every function that a `meta native` definition or a
bodyless `meta` prototype in its own sources declares. Code that includes
the declaration can call the function during translation when the compiler loads the module:

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
`build`, `run`, and `repl`, and the REPL accepts a bodyless prototype for
the same function.

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
  note: name: widget_wrap signature: ((func (("Widget"))) "Widget") it might return or keep its argument; ownership cannot be inferred
```

The compiler loads a module only when an option, a manifest or an import
names it. Without `--native-module`, `nine` reports `no binding for triple`.
A [package with a compile-time part](packages.md#packages-with-compile-time-parts)
builds its module with the package, and importing the package loads it. In a
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
warning. Modules named by an option or a manifest come before the modules
of imported packages.

A module runs inside the compiler and uses the compiler's own runtime, not
a copy of it. Only the compiler that built a module can load it, so a
module must be rebuilt after the compiler changes. The compiler checks this
before it loads any of the module's code:

```text
x2c: error: native module 'helpers.so' was built by another compiler; rebuild it
```

Every function the module exports needs a `meta native` definition or a
bodyless `meta` prototype in the module's sources, and a module whose sources
declare none fails to build.

A module can call any runtime function, because the compiler links the
whole runtime. This holds for a compiler built from a checkout and for one
`x2c bootstrap` installs. A loaded module stays loaded until the compiler
exits. Native modules work on macOS, Linux and WSL. On other platforms,
loading one reports that native modules are not supported.

A package's compile-time part can instead be linked into the compiler
itself, which is the only route where modules do not load.
`x2c build --extension <dir>`, given the compiler's sources, and
`x2c bootstrap --extension <dir>` each translate the package's
sources into the compiler and register its `meta` functions under the
package's name. Any number of packages can be linked this way. Importing
such a package loads no module and needs no `builds/<name>.module`; its
functions come after the modules an option or a manifest names.

## C objects during compilation

Compile-time code keeps C objects the way the program does, because it is
the same C. Structs, unions, bitfields, arrays, enums of any width, local
statics, pointers, and `goto` all behave as C defines them. Struct
assignment copies bytes into the destination's existing storage, so an
address taken earlier stays valid. Passing a struct by value gives the
callee its own copy:

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
[The Region Model](regions.md). As in C, an address the check does not
follow, such as one computed with pointer arithmetic, is undefined behavior
once its storage ends.

A struct, a C `bool`, or a pointer stays inside compile-time code: another
meta function can take it, but a `$` call cannot pass one in or insert one
into the program. Such a call reports `this function cannot run at compile
time` with a reason that names the kind of value: a struct or union
result, an address result, or a parameter or result with no Var form.

## Heap objects during compilation

`Scope.malloc`, `Scope.calloc`, `Scope.memdup`, `Scope.realloc`, and
`Scope.free` work as they do in the program, and `sizeof` is C's. A meta
function can therefore build structs on the heap: a linked list, an array of
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
inserting one with `$make()` reports that the function cannot run at
compile time, because its result has no Var form. Return a value computed
from the heap objects instead.

The [region check](regions.md) treats `Scope.realloc` as the end of the
pointer it is given, as `Scope.free` is. In a `meta` body, a read through a
pointer after `Scope.free` or `Scope.realloc` ended it is an error, and so
is freeing or reallocating a literal, a local's address, or other storage
no Scope allocator returned.

## How a meta function runs

A translation runs in two phases. Before any unit is translated, the
compiler gathers the bodied `meta` functions the inputs reach: those of
each `.xmacro` file an input imports, directly, through an included
header, or through a package, and those an input defines itself. It
emits them, with the declarations they use, as C through the ordinary
backend, compiles them with the host C compiler, and links them with the
runtime into one helper program for the project. The translation then
sends each `$` call, and each compile-time Lisp call, of one of those
functions to the helper and inserts the reply. A project whose inputs
reach no `meta` function builds nothing extra.

The helper is kept under the cache directory (`$X2C_CACHE_DIR`,
`$XDG_CACHE_HOME/x2c`, or `~/.cache/x2c`), named by a hash of the meta
sources, the compiler, the C compiler, and the flags, and it is built
again when any file its build read changes, x2c source or C header. The
shipped meta code of the compiler's own `.xmacro` files and of
`lib/meta.x` is linked into the compiler and runs without a helper. The
REPL compiles each submission's `meta` functions and loads them into the
compiler instead.

Inside a `meta` body the whole body runs at compile time, so `$f(x)` there
is an ordinary call of `f`. `$` keeps its meaning only where program code
meets compile-time code, and says evaluate now and insert the result.

Each unit gets its own `meta static` values: the helper runs their
initializers again before the first call a unit makes.

A project `meta` function receives what it needs as arguments and returns
a value; it does not query the compiler. The syntax builders of
`lib/meta.x`, `x2c_ident`, `x2c_function_name`, `x2c_diagnostic_fail`,
and `x2c_diagnostic_warn` work in the helper, and a builder that needs a
type's parts is finished by the compiler when the call returns. The
operations that read other compiler state, such as `x2c_source_text` and
`x2c_type_fields`, report that they are not available to project meta
code.

Running compile-time code needs what building the program needs: the C
compiler and the runtime headers. A module that does not compile is
reported at the call with the C compiler's first error and the directory
that keeps its C.

A raise inside a `meta` body becomes a diagnostic at the `$` call. A body
that crashes, exits, or overflows the stack ends the helper; the call is
reported with the function and the reason, and the next call starts a new
helper. A `$` call that runs longer than 60 seconds is stopped the same
way; `X2C_META_TIMEOUT` sets another limit in seconds, and `0` turns the
limit off.

### Arguments and results

A `$` call's arguments are evaluated before the call. Each is a numeric,
character, or String literal, a `%(...)` syntax literal, arithmetic over
constants, a Symbol, captured macro syntax, or another `$` call. A captured
literal passed to a parameter that is not syntax, such as a `String`,
arrives as the literal's value. Anything else, such as a program variable,
reports `an argument must be a constant, captured syntax, or a meta call`.

Compile-time Lisp calls a `meta` function by its name with Lisp values.
The native function checks each argument against its declared type, so
passing `0` where a `List` is declared is an error rather than an empty
list.

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

Meta code manages lifetimes with the same operations as native code, and
they mean the same thing: a compile-time call runs inside a Scope the
compiler opens for it, and a returned collection belongs to the compiler,
not to the eventual program's heap. As in C, a value built inside a region
must not be kept, in a `meta static` or a Lisp definition, after that
region is released.

A file-scope variable a `meta` body reads is the compiled group's own copy,
initialized as the declaration says; it does not expose future runtime
state. Mark it `meta static` to say that compile-time code owns it.

## Results: compute or insert

A meta function can pass and return any value to another meta function.
Inserting a result into the program adds a separate requirement: the
compiler must construct code representing that value.

| Result | Explicit `$helper(...)` insertion |
| --- | --- |
| Native integers and floating values | Preserves the numeric Var family, including width, signedness and floating precision. |
| Computed string | Inserts a quoted C string literal. |
| `Symbol` | Inserts a Symbol literal. |
| Identifier or nonempty code `List` | Binds the returned code through normal compiler binding and typing. A data List is not automatically an expression. |
| Boxed `Var` | Insertion follows the contained value. |
| `{}` stored in a `Var` | A fresh empty Map, as in compiled code; inserted like any other Map. |
| `Array` or `Map`, nested at any depth | Constructs fresh collections through the ordinary literal constructors. |
| Struct value, C `bool` or pointer | Diagnosed; the value has no Var form. |
| `Func` | No direct materialization of the compiler's object. |

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
A pointer into the compiler is never a valid address to embed in the future
program.

## Compile-time arithmetic and evidence

Compile-time code is compiled by the same backend with the same C compiler
as the program, so its arithmetic, conversions and casts are the program's.
The `meta-differential` compiler fixture checks narrow and unsigned
arithmetic, wide intermediate values, floating operations and conversions
against runtime calls. The `comptime-lowering`, `meta-native-constructs`,
`meta-import` and `meta-cursors` fixtures cover collections, callable
values, local addresses, C constructs, method chaining and iteration; the
`meta-records` and `meta-heap-objects` fixtures cover structs and the heap.

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

meta static List field_count(Type type) =>
  x2c_literal_int(type.assoc(<fields>).len());

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

`field_count` declares its parameter `Type`, so it receives a description
of the argument's type rather than its code. The compiler computes that
description at the `$` call:

```text
((name "Point") (kind struct) (type ("Point"))
 (fields (("x" (int)) ("y" (int)) ("z" (int)))))
```

`name` is the type's name, or `""` when it has none. `kind` is `struct`,
`union`, `enum`, `pointer`, `scalar` or `other`. `type` is the canonical
type, and `fields` lists the `(name type)` rows of a struct or union's
named fields in declaration order. Read a part with `List.assoc`. Pass the
same hole twice when a function needs both the code and its type, as
`shape_reads` does below.

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

A decorator can make that choice from the function it captures. Here the
`meta` helper selects one of two named Statement templates, then the decorator
inserts the selected invocation into the function body:

```x2c
#include "x2c.x"
#include "meta.x"

static int calls = 0;

macro Statement $counted(Block $body...) {
  calls++;
  $body...
}

macro Statement $plain(Block $body...) {
  $body...
}

meta static List choose_body(List function) {
  List body = x2c_function_body(function);
  String name = x2c_function_name(function);
  List node = name == "tracked" ? $counted(body) : $plain(body);
  return %($node);
}

macro Decorator $count_if_tracked(Function $function) {
  $choose_body($function)...
}

$count_if_tracked()
static int tracked(void) { return 7; }

$count_if_tracked()
static int ordinary(void) { return 9; }

int main(void) {
  printf("%d %d %d\n", tracked(), ordinary(), calls);
  return 0;
}
```

```text
7 9 1
```

`choose_body` runs while the compiler expands the decorator. It reads the
captured function, computes the choice, and returns a deferred invocation.
The chosen template expands when the returned code is inserted. Its body
capture becomes the function's statements; `calls++` runs only when `tracked`
is called at runtime. The template names are known in source, while `meta`
chooses which one to use for each function.

The reverse gradient generator in `packages/autodiff/src/autodiff.xmacro`
uses this pattern.
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

**Asking about types and fields.** A program's `meta` function receives a
type as a `Type` parameter, described above, and asks the compiler
nothing. The queries below answer the same questions for the compiler's
own `meta` code in `lib/`. `x2c_syntax_type` answers the canonical `Type`
of an expression or binding. `x2c_type_fields` answers the named fields
of a struct or union `Type`, each as a metadata row whose first element is
the field name. `x2c_type_layout`, `x2c_type_parts`, `x2c_type_resolve`
and `x2c_type_is_value` answer the remaining generated-code questions.
`x2c_method_resolve` answers which operation a member call selects. These
answers live in the compiler's symbol table, so a macro body cannot derive
them from the code it captured.

**Source text and location.** A parameter declared `Source` receives a
captured hole together with the text the developer wrote for it:
`((text T) (file F) (syntax S))`. `x2c_source_text` returns that text, and
`x2c_embed_text` reads the file a captured `String` literal names beside
the source that wrote it and records it as a translation dependency. Both
read what the argument carries. `x2c_embed_text` also accepts a plain
`String`, resolved against the file that defines the macro.
`x2c_binding_spelling` returns the name a binding was declared with.
`x2c_invocation_file`, `x2c_invocation_line` and `x2c_invocation_column`
give the site of the macro invocation.

**Failing with a diagnostic.** `x2c_diagnostic_fail` reports a message at
the invocation and stops the expansion. It does not return. Use it when the
argument is wrong in a way the macro can see:

```x2c
#include "x2c.x"
#include "meta.x"

meta static List one_word(Source node) {
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

The helper receives the complete capture with its source text, which
`x2c_source_text` reads. A computed subtree is code data, not a new source
capture, and cannot be passed as a `Source`.

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
containing a source-template constructor is also compile-time-only, as are
its meta callers. A call to
one from a runtime body is diagnosed where it is written. Calling
`one_word` from an earlier section at run time gives:

```text
sample.x:19:22: macro: 'one_word' can only be called at compile time
    List n = one_word(node);
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
macros that call them. `shape_fields` reads the fields from the `Type` the
compiler sends. `shape_names` and `shape_reads` turn them into code.

<!-- ignore: shape.xmacro is the external file being illustrated -->
```x2c,ignore
/* The named fields of a struct-typed expression, in declaration order. */
meta static List shape_fields(Type type) => type.assoc(<fields>);

/* One `String` literal holding those field names, comma separated. */
meta static List shape_names(Type type) {
  Array names = [];
  foreach (List field, shape_fields(type)) names.push(field.car());
  return x2c_literal_string(String.join(", ", names));
}

/* `{ p.x, p.y, p.z }`, built from the fields rather than written out. */
meta static List shape_reads(List receiver, Type type) {
  Array reads = [];
  foreach (List field, shape_fields(type))
    reads.push(x2c_expr_field(receiver, field.car()));
  return x2c_expr_composite(reads);
}

macro Expression $shape.names(Expr $value) => $shape_names($value);

macro Expression $shape.reads(Expr $value) => $shape_reads($value, $value);
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

A `meta` function with a body lives in a `.xmacro` file, apart from program
code. A bodied `meta` function in an ordinary program `.x` file is an
error that names the function and asks to move it to an `.xmacro` file the
unit imports:

```text
sample.x:5:1: parse: meta function 'poly' is defined in a program file
  meta int poly(int n) => n * n + 3 * n + 1;
  ^^^^
  note: move it to an .xmacro file this unit imports
```

A macro cannot produce one either: a `meta` function inside a macro
template is reported where it is written. The compiler's own `lib/meta.x`
and its `src/` units are the exceptions. A bodyless `meta` prototype, a
`meta native` declaration and a `meta static` value may still appear in a
`.x` file.

Put a `meta` function in a `.xmacro` that each unit imports. A `.xmacro` file
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

The compiler loads Lisp support into an embedded evaluator. The built-in
macros' algorithms are compiler functions (`src/builtins.x`); the Lisp in
`etc/builtin-core.xlisp` and `etc/lisp-bindings.xlisp` only names them.

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
cannot replace one of its definitions. A `meta` function is installed under
its C name, so `meta int add(int x)` reports that it could not be installed.
A macro file or a `$(...)` form that defines an inherited name reports:

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
