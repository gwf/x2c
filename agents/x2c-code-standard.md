# x2c Code Standard

This standard defines good x2c source in one place: how it reads, how it is
organized, how its parts own their facts, how to find code that falls short,
and how to repair it. It covers hand-authored x2c in `src/`, `lib/`,
`commands/`, `packages/`, `unittest/`, `examples/`, and the samples in the
book. The compiler and runtime are the language's working examples, and
agents copy what they find there, so their source meets this standard first.

The book under `docs/` owns language and library semantics; rules here link
to it for meaning. Correctness and published contracts come before every rule
here. A local representation, ABI, or measured cost may require an exception;
state that constraint beside the exception and keep the rule.

Status: accepted as of 2026-10-05. This is the single definition of x2c
source style. [The adoption plan](../plans/x2c-code-standard.md) tracks its
adoption.

## How to read this standard

Every rule has an ID such as `FN-3`. The prefix gives the level; the number
is stable once published, so lint codes, reviews, and skills can cite it.
Retired rules keep their number and are marked retired.

| Prefix | Level | Prefix | Level |
| --- | --- | --- | --- |
| `PR` | principles | `VT` | values, types, interop |
| `LY` | layout | `LT` | lifetime and memory |
| `ST` | statements and control flow | `ER` | errors |
| `EX` | expressions and literals | `DG` | diagnostics and messages |
| `FN` | functions | `MA` | macros and meta functions |
| `FA` | function families and records | `LI` | compile-time Lisp |
| `FI` | files | `AR` | compiler architecture |
| `CM` | comments and prose | `RT` | runtime library |
| `NM` | names | `PK` | packages and public API |
| `MO` | module sets | `TE` | tests, examples, samples |
| `HP` | hot paths | | |

The [signal catalog](#finding-bad-code) gives each rule's detection signal,
threshold, and tool. The [procedures](#turning-bad-code-into-good-code) give
the repair order and the proof each repair needs. Rules are terse; the
[source style examples](x2c-coding-style-guide.md) holds the worked
prefer/avoid examples, filed under rule IDs.

## Principles

**PR-1 Say what happens.** Code states the operation. Comments state only
what the code cannot: why an owner exists, which invariant is relied on,
where a lifetime ends, why a plausible alternative is wrong.

**PR-2 One owner per fact.** Each invariant, representation, spelling, or
policy has one owner, placed at the phase or module that establishes it.
Consumers rely on it and do not check it again. When a check repeats, find or
strengthen the missing owner first, then delete the copies.

**PR-3 Delete before rearranging.** Before reshaping code, ask what current
syntax, library behavior, or existing owner makes a wrapper, route, check,
protocol, alias, record, or representation unnecessary. Prefer, in order:
deletion, direct use of an existing owner, one shared operation, new code.

**PR-4 Trust established facts.** A producer's guarantee, a type, a pattern,
or a binder establishes exactly what it enforces, and no more. Validate
external input where it enters. Add a check or diagnostic only to preserve
deliberate public behavior or to prevent wrong output, corrupted state, or
an unsafe native crossing. An earlier or more specific error alone does not
justify a check, a diagnostic, or a negative fixture.

**PR-5 Use the language.** Compose current language features and existing
operations. Let target types request conversions, let system macros carry
lifetimes, let `match` carry structure, let receivers carry ownership. Do
not spell a lowering by hand that the compiler performs.

**PR-6 Representation follows identity and lifetime.** Choose a value, a
pointer, a List, an Array, a Map, a Symbol, or a `Var` by the identity,
mutation, and lifetime the data actually has. See
[the philosophy ledger](x2c-philosophy.md) for the verified facts.

**PR-7 Machinery earns its keep.** A macro, ledger, protocol, adapter,
decorator, record, or generated family stays only when it removes owners,
algorithms, or runtime work, counting its definition, helpers, imports,
and generated C. A small net-positive diff is acceptable when it gives a
fact one owner. A generated family is worth its size when several current
families share its operation, failure, representation, and lifetime
rules; one speculative consumer is not enough. Report ownership gains as
ownership gains.

**PR-8 Even proportions.** A reader has a budget per axis: line width,
function height, nesting depth, parameter count, name length, section and
file size. Keep each element inside its band and close to the size of its
neighbors. An element much larger or smaller than its neighbors is a
defect.

**PR-9 One concept, one name, one record.** A concept keeps the same name
across compiler and runtime, the same parameter order across a family, and
at most one record.

**PR-10 Public surface is a contract.** Public runtime signatures, released
names, generated-header contents, and documented error causes are API.
Changing them needs authorization; an uncalled public operation is not dead
code. Compiler methods are provisional API: a rename updates their callers
in `commands/` and needs no approval.

**PR-11 Measure what you claim.** Report authored `.x` lines deleted and
added first, then shape metrics, then generated C and instruction counts.
Never trade a behavioral distinction, or a test of valid behavior or
deliberate public failure, for a smaller diff.

**PR-12 Prefer the general owner, keep its edges.** Delegating a special
case to a general operation is good when the general one preserves the
special case's edge semantics and cost. List the edges (null callback, NaN
payload, pointer values, empty input) before delegating.

## Lines and statements

### Layout

**LY-1** Indent with two spaces. Use no tabs, no trailing whitespace, and
only ASCII in repository source.

**LY-2** Keep code and prose within 79 columns, counting indentation. An
indivisible diagnostic spelling or a table row whose literal fields cannot
wrap may exceed it; review each exception.

**LY-3** Use the 79 columns. Keep a signature, call, condition, or
declaration on one line when it fits and reads in one pass. Split only what
does not fit, or what has real internal structure.

**LY-4** When a signature or call does not fit, end the first line after
`(` and begin all parameters or arguments on the next line with a two-space
continuation. Wrap arguments by semantic group. Never align to an opening
parenthesis. The close and its `{`, `=>`, or `;` stay with the last item
unless an item spans several lines.

**LY-5** Put spaces around binary operators and after commas. Put no space
inside parentheses or brackets.

**LY-6** One blank line separates peer definitions and follows a section
label. No blank line separates a `//` or `/**` comment from what it explains;
a multi-line plain block comment may have one blank line above and below.
Never stack blank lines.

**LY-7** Align columns only for a small stable table, such as one-line
`case` arms or a family of `=>` functions. Never align unrelated
declarations across a region.

### Statements and control flow

**ST-1** Omit braces around a single statement; use them for two or more.
Put `else` on its own line; never write `} else`.

**ST-2** Keep a short guard, update, or loop on one line when the whole
construct fits and reads as one action: `if (!out) return 0;`. Put the body
on the next line when either half is long or a comment belongs between them.

**ST-3** Write guards first and the main path after. An early return
replaces a flag variable or an `else` ladder.

**ST-4** Keep calls out of conditions when the result is used again: bind
the result to a named local, then test it. Assign inside a condition only
in a read loop such as `while ((count = fread(...)) > 0)`.

**ST-5** Spell a negative tag test `value is not T`. Never write
`!(value is T)`.

**ST-6** Rely on protocol truth: `if (items)` tests whether a container
is present and non-empty. A `Var` follows its value's truth, including false
numeric zero and registered truth callbacks. Compare with `NULL` only when
the question is about the pointer. A nonnull `Iter` is true even when
exhausted. Never use `void` as a condition; test `is void`.

**ST-7** Declare a value in the narrowest scope that owns it, initialized
where it becomes meaningful. Never declare at the top and assign later; a
local that an output reference parameter fills is the exception.

**ST-8** Combine consecutive declarations into one row when the row fits:
`String path, List deps, int failed = 0;`. Keep them apart when one needs a
comment, an initializer needs a check between them, the order of failure
matters, or a declarator is complex. Never move a declaration across a
statement to form a row.

**ST-9** Inline a local that only renames a short side-effect-free
expression used once by the next statement. Keep a local that fixes
evaluation order, prevents repeated work, carries a role name across
several statements, or isolates a step that can fail.

**ST-10** Evaluate a repeated stable accessor once, under the role name of
the surrounding operation, when it has no side effect and its receiver
cannot change between uses.

**ST-11** Write membership as `key in values`. Write compound updates
directly, including on `Var`, Array elements, and Map entries:
`counts[key] += 1`. Never hand-write load, compute, and store, and never
pre-test presence before a counting update.

**ST-12** Iterate with `foreach`. Declare the loop variable with the type
the body needs, or `Var` when the body dispatches on tag. Drive an `Iter` or
a cursor by hand only when order, cursor state, streaming, interleaving, or
exhaustion status is the point. Use `map`, `filter`, and folds for direct
transformations. Never call `len()` on a List inside a loop over it.

**ST-13** In a `switch`, end every case with `return`, `break`, or another
transfer, or state the intended fallthrough on the line before it. Use
`$switch` when each case run needs its own block and break.

**ST-14** Keep typedefs at file scope.

**ST-15** Compact an obvious mechanical sequence onto one line when it fits:
a swap, or consecutive `(void) name;` statements. Keep separate lines when a
step branches, can fail, or deserves a comment.

**ST-16** Keep statements free of debug output and temporary instrumentation.
Use `$assert` for an invariant whose failure PR-4 would justify checking,
`$todo` and `$unreachable` for unwritten or
excluded paths; never return a plausible value from a path that should not
run.

### Expressions and literals

**EX-1** Use native literals for every value family that has one, empty
values included: `""`, `[]`, `{}`, `[a, b]`, `{name: value}`. A bare `[]` or
`{}` at a `Var` destination is a fresh Array or Map. Never write
`String.new("")`, `Array.new()`, or `Map.new()`.

**EX-2** Use `%(...)`, `%[...]`, and `%{...}` for quoted data, where names
are content: AST shapes, patterns, configuration trees. Write Symbol names
bare inside `%(...)`; type syntax uses Strings for non-keyword names, as
in `%("String")` and `%(* "Point")`. Do not repeat `%` on nested values,
since a nested `"text $name"` already interpolates; write `${f(x)}` for a
computed insertion. Keep `%{ ${...} }` for a constructed entry row.

**EX-3** Write a plain `"..."` wherever a String or `Var` destination
requests it. Keep `%"..."` for interpolation, multiline text, or escape
decoding. Use interpolation for ordinary text construction. Keep `printf`
formatting when width, base, precision, or pointer spelling is part of the
output. Never unbox a typed `Var` only to reproduce a supported format
conversion.

**EX-4** Let the destination request a conversion. Write the source value
in its natural type at arguments, returns, assignments, and initializers.
Keep an explicit converter or cast only where it selects different
semantics or crosses a boundary the compiler cannot prove: dynamic tag
inspection, variadic and macro boundaries, raw C ABI code, and tests of the
converter itself. The compiler reports the rest as `conversion` warnings.

**EX-5** Chain receiver methods when each result feeds the next:
`path.rstrip("/").split("/").last()`. Write `value.method()` wherever the
static type selects the same callable as `Type.method(value)`; use `.car()`
and `.cdr()`. `cons(head, tail)` stays a free call. An explicit owner call
remains where it selects different semantics, such as an Array method
delegating to its Block implementation.

**EX-6** Reach members with `.` wherever x2c parsed the layout, native
headers included. Keep `->` for a layout x2c never sees, for a call through
a function-pointer field whose name is also a method, and inside `#define`
bodies. Keep `(*p).field` where `.` would need two pointer levels.

**EX-7** Use an established predicate when it has the intended domain:
`isalpha((unsigned char) ch)`. Keep an explicit ASCII range only when ASCII
is the contract.

**EX-8** Never nest ternaries. A conditional expression chooses between two
plain values.

**EX-9** Destructure a trusted small fixed shape flatly:
`Var (tag, type, body) = node;`. Use `match`, `assoc`, or an explicit test
for a conditional shape or an association lookup.

**EX-10** Build a forward sequence of unknown length in a transient Array
and convert once: `statements.list_free()`. Use `cons` only for a
newest-first sequence or a shared suffix. Never prepend in one phase and
reverse in a later one.

**EX-11** Consolidate adjacent `puts` or `fputs(..., stdout)` calls that
emit one static block into one multiline literal, with `$dedent` for
indented source. Compare the emitted bytes; `puts` adds a newline and
`fputs` does not. Keep separate calls when the output is conditional,
formatted, directed elsewhere, or clearer as distinct records.

## Functions and families

### Functions

**FN-1** A function does one job at one level of abstraction, and its body
reads as a sequence of named steps. If its one-sentence purpose needs
"and", split it.

**FN-2** Aim for 3 to 25 lines. A function over 40 lines is a defect unless
it is a table or a dispatcher whose actions are each one line. Patterns
may wrap to fit the line width. A one-use
function that owns no name, failure spelling, cleanup, or concept is also a
defect: inline it.

**FN-3** A dispatcher only dispatches. Each `match` or `switch` action is
one line that calls a named step. Patterns may wrap to fit the line width;
an action over three lines moves into a step.
Shared error handling at the end of a dispatcher has one owner, never a
`goto` from many arms.

**FN-4** Keep one dispatcher per grammar. Never split a dispatcher into a
chain of partial dispatchers that pass a `matched` flag; one `match` with
one-line actions is in band at any length. Wrapped patterns do not change
that exception.

**FN-5** Keep nesting at depth 3 or less, counting the body as 1; depth 5
is a defect. Flatten with guards, early returns, `continue`, and steps.

**FN-6** Keep parameters at four or fewer; seven is a defect. A parameter or
local that steers later control flow becomes two functions or an early
return.

**FN-7** Use an expression body `=>` when the whole function is one valued
return. Keep braces for declarations, control flow, several statements, or
an interior comment.

**FN-8** Declare `T &name` for a parameter through which the callee reads
and writes one live object for the call. Use `T &?` for an optional alias
the callee tests before use. Keep `T *` for retained addresses, indexed
storage, buffers, callbacks, C signatures, and published signatures whose
callers would change. References are parameters only; never fields,
locals, or returns.

**FN-9** Pass a small read-only record by value when a copy is the
contract. Borrow it when updates must reach the caller or the copy is
unnecessary.

**FN-10** Return one result surface per operation. Return the value and let
`void` or `NULL` carry absence when the sentinel cannot occur in the
success domain. Never keep a void adapter that only discards a status, and
never split a result across an out-parameter and a status when one return
would carry it. Reserve `try_` for real presence, exhaustion, or
traversal results.

**FN-11** Give each kind of incidental work one place: validation,
diagnostics, scope switching, save and restore, conversion, bookkeeping.
That place is an existing owner, a helper, a system macro, or a section.
Code that repeats an existing owner's work calls the owner; when that owner
is static in another unit, move it to the unit that owns the concept.

**FN-12** Write a recursive-descent parser in grammar order: parse the left
operand, test or expect the punctuation, recurse, and return the List. Use
one recursive function per production or precedence level. Use stacks,
queues, and request records only for state the grammar cannot express.
Keep token consumption and source-order scope changes in the parser and
hand the canonical List to the operation that owns its meaning.

**FN-13** Keep lambdas small: an expression lambda for a short operation, a
block lambda for a few locals or a `defer`. Move a growing lambda to a named
function with explicit state.

### Families and records

**FA-1** Keep a family of functions together, in the order of the
dispatcher that calls them, with the same parameter order and layout. A
family of one-line functions forms an aligned table.

**FA-2** Shared context is one value. Seven or more parameters, or a group
of parameters passed through several steps, becomes a private record whose
steps are methods, `Record.step(Record &r, ...)`, or the receiver of
`Type._helper` methods. Declare the record as a value in the operation that
owns it and borrow it through `&` receivers.

**FA-3** A record must own its steps. A record whose fields are copied into
locals on entry is a parameter list; return it to parameters. A record never
mirrors another object's fields; keep and pass the original. One concept
has one record.

**FA-4** Put a state-bearing private helper on its dominant receiver as
`Type._step`; keep a stateless helper free as `_snake_case`. Never move a
function only to gain dot syntax.

**FA-5** A stanza of three or more lines that repeats three or more times
gets one owner: a helper, a table, a field list, or a macro. The owner must
hold a fact: an algorithm, a failure spelling, a cleanup, or a policy. A
macro that abbreviates two statements is not an owner. Never merge code
whose ownership, identity, lifetime, failure, or side effects differ; if
unifying needs modes or callbacks, keep the paths separate.

**FA-6** Replace a run of three or more parallel statements that differ
only in a literal or a field name with a table or a `foreach` over rows.
The table is the owner FA-5 asks for, because it holds the facts. In the
compiler, `$copy_fields` from `src/fields.xmacro` states a field list.
Replace parallel switches or sets over one vocabulary with one ledger row
per member.

**FA-7** Delete a forwarding chain (wrapper, router, adapter, callback,
coordinator) that owns no policy, transformation, lifetime, failure, or
representation boundary, and call the owner directly. Count the whole
chain as one candidate. Delete trivial getters and setters too; keep an
accessor that is the enforcement site or protects a representation.

**FA-8** Delete a private language whose users translate back to an existing
value: a private enum, mode, schema, registry, or validator.

**FA-9** Delete a family of validators that re-check shapes the pipeline
already builds, together with their state, hooks, diagnostics, and
fixtures. Never replace one with a shorter validator or a catch-all arm.

## Files and modules

### Files

**FI-1** A file has one subject, stated in its header. Aim for 200 to 1,200
lines. A file over 1,500 lines triggers a review; size alone never orders a
split (MO-3).

**FI-2** Begin with the module header: `/*  name.x -- purpose`, the
copyright line when the file has one, and normally one short paragraph
stating what the module owns and which representation, phase, lifetime, or
compatibility boundary a reader would otherwise miss. A second paragraph is
for a separate correctness constraint. A header never holds a function
catalog, a tutorial, history, or a second copy of a contract owned
elsewhere.

**FI-3** Keep the prologue order: header; `#pragma once` in a module other
modules include; includes needed by public declarations; public types and
declarations; `#pragma private`; private system and repository includes;
private representation, state, and definitions. Move a declaration across
`#pragma private` only to change its visibility.

**FI-4** Order the file so it reads top to bottom: representation and
owner state; the central operation; the concepts it uses, in the order it
uses them, one section each; incidental work; lifecycle and public entry
points. Inside a section, the main function comes first and its helpers
follow in call order. Macros and types precede their first use.

**FI-5** Open each section with a plain lower-case label, `// file walks`.
A concept that needs more gets up to three sentences in one block comment
that starts with the label: `/* file walks`, a blank line, the sentences.
Aim for 3 to 12 functions per section; a section over 400 lines or with two
concepts splits. Never use rulers, all-capital labels, or a table of
contents made of comments.

**FI-6** Write no function forward declarations in ordinary source, `src/`
included. In `lib/`, keep a declaration only for true co-recursion,
for a literal prototype that collection must see before expansion, or for a
unit macro that reads top-level Lisp from its own file; state a non-obvious
reason beside it.

**FI-7** Delete dead code: uncalled private functions, unreachable branches,
`return` after a non-returning call, and checks of established facts. Git is
the archive. Before deleting, search callers across `src lib commands
packages tools etc unittest examples`, macro templates, compile-time Lisp,
protocol hooks, and function-pointer uses.

### Comments and prose

**CM-1** Choose the narrowest form: `/* */` for the module header, a
multi-line contract, or a diagram; `/** */` for published library API and
the compiler's provisional API only; `//` for a short local reason, a
section label, or a table annotation; a trailing
`//` only for a short label that helps compare rows. One thought is one
comment; never stretch it across many `//` lines.

**CM-2** Place a local comment directly before the decision it qualifies
and state the current reason and consequence. Never narrate the next line,
restate a name, or label obvious steps.

**CM-3** Comment a function only when its contract is narrower or stranger
than its name and signature: a proof boundary, a producer guarantee, cache
identity, rollback, lifetime, ordering, or why an alternative is invalid.
An obvious helper gets no comment.

**CM-4** Comments describe the present. Never leave `TODO`, `FIXME`, `BUG`,
history ("moved verbatim", "added after"), stale `file:line` references,
first-person narration, or unexplained "optimized", "important", or
"special case". Put unfinished work in `plans/`; state a remaining
constraint as a current fact.

**CM-5** A `/** */` comment sits directly above a published definition with
no blank line. Its first sentence stands alone as the index summary. Keep it
on one line when it fits; otherwise put `*/` on its own line. Document
observable behavior the signature does not carry: ownership, borrowing,
lifetime, mutation, identity, ordering, laziness, sentinels, failure
atomicity, raised causes, surprising complexity, callback retention, and,
for compiler methods, the required token, AST, or type shape. A public type
comment states purpose, valid state, ownership, and callback rules. A
non-static `src/` callable whose name has no leading `_` and no `__` is
future-public and requires one. Never infer a guarantee from a name alone.
Never repeat parameter names, types, or module membership; never use
`@param` or `@return` tags;
never put `/**` on a static helper or in a module the library manifest
marks `contract` or `internal`. [docs/AGENTS.md](../docs/AGENTS.md) owns
the generator rules.

**CM-6** Use a trailing field comment only for a short parallel annotation
in a dense representation. Never annotate what the field name says. Move a
long field contract above the fields.

**CM-7** State a shared invariant once, beside its owner: a representation
invariant beside the type, a lifetime owner at the surprising allocation.
If many places need the same explanation, the invariant lacks an owner.

**CM-8** Write comments, guides, plans, diagnostics, and commit messages as
literal statements. Put the fact first and name the owner, constraint,
action, or consequence. Leave out metaphor, preamble ("it is important to
note"), persuasion ("clearly", "simply"), praise ("robust"),
negative-then-reversal constructions, closing contrasts such as ", not X"
or "rather than", and the words "deliberately", "honest", and "on
purpose". Give agency only to actors: a type, table, or check does not
name, know, or refuse anything. Spell the language `x2c`.

### Names

**NM-1** Use `Type.method` for a public operation owned by `Type`,
`Type._helper` for a private step on one receiver, `_snake_case` for a
private stateless helper, `snake_case` for locals and parameters,
`UPPER_CASE` for constants and enumerators, and bare PascalCase for types
and private records.

**NM-2** Name the subject parameter with the first letter of its type
(`Compiler c`, `Emitter &e`) when the longer name would wrap lines;
otherwise either name is fine. Repeat the letter if it is taken. A
symmetric operation such as `String.add(String left, String right)` has no
single subject. A private
record's Compiler field is `c`.

**NM-3** A name's length follows its scope: one or two words for a local,
two or three for a helper. A helper omits what its file or section already
says. A name of 25 or more characters, measured without its `Type.` owner,
needs a public contract that fixes it.

**NM-4** One concept has one name across compiler and runtime. The shared
role names, and the only abbreviations, are in the
[glossary](#appendix-b-role-names). Never use `tmp`, `data`, `result`, or
`value` for a role that stays ambiguous across a nontrivial function.
Locals used only to save and restore state become `$let`, including
`old_`, `saved_`, and `previous_` locals with that role.

**NM-5** Name a helper for the semantic action it performs. Avoid
`process`, `handle`, `request`, `do`, and `check` as whole names.

**NM-6** Use an `x2c_*` name only for the intentional C interface: functions
generated code calls, native callers, and process setup. Ordinary public
operations are type methods; private helpers are `static`. An `x2c_*` name
below `#pragma private` still leaks into generated headers. Verify the
generated-code and native callers of a retained C entry before renaming it.
The `builtin_*` functions in `src/builtins.x` stay non-static because
`src/cleanup.x` calls the lowering slot `builtin_try_cleanup_placement`
and `src/macros.x` calls the registry `builtin_targets` across units.
Making the slot static fails native linking; making the registry static
fails translation of `src/macros.x`.

### Module sets

**MO-1** Put a contract where it can be enforced completely. A module
exposes a small public surface above `#pragma private`; implementation and
private dependencies go below it. Include only the public modules the
public declarations need.

**MO-2** Keep `#pragma once` only in compiler and runtime modules that other
modules include, because `--cpp-symbols` and `--live-symbols` hand their
co-recursive include graph to the host preprocessor. Tests, examples,
packages, programs, and units nothing includes omit it unless their own
`.x` includes form a cycle.

**MO-3** Split a file only along an owner boundary: the new unit has a
distinct owner, depends on the rest in one direction, and has its own tests.
Measure each candidate boundary by the private helpers that would cross it
in each direction. A helper that crosses becomes a method of the owner that
establishes its fact, never a new `x2c_*` export. Never create a file only
to shorten another.

**MO-4** Land a split or a reordering as a pure move with no edits inside
the moved text, then a separate change that settles crossings, header, and
order.

**MO-5** Cross-phase helpers belong to the phase that establishes their
contract. Runtime modules never include compiler modules, and runtime code
never calls back into compiler knowledge of ASTs or code generation.

**MO-6** Put macro definitions two or more modules share in an `.xmacro`
beside them; each consumer imports it. An `.xmacro` is its own module kind,
never a header. Import a large ledger only in a unit nothing includes, and
declare its tables `extern` elsewhere.

**MO-7** Before creating a module or compatibility layer, check the
philosophy ledger and the module catalog. Strengthen the existing owner
before adding another place that partially enforces the same rule.

## Values, types, and interop

The language spans a continuum from native C values through typed x2c
values and `Var` to compile-time values. Each crossing has one owner.

**VT-1** Keep native values native. Use C scalars, pointers, structs,
unions, and enums when the type is known at compile time. Use `Var` only
for heterogeneous elements, Map keys and values, Error details, values whose
tag the code inspects or reports, and boundaries with no target type such as
variadic calls and generic callbacks.

**VT-2** Never declare a `Var` local only to pass a typed value to a `Var`
parameter. Pass the typed value.

**VT-3** After an explicit unboxing of untrusted or mixed data, test the tag
or the result; keep an explicit `is T` check only where the incoming `Var`
is dynamic. Use typed readers (`Var.int`) over raw payload readers
(`Var.integer`) unless a silent low-level decode is intended.

**VT-4** Choose collections by mutation and identity: `List` for immutable
sequences with structural identity, `Array` for mutable indexed values and
scratch state, `Map` for keyed lookup, `Buffer` for building text, `String`
for canonical text, `Path` for filesystem locations. Wanting `list[i] = x`
means wanting an Array. An Array or Map hashes by identity, so never use one
as a key that should match by contents.

**VT-5** Use a Symbol for a closed vocabulary you wrote and an Atom for
names from outside the program. Keep a numeric enum where the number is the
point: storage indexes, arithmetic, packed fields, integer ABIs, zero
initialization. When a closed vocabulary needs membership, a dense index,
or ordered iteration, declare one `SymbolSet` literal and add related facts
to the row its index selects.

**VT-6** Declare a record as a value when it belongs to one operation and has
no retained identity; update it through `T &` methods. Never add a pointer
typedef or a second local that only takes its address. Choose a pointer
representation only for shared or retained identity. A record copy is
shallow and transfers no ownership.

**VT-7** Write `class` when the type needs the generated bundle:
construction, boxing, equality and hashing, readable output, cleanup.
Write `typedef` for a type that is never boxed, for function pointers,
enums, and unions, and for a native handle whose lifetime belongs to its
library. The first 30 classes boxed get direct `Var` rows; later classes
box through an overflow cell or record prefix, which costs a lookup.

**VT-8** Adopt a protocol only for one real contract whose operations have
the meanings the protocol requires. Put the adoption beside the type and its
converters, and check `--dump-conformance` before extending a protocol.
Never add a protocol whose generated methods only convert the receiver and
forward to an existing view; call that view.

**VT-9** Box a private record through `protocol Var(T)` beside the private
type with its conversion pair; never make a type public only to store it.
A typedef that inherits `List.var` or `Map.var` needs no adoption; a typed
view that defines its own conversion pair adopts `protocol Var(T) as List`
or `as Map`. For a caller-owned pointer that crosses a `Var` field, give the
pointer a private alias, define its conversions once, keep raw `.p64` access
inside them, and cast to the alias inside the call that requests `Var`.
Call the named reverse converter where the generic `Var`-to-pointer
conversion would otherwise win.

**VT-10** Never give an expression a static type that could disagree with
the type C assigns. Where x2c's model may differ, leave the expression
untyped and let the C compiler decide.

**VT-11** In compiler code, represent types as Lists through the `Type`
owner in `src/type.x`: C words are Symbols, user names are Strings, as in
`("Point")`, `(struct "Tag")`, `(* "Point")`. Add a `Type.*` query instead
of building or decoding type Lists by hand.

**VT-12** Compile-time values cross into program code only through the
staging owner: a `$` call takes constants, captured syntax, Symbols, or
nested `$` calls, and returns code or a value with a `Var` form. Never
return a pointer, a borrowed handle, or a helper-process address.

## Lifetime and memory

**LT-1** Name the lifetime at the acquisition. Use `$auto` for an owned
local of a `Cleanup(T)` type, `$scope()` for a region of temporaries,
`$scope(&slot)` to allocate into a chosen Scope, `$let` to replace one
location for a block, and `$lock` to hold a Mutex. Use `defer` directly
only for a native release the runtime does not own, a conditional
acquisition or rollback, a consuming parameter, paired state that is not a
resource, or cleanup that writes a result.

**LT-2** Adopt `Cleanup(T)` beside a type that owns native storage, through
`$cleanup.by(T, release)` when one method releases it, so every caller can
write `$auto`. Never spell a release at each call site.

**LT-3** Choose scopes by lifetime. Do not create a scope for values whose
owner already provides the lifetime. Return a canonical value (`String`,
`List`, `Symbol`) across a scope boundary, or let the caller own the scope
and pass the slot down. Never let a value allocated in a region be
reachable after the region ends.

**LT-4** Keep each `defer` small and limited to releasing what the block
owns; never use it to swallow failures, never raise from cleanup, and never
`defer` the release of a handle the function returns.

**LT-5** Keep mutable storage owned by the object that mutates it, and
convert to an immutable List or String once, at the phase or API boundary
that promises a snapshot. Never maintain two live representations.

**LT-6** Never structurally mutate a Map while iterating it; collect keys
first before insertion, removal, or growth. Updating existing values does
not invalidate traversal.
Pass a `Block` handle across growth; never cache its byte pointer.

**LT-7** Bracket large temporary List and String construction with
`Pool.open` and `Pool.close` and promote survivors; use a `Context` when the
Scope, Error, and Match state must be bounded too.

**LT-8** Fix a region finding by rearranging the lifetime. In `src/` and
`lib/` every finding fails stage 1; a test or user program may keep one only
when the lifetime is arranged another way, said beside the code.

## Errors

**ER-1** Raise one structured Error at the code that first detects the
failure: `raise %(cause (key value) ...)`. Keep expected outcomes (end of
file, missing key, exhaustion, no match, unparsable number) in return
values or `try_*` status.

**ER-2** Choose the cause a handler would branch on, in this order:
callable shape, dynamic operation, resource or external operation, API
contract, then `<invariant>`. Use the most specific shared cause, and
`<malformed>` for invalid external text.

**ER-3** Put only values in details: Null, numbers, enums, Symbols, Atoms,
Strings, and Lists of those. Use the shared detail keys in
[DG-7](#diagnostics-and-messages).

**ER-4** A shared cause never returns to the raising call. Never check for
a return after valid allocation, growth, open, read, write, format, or
binding operations, after a raise, or after a report that does not return.
Fresh `[]` and `{}` need no null check. Reserve `$error.fallback` for
user-defined causes.

**ER-5** Keep checks for documented null inputs, absence, callbacks,
external input, I/O status that can return, overflow before an operation,
and deliberate public behavior.

**ER-6** Catch only where the code can recover or translate. Order arms
specific first; omit an arm that would only re-raise. Translate by raising a
new cause with the old one as detail. Copy matched details with
`Error.snapshot` when they must outlive the arm.

**ER-7** Every resource owner on a raising path has its cleanup in place
before the raising call (`$auto`, `$scope`, `defer`, or `finally`).

**ER-8** Never let an Error unwind through a C frame. In a callback, catch
at the boundary, snapshot what must survive, return a status the library
understands, and raise again in x2c. Verify which thread invokes each
callback; entering x2c from an arbitrary worker thread needs a proven runtime
guarantee. Make callback-only objects invalid outside the callback.

## Diagnostics and messages

**DG-1** Put diagnostic wording in named report macros near their callers:
`$report.<category>.<case>(c, ...)` for compiler and driver reports, in a
group at the top of the file or a sibling `*-reports.xmacro`; one
`$error.<area>.<condition>` macro per runtime, package, or command
condition in the raising unit's `*-errors.xmacro`, with `$refusal`,
`$decline`, and `$reason` for those verbs. A short structured raise such as
`raise %(bad-state (operation "Pool.close"));` stays at its call site.
Never dispatch diagnostics on string keys at compile time.

**DG-2** Keep guards, severity selection, collection, and cleanup in the
reporting owner. The submitting operation chooses the severity; the code is
a broad boundary category such as `<parse>`, `<type>`, `<macro>`, or
`<region>`.

**DG-3** Report at the source token that owns the problem. A compiler
location has exactly `file`, `line`, `column`, `length`, and `position`.
Constructed syntax with no physical token gets no invented location.

**DG-4** Write a compiler message as one lower-case clause with no final
period. State what was expected or the rule that was broken, in present
tense: "expected ';', '{', or '=>'", "package name must be a C identifier",
"top-level decorators are not supported". Quote source spellings in single
quotes. Never blame the user ("illegal", "bad"), and never say only
"invalid X"; say what X must be.

**DG-5** Put variable facts in notes as `"key:" value` pairs, and add a note
with the supported form when exactly one fix applies:
`"module initialization: void TYPE.initialize(void)"`.

**DG-6** Stop at one error per compile by default. Recover in `full_parse`
by skipping the failed top-level declaration; restore mode state with
`$let` or `defer`; bracket a speculative parse with `Diagnostics.hold` and
`release`.

**DG-7** Use one detail vocabulary for runtime Errors: `operation` for the
public operation as `"Type.method"`, `op` for an operator, `reason` for a
short lower-case reason, `index`, `key`, `want`, `actual`, `expected`,
`path`, `offset`, `line`, `column`, `sig`, `cause` for a lower-level cause,
`library`, `code`, `message` for a native library's own status, and `note`,
`at`, `check` for invariant failures.

**DG-8** Report macro misuse at the invocation with `x2c_diagnostic_fail`
(fatal) or `x2c_diagnostic_warn`, with notes. Add a diagnostic only under
PR-4; an unmatched internal shape may fall through to the existing path.

**DG-9** Fix a compiler warning at its cause: remove the conversion a
`conversion` warning reports, unquote the word a `literal` warning reports.
Stages from 1 onward build with `--fatal-warnings`; never add a
suppression.

## Macros, meta functions, and compile-time Lisp

**MA-1** Choose the smallest tool: a function for runtime computation; a
`meta` function for compile-time calculation; a protocol for shared typed
behavior; a `delegate` field for forwarding to a contained value; `with`
for repeated substitution in one block; a macro for a repeated source shape
whose call reads more clearly than its expansion; a decorator for an
orthogonal wrapper on one recognizable target; a ledger when the same rows
drive several artifacts. Write direct source when generation hides more
than it removes.

**MA-2** A macro earns its keep only when its definition, helpers, imports,
ledgers, and invocations together are a net improvement. Each invocation
states every policy-bearing type, public name, status, and mode. Its
generated names are hygienic unless a public spelling is intended; its
diagnostics point to useful source; normal and `--live-symbols` translation
agree; its generated C stays inspectable; and hot-path cost is unchanged or
measured. Generated private definitions are `static inline`, never plain
`inline`. Hiding a repeated two-statement prefix never justifies a macro or
counts as simplification. Never flatten distinct contracts behind flags,
make one-use data tables, or generate a Map to avoid a small direct
switch.

**MA-3** Macros capture no bindings. A name the body declares, and its
literal references, are private to that expansion; every argument and every
free name resolves by spelling where the expansion lands. To reach a
file-scope name, list it with `using` at the start of the braced body or
after an `Expression` macro's signature. A `Name` argument is a
spelling. Never reintroduce stored binding identities.

**MA-4** Declare each hole with its most specific kind, such as `Expr`, `Name`,
`Type`, `Stmt`, or `Decl`. Qualify a shared macro name (`$project.guard`);
never use the reserved `x2c.` or `lisp.` namespaces. A statement macro used as
a body produces exactly one statement.

**MA-5** Build code as the code it builds. In order of preference: a named
macro applied from a meta function when one shape repeats at several sites;
a quotation `$!( )`, `$!{ }`, or `$!Unit{ }`; holes from locals; `${expr}`
holes for computed parts (call helpers as `${f(x)}`, never as `$f(x)` slots
unless a template application is intended); `x2c_ident` locals for a name
shared across quotations; a typed quotation `$!T{ }` when an operation reads
the type before the code lands; a retained rebuild around bound children.
A hand-built `%(...)` List comes last.

**MA-6** Keep a hand-built `%(...)` List only for patterns and data rows,
parser productions from parsed children, binder output, forms with no
source spelling, typed inner nodes, code queued before it can be bound, and
measured hot paths. Never parse code from a String.

**MA-7** Recognize a source form with its grammar macro when one exists:
`case if_then(?condition, ?ontrue):`. Shared input forms live in
`src/grammar.xmacro`. Keep raw `case %(...)` patterns for internal nodes,
typed shells, resolved forms, and measured hot paths.

**MA-8** A lowering recognizes its input with a source form, gathers facts
in ordinary named functions, and builds its output with one template beside
it. It fits on one screen. A loop or a choice among C shapes may go in a
slot function or in ordinary code around quotations; choose the clearer.
No `code-value` literal appears outside a producer. Compile-time code may
construct any canonical AST; ordinary operations
accept it by structure. Never authenticate syntax by origin or add a second
validator.

**MA-9** Write compile-time algorithms as `meta` x2c. Mark every function a
meta body calls `meta`. Keep compile-time state in `meta static` and make
each imported compile-time effect idempotent per unit. A project meta
function receives compiler facts as parameters (`TypeInfo`, `Source`,
captured syntax) and never queries compiler state.

**MA-10** Use a decorator to place checking, tracing, or a checked foreign
binding beside the item it affects. Never use one to generate sibling
functions, to register types, to declare protocol participation, or to
hide publication, fallback, or ownership policy.

**MA-11** Verify that symbol collection, generated headers, the module
catalog, and the API reference understand any macro that generates public
declarations. Put protocol-relevant prototypes before the adoption that
needs them.

**LI-1** Write no new compile-time algorithm in Lisp. Lisp remains for the
evaluator core, the shared initial environment, the name tables that bind
Lisp names to x2c operations, and the REPL. Port an algorithm that does not
need to be Lisp to a `meta` function.

**LI-2** Use `$(import "...")` for macro imports and `$(...)` only to call
existing Lisp or change the Lisp session. Prefer `x2c_ident(...)` in meta
code to `$(x2c.ident ...)`, and `$f(...)` meta calls to Lisp helpers.

**LI-3** Keep Lisp surfaces thin: a binding file names an x2c operation and
checks arguments only where a Lisp-facing diagnostic needs it. Name
supported SDK operations `x2c.<noun>.<verb>` and internal primitives with
the single reserved `_x2c.` prefix.

**LI-4** Ship a library's Lisp bindings behind one public installer
(`RegexpLisp.install(Lisp)`) built from `$lisp.binding` groups. Bindings take
and return values Lisp can inspect; opaque native objects stay on the x2c
path.

## Compiler architecture

**AR-1** Keep the pipeline in this order, each phase consuming the
previous phase's documented AST: tokenize (`lib/tokenizer.x`) -> collect
declarations (`collect.x`, `.xi` interfaces) -> parse, bind, and type
(`parse.x`, `expressions.x`, `statements.x`, `literals.x`, `type.x`, with
macro expansion and compile-time code inside) -> region analysis
(`regions.x`) -> lowering to a fixed point (`transform.x`, `callables.x`,
`cleanup.x`) -> generation (`generate.x`, `cache.x`) -> emission (`emit.x`)
-> formatting (`format.x`). Put a behavior in the phase whose contract it
changes.

**AR-2** Parsing preserves source order and attaches types as the tree is
built: every expression is `(expr TYPE CONTENT)`. Later phases preserve
existing types and bind newly constructed syntax through the same typing
owner.

**AR-3** Transforms own runtime crossings and normalization. A transform
helper rewrites its node and returns the replacement; the fixed-point driver
processes the returned children. Fold a new lowering step into the driver;
never add an ordered pass list or a struct IR.

**AR-4** Emission prints the normalized shape and repairs nothing. A
semantic decision moves into a lowering with a template, or is recorded as
a backend exception with its reason.

**AR-5** Generated output is deterministic: the same input yields the same
bytes, with no address-dependent order and no generated-name counter shared
across units. No tracked file is both input and output of a build stage.

**AR-6** Change only the boundaries a feature crosses, in order: tokenizer
for new lexical structure, one parser owner, the type owner for a new type
fact, the transform, generate, or emit owner, a runtime owner for a new
primitive, then the smallest fixture per changed boundary. Never add a
downstream workaround.

**AR-7** The compiler uses the same runtime as user programs. Reach an
existing runtime owner from the compiler (`Path.make_dirs`) instead of
writing a compiler-local copy.

**AR-8** Diagnostics retain positioned tokens and origin ancestry; emission
consumes the normalized AST. No later phase rescans String contents or
replaces the user's source with a declaration stream.

**AR-9** Never hand-edit `bootstrap/`, `lib/x2c.x`, or generated
documentation; regenerate through the documented targets. A new compiler
capability reaches the seed before callers that need it compile.

## Runtime library

**RT-1** Runtime files are capability owners: lifetime, values,
conversion, dispatch, canonical immutables, mutable storage, traversal,
matching, errors, system boundaries, threads, scanners, native callables.
Never build a wrapper hierarchy over them.

**RT-2** Establish canonical values once at their constructor or interning
boundary; consumers rely on identity.

**RT-3** A status-bearing operation owns recoverable failure. A convenience
adapter may fail fast but delegates to it, never copying its mutation
logic. `void` stays out of collections and iterator domains.

**RT-4** Index and slice through the shared normalizers; a new indexable
type reuses them.

**RT-5** Share one implementation across typed families through an
imported generic `.xmacro` only when the families obey the same operation,
failure, representation, and lifetime rules. Keep each family's hashing,
equality, layout, boxing, and error policy visible as inputs.

**RT-6** Treat everything reachable through the prelude as public surface,
including struct fields and typedefs. Keep optional modules out of the
prelude; `docs/library-manifest.txt` owns module visibility and
`docs/library-api-tiers.txt` owns callable tiers.

## Packages and public API

**PK-1** Start a package from the tasks a developer brings to that kind of
library, each proven by a small program through the imported surface. A
task that needs the raw API or a hand-written loop is a gap.

**PK-2** Give one obvious ordinary path in x2c values plus the complete
pinned raw C API under its real names, reached through a small checked shim
header. Never copy upstream declarations or add forwarding functions. A
wrapper over a foreign handle publishes `object.native()`.

**PK-3** Before designing types, list each native value's obligations:
allocation and release, pointer and length, borrowed storage and
invalidation, status versus absence, callbacks and their threads. Decide for
each whether the x2c path copies, borrows with a lifetime, converts, or stays
native. Copy a result a later native call invalidates; own a large or
ordered native graph and hand out checked borrowed views.

**PK-4** Make release accept NULL, be idempotent, and return NULL so the
caller clears its handle in one expression. Adopt `Cleanup(T)`, and
make lossy conversion explicit and named. Keep paths x2c cannot represent,
such as embedded NUL, on the raw API.

**PK-5** Raise one structured Error carrying the library name, the operation,
the library's own code and message, and the useful location; a shared raising
helper takes its caller's operation name. Keep expected absence on the return
value.

**PK-6** Lay out a package as `packages/<name>/` with `src/<name>.x` as its
entry unit, public surface above `#pragma private`, and names spelled bare;
consumers write `import "<name>"`. Export a package's macros through
`export $(import "...")` in the entry unit. Add an operator, protocol, or
wrapper type only when it removes work from the application. An operator
that creates native resources gives its intermediate results automatic
cleanup.

**PK-7** Ship a short application that fits on a screen first and a broader
application second; Gary accepts the developer experience before a package
claims completion.

**PK-8** Public API changes need authorization. A public operation or
documented capability with no in-tree caller is not waste. Test through the
real public operation; never publish a helper for a test.

## Tests, examples, and samples

**TE-1** Suites are `unittest/test-<feature>.x` with `static void` tests.
Call `EXPECT_*` as bare statements; never thread an `ok` flag, and guard
with `if (!EXPECT_X(...)) return;` only when continuing would be unsafe.
Use `$test.scoped();` for a whole-function Scope, `$test.run(name)` when
the label is the function name, an explicit `TestHarness_run` for a
descriptive label, and `$test.suite` to register a suite. Register a
deliberate deferral with `TestHarness_skip(name, reason)`. Restore mutable
globals in `finally` before freeing their fixtures.

**TE-2** Prove a defect fix with a test that fails before and passes after.
Test count and patch size are not targets.

**TE-3** A compiler fixture asserts only the phase boundaries it owns,
keeps its program small, and compiles without C warnings unless it declares
them. Normal checks never rewrite expectations.

**TE-4** Delete a test written only for a deleted mechanism together with
the mechanism; keep tests of valid behavior and retained public failures.

**TE-5** Examples and book samples follow this standard; they teach by
example. A sample that shows a non-idiomatic form is a defect in the
sample.

## Hot paths

A hot path is code a benchmark or profile shows on the critical path:
runtime boxing, conversion, dispatch, scanning, interning, matching, and the
compiler's recursive walkers.

**HP-1** Change a hot path only with a paired measurement: retired
instructions under `/usr/bin/time -l`, base and candidate run alternately
from checkout paths of equal length. Prepare each tree with
`make bootstrap-refresh && make build-safe`. Report the delta and its
supported cause. The checkpoint remains advisory during the baseline period;
[performance checkpoints](performance-checkpoints.md) owns the method and
acceptance policy.

**HP-2** On a hot path, measure additions of `defer`, `$scope`, `$let`,
`$auto`, allocation, locks, passes, or calls before accepting them. An
absolute ban or a new acceptance requirement is a proposal for Gary's
review, not a current publication gate.

**HP-3** Keep a hot helper foldable: no fallback `return` after a switch
that makes clang compute every arm, no raise inside a function that should
inline (move it to a cold helper that takes Symbols), constant widths in
calls that should unroll, and no String literal argument that adds a lazy
interning guard.

**HP-4** In a recursive walker, keep an arm that holds `$let` or `defer`
inline unless the depth fixtures pass; each helper frame costs C stack per
level.

**HP-5** When a measured cost forces the base shape back, keep it and state
the measured cost in a comment beside it.

## Finding bad code

Each signal below is a candidate for review. A lint `violation` is
mechanical; a `candidate` needs the source read before acting. A zero
coverage count, a low caller count, size, or recency is a candidate, never
proof. Tool codes are `x2c lint` codes unless named otherwise.

A local exception uses a standalone line comment directly before the
finding's source line (CM-2):

```x2c
// lint: allow CODE RULE-ID: reason
```

The code must name the finding, the rule ID must match that code's rule,
and the reason must contain text. A matching finding and its proposed fix
are suppressed. Other findings on that line remain visible. Malformed
comments, wrong rule IDs, and allowances without a matching finding for a
selected code report `bad-suppression`, a CM-2 violation. Text in strings
and block comments does not declare an allowance. An allowance for a code
that is not selected is not checked for a matching finding.
`bad-suppression` itself cannot be suppressed.

### Shape signals

| Signal | Threshold | Rules | Tool |
| --- | --- | --- | --- |
| Function length | over 40 lines (band 3-25) | FN-2 | `long-function` (>40) |
| Nesting depth | 5 or more, body counts 1 | FN-5 | `deep-nesting` |
| Parameters | 7 or more (band up to 4) | FN-6, FA-2 | `long-parameter-list` |
| Name length | 25 or more characters | NM-3 | `long-name` |
| Section | over 400 lines or two concepts | FI-5 | `long-section` (>400) |
| File | over 1,500 lines | FI-1, MO-3 | `long-file` |
| Neighbor disproportion | element far larger than peers | PR-8 | none |
| Dispatcher action | over 3 lines | FN-3 | `long-dispatch-arm` (counts the whole arm; review wrapped patterns) |
| Purpose sentence needs "and" | judgment | FN-1 | review |

### Statement and layout signals

| Signal | Rules | Tool |
| --- | --- | --- |
| width, tab, trailing space, non-ASCII | LY-1, LY-2 | `over-width`, `tab`, `trailing-whitespace`, `non-ascii` |
| call or signature split although it fits | LY-3 | `wrapped-opening-line`, `horizontal-form` |
| continuation aligned to `(`; lone closer | LY-4 | `continuation-indent`, `standalone-closer` |
| operator spacing | LY-5 | `operator-spacing` (partial) |
| stacked blank lines | LY-6 | `blank-line-stack` |
| braces on one statement | ST-1 | `one-statement-braces` |
| `} else` | ST-1 | `same-line-else` |
| short construct spread over lines | ST-2 | `short-control-flow` |
| `!(x is T)` | ST-5 | `negated-is` |
| declare then assign | ST-7 | `deferred-initialization` |
| repeated stable accessor | ST-10 | `repeated-accessor` |
| `.contains(` | ST-11 | `contains-in` (proven fix) |
| `if ((x = f()))` | ST-4 | `assignment-condition` |
| nested ternary | EX-8 | none |
| `String.new("")` | EX-1 | `empty-constructor` |
| `Array.new()`, `Map.new()` | EX-1 | `empty-constructor` |
| `%"..."` without interpolation | EX-3 | `plain-string` (proven fix) |
| converter at a converting destination | EX-4 | compiler `conversion` warning |
| `p->x` on a parsed layout | EX-6 | `member-arrow` (proven fix) |
| `Type.method(x)` where `x.method()` fits | EX-5 | none |
| `cons` then `reverse` | EX-10 | none |
| adjacent static `puts` | EX-11 | `constant-output-run` |
| one-return body in braces | FN-7 | `expression-body` (proven fix) |
| static `T *` parameter used as one object | FN-8 | `reference-parameter` |

### Ownership and structure signals

| Signal | Rules | Tool |
| --- | --- | --- |
| same predicate or raise in several callers of one producer | PR-2 | `x2c graph`, review |
| stanza of 3+ lines repeated 3+ times | FA-5 | `repeated-routes`, `duplicate-function-body`, `x2c graph clones` |
| parallel statements differing in one literal | FA-6 | `enum-table-switch`, `constant-output-run` |
| fields copied into locals or statics | FA-3 | `struct-copy` |
| private type translated back to an existing value | FA-8 | `internal-type` |
| one-use wrapper; forwarding chain | FN-2, FA-7 | none (graph has the data) |
| uncalled static function | FI-7 | `uncalled-static-function` |
| acquire with a hand-written release | LT-1 | `lifecycle-pair`, `manual-bookkeeping` |
| `old_`, `saved_`, `previous_` locals | NM-4 | `saved-local` |
| subject parameter name that wraps lines | NM-2 | `subject-parameter-name` |
| forward declaration | FI-6 | `forward-declaration`, `src-forward-declaration`, `runtime-forward-declaration`, `same-file-forward-declaration` |
| non-static `x2c_*` without a C caller | NM-6 | none |
| backward private include between phases | MO-5, AR-1 | none |

### Validation signals

| Signal | Rules | Tool |
| --- | --- | --- |
| `return` after a non-returning report or raise | ER-4 | `return-after-report-error`, `return-after-raise` |
| `$error.fallback` on a shared cause | ER-4 | `fallback-shared-cause` |
| null test on fresh `[]` or `{}`; growth confirmation | ER-4 | `fresh-literal-null-guard`, `growth-check` |
| guard on a shape the producer guarantees | PR-4 | `silent-shape-guard` |
| diagnostics built on shape checks | PR-4, DG-8 | `shape-diagnostics`, `validator-diagnostics`, `validator-shape` |
| recursive checker; validator group | FA-9 | `recursive-validator`, `validation-framework` |
| `List.match` then `assoc` on a static pattern | MA-7 | `static-match-capture` |
| `car() == <a> \|\| car() == <b>` chains | MA-7 | `manual-shape-checks` |

Calibrated trust boundaries keep their checks: macro SDK argument checks,
`Ast.try_sequence`, `Compiler.rebuild_protocols`, the artifact readers in
`collect.x`, and the transforms that distinguish lowered from unlowered
forms. A source `match` in a function does not make that function's other
guards trustworthy.

### Comment and prose signals

| Signal | Rules | Tool |
| --- | --- | --- |
| history, `TODO`, null-guard narration | CM-4, CM-2 | `comment-history`, `comment-null-guard` |
| comment restates a name or the next line | CM-2 | `restates-name`, `restates-code`, `narration` |
| ruler or catalog label | FI-5 | `decorated-ruler`, `section-label`, `catalog-label` |
| header that inventories functions | FI-2 | `module-header-inventory` |
| repeated paragraph | CM-7 | `repeated-prose` |
| stock phrase | CM-8 | `prohibited-prose` (partial) |
| invalid local allowance | CM-2 | `bad-suppression` |
| `/**` on static, detached, stacked, boilerplate, wrong tier | CM-5 | `doc-on-static`, `detached-doc`, `stacked-doc`, `doc-boilerplate`, `doc-comment-tier` |

### Macro, interop, and diagnostic signals

| Signal | Rules | Tool |
| --- | --- | --- |
| `x2c_expr_*` or `x2c_literal_*` builders whose result is not inspected before it is returned | MA-5 | none |
| a macro used once through `Macro shape = $m;` | MA-5 | none |
| raw `case %(` on a head with a grammar form | MA-7 | none |
| new `.xlisp` | LI-1 | none |
| `$(defun` in `src/` or `lib/` | LI-1 | `lisp-defun` |
| `$(x2c.ident` in meta code | LI-2 | `x2c-ident` |
| literal `report_error(` wording | DG-1 | `literal-report-error` |
| string-keyed diagnostic dispatch | DG-1 | none |
| `Var` local with one static type | VT-1 | none |
| protocol adoption whose members only forward | VT-8 | none |

`long-section` measures plain lower-case top-level line labels separated
from other text by blank lines. `uncalled-static-function` uses bound AST
references, including function values, and excludes spellings present
elsewhere in the input corpus. Computed names, protocols, native consumers,
and files outside that corpus still need review. The new codes are
candidates except `same-line-else`: its compiler and runtime census is
zero, so it is a violation.

The [adoption plan](../plans/x2c-code-standard.md) lists the detectors to
build for the rows marked "none", ordered by value and cost.

## Turning bad code into good code

A full beautification follows this order. Local cleanup keeps its selected
scope and does not require reshaping or reordering:

1. **Delete.** Remove dead code, checks of established facts, and machinery
   the language or an existing owner makes unnecessary (PR-3, FI-7, ER-4).
2. **Reuse.** Replace repeated work with calls to the existing owner, and
   give each remaining repeated fact one owner (PR-2, FA-5 to FA-8).
3. **Reshape.** Settle the file boundary, then split functions into named
   steps, group shared context into records, and make dispatch actions one
   line (MO-3, FN-1 to FN-6, FA-2, FA-3).
4. **Adopt idioms.** Use system macros, receivers, references, literals,
   quotations, and grammar forms (LT-1, EX-1 to EX-6, FN-8, MA-5, MA-7).
5. **Rename and reorder.** Apply the glossary, then put the file in reading
   order with section labels (NM-1 to NM-5, FI-4, FI-5).
6. **Comment pass.** Keep each comment that would lose a fact if deleted,
   compact it, and delete the rest (CM-1 to CM-8).

### Proof obligations

Select evidence for the task under its current skill and `AGENTS.md`. The
per-file stage comparison belongs to the existing beautification workflow;
this standard does not extend it to all cleanup. Any broader requirement needs
Gary's approval under the process ceiling.

| Change | Proof |
| --- | --- |
| Neutral respelling, rename, reorder, receiver, `=>`, `in`, `.` | compare affected generated output before and after where needed; `stage-diff-0` compares bootstrap with stage 0, not the pre-edit tree |
| Compiler beautification | existing beautify proof: `make stage-1 && make stage-diff-1` once per file; use relevant driver probes |
| A pure move | the multiset of non-blank lines is unchanged except section labels |
| Adopting `$auto`, `$let`, `$scope`, quotations | emission changes: refresh bootstrap through its target, then the focused fixtures and suites |
| Deletion of a check or mechanism | the observable result of valid input is unchanged; invalid input is still rejected before wrong output, corrupt state, or an unsafe crossing |
| Hot-path change | HP-1 paired instruction counts |
| Defect fix | TE-2 fail-before and pass-after |

Gary approved source reshapes that move retained macro-definition line
and byte positions to their reviewed new authored locations on 2026-10-05.
Diagnostic wording, origin ancestry, and all other behavior stay unchanged.

Never rebaseline a stage diff or a fixture to make a neutral rewrite pass;
a difference is a behavior change to fix or to report. Report each neutral
tweak a rewrite makes, such as `$let` now restoring on an error exit.

### Procedures by task

- **Beautify one file**:
  [beautify-x2c-source](skills/beautify-x2c-source/SKILL.md) runs steps 1
  to 6 on one file with the proofs in the table above.
- **Clean local style and comments**:
  [clean-x2c-source](skills/clean-x2c-source/SKILL.md) applies idiom
  respellings, renames, and the comment pass, without reordering.
- **Remove machinery across files**:
  [simplify-x2c-source](skills/simplify-x2c-source/SKILL.md) runs steps 1
  and 2 across a connected slice, then reviews the diff for the strongest
  remaining opportunity.
- **Find redundant checks**:
  [find-redundant-validation](skills/find-redundant-validation/SKILL.md)
  ranks the validation signals without editing.
- **Find overengineering**:
  [find-x2c-overengineering](skills/find-x2c-overengineering/SKILL.md)
  queues candidates, and
  [investigate-x2c-overengineering][investigate] adjudicates one.
- **Replace a manual AST walk**: select a connected grammar family, list
  its accepted forms as patterns, draw the descent, rewrite the slice in one
  edit, and justify every remaining `car`, `cdr`, length, or tag test; see
  [AST patterns](replacing-manual-ast-walks-with-match.md).
- **Split a large file**: list subjects, count crossings per boundary,
  split only an owner boundary, move first, settle second (MO-3, MO-4).

[investigate]: skills/investigate-x2c-overengineering/SKILL.md

## Lessons from the 2026-09-17 to 2026-10-04 campaigns

These results set the rules above; the evidence is in the adoption plan.

- Splitting long functions into named steps on records cut `src/` functions
  over 40 lines from about 155 to 6, excluding generated `linked-meta.x`, and
  the stage diff proved each file unchanged. Files grew about 10%. The next
  review found helpers that scattered complete operations, and a follow-up
  inlined one-use helpers and shrank records. FN-2 and FA-3 carry both results.
- Chained sub-dispatchers with a `matched` flag were merged back into one
  `match` (+53/-119 lines). FN-4 records it.
- Helpers clang would not fold added instructions on runtime hot paths: +11 per
  integer read from a fallback `return 0`, and an interning guard on every fast
  add from a String literal argument. HP-3 records them.
- An extracted arm with `$let` in the recursive transform walk added a C frame
  per level and was put back inline. HP-4 records it.
- A string-keyed central diagnostic catalogue raised the clean stage-1 build
  from 10.04 s to 24.97 s and hid raises from lint. The final form is named
  report macros near their callers. DG-1 records it.
- Delegating a List reduction to the general iterator lost its constant-time
  null case until `62ab2c5f` restored it, and a measured 3x cost on pointer
  values blocked delegating `Var.fallback_repr`. PR-12 records it.
- Respellings that leave generated C byte-identical (`in`, `.`, receivers,
  `=>`, references, renames, reordering) cost nothing downstream; emission
  changes need a bootstrap refresh first. The proof table records it.

## Appendix A: decision tables

### Representation

| Situation | Use |
| --- | --- |
| type known at compile time | C scalar, pointer, struct, union, enum |
| record for one operation, no identity | value record with `T &` methods |
| shared or retained identity | pointer representation, `class X { ... } *;` |
| needs construction, boxing, equality, hashing, cleanup | `class` |
| typed view of a List or Map | `typedef List Row;`, plus `protocol Var(Row) as List;` when `Row` defines its own conversions |
| private record stored in a collection | `protocol Var(T)` beside the type |
| heterogeneous element, Map key or value, Error detail | `Var` |
| hot numeric loop | native types, packed typed Array |
| value needed at translation time | `meta` function, `$f(...)` |

### Collections and text

| Need | Use | Avoid |
| --- | --- | --- |
| AST, pattern, persistent sequence | `List` | Array |
| indexed mutation, stack, queue, scratch | `Array` | List rebuilds |
| keyed lookup, counting | `Map` | `assoc` scans |
| building text | `Buffer`, interpolation | `+` in a loop |
| closed names you wrote | Symbol, `SymbolSet` | hand switches |
| external names | Atom | Symbol |
| sequence built in a loop | Array, then `list_free()` | `cons` and `reverse` |

### Cleanup

| Need | Use |
| --- | --- |
| owned local of a `Cleanup(T)` type | `$auto(...)` |
| region of temporaries | `$scope()` |
| allocate into a chosen Scope | `$scope(&slot)` |
| replace a location for a block | `$let(place, value)` |
| hold a Mutex | `$lock(m)` |
| native release, rollback, result-writing cleanup | `defer` |
| cleanup belonging to an existing `try` | `finally` |
| handle returned to the caller | no release in the returning function |

### Absence and failure

| Outcome | Report through |
| --- | --- |
| missing key, end of file, exhaustion, no match | return value or `try_*` status |
| value domain includes Null | `try_*` |
| sentinel impossible and no reason needed | `void` or `NULL` |
| failure that may cross frames | `raise %(cause ...)` |
| impossible internal state | `$assert`, `$unreachable` |
| wrong macro argument | `x2c_diagnostic_fail` |

### Matching and traversal

| Situation | Use |
| --- | --- |
| static pattern selects a branch, captures used there | source `match` |
| pattern built at runtime, bindings escape, rewrite | `List.match`, `match_replace`, `search` |
| one tag, length, or comparison test | `if` |
| few fixed positions in a trusted shape | flat destructuring |
| visit every element | `foreach` |
| streaming, interleaving, exhaustion status | explicit `Iter` |

### Building compiler output

| To build | Write |
| --- | --- |
| one shape at several sites | named macro applied from a meta function |
| code one function builds | `$!( )`, `$!{ }`, `$!Unit{ }` |
| a computed part | `${expr}` hole |
| a name shared by quotations | `x2c_ident` local |
| a type needed before landing | `$!T{ }` |
| code inspected before it is returned | `lib/meta.x` builders such as `x2c_expr_call` |
| a pattern, data row, internal node | `%(...)` |

## Appendix B: role names

| Role | Name |
| --- | --- |
| subject: Compiler, Emitter, Tokenizer, Build, Frontend, Sym | `c`, `e`, `t`, `b`, `f`, `s` |
| AST List under inspection | `node` |
| expression, statement, declaration node | `expr`, `stmt`, `decl` |
| a node's type; a conversion's destination | `type`, `target` |
| call arguments; declared parameters | `args`, `params` |
| operator; signature; callable value | `op`, `sig`, `fn` |
| count; indexes; cursor pointer; output | `n`; `i`, `j`; `at`; `out` |
| token where a construct starts; origin table index | `origin`; `occurrence` |

## Appendix C: sources consolidated

| Source | Parts here |
| --- | --- |
| [x2c-coding-style-guide.md](x2c-coding-style-guide.md) | LY, ST, EX, FN, FA, FI, CM, NM, LT-1, VT-5 to VT-9 |
| [x2c-code-organization-guide.md](x2c-code-organization-guide.md) | FI-1, MO, AR-6, RT-6 |
| [x2c-philosophy.md](x2c-philosophy.md) working rules and bloat test | PR, ER-4, RT |
| [replacing-manual-ast-walks-with-match.md](replacing-manual-ast-walks-with-match.md) | FN-12, MA-7, procedures |
| [lowering-with-macros.md](lowering-with-macros.md) | MA-5 to MA-8 |
| [adapters-macros-decorators.md](adapters-macros-decorators.md) | MA-1, MA-2, MA-10, VT-8, VT-9 |
| [logger-and-diagnostics-guide.md](logger-and-diagnostics-guide.md) | DG |
| skills: beautify, clean, simplify, validation, overengineering | PR-3, FA-5 to FA-9, signal catalog, procedures |
| book: idioms, values, collections, memory, exceptions, macros, meta functions, packages, wrapping C libraries | VT, LT, ER, MA, PK, appendix A |
| `packages/AGENTS.md`, `unittest/AGENTS.md`, `docs/AGENTS.md` | PK, TE, CM-5 |
| beautification and cleanup history, 2026-09-17 to 2026-10-04 | HP, FN-4, DG-1, PR-12, lessons |
