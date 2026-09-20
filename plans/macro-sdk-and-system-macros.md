# Compile-time Lisp SDK completion and system-wide macros

> Status: reference - diagnostic-location and enum-consumer follow-ups remain
> open; no current dispatch recorded. Phases 1 and 3 and most of Phase 4 are
> shipped. Phase 1 landed in four commits, `f3623b66` through `765e2cdc`:
> both spellings bound and refreshed into `bootstrap/`, then every caller
> switched and the old rows dropped, then the transitional entry-point
> aliases removed. Phase 3 and `$switch` shipped earlier, with unit coverage
> in `unittest/test-system-macros.x` and a chapter section in
> `docs/src/guide/system-macros.md`. Phase 2 shipped smaller than scoped,
> because `$switch` showed that captured syntax is an ordinary walkable List.
> `$table` is dropped. What remains is the diagnostic location argument and
> enum consumers. The old `lib/varops.xlisp` row-accessor task was superseded
> by ed863ce0, which replaced that file with `lib/varops.xmacro`.
> Scoped 2026-09-17 from a read of
> `etc/compiler-sdk.xlisp`, `etc/lisp-bindings.xlisp`, `etc/builtin-macros.xlisp`,
> the 33 `$lisp.bind` calls at `src/macros.x:894`, and the shipped generator in
> `lib/varops.x` + `lib/varops.xlisp`. The macro direction follows the
> 2026-07-28 decision to keep macros as a hygienic replacement for the C
> preprocessor.

## The result

The compile-time Lisp SDK reads and constructs every syntax category it can
already capture, under one naming rule, and the repository ships a small set of
system-wide macros that remove C boilerplate x2c currently reproduces.

Before this work the SDK constructed expressions and literals and inspected
types and functions, and nothing else. It could not read a literal's value or
an enum's members, and it could not construct a statement or a declaration, so
generators hand-walked and hand-wrote canonical AST: `lib/varops.xlisp` dug a
tag Symbol out of a captured `Literal` with
`(car (cdr (cdr (cdr (car (cddr id))))))` and wrote its own cast constructor.

The naming was three rules at once. `x2c.type.fields` was public,
`_x2c.type.parameters` private by prefix, and `x2c._source.text` private by
infix, while `etc/builtin-macros.xlisp` added 52 helpers to the same namespace.
Against 14 public operations, someone typing `x2c.` saw roughly 85 names of
which about 28 were theirs.

## Settled choices

**Naming.** A supported operation is `x2c.<noun>.<verb>` with no infix
underscore. An internal primitive keeps a single reserved prefix and never
appears inside a public name. Shipped-macro helpers leave `x2c.` entirely:
`x2c._foreach.*`, `x2c._class.*`, and `x2c._scope.*` become `foreach.*`,
`class.*`, and `scope.*`, matching
how `lib/varops.xlisp` already names `native.update.*`.

**Loading.** `etc/lisp-extras.xlisp` stays out of a macro session. Its
three-level `c[ad]{3}r` selectors moved into `etc/init.xlisp`, which every
session loads, so a macro body gets them without also importing `fib`,
`range`, and `sort` into every compilation.

**Promotion over invention.** Seven primitives already bound privately become
public under names describing their behavior. They need no new compiler code.

| Current | Public name | Behavior |
| --- | --- | --- |
| `_x2c.literal.string` | `x2c.literal.value` | a String literal's decoded value |
| `_x2c.type.parameters` | `x2c.type.parameters` | function parameter types |
| `_x2c.type.return` | `x2c.type.return` | function result type |
| `_x2c.type.element` | `x2c.type.element` | pointer or array element type |
| `_x2c.type.integral?` | `x2c.type.integral?` | integral predicate |
| `_x2c.type.pointer?` | `x2c.type.pointer?` | pointer predicate |
| `_x2c.foreach.protocol-member` | `x2c.protocol.member` | conformance lookup (`src/macros.x:205`) |

`_x2c.foreach.ident-unique` (`src/macros.x:398`) stays internal. It is
`Compiler.fresh_name` plus `sym.introduce`, and the template language already
exposes gensym publicly through `using $temporary`. Promote it only if a Lisp
generator needs a name the `using` clause cannot declare.

**AST vocabulary.** The canonical node shapes are a compatibility surface that
nothing documents. The constructors cover the shapes generators in this tree
actually wrote by hand; the vocabulary itself stays unsupported. A generator
reaching past them still quasiquotes, and a constructed binary node still needs
explicit `(parens ...)` because the emitter adds no precedence parentheses.

**Dedent semantics.** The prefix is declared by the text itself: after one
leading newline is dropped, it is the run of spaces and tabs opening the first
content line. Dedent removes it from that line and replaces every `\n` or
`\r\n` followed by the prefix with the bare newline, so indentation written
past the prefix survives verbatim and the block renormalizes as a unit. A line
that does not carry the prefix, including a blank one, is left alone, except
that a final line of only whitespace is removed so the closing quote's own
indentation stays out of the result. Inferring the prefix from the minimum
indentation of the content was rejected: it collapses to nothing when any line
sits at the left margin, it does nothing when the first line follows the
opening quote, and adding one line silently changes every other line's result.
An earlier draft took the prefix from the source line the literal begins on;
that rule is not implementable, because `x2c._invocation.location` reports the
invocation token's column rather than the line's indentation and
`x2c.source.text` cannot see behind its capture. Deriving the prefix from the
content needs no location at all.

**Switch semantics.** `$switch` is a decorator with a `Block` target and one
`Expr` argument, written `$switch(condition) { case 1: ... }`. It builds the
switch rather than rewriting an existing one, which keeps it clear of the rule
that a fixed C keyword cannot serve as a `keyword` alias. A switch body is a
flat item list with a regular shape, so the whole transform is one `match-case`
walk: a run of `(at LINE (case ?value))` and `(at LINE (default))` items keeps
its position, and the statements following it become one `(block ...)` carrying
the break that run needs. `case 3: case 4: body;` therefore receives one block
and one break rather than one per label. No break is appended when a run's last
item already transfers, which keeps `-Wunreachable-code` quiet. Items before
the first label pass through unchanged, so a declaration shared by every case
keeps its scope, and any item that is not a label passes through, so `goto`
labels and preprocessor directives inside the body are untouched. Each run's
body becoming a block also satisfies the rule at
`docs/src/reference/language.md:1777` that a switch dispatch cannot bypass a
runtime static declaration, and lets two cases declare the same name.

## Phase 1 - naming and loading

Shipped. 13 bind targets renamed in `src/macros.x`, 7 of them promoted to
public names, with callers switched in `etc/compiler-sdk.xlisp`,
`etc/lisp-bindings.xlisp`, `etc/builtin-macros.xlisp`,
`etc/builtin-macros.xmacro`, `lib/error-macros.xmacro`, `lib/var-tags.xmacro`,
and `lib/lisp.x`. The 52 shipped-macro helpers left `x2c.` for `foreach.`,
`class.`, and `scope.`. The promoted operations are published in
`docs/src/reference/language.md` with the naming rule itself.

Two ordering constraints decided the shape, and both bite at the same place:
something the compiler carries in compiled form against something it reads
from the live tree.

`bootstrap/` holds only `Makefile`, `lib`, and `src`, while `etc/*.xlisp` is
read from the live tree at `src/macros.x:870` and `bootstrap/src/macros.c`
compiles in the bind spellings. Renaming both sides at once leaves the
bootstrap compiler binding old names against renamed Lisp. So both spellings
bound first and landed in `bootstrap/`; the callers switched and the old rows
went in the next change.

`etc/builtin-macros.xmacro` is embedded in the compiler binary by
`src/macros.x:40`, while `etc/builtin-macros.xlisp` beside it is read from
disk. Renaming an entry point breaks the build under the compiler that still
embeds the old macro text, so `foreach.expand`, `scope.expand`, `class.expand`,
and `class.defaults` kept an alias for one refresh and then lost it.

`etc/lisp-extras.xlisp` is not loaded into a macro session. Its three-level
`c[ad]{3}r` selectors moved into `etc/init.xlisp`, which every session already
loads, so macro bodies get them without also importing `fib`, `range`, and
`sort` into every compilation.

## Phase 2 - complete the read and write sides

Shipped. `x2c.type.members`, `x2c.diagnostic.warn`, `x2c.literal.value`
widened to int and Symbol literals, and the constructors `x2c.stmnt.make`,
`x2c.stmnt.return`, `x2c.block.make`, `x2c.decl.make`, `x2c.param.make`, and
`x2c.expr.cast`. The constructors were promotions: five private copies in
`etc/builtin-macros.xlisp` and one in `lib/varops.xlisp` were deleted and their
callers now use the public names.

`x2c.type.members` and the constructors are pure Lisp over `x2c.type.resolve`
and quasiquotes, so `x2c.block.items` and `x2c.syntax.kind` were never built:
captured syntax is an ordinary walkable List and `match-case` reaches it
directly, which `$switch` proved.

Widening `x2c.literal.value` moved one rejection. `lisp.binding.record` relied
on the reader refusing a non-String, and the fixture
`unittest/compiler-fixtures/lisp-bind-non-literal-name` records that a binding
name must be a String literal. `lisp.binding.name` now makes that check where
the requirement lives.

Follow-ups from the original scope:

- The `lib/varops.xlisp:32` row-accessor change is obsolete: ed863ce0
  replaced that file with meta functions in `lib/varops.xmacro`. No bootstrap
  wait for this edit remains.
- The location argument on `x2c.diagnostic.fail` and `.warn` is not built. A
  diagnostic location comes from a `Token` (`src/diagnostics.x:351`) while a
  capture records byte offsets (`src/macros.x:364`), so reporting against
  captured syntax needs an offset-to-token mapping that does not exist. A macro
  can meanwhile put `x2c.source.text` or `x2c.invocation.*` in a note. When it
  is built the parameter is optional, so the 23 existing two-argument calls
  keep their meaning.

## Phase 3 - macros that need no new capability, plus dedent

- `String.dedent(String str)` in `lib/string.x`, composed from the existing
  `String.startswith`, `String.replace`, and `String.new_len`. The `$dedent`
  macro folds at compile time from `x2c.source.text`, not from
  `x2c.literal.value`: a multi-line `%"..."` literal reaches a macro as
  `(expr ("String") (cache 0))` with no text in the node, while `source.text`
  returns the complete spelling. The fold applies when that spelling carries no
  escape and no interpolation hole; every other form emits the runtime call.
- `$todo` and `$unreachable` - expand to a raise carrying file, line, and
  column from the existing `x2c.invocation.*`.
- `$time` - `Statement` target decorator wrapping the target in a timing pair.
- `$assert` - raises `<invariant>` carrying the failing check as written, from
  `x2c.source.text`, and the caller's source line.

`$show`, a field-by-field debug print from `x2c.type.fields`, was dropped:
`class` already generates a string method from a type's `write_` members
(`etc/builtin-macros.xlisp:363`), so it would duplicate shipped behavior.

## Phase 4 - switch

`$switch` shipped. `$table` is dropped.

`$table` would have expanded an aligned text table in a string literal into a
static array of records. The six tables in this repository show why that does
not pay: `cli_commands` (`src/cli.x:78`), `cli_options`, and
`lisp_canonical_names` (`lib/lisp.x:308`) hold Symbols, enum constants,
`CLI_TOP | CLI_TRANSLATE` bitwise expressions, `&lsym_quote`, `NULL`, and
strings containing spaces. A whitespace-delimited grid cannot hold an
expression, an address-of, or a cell containing the delimiter, so it would have
replaced none of them, and `cli_commands` is already aligned by hand, which was
the benefit claimed. `native.update.rows` in `lib/varops.xlisp`, the one real
data table, holds AST fragments and works as a Lisp list with no new syntax.

Enum name tables and exhaustive-switch checking are now unblocked by
`x2c.type.members`. Scope them against `SymbolSet`, which
`docs/src/guide/idioms.md` already directs a closed vocabulary of Symbols to
when it needs membership tests, a dense index, or ordered iteration.

## Validation

Per phase: `make build` plus `unittest/test-system-macros.x`, which covers
every shipped macro, and `make doc-examples`, which compiles the chapter's
samples. Phase 3 and 4 each add a fixture for
the new macro's expansion and one for its rejection case. Publication uses
`tools/gate-state.py ensure agent-pr-check`.

`examples/magic/system-macros.x` is the existing showcase for the shipped macro
set and is registered in `examples/manifest.txt:33`. Phase 3 and Phase 4 extend
it and update `examples/expected/system-macros.stdout` rather than adding a
second showcase. `$time` writes a measured duration and `$todo` raises, so
neither belongs in an exact-match expectation; they get unit coverage instead.

## Plan review

**Facts established by producers.** `x2c.literal.value` is the producing
operation for a literal's text; `$dedent` and `$table` consume its result
without re-validating the literal. The macro binder already rejects malformed
and forged captures, so the new constructors trust their operands and add no
second check. `x2c.block.items` returns what the parser produced; `$switch`
dispatches on `x2c.syntax.kind` rather than re-parsing.

**Deletions and reuse.** The design deletes the row accessor, the cast
constructor, and the embedded AST literals in `lib/varops.xlisp`, and removes
hand-written node shapes from `etc/builtin-macros.xlisp`. `String.dedent` reuses
`String.startswith` and `String.replace` rather than adding a scanner. `$switch`
reuses the existing `Statement` decorator capture and adds one reader; it
introduces no traversal, cache, or registry. The promoted operations add no
compiler code at all. The one lasting new mechanism is the constructor family,
which earns its keep by removing the undocumented node-shape dependency from
every generator in the tree.

**Idiomatic x2c.** The constructors extend the existing `x2c.expr.*` family
with the same shape and the same operand convention. The naming rule is the one
`lib/varops.xlisp` already follows. Nothing here imports a macro framework from
another language; the template language, decorators, and `using` stay as they
are.

**Validators, diagnostics, and negative fixtures.** One. `x2c.type.members`
rejects a non-enum `Type`, mirroring the existing rejection in
`x2c.type.fields` and preventing a generator from emitting a table from an
unrelated type. `$switch` has no validator: an earlier draft rejected any
block item that was not a label or a declaration, and the working
implementation shows that check would reject legal `goto` labels and
preprocessor directives while buying nothing, because passing every non-label
item through is what produces correct output. `$dedent` has no validator
either: a line that does not carry the prefix is left alone by definition, and
a non-literal argument falls through to the runtime call. One negative fixture,
for the enum rejection.
