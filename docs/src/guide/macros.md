# Compile-time Macros

x2c macros generate source at compile time using C-like x2c syntax. They bind
parsed, typed source rather than preprocessor text. The compiler constructs,
binds, and types their templates and arguments as it does ordinary source.
Hygiene keeps generated names from colliding with names in the caller. A
reusable global macro is invoked explicitly with a `$` name; a local macro uses
a bare name inside its defining block. Both declare the syntax kinds they
accept and produce one declared kind of source.

Choose according to what the code does:

- a function computes with runtime values;
- a macro constructs source at translation time;
- a decorator transforms the expression or source item immediately following
  it.

Start with templates. Use compile-time Lisp only when the result requires
computation.

## A first expression macro

The result kind follows `macro`; typed holes appear in the invocation pattern:

```x2c
~
macro Expression $project.minutes(Expr $value) => (
  $value * 60
)
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
macro Expression scaled(Expr $input) => (
  $input * scale
)

return scaled(value);
~}
```

The definition is visible from that point to the end of the block and through
nested blocks. An inner definition of `scaled` temporarily shadows it; a later
definition in the same block replaces it for following calls. Literal
references such as `scale` retain the exact parameter or preceding local they
named at the definition, even if an inner block later declares the same
spelling. Hole arguments still retain their caller bindings.

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
| `Statement` or `Block` | one block item |
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
) => (
  $callee($arguments...)
)
~
~static int add(int left, int right) {
~  return left + right;
~}
~
~int main(void) {
~  return $project.call(add, 20, 22) == 42 ? 0 : 1;
~}
```

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
macro Unit $value.family(Type $box, Type $item) => {
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
| `Statement` | statement |
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
macro Entry $project.handler(Literal $key, Expr $value) => {
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

`Statement` macros are useful for a small, repeated control-flow shape:

```x2c
~
macro Statement $project.guard(Expr $condition) => {
  if (!$condition) return 0;
}
~
~int positive(int value) {
~  $project.guard(value > 0);
~  return value;
~}
```

An expression macro is not a statement macro, and a unit macro cannot appear
inside a function. The compiler diagnoses the mismatch at the invocation.

### Generated names and `using`

Declare scratch bindings after `using` when a template needs caller-local
temporaries:

```x2c
~
macro Statement $project.swap(
  Expr $left,
  Expr $right
) using $temporary => {
  $(x2c.syntax.type $left) $temporary = $left;
  $left = $right;
  $right = $temporary;
}
~
~int main(void) {
~  int left = 1;
~  int right = 2;
~  $project.swap(left, right);
~  return left == 2 && right == 1 ? 0 : 1;
~}
```

Each invocation receives a compiler-private binding for `$temporary`.
Definition-local literal names resolve where the macro was defined, captured
names keep their caller bindings, and generated names cannot collide with
caller source. A local macro's literal references to parameters and preceding
locals also keep those exact bindings when an inner declaration uses the same
spelling.

## Put reusable macros in imports

An `.xmacro` file may contain macro definitions and top-level compile-time
Lisp. Import it explicitly:

<!-- ignore: project-macros.xmacro is the external file being illustrated -->
```x2c,ignore
$(import "project-macros.xmacro")
```

Imports resolve relative to the importing file, become tracked translation
dependencies, load once, and reject cycles. A normal `.xlisp` import executes
in the same translation-unit Lisp session but does not contain macro
definitions.

Prefer a qualified name such as `$test.run` or `$project.logging.trace` in a
shared import. It identifies the project or library at each call and avoids
ambiguous short global names.

## Decorators transform one target

A decorator receives the following expression or source item as its required
first parameter. Invocation arguments follow normally:

```x2c
~
macro Decorator $project.trace(
  Function $function,
  Expr $label
) => {
  printf(
    "[%s] enter %s\n",
    $label,
    $(x2c.literal.string (x2c.function.name $function))
  );
  defer printf("[%s] leave\n", $label);
  $(x2c.function.body $function)...
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
macro Decorator $project.checked(Expr $target) => (
  checked($target)
)
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
  Block $body,
  Name $index,
  Expr $start,
  Expr $stop
) using $begin, $end => {
  {
    int $begin = $start, $end = $stop;
    for (int $index = $begin; $index < $end; $index++) $body
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
macro Statement $control.swap(
  Expr $left,
  Expr $right
) using $temporary => {
  $(x2c.syntax.type $left) $temporary = $left;
  $left = $right;
  $right = $temporary;
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

The declaration and uses are source ordered and local to one `.x` file. An
included `.x` file may declare and use its own aliases, including across its
own includes, but those aliases do not leak into the including source.

A `.xmacro` import may package macro definitions with their aliases:

<!-- ignore: compiler-keywords.xmacro is the external file being illustrated -->
```x2c,ignore
$(import "compiler-keywords.xmacro")

swap(left, right);
```

The aliases become visible at the import in that `.x` file only. Every source
file that wants them imports the pack explicitly; including a file that uses
the pack does not import its aliases. This lets a project use private keyword
spellings without placing them in `x2c.x` or another consumer prelude.

An alias is a contextual parser match, not a globally reserved word. An
ordinary or parameterized alias is claimed only as `ALIAS(...)`, so the name
may still be a type, declaration, field, label, or uncalled function. Its
direct call or cast spelling is claimed by the macro. A zero-argument bare
decorator is broader: the parser claims its name at every position compatible
with its target, which can overlap an expression read or a declaration
beginning with a same-named typedef. Prefer parenthesized aliases in shared
packs and introduce bare decorators only after checking those positions.

Aliases do not create arbitrary grammar. The lexical `with expression { ... }`
statement is contextual grammar built into the language, not a macro alias.
Other forms such as `loop item in values` or a semicolon-separated control
header would require separate parser support. Result positions, decorator
targets, terminators, hygiene, expansion limits, and compile-time restrictions
remain those of the aliased macro.

Use a decorator to place checking, tracing, validation, or checked foreign
binding directly beside the expression or source item it affects.
Do not use a decorator for type registration, protocol participation, or
receiverless startup and shutdown. Those have their own declarations.

## Compile-time Lisp is where computation happens

`$(...)` evaluates Lisp during translation. Inside a macro body, hole names
refer to the captured syntax:

```x2c
~
$(defun project-offset () 2)

macro Expression $project.answer(Expr $base) => (
  $base + $(project-offset)
)
~
~int main(void) {
~  return $project.answer(40) == 42 ? 0 : 1;
~}
```

The compiler supplies operations for diagnostics, identifiers, types, bindings,
literals, function projections, structural matching, and invocation location.
The [language
reference](../reference/language.md#compile-time-lisp-and-imports) lists them.

Local macro names are lexical, but compile-time Lisp is not. A local macro may
define or change Lisp state, and that state remains available for the rest of
the translation unit after the block ends.

`x2c.type.fields` lets a macro walk a complete struct or union in source
order without reconstructing its declaration. Pair each returned name with
`x2c.expr.field` when generated code needs ordinary typed access through a
value or pointer receiver:

```text
(map (lambda (field)
  (x2c.expr.field receiver (car field)))
  (x2c.type.fields (x2c.syntax.type receiver)))
```

`x2c.method.resolve` is the optional form of direct dotted method lookup. A
generator can inspect the returned callee's function `Type` or compose it with
`x2c.expr.call`; a missing method returns `nil` instead of producing a type
diagnostic:

```text
(let ((callee (x2c.method.resolve type "write")))
  (if callee (x2c.expr.call callee receiver value) nil))
```

It does not search delegate fields. A delegated result would also need the
field-projected receiver, which this operation does not return. Macro-generated
dotted call syntax still uses delegation when ordinary expression resolution
later sees the call.

When spelling matters rather than meaning, `x2c.source.text` reads the exact
text of a complete captured argument:

```x2c
macro Expression $project.spelling(Expr $value) => (
  $(x2c.literal.string (x2c.source.text $value))
)

int main(void) {
  return strcmp($project.spelling(1 /* kept */ + 2),
                "1 /* kept */ + 2");
}
```

Forwarding a capture through another macro preserves that text. Constructing
or selecting an AST subtree does not invent source text; use standard Lisp
`repr` when canonical AST rendering is intended.

`x2c.embed.text` reads a regular text file into a compile-time `String` and
records the canonical file as a build dependency. A `String` path is relative
to the file containing that Lisp form. A captured `String` literal is relative
to the caller file where the literal was written:

<!-- ignore: notice.txt is the external file being illustrated -->
```x2c,ignore
macro Expression $project.notice(Literal $path) => (
  $(x2c.literal.string (x2c.embed.text $path))
)

String notice = $project.notice("notice.txt");
```

The returned value stays compile-time data; use `x2c.literal.string`
explicitly when generated code needs a runtime `String`. Empty files are valid.
Directories, embedded NUL bytes, unreadable files, and files too large for a
`String` are rejected.

Most macros should not need those operations. A source-shaped template keeps
the binding and generated result visible to a reader. Use Lisp when a template
must compute a value, inspect a declaration, select among shapes, or generate a
checked name. If the Lisp and AST manipulation is longer or harder to explain
than the repeated source, keep the source.

### Generate several views from one table

Compile-time Lisp can keep one table of facts from which small macros generate
enums, lookup tables, switch cases, declarations, and repetitive functions.
Changing the table then changes every generated form.

Use a table when the outputs repeat the same facts. Write names, types, and
status values explicitly so a reader can understand the generated code without
working through the Lisp. Keep unrelated outputs as direct source.

## Declare methods and converters before adoption

Shallow collection loads `.xmacro` imports and expands their file-scope unit
macros. Generated private helpers remain available to later macro invocations
in the same source file, while generated public declarations and protocol rows
remain visible to importing units. A generated public function definition may
complete a prototype earlier in the same expansion when both have the same
canonical signature and ownership.

Put converter and public method prototypes before an adoption so shallow
collection can classify the conformance and downstream code can discover the
functions. Imported macro definitions survive intervening preprocessor
includes, so a definition can be imported before the headers its invocations
need.

## Choosing the smallest tool

Use:

- a function for runtime computation;
- a protocol for explicit participation in shared typed behavior;
- a macro for repeated source whose invocation has one obvious expansion;
- a decorator for uniform policy on one following expression or source item;
- direct source when generation would hide more than it removes.

Count the macro's definition as well as its calls: a useful macro reduces the
total, preserves useful diagnostics, and makes each binding clear.

For the complete hole grammar, result validation, hygiene rules, limits, and
compiler Lisp SDK, see [Compile-time macros in the language
reference](../reference/language.md#compile-time-macros).
