# Meta Functions

x2c extends C. A `meta` function uses the x2c backend and the host compiler
selected by `--meta-cc`. It runs as native code during translation, and its
body is ordinary x2c: anything the unit can compile, it can run during
translation. Two questions remain, both at the boundary between the
program and compile-time code:

1. Which arguments can cross: a `$helper(...)` call passes constants,
   captured syntax, or the results of other `$` calls.
2. Which results can become program code: returning a value to another
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

A `meta` function with a body can sit beside the code that calls it, as
in the samples of this chapter, or in an ordinary `.x` module that several
units include; see
[Sharing a `meta` function between units](#sharing-a-meta-function-between-units).

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

These are the two forms of a `meta` function: one runs in your program,
and one runs in the compiler. Both come from the same body. A
[rewrite rule](generating-code.md#what-the-compiler-answers) in your program changes only the
program's copy; the copy the compiler runs is compiled as written.
Functions that call a compiler query or build a source template,
directly or through another meta function, are exceptions: they only run
during translation. We will reach those after ordinary calculations.

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
concrete typed value parameter rejects `void`; a `Var` parameter carries it.

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

The project's bodied `meta` functions need no module of your own: the
compiler builds the project meta module from them and caches it, as
[How a meta function runs](#how-a-meta-function-runs) describes. A native
module is built ahead of time instead, by you or by a package. It lets
compile-time code call functions that are not part of the project meta
module, and it can be shared between projects. Define each function with
`meta native`:

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
  `Scope.free` or hold it in a local with initializer `auto`.
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
`make install` installs. A loaded module stays loaded until the compiler
exits. Native modules work on macOS, Linux and WSL. On other platforms,
loading one reports that native modules are not supported.

A package's compile-time part can instead be linked into the compiler
itself, which is the only route where modules do not load.
`x2c build --extension <dir>`, given the compiler's sources, translates
the package's sources into the compiler and registers its `meta` functions
under the package's name. Any number of packages can be linked this way. Importing
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
time` with a reason that states the kind of value: a struct or union
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
  struct Node *node = xmalloc(sizeof *node);
  node->value = value;
  node.next = head;
  return node;
}

meta static long heap_sum(int count) {
  struct Node *head = NULL;
  for (int i = 1; i <= count; i++) head = push(head, i);
  long *squares = xcalloc(1, sizeof(long));
  int size = 0;
  for (struct Node *at = head; at; at = at->next) {
    squares = xrealloc(squares, (size + 1) * sizeof *squares);
    squares[size] = at->value * at->value;
    size += 1;
  }
  long total = 0;
  for (long *at = squares + size - 1; at >= squares; at = at - 1)
    total += *at;
  xfree(squares);
  while (head) {
    struct Node *next = head->next;
    xfree(head);
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
pass between meta functions, but like any pointer it cannot cross `$`.
Return a value computed from the heap objects instead.

The [region check](regions.md) treats `Scope.realloc` as the end of the
pointer it is given, as `Scope.free` is. In a `meta` body, a read through a
pointer after `Scope.free` or `Scope.realloc` ended it is an error, and so
is freeing or reallocating a literal, a local's address, or other storage
no Scope allocator returned.

## How a meta function runs

A translation runs in two phases. Before any unit is translated, the
compiler gathers the bodied `meta` functions the inputs reach: those of
each ordinary source module an input reaches, directly, through includes,
or through a package. It emits them, with the declarations they use, as C through the ordinary
backend, compiles them with the host C compiler (`--meta-cc`, default
`cc`, never the target `--cc`), and links them with the host runtime into
one helper program, the project meta module. A group sees the headers its
unit includes, found from the unit's directory and the `-I` directories.
The translation then
sends each `$` call of one of those
functions to the helper and inserts the reply. A project whose inputs
reach no `meta` function builds nothing extra.

A call runs with the functions of the file that wrote it. An included
`.x` file computes its file-scope constants, such as an enumerator or an
array size, with its own `meta` functions, as its own translation does.
The including unit also receives nonstatic meta functions and can call them
at compile time. Static meta functions remain private to their provider.

The helper is kept under the cache directory (`$X2C_CACHE_DIR`,
`$XDG_CACHE_HOME/x2c`, or `~/.cache/x2c`), named by a hash of the meta
source paths, the compiler, the C compiler, and the flags, including `-D`
and `-U`. It is built again when any file its build read changes, x2c
source or C header; a change to program code alone recompiles the groups
but keeps the helper when no group object changes. The
shipped meta code of the compiler's own source modules and of
`lib/meta.x` is linked into the compiler and runs without a helper. The
REPL evaluates its supported submissions through Lisp. It accepts bodyless
`meta` prototypes for linked or explicitly loaded native functions; user
`meta` function definitions entered at the prompt are outside its supported
subset. Its [`:load` command](repl.md#load-functions-from-a-file) compiles a
source file's public bodied meta functions into a separate project helper
and makes them callable from interpreted submissions.

Inside a `meta` body the whole body runs at compile time, so `$f(x)` there
is an ordinary call of `f`. `$` keeps its meaning only where program code
meets compile-time code, and says evaluate now and insert the result.

A `match` or `catch` pattern in a `meta` body is the exception. Its
captures come from its value, so a `$f(...)` call in it runs while the
body is translated. Only meta code linked into the compiler can run then,
such as the [source-form builders](../internals/compiler-api/grammar.md).
A call of a project function waits until the body runs, so a pattern built
by one cannot capture.

Each unit gets its own `meta static` values: the helper runs their
initializers again before that unit's first call reaches their provider. What those
initializers allocate, a Job one starts included, lasts until the next
unit's reset or the end of the helper.

A project `meta` function receives arguments and returns a value.
Quotations, `x2c_ident`, `Code.name`, `Code.binding_spelling`, `Type.parts`,
`x2c_diagnostic_fail`, and `x2c_diagnostic_warn` work in the helper. The
typing and invocation queries, such as `Type.resolve`,
`Type.fields`, `Code.type`, and `Type.resolve_member`, ask the
compiler while the call waits. The compiler answers in the state of the `$`
call's site, so a project function gets the answer that compiler-linked
meta code gets at the same place. `Code.source_text` reads only the text a
`Source` parameter carries.

Running compile-time code needs what building the program needs: the C
compiler and the runtime headers. A project meta module that does not
compile is reported at the call with the C compiler's first error and the
directory that keeps its C.

A raise inside a `meta` body becomes a diagnostic at the `$` call. A body
that crashes, exits, or overflows the stack ends the helper; the call is
reported with the function and the reason, and the next call starts a new
helper. A `$` call that runs longer than 60 seconds is stopped the same
way; `X2C_META_TIMEOUT` sets another limit in seconds, and `0` turns the
limit off.

A process that compile-time code starts ends no later than its helper.
The helper leads a process group of its own, and everything in that group
ends when the helper ends, whether it quits, crashes, or passes the
deadline, and when the translation that started it ends. Since that group
is not the terminal's, compile-time code that reads the terminal is
stopped until the call's deadline.

### Arguments and results

A `$` call's arguments are evaluated before the call. Each is a numeric,
character, or String literal, a `%(...)` syntax literal, arithmetic over
constants, a Symbol, captured macro syntax, or another `$` call. A captured
literal passed to a parameter that is not syntax, such as a `String`,
arrives as the literal's value. Anything else, such as a program variable,
reports `an argument must be a constant, captured syntax, or a meta call`.

### Lifetime and state

A block that holds a cleanup keeps its C meaning in a meta body. `defer`,
region `auto`, and `with` run their cleanup when the block ends and on every
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
  with (total = 0) { total = 7; }
  auto {
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
`with`, and adds the one element counted in region `auto`. `$exits(9)` leaves
the loop at the `break` after four cleanups. Its `return` computes 2,000 before
the block's cleanup adds 1 to `total`. A loop with a cleanup on its
iteration path still runs each turn in constant space.

A scratch collection that only builds the result takes initializer `auto`. The
return converts the Array to a new List first, then the cleanup frees the
Array:

```x2c
meta static List evens(int n) {
  Array out = auto [];
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
must not be kept, in a `meta static`, after that region is released.

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
| Identifier or nonempty code `List` | Binds the returned code through normal compiler binding and typing, in ordinary code and in macro bodies alike. A List is code when it is an expression node, a macro application, a quotation, or an identifier; inside a macro expansion every List is code. A call written as a whole statement may also return a statement, while a call inside a larger expression must return an expression. A data List is not automatically an expression, and a result used as a `case` pattern stays data. |
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
A boxed Var may contain the result. Collection items, including Map keys,
can contain raw `Null`, distinct from the empty List `%()` and `void`.

Scalars, Strings, Symbols, and Lists that hold only those values are
immutable and are emitted once as constants, as the same values written in
source would be. A List inside a result is data. A List that holds raw
`Null`, an Array, or a Map is built at runtime like one written in source.

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

Compile-time code uses the x2c backend and the host C compiler selected by
`--meta-cc`, which defaults to `cc`. The target `--cc` does not select that
compiler. Arithmetic, conversions and casts follow the host build's native
semantics.
The `meta-differential` compiler fixture checks narrow and unsigned
arithmetic, wide intermediate values, floating operations and conversions
against runtime calls. The `comptime-lowering`, `meta-native-constructs`,
`meta-import` and `meta-cursors` fixtures cover collections, callable
values, local addresses, C constructs, method chaining and iteration; the
`meta-records` and `meta-heap-objects` fixtures cover structs and the heap.

## Generating code

A `meta` function can also take code as a `List` and return new code.
[Generating Code](generating-code.md) covers macro helpers, source
templates, quotations, and the questions the compiler answers.

## Sharing a `meta` function between units

Define a shared `meta` function in an ordinary `.x` module, beside any macros
and runtime code that use it. The project meta build compiles the provider's
meta code into the project meta module. A meta function must be written in
source: a definition inside a macro template, or one produced by a `$` call,
is reported where it is written.

The provider includes its own dependencies. A consumer includes the provider:

```text
#include "shape.x"
```

Nonstatic meta functions become callable during translation at the include
position, including through transitive includes. A `meta static` helper and
its static state remain in the provider. Public meta functions can use those
helpers inside the provider's compiled group. The caller does not receive a
second definition of the helper.

Repeated includes contribute one public declaration per canonical path. For a
meta function with a runtime form, ordinary linkage applies: the provider
owns its runtime definition and including sources receive its declaration.
Compile and link that provider as you would any other source module. The
compile-time helper build and the runtime build are separate.

## Meta functions and runtime Lisp

Compile-time code is x2c. The compiler does not evaluate Lisp, and it rejects
the former `$(...)` and `@(...)` forms with
`compile-time Lisp forms are not supported`. The builtin macros are ordinary
x2c in `etc/compiler-prelude.x`, and the operations a macro calls are the
`meta` prototypes in `lib/meta.x`.

A `meta` function can still use runtime
[Lisp](../library/overview.md#embed-lisp) as a library. A project `meta`
function runs in the project helper, which links the full runtime, so its body
can create a session and evaluate forms:

```x2c
meta static int lisp_sum(void) {
  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  return lisp.eval(%(apply + (list 40 2)));
}

int main(void) {
  printf("%d\n", $lisp_sum());
  return 0;
}
```

```text
42
```

The REPL can call such a function too. A [native module](#native-modules)
the compiler loads receives only the compiler's core runtime exports, which
omit Lisp, so a function that needs Lisp belongs in the project helper or the
REPL. Session rules such as inherited names, closures, and `eval` are in the
[language reference](../reference/language.md#runtime-lisp).
