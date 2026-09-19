# Meta Functions

A `meta` function is an x2c function the compiler can also run during
translation. It lets you write a macro's implementation in x2c instead of in
compile-time Lisp. The body is ordinary x2c: parameters, locals, `foreach`,
`match`, `String`, `List`, `Array` and `Map`. A macro body calls it the way
it calls a Lisp procedure.

This chapter assumes you have read [Compile-time Macros](macros.md). It does
not assume you know Lisp.

## A complete example

Two files. The first is a `.xmacro` holding the `meta` functions and the
macros that call them. `shape_fields` asks the compiler what a struct holds.
`shape_names` and `shape_reads` turn that answer into syntax.

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

macro Expression $shape.names(Expr $value) => ($(shape_names $value))

macro Expression $shape.reads(Expr $value) => ($(shape_reads $value))
```

The second file imports it and uses the macros.

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

## The `meta` word

Write `meta` first on a function definition. A storage class follows it:

```x2c
meta int poly(int n) => n * n + 3 * n + 1;

meta static String label(String stem, int n) => %"$stem-$n";
```

`static` still means what it always meant about the emitted function. `meta`
adds the compile-time form.

`meta` is contextual. It marks a function only when a function definition
follows it. Everywhere else it is an ordinary identifier:

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

A `meta` declaration needs a body. A prototype is an error, because the
compiler has nothing to run.

## One body, two forms

A `meta` function has a compile-time form and a run-time form. They come
from the same body, so they compute the same answer. `$(name args)` calls
the compile-time form; ordinary call syntax calls the run-time one.

```x2c
meta int poly(int n) => n * n + 3 * n + 1;

int main(void) {
  int seven = 7;
  printf("compile time %d\n", $(poly 7));
  printf("run time     %d\n", poly(seven));
  return 0;
}
```

```text
compile time 71
run time     71
```

## Calling a meta function from a macro body

A macro body reaches compile-time code through `$(...)`. Inside it, `$name`
is the hole's captured syntax. The call is spelled as a Lisp call: the
function name first, then the holes.

```x2c
#include "x2c.x"
#include "meta.x"

typedef struct Point { int x, y, z; } Point;

meta static List field_count(List receiver) =>
  x2c_literal_int(x2c_type_fields(x2c_syntax_type(receiver)).len());

macro Expression $probe.count(Expr $value) => ($(field_count $value))

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
compiler operations built is syntax. `x2c_literal_int`, `x2c_literal_string`
and `x2c_literal_symbol` each return an expression holding a value.

## Importing from a `.xmacro`

A `.xmacro` file may hold `meta` functions beside the macros that call them.
Importing it installs their compile-time forms in the importing unit. The
unit that imports the file includes `meta.x`, because a `.xmacro` borrows
the consuming unit's symbol table:

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

## What the compiler answers

`lib/meta.x` declares the compiler operations a `meta` function can call.
Each is a plain function whose name is the compile-time Lisp name with `_`
for `.`, so `x2c.type.fields` is `x2c_type_fields` from x2c. They are grouped
here by the task, not by signature; the
[module reference](../library/modules/meta.md) lists every declaration, and
the [language reference](../reference/language.md#the-same-operations-from-x2c)
gives their semantics.

**Building identifiers, literals and expressions.** `x2c_ident` checks a
spelling and returns identifier syntax. `x2c_literal_int`,
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

macro Expression $probe.twice(Expr $value) => ($(call_of "twice" $value))

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
a macro body cannot derive them from the syntax it captured.

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

macro Expression $probe.word(Expr $value) => ($(one_word $value))

int main(void) {
  int seconds = 90;
  printf("word %s\n", $probe.word(seconds));
  return 0;
}
```

```text
word seconds
```

Writing `$probe.word(seconds * 2)` instead reports the message at that
invocation:

```text
sample.x:15:23: macro: this argument must be one word
  printf("word %s\n", $probe.word(seconds * 2));
                      ^
```

Two signatures differ in shape from their Lisp spellings.
`x2c_expr_call` takes its arguments as one `List`, and `x2c_type_value`
returns `int`.

## A function that reaches a compiler operation has no run-time form

The compiler operations exist only inside a compiler. A `meta` function that
calls one, directly or through another `meta` function, therefore has no
valid run-time form, and the compiler emits no definition for it. A call to
one from a run-time body is diagnosed where it is written. Calling
`field_count` from an earlier section at run time gives:

```text
sample.x:19:22: macro: 'field_count' can only be called at compile time
    int n = field_count(point);
                       ^
  note: reason: it reaches a compiler operation, so no unit emits a
  definition for it; call it from a macro or another meta function
```

In the first example, the generated C mentions none of `shape_fields`,
`shape_names` or `shape_reads`.

A `meta` function that reaches no compiler operation, like `label` above,
keeps both forms and is emitted normally.

## Constant calls are folded

Where both forms agree, the compiler may answer a call from the
compile-time form. A call whose arguments are all compile-time constants is
replaced by its answer; the same call with a local stays a call.

```x2c
meta static int width(String text) => text.len() * 2;

int main(void) {
  String name = "abcd";
  printf("constant %d\n", width("abcd"));
  printf("local    %d\n", width(name));
  return 0;
}
```

```text
constant 8
local    8
```

The generated C shows the difference:

```text
printf("constant %d\n", 8);
printf("local    %d\n", width(name));
```

This is an optimization. The answer is the same either way, so you do not
need to arrange for it. The compiler leaves a call alone when the two forms
could disagree: a `String` result is left alone because its caller owns the
value, and a function reading file-scope state is left alone because the
compile-time form reads its own table.

## What a meta body may not contain today

The compiler translates the body into a compile-time form before it runs.
Some constructs have no such form. The compiler reports this at the `meta`
marker and names the reason. A body holding a struct or union gives:

```text
sample.x:3:1: macro: this function cannot run at compile time
  meta static int mt_scan(int n) {
  ^^^^
  note: reason: a struct or union, which has no compile-time representation
```

The refusals a body is most likely to meet:

| Construct | Reason in the diagnostic |
| --- | --- |
| `goto` | `a goto has no lowering` |
| `defer` | `defer, because a compile-time function does not free its values: the evaluator owns them` |
| a struct or union local, or a `.` field read | `a struct or union, which has no compile-time representation` |
| a `switch` arm running into the next | `a switch arm that falls through into the next` |
| a call with no compile-time binding | `no binding for NAME` |

A compile-time value is a Lisp value, so a struct would have to become a
`Map` keyed by field name, which reads back as a reference where the source
wrote a value. `defer` is refused because the evaluator owns every value a
compile-time function makes, so freeing one would take it away. `goto` and
a falling-through `switch` arm are refused because the compile-time form has
no place to jump to.

Ordinary control flow is carried: `if`, `while`, `for`, `do`, `switch` with
`break` or `return` in each arm, `foreach`, `break`, `continue`, recursion,
`match`, literal templates, lambdas and `Func` values, `String`, `List`,
`Array` and `Map` operations, and file-scope state.

The last row covers the most common case. A call inside a `meta` body
resolves against the compile-time library, and an operation with no binding
there declines the whole function. A body calling `time` reports
`reason: no binding for time`. Prefer the `String`, `List`, `Array` and
`Map` operations the shipped macro files already use.

## Compile-time arithmetic today

Keep compile-time arithmetic in a `meta` function to `int` for now.
Arithmetic on narrow and unsigned integer types and on floating values does
not yet agree between the two forms, and is being corrected on this branch.
