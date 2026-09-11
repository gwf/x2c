# Language Reference

This chapter specifies x2c's syntax, behavior, and current limitations.

The runtime API is described in the [standard library
overview](../library/overview.md), and advice about which construct to use is
in [idioms](../guide/idioms.md). Flags and the dump options that expose each
phase are in [compiler options](cli.md). If you have not built the compiler
yet, the website's install page is the quickest route, and [building the
compiler](../internals/building.md) covers the self-host stages behind it.

## Source files and pragmas

An `.x` file combines declarations and definitions. Translation produces a
header and a C source file.

`#pragma private` marks the start of implementation-only content. Declarations
before it may be emitted to the generated header. A function definition also
begins source-private output, except that a typedef after it still belongs
to the header when a later public prototype names it. Every translated header
starts with `#pragma once` and also carries a conventional include guard, so
`.x` programs do not need to write either one.

The advanced `--cpp-symbols` and `--live-symbols` modes run the host
preprocessor over raw `.x` include graphs. A module used with those modes needs
a source-level `#pragma once` only when its own `.x` includes form a cycle.
Ordinary translation resolves includes itself and terminates cycles without
it.

Every ordinary `.x` translation unit implicitly loads the `x2c.x` standard
runtime prelude. The compiler also emits `#include "x2c.h"` in its generated
header. An explicit `#include "x2c.x"` is also accepted; it does not change
the semantic environment or generated runtime dependency.

Optional modules shipped with x2c are outside that prelude. They require an
explicit source include, such as `#include "typed-array.x"`. Third-party code
uses the package `import` described below.

## Packages and `import`

A package is a directory whose name is a valid C identifier. Its entry unit is
`<dir>/src/<name>.x`, or `<dir>/<name>.x` for a single-file package. The
package is everything that entry unit includes. Everything above
`#pragma private` is public. There is no manifest and no export list.
`--package-dir <root>` registers a directory of packages; a target in
`x2c.toml` may set `package-dirs` instead.

An `import` declaration names a package, binds a local alias, and may name
individual members:

```text
import "<package>" [as <alias>] [with <Name> [as <Local>] {, ...}] ;
```

<!-- ignore: an import needs a registered --package-dir root. -->
```x2c,ignore
import "geo";                 // alias: geo
import "geo" as g;            // alias: g
import "geo" with Vec, span;  // plus bare Vec and span
import "geo" with Vec as V;   // plus bare V
import "geo" as g with Vec;   // both spellings
```

The alias changes how names are written in x2c. `g.Vec`, `g.Vec.new(2.0, 3.0)`,
and `g.span(p)` all compile to the package's C names, which carry the package
prefix: `geo__Vec`, `geo__Vec_new`, `geo__span`. Two packages may therefore
publish the same type or function name in one program. An existing local or
file-scope binding takes precedence over an alias of the same name.

An `import ... with` name renames what you type, never the C symbol.
`Vec v = Vec.new(2.0, 3.0)` emits `geo__Vec` and `geo__Vec_new`. Any public
name the package exports may be listed, including free functions. The alias
is registered either way, and the clause only adds shortcuts. A name the
package does not export is an error at that name, and a local spelling that
another binding or a declaration already owns is reported as
`package name 'V' is already bound` or
`package name 'V' collides with a declared name`. A declaration shadows a
`with` name as it shadows an alias.

Names derived from a package type carry the prefix as well. A `Var(T)`
participant's tag is `<geo__vec>`, and its converters are `geo__Vec_var` and
`geo__Var_vec`. A package's own sources write all of these bare and let the
compiler add the prefix. Only a `Symbol` literal, a global interned identity,
is written out in full.

A package may publish a method on a type it does not define, such as
`Var.json`, or on a type its own vendored header defines. At each receiver
type, method lookup tries an ordinary method first, then a method from the
imported packages, then a protocol method before continuing through typedef
parents. The receiverless form `Type.member(...)` and protocol punctuation
resolve through the same imported names, so a package that adopts one of its
own protocols for a foreign type gives the consumer that operator. One
imported match is callable. More than one is an error at the call, with the
packages listed by name; imports that are never called do not conflict. An
alias-qualified function call such as `json.Var_json(value)` selects one
package explicitly.

A package's own sources are `<dir>/src/**` and the single-file
`<dir>/<name>.x`. Other files in the package directory, including its tests
and examples, are ordinary consumers that reach it through `import`.

An import exposes:

- every public declaration, type, and aggregate above `#pragma private`;
- protocol declarations and adoptions the package makes; and
- any header the package's public part includes, such as a vendored foreign
  header it publishes.

It does not expose macros, `.xmacro` definitions, private declarations, or the
package's own imports. Packages have no re-exports or hierarchy. One program
uses one version of a package.

Names from a C header remain unprefixed, as if the consumer included that
header directly. A package renames what it declares, not what it includes.

An unprefixed public declaration from an x2c file outside the package directory
would enter the consumer's namespace unchanged. The compiler rejects it as
`package 'geo' exposes unprefixed top-level declaration '...'`. A consumer that
declares a name in an imported package's `geo__` space is reported as `'geo__x'
is reserved for imported package 'geo'`.

## C foundation

x2c keeps C declarations, expressions, operators, functions, structs, unions,
enums, pointers, arrays, and control flow. It adds language forms around that
foundation and keeps C's object model.

Raw pointer member access still uses `->`; direct struct members use `.`.
x2c also recognizes method-style calls such as `list.len()`. The namespaced
function is selected from the static receiver type. When that function
declares its first parameter `T *` and the receiver is an addressable `T`, the
receiver's address is passed, so `rec.bump(4)` reaches
`void Rec.bump(Rec *rec, int by)` without an explicit `&`. Normal pointer
conversion rules still apply, including preservation of `const` and other
qualifiers. Method syntax does not make every value dynamically dispatchable;
only registered callbacks define custom behavior.

A method may use `Self` in its result and parameter types when it promises to
preserve the receiver's static typedef:

```x2c
Self List.cdr(Self values);
Self List.append(Self left, Self right);
List List.map(List values, Func fn);
```

For a `ListInt` receiver, dotted lookup treats the first two signatures as
`ListInt -> ListInt` and requires a `ListInt` second argument to `append`.
Ordinary conversion still applies, so a plain `List` reaches the existing
validating `ListInt` converter. `map` remains `List -> List`; x2c never infers
covariance for an unmarked method.

`Self` is contextual syntax, valid only in a dotted method declaration or
definition with a concrete owner and a compatible first parameter. It may be
qualified or nested under pointers. Every occurrence is bound to the original
static receiver typedef, even when lookup crosses several typedefs. A direct
call to `List_cdr` retains the concrete `List -> List` signature, and generated
C keeps that ABI. Prototypes and definitions must agree on both their concrete
types and the positions marked `Self`.

### Expression-bodied functions

A function that returns one expression may use `=>`:

```x2c
~typedef struct Pair { int left, right; } Pair;
static int twice(int value) => value * 2;

String Pair.describe(Pair pair) =>
  %"${pair.left}, ${pair.right}";
```

This is shorthand for a compound body containing one `return` statement. The
expression uses the function's parameter and body scopes and follows the same
conversion, cleanup, and lifetime rules as `return expression;`. The semicolon
terminates the body; nested compound literals, collection literals, and lambda
bodies do not terminate it.

An expression is required; `=>;` is invalid. The rules for returning a value
from a `void` function are unchanged. Use a compound body when a function needs
declarations, several statements, or a comment inside the body.

### Reference parameters

A function parameter declared `T &name` aliases an addressable `T` supplied by
the caller. The parameter name is an ordinary `T` lvalue inside the function,
so reading it reads the caller's object and assigning it changes that object:

```x2c
static void swap(int &left, int &right) {
  int temporary = left;
  left = right;
  right = temporary;
}

int main(void) {
  int first = 4, second = 9;
  swap(first, second);
  printf("%d %d\n", first, second);
  return 0;
}
```

The call does not write `&`; x2c takes each argument's address. Passing a
reference parameter to another reference parameter forwards the same object.
The argument must be an addressable lvalue whose storage remains live for the
call.

Generated C uses a pointer parameter and explicit address-taking and
dereferencing. Reference parameters add no runtime representation or ownership
behavior. The transparent `&` form is supported only on parameters; reference
locals, globals, and return types are not language features.

### Delegate fields

`delegate` marks a named struct or union field as a fallback for dotted method
calls:

```x2c
typedef struct Reader {
  int value;
} Reader;

typedef struct Document {
  delegate Reader reader;
} *Document;

int Reader.read(Reader reader);
```

If normal lookup finds no applicable `Document.read`, `document.read()` uses
the field's static type and emits the same direct call as
`document.reader.read()`: `Reader_read(document->reader)`. The original
receiver expression occurs once. Pointer and value fields follow the ordinary
rules for `.` or `->`, addressability, qualifiers, conversions, and null
values. Delegation emits the field access and direct call; it adds no wrapper,
temporary, runtime check, symbol, or dispatch table.

Normal method lookup remains first, including direct methods, imported methods,
protocol-selected methods, and typedef ancestors in their existing order.
Delegate fields are searched only if those lookups fail. The search visits
marked fields in source order to produce consistent diagnostics. One resolving
path is used; two or more are an ambiguity error, regardless of field order. An
explicit outer method therefore resolves an otherwise ambiguous pair.

Delegate fields may chain without a numeric depth limit. Lookup tracks the
aggregate types on the current field path. A cycle is reported only when lookup
needs that path and finds no valid candidate. One valid path is used even if
another contains a cycle; multiple valid paths remain ambiguous.

The terminal field type determines method typing. `Self` parameters and results
mean that field's static type, never the outer aggregate, and a method
returning `Reader` still returns `Reader`. Delegation does not make the outer
type a subtype, adopt a protocol, acquire a conversion or `Var` identity,
expose the field's fields, or forward punctuation, indexing, operators, or
receiverless calls. `x2c.method.resolve` is also direct-only. Its callee result
cannot represent a projected receiver path.

`threaded` is x2c's spelling of C's thread-local storage class, and gives each
thread its own copy of an object:

```x2c
threaded int depth;
static threaded Scope current;
```

It pairs with `static` or `extern`, in either order, which is the only pairing
C allows. `_Thread_local` and `thread_local` mean the same thing and are
accepted, so C that already writes it either way passes through unchanged; all
three emit `_Thread_local`.

Where C reports a pointer type mismatch as a warning, x2c reports an error:
passing a `struct Rec *` to a parameter declared `List`, `String`, `Map`, or
`Array` is `cannot convert (* "Rec") to ("List")`. Typedef spelling is not a
mismatch, so `Ast` and `List` are the same type here. The rule applies only
when both sides point at a named struct, union, or enum or at a builtin scalar;
`void *`, function pointers, arrays, and types from system headers convert as C
defines. A cast still allows the conversion.

### Protocols

Protocols declare a compile-time relationship between a concrete base and
explicit participant types. The grammar is:

```text
protocol-declaration := protocol type-name ( identifier ) {
                          associated-declaration*
                          protocol-member*
                        }
protocol-adoption    := [ static ] protocol type-name ( identifier )
                        [ as type-name | tag symbol-literal ] ;
associated-declaration
                     := associated identifier = type-name ;
protocol-member      := type-name identifier . identifier
                        ( parameter-list ) [ = c-identifier ] ;
```

The identifier in a declaration body is a fresh type-variable binder. The
identifier in a bodyless adoption must name an existing type:

```text
protocol Var(T) {
  associated Key = Var;
  Value T.getindex(T, Key);
}

protocol Var(Array);
```

The optional `as` form applies only to `Var` and says that the participant
uses an existing fixed runtime tag:

```x2c
typedef List Row;
~Var Row.var(Row);
~Row Var.row(Var);
protocol Var(Row) as List;
```

`Row` retains its own typed conversions, methods, signatures, and protocol
participation. Compatible `List` methods inherited through its typedef chain
may satisfy `Var(Row)` without `Row` forwarding methods. A boxed `Row` carries
`<list>` and uses `List` for dynamic dispatch. Runtime tests therefore cannot
distinguish it from another list: `value is Row` and `value is List` test the
same tag. The type after `as` must be a scalar, pointer, or fixed runtime class
that already has a compiler-known `Var` tag.

The optional `tag` form also applies only to `Var`, but keeps a distinct
descriptor under the supplied custom tag:

<!-- ignore: declaration excerpt; ArrayString is generated by typed-array.x -->
```x2c,ignore
protocol Var(ArrayString) tag <arraystr>;
```

The tag must be a Symbol literal, cannot be built in, and must be unique across
the process. The compiler retains the full lowercase participant name so two
types cannot silently claim the same restricted Symbol. `tag` and `as` are
mutually exclusive: use `tag` for a distinct runtime class and `as` for a typed
view of an existing representation.

Both forms are top-level compiler declarations and emit no program object.
Associated declarations precede members. A declaration binder that shadows a
visible type receives a warning; use the bodyless form to adopt that type.

`static` applies only to a concrete adoption:

```text
static protocol Prepared(LocalPlan);
```

That adoption applies only within the translation unit that declares it. It
forces local generation even when the complete adoption is public. It is also
valid when a private dependency already implies locality; it then records the
same local relationship explicitly and does not change linkage.

An adoption is local when its protocol body, participant typedef, required
converter, required native target, or adoption row is private. A protocol
body below lexical `#pragma private` is legal; `static protocol BASE(T) {
... }` is not, because `static` applies only to concrete adoption. Local
ordinary adapters are `static inline`, appear only in generated C, and are
omitted from generated headers. Local native aliases and their signature
checks are likewise source-only.

Descriptor-producing adoptions such as `Var(T)` may be local. Their
converters and generated thunks remain internal, but descriptor registration
is process-wide so boxed dispatch still works. The author must keep the
derived lowercase or explicit tag unique across the process. Two independent
private registrations of the same tag in different translation units are
unsupported
by convention. A `Var(T) as R` adoption emits no descriptor for `T`; boxed
dispatch uses `R`'s existing descriptor.

One generated C method cannot have incompatible local and external linkage. The
compiler reports that conflict at its source location. A protocol whose
dependencies are all public retains its public behavior.

Participation must be declared; conversion names and matching typedefs do not
imply it. The compiler then determines the adoption's visibility. An adoption
resolves in the unit that contains it, so the protocol, participant, required
converters, native targets, and constraining participant members must be
visible there. Ordinary runtime protocol bodies under `lib/` belong in
`lib/protocols.x`; native declarations and their adoptions sit beside the
participant typedef.

A typedef descendant with no exact adoption may use the nearest visible
ancestor's resolved conformance. It reuses the ancestor's methods, associated
types, conversions, and representation without creating an adoption, adapter,
native alias, descriptor, runtime tag, registration, or conformance output for
the descendant. An exact descendant adoption resolves a new conformance and
takes precedence. If that exact adoption is invalid, it is diagnosed and lookup
does not fall back to an older ancestor. A local ancestor adoption is inherited
only in translation units where that adoption is visible.

Common source forms are a plain adoption for public protocols and public
participants, a plain `protocol Var(PrivateType);` for an internal type that
crosses `Var`, and an explicit `static protocol PrivateBase(PrivateType);` for
a fully private relationship. The latter would also be inferred local; `static`
states it directly.

Each member resolves independently as implemented, native, an ordinary base
default, missing, or a signature conflict. Dot syntax and punctuation accept
implemented and native members plus ordinary base defaults reached through a
total participant-to-base view. A missing `Var` member grants no static
participant method; its descriptor slot carries another protocol's generated
owner when one exists, and is otherwise empty so dynamic boxed use takes the
`Var` fallback directly. Signature conflicts are located errors at the adoption
row.

An explicit adoption may resolve an ordinary implementation through the
participant's typedef chain. For example,
`typedef List Domain; protocol Iter(Domain);` selects `List.iter` directly;
it does not require a forwarding `Domain.iter` method. The participant's own
method wins, followed by the nearest inherited method, and then a protocol
default. Reaching the protocol base uses that default path
instead. Every parameter whose exact type is the method owner is viewed as
the participant type. Concrete result types remain unchanged unless the
method declares them as `Self`.

An ordinary `Var(P)` adoption does not search `P`'s typedef chain. When
`protocol Var(P) as R` names an `R` that occurs in that chain, compatible
methods owned by that exact representation may satisfy the adoption. No
other ancestor is considered. Boxed dispatch already uses `R`'s descriptor.

Associated types unify from the participant's declared member signatures and
use their declared default only when unconstrained. A generated member has one
owner. Incompatible generated signatures or two defaults conflict. A compatible
participant implementation resolves the competition.

The normative [protocols chapter](../guide/protocols.md) specifies converter
totality, adapter-derived conversion directions, punctuation, generated
ownership, boxed dispatch, native aliases, and complete examples.

### C initializers and static assertions

Array and aggregate initializers accept chained index and field designators.
Positional values continue from the designated subobject using C's ordinary
brace-elision rules:

```x2c
String labels[4] = {[1] = "first", "second"};
int grid[2][3] = {[0][1] = 7, 8, 9};
typedef struct Record { String names[2]; Var last; } Record;
Record record = {.names[1] = "second", "last"};
```

Each supplied value converts to its destination element or field type. After
`.names[1] = "second"` above, the next value initializes `last`, including its
ordinary conversion to `Var`. With `.names = "first", "second", "last"`,
brace elision fills both array elements before continuing to `last`. Explicit
braces delimit a nested initializer. Typedefs and compound literals retain
the ordinary destination conversions, including C literals to `String`.
The native compiler owns index constant expressions, array dimensions, and
bounds diagnostics.

`_Static_assert(condition, "message");` is accepted at file scope, block scope,
and within a struct or union. It emits an ordinary C static assertion and adds
no field, binding, or runtime operation:

```x2c
_Static_assert(sizeof(int) >= 2, "int is at least 16 bits");
```

The native compiler evaluates the condition and rejects a false or nonconstant
assertion. Translation and source analysis alone do not perform that check.

### Mixed declaration rows

A semicolon-terminated declaration at file scope, block scope, or inside a
struct or union may restart its declaration specifiers after a comma:

```x2c
int i, float x, char c;
int first, second, const char *name, *alias;
```

Each fresh type starts a declaration with the same scope and source order as if
it were on a separate row. Declarators that share a type keep the C spelling:
`first` and `second` are `int`, while `name` and `alias` are `const char *` in
the second example.

Valid C declarators retain their meaning. In particular, if `T` is a typedef,
`int i, T;` still declares an `int` named `T` and hides the typedef. A spelling
such as `int i, T value;` restarts at `T`, because the second identifier cannot
continue the `int` declarator. Function parameter lists already give each
parameter its own type; mixed rows do not extend `for` initializers, `foreach`
binders, or macro `Decl` arguments.

### Flat List destructuring

Declarations and assignment expressions may destructure the first elements of
a `List` into flat identifier targets:

```x2c
~List values = %(1 2 3);
~List numeric_values = %(0 10 2);
~
Var (a, b, c) = values;
int (start, stop, step) = numeric_values;
(int index, float weight, char code) = %(1 2.5 ${'x'});

Var first, second;
(first, second) = values;
(first) = values;
List copy = (first, second) = values;
```

The leading declaration specifier in `int (start, stop, step)` applies to every
name. The parenthesized typed form gives each target a type, written as it
would be in a parameter declaration. Both forms declare their names in the
enclosing block. Storage classes and per-target initializers are not accepted
inside the parentheses. Inside a `%()` `List` literal, use `${}` to insert a C
character expression because bare single-quote syntax belongs to the `List`
reader.

The singleton assignment destructures. It assigns element zero; the left side
is not a parenthesized scalar assignment.

The source expression is evaluated once. Elements are then assigned from left
to right through the same conversions used by ordinary initialization or
assignment. Extra source elements are ignored. If the `List` is short,
`List.getindex` supplies `void`; a `Var` target receives it, while a typed
target follows its existing `Var` conversion and failure behavior.

Assignment destructuring has the same static type, value, and identity as its
right side, so it may appear in an initializer, argument, conditional arm,
comma expression, return, or another destructuring right side. The right side
is still evaluated only once; returning it does not copy the `List`.

The form is flat. Targets must be simple identifiers. Nested targets, members,
indexed targets, dereferenced pointer targets, and rest captures are not
supported.

## Compile-time macros

Macros are explicitly invoked, hygienic compile-time code generators. They
differ from C preprocessor macros. Holes bind parsed syntax, definitions use
C-like x2c source, and every result is validated for its typed source position
before C generation. They make no promise about the runtime semantics of the
code they emit; for example, substituting an argument twice may evaluate it
twice. A definition's left side looks like its invocation, and its body is x2c
with `$hole` markers:

```x2c
macro Expression $twice($value) => ($value + $value)

int main(void) {
  printf("%d\n", $twice(21));
  return 0;
}
```

Global definitions are top-level items. A compound statement may instead
contain a local definition whose name has no `$`. Both forms emit no runtime
declaration. `macro` is a contextual introducer only when the surrounding
grammar accepts a definition and a result kind and macro name follow it. It
remains legal as an ordinary typedef, variable, parameter, field, or function
name everywhere else. A definition ends with its parenthesized or braced body
and has no trailing semicolon.

Ordinary global invocation is `$qualified.name(arguments)`. A local macro is
invoked as `name(arguments)`. A source file may also give a visible global
macro an identifier spelling through a `keyword` declaration, described under
[Decorators](#decorators). Macro names are separate from C identifiers and
global names may be qualified, as in `$project.logging.trace`. The `x2c.*` and
`lisp.*` macro and Lisp namespaces are reserved for compiler-shipped
facilities; `$lisp.bind`, `$lisp.binding`, and `$lisp.install` are the shipped
native-binding macros.

Definitions and imports become visible in source order. A definition must
precede its first use. A later same-file definition of the same name shadows
the earlier definition for later invocations; it does not change expansions
that already occurred. An imported definition may not collide with a
definition already visible from the importing translation unit or another
import.

### Local definitions

A local definition uses one bare identifier and is a compound-statement item:

```x2c
static int scaled_sum(int scale, int value) {
  macro Expression scaled(Expr $input) => ($input * scale)

  return scaled(value);
}
```

Its name becomes visible at the definition and remains visible to the end of
that block and in nested blocks. An inner definition of the same name shadows
it until the inner block ends. A later definition in the same block replaces
it for following source. Fixed C and x2c keywords are not identifiers and
cannot be local macro names; `with` is also reserved because it introduces the
lexical `with` statement.

A bare `name(...)` selects the innermost local macro before a file-local
`keyword` alias or an ordinary call or typedef-style cast. A bare `name`
without parentheses remains an ordinary identifier. `(name)(arguments)` is an
explicit ordinary call, while `$name(arguments)` selects only the global or
imported macro namespace. A local and global definition may therefore share a
name without ambiguity.

Literal references to function parameters and preceding local declarations
retain their definition-site binding identities. A later same-spelled inner
declaration is emitted under a private shadow name when necessary, so the
template still reaches the captured declaration. Hole arguments retain their
call-site identities. Declarations written in the body and names declared by
`using` retain the ordinary hygiene rules described below.

Local `Expression`, `Statement` or `Block`, `Field`, `Entry`, and `Enumerator`
results use their usual positions. A local decorator may target any syntax
whose invocation position is reachable before the defining block ends. A local
`Unit` result and a local decorator targeting `Function` or `Unit` syntax are
rejected. Their invocation positions are outside that lifetime. A
macro-generated local definition is published at block position with the same
visibility, capture, and shadowing behavior as a direct one.

Compile-time Lisp remains one translation-unit session. A local definition may
read or change that session, but Lisp definitions, imports, globals, and other
effects do not disappear when the local macro name leaves scope.

### Holes and sequences

A hole binds parsed syntax, not source tokens. Its kind is normally inferred
from every position where it appears in the body: an operand needs an
expression, a cast needs a type, and a declarator needs a name. If those uses
do not imply exactly one kind, including when a hole appears only inside
compile-time Lisp, the definition must annotate it in the invocation pattern.

These are the complete hole-kind annotations:

| Annotation | Bound syntax | Example argument |
| --- | --- | --- |
| `Expr` | expression | `count + 1` |
| `Type` | type | `FILE *` |
| `NamedType` | name followed by a complete type definition | `Point { int x; int y; };` |
| `Decl` | non-function declaration | `static int value` |
| `Function` | function definition | `int f(int x) => x;` |
| `Name` | identifier | `checksum` |
| `Literal` | one literal | `42` or `<char>` |
| `Param` | parameter declaration | `const char *name` |
| `Statement` or `Block` | block item | `return value;` |
| `Field` | field declaration | `unsigned ready : 1;` |
| `Entry` | `Map` row | `key: value` |
| `Enumerator` | enum member | `ready = 1` |
| `Unit` | top-level C declaration or definition | `int value;` |

Because the definition is already known, an invocation parses each argument
according to its hole kind. A type such as `FILE *` therefore works as an
argument even though it is not an expression.

A `Decl` argument captures one declaration without a trailing semicolon. Its
comma or closing parenthesis belongs to the macro invocation. The declaration
may have an initializer or use flat destructuring with two or more simple
identifier targets, but it may not contain multiple comma-separated
declarators.

An expression hole may be the receiver of ordinary postfix syntax in the body,
including `$value.field`, `$value.method()`, and `$value[index]`. The hole ends
at its registered identifier; this does not shorten qualified macro names such
as `$project.logging.trace()`. A singular `Name` hole may also appear after `.`
or `->`, as in `$value.$member` or `$pointer->$member`. It supplies the
captured member spelling, not a hygienic generated name.

A registered `Type` hole may likewise supply the type name before `.` in a
method declaration in a `Unit` template, as in `inline Var $type.$method($type
value)`. A literal registered type may use the same member form, as in
`Logger.$method`. Both expansions use the `Type_method` declaration identity.

Repeated `Unit`-macro applications over `Type` holes are how x2c writes
compile-time generic code. Every supplied type must already be a valid named C
type, and every expansion produces separately typed declarations and
definitions. There is no runtime type argument, erased element representation,
or parameterized type spelling such as `Box<T>`. A macro generates named
concrete families such as `IntValue` and `DoubleValue`.

During shallow symbol collection, the compiler expands file-scope unit macros
that contain protocol declarations or adoptions. If expansion succeeds, it
retains those and public declarations, then discards private declarations and
function bodies. A public function definition may therefore follow its
prototype inside the same expansion; importing translation units discover the
retained signature.

Protocol declarations and adoption rows are collection-time compiler
declarations rather than C declarations. A unit macro may emit them, and
importing units receive the retained rows. Converters and public methods named
by an adoption may have prototypes earlier in the same expansion and scope. The
compiler uses them to resolve the adoption and make the functions visible to
later code. Private declarations remain literal. Collection discards them with
the generated bodies.

`$name...` is a sequence hole. It captures zero or more arguments of one
element kind, must be the final argument, and `$name...` in the body is the
splice point:

```x2c
static int sum(int a, int b) {
  return a + b;
}

macro Expression $call(Expr $callee, Expr $arguments...) => (
  $callee($arguments...)
)

static int answer(void) {
  return $call(sum, 19, 23);
}
```

The element kind is inferred in the same way as a singular hole and may be
overridden, for example `Field $members...`. Argument-hole names must be
unique, and a name cannot be both singular and sequence-valued.
`Entry` holes capture one `key: value` row; `Entry $rows...` captures and
forwards zero or more complete rows.

### Result kinds and invocation positions

A macro has one result kind as well as argument kinds:

| Annotation | Body | Legal invocation position |
| --- | --- | --- |
| `Expression` | parenthesized expression | expression |
| `Statement` or `Block` | braced block items | statement |
| `Field` | braced field declarations | struct or union body |
| `Entry` | braced, comma-separated `key: value` rows | `Map` literal |
| `Enumerator` | braced, comma-separated enumerators | enum body |
| `Unit` | braced declarations and definitions | file scope |
| `Declaration` | braced declarations with retained public signatures | file scope |

The result kind is required between `macro` and the `$` name. `Statement` is
the canonical spelling for block-item results; `Block` remains a synonym in
result and hole positions. Parenthesized bodies require `Expression`; braced
bodies require `Statement`, `Block`, `Field`, `Entry`, `Enumerator`, `Unit`,
or `Declaration`.
Inside a compound statement, a `Statement` or `Block` macro may produce zero or
more block items. Where the grammar requires one statement, such as an `if`,
`else`, or loop body, the expansion must contain exactly one statement. An
explicit `{ ... }` or `do { ... } while (0)` in the production satisfies that
requirement; the compiler does not add braces. The invocation must occur in the
matching position:

```x2c
macro Statement $swap(Expr $left, Expr $right) using $temporary => {
  $(x2c.syntax.type $left) $temporary = $left;
  $left = $right;
  $right = $temporary;
}

macro Field $timestamps() => {
  long created_at;
  long updated_at;
}

static void reorder(void) {
  int first = 1, second = 2;
  $swap(first, second);
}

typedef struct Record {
  $timestamps();
} Record;
```

An `Enumerator` body contains zero or more enum members. Members may have
explicit initializers, and commas separate literal members and sequence
splices:

```x2c
macro Enumerator $status_values() => {
  private_start = 3,
  $(x2c.ident "STATUS_READY") = private_start + 1,
  $(x2c.ident "STATUS_DONE")
}

typedef enum Status {
  STATUS_UNKNOWN,
  $status_values(),
  STATUS_COUNT
} Status;
```

Literal names such as `private_start` are hygienic and may be referenced by
later generated initializers in the same expansion. `x2c.ident` publishes an
exact source spelling. Generated members participate in enum ordering and
automatic value assignment, and successful exact members are available to
following source. Duplicate generated names and collisions with source members
are rejected. A malformed or failed sequence publishes none of its provisional
members.

An `Entry` body contains zero or more comma-separated `Map` rows:

```x2c
macro Entry $handler(Literal $key, Expr $value) => {
  $key: $value
}

int main(void) {
  int open = 1, close = 2;
  Map handlers = %{
    ${$handler("open", open)},
    ${$handler("close", close)}
  };
  return handlers.len() == 2 ? 0 : 1;
}
```

An entry invocation occupies one comma-delimited row position but may expand to
any number of rows. Direct and keyword-alias invocations must appear there
inside `${...}`, which leaves the quoted Map syntax to parse x2c. Elsewhere in
an entry macro body, ordinary expression grammar applies, so an expression
macro may generate a key. `$(form)...` inserts a `List` of explicit `(map-entry
KEY VALUE)` nodes; without `...`, `$(form): value` constructs a generated key.

The semicolon belongs to the invocation context, not the definition.
`Enumerator` and entry invocations occupy comma-delimited positions and have no
semicolon. A result used in the wrong position is rejected at the invocation.

### Decorators

A decorator is a macro whose required first parameter is supplied implicitly
from the expression or source item following its application:

```x2c
macro Decorator $trace(
  Function $function,
  Expr $channel
) => {
  printf(
    "[%s] %s\n",
    $channel,
    $(x2c.literal.string (x2c.function.name $function))
  );
  $(x2c.function.body $function)...
}

$trace("request")
static int answer(void) => 42;
```

The call supplies `"request"` to `$channel`; the compiler supplies the
following function to `$function`. The first parameter must be named,
singular, explicitly annotated, and one of:

| Target kind | Following source | Replacement |
| --- | --- | --- |
| `Expr` | one cast expression | one expression |
| `Function` | file-scope function definition | block items replacing its body |
| `Statement` or `Block` | one statement or local declaration | zero or more block items |
| `Field` | one struct or union field | zero or more fields |
| `Unit` | one top-level declaration or definition | zero or more top-level items |
| `NamedType` | name and type definition, ending in `;` | retained top-level declarations |

Parameters after the target are explicit invocation arguments. `using` follows
the complete parameter list, just as it does for other macros. A decorator
application has no semicolon; that omission pairs it with the following target.
Only whitespace and comments may separate them. When a statement decorator
appears where one statement is required, its production must likewise yield
exactly one statement. A compound statement may contain the captured target
plus any additional block items without requiring braces at the invocation.

A `.x` file may give a visible macro or decorator an identifier spelling:

```text
keyword ALIAS $QUALIFIED_MACRO;
```

`keyword` is contextual at file scope. It starts this declaration only when
followed by an identifier and a `$` macro name, and remains an ordinary
identifier elsewhere. `ALIAS` must be a C identifier. A fixed C or x2c keyword
does not tokenize as an identifier and cannot be used.

The named definition must already be visible. A macro alias keeps the direct
invocation's parentheses, comma-separated typed arguments, sequence arguments,
and terminator:

<!-- ignore: $project.swap is defined outside this reference excerpt -->
```x2c,ignore
keyword swap $project.swap;

swap(left, right);
```

This is `$project.swap(left, right);`. Parentheses remain mandatory for a
zero-argument macro: `generate()`.

A decorator with explicit arguments places them before its following target:

<!-- ignore: $project.range is defined outside this reference excerpt -->
```x2c,ignore
keyword range $project.range;

range(index, 0, count) {
  consume(index);
}
```

This is `$project.range(index, 0, count) TARGET`. A decorator with no explicit
arguments retains the shorter `ALIAS TARGET` spelling. If every explicit
parameter is a sequence, `ALIAS() TARGET` supplies an empty sequence; the
parentheses distinguish the argument list from a parenthesized target.

Aliases do not add a second argument grammar. Arguments remain comma-separated
and are parsed by the macro's existing `Expr`, `Type`, `Decl`, `Function`,
`Name`, `Literal`, `Param`, `Statement`, `Block`, `Field`, `Entry`,
`Enumerator`, or `Unit` parameters.
An alias cannot introduce a semicolon-separated control header or capture
arbitrary tokens.

The declaration captures the visible macro definition itself, so redefining
the same macro name later does not retarget the alias. A later `keyword`
declaration for the same alias replaces it only for following source.

Registration and use are source ordered. Expression, statement, field,
entry, enumerator, and unit macro aliases retain their result positions.
`Decorator` aliases retain their captured `Expr`, `Function`, `Statement` or
`Block`, `Field`, or `Unit` target. An invocation in the wrong position
receives the same result or target diagnostic as its direct spelling.

Aliases do not globally reserve their identifiers. A macro or a decorator with
explicit arguments is recognized only when the next significant token is `(`.
The same spelling remains available as a type, declaration, field, label, or
function name, but a direct call or typedef-style cast has the invocation shape
and is claimed by the alias. A zero-explicit-argument decorator has no
parenthesized delimiter. Its spelling is therefore claimed at each parser
position compatible with its target kind; a bare expression decorator can
capture a same-named expression read, and a bare block or function decorator
can overlap a declaration beginning with a same-named typedef.

Aliases are local to the `.x` file that declares them, including when that file
is included or is a package source. One alias map spans that file's
include-separated segments, while a nested included `.x` file receives its
own map. Aliases never leak into the including file.

An explicitly imported `.xmacro` file may contain macro definitions and
`keyword` declarations. Its aliases become visible in the importing `.x` file
at the import position. Every `.x` file that wants the spellings imports the
pack itself; an included file's import does not expose them to its caller, and
no pack is loaded implicitly by `x2c.x`. Macro templates are parsed when
defined, so a later alias does not reinterpret an earlier template; generated
`List`s and strings are not reparsed as alias-bearing source.

An alias changes spelling, not decorator capability. x2c's current thread and
lambda facilities cannot lift a local block with captured variables into a C
callback. A decorator may wrap an existing callback or a noncapturing
construct; captured thread blocks require a separate compiler feature.

An `Expr` decorator has a parenthesized body and is parsed as a prefix unary
form. Its target is the following C cast expression, including primary and
postfix expressions, unary expressions, and casts. It therefore binds before
binary, conditional, assignment, and comma operators. Parentheses widen the
target explicitly:

```x2c
macro Decorator $nonzero(Expr $target) => ($target != 0)

~int main(void) {
~  int value = 1;
int left = $nonzero() value + 1;
int whole = $nonzero() (value + 1);
~  return left && whole ? 0 : 1;
~}
```

The first initializer applies `$nonzero` to `value`; the second applies it to
the complete addition. The replacement is bound as one typed expression and
remains parenthesized at its call site. Surrounding C precedence cannot change
its meaning.

Decorators stack closest-first. The inner expansion must leave exactly one
target of the required kind for the outer decorator:

```x2c
~macro Decorator $logged(Function $function) => {
~  $(x2c.function.body $function)...
~}
~macro Decorator $validated(Function $function) => {
~  $(x2c.function.body $function)...
~}
$logged()
$validated()
int answer(int value) {
  return value * 2;
}
```

A `Function` decorator preserves the original name, storage, qualifiers, return
type, parameters, binding, and method identity. It may splice the old body,
replace it, or produce an empty body. A general `Unit` decorator can transform
a complete function or declaration, but a public target must retain the same
public binding and contract and cannot gain new public siblings. Private
targets and hygienically private siblings may be rewritten freely.

Shallow declaration collection loads macro imports so imported unit macros can
publish their declarations and protocol rows. It does not execute other
top-level Lisp forms. `Decorator`-shaped adjacency still collects the unchanged
source target. A public target's captured source must participate in the
decorator's `Match` replacement, and dropping it makes the match fail. Imported
decorators work without an extra prototype.

### Hygiene and generated names

Captured syntax retains its call-site binding identity. Free identifiers
written literally in a body resolve where the macro was defined, including
parameters and preceding declarations captured by a local macro. A declaration
written in a body receives a fresh binding identity and a private generated C
spelling for each expansion.

The `using` clause declares one or more compiler-allocated name holes. Every
occurrence of one such hole within an expansion receives the same binding;
different expansions receive different bindings. A `using` name may not
duplicate an argument hole or another `using` name. These holes are singular
`Name` holes and take no kind annotation and no `...`.

Compile-time Lisp uses `x2c.ident` to mark an exact public spelling. In a
declarator slot that spelling creates a declaration and is normally rejected if
it is already bound in the same target scope. The one completion case is a
function definition produced by a `Unit` macro after a same-scope prototype,
including one earlier in that expansion. Canonical return and parameter types,
qualifiers, linkage, and any method owner/member identity must match exactly.
The definition reuses that prototype's binding once; a mismatch, a second
definition, or a collision with another binding kind is rejected at the
invocation. A nested scope may still shadow an outer declaration normally. In
an identifier expression `x2c.ident` resolves the existing spelling and rejects
an unknown one. Use a macro `using` hole for a compiler-private name that
cannot collide. A bare Lisp `String` does not become a name when returned into
a name-capable position.

The compiler parses and types arguments before expanding a macro. It then
matches syntax, evaluates compile-time Lisp, and binds the generated syntax.
Generated declarations become visible to following source only if expansion
succeeds; a failed expansion leaves no provisional symbols or bindings.
Expansion is limited to 64 nested applications and 10,000 applications per
translation unit; an identical recursive application is rejected immediately.
Statements authored by a macro are attributed to the invocation site; captured
statements retain their original source locations.

Operators in a macro expansion use the same protocol dispatch as operators
written directly, including derived `==`, `!=`, and relational operations.
Generated enumerators are installed as they are constructed, so duplicate
spellings fail before C generation.

### Compile-time Lisp and imports

`$(...)` is the only entry from an x2c body into compile-time Lisp. At top
level its result is discarded. Inside a macro body, `$name` refers to the
hole's exact AST, and the result is inserted according to the recorded body
position. A syntax `List` inserts syntax, a scalar becomes an expression
literal, a semantic `Type` `List` fills a type slot, and a syntax sequence
splices only at a sequence splice point. `String`s are values, never source
text to be reparsed.

Inside `%(...)` and `%"..."`, `$name` and `${expression}` are runtime literal
unquote. To place a compile-time result there, the outer `${` first enters x2c
expression grammar and the inner `$(` enters Lisp: `${$(...)}`.

```text
$(import "helpers.xlisp")
$(import "project-macros.xmacro")

macro Expression $computed(Expr $value) => ($(car (list $value)))
```

`.xlisp` files execute in the translation unit's Lisp session. `.xmacro`
files may contain macro definitions and top-level Lisp forms. Import paths are
relative to the importing file, canonicalized, loaded once, and checked for
cycles. Direct Lisp file operations remain available but are not tracked as
compiler dependencies.

Compile-time Lisp is trusted code. It runs with the compiler user's authority,
including the existing native bindings and file operations; there is no
sandbox. Lisp may also construct canonical AST `List`s directly, including
static declarations. The compiler accepts a valid structure whether it came
from the parser, a `Match` capture, a template, or handwritten Lisp. Shapes
such as `src` and `construct(src)` are ordinary AST data.

The compiler does not verify every type or binding annotation in a constructed
`List` or reject it because of its origin. This is deliberately unsafe
metaprogramming, much as C permits unsafe pointer operations. Prefer literal
templates and the contextual `x2c.*` operations when you want the compiler to
construct syntax for you.

The compiler supplies these contextual Lisp operations:

```text
(x2c.syntax.type syntax)
(x2c.binding.spelling syntax)
(x2c.source.text syntax)
(x2c.embed.text path)
(x2c.diagnostic.fail message notes)
(x2c.ident spelling)
(x2c.invocation.file)
(x2c.invocation.line)
(x2c.invocation.column)
(x2c.method.resolve type name)
(x2c.function.name function)
(x2c.function.parameter function name)
(x2c.function.body function)
(x2c.type.fields type)
(x2c.type.resolve type)
(x2c.type.layout type)
(x2c.type.value? type)
(x2c.type.tag-name name)
(x2c.type.reverse-name base participant)
(x2c.type.parts type)
```

`x2c.syntax.type` returns the canonical semantic `Type` for supported typed
syntax.

`x2c.binding.spelling` accepts a name hole's valid identifier `String` or
compiler-issued identifier and binding syntax, and returns its source spelling
without exposing the numeric identity. Unknown, malformed, and forged binding
identities are rejected.

`x2c.source.text` returns the exact source spelling of one complete captured
macro argument or decorator target, including its interior whitespace,
comments, parentheses, newlines, and literal escapes. Imported macros still
read the caller's source, and syntax forwarded through another macro retains
where it was written. Constructed syntax, derived subtrees, name values, and
calls outside expansion are rejected. Standard Lisp `repr` renders a canonical
AST rather than its source spelling.

`x2c.diagnostic.fail` reports a macro diagnostic at its source location with
`String` notes and does not return.

`x2c.ident` returns the tagged name value described above and accepts a
`String` that is a valid identifier spelling.

`x2c.invocation.file`, `.line`, and `.column` return the caller's x2c source
location while a macro body is expanding. Lines and columns are one-based; an
imported macro still names its caller rather than its definition or generated
C. For example, `$(x2c.invocation.line)` produces an integer expression for the
invocation line.

The `x2c.function.*` operations inspect a decorator's captured function. `name`
returns its free-function or dotted method name as written in source,
`parameter` resolves a named parameter to bound identifier syntax, and `body`
returns the block-item sequence for an explicit `...` splice. Use
`x2c.syntax.type` on a resolved parameter when its canonical `Type` is needed.
These operations do not construct or mutate functions.

`x2c.method.resolve` performs direct method lookup for a `Type` and identifier
`String`. It returns the typed callee expression without invoking it, or `nil`
when the method is absent; callers supply arguments according to the returned
function `Type`. It does not search delegate fields. The returned callee cannot
represent the receiver's field access.

`x2c.type.fields` resolves a typedef or qualified `Type` to a complete struct
or union and returns its named fields in source order as `(("name"
DECLARED_TYPE) ...)`. Unnamed fields are omitted; incomplete and non-aggregate
`Type`s are rejected. Each declared `Type` retains pointer, array, qualifier,
and bitfield modifiers.

`x2c.type.resolve` follows the ordinary typedef chain and returns its canonical
type representation. `x2c.type.layout` returns the ordered field records of
that representation, including unnamed members and padding. Each record is
`(NAME DECLARED_TYPE)`; an unnamed field has an empty name. Use `fields` for
named-member access and `layout` when every declared field affects a decision.
`x2c.type.parts` separates a semantic type into its declaration base and
declarator modifiers as `(BASE MODIFIERS)`.

`x2c.type.value?` recognizes numeric scalars and enums, Symbol, Var, Atom,
String, List, and their typedef aliases. Pointer-shaped runtime handles such
as Array are not classified as values by this operation. `x2c.type.tag-name`
returns a round-tripping compact Symbol from the full type-name String and
the current owning source file, relative to the compiler root when applicable.
This keeps private types with the same spelling in different files distinct.
Descriptor registration still checks collisions and capacity; a compact tag
does not establish type equality.

`x2c.type.reverse-name` returns the conventional reverse-converter spelling
for base and participant name Strings, using the protocol registry's package
naming rules. For example, base `"Var"` and a registered package participant
`"geometry__Point"` produce `"geometry__Var_point"`.

The Lisp SDK also supplies operations for literals, parameters, and
expressions:

- Literals and parameters: `x2c.literal.string`,
  `x2c.literal.int`, `x2c.literal.symbol`, `x2c.embed.text`, and
  `x2c.parameters.arguments`.
- Expression construction: `x2c.expr.ident`, `x2c.expr.index`,
  `x2c.expr.field`, `x2c.expr.call`, and `x2c.expr.composite`.

`x2c.literal.string` turns a compile-time `String` into a runtime `String`
literal expression, and `x2c.literal.int` and `x2c.literal.symbol` do the same
for a number and a `Symbol`. `x2c.parameters.arguments` accepts either a
`(params ...)` node or a `List` of parameter nodes and returns their bound
identifier expressions.

`x2c.embed.text` reads a regular text file exactly, returns its contents as a
compile-time `String`, and records its canonical path as a translation
dependency. It accepts either a Lisp `String` path, resolved relative to the
file containing the Lisp form, or complete captured `String`-literal syntax,
resolved relative to the caller file where the literal was written. Absolute
paths remain absolute. A zero-byte file is valid. Invalid paths, non-regular
files, read failures, embedded NUL bytes, and `String` size overflow are
diagnosed. Runtime embedding remains explicit through `x2c.literal.string`.

The `x2c.expr.*` constructors build one expression each and take expression
ASTs as their operands. A generator composes them instead of writing the node
shapes by hand:

```text
(x2c.expr.index (x2c.expr.ident (x2c.ident "lhs")) (x2c.literal.int 0))
```

`x2c.expr.ident` wraps a name value from `x2c.ident` or a `String` spelling.
`x2c.expr.field` takes a receiver expression and identifier `String` and builds
typed field access, selecting `.` or `->` from the receiver `Type`.
`x2c.expr.call` takes a callee expression and zero or more argument
expressions. `x2c.expr.composite` takes a `List` of expressions and returns a
comma-separated initializer. Compose a call to an existing spelling with
`x2c.expr.call`, `x2c.expr.ident`, and `x2c.ident`.

Names under `x2c.*` or `_x2c.*` with a component beginning `_` are private
implementation details.

Compiler facilities load before author imports, and macro code cannot redefine
them.

Standard Lisp exposes the `List` matcher of [Pattern
Matching](../guide/match.md) as six names. `match` tests a whole subject and
returns association-list bindings, `nil` on failure, and truthy `(())` for a
match with no named binders; a pattern describes a `List` shape, so a subject
that is not a `List` fails rather than raising. `bound` reads one binder out of
that alist. `search` finds the first matching subtree. `match-replace` and
`search-replace` rewrite the whole subject or the first matching subtree from a
template. `match-case` tries each clause's pattern in order and evaluates the
first body whose pattern matched, with that pattern's binders in scope as
variables; a final `(else body)` clause runs when nothing matched.

```lisp
(match-case form
  ((add ?a ?b) (+ ?a ?b))
  ((neg ?a)    (- 0 ?a))
  (else        0))
```

A clause's pattern is quoted implicitly and written as `List` syntax, with the
same `?binder` and `*binder` spellings. A binder keeps its `?` where the body
reads it. Without an `else` clause an exhausted `match-case` is `nil`.

### Macro-visible syntax

Lisp sees the canonical parsed, typed `List` AST used by `--dump-ast`, with
source `(at ID NODE)` wrappers removed. Tags and semantic `Type`s remain
`List`s. Binding records are visible so syntax can be preserved and compared,
but their numeric IDs are opaque and must not be forged. Use
`x2c.binding.spelling` when text is required.

The compiler records where syntax was written separately from its AST value.
`x2c.source.text` exposes it only for a complete captured argument or decorator
target; arbitrary AST `List`s do not acquire source text by structural
equality. Diagnostics retain the definition, invocation, import, and generated
ancestry even after a macro returns a new `List`. Returned syntax must be valid
for its expression, field, enumerator, block-item, or translation-unit
position. Protocol declarations, macro definitions, preprocessor nodes, and
other compile-time-only source items are retained at translation-unit position
and apply their source-order effect. The compiler rejects forms that are
malformed or invalid in that position. As with other constructed ASTs, it does
not recursively verify annotations or check where a handwritten `List` came
from.

### Named types and declaration production

`NamedType` captures `NAME TYPE;` or the forward form `NAME;`. The name comes
first, with no equals sign. `{ FIELDS }` abbreviates a value struct;
`struct { FIELDS } *` explicitly declares a pointer representation. Ordinary
type and declarator grammar owns qualifiers, fields, arrays, and pointers.
The name is reserved before its fields are parsed, and the complete definition
supplies its representation. A forward declaration does not imply a pointer.
Layout must be complete wherever the ordinary type rules require it.

The captured form is `(named-type NAME TYPE)`, where NAME is a String and TYPE
is the complete canonical type syntax; a forward uses an empty TYPE. This form
is constructible by any macro or Lisp producer. Binding it publishes the same
ordinary typedef and aggregate declarations as the captured source.

A `Declaration` macro, or a `NamedType` decorator, produces declarations once
while the owning source's public declarations are collected. Its result is
retained for full binding; the producer is not evaluated again to obtain its
bodies. Nested declaration producers share this rule. The source's private
boundary and ordinary dependency invalidation apply to the retained result.
Imported and cached declarations publish the selected signatures of their
owning source.

The canonical container is `(declaration-bundle (rows ITEM ...))`. Rows may
include ordinary top-level syntax and these constructible forms:

- `(default FUNCTION)` supplies a function candidate. An ordinary declaration
  of that exact function in the owning source wins, including a later one.
  Only the selected body is bound. A candidate below `#pragma private` has
  static linkage. Two ordinary definitions still conflict.
- `(declaration-recipe CALLBACK ARGUMENTS)` defers a Lisp producer until the
  owning source's declarations are available. It is evaluated once, and its
  declarations join the same bundle.
- `(default-forward CHILD PARENT MEMBER FALLBACK)` selects an ordinary parent
  method after signatures are collected and supplies a child forwarding
  method. FALLBACK is an optional function candidate when no parent applies.
- `(syntax-recipe CALLBACK ARGUMENTS)` supplies syntax when a retained body is
  bound, allowing it to use the selected method signatures.

These rows express declaration and binding positions, without authenticating
which producer constructed them. Retained bodies also carry the usual macro
bindings and source locations for diagnostics. A consumer cannot replace a
provider's exported default by defining another function with its name.

### Class declarations

The shipped `class` keyword aliases the `$class` NamedType decorator. See
[Classes and System Macros](../guide/system-macros.md) for construction and
lifetime examples. A class preserves its explicit representation and ordinary
typedef ancestry. It adds replaceable methods through declaration defaults.
An explicit `new` suppresses its generated constructor and init requirement.
Derived classes forward the nearest applicable constructor; variadic forwarding
requires an explicit constructor.

Flat value fields produce positional constructors in declaration order, with
unnamed bitfield padding omitted. Non-flat or resource-containing aggregates
require `void T.init(T *)` for a value or `void T.init(T)` for a heap pointer,
called on zero-initialized storage. Heap defaults allocate through Scope and
provide early `free`; they do not recursively own fields. Scalar and derived
aliases retain their ordinary Var representation. Heap classes box identity;
aggregate values box a Scope-owned copy and require compatible equal/hash
operations, generated for supported value fields.

`str` and `repr` are independently replaceable. Aggregate value str delegates
to repr; heap str prints identity. Generated repr traverses printable fields
and uses addresses for opaque pointers. Repeated identities on the active
rendering path print their pointer form. Descriptor registration retains the
runtime's fixed capacity and worker-start freeze rules.

### Managed-initializer syntax

`(managed-init EXPR)` is a constructible initializer form. `$auto(value)`
produces it; an equivalent List built by another macro or compile-time Lisp
has the same meaning. It may be wrapped in typed `expr` nodes and parentheses.
Only the complete initializer of an initialized automatic declaration that is
a compound-statement item consumes the form. The declaration keeps its type,
binding identity, initialization conversions, and enclosing scope, followed by
an ordinary deferred call to the type's selected `cleanup` method.

The declared type must participate in `Cleanup(T)`, whose member is
`void T.cleanup(T)`, directly or through its ordinary typedef ancestry.
Initializers run once in source order. Each successful initializer registers
its cleanup before the following initializer runs, including within a compound
declaration. Cleanup observes the declared binding at exit; reassignment does
not dispose the old value, and returning or storing an alias does not cancel
cleanup.

Static, external, or threaded storage, field initializers, for-header
declarations, assignments, returns, call arguments, and forms nested inside
operators are outside this enclosing-block position. These are syntax-position
rules, independent of the producer of the AST. There is no runtime expression
helper or expression-exit cleanup.

### Checked foreign aliases

The reserved target macro `$x2c.foreign.alias` binds one top-level X2C
function name directly to an ABI-compatible C function:

```x2c
$x2c.foreign.alias(fclose)
inline int File.close(File file);
```

The target must be one fixed-arity function declaration without a body or
initializer, and the argument must be one direct C identifier. Static aliases
remain private; non-static aliases are published in the generated header like
any other declaration. The generated C uses `_Static_assert` and `_Generic` to
check the exact function-pointer type before defining the lowered X2C name as
the native name. Calls and address-taking therefore use the native function
itself; no wrapper object, thunk, argument mapping, or initializer is emitted.
Variadic aliases are rejected.

### Typed callback adapters

The reserved expression macro `$x2c.callback.adapt` adapts one direct function
to an explicitly named callback typedef:

```x2c
typedef String (*StringCallback)(Var);

static StringCallback array_string =
  $x2c.callback.adapt(StringCallback, Array.str);
```

The target must name a fixed, non-variadic function-pointer typedef. The
source must be a direct free-function or `Type.method` designator, not a
function-pointer variable, lambda, bound receiver, or conditional expression.
Target and source must have the same arity and exact non-`void` return type.
Parameters may be exact, or a target `Var` parameter may be extracted to the
pointer/typedef owner or `Symbol` required by the source. The adapter performs
no numeric or general coercion and does not insert, drop, reorder, or default
arguments.

The compiler emits one translation-unit-local, statically typed thunk for each
source/target pair and reuses it within that translation unit. The thunk has a
prototype before any file-scope initializer that references it, and no
incompatible function-pointer cast is emitted. The expression therefore suits
private descriptor tables and other fixed C callback positions.

## Values and literals

The tagged value model specified here is introduced gradually in
[values and Var](../guide/values.md).

### Percent literals, quote, and unquote

In operand position, `%` followed by a literal delimiter is the quoting sigil.
The delimiter selects a literal grammar, which then decides how to read the
contents. Quoting here means a parser-context change; it does not mean that
every percent form contains unevaluated symbolic data. Binary `%` remains the
modulo operator, and `%!` remains the lambda-literal prefix.

The collection and string literal forms are:

| Form | Static type | Element syntax |
| --- | --- | --- |
| `%(a b c)` | `List` | quoted values separated by whitespace |
| `%<<a b c>>` | `SymbolSet` | literal compact `Symbol`s in dense order |
| `%[a, b, c]` | `Array` | quoted values separated by commas |
| `%{a: b, c: d}` | `Map` | quoted key/value pairs |
| `%"text"` | `String` | quoted text plus unquote |

The static type in that table is the default. The declared target may instead
be one of the optional typed families: a packed `Array` from `typed-array.x`, a
packed `Map` from `typed-map.x`, or a typed cons chain from `typed-list.x`. The
literal then builds that representation directly, and an element that does not
convert raises `<no-convert>`. A null source stays null.

The empty forms are `%()`, `%<<>>`, `%[]`, `%{}`, and `%""`. Each `%[]` or
`%{}` evaluation creates a fresh allocated object that can be mutated
immediately; null is not an empty `Array` or `Map`.

Inside a `List`, `Array`, or `Map`, a bare spelling is a case-sensitive `Atom`.
It is a compact `Symbol` when `Symbol` encoding reproduces the spelling
exactly; otherwise it uses `<lsym>`. Consequently, `%(name)`, `%[name]`, and
the key in `%{name: 1}` hold the same value as an explicit `<name>`, and the
angles are redundant. Use angles when bare collection syntax would read the
text as another value, as in `<1>` for the `Symbol` `1` rather than the integer
`1`, or when compact `Symbol` representation is required. The empty `Symbol`
must likewise be written `<"">` because a bare `Atom` cannot be empty. An
angle spelling that does not fit is rejected instead of falling back to
`<lsym>`.

Integer, floating, signed numeric, and character literals retain their
concrete types. Lowercase `void` remains the absence sentinel and is rejected
if collection construction tries to store it.

`$name` inserts one identifier expression into a quoted collection.
`${expression}` inserts one arbitrary x2c expression, including calls, member
and index expressions, operators, casts, compound literals, `NULL`, enum
constants, and comma expressions. Each expression is evaluated once. `@name`
and `@{expression}` splice a `List` into a surrounding `List`; Arrays and Maps
have no splice form. The identifier forms are the short versions of the braced
expression forms. The [collections](../guide/collections.md) chapter walks
through building and using each one.

For `List`s that will be evaluated as Lisp, `'`, `` ` ``, `,`, and `,@` are the
short forms of `quote`, `quasiquote`, `unquote`, and `unquote-splicing`. Each
wraps the one element that follows it, wherever it appears, so `%(...)` and
the Lisp reader construct the same `List` data from the same text. Reader
punctuation also ends a bare `Atom`: `%(a,b)` is `a` followed by
`(unquote b)`. These spellings do not replace x2c's `$` and `@`: those still
insert or splice x2c values while the `List` itself is being constructed.
A `@` followed by whitespace, `)`, or `=` is the ordinary `@` or `@=`
operator atom, so `%(op @ a b)` spells the same `List` the parser builds.

`%<<...>>` is an immutable ordered `SymbolSet`. Bare entries are compact
`Symbol`s rather than `Atom`s, and their source positions are their numeric
indexes. Entries must be literal spellings; interpolation, splicing, and
runtime expressions are not accepted. Every entry must survive compact `Symbol`
encoding exactly. Duplicate encoded `Symbol`s are a
compile-time error. `SymbolSet.index` returns the source-order index or `-1`,
`contains` tests membership, `getindex` performs the reverse mapping, and the
`Iter` protocol traverses members in source order. The compiler emits the
perfect hash and ordered membership table as static bytes, with no runtime
construction or allocation.

Inside `%()`, `%[]`, `%{}`, and `%""`, `$` is the unquoting sigil. It leaves
the selected literal grammar, parses and evaluates one x2c expression, inserts
the converted result, and returns to the literal grammar. In `%()`, `@` makes
the same crossing but splices the evaluated `List`'s elements. Collection
insertion converts to the representation required by the literal; `String`
insertion accepts `String`, `Symbol`, declared converters, `Var`, aliases of
`Var`, and supported numeric values under the existing conversion rules.

The braces belong to the unquote and contain one complete x2c expression,
including nested calls, indexing, casts, assignments, conditionals, comma
expressions, and nested literals. In a collection, `$name(...)` instead inserts
`$name` and then reads `(...)` as a nested symbolic `List`. In `%""`, the
parentheses after `$name` are text. A runtime call in any quoted form is
therefore `${name(...)}`.

Nested `(...)`, `[...]`, and `{...}` remain quoted `List`, `Array`, and `Map`
data, and nested `"..."` selects the x2c `String` grammar with its interpolation
and escape rules. None repeats the `%` sigil, because a bare `%` inside quoted
collection data is an `Atom`: `%(k %"txt")` reads as the three elements `k`,
`%`, and `"txt"`. `${"text"}` instead inserts an ordinary C string expression.
Unescaped comma, colon, `]`, and `}` terminate collection Atoms; backslash
escaping or angle syntax expresses those bytes as data. `%<<...>>` accepts
literal `Symbol`s only and permits no interpolation or splicing.

`$(...)` remains compile-time Lisp in ordinary x2c code. Inside a quoted
collection, `${$(+ 40 2)}` first unquotes into x2c and then enters compile-time
Lisp.
`$name(...)` remains a macro invocation in x2c. These parser contexts do not
change Lisp `quote` or `quasiquote`.

Percent strings are byte strings: they may span physical lines and their
`\\x`, `\\u`, and `\\U` escapes consume one or two hexadecimal digits.
Ordinary C string and character literals instead follow C escape widths,
including exactly four digits for `\\u`, eight for `\\U`, and one or more for
`\\x`; an unescaped newline does not continue an ordinary C literal.

Adjacent ordinary C string literals form one expression, including across
comments or newlines. Their separate escape boundaries are preserved:
`"\\x41" "B"` contains `A` followed by `B`. The result keeps ordinary C string
typing and converts to `String` when its context requires it. This adjacency
rule does not combine percent strings or change quoted collection syntax.

Immutable literal construction is cached for the process lifetime. This
includes an ordinary C string literal when its context promotes it to `String`,
as in `String name = "x2c";`; a dynamic `char *` or `char[]` value still
converts when the expression is evaluated. The ordinary literal keeps its exact
C escape spelling and decoding, and does not acquire percent-string escape
rules.

Cached `String`s, boxed `Var` values, and canonical `List` graphs are allocated
eagerly during translation-unit initialization and retained for the process
lifetime. A cached literal in a public inline function uses private storage in
each C translation unit that includes the generated header; canonicalizers
still make equal `String` and `List` values share their value identity. A
guarded call on the inline entry is the fallback on hosts where eager
constructors do not run. Consequently, an allocation failure may occur before
`main` rather than at the source expression.

Caching does not change the other identity rules: `List`s and non-empty
`String`s are canonical when constructed through their canonicalizers; `Array`s
and `Map`s are mutable identity-bearing objects and are constructed at each
evaluation. Non-empty `Array` and `Map` literals use counted construction. Raw
`Null` remains valid collection data, while a dynamic expression that evaluates
to `void` reaches the collection owner and is rejected rather than ending
construction.

File-static `String`, `List`, `Array`, and `Map` declarations may use their
percent literals directly. A file-static `Var` may likewise use one of those
literal values:

```x2c
static String child = %"$root/child";
static String root = %"root";
static List names = %($root $child);
static Var literal_index = %{root: $root, child: $child};
```

The compiler leaves each C declaration zero-initialized and moves its
runtime assignment into the translation unit's guarded initializer. Literal
caches run first, followed by the assignments in dependency order; a
declaration may therefore depend on a later file-static declaration.
Independent assignments retain source order. Every object referenced by one
of these initializers must itself be file-static, and a dependency cycle is a
compile-time error. Native initializer operands expand at the original source
position: later macro definitions do not change them, `__COUNTER__` keeps
source order, and explicit inline tags remain visible at file scope. Native
macro invocations retain their normal stringizing and token-pasting rules.
Tags hidden inside an opaque native macro remain subject to native C scope.

A function-local `static` declaration with a runtime-valued initializer runs
once when control first reaches it. This includes aggregates containing
`String` or `Var` values, function calls, and values from function arguments.
Concurrent calls wait for the initializing call to publish the whole object.
If initialization raises an Error, a later call retries; side effects already
performed by the initializer remain. Recursive initialization, including a
cycle between initializing threads, raises `bad-state` rather than waiting
forever. A `static threaded` declaration follows the same rule separately in
each thread. Native constant initializers retain native C static storage.

Runtime-initialized local objects preserve their declared type, qualifiers,
array shape, and address across calls. Their storage lasts until process
shutdown, or thread teardown for `threaded` objects. This storage does not
extend the lifetime of values it refers to: an initializer allocating a Map
inside a temporary Scope still gives that Map the ordinary Scope lifetime.
Use an owner that outlives every use of the stored value. Failed initialization
retains the reserved address; the next attempt starts with zeroed storage.
Only successful initialization publishes the value, and retry does not change
referent ownership.

A `goto` or switch dispatch cannot bypass a runtime static declaration and
enter its remaining block. Put the declaration before the switch, or put it
inside a case's own block. A nested switch reached after initialization is
valid.

Native macro calls can be runtime initializers. A bare unknown native macro
name, however, retains native C initializer rules: its expansion may be either
a constant or a call, which x2c does not inspect. Use an explicit function call
when a runtime expansion needs first-use initialization. Native macro bodies
also cannot name a lowered local object implicitly; pass the object as a macro
argument so its ordinary bound expression is preserved.

### Symbols

`<name>` and `<"punctuated name">` produce a 64-bit immediate `Symbol`.
`Symbol`s are encoded, not allocated or entered in an intern table.

The encoding is selected from the payload:

- the restricted 5-bit alphabet preserves at most ten characters;
- the general 7-bit encoding preserves at most seven characters.

A source literal is accepted only when decoding the encoded value reproduces
its exact spelling. Case folding, `_`/`-` folding, and truncation are compile
errors in literals. `Symbol.new` remains the runtime encoding API and
truncates or normalizes dynamic input to the selected capacity.
`Symbol.try_new` instead reports whether dynamic input has an exact compact
representation and leaves its output untouched when it does not. Equality
compares the encoded value.

`Symbol`s also name outcomes and states. For example, `Lisp.read` returns
`<value>` or `<eof>`. It raises `<incomplete>` or `<malformed>`, and neither
returns to the call. `Error` causes such as `<bad-sig>`, `<no-symbol>`,
`<bad-arity>`, `<bad-types>`, and `<bad-result>` are `Symbol`s too. Numeric
enums remain appropriate when their values are indexes, packed fields,
arithmetic inputs, or external numeric encodings.

For Lisp input, `<incomplete>` means more source can complete the current form:
an open list, string, block comment, or symbol literal, a reader prefix without
its form, or an escape cut off by end of input. `<malformed>` means the bytes
already prove the form invalid, such as a bad escape, raw string newline,
malformed number, invalid closed symbol literal, or stray closing parenthesis.
The shared `Tokenizer` classifies lexemes; `Lisp.read` checks structural form
balance and preserves the form-start cursor on either failure.

### Atoms

`Atom` is the canonical exact-name type used by `List` literals and Lisp. It is
`Var`-shaped and has two representations:

- an immediate compact `<symbol>` when encoding and decoding reproduces the
  exact spelling bytes;
- a private `<lsym>` whose payload is the canonical `String` pointer otherwise.

`Atom.intern` is the only function that maps a spelling to a representation.
Repeated construction of one spelling has identical `Var` bits. Long `Atom`
equality therefore completes in the existing raw-`Var` fast path, and its hash
is the `String`'s cached hash. `Atom.str` returns the exact bytes, and `Atom`
representation escapes delimiters, numeric-looking prefixes, comment openers,
whitespace, controls, and backslashes so both `%()` and `Lisp.read` recover the
same value.

Long `Atom`s follow the canonical `String` pool lifetime, which is described in
[scopes and lifetime](../guide/memory.md). Promoting a `List` also promotes
long `Atom` payloads contained in it; a standalone long `Atom` that must escape
a child `String` pool can promote its `Atom.str` before that pool is released.

For a side-by-side introduction to the two types, see
[symbols and atoms](../guide/symbols.md).

### `Var`, Null, and `void`

`Var` is the tagged value used by heterogeneous collections and generic
runtime APIs. Supported native source types round-trip through their matching
`Var` tags. `long`, `unsigned long`, `long long`,
`unsigned long long`, and `long double` use immutable scope-owned boxes while
`Var` itself remains eight bytes. Their tags are `<long>`, `<ulong>`,
`<llong>`, `<ullong>`, and `<ldouble>` respectively; the runtime derives their
widths from those C types. Explicit `i48/u48` tags complete the numeric family
set. The same names with `*` or `**` identify their pointer families.

Raw `Null` is the all-zero `Var`. A typed empty `String` and `nil`/`List`
preserve their type tag when boxed. `Array`s and `Map`s instead require
allocated objects even when empty; boxing a null pointer with either value tag
is an invariant violation. `void` is the all-ones terminal/tombstone value used
by APIs for exhaustion or absence. Status-bearing `Iter` and `Map` APIs
separate success from payload bits. `Iter.next`, `Map.get`, and `Map.del`
use `void` for exhaustion or absence. Malformed representations, including null
wide boxes and null `Array` or `Map` values, are rejected. Every accepted
nonnull pointer must name a live object established by its constructor.

Lowercase `void` is contextual. In a type position it retains C's no-result
type, including function returns, `(void)` parameter lists, `void *`, casts,
and `sizeof(void)`. In an expression position it is a `Var` literal for the
all-ones sentinel. Parentheses do not change that distinction: `(void)` is a
parenthesized sentinel expression when it stands alone, while `(void) call()`
and `(void *) pointer` are casts because an operand follows the complete type.

Two sentinel operands compare equal with `==` and identical with `===`;
`!=` and `!==` are their exact inverses. A sentinel and any ordinary value
compare unequal. `Var.equal`, `Var.fallback_equal`, `Var.same`, and the four
equality and identity operations accepted by `Var.binary` follow those rules.
`Var.str`, `Var.repr`, `Var.write_str`, and `Var.write_repr` all render the
sentinel as lowercase `void`.

Hashing, ordering, truthiness, iteration, conversion, arithmetic, compound
updates, and increment or decrement raise `<void-op>` when they receive it.

### Exact Var-tag tests with `is` and `is not`

The contextual `is` operator tests a `Var` value against a source type or an
exact tag `Symbol`. Add `not` after `is` to invert the result without wrapping
the test in `!()`:

```x2c
Var value = 42;

int integer = value is int;
int byte = value is u8;
int sequence = value is List;
int exact = value is <i32>;
int pointer = value is (Var *);
int absent = value is void;
int not_byte = value is not u8;
int present = value is not void;
```

The left operand must have static type `Var` or a file-scope alias of `Var`.
The result is `int`. The operator has relational precedence, and its left
operand is evaluated exactly once. A `Symbol` expression on the right is also
evaluated exactly once. A type selector is compile-time syntax and is not
evaluated. `is not` has the same precedence and evaluation rules, then
logically negates the exact-tag result. `is` and `not` remain ordinary
identifiers in all other positions, so existing variables with either name
and calls such as `value.is(<i32>)` are unchanged.

The test compares exact `Var` tags. It does not test numeric convertibility,
protocol ancestry, or C type identity. Qualifiers and aliases are resolved to
the tag family used by boxing, which means source types that share one tag
cannot be distinguished. For example, `char` and `signed char` both select
`<i8>`, while `int`, `int32_t`, and `i32` all select `<i32>`.

The right operand may be either a type or a `Symbol` expression. Accepted types
include a supported scalar or system numeric typedef, a builtin runtime type
such as `String`, `List`, `Symbol`, or `Var`, a visible type with a declared
`protocol Var(T)` conversion, or a package-qualified form of one of those
types. Supported pointer and double-pointer types are also accepted, but
declarator-shaped types must be parenthesized:

```x2c
static int pointer_tags(void) {
  int number = 0;
  int *pointer = &number;
  int **double_pointer = &pointer;
  Var pointer_value = pointer;
  Var double_pointer_value = double_pointer;
  return pointer_value is (int *) &&
         double_pointer_value is (int **);
}
```

An unparenthesized pointer selector is rejected with the parenthesized
spelling. `Array`s, function types, unsupported pointer depths, unknown types,
and aggregates without a `Var(T)` adoption have no tag to select and are
rejected. Enum selectors are rejected because enum values box as the shared
`<i32>` family and retain no nominal enum identity.

A literal or computed `Symbol` is used directly as the exact tag selector:

```x2c
Var value = 42;
Symbol wanted = <i32>;

int literal = value is <i32>;
int computed = value is wanted;
```

An unregistered `Symbol` cannot match a valid `Var` tag, so the result is
false. No other expression type is accepted on the right: numeric, pointer,
object, and `Var`-valued expressions do not stand for types.

Lowercase `void` is the one selector whose type spelling also names a value.
It tests the all-ones absence sentinel through `Var.is_void`: `void is void`
is true, while the sentinel does not match any ordinary tag or type. Raw `Null`
has the pointer-family `<p48>` tag, so it matches `(void *)` and does not match
`void`; there is no `Null` selector.

A `Type` hole or a `Symbol`-valued `Expr` hole in an `Expression` macro may
occupy the selector position. An expanded type is resolved in the invocation
context, including pointer types:

```x2c
macro Expression $has_type(Expr $value, Type $T) => ($value is $T)
macro Expression $has_tag(Expr $value, Expr $tag) => ($value is $tag)

static int has_pointer_type(void) {
  int number = 0;
  int *pointer = &number;
  Var value = pointer;
  return $has_type(value, int *) && $has_tag(value, <i32*>);
}
```

### Dynamic numeric conversion

The public numeric conversion domain contains all 15 `Var` families: `i8/u8`,
`i16/u16`, `i32/u32`, `i48/u48`, `long/ulong`, `llong/ullong`, and
`f32/f64/ldouble`.
`Var.convert(value, tag)` returns the converted value and raises the specific
`Error` cause when no conversion exists, the target is invalid, the value is
out of range, or the `Var` encoding is invalid. None of those causes return to
the call. Compiler-inserted `Var`-to-native numeric conversion passes through
the same function before using the target extractor. The scalar-named readers
`Var.int`, `Var.double`, and their siblings apply the same rules directly. A
matching tag reads its payload, and any other numeric tag converts through
`Var.convert`. The raw payload readers `Var.integer` and `Var.floating` and the
wide `*_value` functions remain exact low-level decoders.

Integer-to-integer conversion never uses a floating intermediary. It retains
the destination-width low bits; signed destinations interpret those bits as
two's-complement. Floating-to-integer conversion truncates toward zero when the
truncated result is representable. NaN, infinities, and out-of-range results
report `<conv-range>`. Integer-to-floating and floating
narrowing use normal host floating-point behavior.

These numeric rules do not define conversions between nonnumeric tags.
`String`, `Symbol`, collection, pointer, and custom-object values use their
declared conversions. Numeric-to-`String` interpolation boxes through the
verified numeric tags and renders with `Var.str`. A structurally valid
nonnumeric `Var` may convert to its own tag unchanged; conversions to other
tags must be defined separately.

A printf-family call with a static format can also format a `Var`. Numeric
format specifiers convert it to the required promoted C type through
`Var.convert`; `%s` uses `Var.str`. The recognized families are `printf`,
`fprintf`, `sprintf`, `snprintf`, `String.printf`, `File.printf`, and
`Buffer.printf`. A call with a `Var` variadic argument requires one direct
static format literal. Automatic lowering covers numeric conversions, `%c`,
`%s`, `*` width and precision, and the `hh`, `h`, `l`, `ll`, and `L` modifiers.
Other modifiers, pointer and count conversions, wide strings and characters,
and positional formats require explicit native arguments.

### Dynamic truthiness and binary operators

When a condition has static type `Var` or a file-scope alias of `Var`, the
compiler applies the `Var.truth` base member in `if`, `while`, `do`, classic
`for`, `?:`, and unary `!`. A static protocol participant uses its eligible
`truth` member: an implementation, native alias, or base default. The compiler
applies the member independently to operands of `&&` and `||`, leaving C's
short-circuit evaluation intact.

Truthiness is false for numeric or `Symbol` zero, `Null` and null pointers,
canonical empty `String`/`List`, and empty `Array`, `Map`, `Block`, `Bytes`, or
`Buffer` values. It is true for nonzero values, NaN, infinities, nonempty
containers, and other nonnull objects. A nonnull `Iter` is true even when
exhausted; the test does not probe its producer. `void` is outside the value
domain, and a compiler-inserted `Var.truth` raises `<void-op>` for it. That
raise does not return to the test.

If either operand of `+`, `-`, `*`, `/`, `%`, `@`, `<<`, `>>`, `&`, `^`, or
`|` has static `Var` identity and the other operand is `Var` or statically numeric,
both operands convert to `Var` and the result is `Var`. A nonnumeric operand is
rejected at compile time if its type is known statically, or at runtime if it
is held in a `Var`. Native-only expressions remain native C. Integer operations
promote their operands to a common integer type. Arithmetic and left shift
retain the low bits that fit that type; signed results interpret those bits as
two's-complement. Signed right shift fills the sign bits. A negative shift
count or a count at least the promoted left width fails, as does integer
division or remainder by zero. `String`-tagged `Var` values additionally accept
`+` with a `String` or raw C string operand. The result is a canonical
`String`; no other runtime tag is stringified implicitly.

Floating operands support `+`, `-`, `*`, and `/` in the widest participating
floating family. Host floating behavior includes infinities or NaN from
floating division by zero. Remainder, shifts, and bitwise operators reject a
floating operand. Direct `Var` lvalues support prefix and postfix `++`/`--`;
prefix returns the updated `Var` and postfix returns its original value. Unary
`-` uses an eligible `neg` protocol member for a static participant or the
`Var` base member for a dynamic value. Comparisons dispatch separately.
`==`/`!=` use an eligible `equal` member, relational punctuation derives from
`compare`, and `===`/`!==` remain unconditional identity tests. Eligible means
implemented, native, or a base default. Equality, identity, and total ordering
do not become binary-arithmetic operations.

For `==` and `!=`, a C string literal opposite an operand of static type
`String` converts to `String` before ordinary protocol comparison. This
applies in either operand order and through parentheses around the literal.
Other C pointer expressions, including variables, casts, and conditional
expressions, retain their native comparison behavior. `===` and `!==` do not
perform this literal conversion.

Direct runtime calls to `Var.binary` additionally accept comparisons and eager
`&&`/`||`. The compiler does not use that eager logical path. It converts each
`Var` operand at its original C short-circuit position.

### Protocol-backed direct updates

A direct participant lvalue supports `+=`, `-=`, `*=`, `/=`, `%=`, or `@=`
when its protocol-resolved `add`, `sub`, `mul`, `div`, `mod`, or `matmul`
member has signature
`Participant member(Participant, RHS)`. The right operand is converted to
`RHS`. Prefix and postfix `++`/`--` use `add` or `sub` with the integer `1`
converted to `RHS`.

The lvalue is evaluated once. Its current value is passed to the member once,
and the returned `Participant` is stored once. Compound assignment and prefix
forms return the stored value; postfix forms return the original value. Plain
`=` and the identity operators `===` and `!==` are not overloadable.

### Dynamic compound assignment

Native-only compound assignment remains native C. If a numeric compound
assignment involves `Var`, the compiler takes the address of an addressable
lvalue once. The runtime loads its current value, performs the dynamic
operation, converts the result to the declared target family, and stores once
only after every step succeeds. The expression result is that converted value.
A failed conversion, divide, remainder, or shift leaves the target unchanged.

This rule covers native scalar numeric and `Var` lvalues, including C indexing
and member access. The compiler selects a typed adapter from the resolved
storage family; plain `char` and `signed char` remain distinct storage types
even though both box as `<i8>`. Enum and bitfield targets are excluded.

`String`-tagged `Var` values accept `+=` with `String` or raw C string
operands. Native `String` lvalues accept the same `+=` spelling as
concatenate-and-rebind. Concatenation finishes before the binding is changed.

`Array` and `Map` elements support all ten numeric compound operators and
prefix/postfix `++`/`--`. The runtime performs the element read, operation,
stored-tag conversion, and write in one call. A missing `Map` key or
out-of-range `Array` index fails without insertion, growth, or mutation.
Numeric `+=` is the `Map` exception. A missing destination key is inserted with
the right-hand side as its initial value, as though the prior value were
numeric zero, and the inserted value keeps the right-hand side's numeric tag.
The read, modify, and write happen in one call; that is not a thread-safety
guarantee.

Additive initialization does not make `void` numeric. A missing or `void`
right-hand side still fails, as do nonnumeric `+=` and every other compound
operator when the destination key is absent. Successful insertion is a
structural `Map` change and may invalidate outstanding traversal state.

A direct, optionally parenthesized `Array` or `Map` indexed right-hand side
uses one typed cross-container helper. The source value is captured before the
destination is committed, including same-container and same-slot cases. A cast
or larger expression reads the source and then performs one destination update.
Each base, selector, and value expression is evaluated once, and C's operand
evaluation order remains unchanged.

Dynamic conversion, operators, and updates do not have parallel error-code
APIs. A failure raises its specific cause through the ambient `Error` channel.
When a handler consumes that `Error`, a value-producing operation returns its
documented sentinel and an update leaves its target unchanged. The sentinel
says that no result or mutation was produced and does not encode why.
`<alloc-fail>` and `<size-limit>` are exceptions: they may transfer to a
matching filtered `catch`, but never return a sentinel or continue the update.

The `try_*` prefix remains for status results whose payload alone cannot
represent every successful result. Examples include `Map.try_get` for presence,
`Iter.try_next` for exhaustion, `String.try_long` for parse success, and
match/search operations for no-match. Those integer results answer whether a
result exists or an operation applies. Failure causes still use the ambient
`Error` channel rather than a status `Symbol` or error out-parameter.

## Indexing and slicing

Native C arrays and pointers retain C indexing. `Array`, `List`, `String`, and
`Map` also define indexed access.

- `Array`, `List`, and `String` accept negative indices.
- An out-of-range `Array` or `List` read returns `void`.
- An out-of-range `String` read returns `-1`; its indexed result is a byte
  represented as an `int`, not a one-byte `String`.
- A missing `Map` key returns `void` through `get` and bracket reads;
  `Map.try_get` reports presence separately.
- `Array` literal elements cannot be `void`; counted construction enforces the
  same invariant as `Array.push`.
- `Map` literal keys and values cannot be `void`; counted construction enforces
  the same invariant as `Map.set`.
- `Array` and `Map` indexed assignment are supported.
- `Array` and `Map` indexed compound assignment and prefix/postfix `++`/`--`
are supported as single-call updates.
- Numeric `map[key] += value` initializes an absent key from `value`; other
  indexed updates require an existing destination.
- `List` indexed assignment is not supported.
- `String` indexed assignment is not supported: `String` is immutable, and an
  in-place write would corrupt every equal `String` sharing its canonical
  storage. Use the copy-producing `String.withindex` result, or bind a
  transient `String.malloc` buffer to a `char *` and write that natively.

The optional typed families have different indexing rules:

- A packed `Array` from `typed-array.x` has a raw bracket: reads, writes, and
  compound updates index a concrete element pointer with no null test, no
  bounds test, and no negative-index normalization. An index outside the
  elements is undefined as it is for the equivalent C pointer. `try_get` is
  the checked read, and it does normalize a negative index.
- A packed `Map` from `typed-map.x` adopts `protocol Var`, so its `getindex`,
  `setindex`, `updateindex`, and `postfixindex` members provide bracket reads,
  writes, compound updates, and numeric postfix updates. A typed cons chain
  from `typed-list.x` does not adopt `protocol Var`; use `car` and `nth_cdr`.

`Array`, `List`, and `String` support `value[start:stop:step]`. Bounds and step
may be omitted. Negative bounds and reverse steps are normalized consistently.
A zero step is invalid.

`List` indexed updates and `String` character updates remain unsupported.
`Array`-level and `Map`-level `+=` are also unsupported; update an element
instead of the container binding.

## Iterator destination omission

Iterator sources and lazy operations take a final `Iter` destination pointer.
That argument may be omitted for calls nested in an iterator expression that
is consumed immediately by `try_next`, `next`, `done`, `list`, `array`,
`reduce`, `foldl`, `any`, `all`, `find`, `count`, `sum`, `product`, `min`,
`max`, or `foreach`.

For every missing destination, x2c passes a distinct zero-initialized
`struct Iter` compound literal. Its automatic lifetime is the enclosing block,
so every source remains valid while the final consumer runs. Explicit final
destinations are preserved, including a mixture of explicit and omitted
destinations in one chain. Calls nested in iterator-valued arguments, such as
both inputs to `zip` or `map2`, are completed recursively.

This is specific to iterator destinations, not general default-argument
syntax. An iterator assigned to a local, returned from a function, boxed, or
passed to an arbitrary call still requires explicit storage at every stage.
`unzip` also remains explicit because its two result iterators share one
caller-owned `UnzipShared` buffer.

## Lambdas

The literal forms are `%!(parameters) => expression` and
`%!(parameters) => { statements }`. An optional `using &name, &other` clause
between the parameters and `=>` captures those surrounding bindings by
reference.

An expression body parses through assignment precedence. An unparenthesized
comma separates arguments of an enclosing call; write `(first, second)` when
the comma expression itself is the lambda body.

Current guarantees:

- an expression body produces its value; a native C `void` expression runs
  once and produces Null;
- a block body accepts statements, including declarations, control
  flow, `defer`, and nested lambdas. `return expression;` converts the result
  to `Var`; bare `return;` and fallthrough produce Null;
- bare parameters are `Var` values;
- nullary and multi-parameter forms work;
- unlisted automatic values referenced by the body become read-only snapshots
  when the lambda is created, provided their types convert to and from `Var`;
- assignment, updates, taking a captured binding's address, and passing it by
  reference require `using &name`. Explicit readers and writers share the
  original binding; adding another lambda cannot change a snapshot;
- globals remain directly accessible.

```x2c
int value = 1;
Func read = %!() => value;
Func bump = %!() using &value => ++value;
value = 2;
printf("snapshot=%ld shared=%ld\n", read().integer(), bump().integer());
// snapshot=1 shared=3
```

Clause names resolve in the surrounding scope. Parameters and local
variables still shadow them. Repeated entries are redundant, and an entry
unused by the body creates no capture.

Typed parameter syntax retains the complete parameter declarator. A parameter
such as `int &value` aliases its caller's lvalue just as it does in a function;
a dynamic `Func` call checks the source type and qualifiers before passing the
address to its generated adapter. Value parameters are evaluated once and
boxed, while reference parameters take the lvalue's address without first
reading it.

A noncapturing lambda remains a generated C function and can adapt to a
supported C callback type, including `int (*)(int)`, in an initializer,
assignment, argument, or return. A local typedef of the callback type has the
same behavior. Parentheses around the lambda preserve this adaptation.
Where a `Func` is expected, a fixed nonvariadic function or
function-pointer value converts implicitly when the `Func` conversion supports
its parameters and result. Value parameters and results need a lossless `Var`
conversion, and reference
parameters retain their typed lvalue address. A direct function or noncapturing
lambda has one file-static `Func` handle that every conversion reuses. A
function-pointer expression is evaluated once and its exact pointer is copied
into a new `Func`; later assignment to the source pointer does not retarget it.
A null function pointer instead produces null `Func` without allocating a
binding. Variadic functions do not convert implicitly; use the advanced
`Func.new_rest` API when a native operation consumes a rest `List`.

A capturing lambda has static type `Func`; calling it directly returns `Var`.
The same is true after a noncapturing lambda converts to `Func`. Successful
effect-only calls produce Null through either route. Explicitly returning
the `void` sentinel still produces it, and `Func.apply` rejects that result.
A `Func` cannot be passed as a context-free C callback because that ABI has
nowhere to carry its captured values. `List`, `Array`, `String`, and `Iter`
higher-order methods accept `Func` instead, so they can use captured callbacks
without a second API.

Each snapshot conversion executes once, in body first-use order, when the
`Func` is constructed. A reference capture uses a shared typed cell allocated
where the original binding is declared, preserving initializer order and
single evaluation. Calling the `Func` allocates no capture storage.

A default capture of an outer reference parameter snapshots its current
referent. `using &name` retains the caller's alias without another cell.
Reference captures retain the source's qualifiers: capturing a `const` object
by reference does not make it writable.

Nested lambdas capture from their enclosing lexical environment. Sharing an
original variable requires `using &name` at every enclosing lambda. An inner
reference clause cannot reach through an enclosing snapshot. A nested
snapshot records the value when that inner lambda is constructed.

Capturing a pointer, `Array`, or `Map` copies its pointer value. The binding is
read-only, but its pointed-to contents remain mutable; later rebinding the
original variable does not retarget the capture. An aggregate without `Var`
conversions cannot be captured by value; capture a pointer or explicitly
capture the aggregate by reference.

Captured values and cells remain valid only as long as their owning `Scope`.
Caller objects and pointer-backed contents keep their existing lifetimes;
reference capture extends neither and adds no synchronization. Reused direct
function handles have file-static lifetime.

## Statements

### C control flow

x2c accepts C-style `if`, `switch`, `while`, `do`, classic `for`, labels,
`goto`, `return`, `break`, and `continue` statements.

### System block decorators

The built-in macro pack installs `$scope`, `$let`, and `$lock` without a
per-source import. They retain the normal runtime declaration requirements
and macro collision policy. None has a bare keyword alias.

`$scope()` retains one region around its following statement and defers
release inside an inner block containing that statement. `$scope(pointer)`
evaluates the Scope-pointer expression once, pushes that destination, and
uses the same inner-block placement for a deferred pop. Pop restores the
previous destination without destroying the selected Scope. More than one
argument is an invocation error. A decorator around a loop creates one
region; a decorator around its body creates one per iteration.

`$let(place, value)` captures the address of the place once, saves its value,
registers restoration, assigns the new value once, and runs its body. The
place must be addressable and assignable, and its storage must outlive the
body. Restoration uses the captured address even when later changes would
cause the original expression to name different storage.

`$lock(mutex)` evaluates a Mutex expression once, calls `lock`, then defers
`unlock` around its body. A failed acquisition registers no unlock. These
forms add ordinary blocks and defers without hidden loops; break, continue,
return, and error transfer retain their ordinary enclosing boundaries.

See [Classes and System Macros](../guide/system-macros.md) for examples and
expansions.

### With

`with expression [as name] { ... }` gives an expression a short lexical name.
The name defaults to `_`:

```x2c
~typedef struct Point { int x, y, z; } Point;
~int main(void) {
Point point = { 0 };
with point {
  _.x = 1;
  _.y = 2;
  _.z = 3;
}
~  return point.x == 1 && point.y == 2 && point.z == 3 ? 0 : 1;
~}
```

The expression may be any x2c expression. Each use acts as a parenthesized copy
of that expression. A call used twice is called twice, and an unused expression
is not evaluated. `with` does not introduce a hidden runtime temporary or
promise single evaluation.

The name is available only in the required braced body and only in expression
positions. It does not replace field names, labels, declaration names, type
syntax, or literal atoms. A declaration of the same name shadows it from that
declaration onward.

`with` nests lexically. An inner use of the same name shadows the outer one,
and the outer meaning resumes after the inner block. Naming the outer
expression keeps it available through an inner default shorthand:

```x2c
~typedef struct Point { int x, y; } Point;
~typedef struct Pair { Point left, right; } Pair;
~int main(void) {
~  Pair pair = { 0 };
with pair.left as left {
  with pair.right {
    _.x = left.x;
  }
}
~  return 0;
~}
```

At the beginning of a statement, `with` always introduces this construct. It
remains a contextual identifier in declarations and other expression positions.
A statement that calls a function named `with` uses the spelling
`(with)(arguments);`.

### Foreach

`foreach(declaration, expression) statement` evaluates the expression once
and visits its elements. The declaration has no trailing semicolon and may
bind one name or destructure a key and value:

```x2c
~int main(void) {
~  List values = %(1 2 3);
~  Map map = %{1: 10, 2: 20};
~  int total = 0;
foreach(int value, values) total += value;
foreach(int key, map.keys()) printf("%d\n", key);
foreach(Var (key, value), map)
  printf("%d=%d\n", key.integer(), value.integer());
~  return total == 6 ? 0 : 1;
~}
```

Cursor-backed collections use their typed `try_next` member directly. Other
values convert to `Iter`, and each yielded `Var` converts to the declared loop
type when that conversion exists. [Iteration](../guide/iteration.md) covers
the loop forms and the `Iter` protocol in tutorial order.

Foreach uses `Iter.try_next`. Successful payloads exclude `void`,
which is the terminal sentinel returned by `Iter.next`.
A boxed `Var` without a registered iterator adapter produces an
already-exhausted iterator. A receiver with a statically known type and no
visible exact or inherited `Iter` conformance is rejected as not iterable.

### Match

`match (expression) { case pattern: statement ... default: statement }`
evaluates its subject once and executes the first matching case.
[Pattern matching](../guide/match.md) introduces the pattern language with
worked examples.

Patterns use `List`-literal notation. `?` and `*` are anonymous wildcards.
Named binders are `?IDENT` and `*IDENT`, where `IDENT` is
`[A-Za-z_][A-Za-z0-9_]*`. Binder keys are canonical `Atom`s, so long and
case-sensitive identifiers work in recursive, prepared, and compiled match
paths. A sigil-leading `Atom` with any other suffix is a malformed pattern:
recursive matching fails, `MatchPlan` reports `binder-name`, and compiled
`match` syntax reports a positioned diagnostic.

`Match` operators and predicate names are compact `Symbol`s. The
`?binder?`, `*binder?`, and `!op?` spellings are reserved control vocabulary
only in their `!is` predicate operand positions; they are not named
binders. Nested `List` patterns, literal comparison, default selection, and the
`!not`, `!or`, `!and`, `!set`, `!quote`, and `!is` forms are supported. `break`
exits the `match`; `continue` targets an enclosing loop.

Runtime-built patterns may interpolate an interned `Match` operator in head
position and retain the literal operator's semantics. Source `match` arms
require literal operators so the compiler can prove binder availability. Named
binders under `!not` are not definitely assigned; binders under `!or` or
membership-style `!set` must occur in every alternative; `!quote` is opaque.
Arm binders are semantic `Var` or `List` locals and support method syntax.

`?(Type name)` declares a native typed capture. Its exact `Var` tag must
match the tag tested by `value is Type`; mismatches fail the pattern without
conversion. The type applies to every unquoted occurrence of that binder in
the arm, including `?name` and alternative branches. Repeated names retain
their equality constraint. The shorthand lowers to existing `!is` predicates
and ordinary local declarations; explicit `!is` captures remain `Var` locals.
The opener `?(` is adjacent; `? (String text)` is a wildcard followed by
a sublist pattern.

An arm may place `if (expression)` before its colon. The expression runs
after matching, with captures visible, and uses ordinary truth conversion.
False tries the next arm; errors propagate normally. A successful guard runs
the body once. Capture scopes and the existing `break`, `continue`, and
cleanup rules apply to guarded arms too.

### Errors and cleanup

`try` requires a following filtered `catch`, `finally`, or both.

`raise %(CODE (KEY VALUE)...);` records one structured `Error`. `CODE` and
every `KEY` are bare `Symbol`s read by this syntax; each `VALUE` is one
expression. Values are restricted recursively to `Null`/`nil`, numeric and enum
values, `Symbol`s, `Atom`s, `String`s, and `List`s of permitted values. `void`,
pointers, mutable containers, resources, custom objects, and other
identity-bearing values are invalid. Statically known violations are compiler
errors; invalid contents supplied dynamically through `Var` reach `Error`'s
`<bad-types>` raw floor. A `try` may have adjacent `catch` arms:

<!-- ignore: illustrative `Block` and reporting callbacks are omitted -->
```x2c,ignore
try block.reserve(n);
catch %(alloc-fail * (bytes ?count) *): return 0;
catch %(bad-arg *rest): report(rest);
catch: return -1;
```

The newest `Error` is matched as `%(CODE @DETAIL)`. Filtered arms use the same
pattern and binder rules as `match`; `?name` declares a `Var`, `*name`
declares a `List`, and the first matching arm runs. A bare `catch:` is the
optional default and must be last. Every filter expression is evaluated once
when the `try` is entered.

Selecting a filtered arm consumes the errors accumulated since that arm was
registered and transfers through each intervening cleanup frame. Its
`finally` and `defer` cleanup runs before the selected arm. The transferring
registration is removed before the arm executes, so raising a replacement
`Error` continues outward instead of re-entering the same arm. When no arm
matches, the `Error` continues outward unchanged. Catch bindings are borrowed
through the selected arm and must be copied with `Error.snapshot` to outlive
it.

Every cause in the shared table never returns to its raising call. `Error`
keeps their policies at `<abort>` and observing handlers cannot consume them;
only a matching filtered `catch` transfers control. For a literal `raise` of
one of them, generated C places `__builtin_unreachable()` after the runtime
`raise` call so C control flow has the same rule. [Errors and
Cleanup](../guide/exceptions.md) lists the table.

The `defer` statement schedules the statement for the current block exit.
Multiple `defer` statements unwind in last-in, first-out order. Cleanup runs
for normal scope exit, `return`, `goto`, and `Error` transfer, all the way out
to the function boundary. `break` and `continue` unwind cleanups only up to the
innermost enclosing loop or `switch` (whichever the jump targets) and stop
there; a `defer` or cleanup frame registered outside that boundary is left for
a later normal exit, `return`, or `Error` transfer to reach. The [errors and
cleanup](../guide/exceptions.md) chapter shows how the two are combined.

A `return` expression is evaluated and saved before its cleanups run; the
saved result is returned afterward. A `goto` within the same cleanup ancestry
runs no cleanup. An outward `goto` runs every cleanup region it exits. A
`goto` into a protected cleanup region, or into a sibling protected region,
is rejected at compile time.

Generated `Error` transfer preserves directly modified automatic locals and
parameters under the repository's optimized build. The compiler supplies the
required volatile C representation for those values and its cleanup guards;
source code does not need optimization-specific qualifiers for ordinary direct
assignments in `try`, `catch`, or `finally`. `Error` transfer does not
restore the process signal mask; code that changes a signal mask owns
restoring it.

### Type-owned initialization

A translation unit may define one top-level initializer with the exact
signature `void TYPE.initialize(void)`, where `TYPE` is a typedef name. The
compiler calls it lazily at every non-static function boundary and guards it so
direct or recursive calls still execute its body once. Static functions are
internal helpers. They trust a non-static entry point or the initializer that
called them and do not repeat the generated guard.

Compiler-owned literal and static-runtime initialization runs after the guard
is set and before the method body. This makes calls from the initializer back
into static helpers in the same translation unit safe. Translation units that
need only literal caching retain a private synthetic initializer.

Other initialization statements and runtime-valued static assignments belong in
the method body. Eligible file-static percent literals use the generated
sequence described under [Values and literals](#values-and-literals). Top-level
decorators are rejected.

### Type-owned shutdown

A translation unit may likewise define one top-level shutdown function with the
exact signature `void TYPE.shutdown(void)`. The compiler registers it once
through `Scope.shutdown_hook` when that unit initializes. When the unit also
defines `TYPE.initialize`, that guarded function registers it after its
complete generated initialization sequence; otherwise the unit's private
synthetic initializer registers it.

Shutdown hooks run in reverse registration order. A type initializer that
acquires process-lifetime resources therefore registers its matching shutdown
only after acquisition succeeds. Calling `TYPE.shutdown` directly still passes
through the unit's initialization guard.

## Types and conversions

x2c accepts normal C type forms plus runtime types such as `Var`, `List`,
`Array`, `Map`, `String`, `Symbol`, and `Iter`.

Typedef declarations are supported at file scope and inside compound
statements. Local aliases follow lexical scope and shadowing. Their uses are
resolved while that scope is available, preserving the existing meaning of
file-scope types, including their methods and converters. Local typedefs stay
inside their C blocks and are not exported. A locally defined aggregate also
stays in its block; it cannot supply a type to a lambda helper lifted outside
that block.

Direct and chained file-scope aliases of `Var` behave like `Var` in boxing,
extraction, initialization, assignment, function arguments, returns, and
comparisons. Declarations and signatures retain the source alias. This rule
is specific to `Var`; other file-scope typedefs gain only the methods and
converters declared by their own ancestry.

A typedef and the type it names may substitute for each other in either
direction. An `Array` can therefore be used as a `Block`, and an `Ast` as a
`List`, without conversion. Two typedefs of a common type cannot substitute for
each other this way: they may describe different contents despite sharing a C
representation. Thus `ArrayInt counts = someArrayDbl;` is a type error that
names the required converter. Declaring that converter, as `lib/typed-array.x`
does for `Array.arrayint`, permits the conversion; a cast still permits
reinterpretation.

Supported primitive C specifiers are order-independent and normalize to one
compiler spelling. For example, `double long` becomes `long double`, and
`long unsigned long` becomes `unsigned long long`. Invalid combinations such
as `long float` are structured type errors at the original source token.
Numeric literal radix, magnitude, and suffix determine the annotated native
family; integer promotions and the usual arithmetic conversions then operate
on that canonical identity. A literal beyond the supported native integer
families is a structured type error rather than a mismatched variadic value.

Conversions remain context-sensitive outside the numeric domain. A source
expression may be boxed to `Var`, converted through an established target
conversion, or rejected. Scalar typedefs retain their declared annotation but
use the underlying scalar family for arithmetic and conversion to or from
`Var`.

A converter is the source method named for its target: `Source.target` for a
plain target and `Source.str` for `String`. Lookup uses the source type's exact
converter when it declares one; otherwise it walks the source's typedef chain
and uses the nearest converter declaration. Thus a `typedef List Row` may be
assigned or interpolated as a `String` through `List.str` without a forwarding
`Row.str`. The generated call still names `List_str`, and direct C calls retain
the converter's declared ABI. Lookup stops without a call when the target
itself occurs in the chain, since typedef identity already handles that
crossing.

Type qualifiers take part in that decision. `const`, `volatile`, and
`restrict` are retained on the declared type of a function result, a global
object, a record field, and a local, including one imported from a C header.
Handing such a value to a target that is the same type without one of those
qualifiers is a structured type error, because that conversion passes the
same address on unchanged. A conversion that copies through a converter is
unaffected: `const char *` still becomes a `String` through `String_new`. A
qualifier on the value being copied, as opposed to what it points at, is not
part of the comparison, so `char *const` converts to `char *`.

A pointer to `void` is held to the same rule even though its base type differs
from the source's, because it also passes the same address on unchanged.
`void *` therefore does not accept a `const char *`; `const void *` does.

## Host preprocessing

When preprocessing is required, x2c passes the source pathname and every
include directory to the host `cc` as separate argv elements. Spaces and shell
metacharacters in paths are data, not command syntax. The host process receives
the source path, so quoted includes and its diagnostics retain source-file
context.

The active preprocessed stream is shallow-parsed only to establish the global
environment. Full parsing, diagnostics, and emitted source still come from the
original token stream. Directives remain AST nodes in source order at top level
and inside compound statements, including a trailing directive before `}`.

An include that x2c cannot resolve remains in the emitted C. Translation
without host preprocessing can therefore succeed with an active missing
header; native compilation rejects it. Explicit host preprocessing also
rejects an active missing header. A missing include in an inactive branch
such as `#if 0` does not prevent compilation.

This is not full preprocessing of x2c source: the original tokens must still
form syntax that x2c can parse. Macro expansion that supplies grammar, or
inactive branches containing otherwise unparseable source, can require
adjustment even when the host C compiler accepts them.

A failed host preprocess prints its captured stderr, reports a structured x2c
driver diagnostic at the first directive, and exits nonzero. Partial host
stdout is never parsed after failure. `--no-cpp` bypasses this discovery pass;
`--dump-cpp-text` exposes the successful host output.

## Diagnostics

Command-line options, including the dump flags that expose an individual
phase and the include and output directory switches, are listed in
[compiler options](cli.md).

By default a run records one ordinary error and then emits a `<limit>`
diagnostic. Locations retain `file`, one-based `line` and `column`, token
`length`, and absolute byte `position`. The source renderer uses `length` for
the caret width.
