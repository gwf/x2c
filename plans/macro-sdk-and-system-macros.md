# Compile-time Lisp SDK completion and system-wide macros

> Status: active - 2026-09-17. Phase 3 and most of Phase 4 are shipped:
> `String.dedent`, `$dedent`, `$switch`, `$assert`, `$todo`, `$unreachable`,
> and `$time`, with unit coverage in `unittest/test-system-macros.x` and a
> chapter section in `docs/src/guide/system-macros.md`. Building them removed
> most of Phase 2, because `$switch` needed no new SDK operation at all.
> Phase 1 is not started and carries a correction an independent review
> reproduced: its rename breaks the checked-in bootstrap and needs a
> compatibility step. `$table` and the enum readers remain.
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
infix. `etc/builtin-macros.xlisp` adds 52 helpers to the same namespace: 16
`x2c._foreach.*`, 35 `x2c._class.*`, and one `x2c._scope.*`. Against 14 public operations in
`etc/compiler-sdk.xlisp`, someone typing `x2c.` sees roughly 85 names of which
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
`x2c._foreach.*`, `x2c._class.*`, and `x2c._scope.*` become `foreach.*`,
`class.*`, and `scope.*`, matching
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

Rename the bind targets in `src/macros.x`, the definitions in
`etc/compiler-sdk.xlisp`, and their callers in `etc/lisp-bindings.xlisp`,
`etc/builtin-macros.xlisp`, and `etc/builtin-macros.xmacro`. Move the 52 shipped-macro helpers out of `x2c.`.
Load `etc/lisp-extras.xlisp` with the other three libraries. Publish the
promoted operations in `docs/src/reference/language.md` beside the existing SDK
list.

The rename needs a compatibility step, and the plan's earlier claim that the
checked-in bootstrap builds the renamed tree is wrong. `bootstrap/` holds only
`Makefile`, `lib`, and `src`; `etc/*.xlisp` is read from the live tree at
`src/macros.x:870`, while `bootstrap/src/macros.c` hard-codes the old bind
spellings. Renaming both sides at once leaves the bootstrap compiler binding
old names against renamed Lisp, and the build fails before `bootstrap-refresh`
can run. So this phase binds both spellings in `src/macros.x`, lands in
`bootstrap/`, and drops the old spellings in a following change. A C-side bind
name is a compiler capability with respect to the shared `etc/` files.

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

Captured syntax reaches Lisp as an ordinary walkable List, so `block.items` and
`syntax.kind` are `cdr` and `car` and need no C. Both must see through the
`(at LINE ...)` origin anchors that `src/statements.x` wraps around every
ordinary block item, or every item reports its kind as `at`. Only
`x2c.type.members` and the diagnostic additions below need compiler code, so
this phase splits by where each part lands.

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

## Phase 4 - switch and table

- `$switch` as specified above. Implemented; needs a fixture and the showcase
  entry.
- `$table` - a dedented text table in a string literal expands to a static
  array of records, using `x2c.source.text` and the Phase 2 constructors.

Enum name tables and exhaustive-switch checking wait behind `x2c.type.members`
and are scoped against what `SymbolSet` already covers. `docs/src/guide/idioms.md`
directs a closed vocabulary of Symbols needing membership tests, a dense index,
or ordered iteration to a `SymbolSet` literal, and `x2c._symbol-set` is already
a primitive, so the remaining gap is narrower than the C case suggests.

Resource-management macros are out of scope; `$auto`, `$scope`, `$lock`, and
`defer` hold that ground.

## Proof: what a working implementation showed

Seven operations are implemented, tested, and documented: `String.dedent`,
`$dedent`, `$switch`, `$assert`, `$todo`, `$unreachable`, and `$time`. Building
them was the test of whether the proposed API can express them, and it changed
the plan more than the plan changed the implementation.

`$switch` needed no new SDK operation. A switch body is a flat item list whose
labels and statements form a regular pattern, so `match-case` over `car` and
`cdr` of the captured block is the entire transform, and the `(at LINE ...)`
origin anchors are matched as part of the pattern rather than seen through.
The proposed `x2c.block.items` and `x2c.syntax.kind` bought nothing. Measured:
`case 1: case 2:` share one generated block and one break; a case ending in
`return` gets no break; two cases declare the same name and compile, which
plain C rejects without hand-written braces; a leading declaration, a `goto`
label, and an `#ifdef` inside the body all pass through and compile.

Both `$dedent` paths work. A literal with no escape and no hole folds during
translation: `$dedent(%"\n    alpha\n      beta\n    gamma\n  ")` emits
`String_new("alpha\n  beta indented further\ngamma\n")` with no runtime call.
An interpolated literal emits `String_dedent(String_join(...))` and produces the
same text at run time. `$time` expands to a `clock_gettime` pair around its
target with `using` temporaries.

Five things the implementation settled:

- The fold reads `x2c.source.text`, which already exists. The proposed
  `x2c.literal.value` would not have worked, so `$dedent` is not evidence for
  that operation.
- The transform is about 85 lines of compile-time Lisp over `substring`,
  `string-length`, and `string-append`. It recurses per character within a line
  and per line across the text; per-character recursion over a whole text would
  reach the interpreter's ceiling, which sits between 2,000 and 20,000 frames.
- `x2c.expr.ident` takes the tagged value from `x2c.ident` while
  `x2c.expr.field` takes a plain String and calls `x2c.ident` itself. Passing
  the tagged value to `field` fails with `bad-types`. The constructor family
  already has the inconsistency the naming rule is meant to remove.
- `String.dedent` needs no prefix argument, which removes the open question
  about what prefix an emitted runtime call would receive.
- Phase 2's reader set is mostly unnecessary. Captured syntax is an ordinary
  walkable List and `match-case` is already in the compile-time Lisp, so the
  readers that remain worth adding are `x2c.type.members` and the diagnostic
  additions, both of which need C.

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
