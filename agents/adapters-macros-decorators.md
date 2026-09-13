# Adapters, Macros, and Decorators

This is a living guide for agents simplifying x2c code. It records patterns
that have worked, patterns that have failed, and the evidence needed to tell
the difference. Add to it as the repository teaches us more.

The language contract belongs in the
[language reference](../docs/src/reference/language.md), especially its
sections on compile-time macros, decorators, macro-visible syntax, and typed
callback adapters. This guide is about choosing and evaluating those tools,
not redefining their syntax.

Macros and decorators are a normal part of the x2c design vocabulary, not a
last resort or a spelling of the C preprocessor. Look for them whenever code
review exposes uniform hand-written source, copied compile-time facts, or an
orthogonal wrapper repeated beside several targets. The rest of this guide
explains when those opportunities produce clearer code and when they do not.

## Start with the boundary

Do not begin by asking, "Can a macro generate this?" Begin with four plainer
questions:

1. What fact or invariant is being repeated?
2. Which module already owns that fact?
3. Is the repeated code translating between two representations, or merely
   spelling the same operation several times?
4. Which differences between the copies are policy and must remain visible?

Choose the smallest tool that answers those questions:

- One caller needs a clearer implementation: use a normal helper.
- Two APIs or representations meet: use a typed adapter.
- One fixed source form repeats with different names or types: use a macro.
- Several declarations derive from the same rows: use a compile-time ledger
  with small projections.
- Existing code needs one orthogonal wrapper: use a decorator.
- Keys or membership change while the program runs: use a Map or another
  runtime collection.

An adapter, macro, decorator, and Map solve different problems. Combining
them is useful only when each retains one clear job.

## Adapters translate; they do not become new owners

An adapter sits at a real boundary: callback signature to method signature,
public compatibility shape to internal representation, boxed value to native
value, or one owned view to another. A good adapter:

- has a narrow, typed input and output;
- delegates the operation to the existing owner;
- performs only the conversion required by the boundary;
- preserves or explicitly translates status and failure;
- does not copy the owner's algorithm or validation policy.

The compiler-owned `$x2c.callback.adapt` is the strongest current example.
It produces a typed thunk for a fixed callback boundary while the source
method remains the behavior owner. See
`docs/src/reference/language.md` under "Typed callback adapters" and
`unittest/compiler-fixtures/callback-adapt.x:20`.

A private record stored in `Var` is another direct adapter boundary. Define
the private conversion pair, declare `protocol Var(PrivateRecord);`, and let
typed arguments, results, assignments, and initializers request the crossing.
Keep explicit tag checks where the incoming `Var` is genuinely dynamic. The
generated adapters remain local because the participant is private.
`Lambda` in `lib/lisp.x` and `LogTextSink` in `lib/logger.x` are checked
repository examples. Sharing
`<p48>` with other callback state is not a reason to leave a known private
callback payload untyped. Macro definitions and their typed slots are ordinary
Lists, not pointer records, so they are deliberately not examples of this
adapter pattern.

Caller ownership does not disqualify the same pattern. Ownership answers where
the pointee lives and how long it remains valid; protocol participation answers
how its pointer crosses a typed boundary. `lib/iter.x` keeps every pipeline
state struct in caller storage, but stores twelve known state-pointer types in
`Iter.obj`, which is a `Var`. Private `StateRef` aliases and `Var(StateRef)`
rows therefore name real crossings without allocating, copying, or extending
the state lifetime. A survey must inspect what enters and leaves each `Var`
field, not reject the field because the pointed-to storage is native or
caller-owned.

Transparent C pointer aliases have one compiler complication. On an implicit
`Var`-to-pointer assignment, the generic pointer decoder can win before the
alias's named reverse converter. Call the reverse converter explicitly at that
boundary, as `iter.obj.mapstateref()`, and keep its implementation inline. A
public parameter that retains the underlying pointer spelling likewise needs
an inline cast to the private alias before a `Var` parameter can select the
forward converter. Put that cast directly in the call; do not introduce an
alias-typed temporary solely to trigger conversion. For a hot callback,
inspect generated C and run the existing benchmark to confirm that the
converter reduces to the original pointer load.

`MatchPlan` in `lib/match.x` is the reusable executor. The cache retains the
plan itself, and callers use its executor methods directly. A protocol whose
only work is to convert the receiver and forward those methods would add
functions without sharing an implementation.

Least-public protocol generation remains useful when a relationship supplies
a real default or typed crossing. It is not a reason to generate forwarding
methods around an existing view. Measure generated C as well as source: a
small protocol declaration can hide a much larger generated surface.

For a protocol and participant that are both private, use
`static protocol PrivateBase(PrivateParticipant);`. Locality would also be
inferred, but the explicit spelling makes the fully private relationship
clear at the declaration.

Type's handwritten inline List methods supply its complete static and boxed
behavior, including `contains` and `getindex`. A replacement must preserve
both ordinary calls and indexing; forwarding methods alone do not establish
that the compiler's indexing path can consume a separate protocol.

Prefer an explicit adapter when the source and target contracts genuinely
differ. Hiding that translation in a large macro makes the boundary harder to
review and usually creates a second policy owner.

## Macros remove uniform source repetition

A macro is a good fit when its invocations are easier to read than the
expanded code and every invocation follows the same policy.

A macro is not an architectural simplification merely because it hides a
repeated prefix. Replacing a lock call and deferred unlock, a check and raise,
or another two-statement sequence with one macro invocation leaves the same
operations and concepts in place. Keep that change only as an independently
justified local idiom; never count it as the result of a broad simplification
campaign.

Current proven shapes include:

- Uniform method or function families in `lib/logger.x:895-900` and `933-938`
  and in `lib/common.x:479-487`. Names and types vary; behavior does not.
- Private pointer conversion pairs in `lib/var-adapters.xmacro`. The tagged
  form preserves `Var.new` and `Var.pointer`; the raw form preserves the
  direct `p64` store and load used by iterator callbacks.
- Uniform selector or native adapter families in `lib/list.x:331` and
  `lib/varops.x:60`. Each invocation supplies the facts that differ.
- Local resource setup in `lib/match.x:164` and `lib/match.x:173`. The macro
  hides stack-storage mechanics while release and fallback policy stay
  visible.
- Test registration in `unittest/test-macros.xmacro:1`. The macro removes a
  mechanical name-to-registration conversion.
- One ledger in `lib/var.x` with mechanical projections imported from
  `lib/var-tags.xmacro`. One row supplies the enum, table, and switch
  projections.

`lib/map-generics.xmacro` also shows how to remove fake adapters without
discarding real ones. Its generated families call ordinary `Scope`, `Bytes`,
and `Block` operations through exact `x2c.ident` references; passing those
operations through one wrapper per consumer would add no policy or conversion.
The Map boxing and pair-building adapters remain because their declared types
are required at the `Var` crossings. A failed direct spelling is evidence
about that one call, not a reason to preserve the whole forwarding layer.

Keep a macro only when:

- the macro definition, helper code, ledger, and invocations are a net
  improvement over the direct source;
- the invocation states every policy-bearing type, public name, status, or
  mode that a reviewer needs;
- generated names are hygienic unless an exact public spelling is deliberate;
- diagnostics still point to useful source;
- normal and `--live-symbols` translation agree;
- generated C remains direct enough to inspect;
- hot-path performance is unchanged or measured and accepted.

Line reduction is the normal test, but not the only possible win. The Var tag
ledger is valuable because several projections consume the same rows. Count
the ledger and projection helpers when comparing total production line count.
Record such an ownership win honestly; do not report it as a line-count win.

### Use a ledger only for repeated facts

A compile-time ledger is appropriate when the same rows must drive several
artifacts. Each projection should be small and unsurprising.

Keep fixed policy in the module whose behavior it defines, as
`lib/dispatch.x` does with direct switches for primitive rendering. A
substantial xmacro may keep AST projection mechanics out of the runtime
source, as `lib/var-tags.xmacro` does. When two modules must read the same rows
the xmacro holds them instead, because a `$(def)` does not cross an `#include`:
`lib/var.x` and `lib/varconvert.x` both read the tag ledger, so it is in
`lib/var-tags.xmacro`. A single three-row table does not justify five one-use
macros: direct aligns,
offsets, and copies keep a frozen program's byte layout visible.
A one-use data-only xmacro adds a file boundary without sharing an
implementation;
`lib/lisp.x` therefore declares its native target rows directly. Its local
expression macro remains necessary because `x2c.ident` is valid only during
macro expansion; a direct top-level Lisp splice fails before translation.

Do not create a ledger merely because several cases share a noun. Match's six
guard operators, for example, have different normalization, capture, layout,
and lowering behavior. Turning those behaviors into generated AST would hide
the useful differences and add another representation to maintain.

Likewise, a three-member enum with no parallel table or switch is already the
clearest possible ledger: the enum itself.

### Keep important names explicit

Do not make a reader reverse-engineer public function names, C types, or
failure modes from clever Lisp. The native update macro in
`lib/varops.x:652` explicitly receives both the native type and public
function name. That repetition is useful documentation at the call site.

Generated public declarations also have repository-wide consequences. Check
symbol collection, generated headers, the module catalog, and documentation
tools rather than assuming they understand a new source-shaped macro.

Unit macros may generate protocol adoptions after the methods and converters
that satisfy them. Successful expansion retains those rows for conformance and
symbol snapshots. Repeated applications retain distinct rows by combining the
generated declaration location with the macro invocation location. Shallow
collection transactionally expands file-scope unit macros that contain
protocol rows, so importing units receive them and the expansion's public
declarations too. Public definitions may complete prototypes earlier in the
same expansion. Keep each private alias and exact converter prototype literal;
private declarations are discarded with generated bodies. The iterator family
keeps its rows direct because those relationships are useful source
documentation:

```x2c
typedef LocalState *LocalStateRef;

static inline Var LocalStateRef.var(LocalStateRef);
static inline LocalStateRef Var.localstateref(Var);

$(import "var-adapters.xmacro")
$var.raw.pointer(LocalStateRef, localstateref);

protocol Var(LocalStateRef);
```

Keep `static inline` in both a literal private prototype and its generated
definition; plain `inline` macro output can otherwise escape into the
generated header. Repeated adoption families may be generated when that makes
the family easier to read; keep a row direct when the relationship itself is
useful source documentation.

## Decorators wrap existing code

Use a decorator when one existing expression, declaration, function,
statement, field, or unit should remain recognizable but gain an orthogonal
wrapper. The checked examples in `examples/decorators.x` show tracing and
parameter preconditions; the compiler fixtures under
`unittest/compiler-fixtures/macro-decorator-*` own the exact supported
boundary.

Decorators are a normal tool for runtime and compiler source when one
orthogonal wrapper repeats around visible targets. Prefer one when:

- the undecorated target remains visible and readable;
- the wrapper is independent of the target's business policy;
- composition order is intentional and tested;
- the decorator is shorter and clearer than repeating the wrapper;
- removal of the decorator restores the ordinary target without leaving
  hidden companion machinery.

Do not use a decorator to:

- generate a family of sibling functions; use a unit macro or direct code;
- conceal output-publication, fallback, or ownership policy;
- replace a normal helper that already names the operation clearly;
- manufacture arbitrary AST simply because the macro system permits Lisp;
- assume every parsed construct is valid as constructed decorator output.

When a natural decorator shape fails, reduce it to a small compiler probe.
Treat an unsupported or inconsistent source-shaped form as a possible
language gap, not an invitation to ship a larger AST-building workaround.

## Maps and generated ledgers

Use a runtime Map when entries are discovered, added, removed, or queried at
runtime. Use a compile-time ledger when a fixed set of source facts generates
declarations or code.

Do not generate a Map merely to avoid a direct switch when:

- the set is fixed and small;
- direct cases have meaningfully different behavior;
- lookup allocation or initialization would enter a hot path;
- the Map would duplicate a canonical table already owned elsewhere.

An adapter may expose data from an owned Map, but it should not duplicate the
Map's admission, mutation, or failure policy.

## Reject fake uniformity

Similar-looking code is not necessarily the same code. Reject a macro or
decorator when it:

- needs flags that select substantially different bodies;
- flattens distinct success, failure, or output contracts;
- is longer or harder to understand than the source it replaces;
- moves ordinary source into opaque AST construction;
- hides a hot-path cost such as cleanup registration or allocation;
- worsens diagnostics or loses source provenance;
- creates public symbols as an accidental side effect;
- works in normal translation but fails with live symbols;
- becomes a second owner of facts already enforced elsewhere.

Retain the negative result in this guide. A short explanation can prevent the
next agent from repeating an attractive but unhelpful experiment.

### Rejections are versioned evidence

A rejection applies to the exact implementation and compiler capability that
were measured. Record its authored-line cost, diagnostics, generated C,
performance, and the source shape that failed. Do not turn that result into a
permanent rule against the family.

Archived plans are execution logs, not a source of new restrictions. Follow
current `AGENTS.md`, this guide, and active plans. An archived `do not reopen`
or `no other candidate` statement is historical unless current guidance
repeats its exact technical reason.

### Result flow and shared helpers

`$error.fallback` is defined for user-defined resumable causes; a shared cause
must not use it because shared causes never return to the raise.

The filesystem helpers `_build_mkdirs` and `_build_remove_tree` in
`src/build.x` also serve `src/bootstrap.x`. The Lisp evaluator's local target
rows in `lib/lisp.x` produce the native-target Map. Use macros, compile-time
Lisp, or ordinary helpers according to which form leaves the facts easiest
to inspect.

### Whole-test retained Scope

Status: proven as a statement macro; rejected as a function decorator
Checked: 2026-07-30 at `9d762c97`
Owner: `unittest/test-macros.xmacro`

Problem: 156 tests repeated `Scope.retain()` at entry and `Scope.release()` at
the sole exit. Direct form used 312 statements. `$test.scoped();` plus its
four-line definition uses 160 statements and makes early returns safe through
`defer`, a net reduction of 152 source lines. A function decorator was
rejected because re-elaborating captured bodies does not currently accept
existing `try` nodes or already typed indexing nodes. The statement macro
adds the wrapper without reconstructing the body. `make verify` owns the
runtime proof.

### Lisp session entry decorator

Status: proven
Checked: 2026-07-30 at `9d762c97`
Owner: `lib/lisp.x`

Problem: `Lisp.eval`, `Lisp.apply`, and `Lisp.eval_string` repeated the same
null-session failure and session-Scope wrapper. `$lisp.entry` leaves each
business body visible and centralizes that orthogonal boundary, reducing
`lib/lisp.x` by 10 lines. The source scanner also had to learn decorator
adjacency so generated API documentation still sees the original signature
and comment. Macro-authored `raise` does not survive constructed-fragment
elaboration, so the decorator delegates that operation to one private helper.
`make verify`, `make stage-3`, generated C inspection, and the API-reference
scanner own the proof.

### SymbolSet replaces generated Symbol switches

Status: proven
Checked: 2026-08-01 at `b2ac91ae`
Owner: `lib/var.x` and `lib/symbolset.x`

Problem: the var-tag ledger projected two 109-case switches (`$var.tag.cases`,
`$var.tag.kind.cases`) merely to map a Symbol to its dense id and kind.
Direct form: macro-generated sparse `switch (tag)` per lookup.
Adapter/macro/decorator form: one `$var.tag.symbolset()` projection into a
`SymbolSet` literal; `_tag2id` becomes `(TagId) tags.index(tag)` and the kind
becomes a column on the already-indexed `taginfo` row.
Economics: two ledger projections deleted, 108 fewer generated C lines in
`var.c`, lookup 18.0 ns to 3.0 ns; the 109-member set is 1,084 read-only
bytes with no allocation or initialization.
Proof: compile-time validation rejects malformed or duplicate Var rows;
runtime Var tests cover every kind and representative exact tags.
Limits or counterexample: members must be compile-time literals; never pay a
second set lookup to remove a second switch — widen the indexed row instead.

### Macro-generated typed array families

Status: proven
Checked: 2026-08-03 at `66448562`
Owner: `lib/array-generics.xmacro`, `lib/array.x`, and `lib/typed-array.x`

Problem: packed typed arrays over six scalar element types would repeat one
~300-line module per type, the shape drifting independently six ways.
Direct form: six hand-written modules, roughly 1,800 authored lines.
Adapter/macro/decorator form: one imported generator owns fixed-width storage
and sequence operations. Ordinary `Array` instantiates the storage algorithms
with `Var`; each packed family explicitly instantiates the same core with its
native element type, then separately requests methods and Block, Iter, and Var
publication.
Economics: one authored implementation now serves ordinary `Array` and all six
packed families; the generated C remains specialized and uses native element
pointers until Iter or Var transport is requested.
Proof: the Array suite checks ordinary Array behavior,
`unittest/test-typed-array.x` exercises every family and the added sequence
operations, and the `array-generator-family` compiler fixtures compare normal
and live symbol collection on a seventh internal family.
Limits or counterexample: only the six existing trivially copied numeric
types are shipped. This does not promise arbitrary structs, owned resources,
or over-aligned elements, and `%[...]` still constructs ordinary `Array`.

### Macro-generated typed map families

Status: proven
Checked: 2026-08-08 at `f83edbdb`
Owner: `lib/map-generics.xmacro`, `lib/map.x`, and `lib/typed-map.x`

Problem: a second Robin Hood table for native key and value types would
repeat the probing, record reuse, growth, deletion, and traversal algorithms
that ordinary `Map` already owns, with the two copies free to drift.
Direct form: one hand-written module per typed family, each restating the
whole table algorithm.
Adapter/macro/decorator form: one imported generator owns scope-backed table
storage and every algorithm; ordinary `Map` instantiates it with Var hashing
and equality, and each typed family instantiates the same core with concrete
key and value operations. Iter and Var publication is a separate opt-in
expansion, so a family that never boxes pays nothing for it.
Economics: `lib/map.x` lost roughly 300 authored lines while gaining three
typed families; the generated C stays specialized on their record fields.
Proof: the Map suite checks ordinary Map behavior,
`unittest/test-typed-map.x` covers all three shipped families including
expand unwinding, and the `map-generator-family` compiler fixtures compare
normal and live symbol collection on an internal family that also exercises
the publication stage.
The generator names allocation, `Scope`, and `Bytes` operations directly with
`x2c.ident`. Map boxing and pair construction stay explicit because their
typed signatures select the required `Var` conversions.
Limits or counterexample: key hashing, equality, value validity, record
layout, boxing, and error policy remain visible inputs. Those are actual
family differences, not leftover forwarding code.

### Macro-generated typed list families

Status: proven
Checked: 2026-08-07 at `b2970c0f`
Owner: `lib/list-generics.xmacro` and `lib/typed-list.x`

Problem: seven typed cons chains over `List` would restate the structural
walk and a per-tag car read seven times, even though the interning pool,
hashing, equality, printing, and comparison are already List's own and need
no generated code at all.
Direct form: one hand-written module per element type, each restating the
structural operations and its own encoding.
Adapter/macro/decorator form: the typedef chain inherits structural List
operations (`cdr`, `reverse`, `append`, `sort`, the slices, and `iter`).
Receiver-relative results retain the typed spelling, so a walk does not
reinsert the validating converter on every step. `$list.typed.family` owns
the operations that inspect an element (`car`, `cons`, `last`, `index`, and
the `List` and `Var` converters), reading and writing the car through the
cheap encoding for its tag rather than `Var.new` and `Var.integer`.
`lib/typed-list.x` supplies each family's encoder, decoder, and tag literal
and instantiates that unit.
Economics: one `Unit` macro serves seven families. Typed lists share List's
canonical pool, so a typed chain and the plain literal that spells it are the
same cells and a typed `cons` finds a cell an untyped `cons` already built;
the converters retype rather than copy, which is sound because cells are
interned and never mutated. What that buys is a typed surface, not
throughput: `cons` is still a pool probe where `ArrayInt.push` is a memcpy.
Proof: `unittest/test-typed-list.x` covers all seven families, canonical cell
sharing, native element reads, nil as zero, typed structural results, a walk
that does not reconvert, `Iter` participation, widening to `List` for the
Var-callback operations, conversion through `Var`, and rejection of a foreign
element.
The 2026-08-10 follow-up deleted `$list.structural.family`: its seven `Iter`
methods only forwarded to `List.iter`, and typedef protocol inheritance makes
their exact adoptions unnecessary.
Limits or counterexample: the family does not adopt `protocol Var`. A typed
list already boxes as `<list>` through the typedef chain, so adopting would
spend one of the 32 custom tag slots per family to gain only bracket indexing,
which is a linear walk on a cons chain. There is no `long` family, and
`lib/typed-list.x:16-20` says why: `Var.box_i64` allocates a Scope-owned box,
so a cell outliving that scope would hold a dangling car, and `List.equal`
compares car bits, so two boxes of one number differ and every `cons` would
miss the interning table and grow it without bound.
`docs/src/guide/collections.md` owns the user-facing surface.

### Block(T) base defaults replace forwarding wrappers

Status: proven
Checked: 2026-08-01 at `21740d80`
Owner: `lib/protocols.x` and protocol base-default emission

Problem: `Array` and `Bytes` each hand-forwarded `len`, `capacity`, and
`clear` to their Block implementations — six wrapper methods repeating one
delegation contract.
Direct form: per-type wrapper methods delegating to Block.
Adapter/macro/decorator form: `protocol Block(T)` declares the members once
with base defaults; participants adopt and the compiler emits the checked
bindings.
Economics: net −2 lines, but six forwarding contracts collapse to one owner,
and landing it exposed and fixed two compiler defects (base-default binding
scope, base-typedef membership).
Proof: `make verify` plus the base-default probe asserting the consumer's C
calls the bound function directly, not through a runtime lookup.
Limits or counterexample: these base defaults own the shared operation.
Explicit adoption prevents accidental conformance; the
[Protocols chapter](../docs/src/guide/protocols.md) owns
generated-member selection and conflicts. Converter names such as `Var.block`
and `Var.as_iter` should express their API meaning, not act as conformance
switches.

### Type as a native List protocol participant

Status: rejected
Checked: 2026-07-30 at `9d762c97`
Owner: `src/type.x` and protocol generated-member ownership

Problem: `Type` is a `List` typedef but repeats ten inline forwarding methods
so its static operators and `Var(Type)` descriptor retain List semantics. A
native `protocol List(T)` can emit checked `Type_*` aliases to the existing
`List_*` owners, including the early `Type_getindex` binding required by the
postfix parser, with no call overhead. The generated-owner selector considers
ordinary defaults but not native rows. Combining the native aliases with
`protocol Var(Type)` emitted losing `Var` fallback wrappers under the same
names and the generated C failed with a redefinition; C2 has since stopped
emitting those wrappers, so this half of the blocker is unverified against
the current compiler. An ordinary `List(Type)` protocol compiles if
`Type.getindex` stays explicit, but replaces hot inline calls with wrappers and
is not an improvement. Typedef method inheritance already supplies ordinary
List methods such as `car`, `cdr`, and `cons`; the explicit Type methods own
the distinct protocol, operator, boxing, and indexing boundaries. Changing
generated-member ownership merely to recreate this working split would add
machinery without a capability or ownership benefit.

### Shipped expression constructors for generators

Status: proven
Checked: 2026-08-02 at `d2a51d85`
Owner: `etc/compiler-sdk.xlisp` compile-time Lisp SDK

Problem: a macro that generates code has to build AST nodes, and the SDK
shipped constructors only for a String literal, a cast, and a call — the last
two private. Every generator that needed anything else wrote the node shape by
hand. `lib/var-tags.xmacro` defined its own `var.tag.int-expr` and
`var.tag.symbol-expr`; `lib/varops.x` spelled a three-level index node inline;
the `(expr () (composite (commas ...)))` initializer wrapper appeared four
times across two files. The shapes are only discoverable by reading
`src/emit.x`, and getting one wrong fails as `compile-time Lisp evaluation
failed` at the invocation, not at the definition.

Direct form:

```text
$(defun var.tag.symbol-expr (value)
  `(expr ("Symbol") (literal ("Symbol") ,(str value) ,value)))
```

Adapter/macro/decorator form: `x2c.literal.int`, `x2c.literal.symbol`,
`x2c.expr.ident`, `x2c.expr.index`, `x2c.expr.call`, and
`x2c.expr.composite`, all taking expression ASTs as operands so a generator
composes them. Cast construction remains private to its shipped consumer.

The retained constructors have shipped callers or a concrete documentation
example. Cast, named-call, runtime-List, and statement construction stay
private to their consumers rather than enlarging the public SDK. A wrong
literal argument reports `x2c.literal.int requires a number` instead of
failing later inside an expansion.

Proof: generated `.h` and `.c` byte-identical for `lib/var.x` and
`lib/varops.x` before and after adoption; `make precommit` and `make check`.

Limits or counterexample: expression nodes only. Statement and declaration
shapes — `switch`, `case`, `return`, and the `(op & ...)` selector in
`var.tag.decode-inner` — are still hand-written quasiquotes. Add constructors
for those when a second generator needs the same one, not before.

Language gap, if any: none; this is an SDK addition, not a compiler change.

## Measure a candidate

Before keeping a macro or decorator, record:

- direct source lines removed;
- macro, decorator, ledger, and helper lines added;
- number and clarity of invocation sites;
- which facts now have one owner;
- generated public-surface changes;
- normal and live-symbol translation results;
- generated C differences;
- relevant runtime or translation benchmark results;
- diagnostics from one deliberately invalid use.

Count each candidate independently. A useful cleanup elsewhere must not hide
a macro that loses on its own.

## Add what we learn

Update an existing entry when a capability changes. Add a new entry when an
experiment establishes a reusable pattern or counterexample. Use this compact
record:

```text
### Pattern name

Status: proven | conditional | rejected
Checked: YYYY-MM-DD at <commit>
Owner: <module or compiler phase>

Problem:
Direct form:
Adapter/macro/decorator form:
Economics:
Proof:
Limits or counterexample:
Language gap, if any:
```

`Direct form` and the proposed replacement should be plain enough that a
future agent can compare them without understanding compiler internals.
`Economics` must distinguish line reduction from ownership or consistency
improvements. `Proof` should name existing tests, fixtures, generated
artifacts, or benchmarks rather than proposing a new recurring gate.

Entries are evidence, not permanent law. If a compiler improvement changes a
previous result, re-run the smallest decisive probe, update the status, and
preserve a sentence explaining what changed.
