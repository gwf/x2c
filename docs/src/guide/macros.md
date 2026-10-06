# Compile-time Macros

For using the shipped `class`, `$scope`, `$let`, `$lock`, and `$auto`
facilities, see [Classes and System Macros](system-macros.md). This chapter
explains how to author macros, including the ordinary facilities those
definitions compose.

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

Use `with` when the repeated source is local to one braced block and does not
need a reusable macro:

```x2c
~typedef struct Point { int x, y; } Point;
~int main(void) {
~  Point point = { 0 };
with point {
  _.x = 1;
  _.y = 2;
}
~  return point.x == 1 && point.y == 2 ? 0 : 1;
~}
```

The optional `as name` form replaces `_` with a chosen lexical name. Like a
macro hole, every use substitutes the original expression and may evaluate it
again; `with` does not create a runtime temporary. It declares no reusable
generator and has no name outside its block.

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
invoked, like every macro's free names. Names the caller writes in
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

`with` remains the smaller choice when the only need is repeated substitution
of one expression. A local macro is worth defining when it needs typed
holes, declarations, control flow, computed source, or more than one input.

## Holes say what binds

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

A trailing `...` makes the final hole a sequence. The replacement uses the
same ellipsis to splice the captured sequence:

```x2c
~
macro Expression $project.call(
  Expr $callee,
  Expr $arguments...
) =>
  $callee($arguments...);
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
macro Stmt $fail(Expr $cause, Expr $op, Expr $fields...) {
  raise %($cause (operation ${$op}) $fields...);
}
```

Here `${$op}` inserts the captured x2c expression into the literal payload.
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
`Entry` holes capture complete rows, and a trailing `...` captures or inserts
a row sequence. A `Map` literal reads quoted data, so `${...}` crosses into
x2c before invoking either a `$handler(...)` or a keyword alias:

```x2c
macro Entry $project.handler(Literal $key, Expr $value) {
  $key: $value
}

int main(void) {
  int open = 1, close = 2;
  Map handlers = %{
    ${$project.handler("open", open)},
    ${$project.handler("close", close)}
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
  printf("%s\n", %"value ${$value}");
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

### Generated names and `using`

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

Each invocation receives a compiler-private binding for `temporary`, so
generated names cannot collide with caller source. A macro captures no
bindings: a name its body reads without declaring resolves where the
expansion lands, as do the names a caller writes in its arguments. A
body that must reach a file-scope declaration that a caller's local could
hide lists it with `using name;`, as the
[reference](../reference/language.md#hygiene-and-generated-names) shows.

Use a leading body directive only when compile-time Lisp or a nested macro
needs a private `Name` hole before an ordinary declaration can introduce it:

<!-- ignore: project_generate is the external generator being illustrated -->
```x2c,ignore
macro Unit $project.generated() {
  using $private;
  $project_generate($private)...
}
```

The directive creates syntax identity, not runtime storage. It can therefore
name a generated helper function or label as well as an automatic variable.
All `using` directives must precede the body's ordinary items. The older
signature `using` form remains accepted for compatibility; lambdas separately
use `using &name` for reference capture.

## Put reusable macros in ordinary source modules

An ordinary `.x` file may hold runtime code, macro definitions, keyword
aliases, meta functions, and top-level compile-time Lisp. Include the module
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

`$(import "helpers.xlisp")` remains the loading form for Lisp files. A Lisp
import executes in the translation-unit Lisp session and rejects import
cycles.

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
~
#include "meta.x"
meta static String project_name(List fn) => x2c_function_name(fn);
meta static List project_body(List fn) => x2c_function_body(fn);

macro Decorator $project.trace(
  Function $function,
  Expr $label
) {
  printf(
    "[%s] enter %s\n",
    $label,
    $project_name($function)
  );
  defer printf("[%s] leave\n", $label);
  $project_body($function)...
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

The helpers receive the complete captured function. One returns its name;
the other returns its body as the sequence inserted by `...`.

There is no semicolon after the decorator invocation. Decorators stack
closest-first, and each expansion must leave exactly one target for the next.
A function decorator preserves the function's original name, storage,
signature, and method ownership.

A statement macro or statement decorator may be used directly as an `if`,
`else`, or loop body when its production contains exactly one statement.
An explicit compound statement or `do { ... } while (0)` counts as one; an
unwrapped sequence of block items does not. The compiler never inserts
braces, so the production still decides scope and control flow.

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

A `Decl` argument ends at the invocation's comma or closing parenthesis, so
its trailing semicolon is omitted. It accepts one declarator with an optional
initializer, or flat destructuring with two or more simple identifier targets.
For example, `foreach(int value, values)` supplies `int value` as one `Decl`
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
the [language reference](../reference/language.md#the-same-operations-from-x2c)
specifies them.

A `Stmt` macro can also call its helper with the arrow form. The helper
receives captured statements as code and may return any statement that fits
where the macro is invoked. `$!{ ... }` quotes statements the way
`$!( ... )` quotes an expression:

```x2c
#include "meta.x"
meta static List project_logged(List code) =>
  $!{ { puts("before"); $code puts("after"); } };

macro Stmt $project.logged(Stmt $code) => $project_logged($code);

int main(void) {
  int ready = 1;
  $project.logged(if (ready) puts("ready"););
  return 0;
}
```

```text
before
ready
after
```

A `meta` parameter declared `TypeInfo` receives a description of the
argument's type, including a struct or union's fields in declaration
order. Pass the hole twice to receive both its code and its type. A quotation
uses each field name to build a member read:

```x2c
#include "meta.x"
meta static List project_fields(List receiver, TypeInfo type) {
  Array reads = [];
  foreach (List field, type.assoc(<fields>)) {
    String member = field.car();
    reads.push($!( $receiver.$member ));
  }
  List items = reads.list_free();
  return $!( { $items... } );
}
macro Expression $project.fields(Expr $value) =>
  $project_fields($value, $value);
~typedef struct Point { int x, y; } Point;
~int main(void) {
~  Point p = { 2, 3 };
~  int values[2] = $project.fields(p);
~  return values[0] != 2 || values[1] != 3;
~}
```

A `TypeInfo` parameter's `methods` part names the type's direct dotted methods.
A generator can test for one and build the dotted call, which the compiler
resolves as it would the same call in source:

```x2c
#include "meta.x"
meta static List project_write(TypeInfo type, List receiver, List value) {
  List methods = type.assoc(<methods>);
  if (!methods.contains("write")) return %();
  return $!( $receiver.write($value) );
}
```

The list does not search delegate fields. A delegated result would also need the
field-projected receiver, which this operation does not return. Generated
dotted calls still use delegation during ordinary expression resolution.

To read the exact source text of a complete captured argument, declare
the parameter `Source` and use `x2c_source_text`:

```x2c
#include "meta.x"
meta static String project_text(Source value) => x2c_source_text(value);
macro Expression $project.source(Expr $value) => $project_text($value);

int main(void) {
  return strcmp($project.source(1 /* kept */ + 2),
                "1 /* kept */ + 2");
}
```

Passing a complete capture to a meta helper preserves the source information
for this query. Forwarding it through another source macro does too.
Constructing or selecting an AST subtree does not invent source text; use
`List.repr()` to render code data.

`x2c_embed_text` reads a regular text file into a compile-time String and
records it as a build dependency. A captured String literal retains the
caller's file location for resolving a relative path:

<!-- ignore: notice.txt is the external file being illustrated -->
```x2c,ignore
#include "meta.x"
meta static String project_notice(Source path) => x2c_embed_text(path);
macro Expression $project.notice(Literal $path) => $project_notice($path);

String notice = $project.notice("notice.txt");
```

A captured path stays relative to its caller even when the macro is defined
in an imported file. A project meta function also accepts an absolute
String path; a relative one needs the `Source` that locates it.

Empty files are valid. Directories, embedded NUL bytes, unreadable files and
files too large for a String are rejected.

Prefer source templates for generated code and meta functions for the
calculations that supply their arguments. Use the optional `$(...)` Lisp
entry when integrating existing Lisp helpers or changing the compiler's Lisp
session. For example, `$(project_offset)` calls the helper above from Lisp.
Local macro names are lexical; Lisp definitions instead remain available for
the rest of the translation unit after the defining block ends.

### Generate several views from one table

A meta function can keep one table of facts from which small macros generate
enums, lookup tables, switch cases, declarations, and repetitive functions.
Changing the table then changes every generated form.

Use a table when the outputs repeat the same facts. Write names, types, and
status values explicitly so a reader can understand the generated code without
working through the generator. Keep unrelated outputs as direct source.

## Declare methods and converters before adoption

Shallow collection loads included macro definitions and expands file-scope
`Unit` macros. It evaluates preceding top-level Lisp contributions when the
producer needs them. Generated private helpers stay available in their source
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
compiler Lisp SDK, see [Compile-time macros in the language
reference](../reference/language.md#compile-time-macros).
