# Language features as modules

> Status: reference
> Research on private branch `gwf/hooks-spike`, 2026-10-07. Two read-only
> surveys classified every compiler language feature; their key claims were
> spot-checked against source. Line counts are approximate physical lines.

## Question

Can x2c language features live in single-purpose files that register one
lowering, so that a user include, a library file, and a compiler module use
the same shape? Which features are separable, and which are intertwined with
the compiler?

## Reference point

The built-in string switch (`builtin-string-switch.diff`) is purely
additive: one dispatch line in `Compiler._step_tag` and one 120-line block
that calls only shared services. It could be its own file.

## Classification

**A**: additive and self-contained, like string switch. **B**: self-contained
logic with a few named touch points elsewhere. **C**: intertwined with core
typing, binding, or control-flow analysis.

### Already extensions

These are keyword aliases or decorators that expand to ordinary syntax:
`foreach` (`keyword foreach $x2c.foreach`, etc/builtin-macros.x:16-27),
`class`, `$scope`, `$let`, `$lock`, `loop`, and everything in
lib/system-macros.x (`$switch`, `$time`, `$assert`, `$todo`,
`$unreachable`, `$dedent`). About 480 compiler lines plus 125 library lines.
`foreach` depends on four private primitives (`complete_iter_chain`,
`promote_string_literal`, function lookup, unique names); with those public,
it would be a pure library file.

### Separable with a seam

| Feature | Lines | Class | Touch points |
| --- | ---: | --- | --- |
| printf Var formats (transform.x:1208-1453) | 246 | A | one entry in `_call`; family table in expressions.x |
| Collection literals and literal order (transform.x:545-706) | 160 | A | public entry already called from cache.x |
| Cast, index, slice, return, var | 80 | A | thin routes into conversion services |
| Destructuring | 330 | B | pattern-keyed statement registration; function-entry pre-pass |
| raise | 200 | B | "never returns" fact; `runtime_literals` flag; `error.h` anchor |
| `$auto` and managed declarations | 110 | B | declaration position; `managed-init` node known in 5 places |
| String interpolation | 200 | B | tokenizer segment mode; literal cache |
| Runtime static locals | 320 | B | cleanup region participation |
| class defaults | 780 | B | collection-time declaration defaults service |
| Truthiness, getindex/setindex, dynamic operators | 470 | B | several handlers share the `op` arm; parent-before-child order |
| match | 650 | B | see "Revised after review" below |
| Lambda lowering | 550 plus callables.x | B | see "Revised after review" below |

### Core

| Feature | Lines | Why |
| --- | ---: | --- |
| Declarations, call arguments, assignment, comparison | 165 in transform plus initializers.x | implicit conversion rules of the language |
| defer | 320 | control-flow analysis over every transfer; the primitive other features reuse |
| try/catch/finally | 700 | regions, label ancestry, volatile preservation |

Roughly: transform-phase feature code is 30% A, 59% B, 12% C; parse, bind,
and later phases hold about 480 lines A, 2,000 B, and more than 5,000 C.

## Revised after review

Gary's correction: the surveys classified the current implementation, not
the necessary one. Rechecked against source:

- **match.** Its cleanup barrier is the switch barrier:
  `Walk._rewrite_matchcases` and `Walk._rewrite_switch` both call
  `_bounded(body, 0)` (cleanup.x:531-536). Binders are ordinary declarations
  once typed. The C text built in emit.x (`_match_cases`, `_match_if`) is a
  choice; a typed-phase module can produce an ordinary `switch` on the head
  symbol plus `if` arms with Match runtime calls. The Match engine was once
  isolated behind a thin API and can be again.
- **catch patterns.** Selection happens at raise time, before unwinding: the
  catch site prepares a `MatchPlan` per arm (lib/error.x:950-1000). Patterns
  restricted to a simpler form can lower to nested `if` tests, emitted as a
  predicate helper the catch site calls during selection, not as tests in
  the catcher after landing.
- **Lambda lowering.** Capture analysis now runs inside identifier
  resolution, but a typed function-level hook sees binding identities, so
  free variables, mutated captures, cell rewriting, and helper lifting
  through unit support are structural. Func typing and call conversion stay
  core.

- **Code quotations.** `$!{...}`, `$!(...)`, and `$!KIND{...}` are already
  anonymous macro definitions applied to the locals they name:
  `parse_macro_quotation` (macros.x:1556) reads the body through the macro
  definition reader with `d.quotation` set, whose parameters are the holes the
  body names (macros.x:904). What is special is only the `$!` prefix and the
  kind selection (expressions.x:626). Wave 4 tested a reader-prefix hook
  and rejected it: every quotation-specific step needs parser and binder
  state (token cursor, holes, symbol lookup, literal cache), so the hook
  adds about 20 kernel lines and removes none (reader-prefix.md).
  Quotations stay in the kernel's macro substrate.
- **Protocols.** protocol.x (2,832 lines) already falls into four parts:
  declaration parsing, publication, adoption, and conformance checking
  (449-1490); typing queries such as conversion, member resolution with the
  self type, and operator lookup (967-1980, with operator-ledger.x and
  type-ledger.x); generated code such as owners, update helpers, adapters,
  and descriptor tables registered through `add_support` and `add_init`
  (1983-2706); and the runtime dispatcher in lib/. The split: declarations
  and code generation become a module that runs when declarations are
  collected and fills fact tables through the API; core typing keeps a small
  compiled query engine over those tables; the dispatcher stays in the
  runtime. Queries run on hot paths and stay compiled; declarations are rare
  and tolerate meta cost.

## Principle

Everyone uses the same thin API: compiler modules, library extensions, and
user includes. A feature that needs something outside that API either
justifies a new API entry or stays core. This keeps the compiler from
becoming monolithic again.

## Lift and shift already exists

`foreach` shows the whole path today. Its surface is a decorator in
etc/builtin-macros.x, its algorithm is meta code compiled into the compiler
(`_foreach_expand`, builtins.x, through linked-meta), and one line wires it:
`keyword foreach $x2c.foreach;`. A module written as macros and meta
functions moves into the compiler unchanged, and its registration is the
module's initializer. Generalizing needs more registration kinds, not a new
architecture.

## Seams a module system needs

Ranked by how many features need them:

1. **Typed node lowering.** The transform dispatch already declines by
   returning the node unchanged and re-normalizes a changed result. A module
   registry needs several handlers per kind and pattern-keyed registration.
   Used by string switch, collection literals, printf, raise, destructuring.
2. **Statement keyword at parse time.** Exists as `keyword` for identifiers;
   `hook` covers C keywords. Every core statement has two entries, the token
   parser (statements.x:91-119) and the constructed-form binder
   (parse.x:2862-2960); a module must register both, or the parser must
   always build syntax and then bind it.
3. **Declaration position.** `$auto`, destructuring, class, function hooks.
4. **Services for every module.** Unit support and file initialization,
   diagnostics at a node, include anchors (`error.h`, `exception.h`), and
   hygienic temporaries shared across quotations.
5. **Cleanup participation.** Barriers, regions, transfers. Needed by try,
   defer, match, switch, static locals. Hardest; `defer` is the published
   primitive features compose with instead.
6. **Identifier resolution.** `with` and lambda captures. Hardest; stays core.
7. **Reader prefix.** Rejected in wave 4; quotations stay in the kernel.
8. **Fact registration at collection.** Protocol conformance, conversions,
   operator members, and class defaults, replayed through interfaces.

## Roadmap shape

One module API, used in three places with the same source:

1. A user include prototypes an extension (project meta, out of process,
   about 1.3 M instructions and 0.17 ms per meta call).
2. Adoption moves the file into `lib/` (library meta, in process, about
   1.5 M instructions per use for `$switch`).
3. A hot or core feature moves into `src/` as a module behind one
   registration line (string switch built in: 6.55 M per use, below
   hand-written 7.75 M).

Rare constructs (string switch, printf formats, raise, foreach) tolerate
meta cost. Hot node kinds (operators, calls, declarations) stay compiled.

## Candidate experiments

1. **Typed-node hook.** `hook` at the transform phase; port string switch to
   it and add the node-diagnostic API for its label check.
2. **foreach as a library file.** Publish its four private primitives as SDK
   operations and measure.
3. **`$auto` through a declaration hook.** Delete the `managed-init` node
   kind and its five special cases.
4. **printf formats as its own file.** A pure refactor that tests whether a
   built-in moves out cleanly with no hooks.

## Conversions are one class of requirement

The book lists the converting destinations (language.md, "Types and
conversions"): an initializer's value, an assignment, a `return`, a declared
call argument, an interpolation hole, and a `Var` value a printf-family
format consumes. The rules are keyed on source and destination types: same C
type or typedef substitution, `Var` crossing, a declared converter, `Func`
conversion, and literal promotion. Conversion is therefore a small set of
positions crossed with a rule table. It stays core, but as one separated
concern. Today `convert_expression` has about 74 direct call sites in 8
files (28 in transform.x); the positions are not yet the single entry.

## Ordering rule for generated code

Support declarations (`add_support`) are lowered once by the transform drain,
so code literals contributed before or during the transform cost one ordinary
lowering. File-initialization statements are spliced in after the transform
and must arrive lowered (`Compiler.add_init`), so strings or pre-lowered
forms fit there. Contribute code literals before lowering and lowered forms
after it; a module that follows this never re-runs transformations.

## Kernel or component, by keyword

Operators (`in`, `is`, `is not`, `===`, `@`) are left as they are for now.

| Keyword or word | Verdict | What the component needs from the kernel |
| --- | --- | --- |
| `macro`, `keyword`, `meta`, `native`, `using`, `$`, `$!`, `$(` | Kernel: the extension substrate | (it is the API) |
| `import`, `as` in import, `with` in import | Kernel: unit assembly and interfaces | (it is the API) |
| `defer` | Kernel: cleanup regions | (it is the cleanup service) |
| `protocol`, `associated`, `Self`, `as`/`tag` in adoption | Component | fact registration at collection; member-resolution and conversion rule tables; unit support and initialization for adapters and descriptor tables |
| `delegate` | Component (with protocols) | a member-resolution fallback rule |
| `match` | Component | the pattern API; typed node lowering to `switch` plus `if` arms |
| `catch` | Component (pattern part) | the pattern API, emitted as a selection predicate |
| `try`, `finally` | Component | cleanup participation (regions, transfers); include anchor |
| `raise` | Component | "never returns" fact; include anchor |
| `with` | Component | a local expression macro invoked by bare name |
| `threaded` | Lexical data | a spelling alias for `_Thread_local` |
| `foreach`, `class`, `loop`, `synchronized` | Already components | `class` needs the declaration-defaults service |

### Patterns as one component

`match`, `catch`, macro recognition, and typed captures (`?(T x)`) share one
pattern language. One pattern component compiles a pattern into a test and
its binders: static patterns into nested `if` tests over List structure,
dynamic ones into a runtime `MatchPlan`. Its clients choose where the test
runs: a `match` arm in place, a catch site's selection predicate, a macro's
recognition.

### Protocols and adapters as shims

An adapter sits between two API endpoints: a caller's expected signature
and a participant's member. It is a small template instantiated per pair
and memoized per unit. Protocol conformance supplies the pairs as facts;
the kernel's resolution engine reads the facts; the adapter template emits
through unit support. None of the three needs private compiler state.

### The kernel that remains

1. Lexer and C parser.
2. Binder: scopes, names, identifier resolution.
3. Typing: the conversion engine (positions by rule table) and member
   resolution, both reading registered facts.
4. Cleanup and region service (`defer`).
5. Macro and meta substrate: expansion, hygiene, quotation, meta execution.
6. Hook dispatch and module registration.
7. Unit assembly: imports, interfaces, pending destinations, emission.

## What remains open

- **Operators** (`in`, `is`, `is not`, `===`, `@`, and protocol operator
  dispatch) stay as they are until the conversion and resolution engines are
  separated.
- **Two statement entries.** Every core statement has a token production and
  a constructed-form binder; unify them or register both.
- **Conversion positions** are not yet the single entry to the conversion
  engine (about 74 direct `convert_expression` calls).
- **Meta cost** for user-space extensions: about 1.3 M instructions per
  project meta call, and a second layer while quotations cannot share
  hygienic names.
- **Hook composition**: order when several hooks match one node, and replay
  of hooks through interfaces beyond the keyword-alias rows.
- The API the kernel exposes: see `thin-api.md`.
