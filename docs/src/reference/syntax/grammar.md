# Source grammar

The [EBNF file](x2c.ebnf) below describes x2c's source forms at the
[extraction revision](index.md). It consumes tokens after the
[lexical transformations](lexical.md). It is a descriptive grammar with
explicit contextual recognizers, not a ready-to-run parser-generator input.
The [language reference](../language.md) owns semantics and restrictions.

## Notation and entry points

`A = B ;` defines a production. `,` concatenates, `|` selects alternatives,
`[ ... ]` is optional, `{ ... }` repeats zero or more times, and parentheses
group. Single- or double-quoted strings denote terminal token spellings.
`(* ... *)` is a comment. `? description ?` is an external recognizer,
whose contract is stated below or in the lexical specification.

A quoted keyword can mean a token kind or a contextual identifier spelling.
For example, `is` is initially an identifier; `inline` includes normalized
GNU spellings. Productions do not accept a token of an incompatible mode
merely because its text matches a terminal. Trivia can separate code tokens
unless the lexical specification requires adjacent bytes for one token.

Alternatives are not a PEG priority list. The contextual rules below select
ambiguous alternatives before semantic checks. Repetition in the binary
expression ladder folds left; assignment and conditional tails recurse right.
The grammar permits some syntactic structures whose types or placement later
fail. It does not enumerate invalid programs by duplicating the type system.

The ordinary entry is `translation-unit`. `source-unit` also names script
input. After frontend shebang handling, a script with an explicit `main`
uses ordinary file scope. A script without `main` retains file-level
functions, types, imports, macros, and explicit static declarations, while
its executable block items become the implicit script body. This partition
uses `Compiler.script_statement_starts`, `_declaration_stays`, and
`defines_main` in `src/parse.x`; arbitrary interleaving is not permission to
refer to script locals from file-level functions.

## Declaration contracts

**D1: names and declaration starts.** `Compiler.test_declaration` uses
storage/type keywords, native prefix macros, typedef bindings, package
aliases, and template-hole kinds. A known non-typedef object name does not
start a declaration. An unknown identifier can start one when the following
token looks like a declarator. Thus the grammar does not assume a lexer token
named `TYPE_NAME`. Import aliases fold through the current symbol table;
local bindings can shadow them. An imported package string must decode to
an identifier, and each imported member must exist.

`identifier` normally consumes `ident`. Method/declarator name positions
also accept identifier-shaped keyword text when their parser explicitly
does so. `method-owner` is the owner recognized by
`Compiler._complex_identifier`: a built-in type word or known typedef,
including package-qualified type names. `Self` is resolved as a contextual
type. Type existence and a valid scalar combination remain semantic checks.
The scalar-word production does not include `_Bool`: the current parser
handles names outside that list through its named-type path.

**D2: declaration commas and parentheses.** In a declaration row, a comma
starts a new group only when `_group_comma` recognizes a declaration start
with a following declarator. Otherwise it joins declarators of the current
type. For example, `int i, T;` declares two integers, whereas
`int i, T value;` can introduce a new group. Within parentheses,
`_parameters_follow` distinguishes an abstract function declarator from a
parenthesized name using the current typedef environment.

A declarator can have no direct name: this represents an abstract declarator,
an unnamed bit-field, or a type-only declaration, as allowed by its context.
Function declarator parameter lists are nonempty: `(void)` is the no-argument
form. Calls and lambdas separately permit `()`. Array dimensions use an
expression; bit-field widths use a primary expression, which can be grouped.
A full `type-operand` can contain abstract declarators; `type-name` only
contains qualifiers, a specifier, and pointer/reference modifiers. These
are different entry points, notably in casts versus `_Generic` associations.

**D3: native declarations.** The storage parser permits one ordinary storage
class and one `threaded`, with `inline` and recognized attributes. `typedef`
has its own declaration path and cannot appear as trailing storage. Known
native macros can supply storage, qualifiers, types, annotation invocations,
or a wrapper around a type. Shallow C-header collection can ignore an unseen
prefix before a declaration keyword. `prefix-macro` names that existing
operation; it does not authorize arbitrary token expansion.

`attribute` retains the balanced source text of `__attribute__(...)` or a
known annotation macro. Placement follows `_attribute`, `_storage_class`,
and `_declarator_suffix`; tag attributes handled by `_skip_attributes` belong
to shallow imported-header collection. The EBNF shows their structural
positions, not a grammar for GNU attribute arguments. Native C still checks
the resulting declaration. Reference placement, bit-field legality, storage
compatibility, and initializer conversion are outside these productions.

Ordinary aggregate bodies enter the field parser even when the next token
is `}`; the grammar therefore requires a field item. Named-type record
bodies explicitly permit an empty body. A protocol definition's participant
is a binder; an adoption's participant is a type. Protocol members must be
single function declarations owned by that binder. Associated types precede
members; `as` and `tag` are mutually exclusive Var-adoption modifiers.

A leading `static` on a typedef, protocol, class, or top-level Lisp form
also controls source visibility. `meta native` applies to function
interfaces. See the reference for the public/private and compile-time rules.

## Expression contracts

**E1: casts, selectors, and braces.** A parenthesized declaration start
selects a cast; otherwise parentheses group an expression. At statement
start, named parameters in the parentheses select a typed destructuring
declaration; one anonymous parameter can instead be a cast.

`is [not]` shares relational precedence. Its right operand is a type when
`_is_type_selector_start` recognizes a declaration, `Void`, or an unbound
identifier; otherwise it parses one cast expression for the Symbol selector.
An explicit pointer type requires parentheses. Arrays and function types
are not accepted as direct `is` type selectors.

A brace in expression position is a Map when `_brace_starts_map` sees an
Entry macro or the first non-conditional colon before a top-level comma or
terminator. Otherwise it is an initializer. Consequently `{}` initially
parses as an empty composite; its destination can establish Map meaning.
The productions alone do not select `map` for every brace expression.

Immediately after `(`, a leading brace with a top-level semicolon selects
a statement expression. A template hole can also select it when there is
no top-level comma. Otherwise the brace remains data. Bare statements in
parentheses without braces do not form a statement expression.

**E2: precedence.** From lowest to highest:

| Level | Operators | Association |
| --- | --- | --- |
| Comma | `,` | Left |
| Assignment | `= += -= *= /= %= @= <<= >>= &= ^= \|=` | Right |
| Conditional | `? :` | Right |
| Binary 1 | `\|\|` | Left |
| Binary 2 | `&&` | Left |
| Binary 3 | `\|` | Left |
| Binary 4 | `^` | Left |
| Binary 5 | `&` | Left |
| Binary 6 | `== != === !==` | Left |
| Binary 7 | `< <= > >= in is` (`is not` included) | Left |
| Binary 8 | `<< >>` | Left |
| Binary 9 | `+ -` | Left |
| Binary 10 | `* / % @` | Left |
| Cast/unary | Cast, prefix update, address, dereference, sign, `~ ! sizeof` | Prefix nesting |
| Postfix | Call, index, slice, member selection, postfix update | Left |

`src/operator-ledger.x` owns the binary rows except the contextual `is`
handler in `src/expressions.x`. Assignment parses a conditional left side;
whether that side is assignable is a semantic question. An expression-bodied
function uses a full expression, while a lambda expression body uses an
assignment expression. Calls and literal element lists permit trailing commas.

**E3: special primaries.** `_Generic`, `va_arg`, and `offsetof` are recognized
by identifier spelling in `_parse_ident_primary`. Adjacent C strings join.
A following identifier joins that sequence when it names a recorded native
string macro or is unbound, except `in`; a bound runtime name does not.
This is the external `native-string-word` recognizer. The native compiler
owns the ultimate validity of those C macro spellings.

## Statement, directive, and pattern contracts

**G1: positions and directives.** A block accepts declarations and statements;
a governed position requires one statement. A macro expansion yielding
multiple block items must respect that difference. `parse_governed` retains
preprocessor groups while parsing one governed statement per applicable arm.
`src/preprocess.x` owns conditional selection; this grammar treats a retained
directive as one token, not an arbitrary statement or expression.

`else` belongs to the nearest eligible `if`. Match defaults and unfiltered
catches must be last in their applicable arm sequence. A label, `case`, or
`default` is a parsed row by itself. `do ... while (...)` does not consume
a semicolon; a conventional following `;` is an empty statement. This
matters when comparing parser consumption, even though emitted C uses its
required do-while punctuation. The statement parser also accepts a `%{`
token as a compound-statement opener; its contents still arrive from Map
lexical mode, so it is not a general substitute for a code-mode `{`.

**P1: patterns and error payloads.** A match pattern must reduce to a static
List pattern. Besides a List expression, a visible macro can supply a derived
pattern. Its arguments are `?`/`*` binders with optional identifiers, nested
macro patterns, or List patterns. `${$macro(...)}` embeds a derived pattern
inside a List; in an `(expr TYPE CONTENT)` pattern its position can request
only the content. Typed captures use `?(Type name)` and the type's Var tag.
`src/literals.x` and `src/macros.x` own these rules; `lib/match.x` and its
plan operations own pattern meaning, not source token recognition.

Raise and catch payloads have narrower rules than an arbitrary List.
Raise detail keys are bare exact Symbols; each detail contains one value.
Catch details are a `*`-prefixed pattern or `(key pattern)` pair. A pair's
value/pattern cannot be an outer splice, and a raise/catch code is required.
Cause and key Symbols must round-trip through the compact representation.
Template slots can produce the corresponding expression or argument rows;
they do not create a separate unchecked payload grammar.

## Literal and Lisp contracts

**L1: tokens versus bytes.** In data mode, bare `[`, `{`, and `"` emit the
same opener kinds as code `%[`, `%{`, and `%"`. The EBNF uses these normalized
kinds for nested data. Bare `(` remains the nested-list opener. List elements
are separated by token boundaries, not by C commas: a comma is a reader
prefix there. Array/Map entries use commas. Arrays and Maps accept value
insertion, while List `@` additionally splices. An inserted value expression
uses code mode. Literal meaning, caching, Symbol limits, and pattern binders
remain subject to the reference's rules.

A percent List containing just one reader-prefixed form returns that form
rather than adding another surrounding list. Quoted Map entries can contain
`${...}` with either a computed key followed by `:` or an Entry macro/slot.
A String interpolation uses `$name` or `${expression}`; the latter also
supports macro sequence handling where the template parser permits it.

`lisp-escape` records the contents inside `$(`, whose outer parentheses also
form the compile-time Lisp call/list. It is not a sequence of C expressions.
The ordinary Lisp reader supports lists, four reader prefixes, and atomic
values; it has no special dotted-pair production. Compiler templates add
hole capture before evaluation. The EBNF covers reading; it does not specify
Lisp evaluation, imports, or the available compile-time operations.

## Macro extension contracts

The macro mechanism makes a fixed enumeration of every source spelling
impossible. These contracts specify how visible definitions extend the
productions, without treating extension contents as unrestricted text.

**M1: arguments and positions.** Look up the macro or keyword alias in the
active compiler state, then parse each argument using its signature category.
An untyped hole initially reads an assignment expression. A final sequence
parameter repeats its category with commas; it can capture zero elements.
After a `Decl` argument, `in` may replace the separating comma, which is how
`foreach (T value in collection)` uses the ordinary macro parser.

| Hole kind | Argument recognizer |
| --- | --- |
| `Expr`, `Expression`, untyped | Assignment expression |
| `Type` | Type name |
| `NamedType` | Named-type declaration, including its semicolon |
| `Decl` | One non-function, non-typedef declaration; destructuring can omit its initializer |
| `DeclaratorRow` | One declarator with optional initializer; base type supplied at expansion |
| `Param` | Parameter declaration or ellipsis |
| `Name` | Identifier spelling |
| `Literal` | Atomic literal |
| `Stmt` | Block item |
| `Field` | Field item |
| `Entry` | Map entry |
| `Enumerator` | Enumerator |
| `MatchRow` | One match arm |
| `Unit` | Top-level item |
| `Function` | Function definition |
| `Catch`, `Captures` | Structured template sequence positions; not generic invocation arguments |

Result/argument kind spellings are case-insensitive; EBNF lists their usual
capitalization. `macro_categories` in `src/macros.x` is the complete table.
Expression, statement, field, entry, enumerator, unit, declaration, and
decorator results must be applied in compatible positions. Local macro values
and keyword aliases use their bound signatures too. `class` and `foreach`
are built-in aliases, whose definitions live in `etc/builtin-macros.x`.
The remaining built-ins and library macros need no new core productions.
A bare visible `$name` can also denote a Macro value without invoking it.
A direct non-decorator invocation consumes `;` in unit, block, statement,
and field positions. Enumerator and Entry invocations use their enclosing
comma list instead. Anonymous open arrow statements omit that terminator.

**M2: definitions and bodies.** A global definition uses a `$` name; a named
local definition omits `$`; an anonymous macro expression omits the name.
An Expression result, or expression-target Decorator, requires an arrow
expression body. A Stmt result uses a braced block-item template or an arrow
statement (a Stmt macro/decorator invocation or an expression statement). Other results use a braced category-specific sequence,
optionally preceded by `=>`. The arrow is two tokens. A named expression
body normally ends with `;`; an anonymous arrow body omits that terminator,
which belongs to the enclosing expression. The implementation also accepts
a legacy parenthesized expression body after the arrow without its own
semicolon when the next token cannot extend that expression. A following
semicolon selects the canonical form. See `_legacy_expression_body` and
`Definition.expression_body`.

A braced template can begin with `using` lines terminated by semicolons.
`using $name` declares fresh names; `using name` retains a file-level binding.
A signature can also have a `using` clause. Sequence parameters must be last.
Local definitions cannot produce Unit/Declaration results or decorate
Function/Unit/NamedType targets. These restrictions are enforced by
`Definition` in `src/macros.x`.

**M3: decorators.** The first signature parameter is the target; invocation
arguments supply the remaining parameters and the following source supplies
the target category. Targets can be Expr, Stmt, Field, Unit, Function, or
NamedType. An identifier alias omits parentheses when there are no ordinary arguments;
a `$` invocation still has its argument parentheses.
Unit/Function/NamedType decorators therefore extend file scope as well as
block/expression positions. In indentation syntax, leading `@` is a decorator line marker removed
before parsing. Brace-source decorators compose directly before their target.
A naked file-scope `@` is rejected. Target placement and alias shadowing
follow `try_parse_macro_target_at`, not arbitrary grammar substitution.

**M4: quotations.** `$!(expression)` quotes an expression; `$!{...}` quotes
block items. `$!Kind{...}` selects a result kind, Type, or Param. A typed
quotation `$!T{expression}` or `$!(type){expression}` uses a type operand;
the parenthesized form also accepts `$name` or `${expression}` carrying a
type. Category names take priority over an ordinary type spelling. The
quotation captures local `$name` references and braced value holes according
to `parse_macro_quotation`. Typed quotations have context and nesting
restrictions described in the reference.

**M5: slots and sequences.** Inside a template, `$name` inserts a declared
hole in a category-compatible position, and `$name...` splices a sequence.
`${expression}` and `$(...)` supply computed syntax in the applicable slot;
meta calls use the same binding operations. The parser selects the slot's
role (expression, type, name, parameter, declarator row, field, entry,
enumerator, match row, catch, captures, block, or unit) and whether a sequence
is permitted. In a meta call, a whole `$name` hole passes its captured value;
a whole sequence hole passes one List, rather than splicing call arguments.
Meta argument lists do not allow a trailing comma.
Call arguments, initializer elements, quoted Array elements,
and raise details also have argument-sequence positions. A sequence marker
is not permission to insert multiple statements where one statement is needed.

This is syntax construction over canonical Lists. Ordinary binder operations
accept structurally valid constructed forms without authenticating their
origin. The grammar must not be used to add origin tracking or to reject a
legal AST merely because it was built with Lisp rather than parsed text.

## Complete production inventory

The following is included directly from the standalone file. There is only
one copy of the production inventory.

```ebnf
{{#include x2c.ebnf}}
```

## Coverage and validation limits

The inventory covers declarations, types, expressions, statements, literals,
protocols, macro syntax, embedded Lisp reading, and script entry selection.
External recognizers name deliberate boundaries: native annotation contents,
dynamic macro signatures, context-sensitive names, slots, and static patterns.
The accompanying lexical specification covers raw source and layout spelling.

Source comparison, existing fixtures, and focused probes can establish
specific correspondences. They do not prove that this grammar and the
compiler accept exactly the same language. In particular, no independent
parser has yet consumed this EBNF over the entire repository corpus. Full
semantic validity, imported C dialects, and arbitrary compile-time evaluation
remain outside that claim.
