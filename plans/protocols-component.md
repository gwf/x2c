# Protocols as a component

> Status: reference
> Research on `kernel/protocols-research` from dev `358a27c1`, 2026-10-10.
> The prototype commits on that branch are evidence, not for integration.
> The recommendation awaits Gary's choice; nothing here authorizes
> delivery.

Question: which parts of protocols (declarations, conformance, owners,
adapters; the migration table's 1,850 kernel lines) can leave the kernel as
a shipped component on the two primitives, at what source and translation
cost, and what must the kernel keep?

## Answer

One move is worth making: adapter synthesis. A shipped
`src/component-protocols.x` (195 lines) writes the forwarding members,
`Var` descriptor thunks, method tables, and descriptor registration through
`x2c_place(%(unit-support))` and `x2c_place(%(unit-init AREA))`. The kernel
presents each conformance it emits adapters for as a `conform` form.
The prototype passes all 1,129 fixtures and every probe. A second
bootstrap refresh reaches a fixpoint. Every lib and src C/H file is
byte-identical to dev, and so is the C of every workload. It adds no SDK
operation. The kernel loses a net 159 lines. Translation costs about 1 M
more per conformance, because source quotations bind where the kernel
bound pre-lowered bodies.

Everything else stays in the kernel. Declaration parsing and publication
own macro-visible syntax and the interface transport. Conformance
resolution and owner lookup are the query engine that every dot call and
protocol operator reads. Moving resolution would need about six new SDK
operations and a fact-returning rule contract, and it would delete
nothing from that engine. The 1,850-line estimate assumed that resolution
moves; the movable part is about 300 lines.

Cross-unit facts need no new kernel service. Declarations and adoptions
already cross interfaces and packages as generic `("source-node"
LOCATION)` Sym rows. Each unit re-derives conformance from them, which
costs 38 M per unit for the prelude's 44 conformances.

## What each part needs from the kernel

| Part | Lines | Decision |
| --- | ---: | --- |
| Declaration parsing | 223 | stays: parsing is kernel |
| Publication, adoption drafts | 295 | stays: registries feed queries |
| Conformance resolution | 708 | stays: needs six SDK operations |
| Lookup, member names, dump | 205 | stays: kernel queries |
| Member resolution, owners | 222 | stays: read on every use |
| Update and discard helpers | 201 | stays: operator lowering |
| Adapter synthesis | 302 | moves: the prototype |
| Native alias insertion | 73 | stays: no boundary placement |
| Diagnostics macros | 248 | stay with their checks |

What each part reads from the kernel:

- Parsing reads tokens, the type parser, member declarations, and the
  macro-hole mode.
- Publication writes the `protocols` and `adoptions` registries, retains
  Sym rows with static marks, infers privacy from file statics, fills the
  Var tag table, and reports conflicts.
- Resolution reads a function's signature by spelling (skipping
  generated adapters, following package spellings and `self` results),
  definition state, typedef ancestry, the VarMethods slots, converter
  spellings, numeric types, and fixed Var tags, and reports at an
  adoption's location. The SDK covers only the slots (`Type.fields`), the
  spellings (`Type.reverse_name`), numeric types (`Type.numeric`), and
  full resolution (`Type.resolve`).
- Member resolution and owner decisions read the conformance rows,
  ancestry, and Sym references for every dot call, protocol operator,
  truth test, bracket read, and discard. `Type.protocol_member` and
  `Type.getter` already expose them to components.
- The update and discard helpers belong to operator lowering in
  transform.x and expressions.x. `%(unit-support KEY)` fits their output,
  but no recognition point reaches a participant's direct update.
- Adapter synthesis needs placement in support and initialization,
  parameter syntax, and runtime calls by name. `x2c_place`, `$!Unit`,
  `$!Param`, `Type.parts`, `Type.resolve`, `x2c_ident`, and `Code.lowered`
  provide all of it.
- Native aliases need `finish_foreign_alias` and insertion at the
  participant typedef's header boundary, which no placement offers.

Lines are sections of dev's `src/protocol.x` (2,832 lines). Declaration
marks (`$rewrite_marked`) do not apply. A mark is per field, keyed by the
aggregate, and registers a member rule tested on a lookup miss. Protocol
facts are per (base, participant) pair. They are read on hits, by
operators, and by truthiness, not only on misses.

## Conformance facts across units

The interface already carries every protocol declaration as a generic Sym
row. Measured on dev's interfaces:

| Rows, bytes | lib and src, 78 files | W1 below, one unit |
| --- | ---: | ---: |
| All interface bytes | 2,608,122 | 564,135 |
| `adopt` rows | 88 (24,088 B) | 400 (197,384 B) |
| `protocol` records | 5 | 1 |
| `meta-protocol` rows | 9 (1,263 B) | 0 |
| `generated-protocol` rows | 109 (5,671 B) | 400 (19,180 B) |

A row is keyed `("source-node" LOCATION)`, and its value is the
macro-visible node `(adopt ...)`, `(protocol ...)`, or `(meta-protocol
...)`. Packages carry the same rows through the head list in
`_package_protocol_row`. No conformance row crosses. `rebuild_protocols`
reinstalls the declarations, and `resolve_protocols` re-derives every
visible conformance at the start of each full parse.

A generic component-fact row keyed by component and type would replace
nothing. The protocol rows are the declarations themselves. Keyed by type,
they would collide for a type with several adoptions or several static
adoptions. The only protocol-specific transport is small: the head list,
the `generated-protocol` marker rows that `record_generated_symbol` writes
for forwarding members, and the static-adoption skip in collect.x.

Recording resolved conformance in the declaring unit's interface would be
the real cross-unit fact. A probe that runs the full-parse resolution
twice measures one pass at 37.7 M on the empty unit (44 conformances) and
167 M on W1 (444). That is 3.1 percent of an empty unit. But it changes
semantics: a later unit that sees more participant members resolves more
today. It is an optimization independent of components.

## The prototype

Branch `kernel/protocols-research`, from `4ce4700a` to `75c1a019`.

- `Code.register_rewrite` accepts the `conform` head at the node point
  (one word in each of two match arms in src/meta-sdk.x).
- `Compiler.generate_protocol_adapters` keeps its iteration, its native
  aliases, and its filter: the forward converter is defined here, and the
  participant is not numeric. For each ordinary conformance,
  `_present_conformance` builds
  `(conform BASE PARTICIPANT FORWARD REVERSE BINDER DESCRIPTOR (ROW...))`
  and calls `Compiler.rewrite` at `AST_UNIT`. It settles what needs kernel
  state: the generated-owner decision of each member, collision and
  descriptor-requirement diagnostics, `record_generated_symbol`, and the
  generated bindings of each thunk and method table, through `fresh_name`
  and `sym.introduce`. Source quotations reject `_x2c_` names, so the
  component cannot spell them.
- Each row is `(MEMBER STATUS SOURCE EXPECTED TEMPLATE PART...)`, with parts
  `(default STORAGE)`, `(inherited EXPECTED)`, and `(thunk BINDING
  ERASED)`. DESCRIPTOR is `(METHODS NAME VAR-TAG AREA [TAG])`.
- The component places each function as a `$!Unit` quotation and the
  method table's assignment as `$!{...}`. It places the registration as a
  `Code.lowered` statement that calls the runtime by name. Binding those
  calls instead added redundant prototypes of
  `x2c_register_builtin_descriptor` and `x2c_register_descriptor` to 11
  lib units, which the kernel's unbound calls never emitted. The rule
  answers `(seq)`.
- The token replacement added to placed effects in src/macros.x is not
  needed and is not part of the recommendation.
- Five probe scripts list the prelude components by name and needed the
  new file.

A user `$rewrite(%(conform ("Shape") ("T1") *))` that answers `(seq)` runs
before the shipped rule and removes only `T1`'s Shape adapters.

## Measurements

Instructions retired, `builds/0/x2c translate --quiet --plain --no-deps -j
1`, fresh unique stems, median of 3. Both compilers were converged and
built in worktrees with paths of equal length. W0 declares 200 struct
handle types, each with `var`, the reverse converter, `str`, and a
forward view to `Shape`, and no adoptions. W1 adds `protocol Var(Ti);` and
`protocol Shape(Ti);` to each type. `Shape(T)` declares `area` and
`scale` with base defaults, so each type gets two forwarding members, one
`str` thunk, a method table, and registration. W2 adds one function per
type with two protocol dot calls, a boxing, and a boxed `str`.

| Workload | dev | prototype | Difference |
| --- | ---: | ---: | ---: |
| Empty unit | 1.204 G | 1.217 G | +13 M |
| W0, 200 types, no adoptions | 4.005 G | 4.000 G | -5 M |
| W1, 400 adoptions | 6.236 G | 6.630 G | +394 M |
| W2, W1 and 200 uses | 7.437 G | 7.827 G | +390 M |
| lib/common.x, the built-in adapters | 3.957 G | 4.004 G | +47 M |
| src/protocol.x, each tree's own source | 5.848 G | 5.419 G | -429 M |

At dev, adoptions cost 11.2 M per type (W1 minus W0). The prototype costs
13.2 M, which is about 1 M more per conformance. Member resolution per use
is unchanged: W2 minus W1 is 1.201 G at dev and 1.197 G with the
prototype. Samples of a 1,000-type W1 put the difference in placement
binding. `bind_syntax` under adapter generation took 250 of 3,222 samples
at dev and 501 of 2,625 in the prototype. The kernel bound bodies it had
already lowered, with parameter bindings it introduced. The component
cannot name those bindings without `new-name` spellings that change the C.
The empty unit pays +13 M to read one more prelude component. The
src/protocol.x row compares two different sources. It shows the smaller
file, not a per-use cost.

Correctness: `make verify-fixtures` passes 1,129 fixtures (2,522
artifacts) with the header-cache, protocol-boundary, package-install, meta,
and CLI probes. A second `make bootstrap-refresh` after `make build-safe`
changes no file. Against dev, the bootstrap differs only in collect.c,
linked-meta.c/h, macros.c, meta-sdk.c, protocol.c, and the new
component. W0, W1, and W2 produce identical C and H.

## Source cost

| Change | Lines |
| --- | ---: |
| protocol.x: generation (listed below) | -225 |
| protocol.x: `_present_conformance` and its row parts | +66 |
| meta-sdk.x `conform` head; two prelude lists | +2 |
| Kernel net | -157 |
| src/component-protocols.x | +195 |
| Total | +38 |

The deleted generation is `AdapterFunction`, the `ProtocolAdapters`
member, thunk, and register methods, `_guard_rendering` and its
decorator, `_register_descriptor` with four registration helpers, and
`_string_literal`. The component's 195 lines replace those 225 lines of
hand-built AST (`_helper_call`, `rebuild_expression`, and
`_signature_declaration` for thunks) with quotations. The deletion rule
judges kernel removed against component added. On that rule this move is
close to even, like match's first move.

## SDK additions

Move 1 adds none. It extends one existing operation:

- `Code.register_rewrite` takes `(conform *)` at the node point. This lets
  a component, or a user rule, own adapter synthesis for a conformance.
  lib/meta.x and the architecture chapter name the head with the others.

Moving resolution as well would need these additions. The plan does not
recommend them.

1. `Code.function(spelling)`: the visible function, its signature and
   binding, following package spellings and `self` results and skipping
   generated adapters (`_declared`, `imported_spelling`,
   `_relative_signature`).
2. `Code.defined(function)`: definition or completion state
   (`_default_completes`, `_defines_function`).
3. `Code.is_static(spelling)`: file-static privacy (`_is_private`,
   storage inference).
4. `Type.parent(type)`: one typedef step (`_ancestry`).
5. `Type.var_tag(type)`: the unit's Var tag (`as` checks, descriptors).
6. A rule result or effect that stores a conformance row where
   `protocol_members_for` reads it.

They would also need `x2c_diagnostic_error_at` to accept a location row.
That is six operations and one extension, a 12 percent increase over the
49 public operations. The kernel would still own the row format, the
lazy resolution trigger, and every reader.

## What the kernel keeps

- Parsing of `protocol` bodies and adoptions, and publication. The node
  shapes are macro-visible syntax that decorators such as `class`
  construct, and the binder publishes them.
- The `protocols`, `adoptions`, `conforms`, `protocol_helpers`, and
  `proto_cache` fields, and the `collect_protocols` and
  `import_protocols` flags. No field goes in move 1. `protocol_helpers`
  also holds the `explicit-converter`, `fresh-callee`, and
  `discard-helper` entries that expressions.x uses.
- Resolution, unification, generated-owner decisions, member resolution,
  `protocol_member_names`, `protocol_rejects_direct_member`, and
  `--dump-conformance`.
- src/operator-ledger.x: precedence and compound mappings are parser facts,
  and the member mapping feeds the conversion engine.
- Update and discard helpers. They are operator lowering, with no
  recognition point for a participant's direct update. They are a later
  candidate for the operators component on `%(unit-support KEY)`.
- Native alias insertion. It needs a header-boundary placement, and only
  fixtures use native protocols.
- `install_generated_protocol_symbols` and `record_generated_symbol`. A
  unit's own calls must bind to forwarding members before those members
  exist.

## Risks

- `_generated_function` kept a documented prototype's prose when a
  generated function completed it. Placement binds through
  `bind_syntax` and does not do this. All lib and src headers are
  identical, but no fixture covers a documented prototype of a forwarding
  member.
- The `conform` form becomes macro-visible. Its row and part shapes are a
  contract between the kernel and every rule on that head, as the landing
  rows are for `try`.
- Bootstrap transition: the head must reach the bootstrap before the
  component registers on it. Locally that is two refresh rounds; the first
  converged in 19 s. Editing the component later meets the stale linked
  copy defect that the match plan records.
- The probe scripts list prelude components by name, so each new component
  edits five scripts.

## Recommendation

Proceed in one move: adapter synthesis as `src/component-protocols.x` on
the `conform` head, without the src/macros.x effect change. The move
deletes 157 kernel lines and adds 195 component lines. It keeps all C
byte-identical and adds no SDK operation. It costs about 1 M per
conformance and 13 M per unit. Then stop. Keep declarations, publication,
conformance resolution, owners, operators, the update and discard
helpers, and native aliases in the kernel. Correct the migration table's
protocol row from 1,850 lines to about 300.

Gary decides:

1. Whether the move's cost (+13 M per unit, +1 M per conformance, +1.2
   percent on lib/common.x) and its +38 total lines are acceptable for a
   user-replaceable adapter synthesis.
2. Whether `conform` becomes a documented rewrite head that user rules
   may own.
3. Whether resolution stays in the kernel, as recommended, rather than
   paying the six SDK operations above.
4. Separately, whether to record resolved conformance in interfaces. That
   would save about 38 M per unit and change resolution for participants
   that gain members in later units.

Not measured: Linux and GCC, stages beyond the fixpoint, `make verify`
unit tests, and examples.

## Plan review

- Established facts: resolution decides each member's status and owner,
  and `_generated_owner` decides linkage. The form carries those
  decisions, and the component does not recheck them. Collisions and
  descriptor requirements are reported once, before presentation, as
  today.
- Reuse and deletion: the component reuses the placements, quotations,
  `Type.parts`, `Type.resolve`, and `Code.lowered`. It deletes the
  hand-built AST helpers. The one new mechanism is the `conform` head,
  which is necessary because the trigger is "this unit defines the forward
  converter". No existing family offers that. A per-node `adopt` rule
  would run in the declaring unit, but lib/protocols.x declares the
  built-in adoptions while lib/common.x generates their adapters.
- Idiom: the component is a translator on a form the kernel produces,
  like `try`'s landing. It writes functions as quotations, not as a
  framework.
- Validators and diagnostics: none are added. The kernel keeps the
  collision, requirement, and missing-rule reports it already had.
