# Compile-time Macros

For using the shipped `class`, region `auto`, `with`, `$lock`, and initializer
`auto` facilities, see [Classes and System Macros](system-macros.md). This
chapter explains how to author macros, including the ordinary facilities
those definitions compose.

x2c macros generate source at compile time using C-like x2c syntax. They bind
parsed, typed source rather than preprocessor text. The compiler constructs,
binds, and types their templates and arguments as it does ordinary source.
Hygiene keeps generated names from colliding with names in the caller. A
reusable global macro is invoked explicitly with a `$` name; a local macro uses
a bare name inside its defining block. Both declare the syntax kinds they
accept and produce one declared kind of source.

Choose according to what the code does:

- a function computes with runtime values;
- a meta function also computes during compilation;
- a macro constructs source at translation time;
- a decorator transforms the expression or source item immediately following
  it.

Start with templates. Use meta functions when the result requires
computation.

## A first expression macro

The result kind follows `macro`; typed holes appear in the invocation pattern:

```x2c
~
macro Expression $project.minutes(Expr $value) =>
  $value * 60;
~
~int main(void) {
~  int seconds = $project.minutes(2);
~  return seconds == 120 ? 0 : 1;
~}
```

Read the definition from left to right:

| Source | Meaning |
| --- | --- |
| `Expression` | the expansion must be one expression |
| `$project.minutes` | the explicit, qualified invocation name |
| `Expr $value` | bind one caller expression to `$value` |
| `$value * 60` | insert that expression into the replacement |

The `$` marks macro syntax. It does not make a runtime variable dynamic.
Macro names are in their own namespace, so qualification is useful for
project and library names. The `x2c.*` namespace is reserved for
compiler-shipped facilities.

The replacement preserves ordinary evaluation rules. If a hole appears twice,
the caller's expression appears twice and may be evaluated twice. Use a
generated temporary when the macro promises single evaluation, or use a
function when that fits better.

## Local expression shorthand

Use `alias` when one scope repeats an expression and does not need a
reusable macro:

```x2c
~typedef struct Point { int x, y; } Point;
~typedef struct Shape { Point origin; } Shape;
~int main(void) {
~  Shape shape = { { 0, 0 } };
alias shape.origin as origin;
origin.x = 1;
origin.y = 2;
~  return shape.origin.x == 1 && shape.origin.y == 2 ? 0 : 1;
~}
```

The name lasts to the end of the enclosing scope. The braced form
`alias shape.origin { ... }` limits the name `_` to its body. Like a macro
hole, every use substitutes the original expression and may evaluate it
again; `alias` does not create a runtime temporary. It declares no reusable
generator. See
[expression aliases](../reference/language.md#expression-aliases-with-alias).

## Keep a generator inside one block

Use a local macro when one function or nested block needs a typed generator:

```x2c
~static int scaled_sum(int scale, int value) {
macro Expression scaled(Expr $input) =>
  $input * scale;

return scaled(value);
~}
```

The definition is visible from that point to the end of the block and through
nested blocks. An inner definition of `scaled` temporarily shadows it; a later
definition in the same block replaces it for following calls. A name the
body reads without declaring, such as `scale`, resolves where the macro is
invoked, as in a global macro, unless the macro lists it with
[`using`](#keep-a-file-scope-name-with-using). Names the caller writes in
arguments resolve there too.

The bare call shape belongs to the local macro before a file `keyword` alias or
ordinary function. A use without parentheses is an ordinary identifier, and
`(scaled)(value)` explicitly calls a function. `$scaled(value)` uses only a
global or imported macro, so local and global definitions may share a name.

Local expression, statement, field, `Map`-entry, and enumerator generators keep
their usual result positions. Local decorators are available when their target
also occurs inside the block. `Unit` generators and decorators over functions
or translation-unit items remain global because they have no invocation
position inside the local name's lifetime. A macro may generate a local
definition; it has the same source-order visibility and capture behavior as a
direct one.

`alias` remains the smaller choice when the only need is repeated substitution
of one expression. A local macro is worth defining when it needs typed
holes, declarations, control flow, computed source, or more than one input.

<a id="holes-say-what-binds"></a>

## Hole syntax kinds

Every hole has a syntax kind:

| Hole kind | Accepts |
| --- | --- |
| `Expr` | an expression |
| `Name` | an identifier binding |
| `Type` | a type |
| `Param` | a function parameter |
| `Function` | a complete function definition |
| `Decl` | one declaration without its trailing semicolon |
| `Stmt` | one block item |
| `Field` | one struct or union field |
| `Entry` | one `Map` `key: value` row |
| `Enumerator` | one enum member |
| `Unit` | one translation-unit item |
| `Literal` | one literal, such as `42` or `<char>` |

The reference lists [every hole kind](../reference/language.md#holes-and-sequences),
including the less common `NamedType`, `DeclaratorRow`, `Catch`,
`Captures`, and `MatchRow`.

An `@` prefix makes the final hole a sequence. The replacement uses the
same prefix to splice the captured sequence:

```x2c
~
macro Expression $project.call(
  Expr $callee,
  Expr @arguments
) =>
  $callee(@arguments);
~
~static int add(int left, int right) {
~  return left + right;
~}
~
~int main(void) {
~  return $project.call(add, 20, 22) == 42 ? 0 : 1;
~}
```

A `raise` template can also insert expression holes for the error code and
field keys. A sequence hole between field pairs supplies alternating key and
value expressions, in source order:

```x2c
macro Stmt $fail(Expr $cause, Expr $op, Expr @fields) {
  raise %($cause (operation $($op)) @fields);
}
```

Here `$($op)` inserts the captured x2c expression into the literal payload.
The holes are substituted before the ordinary raise expression binding and
lowering; they do not evaluate Lisp code.

Typed holes tell the reader whether an argument is an expression, binding,
type, declaration, or sequence, without requiring knowledge of the AST.

## Type holes are compile-time generics

A `Type` hole lets one `Unit` macro generate the same typed interface for
several concrete C types. Each invocation is checked independently and emits
ordinary declarations and functions specialized to the types it receives:

```x2c
~typedef struct { int value; } IntValue;
~typedef struct { double value; } DoubleValue;
~
macro Unit $value.family(Type $box, Type $item) {
  static inline $box $box.new($item value) {
    $box box = { value };
    return box;
  }

  static inline $item $box.get($box box) {
    return box.value;
  }
}

$value.family(IntValue, int);
$value.family(DoubleValue, double);
~
~static double measure(void) {
~  IntValue count = IntValue.new(3);
~  DoubleValue ratio = DoubleValue.new(0.5);
~  return count.get() * ratio.get();
~}
```

Each expansion is a distinct C type. `IntValue.get` returns `int`,
`DoubleValue.get` returns `double`, and the generated C has no runtime type
parameter or hidden cast. The caller supplies named concrete types, and the
macro builds their shared implementation.

## Result kinds match source positions

The declared result kind determines where an invocation may appear:

| Result kind | Invocation position |
| --- | --- |
| `Expression` | expression |
| `Stmt` | statement |
| `Field` | struct or union body |
| `Entry` | `Map` literal row |
| `Enumerator` | enum body |
| `Unit` | translation unit |
| `Decorator` | as a prefix immediately before its target |

An `Entry` macro can produce zero, one, or several comma-separated `Map` rows.
`Entry` holes capture complete rows, and `@rows` captures or inserts
a row sequence. A `Map` literal reads quoted data, so `$(...)` crosses into
x2c before invoking either a `$handler(...)` or a keyword alias:

```x2c
macro Entry $project.handler(Literal $key, Expr $value) {
  $key: $value
}

int main(void) {
  int open = 1, close = 2;
  Map handlers = %{
    $($project.handler("open", open)),
    $($project.handler("close", close))
  };
  return handlers.len() == 2 ? 0 : 1;
}
```

`Stmt` macros are useful for a small, repeated control-flow shape:

```x2c
~
macro Stmt $project.guard(Expr $condition) {
  if (!$condition) return 0;
}
~
~int positive(int value) {
~  $project.guard(value > 0);
~  return value;
~}
```

A `Stmt` macro whose body is one expression statement, or one invocation of
another `Stmt` macro, can write it after `=>`, like an expression macro:

```x2c
~
macro Stmt $project.note(Expr $value) =>
  printf("%s\n", %"value $($value)");
~
~int main(void) {
~  $project.note(42);
~  return 0;
~}
```

That expression may also be a call to a `meta` function that returns a
statement, as shown under
[Compute with meta functions](#compute-with-meta-functions).

An expression macro is not a statement macro, and a unit macro cannot appear
inside a function. The compiler diagnoses the mismatch at the invocation.

### Private names

Declare scratch bindings normally. A declaration written literally in a macro
body and every literal reference to it receive a private binding for each
expansion:

```x2c
~
#include "meta.x"
meta static List project_type(TypeInfo type) => type.assoc(<type>);

macro Stmt $project.swap(
  Expr $left,
  Expr $right
) {
  $project_type($left) temporary = $left;
  $left = $right;
  $right = temporary;
}
~
~int main(void) {
~  int left = 1;
~  int right = 2;
~  $project.swap(left, right);
~  return left == 2 && right == 1 ? 0 : 1;
~}
```

The helper returns a type into the declaration's type slot. The same explicit
call form also supplies expressions and generated names in their own slots.

Each invocation receives a compiler-private binding for `temporary`, so a
name the body declares never collides with caller source.

### Free names resolve where the expansion lands

A name the body reads without declaring means what it would mean if the
expansion were written by hand at the call site. A caller's declaration of
that spelling supplies it, including a local:

```x2c
static int scale = 3;

macro Expression $scaled(Expr $value) => $value * scale;

int main(void) {
  printf("%d\n", $scaled(2));
  {
    int scale = 10;
    printf("%d\n", $scaled(2));
  }
  return 0;
}
```

```text
6
20
```

The second call reads the block's `scale`, as `2 * scale` written there
would. Names the caller writes in arguments resolve at the call site too. A
macro that should reach a caller's variable by design takes the name as a
`Name` argument, as `$repeat` does in the
[reference](../reference/language.md#hygiene-and-generated-names).

### Keep a file-scope name with `using`

A macro that must reach a particular file-scope declaration, whatever the
caller declares, lists that name with `using`. An `Expression` macro writes
the list after its signature. A braced body writes it as its first item:

```x2c
static int scale = 3;
static int bump(int value) => value + 1;

macro Expression $scaled(Expr $value) using scale => $value * scale;

macro Stmt $bumped(Name $target) {
  using bump;
  $target = bump($target);
}

int main(void) {
  int scale = 10, bump = 0;
  printf("%d\n", $scaled(2));
  $bumped(bump);
  printf("%d %d\n", scale, bump);
  return 0;
}
```

```text
6
10 1
```

Each listed name keeps the declaration that file scope supplies where the
macro is written: a function, object, or enumerator of that file or of a
header it includes, or a native name such as a C library function. The
expansion reads that declaration with its type. A caller's local of the same
spelling receives a separate generated C spelling, so the expansion still
reaches the file-scope name. Only names, not types, can be listed; a type
name in a body always resolves where the expansion lands.

List every helper that a macro calls when the macro is meant for other
files. A helper reached from another translation unit must be nonstatic, or
`module` within a module unit, because a `static` function is private to
its own unit.

### Generated names with `using $name`

Use a leading `using $name;` directive only when a `meta` call or a
nested macro needs a private `Name` hole before an ordinary declaration can
introduce it:

<!-- ignore: project_generate is the external generator being illustrated -->
```x2c,ignore
macro Unit $project.generated() {
  using $private;
  @project_generate($private)
}
```

The directive creates syntax identity, not runtime storage. It can therefore
name a generated helper function or label as well as an automatic variable.
All `using` directives must precede the body's ordinary items.

The three spellings of `using` do different things:

| Spelling | Where | Effect |
| --- | --- | --- |
| `using name` | macro signature or first body item | keep the file-scope declaration of `name` where the macro is written |
| `using $name` | first body item | create a fresh private name for each expansion |
| `using &name` | lambda | share a captured local by reference |

## Put reusable macros in ordinary source modules

An ordinary `.x` file may hold runtime code, macro definitions, keyword
aliases, and meta functions. Include the module
wherever its public definitions are needed:

<!-- ignore: project-macros.x is the external file being illustrated -->
```x2c,ignore
#include "project-macros.x"
```

Nonstatic definitions become available at the include line, including through
transitive includes. Use `static macro` or `static keyword` for helpers that
belong only to the declaring file. Ordinary includes are tracked translation
dependencies and each canonical file contributes once per unit; include
cycles terminate without loading a second copy.

A package publishes the nonstatic macros and aliases its entry source and
ordinary includes define. `import "name";` makes that syntax available at the
import position.

Prefer a qualified name such as `$test.run` or `$project.logging.trace` in a
shared module. It identifies the project or library at each call and avoids
ambiguous short global names.

## Decorators transform one target

A decorator receives the following expression or source item as its required
first parameter. Invocation arguments follow normally:

```x2c
macro Decorator $project.trace(
  Function $function,
  Expr $label
) {
  printf(
    "[%s] enter %s\n",
    $label,
    $Code.name($function)
  );
  defer printf("[%s] leave\n", $label);
  @Code.body($function)
}

$project.trace("request")
int answer(int value) {
  return value * 2;
}
~
~int main(void) {
~  return answer(21) == 42 ? 0 : 1;
~}
```

`$Code.name` and `@Code.body` receive the complete captured function.
`Code.name` returns its name, and `Code.body` returns its body as the
sequence that `@` inserts.

There is no semicolon after the decorator invocation. Decorators stack
closest-first, and each expansion must leave exactly one target for the next.
A function decorator preserves the function's original name, storage,
signature, and method ownership.

A statement macro or statement decorator may be used directly as an `if`,
`else`, or loop body when its production contains exactly one statement.
An explicit compound statement or `do { ... } while (0)` counts as one; an
unwrapped sequence of block items does not. The compiler never inserts
braces, so the production still determines scope and control flow.

An `Expr` target makes the decorator a prefix expression:

```x2c
~static int checked(int value) {
~  return value;
~}
macro Decorator $project.checked(Expr $target) =>
  checked($target);
~int main(void) {
~  int value = $project.checked() (20 + 22);
~  return value == 42 ? 0 : 1;
~}
```

Expression decorators bind like a prefix unary operator. They capture the
following primary/postfix, unary, or cast expression before surrounding
binary, conditional, assignment, or comma operators. Parenthesize a larger
target: `$project.checked() value + 1` checks `value`, while
`$project.checked() (value + 1)` checks the complete addition. Chained
expression decorators remain closest-first.

### Give macros local keyword spellings

A `keyword` declaration removes the qualified `$` spelling while preserving
the macro's existing invocation grammar. This makes a parameterized decorator
look like a new control construct without adding a new parser for its header:

```x2c
macro Decorator $control.range(
  Stmt $body,
  Name $index,
  Expr $start,
  Expr $stop
) {
  {
    int begin = $start, end = $stop;
    for (int $index = begin; $index < end; $index++) $body
  }
}

keyword range $control.range;

~static void consume(int value) { printf("%d\n", value); }
~int main(void) {
range(index, 0, 3) {
  consume(index);
}
~  return 0;
~}
```

`range(index, 0, 3) TARGET` is exactly
`$control.range(index, 0, 3) TARGET`. The macro still handles the typed
`Name` and `Expr` arguments, hygiene for its private bounds, and parsing of
the following block.

Ordinary macros can use the same declaration. Their parentheses remain
mandatory, even when they take no arguments:

```x2c
#include "meta.x"
meta static List project_type(TypeInfo type) => type.assoc(<type>);

macro Stmt $control.swap(
  Expr $left,
  Expr $right
) {
  $project_type($left) temporary = $left;
  $left = $right;
  $right = temporary;
}

keyword swap $control.swap;

~int main(void) {
~  int left = 20, right = 22;
  swap(left, right);
~  return left != 22 || right != 20;
~}
```

`Decorator` arguments use the same comma-separated typed and sequence
parameters as direct macro calls. A decorator with no explicit arguments uses
`ALIAS TARGET`; one with arguments uses `ALIAS(arguments) TARGET`. An
all-sequence decorator uses `ALIAS() TARGET` when the sequence is empty, so a
parenthesized target of a zero-argument decorator remains unambiguous.

A `Decl` argument ends at the invocation's comma or closing parenthesis;
`foreach` also accepts `in` after its declaration. The trailing semicolon is
omitted. A `Decl` accepts one declarator with an optional
initializer, or flat destructuring with two or more simple identifier targets.
For example, `foreach(int value in values)` supplies `int value` as one `Decl`
argument.

The declaration and uses are source ordered. A public alias in an included
module becomes available at that include; a `static keyword` declaration
stays in its source file. A module may keep an alias beside its macro:

<!-- ignore: compiler-keywords.x is the external file being illustrated -->
```x2c,ignore
#include "compiler-keywords.x"

swap(left, right);
```

A later alias does not reinterpret an earlier macro template. Use
`static keyword swap $swap;` when the short spelling is private, while the
qualified macro remains public.

## Compute with meta functions

Write compile-time calculations as ordinary x2c functions marked `meta`.
A macro calls one with `$helper(...)`; its captured holes supply code rather
than the future runtime values of those expressions:

```x2c
meta static int project_offset(void) => 2;

macro Expression $project.answer(Expr $base) =>
  $base + $project_offset();

int main(void) {
  printf("%d\n", $project.answer(40));
  return 0;
}
```

```text
42
```

Include `meta.x` when the calculation needs compiler operations for
diagnostics, identifiers, types, bindings, source text or function bodies.
The [meta-function guide](meta-functions.md) introduces these operations;
the [language reference](../reference/language.md#compile-time-calls-and-operations)
specifies them.

A helper can also receive a captured statement, a description of a type
(`TypeInfo`), or the exact source text of an argument (`Source`).
[Generating Code](generating-code.md#calling-a-meta-function-from-a-macro-body)
shows each.

Prefer source templates for generated code and meta functions for the
calculations that supply their arguments. Compile-time code is always x2c.
Lisp remains a runtime library for DSLs and the REPL.

### Generate several views from one table

A meta function can keep one table of facts from which small macros generate
enums, lookup tables, switch cases, declarations, and repetitive functions.
Changing the table then changes every generated form.

Use a table when the outputs repeat the same facts. Write names, types, and
status values explicitly so a reader can understand the generated code without
working through the generator. Keep unrelated outputs as direct source.

## Declare methods and converters before adoption

Shallow collection loads included macro definitions and expands file-scope
`Unit` macros. It applies preceding top-level definitions when the producer
needs them. Generated private helpers stay available in their source
module. Public declarations and protocol rows reach includers. The full parse
binds the retained result without running its producer again.

A generated public function definition can complete a preceding prototype in
the same expansion when their canonical signature and ownership agree.

Put converter and public method prototypes before an adoption so shallow
collection can classify the conformance and downstream code can discover the
functions. Included macro definitions survive intervening preprocessor
includes, so a definition can be included before the headers its invocations
need.

## Choosing the smallest tool

Use:

- a function for runtime computation;
- a meta function for compile-time calculation and compiler queries;
- a protocol for explicit participation in shared typed behavior;
- a macro for repeated source whose invocation has one obvious expansion;
- a decorator for uniform policy on one following expression or source item;
- direct source when generation would hide more than it removes.

Count the macro's definition as well as its calls: a useful macro reduces the
total, preserves useful diagnostics, and makes each binding clear.

For a complete generator built from these pieces, see [Automatic
Differentiation](autodiff.md): a `Type`-hole family for dual numbers, and
`Unit` decorators whose meta functions transform a function's typed code
into its derivative.

For the complete hole grammar, result validation, hygiene rules, limits, and
compiler operations, see [Compile-time macros in the language
reference](../reference/language.md#compile-time-macros).
