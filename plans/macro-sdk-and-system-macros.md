# Compile-time Lisp SDK completion and system-wide macros

> Status: needs author scoping - 2026-09-17. Designed from a read of
> `etc/compiler-sdk.xlisp`, `etc/lisp-bindings.xlisp`, `etc/builtin-macros.xlisp`,
> the 34 `$lisp.bind` calls at `src/macros.x:894`, and the shipped generator in
> `lib/varops.x` + `lib/varops.xlisp`. No code written. The macro direction
> follows the 2026-07-28 decision to keep macros as a hygienic replacement for
> the C preprocessor.

## The result

The compile-time Lisp SDK reads and constructs every syntax category it can
already capture, under one naming rule, and the repository ships a small set of
system-wide macros that remove C boilerplate x2c currently reproduces.

Today the SDK constructs expressions and literals and inspects types and
functions. It cannot read a literal's value, an enum's members, a block's
items, or a node's kind, and it cannot construct a statement, declaration,
block, or type. Generators therefore hand-walk and hand-write canonical AST.
`lib/varops.xlisp:34` digs a tag Symbol out of a captured `Literal` with
`(car (cdr (cdr (cdr (car (cddr id))))))`, and `lib/varops.xlisp:44` writes
`(expr () (cast (decl ,type (bindings (bind () ())))  ,value))` by hand because
no constructor exists. That file is 57 lines and roughly half of it is working
around missing SDK operations.

The naming is three rules at once. `x2c.type.fields` is public;
`_x2c.type.parameters` is private by prefix; `x2c._source.text` is private by
infix. `etc/builtin-macros.xlisp` adds 52 `x2c._foreach.*` and `x2c._class.*`
helpers to the same namespace. Against 14 public operations in
`etc/compiler-sdk.xlisp`, someone typing `x2c.` sees roughly 86 names of which
about 28 are theirs.

`etc/` holds four Lisp files with three loading behaviors. `src/macros.x:884`
evaluates `init.xlisp`, `compiler-sdk.xlisp`, and `builtin-macros.xlisp`;
`lisp-bindings.xlisp` loads conditionally at `src/macros.x:92`;
`etc/lisp-extras.xlisp` never loads into the macro environment, which is why
`caddr` is unbound inside a macro while `cadr` and `cddr` work.

## Settled choices

**Naming.** A supported operation is `x2c.<noun>.<verb>` with no infix
underscore. An internal primitive keeps a single reserved prefix and never
appears inside a public name. Shipped-macro helpers leave `x2c.` entirely:
`x2c._foreach.*` and `x2c._class.*` become `foreach.*` and `class.*`, matching
how `lib/varops.xlisp` already names `native.update.*`.

**Loading.** `etc/lisp-extras.xlisp` loads with the other three, so the macro
environment and the Lisp shell offer the same library. It is 34 lines of
`sort`, `range`, `subst`, and the `c[ad]{3}r` accessors.

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

**AST vocabulary.** The canonical node shapes are already a compatibility
surface that nothing documents. The constructor set completes far enough that a
generator never writes a node shape by hand, and the shapes stay unsupported.
Constructors add `(parens ...)` around binary nodes, since the emitter adds no
precedence parentheses.

**Dedent semantics.** The prefix is declared, not inferred. It is the leading
whitespace of the source line on which the literal begins. Dedent removes that
prefix from the first line and replaces every `\n` or `\r\n` followed by the
prefix with the bare newline, so indentation past the prefix survives verbatim
and the block renormalizes as a unit. A single leading newline after the
opening quote is dropped. A line that does not carry the prefix is left alone.
Inferring the prefix from the minimum indentation of the content was rejected:
it collapses to nothing when any line sits at the left margin, it does nothing
when the first line follows the opening quote, and adding one line silently
changes every other line's result. Taking the prefix from the closing quote's
line was considered and rejected as the less predictable of two declared rules.

**Switch semantics.** `$switch` is a decorator with a `Block` target and one
`Expr` argument, written `$switch(condition) { case 1: ... }`. It builds the
switch rather than rewriting an existing one, which keeps it clear of the rule
that a fixed C keyword cannot serve as a `keyword` alias. It transforms only
the direct items of the captured block, so a nested switch and a case produced
by another macro are untouched, and ordinary nesting remains the way to write
deliberate fallthrough. It operates on runs of labels, so `case 3: case 4:
body;` receives one block and one break rather than one per label. It appends
no break when a run's last item is `break`, `return`, `continue`, `goto`, or a
non-returning raise, which keeps `-Wunreachable-code` quiet. Each run's body
becomes a block, which also satisfies the rule at
`docs/src/reference/language.md:1777` that a switch dispatch cannot bypass a
runtime static declaration.

## Phase 1 - naming and loading

Rename the bind targets in `src/macros.x`, the definitions in
`etc/compiler-sdk.xlisp`, and their callers in `etc/lisp-bindings.xlisp` and
`etc/builtin-macros.xlisp`. Move the 52 shipped-macro helpers out of `x2c.`.
Load `etc/lisp-extras.xlisp` with the other three libraries. Publish the
promoted operations in `docs/src/reference/language.md` beside the existing SDK
list.

No new compiler capability, so the checked-in bootstrap builds the renamed
tree; `bootstrap/` refreshes as part of publication.

## Phase 2 - complete the read and write sides

Readers:

- `x2c.literal.value` - promotion; also accepts int and Symbol literals.
- `x2c.type.members` - enum members as `(("NAME" VALUE) ...)`. Nothing exposes
  them today: `x2c.type.fields` rejects non-aggregates (`src/macros.x:306`) and
  `x2c.type.parts` returns `declaration_parts()`, a base and declarator-modifier
  split (`src/macros.x:256`).
- `x2c.block.items` - the block-item sequence of a captured `Block` or compound
  `Statement`.
- `x2c.syntax.kind` - the node kind of any captured syntax.

Constructors, extracted from the quasiquotes `etc/builtin-macros.xlisp` and
`lib/varops.xlisp` already contain:

- `x2c.stmnt.make`, `x2c.stmnt.return`, `x2c.block.make`
- `x2c.decl.make`, `x2c.expr.cast`, `x2c.type.make`
- typed literal construction, replacing rows such as
  `(expr (int) (literal (int) "0"))` embedded in `lib/varops.xlisp`

Diagnostics: add `x2c.diagnostic.warn`, and a location argument on both
diagnostic operations accepting captured syntax, so a macro reports against the
declaration it rejects rather than always at its own invocation.

Acceptance for this phase is `lib/varops.xlisp`: the
`(car (cdr (cdr (cdr (car (cddr id))))))` row accessor, the
`native.update.cast` constructor, and the embedded AST literals all disappear.
Confirm during implementation whether a bare identifier can replace the seven
`$(x2c.ident "lhs")` wrappers in the `$native.update` body at `lib/varops.x:54`;
if it can, include that template fix here.

This phase adds compiler capability, so it lands in `bootstrap/` before
anything in Phase 3 or 4 calls it.

## Phase 3 - macros that need no new capability, plus dedent

- `String.dedent(String str, String prefix)` in `lib/string.x`, composed from
  the existing `String.startswith` and `String.replace`. The `$dedent` macro
  folds it at compile time when `x2c.literal.value` resolves the argument, and
  emits the call otherwise, so interpolated and runtime strings behave
  identically. Give it a `keyword dedent` alias.
- `$todo` and `$unreachable` - expand to a raise carrying file, line, and
  column from the existing `x2c.invocation.*`.
- `$bench` - `Statement` and `Function` target decorator wrapping the target in
  a timing pair.
- `$show` - field-by-field debug print from `x2c.type.fields`.

## Phase 4 - switch and table

- `$switch` as specified above.
- `$table` - a dedented text table in a string literal expands to a static
  array of records, using `x2c.literal.value` and the Phase 2 constructors.

Enum name tables and exhaustive-switch checking wait behind `x2c.type.members`
and are scoped against what `SymbolSet` already covers. `docs/src/guide/idioms.md`
directs a closed vocabulary of Symbols needing membership tests, a dense index,
or ordered iteration to a `SymbolSet` literal, and `x2c._symbol-set` is already
a primitive, so the remaining gap is narrower than the C case suggests.

Resource-management macros are out of scope; `$auto`, `$scope`, `$lock`, and
`defer` hold that ground.

## Validation

Per phase: `make x2c` plus the macro fixtures under `unittest/`, and the
executable examples that exercise macros. Phase 3 and 4 each add a fixture for
the new macro's expansion and one for its rejection case. Publication uses
`tools/gate-state.py ensure agent-pr-check`.

`examples/magic/system-macros.x` is the existing showcase for the shipped macro
set and is registered in `examples/manifest.txt:33`. Phase 3 and Phase 4 extend
it with the macros they add and update `examples/expected/system-macros.stdout`
rather than adding a second showcase.

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

**Validators, diagnostics, and negative fixtures.** Two, each protecting wrong
output rather than earlier failure. `x2c.type.members` rejects a non-enum
`Type`, mirroring the existing rejection in `x2c.type.fields` and preventing a
generator from emitting a table from an unrelated type. `$switch` rejects a
captured block item that is neither a label run nor a declaration, since it
would otherwise emit a switch body whose breaks land in the wrong place.
`$dedent` has no validator: a line that does not carry the prefix is left alone
by definition, and a non-literal argument falls through to the runtime call.
Negative fixtures cover the two rejections.
