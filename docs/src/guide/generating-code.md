# Generating Code

A [`meta` function](meta-functions.md) can take the code being compiled as a
`List`, inspect it, and return new code for the compiler to insert. Read
[Compile-time Macros](macros.md) first. The macro declares
what code to capture; the `meta` function implements the transformation
in x2c. Include `meta.x` to use the compiler's operations: the methods of
`Code` and `Type`, and the `x2c_` helpers.

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

meta static List field_count(TypeInfo type) =>
  $!int{ ${((List) type.assoc(<fields>)).len()} };

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

`field_count` declares its parameter `TypeInfo`, so it receives a description
of the argument's type rather than its code. The compiler computes that
description at the `$` call:

```text
((name "Point") (kind struct) (type ("Point"))
 (fields (("x" (int)) ("y" (int)) ("z" (int)))) (methods ()))
```

`name` is the type's name, or `""` when it has none. `kind` is `struct`,
`union`, `enum`, `pointer`, `scalar` or `other`. `type` is the canonical
type, and `fields` lists the `(name type)` rows of a struct or union's
named fields in declaration order. `methods` lists the names of the type's
direct dotted methods. Read a part with `List.assoc`. Pass the same hole twice when a function needs both the code
and its type, as `shape_reads` does below.

The function's result determines the expansion. A `List` that a
quotation built represents code. A typed quotation of one value, such as
`$!int{ $count }` or `$!String{ $name }`, is an expression holding that
value.

A `Stmt` macro can use the same arrow form. Its body is then the statement
`$helper(args);`, and the helper may return any statement that fits where
the macro is invoked, not only an expression:

```x2c
#include "x2c.x"
#include "meta.x"

meta static List repeated(List code) => %(block $code $code);

macro Stmt $sample.twice(Stmt $code) => $repeated($code);

int main(void) {
  int n = 0;
  $sample.twice(n += 2;);
  $sample.twice(if (n == 4) puts("four"););
  printf("%d\n", n);
  return 0;
}
```

```text
four
four
4
```

`repeated` receives each captured statement as code and returns a block
that holds it twice. The second invocation passes an `if` statement, which
an expression position could not accept. A `$helper(args);` statement in
an ordinary function may also return a statement. There, only an expression
node, a macro application, a quotation, or an identifier is code. A
`%(block ...)` such as the one `repeated` builds is data there and becomes a
runtime `List` value. A helper for ordinary code therefore returns
statements as a `$!{ ... }` quotation.

### Methods, source text, and embedded files

A `TypeInfo` parameter's `methods` part lists the type's direct dotted methods.
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
the parameter `Source` and use `Code.source_text`:

```x2c
#include "meta.x"
meta static String project_text(Source value) => Code.source_text(value);
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

## Source templates from meta functions

A Unit or Stmt macro used as an expression inside a meta function
constructs a deferred template invocation. Its arguments are values computed
by the meta function. The returned code expands when inserted into the
program, using ordinary macro substitution, scope and binding rules.
Expression macros retain their usual expansion behavior.

```x2c
macro Unit $sample.make_function(Name $name, Expr $result) {
  int $name(void) { return $result; }
}

meta static List build_function(String name, int n) {
  List node = $sample.make_function(name, n * 2);
  return %($node);
}

macro Unit $sample.make_answer() { @build_function("answer", 21) }

$sample.make_answer();
int main(void) {
  printf("%d\n", answer());
  return 0;
}
```

```text
42
```

The constructor returns one code node. The helper wraps it in a List because
`@` inserts a sequence of nodes. It does not return an already expanded
function declaration for the helper to inspect. Name, Type, parameter and
statement captures still follow the source macro's declared hole kinds.

A decorator can make that choice from the function it captures. Here the
`meta` helper selects one of two named Stmt templates, then the decorator
inserts the selected invocation into the function body:

```x2c
#include "x2c.x"
#include "meta.x"

static int calls = 0;

macro Stmt $sample.counted(Stmt @body) {
  calls++;
  @body
}

macro Stmt $sample.plain(Stmt @body) {
  @body
}

meta static List choose_body(List function) {
  List body = Code.body(function);
  String name = Code.name(function);
  List node = name == "tracked" ? $sample.counted(body) : $sample.plain(body);
  return %($node);
}

macro Decorator $sample.count_if_tracked(Function $function) {
  @choose_body($function)
}

$sample.count_if_tracked()
static int tracked(void) { return 7; }

$sample.count_if_tracked()
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

The reverse gradient generator in `packages/autodiff/src/autodiff-macros.x`
uses this pattern.
Its `ad_reverse_with` returns an invocation of the `ad.gradient` source
macro. The macro contains the generated function declaration, tape storage,
reverse-pass label and cleanup. Meta helpers compute the parameter and
statement sequences. The macro owns the fresh scratch names and passes those
same names to the fragment helpers, keeping all generated references in the
intended function scope.

## Quoting code with `$!`

A template that a `meta` function uses once can be written where it is used.
`$!( expression )` builds an expression, `$!{ items }` builds statements, and
`$!Unit{ ... }`, `$!Field{ ... }`, or another category name before the braces
builds that kind of code. A `$name` inside refers to the function's local
`name` and inserts its value: syntax where the position takes syntax, and a
number, String, or Symbol as a literal. `@name` splices a `List` local.
`${expression}` inserts any value; see below. Each local's first position determines what it fills.

```x2c
#include "x2c.x"
#include "meta.x"

meta static List numbered(List subject, List arms) {
  Array cases = [];
  int index = 0;
  foreach (List arm, arms) {
    cases.push($!{ if ($subject == $index) $arm });
    index++;
  }
  return cases.list_free();
}

macro Stmt $sample.choose(Expr $subject, Stmt @arms) {
  @numbered($subject, $arms)
}

int main(void) {
  int pick = 1;
  $sample.choose(pick, printf("zero\n");, printf("one\n");, printf("two\n"););
  return 0;
}
```

```text
one
```

A quotation is an anonymous macro applied at once to the locals its body
names, so it follows the same rules as any template: arguments arrive as the
syntax or values the locals hold, names the body declares are private to the
expansion, and other names resolve where the code lands. It keeps nothing
from the function once it has been applied. Inside a `%(...)` List, `$`
inserts a value, so bind a quotation to a local first and insert the local.
`$` inserts one value and `@` splices a sequence in templates and
quotations. Runtime List literals use the same prefixes. Native C varargs
retain their `...` spelling. An `@name` sequence splices into call arguments
and braced initializers such as `$!( { @items } )` or `(T){ $first, @rest }`,
and `%[@items]` Array literals; Map entries splice as `%{${@rows}}`.
A quotation expands where code is bound, spliced, or resolved: return it,
pass it to a slot, or use it as another quotation's hole. A quotation inside
hand-built expression syntax, such as a call's argument list or a declaration
initializer, expands when the compiler resolves that expression.

A local declared `Type` fills a type position, which lets a quotation
declare a variable whose type it computes:

<!-- ignore: a meta function fragment without its includes -->
```x2c,ignore
meta static List counter(String name) {
  Type type = %(unsigned);
  return $!{ $type $name = 0; };
}
```

A `Type` spells C type keywords such as `unsigned` and `char`, and the `*`
of a pointer, as Symbols. It spells every other type name as a String:
`%("String")`, `%(* "Point")`, `%(struct "Tag")`. `%(String)` holds an
`Atom`, so it is an error where it fills a type. The compiler reports
`type name 'String' must be a String: write %("String")`.

### Holes that name an expression

A `$name` hole needs a local. When the value is a field, an element, or the
result of a call, `${expression}` inserts it without one:

```x2c
#include "x2c.x"
#include "meta.x"

typedef struct Call { List callee; List arguments; Type result; } Call;

meta static List scaled_call(List callee, List a, List b) {
  Call d = {.callee = callee, .arguments = %($a $b), .result = %(int)};
  return $!( ({
    ${d.result} value = ${d.callee}(@{d.arguments});
    value * ${d.arguments.len()};
  }) );
}

macro Expression $sample.scaled(Expr $f, Expr $a, Expr $b) =>
  $scaled_call($f, $a, $b);

static int sum(int a, int b) => a + b;

int main(void) {
  printf("%d\n", $sample.scaled(sum, 2, 5));
  return 0;
}
```

```text
14
```

The braces hold ordinary code of the function that contains the quotation.
The function evaluates each `${...}` once, when it evaluates the quotation,
before the quotation builds its code. Holes are evaluated in the order they
are written. Names in the braces resolve where the quotation is written. A
name that the quotation's body declares is not visible in the braces,
because the body is code for another place. A `${...}` hole therefore means
the same as a local declared just before the quotation and named with `$`:

<!-- ignore: a meta function fragment without its includes -->
```x2c,ignore
return $!( ${d.callee}(@{d.arguments}) );
// means
List callee = d.callee;
List arguments = d.arguments;
return $!( $callee(@arguments) );
```

The expression's declared type gives the hole its kind, as a local's type
does. A `Type` expression fills a type position, as `${d.result}` does
above. A `String`, `int`, or `Symbol` expression inserts a literal, so
`${d.arguments.len()}` inserts `2`. A `List` expression inserts the syntax it
holds. `@{expression}` splices a `List`, like `@name`. Each `${...}` or `@{...}` is
a separate hole, even when two are spelled alike.

A `${...}` belongs to the innermost quotation that contains it. To put one
quotation's code inside another, write the inner quotation as a hole:
`$!( $inner * ${$!( $a - $one )} )` builds the inner code first and inserts
it.

Inside a `%(...)`, `%[...]`, `%{...}`, or `%"..."` literal in a quotation's
body, `${...}` keeps its literal meaning: it inserts a value when the built
code runs. Write `${${expression}}` there to insert a value that the function
computes. A template Array splices a computed sequence through the same
code boundary: `%[${@{items}}]`. This constructs template slots; ordinary
Arrays and Maps do not support runtime splicing. A List's `@{expression}`
still runs when the generated program constructs that List.

Literal characters need no new staging operator. Write an ordinary string
such as `"$ @"`, or `%"\$ @"` for a percent string. Quoted atom escapes
such as `%(\$ \@)` preserve sigils as data.

`${...}` works only in quotations. A named template has no function to
evaluate it in; it computes with a `$meta(...)` call or a `$(...)` slot,
which run where it expands.

### Code that knows its type

A quotation is bound where it lands, so until then its code has no type.
Sometimes the code a function builds must state its type at once: another
operation reads the type before the code lands, or the code goes where
nothing binds it again. Write the type between `$!` and the braces that hold
the expression:

<!-- ignore: a meta function fragment without its includes -->
```x2c,ignore
meta static List doubled(List value) {
  List twice = $!double{ $value * 2 };
  // Code.type(twice) is (double) already.
  return twice;
}
```

`$!T{ expression }` builds the expression where it is written and gives it
the type `T`. `T` is one identifier that names a type, such as `int` or
`String`. Put any other type in parentheses: a type of several words, as in
`$!(unsigned long){ ... }` or `$!(char *){ ... }`, or a `Type` local or
`${...}` hole whose value is the type, as in
`$!($result){ $callee(@arguments) }`. A kind name such as `Unit` or
`Type` after `$!` always names a kind, so a type spelled like one also takes
parentheses: `$!(Type){ ... }`.

A typed quotation states the type the code has. It converts nothing, so
write a cast inside the braces when the code needs one.

The rest of the code is built the way a quotation builds it, with two
differences:

- Nothing is bound. Holes keep the syntax their locals hold, a binding
  becomes a reference to it, and a number, String, or Symbol becomes a
  literal. A number keeps its exact value and type, and a String is a
  String literal when `T` is `String`. A `@items` sequence makes each
  number, String, or Symbol it holds a literal in the same way. A name the
  expression reads without
  declaring stays a name and is bound wherever the code is bound, if it is
  bound at all.
- The code declares nothing. A typed quotation has no expansion to keep
  names private to, so a name it needs comes from a hole, such as a local
  that holds `x2c_ident("total")`. For the same reason it applies no
  template; build that code first and insert it. Inside another quotation,
  write a typed quotation as a hole: `${$!int{ $b }}`.

Only the outermost expression receives `T`. Inner expressions carry no type
until something binds them. Write `T` exactly: the compiler trusts it as it
trusts the type a typed call already carries.

A typed reference to a binding the function holds is the shortest form:
`$!($type){ $binding }` is the expression that reads `binding` as a `type`.

### Types and parameters

A quotation can also build a type or one parameter. `$!Type{ ... }` holds a
type written as a cast writes it. It builds the `Type` List that a `Type`
local holds:

```x2c
~#include "x2c.x"
~#include "meta.x"
~
typedef struct Point { int x; int y; } Point;

meta static String point_types(void) {
  Type point = $!Type{ Point };
  Type pointer = $!Type{ const $point * };
  Type reader = $!Type{ int (*)($point *) };
  return point.repr() + " " + pointer.repr() + " " + reader.repr();
}
~
~int main(void) {
~  printf("%s\n", $point_types());
~  return 0;
~}
```

```text
("Point") (* const "Point") (* (func ((* "Point"))) int)
```

A `Type` local or a `${...}` hole of type `Type` stands for a type in the
braces. The declarator around it builds a new type from it, so
`$!Type{ const $point * }` is a pointer to a constant `Point`. A type name
keeps its spelling: `$!Type{ String }` is `%("String")`.

`$!Param{ ... }` holds one parameter declaration. Put the parameters in a
function with a sequence hole:

```x2c
~#include "x2c.x"
~#include "meta.x"
~
meta static List sum_function(String name, int count) {
  Array params = [];
  List total = $!( 0.0 );
  for (int i = 0; i < count; i++) {
    List x = x2c_ident(%"x$i");
    params.push($!Param{ double $x });
    total = $!( $total + $x );
  }
  List declared = params.list_free();
  List function = $!Unit{ double $name(@declared) { return $total; } };
  return %($function);
}
macro Unit $sample.define_sum(Literal $name, Literal $count) {
  @sum_function($name, $count)
}
$sample.define_sum("sum3", 3);   // sum3(1.0, 2.0, 3.5) is 6.5
~
~int main(void) {
~  printf("%g\n", sum3(1.0, 2.0, 3.5));
~  return 0;
~}
```

```text
6.5
```

Both build their List where they are written, as a typed quotation does.
Nothing binds them until the function that holds them is bound. The braces
may not declare a name of their own. A parameter takes its name from a hole,
so the body reads it through the same `x2c_ident(...)` local. There is no
`$!Decl{ ... }`, because `$!{ ... }` and `$!Unit{ ... }` already build
declarations.

## What the compiler answers

`lib/meta.x` declares the compiler operations. An operation on a value is
a method of its type: `Code` for captured code and `Type` for a semantic
type. The rest are `x2c_` helpers with no value to act on, such as
`x2c_ident`, `x2c_invocation_line` and `x2c_diagnostic_fail`. Code is built
with quotations, so the module declares no constructors.

`x2c_ident`, `Code.name`, `Code.binding_spelling`, `Type.parts`,
`x2c_diagnostic_fail` and `x2c_diagnostic_warn` work in every `meta`
function. The queries that read the compiler's symbol table, such as
`Code.type`, `Type.fields` and `Type.resolve`, also work in every `meta`
function: the compiler answers a project function's query while the call
waits, in the state of the call's site. `TypeInfo` and `Source`
parameters still deliver a description in one argument. The operations
are grouped here by the task, not by signature; the
[module reference](../library/modules/meta.md) lists every declaration, and
the [language reference](../reference/language.md#the-same-operations-from-x2c)
gives their semantics.

### Building code

A quotation builds the code, and a typed quotation of
one value, such as `$!int{ $count }`, is the literal expression that holds
it. `x2c_ident` checks a name and returns identifier code, which a
quotation uses where the code reads the name:

```x2c
#include "x2c.x"
#include "meta.x"

meta static List call_of(String callee, List argument) {
  List name = x2c_ident(callee);
  return $!( $name($argument) );
}

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

### Asking about types and fields

A `meta` function receives a type as a
`TypeInfo` parameter, described above, or asks the compiler with the
queries below. `Code.type` answers the canonical `Type`
of an expression or binding. `Type.fields` answers the named fields
of a struct or union `Type`, each as a metadata row whose first element is
the field name. `Type.layout`, `Type.resolve` and
`Type.is_value` answer the remaining generated-code questions.
`Type.parts` reads only the `Type` it receives.
`Type.resolve_member` answers which field or method a member access
selects. These
answers live in the compiler's symbol table, so a macro body cannot derive
them from the code it captured.

### Source text and location

A parameter declared `Source` receives a
captured hole together with the text the developer wrote for it:
`((text T) (file F) (syntax S))`. `Code.source_text` returns that text, and
`x2c_embed_text` reads the file a captured `String` literal names beside
the source that wrote it and records it as a translation dependency. Both
read what the argument carries. `x2c_embed_text` also accepts an
absolute `String` path.
`Code.binding_spelling` returns the name a binding was declared with.
`x2c_invocation_file`, `x2c_invocation_line` and `x2c_invocation_column`
give the site of the macro invocation.

### Failing with a diagnostic

`x2c_diagnostic_fail` reports a message at
the invocation and stops the expansion. It does not return. Use it when the
argument is wrong in a way the macro can see:

```x2c
#include "x2c.x"
#include "meta.x"

meta static List one_word(Source node) {
  String text = Code.source_text(node);
  if (text.contains(" "))
    x2c_diagnostic_fail("this argument must be one word", %());
  return $!String{ $text };
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
`Code.source_text` reads. A computed subtree is code data, not a new source
capture, and cannot be passed as a `Source`.

Writing `$probe.word(seconds * 2)` instead reports the message at that
invocation:

```text
sample.x:15:23: macro: this argument must be one word
  printf("word %s\n", $probe.word(seconds * 2));
                      ^
```

`x2c_diagnostic_fail_at` reports under a category, such as `<macro>` or
`<type>`, at a node the macro received, such as one captured statement,
instead of at the invocation.

### Placing code beyond the result

`x2c_enclosing` answers the syntax
around the invocation: the initialized `<declarator>`, the block item
(`<statement>`), the `<function>`, or the `<unit>`. `x2c_place` adds code
the result cannot hold: `%(after-statement)` after that declarator or block
item, `%(block-exit)` on every exit from the block after it, as a `defer`
there runs, `%(function-entry)` at the entry of the enclosing function
before its first statement, `%(unit-support KEY)` among the unit's
file-scope declarations once for each key, and `%(unit-init)` in the
unit's initialization. Code placed at function entry follows the parameters
and keeps the order of its placements. A macro in a lambda body places it in
the function that holds the lambda; a `$rewrite` rule, which runs while the
body lowers, places it in the lambda's own function. A macro in a `defer`
finalizer places it in the function that holds the `defer`; a `$rewrite`
rule that places it while the finalizer lowers is rejected, because the
finalizer runs as its own callback. A failed expansion leaves none of it
behind. Placed code that declares a name takes it from
`x2c_binding_fresh(role)`, which returns a binding the compiler names, so
the result can refer to the same binding. Code placed once under
`%(unit-support KEY)` takes its name from `x2c_binding_for(KEY, role)`,
which returns the same binding for the same key in a unit, so every result
that refers to it agrees.
Here the counter runs after each statement that traces a value:

```x2c
#include "x2c.x"
#include "meta.x"

static int traced = 0;

meta static List trace_after(List value) {
  x2c_place(%(after-statement), $!{ traced++; });
  return value;
}

macro Expression $trace(Expr $value) => $trace_after($value);

int main(void) {
  printf("%d %d\n", $trace(1), traced);
  printf("%d\n", traced);
  return 0;
}
```

```text
1 0
1
```

`$auto` is written this way: it places a release after the declarator it
initializes, and the declaration checks that the expansion is its complete
initializer before it binds that release.

### Rewriting a function definition

`$rewrite` from `rewrite.x` registers
a `meta` function as a rule for the code its macro builds. When that macro
is a `Unit` macro whose body is one function definition, or only its one
`Function` hole, the rule receives each function definition the program
writes once, after binding and typing and before the body lowers. A
definition that the program's own `meta` code places or returns is the
program's. A `meta` function whose body uses only what the runtime library
provides also has a runtime form, an ordinary C function in its unit, and
that definition is the program's, so the rule receives it. A definition
that the compiler writes while lowering is not offered: a lambda's function,
a `defer`'s cleanup, a `Func` adapter, a protocol's forwarding member, or
the compiler's own replacement of a definition. The
statements such a definition holds from the program still reach the
program's statement rules. The rule returns the definition unchanged to
decline, or a replacement definition. The replacement is lowered as written
and offered to the other rules, but not again to the rule that returned it.
A pattern that spells its return type, such as `int $name(...)`, is tried
only on definitions with that return type and storage, before the rules
whose pattern holds a hole there:

```x2c
#include "x2c.x"
#include "rewrite.x"

static int entries = 0;

macro Unit $any_function(Function $function) { $function }

$rewrite($any_function)
meta Code count_entries(Code function) {
  if (!Code.name(function).startswith("counted_")) return function;
  match (function) case %(function ?type ?declarator ?):
    return %(function $type $declarator
      (block ${$!{ entries++; }} @{Code.body(function)}));
  return function;
}

int counted_next(int x) { return x + 1; }

int main(void) {
  counted_next(1);
  counted_next(2);
  printf("%d\n", entries);
  return 0;
}
```

```text
2
```

The compiler binds each of these under its x2c name and derives the Lisp
name from it: a method keeps its spelling, so `Code.binding_spelling` is
`Code.binding_spelling` in Lisp, and in a helper each `_` becomes `.`, so
`x2c_invocation_line` is `x2c.invocation.line`. A Lisp form has no
quotation, so the Lisp library also defines `x2c.literal.string`,
`x2c.literal.int` and `x2c.literal.symbol`, which build the literal a
`$(...)` form returns for a value.

The compiler's shipped components lower language features with the same
`$rewrite` decorator. A program definition spelled like a shipped
component's `meta` function or helper is a separate definition: shipped
rules and templates resolve their own names to the copies the compiler
links.

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

In the complete shape example below, `shape_names` and `shape_reads` construct
source code and have no runtime forms. The consumer uses their returned code.

A `meta` function that needs no compiler query, like `poly` above,
keeps both forms and is emitted normally.

## A complete example

Two ordinary source files. `shape.x` holds the `meta` functions and the
macros that call them. `shape_fields` reads the fields from the `TypeInfo` the
compiler sends. `shape_names` and `shape_reads` turn them into code.

<!-- ignore: shape.x is the external file being illustrated -->
```x2c,ignore
#include "meta.x"

/* The named fields of a struct-typed expression, in declaration order. */
meta static List shape_fields(TypeInfo type) => type.assoc(<fields>);

/* One `String` literal holding those field names, comma separated. */
meta List shape_names(TypeInfo type) {
  Array names = [];
  foreach (List field, shape_fields(type)) names.push(field.car());
  return $!String{ ${String.join(", ", names)} };
}

/* `{ p.x, p.y, p.z }`, built from the fields rather than written out. */
meta List shape_reads(List receiver, TypeInfo type) {
  Array reads = [];
  foreach (List field, shape_fields(type)) {
    String member = field.car();
    reads.push($!( $receiver.$member ));
  }
  List items = reads.list_free();
  return $!( { @items } );
}

macro Expression $shape.names(Expr $value) => $shape_names($value);

macro Expression $shape.reads(Expr $value) => $shape_reads($value, $value);
```

The second file includes `shape.x` and uses its public macros. The include
also makes its nonstatic meta functions available.

<!-- ignore: this program includes the shape.x file above -->
```x2c,ignore
#include "x2c.x"
#include "meta.x"

#include "shape.x"

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

