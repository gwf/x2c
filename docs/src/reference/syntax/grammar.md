# Source grammar

The [EBNF file](x2c.ebnf), generated from [ordinary List data](data.md),
describes x2c's current source forms. It consumes tokens after the [lexical
transformations](lexical.md). A parser generator cannot use it directly,
because some rules depend on context. The [language reference](../language.md)
defines semantics and restrictions.

## Notation and entry points

`A = B ;` defines a production. `,` concatenates, `|` selects alternatives,
`[ ... ]` is optional, `{ ... }` repeats zero or more times, and parentheses
group. Double-quoted strings denote terminal token spellings. Backslash
escapes a quotation mark, apostrophe, or backslash inside a terminal string.
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
`defines_main`, defined in `src/parse/units.x`. File-level functions cannot refer
to script locals.

Module blocks are expanded by `src/collect/collect.x` before `translation-unit`
parsing. `module-block` is spliced before parsing and is not a `unit-item`. It
contains quoted member paths, separated by commas, with an optional trailing
comma. Members are inserted in order from the containing file's companion
directory, `NAME/` beside `NAME.x`; each path must resolve inside it. Nested
module blocks are expanded too. Each file permits one file-scope block and
must use default symbol collection. CPP and live-symbol modes do not support
member splicing. The `module` storage class is described in D4.

## Declaration contracts

### D1. Names and declaration starts

`Compiler.test_declaration` uses storage/type keywords, native prefix macros,
typedef bindings, package aliases, and template-hole kinds. A known
non-typedef object name does not start a declaration. An unknown identifier
can start one when the following token looks like a declarator. Thus the
grammar does not assume a lexer token named `TYPE_NAME`. Import aliases fold
through the current symbol table; local bindings can shadow them. An imported
package string must decode to an identifier, and each imported member must
exist.

`identifier` normally consumes `ident`. Member selection, method names,
and declarator names also accept identifier-shaped keyword text where
their parser explicitly does so. In `macro-name`, the component after `$`
must be an `ident`; each component after a `.` may also be keyword text,
so `$a.if` and `$a.while.for` are macro names. `method-owner` is the owner recognized by
`_complex_identifier`: a built-in type word or known typedef,
including package-qualified type names. `Self` is resolved as a contextual
type. Type existence and a valid scalar combination remain semantic checks.
The scalar-word production does not include `_Bool`: the current parser
handles names outside that list through its named-type path.

After declaration `auto` and its qualifiers, a name followed by `=` selects
local type inference instead of a type reference. The inferred form requires
one plain initialized name. Otherwise `auto` prefixes an explicitly typed
declaration. An `auto` immediately after a declarator's `=` wraps the complete
initializer through `$auto`; it does not begin a general expression.
These managed forms require initialized block-item objects and cannot combine
declaration and initializer `auto` in one declaration group. See
[managed declarations and initializers](../language.md#managed-declarations-and-initializers).

A leading `auto` shares its storage class across the declarators in one
group. Prefer `auto Array left = [], right = [];` when both bindings keep
their acquired values. Retain initializer `auto` when a binding changes or
only part of the group needs cleanup.

### D2. Declaration commas and parentheses

In a declaration row, a comma starts a new group only when `_group_comma`
recognizes a declaration start with a following declarator. Otherwise it joins
declarators of the current type. For example, `int i, T;` declares two
integers, whereas `int i, T value;` can introduce a new group. Within
parentheses, `_parameters_follow` distinguishes an abstract function
declarator from a parenthesized name using the current typedef environment.

A declarator can have no direct name: this represents an abstract declarator,
an unnamed bit-field, or a type-only declaration, as allowed by its context.
Function declarator parameter lists are nonempty: `(void)` is the no-argument
form. Calls and lambdas separately permit `()`. Array dimensions use an
expression; bit-field widths use a primary expression, which can be grouped.
A full `type-operand` can contain abstract declarators; `type-name` only
contains qualifiers, a specifier, and pointer/reference modifiers. These
are different entry points, notably in casts versus `_Generic` associations.

### D3. Native declarations

The storage parser permits one ordinary storage class and one `threaded`, with
`inline` and recognized attributes. `typedef` has its own declaration path and
cannot appear as trailing storage. Known native macros can supply storage,
qualifiers, types, annotation invocations, or a wrapper around a type. Shallow
C-header collection can ignore an unseen prefix before a declaration keyword.
`prefix-macro` stands for that operation. It accepts only recorded native
macros.

`attribute` retains the balanced source text of `__attribute__(...)` or a
known annotation macro. Placement follows `_attribute`, `_storage_class`, and
`_declarator_suffix`; tag attributes handled by `_skip_attributes` belong to
shallow imported-header collection. The EBNF shows their structural positions,
not a grammar for GNU attribute arguments. Reference placement, bit-field
legality, storage compatibility, and initializer conversion are outside these
productions.

Ordinary aggregate bodies enter the field parser even when the next token
is `}`; the grammar therefore requires a field item. Named-type record
bodies explicitly permit an empty body. A protocol definition's participant
is a binder; an adoption's participant is a type. Protocol members must be
single function declarations owned by that binder. Associated types precede
members; `as` and `tag` are mutually exclusive Var-adoption modifiers.

### D4. Interface modifiers

`private-interface` is the top-level visibility dispatch before declaration
parsing. A leading `static` on a typedef, protocol body, or class also controls
source visibility. `meta native` applies to function interfaces. Protocol
adoptions permit `meta` followed by optional `static`, or `static` alone;
protocol bodies reject `meta`. A file-scope `module-declaration` is the word
`module` followed by an identifier, a type keyword, a qualifier, `inline`, or
`typedef`. It parses as the same declaration with `static` in place of
`module`. See the reference for the public/private and compile-time rules. A
visible binding named `module` disables the `module-declaration` form.

## Expression contracts

### E1. Casts, selectors, and braces

A parenthesized declaration start selects a cast only when the token after `)`
can start its operand. `_cast_operand_follows` recognizes primary starts,
`sizeof`, prefix update, and unary operators. Otherwise parentheses resume a
grouped expression. At statement start, named parameters in the parentheses
select a typed destructuring declaration; one anonymous parameter can instead
be a cast.

After `sizeof`, a parenthesized declaration start is a type operand that ends
at its `)`, unless `{` follows the `)`. Then the operand is a compound
literal with its postfix continuation: `sizeof (int[]){1, 2, 3}` measures the
array, and `sizeof (P){1, 2}.y` measures the member. Any other operand is a
`unary` expression, so a parenthesized expression keeps its postfix
continuation: `sizeof(a)[0]` measures an element.

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

### E2. Precedence

From lowest to highest:

| Level | Operators | Association |
| --- | --- | --- |
| Comma | `,` | Left |
| Assignment | `= += -= *= /= %= <<= >>= &= ^= \|=` | Right |
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
| Binary 10 | `* / %` | Left |
| Cast/unary | Cast, prefix update, address, dereference, sign, `~ ! sizeof` | Prefix nesting |
| Postfix | Call, index, slice, member selection, postfix update | Left |

`src/operator-ledger.x` defines the binary rows except the contextual `is`
handler in `src/expressions/expressions.x`. Assignment parses a conditional left side;
whether that side is assignable is a semantic question. An expression-bodied
function uses a full expression, while a lambda expression body uses an
assignment expression. Calls and literal element lists permit a trailing
comma. Meta calls such as `$name(a, b,)` and macro invocations reject it.

| Form | Operand or target |
| --- | --- |
| `in` | Shift expression at relational precedence |
| `is [not]` | Contextual type selector or one cast expression |
| Lambda `=>` body | Assignment expression, or raw braced block |
| Function `=>` body | Full comma expression |
| Expression macro body | Full comma expression |
| Expression decorator target | One cast expression |

### E3. Special primaries

`_Generic`, `va_arg`, and `offsetof` are recognized
by identifier spelling in `_parse_ident_primary`. Adjacent C strings join.
A following identifier joins that sequence when it is a recorded native
string macro or is unbound, except `in`; a bound runtime name does not.
This is the external `native-string-word` recognizer.

## Statement, directive, and pattern contracts

### G1. Positions and directives

At statement start, `auto` introduces a cleanup region before a block,
`if`, `while`, `for`, `do`, `switch`, `match`, `try`, `return`, `raise`,
`defer`, `break`, `continue`, `goto`, `foreach`, or `with`. Before a typed
function definition, it wraps the body, including an expression body.
`auto (destination)` supplies an explicit Scope destination and takes a
statement or function target. The destination is required between the
parentheses: `auto()` is not a form. These native prefixes use ordinary
statement-decorator expansion; declaration and initializer `auto` retain
the managed-object meanings in D1.

A block accepts declarations and statements;
a governed position requires one statement. A macro expansion yielding
multiple block items must respect that difference. `parse_governed` retains
preprocessor groups while parsing one governed statement per applicable arm.
`src/preprocess.x` selects conditional groups; this grammar treats a retained
directive as one token.

`else` belongs to the nearest eligible `if`. Match defaults and unfiltered
catches must be last in their applicable arm sequence. A label, `case`, or
`default` is a parsed row by itself. `do ... while (...)` does not consume a
semicolon; a conventional following `;` is an empty statement. This matters
when comparing parser consumption, even though emitted C uses its required
do-while punctuation. `case` consumes a full expression, including a comma
expression, but not a GNU `...` range. The statement parser also accepts a
`%{` token as a compound-statement opener; its contents still arrive from Map
lexical mode, so it is not a general substitute for a code-mode `{`.

### P1. Patterns and error payloads

A match pattern yields a List pattern, which can be static or supplied at
runtime. Besides a List expression, a visible macro can supply a derived
pattern. Its arguments are `?`/`*` binders with optional identifiers, nested
macro patterns, or List patterns. `${$macro(...)}` embeds a derived pattern
inside a List; in an `(expr TYPE CONTENT)` pattern its position can request
only the content. Typed captures use `?(Type name)` and the type's Var tag.
`src/literals/literals.x` and `src/macros/macros.x` implement these rules. `lib/match/match.x`
defines what a pattern means.

Raise and catch payloads have narrower rules than an arbitrary List.
Raise detail keys are bare exact Symbols; each detail contains one value.
Catch details are a `*`-prefixed pattern or `(key pattern)` pair. A pair's
value/pattern cannot be an outer splice, and a raise/catch code is required.
A catch code may instead be a nested List pattern such as `(!or io eof)`.
Raise causes and bare catch causes and detail keys must round-trip through
the compact Symbol representation.
Template slots can produce the corresponding expression or argument rows;
they do not create a separate unchecked payload grammar.

## Literal and Lisp contracts

### L1. Tokens versus bytes

In data mode, bare `[`, `{`, and `"` emit the same opener kinds as code `%[`,
`%{`, and `%"`. The EBNF uses these normalized kinds for nested data. Bare `(`
remains the nested-list opener. List elements are separated by token
boundaries. A comma there is a reader prefix. Array/Map entries use commas.
Arrays and Maps accept value insertion, while List `@` additionally splices.
An inserted value expression uses code mode. Literal meaning, caching, Symbol
limits, and pattern binders remain subject to the reference's rules.

A percent List containing just one reader-prefixed form returns that form
rather than adding another surrounding list. Quoted Map entries can contain
`${...}` with either a computed key followed by `:` or an Entry macro/slot.
A String interpolation uses `$name` or `${expression}`; the latter also
supports macro sequence handling where the template parser permits it.

Code has no compile-time Lisp production. A `$(` or `@(` form in code is
reported where it is written as `compile-time Lisp forms are not supported`.
The runtime Lisp reader supports lists, four reader prefixes, and atomic
values; it has no special dotted-pair production. The EBNF covers reading; it
does not specify Lisp evaluation.

## Macro extension contracts

The macro mechanism makes a fixed enumeration of every source spelling
impossible. These contracts specify how visible definitions extend the
productions, without treating extension contents as unrestricted text.

### M1. Arguments and positions

Global macro definition names and keyword
alias targets require `$`; `@` cannot replace that prefix. Dotted macro
names permit keyword-shaped components after the first component, such as
`$error.arg.void`. A scalar macro expression uses `$name(...)`, a local
macro name, or a keyword alias; `@name(...)` is not a scalar expression.

Look up the macro or keyword alias in the
active compiler state, then parse each argument using its signature category.
Invocation arguments reject a trailing comma. The first `Param` argument
opens one scope shared by the remaining arguments.
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
capitalization. `macro_categories` in `src/macros/macros.x` is the complete table.
Expression, statement, field, entry, enumerator, unit, declaration, and
decorator results must be applied in compatible positions. Local macro values
and keyword aliases use their bound signatures too. `class` and `foreach`
are built-in aliases, whose definitions live in `etc/compiler-prelude.x`.
The remaining built-ins and library macros need no new core productions.
A bare visible `$name` can also denote a Macro value without invoking it.
A direct non-decorator invocation consumes `;` in unit, block, statement,
and field positions. Enumerator and Entry invocations use their enclosing
comma list instead. Anonymous open arrow statements omit that terminator.

### M2. Definitions and bodies

A global definition uses a `$` name; a named local definition omits `$`; an
anonymous macro expression omits the name. An Expression result, or
expression-target Decorator, requires an arrow expression body. A Stmt result
uses a braced block-item template or an arrow statement (a Stmt
macro/decorator invocation or an expression statement). Other results use a
braced category-specific sequence, optionally preceded by `=>`.  A named
expression body normally ends with `;`; an anonymous arrow body omits that
terminator, which belongs to the enclosing expression. The implementation also
accepts a legacy parenthesized expression body after the arrow without its own
semicolon when the next token cannot extend that expression. A following
semicolon selects the canonical form. See `_legacy_expression_body` and
`_expression_body`.

A braced template can begin with `using` lines terminated by semicolons.
`using $name` declares fresh names; `using name` retains a file-level binding.
`body-using` describes those leading lines.
A signature can also have a `using` clause. Sequence parameters must be last.
Local definitions cannot produce Unit/Declaration results or decorate
Function/Unit/NamedType targets. These restrictions are enforced by
`Definition` in `src/macros/macros.x`.

### M3. Decorators

The first signature parameter is the target; invocation arguments supply the
remaining parameters and the following source supplies the target category.
Targets can be Expr, Stmt, Field, Unit, Function, or NamedType. An identifier
alias omits parentheses when there are no ordinary arguments; a `$` invocation
still has its argument parentheses. Unit/Function/NamedType decorators
therefore extend file scope as well as block/expression positions. Indentation
syntax removes the leading `@` of `@$decorator(...)` before parsing; see the
[lexical specification](lexical.md). Brace-source decorators compose directly
before their target. A decorator invocation consumes its following target and
must not end with a semicolon. At file scope, a `Stmt` decorator applied to a
function definition captures and decorates the function body. This adaptation
does not permit arbitrary Unit targets for `Stmt` decorators. A naked
file-scope `@` is rejected. Target placement and alias shadowing follow
`try_parse_macro_target_at`, .

### M4. Quotations

`$!(expression)` quotes an expression; `$!{...}` quotes
block items. `$!Kind{...}` selects a result kind, Type, or Param. A typed
quotation `$!T{expression}` or `$!(type){expression}` uses a type operand;
the parenthesized form also accepts `$name` or `${expression}` carrying a
type. Category names take priority over an ordinary type spelling. The
quotation captures local `$name` references and braced value holes according
to `parse_macro_quotation`. Typed quotations have context and nesting
restrictions described in the reference.

### M5. Slots and sequences

Inside a template, `$name` inserts a declared hole in a category-compatible
position, and `@name` splices a sequence. `${expression}` and `$producer(...)`
meta calls supply computed syntax in the applicable slot. `@producer(...)` can
supply sequences in positions that accept a sequence slot. Shared invocation
lookup recognizing `@` does not permit scalar `@` calls or `@` definition
names. The parser selects the slot's role (expression, type, name, parameter,
declarator row, field, entry, enumerator, match row, catch, captures, block, or
unit) and whether a sequence is permitted. In a meta call, a whole `$name` hole
passes its captured value; a whole sequence hole passes one List, rather than
splicing call arguments.

Lambda templates accept `&$name` capture rows as well as one Captures slot.
Quoted Arrays accept `${@sequence}` in an argument-sequence position. Quoted
Maps accept a bare Entry slot or a slot inside `${...}`. These slots require a
compatible template context. Call arguments, initializer elements, quoted
Array elements, and raise details also have argument-sequence positions. A
sequence slot cannot supply several statements where one statement is
required.



## Complete production inventory

The following is included directly from the standalone file.

```ebnf
{{#include x2c.ebnf}}
```

## Coverage and validation limits

The inventory covers declarations, types, expressions, statements, literals,
protocols, macro syntax, runtime Lisp reading, and script entry selection.
External recognizers cover: native annotation contents, dynamic macro
signatures, context-sensitive names, slots, and pattern recognition. The
accompanying lexical specification covers raw source and layout spelling.

Source comparison, existing fixtures, and focused probes can establish
specific correspondences. They do not prove that this grammar and the compiler
accept exactly the same language. In particular, no independent parser has
consumed this EBNF over the entire repository corpus. Full semantic validity,
imported C dialects, and arbitrary compile-time evaluation remain outside that
claim.
