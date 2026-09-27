> Status: active
> Production implementation plan, 2026-09-27. No implementation is authorized
> by this document. Research proves a complete try candidate; this change adds
> reusable core support while retaining every existing lowering. Consumer
> migrations follow after the core is bootstrapped and delivered.

# Dual-purpose macro core support

## Result and scope

A macro value supplies one structure for construction and recognition:

```x2c
macro Expression $sum(Expr $left, Expr $right) { $left + $right }
Macro sum = $sum;
List result = sum(left, right);
match (result) { case sum(?left, ?right): consume(left, right); }
Macro twice = macro Expression(Expr $value) => $value + $value;
```

These four forms, `macro open`, producer-attached stage marks, slot-result
semantics, and the demand-driven producer table are the client contract.
Compiler clients never read descriptors, capture rows or stage fields. This
change provides the contract, frame/cleanup producers and transaction support;
it does not replace `_try_block` or any other lowering. Capture-role
consolidation is an independent behavior-preserving change, not a prerequisite.

The detailed representation and grammar remain owned by
[the compiler contract](compiler-dual-macro-contract.md). This plan records
implementation ownership and the proof required for core delivery, not a
second language specification.

## Parser and shared application

`src/macros.x::parse_macro_definition` owns shared typed definition parsing;
`try_parse_macro_expression` owns unapplied named selection. The anonymous
literal enters through `src/expressions.x::parse_primary` and its value-capture
operation; `_parse_call` owns Macro-valued application. The Match arm/context
parser in `src/statements.x` calls `macros.x::try_parse_macro_pattern` for
value-selected cases. `$name` selects a macro,
`$name(...)` retains existing direct invocation, and `m(...)` applies the value
held in ordinary variable `m`. No global-looking template selector or public
field API is introduced. `open` is a definition modifier, not an expression
operation. Anonymous definitions use the same typed parameters and lifetime as
named Macro values.

Use the existing canonical `macrodef`, invocation/capture machinery,
`_capture_pattern`, `_capture_row`, `template.replace`, and deferred invocation
route. Construction and recognition share the existing capture-role layout, using
the consolidated owner if it has already landed;
recognition remains ordinary Match structural recognition. Repeated holes
check equality through that shared relation; sequence projections preserve
order and reconstruct through existing splice machinery. Arbitrary meta
computations remain construction operations and are not inverted.

Prepare immutable template role layout, normalized binder relationships and
Match program once per compiler process. Keep target-unit bindings, Type
projections, origins and effects in the target Compiler. Do not add a separate
AST representation, semantic resolver or recursive validator. Do not ship
`Prototype_*`, name-based native dispatch, or a special case for
`compiler_try_shape` from the isolated implementation.

## Open names and native declarations

Closed definitions keep definition-site references and existing freshening.
An open definition records free references by semantic role before construction:
value reference, Type/tag reference, native callee, introduced declaration,
member label or parameter hole. Only free roles are resolved in the target
unit. Introduced identities remain fresh, member labels remain labels, and
meta producer callees retain the definition environment. Replacing every
identifier with the same name would corrupt these relationships.

Build the general free-role table in the definition producer, using existing
binding identities and local/capture maps. Resolve that table once per target
unit at the enclosing source construct's parsing or canonical binding owner,
while scopes are live. Retain prepared references as internal bound holes.
Do not retain unit scope stacks or resolve names for the first time during
lowering. A shared preparation operation serves literal and constructed code.
For try and defer consumers it is reached by literal parsing, canonical
`bind_syntax` branches, and managed-initializer cleanup production: defer can
become try later. Definition parsing does not prepare target names.

Ordinary declared globals use `Sym.resolve_global` and the ordinary Type and
call binders. Open Type/tag roles use the existing base-scope Type owner;
they do not use caller-local lookup or lose the distinction between a typedef
and a tag. The closed rule is unchanged.

Native callee is a producer role, not a heuristic for an absent declaration.
The try runtime helpers use the existing native String-call contract even if
a target binding has a Type. Their result types are authoritative: push and
landed return `void`; `sigsetjmp` returns `int`. Arguments go through ordinary
expression binding without fabricated parameter signatures. The frame
reference has the existing native `ExceptionFrame` Type; its declaration and
uses share one issued Name. `lib/exception.x` owns that record and push/landed;
generated `exception.h` includes `<setjmp.h>`. `generate.x` keeps selecting
that header through `needs_exception`. Do not add source prototypes or move
includes to make the open skeleton bind.

The phase-5 prototype proves these three native roles. Its fixed three-name
map is evidence, not the general implementation: it does not prove arbitrary
value/Type/tag resolution or declarations added after first preparation.
Focused core probes must exercise general role extraction and those ordinary
owners before claiming general open behavior.

## Producer-attached stages and slots

Phase7 measured the old unconditional support work across the seven-file
corpus: added binder/expression carrier checks consume about 18.4 ms default
and 18.7 ms live in raw diagnostic spans. Ordinary-node recognition must be
absent from the first production version, rather than optimized after migration.
See [fixed-cost evidence](../.context/dual-macro-phase7/README.md); timer
calibration and cross-run attribution limits are explicit there.

Keep one private canonical carrier `(code-value STAGE VALUE EFFECTS)` over
ordinary AST Lists. Plain List inputs default to `source`. `source` enters
ordinary binding. `bound` preserves binding and Type facts without rebinding;
`lowered` also preserves lowered productions and existing lifecycle placement.
AstPos, return context and origins remain compiler context, not duplicated
carrier fields. No client wrapper calls or public stage getters are needed.

Activate carrier recognition only inside the common application's binding
context. Ordinary expression/node binding must not run carrier shape checks,
search retained-hole maps or recognize deferred template carriers. The
application owner enters this context; clients add no wrappers or flags.
Keep ordinary macro-slot evaluation unchanged outside it. Use a distinct
application-binding context from definition-origin policy or native dispatch;
the prototype's shared flag is not the production owner. Standalone new Macro
applications must enter automatically at their application boundary, preserving
the four forms. Do not arm every legacy `_invoke_definition`, which would
restore the ordinary-transaction cost. Direct legacy invocations producing
new effect carriers need entry into the same construction driver before
argument/effect preparation; that edge is not proved by the try prototype.
A single cheap context branch may select the application path; stage
recognition belongs only to that path.

Attach marks where an operation establishes the fact:

| Producing operation | Result |
| --- | --- |
| Parsed or structurally constructed code without semantic binding | source |
| Existing semantic expression/Name producer | bound |
| Existing bound native call producer | bound |
| Region driver after ordinary child lowering | lowered |
| Declaration assembly already published by its existing owner | lowered sequence |
| Landing assembly after region analysis | lowered statement |
| Cleanup placement after region analysis | lowered sequence |
| Macro application skeleton pending ordinary binding | source |

The core supplies the carrier operation and consumers; migrating a producing
operation later owns changing its return boundary. Do not change unrelated
List-returning APIs merely to make all Lists marked. Bind/convert skeleton
expressions through `Compiler.bind_syntax` and `resolve_expression`; stop at
retained holes. Caller placement and Type facts are trusted where the producer
already establishes them. A new conversion-sensitive slot must enter the
existing conversion owner rather than copy its checks.

`Compiler.evaluate_macro_slot` returns a marked result intact before existing
splice flattening. A sequence slot contains a marked ordinary `(seq ...)`;
flatten its code after consuming its effects, never flatten the carrier.
Generic native meta dispatch uses the existing function binding and native
bridge; the prototype's string-name dispatch is deleted.

The first effect vocabulary is `new-name`, `early`, `cleanup`. New-name uses
ordinary fresh-name/binding issuance; early uses `add_early` plus ordinary
adapter memoization; cleanup requests placement already computed by regions.
Producers return data; the target Compiler applies it transactionally. The
producer table initially supplies frame declaration and placed cleanup.
Other producers and effect records are implemented by the first migration
that needs them, not by this core change.

## Transaction ownership

Phase7 measured roughly 5.1 ms default / 5.4 ms live of added snapshot work
across 2119/2124 ordinary transaction entries in the seven-file corpus. The
selective candidate performs extended snapshots at only two entries per mode
and preserves the rollback proof. Use that selective form from the start;
do not first ship unconditional extensions. Open preparation measured only
0.043/0.046 ms total including cache hits and remains once-unit preparation.

Extend the existing `SymTxn` in `src/compiler.x`; do not add a parallel
transaction system. Preserve existing current-scope facts and counters, stage
separate base-scope bindings when current and base scopes differ, and include
`names.adapters`, append positions for `early_decls`, `inits`, and origin
records, plus scalar `origin` and `needs_exception`.

Use selective extension in the existing transaction owner: arm the private
template-construction context before the outer transaction and before frame
allocation, and retain it through child/region preparation, producer evaluation,
application, commit or rollback. Every nested transaction stores whether it
has extended coverage. Snapshot and restore the added fields only when that
coverage is active; ordinary transactions do no added map copies or queue
captures. This preserves baseline transaction behavior outside construction.
Do not activate coverage only around the final `shape(...)` call, which misses
earlier mutations. The application/lowering owner establishes this context;
it is not a public API or a client stage wrapper.

Nested commit makes staged facts visible to its enclosing transaction; outer
rollback restores them. Successful commit preserves borrowed Map owners and
publishes staged rows. The queues are append-only during this operation and
staged map rows are immutable. This contract does not promise rollback of
arbitrary mutation inside existing row objects or destructive queue edits.
Adapter keys come from the producer's existing identity/argument semantics,
not the research probe's fixed key. No second cache validator is added.

## Implementation and bootstrap order

1. Reuse the shared capture-role owner if its independent consolidation has
   landed; otherwise retain the existing capture machinery. The refactor can
   proceed separately and is not a core-support prerequisite.
2. Implement first-class forms, role extraction, open preparation,
   application/recognition, generic slot results and stage carriers in their
   existing parser/macro/Match owners. Retain old lowerings. Add the narrow
   producers and extend `SymTxn` as above. Update the language book with the
   public forms, default closed rule and native role contract.
3. Use an intermediate compiler built from source the checked-in compiler
   accepts to introduce parser support before any checked-in source uses new
   forms. Then use that compiler to compile focused feature fixtures. Refresh
   bootstrap only in the separately authorized production implementation,
   through documented generation targets. Never transplant research compiler
   copies or hand-edit generated C/H.
4. Verify focused behavior and ordinary self-host C comparison with existing
   lowerings unchanged. Review the authored diff for duplicated owners and
   prototype residue, fix it, and use the existing publication command for
   the exact production tree. No new gate or recurring requirement is added.
5. Deliver core support before a separate consumer change. Later migrations
   use the frozen contract and record their cumulative measured cost in the
   compiler contract; the research branch must not be merged as is.

## Evidence and focused validation

Existing research inputs, verified to exist:

- `.context/dual-macro-phase3/capture/probe.x` and `helper.x`: projections.
- `.context/dual-macro-phase3/stages/driver.x`, `pending.x`,
  `retained-cases.x`, `sequence-cases.x`: stages and deferred applications.
- `.context/dual-macro-phase3/hygiene/contextual.x`, `audit.x`,
  `source-case.x`: binder/reference relationships.
- `.context/dual-macro-phase3/compiler-use/open-probe.x`,
  `open-type-probe.x`: target value/Type controls; these are separate from
  the specialized native-callee proof.
- `.context/dual-macro-phase5/rollback-final.log` and
  `final-comparison.json`: final true-open combined proof and corpus result.

Promote focused cases through existing fixture mechanisms, not the entire
research harness. Extend meaningful coverage for construction/recognition,
repeated mismatch, sequence reconstruction, nested scopes, closed/open
references, native result types and no added header prototypes. Retain the
62-case raw C/H comparison as the useful try-consumer readiness proof; it is
not a substitute for the core's general role and conversion probes.

Existing regressions include `macro-template-lexical-shadow.x`,
`macro-name-stability.x`, `macro-sequences.x`, `macro-sequence-nonfinal.x`,
`macro-source-parity.x`, `macro-unit-name-hole.x`,
`macro-match-binder-literals.x`, `meta-template-calls.x`,
`meta-definition-macro-template.x`, `match-api-shadow.x`, and
`match-api-literal-sites.x` under `unittest/compiler-fixtures/`.

The rollback probe must deliberately fail a source skeleton after nested
commit and compare local/global bindings, counters, early declarations,
initializers, adapters, origin records/scalar and exception state. The existing
probe demonstrates append-only/immutable-row rollback, not arbitrary mutation.

Helper transport and REPL interpreter isolation remain separate tracks.
Native preparation in the proved try path holds fixed emission facts; it is
not rollback of arbitrary prepared references. General open references prepared
from speculative declarations need cache transaction ownership or preparation
from committed declaration facts; the try rollback probe does not prove that.
Precise diagnostic attribution, general slot-context conversion and mixed
Name declaration/member uses require focused tests; corpus parity alone does
not close them. Generic role extraction is implementation work supported by
existing owners, not an already measured result.

## Plan review

Ordinary parser/binder producers establish placement, Types and binding
identity; region producers establish lowered lifecycle placement. Consumers
trust those facts rather than revalidate entire trees. Match, capture layout,
substitution, freshening, native call binding and `SymTxn` are reused. The
lasting additions are the four forms, explicit open free-role preparation,
private stage/effect carriers and narrow transactional producers needed to
preserve those established facts. Prototype dispatch and duplicate temporary
bound-slot maps are deleted. Source remains ordinary x2c templates and Match,
with operational work in existing compiler owners. No semantic validator or
new dedicated diagnostic is proposed. Negative cases protect existing repeated
hole recognition, closed hygiene, ordinary placement/conversion behavior and
actual rollback of effects; they do not authenticate constructed code origin.
