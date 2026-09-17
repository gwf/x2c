# x2c Source Style Guide

x2c's compiler and runtime are examples of the language as well as its
implementation. Source should be compact enough to scan, explicit enough to
verify, and unsurprising enough that a reader notices the algorithm rather
than the formatting.

This guide governs hand-authored `.x` files in `src/` and `lib/`. Correctness
and the ownership rules in `agents/x2c-philosophy.md` come first. A local
representation or ABI constraint may require an exception; explain that
constraint beside the exception instead of weakening the general rule.

Examples in this guide are illustrative fragments unless introduced as
complete programs. They endorse the illustrated property, not every detail of
the invented code.

## The governing test

Code should say what happens. Comments should say what cannot be recovered
from the code: why this owner exists, which invariant is relied upon, where a
lifetime ends, or why a tempting alternative is wrong.

Prefer:

```x2c
// The artifact may be absent, but a present directory is not a readable
// source file and must fail before its declarations are cached.
if (!_includable_file(path))
  c.report_error(<input>, "unreadable include", token, %($path));
```

Avoid:

```x2c
// Check if the path is a regular file.
if (!_regular_file(path))
  // Report an error.
  c.report_error(<input>, "unreadable include", token, %($path));
```

The preferred comment changes how the reader interprets the branch. The
avoided comments merely translate the code into English.

## Delete before rearranging

A cleanup starts by asking what current x2c syntax, library behavior, or
existing owner makes a wrapper, route, check, protocol, alias, or
representation unnecessary. Formatting a redundant path leaves the redundancy
in place. [The bloat test](x2c-philosophy.md#the-bloat-test) describes what a
deletion must preserve and how to measure its result.

## Prose

Write comments, guides, plans, diagnostics, and commit messages as literal
statements. Put the fact first and give the owner, constraint, action, or
consequence. Leave out metaphors, preambles such as "it is important to
note", persuasion such as "clearly" or "simply", and praise such as "robust".
Give agency only to actors: a type, table, or check does not "name", "know",
or "refuse" anything. Avoid negative-then-reversal constructions, "rather
than" and ", not X" closers, and the words "deliberately", "honest", and "on
purpose".
[`audit-source.sh`](skills/clean-x2c-source/scripts/audit-source.sh) reports
common stock phrases in a source file as prohibited prose candidates.

Write the language name `x2c`: lowercase `x`, digit `2`, lowercase `c`.
Speech-to-text may replace it with the word it sounds like; correct that
spelling wherever it appears.

## Each file has one subject

### Module headers

Begin with the filename, a short purpose phrase, the existing copyright
notice when the file carries one, and normally one compact ownership
paragraph.

Prefer:

```x2c
/*  deps.x -- Make dependency output for x2c translation units

    Copyright (c) 2026 Gary William Flake.

    Translation owns the prerequisite set. This module owns its stable Make
    spelling and atomic publication.
*/
```

Avoid:

```x2c
/*  deps.x -- dependency helpers

    This module contains all of the dependency functions. It parses
    dependency files, writes dependency files, escapes paths, sorts paths,
    creates temporary files, renames them, and handles errors. The functions
    below are:

      translation_depfile_write
      translation_depfile_parse
      ...
*/
```

A header answers:

- What concept does this module own?
- Which representation, phase, lifetime, or compatibility boundary would a
  reader otherwise miss?

A header does not contain:

- a function or feature catalog;
- a tutorial for the public API;
- change history or implementation chronology;
- details that belong beside one declaration or table;
- a second copy of a contract already owned by the book or philosophy.

A second paragraph is justified when it states a separate constraint needed
for correctness. Length is not the rule, but a header that grows past two
short paragraphs should be split. Put an encoding diagram beside the encoding
table, a grammar beside its parser, and user-facing syntax in `docs/`.

### Prologue order

Keep the reader's path stable:

```x2c
/*  widget.x -- checked widgets over Block storage

    Copyright (c) 2026 Gary William Flake.

    Widget owns element validation; Block owns capacity and allocation.
*/

#pragma once
#include "common.x"

typedef Block Widget;

#pragma private

#include <limits.h>
#include <string.h>

#include "block.x"
#include "exception.x"
```

The order is:

1. module header;
2. `#pragma once`, in a compiler or runtime module only;
3. dependencies needed by public declarations;
4. public types;
5. `#pragma private`;
6. private system and repository dependencies;
7. private representation, state, helpers, and definitions.

An include may move earlier when a public declaration needs it. Do not move a
declaration across `#pragma private` merely to make the include list look
tidy; visibility is a contract, while alphabetical order is not.

`widget.x` above is a runtime module, so it carries `#pragma once`. A test,
example, package, or program starts at step 3; see
`agents/x2c-code-organization-guide.md` for why.

### Top-level order

Order a module for a reader, not for the compiler:

1. representation and owner state;
2. small private foundations;
3. operations grouped by concept;
4. lifecycle or public entry points at the natural boundary.

Keep a private helper near the operations it supports when moving it to a
global "private helpers" block would make the reader jump around.

Prefer:

```x2c
// slice normalization

static int _normalize_bound(int length, int *bound) {
  // ...
}

Array Array.getslice(Array a, int start, int stop, int step) {
  // ...
}
```

Avoid a table of contents made from comments:

```x2c
// PRIVATE HELPERS ===========================================================
// PUBLIC INTERFACE ---------------------------------------------------------
// ARRAY METHODS ============================================================
// SLICE METHODS ============================================================
```

Use a plain, lower-case section label only when it makes a real transition in
a long file:

```x2c
// immutable programs
```

Do not decorate labels with repeated hyphens, equals signs, or multiple
capitalization schemes.

### Vertical space

Whitespace carries hierarchy:

- no blank line between a `//` or `/**` comment and what it explains;
- a multi-line plain block comment may have one blank line above and below
  when that makes the surrounding code easier to scan;
- one blank line between peer declarations or short definitions;
- one blank line after a section label;
- no consecutive or decorative stacks of empty lines.

Prefer:

```x2c
static int _is_digit(int ch) => ch >= '0' && ch <= '9';

static int _is_hex(int ch) =>
  _is_digit(ch) || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F');

// public scanning

int scan_number(char *text) {
  // ...
}
```

Avoid:

```x2c
static int _is_digit(int ch) => ch >= '0' && ch <= '9';



// PUBLIC SCANNING ----------------------------------------------------------


int scan_number(char *text) {
  // ...
}
```

## Comments earn their space

### Choose the narrowest comment form

Use each delimiter for one purpose:

- `/* ... */` for the module header, a multi-line contract, or a diagram;
- `/** ... */` for public library prose and the compiler's provisional public
  API, consumed by the generated reference;
- `// ...` for a short local reason, section label, or dense table annotation;
- trailing `//` only when a short label makes a row easier to compare.

A multi-line plain block may keep the closing delimiter tight:

```x2c
/* Symbol values are encodings, not lexical ordinals. Keep this table in
   encoded order because lookup uses a lower bound. */
static VarDescriptor descriptors[] = {
  // ...
};
```

Or put the delimiter on its own line:

```x2c
/* Symbol values are encodings, not lexical ordinals. Keep this table in
   encoded order because lookup uses a lower bound.
*/
static VarDescriptor descriptors[] = {
  // ...
};
```

Either form is correct. A plain block may also have one blank line on each
side when the space makes its scope clearer:

```x2c
scan_prefix(input);

/* The suffix scanner starts after the delimiter but reports lengths from the
   original input boundary. */

scan_suffix(input, delimiter_length);
```

Do not add more than one blank line on either side.

Avoid stretching one thought across many consecutive line comments:

```x2c
// Symbol values are encodings.
// They are not lexical ordinals.
// This table is in encoded order.
// Lookup uses a lower bound.
static VarDescriptor descriptors[] = {
  // ...
};
```

### Public API documentation

[`docs/AGENTS.md`](../docs/AGENTS.md#the-generated-api-reference) describes
which declarations carry a `/** ... */` comment and how the generator reads
it. The first sentence becomes the reference index summary and must
stand alone. Keep a doc comment on one physical line when its complete text
fits there; otherwise put `*/` on its own line.

A trivial callable normally gets one line:

```x2c
/** Returns the number of elements. */
size_t Array.len(Array a) => Block.len(a);
```

Add prose only for behavior the signature does not carry:

```x2c
/** Removes and returns the element at `index`, or `void` when out of range.
    Negative indexes count from the end. On failure, the Array is unchanged.
*/
Var Array.del(Array a, int index) {
  // ...
}
```

Avoid:

```x2c
/** Deletes an element from an Array.

    Parameters:
    - a: the Array
    - index: the index

    Returns: the deleted element.
    Raises: nothing.
    See: Array.
*/
Var Array.del(Array a, int index) {
  // ...
}
```

Document observable facts such as result or output-parameter behavior,
mutation, identity, ownership, borrowing, lifetime, required cleanup, callback
invocation and retention, ordering, laziness, token consumption, sentinels,
state changes, failure atomicity, complexity when surprising, and real raised
causes. Compiler methods also state required token, AST, or type shapes and
relevant `Compiler`, `Sym`, transaction, or phase state when the declaration
does not make them clear. Public type comments state the type's purpose, valid
state, ownership, and callback rules when applicable. Field-level
implementation details remain ordinary comments.

Do not repeat parameter names, types, module membership, or empty metadata.
Do not infer guarantees from a name alone. Shared invariants belong in the
module header, not on every method.

### Internal functions and contracts

An obvious helper needs no prose:

Prefer:

```x2c
static int _ascii_digit(int ch) => (unsigned) (ch - '0') < 10;
```

Avoid:

```x2c
// Check if a character is a digit.
static int _ascii_digit(int ch) => (unsigned) (ch - '0') < 10;
```

Comment a function when the contract is narrower or stranger than its name
and signature:

```x2c
/* Return a spelling only when the operand is provably nonzero without
   constant folding. Unknown forms stay silent so legal C is never rejected. */
static String _known_nonzero_integer(List expression) {
  // ...
}
```

The useful comment gives the proof boundary and the consequence of
uncertainty. "Find a nonzero integer" would not.

Use plain `/* ... */` beside the code that owns internal knowledge a compiler
developer cannot recover locally: representation invariants, phase
responsibility, producer guarantees, cache identity, transaction rollback,
lifetime, ordering, or why a plausible alternative is invalid. This applies
to static helpers and to non-static names excluded from the provisional API.
It is not a quota for private functions; obvious helpers still need no prose.

### Local comments explain decisions

Place a local comment immediately before the decision it qualifies. State the
current reason and consequence.

Prefer:

```x2c
// The selected arm's captures are copied out, so the pattern pool can go.
_catch_commit_captures(h, record, layout, &captures);
List.pool_release();
_catch_retain(h);
```

Avoid:

```x2c
// Commit captures.
_catch_commit_captures(h, record, layout, &captures);

// Release list pool.
List.pool_release();

// Retain the handler.
_catch_retain(h);
```

For a branch, explain why the case differs:

```x2c
if (!source.len()) {
  // Empty String is native zero; scanning still needs one addressable byte.
  tokenizer.text = Scope.calloc(1, 1);
}
```

Do not narrate the branch:

```x2c
if (!source.len()) {
  // Allocate one byte.
  tokenizer.text = Scope.calloc(1, 1);
}
```

### Comments describe the present

Use direct present-tense claims.

Prefer:

```x2c
// Shallow macro collection retains public declarations but discards private
// helpers with the generated bodies.
```

Avoid:

```x2c
// NB: Added this third clause after macros broke the old logic.
```

Do not leave:

- `TODO`, `FIXME`, or `BUG` as a substitute for a plan or issue;
- "moved verbatim", "recently added", or other version-control history;
- "optimized", "important", or "special case" without saying what is
  optimized, important, or special;
- stale file-and-line references;
- first-person narration when the owner can be named.

If unfinished work must remain visible, put it in `plans/`. If a source
constraint remains, state the constraint as a current fact.

Prefer:

```x2c
// The checked-in bootstrap does not accept this declaration form.
```

Avoid:

```x2c
// TODO: clean this up later.
```

### Inline and field comments

Use trailing comments for short, parallel annotations in a dense
representation:

```x2c
struct Iter {
  Var obj;
  Var state;
  IterNextFn next;  // NULL once the source is exhausted
  Func aux;         // callback state for lazy stages
};
```

Do not annotate what the field already says:

```x2c
struct Token {
  String text;  // token text
  Symbol type;  // token type
  int line;     // line number
};
```

Move a long field contract above the related fields or type. Do not build a
paragraph in the right margin.

Keep comment-bearing fields vertical when their comments are part of the
explanation. Do not combine them merely to shorten the struct.

## Layout is quiet and mechanical

### Indentation, width, and text

- indent with 2 spaces, never tabs;
- keep hand-authored code and prose within 79 columns;
- leave no trailing whitespace;
- keep repository source ASCII;
- use spaces around binary operators and after commas;
- do not add spaces just inside parentheses or brackets.

Prefer:

```x2c
if (index < 0)
  index += length;
return index >= 0 && index < length;
```

Avoid:

```x2c
if(index<0)
    index+=length;
return ( index>=0&&index<length );
```

An indivisible diagnostic or generated spelling may exceed 79 columns when
splitting it would change observable text. A stable initializer-table row may
also exceed 79 columns when indivisible literal fields cause the excess and
wrapping would split the row's visible structure. These are narrow exceptions,
not reasons to let surrounding code drift right. Keep surrounding punctuation
and non-literal expressions compact, and review each exception directly.

Treat 79 columns, including the current indentation, as usable horizontal
space rather than a signal to wrap early. Before splitting a construct, try
its complete horizontal form. A short signature, call, declaration group,
expression, condition and body should normally stay on one line when the
result is still under 80 columns and reads in one pass.

Vertical layout marks real structure: a long or nested expression, semantic
argument groups, a step that can fail, or a statement that needs its own
comment. Do not spend lines merely to make a short construct look prominent.

### Signatures and calls

Keep a signature or call on one line when it fits at its actual indentation.
When it does not, end the opening line after `(` and begin all parameters or
arguments on the next line with a two-space continuation. Do not align them to
a distant opening parenthesis. Keep the close and its `{`, `=>`, or `;`
trailer with the final parameter or argument when each occupies one physical
line. The close may stand alone only when an individual parameter or argument
spans more than one line.

Prefer:

```x2c
static int _same_slot(Map m, Var key, Var expected) =>
  m.lookup(key).same(expected);

static int MatchLower._compile_bind_and_leaf(
  MatchLower m, Var binder, Var leaf) {
  // ...
}
```

Use an expression body when the complete function is one clear valued return.
Keep braces when the body needs declarations, control flow, several
statements, or an interior comment. Wrap a long expression after `=>` with a
two-space continuation; its terminating semicolon stays with the expression.

Avoid:

```x2c
static int MatchLower._compile_bind_and_leaf(MatchLower m,
                                             Var binder,
                                             Var leaf) {
  // ...
}
```

Wrap calls by semantic groups:

```x2c
c.report_error(
  <protocol>, message, declaration_token,
  %("participant:" $participant "member:" $member));
```

Do not align continuations to an opening parenthesis, where the indentation
depends on a renamed callee:

```x2c
c.report_error(<protocol>, message, declaration_token,
               %("participant:" $participant
                 "member:" $member));
```

When an argument is itself multiline, a standalone close exposes that nesting:

```x2c
c.report_error(
  <protocol>, message,
  %(
    "participant:" $participant
    "member:" $member
  )
);
```

### Control flow

Use braces for a body with more than one statement. Omit them for a single
statement. Put `else` on its own line; never write `} else`.

```x2c
if (!node) return NULL;

if (node is List)
  visit(node.list());
else if (node is Array) {
  Array values = node.array();
  visit_all(values);
}
else
  visit_leaf(node);
```

Spell a negative type test with `is not`. Do not wrap a positive `is` test in
logical negation:

```x2c
if (value is not <list>) return 0;
```

Avoid:

```x2c
if (!(value is <list>)) return 0;
```

A short single-statement `if`, `else`, or loop should stay on one line when
the complete construct fits and reads as one action. Guards are the most common
case, but ordinary local updates and compact traversal bodies use the same
rule:

```x2c
if (!out) return 0;
if (head is List) normalized_head = _normalize_pattern(head);
foreach(Var part, parts) if (!_collect(part)) return 0;
```

Use the next line when either half is long, the action needs emphasis, or a
comment belongs between the condition and body:

```x2c
if (c.peek() == <eof>)
  c.report_error(<parse>, "unexpected end of input", token, NULL);
```

Avoid braces that visually outweigh the work:

```x2c
if (!out) {
  return 0;
}
```

Compact a short sequence when its parts form one obvious mechanical action.
A swap is easier to recognize as one line:

Prefer:

```x2c
int swap = left; left = right; right = swap;
```

Avoid:

```x2c
int swap = left;
left = right;
right = swap;
```

Keep statements on separate lines when any step branches, can fail, deserves
its own comment, or is not recognizable as part of the same compact idiom.

Pack consecutive `(void) identifier;` statements onto as few lines as fit
under 80 columns:

```x2c
(void) map; (void) source;
```

Apply this only to plain identifiers. Keep a statement separate when it has
its own comment; calls and other expressions may have behavior and are not
this idiom.

### Declarations

Declare a value in the narrowest scope that owns it and initialize it when
the value becomes meaningful.

Prefer:

```x2c
List result = c.parse_expression();
if (!result) return NULL;

Type type = result.cadr();
return c.convert_expression(result, type);
```

Avoid speculative declarations at the top:

```x2c
List result;
Type type;

result = c.parse_expression();
if (!result) return NULL;
type = result.cadr();
return c.convert_expression(result, type);
```

Combine consecutive declarations into one row when the complete row stays
under 80 columns, including indentation. Use this throughout hand-authored
source for file-scope globals, block locals, and struct or union fields. A row
may restart its type and may mix declarators with and without initializers;
preserve source order.

```x2c
static size_t pool_allocation_calls, pool_free_calls;

struct Token {
  String text, Symbol type, int line, column;
};

String source_path, List dependencies, int failed = 0;
```

Keep declarations separate when one needs its own comment, they belong to
different scopes, an initializer needs an intervening check or cleanup,
combining them would obscure evaluation or failure order, or a function
pointer or other complex declarator would make the row hard to read. Never
move declarations across an executable statement merely to form a row.

```x2c
List result = c.parse_expression();
if (!result) return NULL;
Type type = result.cadr();
```

Do not introduce a local merely to rename a short side-effect-free expression
used once by the next statement. Inline it when the resulting statement fits:

```x2c
return %(!set $binder ($op @{args.cdr()}));
```

Keep the local when it fixes evaluation order, prevents repeated work, carries
a useful name across several statements, or isolates an operation that can
fail.

Evaluate a repeated stable accessor once when the accessor is side-effect-free
and the receiver cannot change between uses. Give the value the role name used
by the surrounding operation. Do not cache an accessor merely because its
spelling repeats; mutation, lazy work, or a changed receiver can make separate
calls meaningful.

Typedefs belong at file scope. The compiler's delayed transform does not
support block-local typedef ownership.

### Standard predicates

Prefer an established library predicate or helper to an expanded definition
when it has the intended semantics. For C character predicates, first place
the input in the `unsigned char` domain:

```x2c
unsigned char first = (unsigned char) spelling[1];
if (!(isalpha(first) || first == '_')) return 0;
```

Do not hand-spell alphabetic and numeric ranges when `isalpha`, `isalnum`, or
another existing owner expresses the same accepted domain. Keep explicit
ranges when ASCII rather than the predicate's domain is part of the contract.

### Switches and compact tables

Alignment is useful when it exposes a small, stable table:

```x2c
switch (token.type) {
  case <if>:       return _parse_if(c);
  case <while>:    return _parse_while(c);
  case <return>:   return _parse_return(c);
  case <{>: {
    c.next();
    return c.parse_compound_statement();
  }
}
```

Do not align unrelated declarations across a large region. Padding that must
change when one name grows is noise, not structure.

Document intentional fallthrough immediately before it. Otherwise terminate
each case with `return`, `break`, or an explicit transfer.

## Names expose ownership

Use:

- `Type.method` for a public operation owned by `Type`;
- `Type._helper` for a private helper dominated by one receiver;
- `_snake_case` for a private stateless helper;
- `snake_case` for local variables and parameters;
- `UPPER_CASE` for true constants and enum members.

When one parameter is the subject of the whole function, name it with the
first lowercase letter of its unqualified type: `Compiler c`, `Emitter e`, or
`UnzipShared *u`. If that name is already bound, repeat the letter until the
name is free: `c`, `cc`, `ccc`. Other parameters keep names that state their
roles.

Prefer receiver ownership when most inputs and mutable state come from one
object:

```x2c
static List Emitter._declarator(
  Emitter e, List declaration, List modifiers) {
  // ...
}
```

Keep a free helper when no receiver owns the operation:

```x2c
static int _is_reserved_spelling(String s) {
  // ...
}
```

Do not move a function merely to obtain dot syntax.

Names should make routine comments unnecessary:

Prefer:

```x2c
static int _path_is_readable_file(String path);
```

Avoid:

```x2c
// Check whether p is a readable regular file.
static int _check(String p);
```

Short conventional names remain appropriate for tight traversal scopes:

```x2c
for (List p = values; p; p = p.cdr())
  output.push(p.car());
```

Do not use `tmp`, `data`, `result`, or `value` when the role remains ambiguous
across a nontrivial function.

### Public C names

Use an `x2c_*` name only for the C interface described in
[One owner per concern](x2c-code-organization-guide.md#one-owner-per-concern).

### Forward declarations

Do not write function forward declarations in ordinary x2c source. x2c
collects the complete unit, derives generated headers from definitions, and
emits required external C prototypes from canonical global signatures. The
compiler in `src/` is user-space x2c for this rule.

Only runtime files under `lib/` have exceptions. Keep a declaration there when
definitions must name each other through a genuinely co-recursive dependency,
whether they share a file or cross runtime units. Also keep an exact literal
prototype when shallow macro, protocol, or generated-definition collection
must see it before expansion. State a non-obvious exception beside the
declaration. A declaration merely repeated by a later definition is not an
exception.

## Let x2c carry the syntax

Use language forms that expose the intended owner and shape. Do not spell
their C lowering by hand.

### Parsers read like grammars

Write each recursive-descent production in the order of the grammar it
recognizes: parse the left operand, test or expect the punctuation, recurse
for a right-associative operand, and return the resulting List.

```x2c
List Compiler.parse_conditional(Compiler c) {
  List condition = _parse_binary_ops(c);
  Token origin = c.token;
  if (!c.test(<?>)) return condition;
  List ontrue = c.parse_expression();
  c.expect(<:>);
  return c.resolve_expression(
    %(expr () (op ? $condition $ontrue ${c.parse_conditional()})), origin);
}
```

- Use one recursive function per production or reusable precedence level.
  Reserve operand and operator stacks, work queues, request records, and
  callbacks for state the grammar cannot express directly.
- Keep token consumption and source-order scope changes in the parser. Give
  the canonical List to the operation that owns its meaning:
  `Compiler.resolve_expression` for expression types, conversions, protocol
  operators, and method resolution; the declaration helpers in `src/parse.x`
  for installation and publication.
- Complete macro-produced Lists through those same operations. The
  generated-syntax walk visits Lists and enters their scopes; it does not
  replay tokens, parse generated strings, or copy typing rules.
- Name a shared helper for the semantic action it performs. Avoid vague
  names such as `process`, `request`, and `handle`.

Later phases descend through ASTs the same way; see
[AST patterns](replacing-manual-ast-walks-with-match.md).

### Trust supported conversions

When the compiler supports a conversion, write the source value in its natural
type and let the target type request the crossing. This applies to function
arguments, return values, assignments, and initializations.

Prefer:

```x2c
static Var _publish_label(
  Var input, String replacement, Array labels, Map fields) {
  String text = input;
  fields[<label>] = replacement;
  labels.push(text);
  return replacement;
}
```

Avoid explicit extraction and boxing at the same verified boundaries:

```x2c
static Var _publish_label(
  Var input, String replacement, Array labels, Map fields) {
  String text = input.string();
  fields[<label>] = replacement.var();
  labels.push(text.var());
  return replacement.var();
}
```

The target types of `text`, `Map.setindex`, `Array.push`, and the function
return already tell the compiler which conversions are needed. Explicit
`.var()`, `Var.new`, `.string()`, `.list()`, `.array()`, `.integer()`, and
similar converters stay only where they select real semantics or cross a
boundary the compiler cannot prove. Common legitimate sites include dynamic
tag inspection, variadic or macro boundaries, raw C ABI code, and direct
tests of the conversion owner.

The compiler reports a converter call or cast that repeats its destination's
crossing as an `unnecessary conversion` warning; see
[Conversions](../docs/src/reference/language.md#types-and-conversions).

The same rule applies to literals. Write a plain `"..."` where a String or
Var destination, Array element, Map key or value, or method receiver requests
the promotion. Inside `%()`, a nested `"text $name"` already interpolates.
Elsewhere keep `%"..."` when interpolation, multiline text, or escape
decoding requires it. Write Arrays and Maps as
evaluated literals such as `[item, count + 1]` and `{name: value}`, and keep
`%[...]` and `%{...}` for quoted data. See
[Collection literals](../docs/src/guide/collections.md#array-and-map-literals)
for the key, `{}`, and `$` insertion rules.

### Separate storage ownership from typed crossings

A record may stay in caller-owned native storage while its pointer crosses a
`Var` field. When the stored and recovered pointer type is known, give that
pointer a private alias, define its conversions once, and adopt
`Var(Alias)`. The pointee and its lifetime stay where they were. Keep raw
`.p64` access inside the conversions, and call the named reverse converter
when the generic `Var`-to-pointer conversion would otherwise win:

```x2c
typedef LocalState *LocalStateRef;

static inline Var LocalStateRef.var(LocalStateRef l) => (Var) { .p64 = l };
static inline LocalStateRef Var.localstateref(Var v) => v.p64;
protocol Var(LocalStateRef);

static int _next(Iter i, Var *out) {
  LocalStateRef state = i.obj.localstateref();
  // ...
}
```

When a public parameter keeps the underlying pointer spelling, cast it to the
alias inside the call whose prototype requests `Var`:
`return dest.init((LocalStateRef) state, _next, 0);`. The cast selects the
participant and the `Var` parameter inserts its forward converter, so an
alias-typed temporary for that call adds nothing.

[Box private records through
`Var(T)`](../docs/src/guide/idioms.md#box-private-records-through-vart) and
[Protocols](../docs/src/guide/protocols.md#declaration-and-adoption) describe
adoption and visibility, and
[Adapters, macros, and decorators](adapters-macros-decorators.md) describes
generating a repeated converter family.

A protocol adoption must supply a real shared operation, default, or typed
crossing. Do not add a protocol whose generated methods only convert the
receiver to an existing view and call that view's methods. Call the conversion
and method directly.

### Prefer receiver chains

Always prefer receiver methods and chain them when each result feeds the next
operation.

Prefer:

```x2c
String stem = path.rstrip("/").split("/").last();
```

Avoid class-style calls, temporary values, and explicit converters that repeat
the same pipeline:

```x2c
String clean = String.rstrip(path, "/");
List parts = String.split(clean, "/");
String stem = parts.last().string();
```

Use `value.method()` instead of `Type.method(value)` whenever the receiver's
static type selects the same callable. Use `.car()` and `.cdr()` rather than
free `car(value)` and `cdr(value)`. The ordinary free-function exception is
`cons(head, tail)`, which constructs a new head while deliberately sharing a
suffix and therefore has no natural receiver.

An explicit owner call remains valid only when it selects different semantics,
such as delegating from an Array method to its Block implementation, or when
the receiver's static type cannot select the callable.

### Status results

One operation gets one public surface. Do not keep a void adapter that
merely discards a status owner's result, and do not split a result across an
out-parameter and a status code when the sentinel cannot occur in the
success domain. Return the value and let `void` or NULL carry absence:

```x2c
Var owned = value.clone_wide();
if (owned is void) return void;
```

Reserve `try_` names for genuine presence, exhaustion, or traversal results;
see [Separate absence from
data](../docs/src/guide/idioms.md#separate-absence-from-data). See the root
[AGENTS.md](../AGENTS.md) for the Error causes that never return and the
checks that stay.

### Closed identities

Use Symbol literals such as `<abort>` for closed control vocabularies. Keep a
numeric enum when values index storage, participate in arithmetic, cross an
integer ABI, or rely on zero initialization. When the vocabulary also needs
membership, a dense index, or ordered iteration, declare one `SymbolSet`
literal instead of a hand-written or generated switch:

```x2c
static const SymbolSet tags = $var.tag.symbolset();
static TagId _tag2id(Symbol tag) => (TagId) tags.index(tag);
```

[Ordered Symbol sets](../docs/src/guide/collections.md#ordered-symbol-sets)
describes the literal. When another fact belongs to the same identity, add it
to the row the index already selects, such as `taginfo[id].kind`, and keep
one lookup.

### Literals, strings, and formatting

Use native x2c literals whenever the value family has literal syntax,
including empty values:

```x2c
String text = %"";
Array values = [];
Map index = {};
```

Avoid spelling the same values through constructors or representation
details:

```x2c
String text = String.new("");
Array values = Array.new();
Map index = Map.new();
```

Keep `%""` for an empty String because `""` becomes a static initializer. An
empty List is `NULL`.

File-static declarations use these literals too; see
[File-static literals](../docs/src/guide/collections.md#file-static-literals).

Use interpolation for ordinary construction:

```x2c
String path = %"${root.rstrip("/")}/$name";
```

Keep printf formatting when width, base, precision, character, or pointer
spelling is part of the contract:

```x2c
output.printf("%08x", hash);
```

Do not manually extract a statically typed `Var` merely to reproduce a
supported format conversion.

Consolidate adjacent `puts` or `fputs(..., stdout)` calls that emit one static
prose block into one multiline literal. Compare the emitted bytes before and
after: `puts` contributes a newline while `fputs` does not, and indentation in
a multiline literal may be observable. Keep separate calls when the output is
conditional, formatted, directed elsewhere, or clearer as distinct records.

### Lists and ordered construction

Use a literal for a fixed semantic shape:

```x2c
return %(expr $type (call $function $arguments));
```

Use a fixed accessor or flat destructuring for a trusted small shape:

```x2c
Var (tag, type, body) = node;
List parameters = signature.cadr();
```

Do not destructure a conditional shape or association lookup. Use `match`,
`assoc`, or an explicit check at that boundary.

Build a variable-length forward sequence with a transient Array:

```x2c
Array statements = [];
while (c.peek() != <}>) statements.push(c.parse_statement());
List body = statements.list_free();
```

Use `cons` when the sequence is naturally newest-first or deliberately shares
a suffix. Do not prepend in one phase and make a later phase reverse it.

### Pattern matching

See [AST patterns](replacing-manual-ast-walks-with-match.md) for choosing
among a source `match`, `match_replace`, flat destructuring, and `foreach`,
and the [pattern-matching guide](../docs/src/guide/match.md) for the pattern
vocabulary.

- Prefer a source `match` when the pattern is a static literal, success
  selects a local branch or early return, and the captures are consumed
  inside that branch.
- Keep `List.match` when the pattern is built or selected at runtime, the
  binding List leaves the branch, the caller needs only a boolean, or a
  statement rewrite would duplicate case bodies or change arm order.
- A static source arm owns a prepared plan and pays its first-use cost;
  `List.match` reuses the shared prepared-pattern cache. On a hot path, keep
  a conversion made for performance only after paired measurement.
- Use explicit traversal when order, cursor state, ownership, or performance
  is the point.
- Use direct access for a shape an earlier phase guarantees. Do not add a
  validator or catch-all arm only to give an invalid internal shape an
  earlier diagnostic.

## Compiler code shows phase ownership

Parser code preserves source order and source-established types. Transforms
own runtime crossings and normalization. Emitters consume the normalized
shape and do not repair earlier phases. A transform helper rewrites its
current node and returns the replacement; the fixed-point driver processes
the returned children. Add local recursive repair only when the phase
contract requires it. Comment a phase boundary where it would surprise a
reader. The phases and their modules are listed under
[Compiler organization](x2c-code-organization-guide.md#compiler-organization).

## Representation and lifetime stay visible

Use a compact comment beside the representation when fields alone do not show
the invariant:

```x2c
/* Presence bits stay separate because raw Null is valid captured data and
   void cannot enter the value array. */
typedef struct MatchCaptureBuffer {
  Var *values;
  unsigned long *present;
} MatchCaptureBuffer;
```

Name the lifetime owner at the allocation or crossing when it is surprising:

```x2c
// Canonical storage belongs to the Pool, not the caller's active scope.
return Scope.malloc_in(&inner.scope, size);
```

Do not repeat an invariant downstream after a constructor, canonicalizer, or
typed boundary has established it. If readers need the same explanation in
many places, the invariant probably lacks one clear owner.

## Review checklist

Run [`audit-source.sh`](skills/clean-x2c-source/scripts/audit-source.sh) for
width, whitespace, wrapping, braces, deferred initialization, forward
declarations, negated `is` tests, narration, stock prose, and subject
parameter names in receiver methods. Then check what it cannot:

- Did the current language or an existing owner make a whole wrapper, route,
  check, protocol, alias, or representation unnecessary?
- Does every comment add a fact the code does not already say, with each
  shared invariant explained once at its owner?
- Is the module header about ownership, and are public `/**` comments
  proportional to their callables?
- Are section labels sparse and structurally meaningful?
- Are declarations named for their roles and combined into rows where the
  complete row fits?
- Are one-use pure temporaries and hand-expanded standard predicates gone?
- Is every `else` on its own line?
- Are `x2c_*` names limited to intentional generated-code or native C entry
  points?
- Do native literals, receiver chains, and target-typed conversions carry the
  construction?
- Does each operation expose one status surface, with `try_` reserved for
  genuine presence or exhaustion?
- Do closed vocabularies that need membership or a dense index use a
  `SymbolSet`?
- Do parser functions follow grammar order, and do source parsing and
  generated Lists call the same semantic operation?
- Is the language name written `x2c`?
