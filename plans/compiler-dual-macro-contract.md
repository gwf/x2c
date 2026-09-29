> Status: active -- dual-macro compiler migration, updated 2026-09-28.
> Core support and try/wrapper/cell/Func migrations are on dev. Capture-hole
> support landed at b59b8ade; reconstruction and parameter-scope fixes
> landed at 799875a8. Lambda source recognition and construction are
> published at c99dd68d; the single five-pair cost run measured +3.24% default / +2.30% live. Ownership
> boundaries are recorded in compiler-dual-macro-architecture.md. Next:
> Protocol helper synthesis. Callable-defer helper synthesis is on dev at
> `308709aa`; Var array/map literals are on dev at `aaba3ca4`; try/defer
> cleanup calls are on dev at `4f89a063`. Their timing attempts are recorded
> below. A narrow structural Var optimization could not retain the named
> constructor/update calls in the template under the current rebuild contract.
> The inline captured-lambda factory is on dev at `4576e25e`; shared
> captured-environment typedef binding is on dev at `d546a124`; Func bridge
> factories are on dev at `a4c18301`. Their paired timing attempts are
> recorded below, but the binary-location mismatch invalidates causal cost
> claims. Indirect Func context typedef binding is a concrete hygiene
> exception. The narrow protocol discard template prototype is an exception
> under the process ceiling. Managed declaration cleanup is on dev at
> `c00397af`; discarded destructuring assignment is on dev at `1d5c9b0a`.
> Protocol descriptor storage is on dev at `6a3674bf`; other protocol
> shapes and source coverage remain.
> The current campaign handoff
> below supersedes historical sequencing and authorization in this record.

# Current campaign handoff

Gary authorizes the compiler migration through delivery to dev. The goal is
that x2c is its own meta-language: a reader sees the source construct being
recognized and the C it becomes, without knowing the intermediate tree.
Passing tests supports this reading; it does not replace it.

## Shared direction and immediate next work

The [current architecture survey](compiler-dual-macro-architecture.md)
records the source-backed ownership proposal, shared initialization example,
emission boundary and unresolved lambda construction projection. It is the
next-work design companion; the historical census below is not its substitute.

The campaign is broader than replacing individual case arms. Shared grammar
macros own the relationship between language forms and tree structure, for
construction and recognition. A macro used only for recognition is useful;
it need not have an expansion caller. Survey literal AST matches across the
compiler as candidates, while distinguishing syntax from semantic data,
registries and diagnostics. Do not invent source keywords for bookkeeping.

The current architectural survey traces representative transformations
across their owners and shows illustrative readable clients. It identifies
shared prerequisites, duplicated structural knowledge, responsibilities to
consolidate, and mechanisms that can disappear. Extend that inventory as
sites are implemented: distinguish migrated, directly migratable, needing
a capability, and excluded for a concrete reason. Group them by transformation
and owner, not just keyword or literal occurrence.
The historical 215-head census is a miss-detection aid, not a current site
count, percentage of migratable code, or estimate of removable lines.

Proposed boundaries to investigate, not yet decided file moves:

- Shared grammar vocabulary in `src/grammar.xmacro`.
- Cohesive transformations with input recognition, output templates and
  supporting meta functions readable together.
- Existing shared services for binding, types, traversal, lifetimes,
  diagnostics and emission. Preserve semantic ownership while removing
  repeated knowledge of structural representations.

The proposal should make the small delivery batches serve an explicit
architecture. File merging is not an objective by itself. Routine decisions
belong to the orchestrator; bring Gary consequential unresolved semantics,
compatibility or architectural tradeoffs with concrete examples and evidence.
This discussion authorizes the survey/proposal, not speculative file moves.

## Resume checkpoint (2026-09-28, usage reserve)

Published compiler checkpoint: `f99136f8`, defer record/registration, gate
green. Lambda source recognition/construction is on dev at `c99dd68d`;
retained reconstruction and parameter-scope prerequisites at `799875a8`;
constructed aggregate tag-identity repair at `a9f6d566`. All workers finished
and their results were collected. New workers must use Sol medium. Gary
asked to preserve a committed, pushed handoff before usage reaches zero.

The defer draft's empty member type was a real compiler defect, not a
reason to accept its passing runtime tests. A reduced identity-tag/identity-
field fixture showed `_finish_type` converting a tag identity to a spelling
when binding returned structurally equal syntax. The separate capability
keeps aggregate roots on the whole-type path. After integration, captured
member assignments have `(* const void)` and typedef tags retain identity.

Defer registration now uses adjacent templates and two registered slots.
`_defer_block` and its manual C-shape assembly are deleted. The grammar owns
unary `$deferred` recognition. Capture addresses are assigned in order into
a zero-initialized, hygienically named environment; body and cleanup retain
their lowered stage. Ordinary binding publishes generated environment types.
Callable-defer environment/helper synthesis itself remains a separate shape.

Publication required a local bootstrap refresh after the first stage-0
comparison exposed the previous defer output; the local 192-file comparison
then passed. The next attempt exposed only sidecar differences in nine
fixtures. Each diff was reviewed before updating expectations; the final
gate passed and pushed. Intentional C changes and their reason are recorded
in the source/refresh commits. The single five-pair cost run is complete:
+2.46% default / +4.11% live versus `a9f6d566`. Lambda measured +3.24% /
+2.30% versus `799875a8`. Do not repeat either timing run. At this checkpoint
no jobs or workers remained active.

Next work, in order: the other surveyed transform shapes, protocol helper
synthesis, and complete source-form
coverage across the compiler. Static-local initialization is skipped for
the concrete native `__typeof__`/preprocessor/type-alias boundary recorded
below. Before each next edit, write its complete readable client/template;
keep capability changes separate from adopters. No parser/library repair
should be hidden inside a lowering cleanup.

Primary checkout: `/Users/gary/.codex/worktrees/2fee/x2c`, branch
`codex/dual-macro-migration`. Worker checkouts are free and preserved at
`/Users/gary/.codex/worktrees/grammar-survey/x2c` and
`/Users/gary/.codex/worktrees/helper-survey/x2c`. Their older draft branches
are historical recovery points, not pending work to merge wholesale.
The primary branch contains all integrated authored work. Resume here and
verify origin/dev before starting the next batch. Do not wait for an old
worker or use Gary as the wakeup mechanism.

## Verified checkpoint and remaining sequence

- Last verified publication: `f99136f8` on dev, defer registration gate green.
  Capture-clause holes, safer expansion-depth diagnostics, retained template
  reconstruction and parameter/local redeclaration repairs are landed.
- Lambda adoption is implemented at private checkpoint `f3b86a1d`, including
  the earlier recognition draft. Fifteen focused fixtures passed construction;
  six relevant fixtures passed after retaining root-wrapper traversal.
  Publication passed at `c99dd68d`; the one five-pair cost run measured +3.24% default / +2.30% live. Parser/binder producers
  use the source macros through `rebuild_expression`, without re-entering
  binding. All nine manual lambda constructors were removed.
- Earlier try/wrapper/cell/Func lowerings and their exemplar are landed.
  The recorded cumulative default compiler cost is about +1.1%; it is not
  a measurement of the unpublished lambda draft.

After the architectural proposal, retain the requested dependency order:

1. Lambda recognition and construction are complete at `c99dd68d`.
   Captured-lambda C helper synthesis remains in the later transform survey.
2. Defer registration is complete at `f99136f8`; static-local initialization
   is skipped for its recorded native-type limitation. Callable-defer
   environment/helper synthesis landed at `308709aa`. Next are Var array/map
   literals landed at `aaba3ca4`; other surveyed shapes remain. Gary approved
   combining independently checked, disjoint shapes in one publication batch.
3. Protocol helper synthesis beyond the already migrated wrapper.
4. Complete source-form coverage for parsed statements and expressions:
   no raw `%()` recognition of parsed nodes outside grammar and parser.

Write each target client/template in "Readable form" before implementation.
Remove the old paths rather than retaining parallel implementations. Record
a concrete exception when type dispatch cannot be expressed by a template;
do not force a migration or silently treat exceptions as completed work.
Generated C rebaselines need their reason in the commit. Keep
`agents/lowering-with-macros.md` current when a rule or better exemplar lands.
The three defect tasks under "Migration defect tasks" remain authoritative:
depth diagnostics, parameter redeclaration, and the standalone raw-symbol
sweep. Fix the first two when migration touches their owners; do not turn
the standalone sweep into unrelated recurring campaign validation.

## Coordination, validation and reporting agreement

The orchestrator owns the entire campaign, integration, source review,
publication and cost reporting. Use a single agent unless two changes touch
disjoint files. Delegate bounded independent work in isolated worktrees under
`orchestrate-x2c-work`; workers never gate, push, merge dev, or run timing.
Gary requires Sol, not Astra, for campaign subagents. Explicitly select
`gpt-6-sol` with `medium` reasoning for new workers rather than inheriting
the parent model. Gary reduced the reasoning level to conserve usage budget.
Give workers explicit ownership, acceptance examples and focused checks;
verify their findings and review their authored changes before integration.
Keep ownership of continuation: collect worker completion, integrate or
dispatch the next ready work, and remain active while workers or jobs are
pending. Gary is not the wakeup mechanism. Do not end a turn on a routine
implementation choice already covered by the campaign's authorization.

- Private commits are checkpoints and require no checks merely to commit.
- Between implementation edits: `make build`, then
  `unittest/compiler-fixtures/run.sh check --fixture NAME` for touched
  fixtures. Nothing broader. Resolve known bootstrap transitions locally.
- Land parser/library capabilities first; land their adopters in the next
  batch. Do not bundle capability work with cleanup.
- Review the complete batch, then run `tools/land-dev` once. Do not run its
  broad components separately. On sidecar-only rebaseline failures, read
  the diff, update sidecars and retry once. Other failures require fixing
  the cause with focused checks before retrying. Never rerun a gate on an
  unchanged tree.
- Timing: exactly one five-pair paired run per landed batch, recorded as a
  ledger row. A combined batch receives one batch-level cost row, without
  assigning cost to its individual shapes. No timing at other times.
- Give useful periodic updates during long jobs: verified progress, what
  remains, failures and independent work. Report each batch in five lines:
  commit on dev; change as read; gate result; cost row; next work.

On resumption read AGENTS.md, the lowering exemplar, grammar.xmacro,
_lower_try/$compiler_try in transform.x, the Func templates in expressions.x,
then this handoff, "Readable form" and the ledger. Verify checkout and remote
state before acting; checkpoint hashes above are historical evidence, not
a claim that upstream cannot advance. Do not read `.context/` or the research
branch `codex/compiler-dual-macro-spike`; never merge that branch.

## Historical research status

The following research evidence is retained for context. Its authorization,
cost baselines and implementation status do not override the handoff above.

> Status: reference -- research complete; core support and the try
> migration are on dev. The ledger records the production try row.
> The combined try template/slot/effect/stage candidate passes 62-case raw
> C/H and outcome comparison. The failing-skeleton rollback probe also passes.
> Phase7 selective support passes the same proof; default compiler total is
> +0.133% versus original. Live median is -1.318% with broad overlapping ranges;
> no stable speedup is claimed. The unsupported 5% recommendation is withdrawn.
> Inserted-name shadowing is baseline parity and remains a follow-up.
> Phase7 profiles/removes fixed support work and updates the core/try plans.
> Production implementation is not authorized by this research record.

# Compiler contract for dual-purpose macros

Research evidence is retained on `codex/compiler-dual-macro-spike` at
[`1e2d5607`](https://github.com/gwf/x2c/commit/1e2d5607be514c7205507d3f6e39c889e0cff7ec).
Source offsets refer to the research baseline;
verify current owners before implementation. All `.context/` paths below name
repository paths on that pinned research branch, not files delivered to dev.
The research branch contains compiler snapshots and must not be merged.

The compiler should write lowering shapes using the four Macro forms and
meta function calls in slots. Meta functions produce non-source nodes and
return effects as data; the compiler applies those effects and retains sole
ownership of binding, typing, scope, regions and diagnostics. Raw `%()` for
internal productions belongs inside their meta producers, never lowering
template clients. This recommendation records the revised compiler-contract
request and an external compiler-opportunity survey (survey baseline
`553429f`). The original request attachment (`Pasted text.txt`) and
`dual-macro-compiler-opportunities.md` were external inputs, not files retained
in the pinned research snapshot. Their original locations cannot be resolved
to repository files; consequential requirements and decisions are recorded
here, with archived probe evidence linked below.

This plan's measured compiler baseline is
`1b23aaa7e103461c3b219b9e10546aeb35384b60`.
Current source, rather than historical line numbers, is authoritative.
The prototypes remain in `.context/dual-macro-phase3/` through phase7 and
managed isolated worktrees. Nothing in this plan claims that its proposed
semantics already ship in x2c. **Do not merge this research branch as is.**
`.context/dual-macro-phase4/combined/` tracks full copies of five compiler
sources (compiler, expressions, macros, parse and transform), alongside a
prototype module. They are research snapshots, not production owners.
Production changes must be authored separately against current dev.

The narrowed combined try path, including open native calls and producer-attached
stages, is demonstrated. First production work remains
the independent capture-role consolidation; later lowering migrations integrate
the proved common result/effect path into ordinary compiler owners. Prototype
wrappers and native dispatch are scaffolding, not additional public APIs.

| Requested decision/proof | Result in this spike | Evidence |
| --- | --- | --- |
| Four forms plus meta slot calls | Frozen client semantics, including open native roles and producer-attached stages; implementation still isolated | parser3/capture; phase5 incremental patch; sections 1/8 |
| Internal-node producers | Demand-driven owner/producer inventory; no raw internal builds in clients | grammar-producer-policy.md; appendix |
| Effects with rollback | Extended existing transaction passes real early/memo writes, failing skeleton, nested rollback and borrowed-map commit | phase4/combined and root-final-probe.log |
| Source/bound/lowered insertion | Combined compiled-in template, parsed meta slots and carriers pass 62-case raw comparison | phase4/combined; phase4/comparison/final-comparison.json |
| Open versus closed names | Compiled-in target value signature and primitive cast Type lookup succeed; caller-local native-helper failure is baseline parity/follow-up; closed regression passes | compiler-use/open-policy.md and logs |
| Tree rules | One bounded return-normalization rule works with nested traversal and pruning | stages/driver.x |
| Field grammar | Source/derived layouts and 215-head census recorded; dynamic-head reconciliation incomplete | grammar-fields.md, grammar-head-census.md |
| Cost | Phase5 five-pair compiler medians +1.40% default, +1.94% live; phase4 +1.34% retained as history | phase5/paired-summary.json; phase4/comparison/results.md |
| Name/origin/sequence | Bounded role/origin/sequence probes; general combined coverage remains limited | grammar-mixed-name.x, hygiene/source-case.x, stages/sequence-cases.x |

## 1. Surface contract

| Form | Meaning | Evidence |
| --- | --- | --- |
| `Macro m = $name;` | Select a registered global named definition without invoking it. | Phase 2 parser3 and complete-value probes. |
| `m(args)` | Apply the selected value to logical arguments; return code for ordinary insertion. | Phase 2 construction and phase 3 retained-call construction. |
| `case m(?a, ?b):` | Recognize using the same definition; publish logical captures only after success. | Phase 3 capture, hygiene and retained/expanded cases. |
| `macro Kind(...) => ...` | Anonymous macro value with typed holes and lexical captures. | Expression factories, relay, composition and invocation probes; category coverage is narrower than this grammar. |
| `$producer(args)` inside a template | Existing meta-call grammar fills a slot with code and effect data. | Existing `meta-call`/`macro-slot` owners; the new common result/effect adapter is proposed. |

Dollar signs select registered global macros and identify holes inside their
bodies. Local named macros retain their existing lookup/invocation rules;
this spike does not redefine ordinary function/macro name collisions.
Ordinary Macro variables have ordinary names. Parentheses apply either a
named macro or a Macro value. No parentheses means selection of a value.
`$name(args)` retains existing named macro behavior, including meta
computations; it must not become universal deferred construction.
`case m(?a, *items):` uses existing Match scalar/sequence capture notation.
The sequence occupies one logical List value, including the empty List.

A sequence-valued meta slot uses the existing `$producer(args)...` insertion
form; the new result adapter aggregates its effects before flattening its code
values. This is existing grammar with proposed common result semantics, not a
new public function family.

Compiler lowering clients must not read descriptor fields, capture rows,
fresh rows or invocation markers. Macro parsing, application and stage owners
necessarily read those records; this restriction is on their clients, not an
impossible prohibition on the implementation itself. Meta producers may inspect canonical AST and supplied Type/fact data.
Lowering clients do not inspect result envelopes or build internal heads.

The required additions beyond those four forms are:

* An explicit **`open` definition modifier**, proposed as
  `macro open Statement $region(...) { ... }` and
  `macro open Statement(...) => { ... }`. This is one real resolution rule,
  not a getter, contextual pattern introducer or API family. Default is
  closed; explicit `closed` syntax is unnecessary. This modifier is a proposed
  addition to production, implemented in the isolated phase5 parser.
* Existing `Compiler.bind_syntax(value, AstPos, return_type)` for consuming
  constructed code in a specified target compiler. Callers also retain
  ordinary compiler origin context. A runtime Macro call cannot guess which
  target Compiler owns the result; binding supplies that context explicitly.
* Private meta producer functions for internal forms, listed below. Their
  calls use ordinary existing slot-call syntax; there is no public getter,
  stage-marker method, descriptor API or new x2c-prefixed API family. `%()`
  is confined to those producers and their private canonical helpers.

### Complete compiler-client freeze list

1. `Macro m = $name;` selects; `m(args)` constructs;
   `case m(?a, ?b):` recognizes; `macro Kind(...) => ...` is anonymous.
2. `macro open Kind ...` explicitly selects target-global free-name policy;
   default user definitions remain closed.
3. `$producer(args)` and sequence slot insertion return ordinary canonical
   values plus ordered effects, consumed by the one common application owner.
   Effects are applied by the caller's existing Compiler transaction.
4. **The producing operation attaches its stage** when it finishes: parsed or
   newly assembled unbound code is source; resolved references/typed expressions
   are bound; completed transform/region output is lowered. An ordinary List
   with no carrier defaults to source, never to bound/lowered by shape. The
   binder binds source skeletons and stops at prepared bound/lowered boundaries;
   parent conversions retain ordinary ownership. A client passes the producer
   result directly, with no stage wrapper calls or stage-field inspection.
5. The producer table names canonical owners and required facts. Only producers
   demanded by a migration are built. The first try proof needs frame-declaration
   and cleanup-placement producers, with new-name, early and cleanup effects.

6. Open references to generated-header-only functions emit native String
   callees with the authoritative producer-declared result Type. The exception
   helpers and sigsetjmp use this rule; typed source callees added forward
   declarations and broke raw byte parity. Include placement stays unchanged.
7. General free-role extraction belongs to the production application owner
   before any lowering other than try migrates. `_prototype_open_code` currently
   recognizes three call names by hand; that special case is not production
   support for arbitrary open definitions.

This freezes semantics, not public descriptor fields or a new API family.
The current try body contains native calls directly. Its prepared free-reference
inputs and producing-operation stages are supplied by ordinary owners behind
the common adapter. Future hygiene improvements must preserve these forms, not
add another client calling convention.

No new `Params` kind is needed: `Param $parameters...` already exists.
The wrapper probe `grammar-param-sequence.x` executes 6. Substituting `Decl`
for `Param` in that slot fails kind inference; the two are not aliases.
Use one trailing sequence in an interface. Existing named invocation parsing
greedily consumes its comma tail, so two ungrouped sequences cannot be frozen
as a working call convention. The demonstrated value call accepts the source tail as separate arguments
and groups it internally into one logical sequence. Passing an already grouped
List as one tail argument is not the same ABI and can produce a nested List.
Multiple logical sequences need a tested grouped-call convention before use;
they are not frozen by this spike.

Anonymous definition must not inherit named local macro restrictions merely
because it captures lexical values. Registration and lexical capture are
separate facts. In particular, an anonymous Unit value need not publish
anything until insertion at AST_UNIT. This is a compatibility-preserving
design requirement, not a capability demonstrated by the current prototype.

## 2. Free names: closed by default, explicitly open globals

Closed macros preserve definition-site references. Introduced declarations
are fresh per expansion; parameter code retains its existing identities.
This is the existing rule, not a new interpretation of closed templates.
`src/macros.x:3634-3681` records introduced local placeholders and fresh rows;
`expand_macro_invocation_node` allocates them at insertion. The
`macro-template-lexical-shadow` fixture protects the existing namespaces and
shadowing behavior.

An open definition stores each free reference by its grammatical role and
name until insertion. At insertion it resolves **in the target unit's global
environment**, not in the caller's block scope. A local `sigsetjmp` or local
typedef `ExceptionFrame` must not capture the generated skeleton. Template
locals still use structural lexical binding and freshening. Hole values are
never subjected to this global resolution policy.

This applies to program value, typedef and tag roles, not member labels.
A meta function called in a template slot remains a definition-environment
computation: `open` does not redirect that producer call into the target program.
Program references within its returned code follow the supplied stage/free-name
contract. The common adapter must distinguish these grammatical roles. Existing
`Sym.resolve_global`/`reference_global` are the value lookup owners.
Existing Type/declarator binding owns global type resolution, but needs an
explicit global projection: retaining a String Type name is insufficient.
`_finish_type` (`src/parse.x:2195`) calls `Sym.local_type`, which searches local
typedef/tag scopes (`src/compiler.x:3686`). Likewise `x2c.ident` expresses
deferred reference lookup, not the required global-only policy.

Compiler templates compiled into the binary must not store its binding IDs
as program IDs. `_resolve_identifier` rejects identities not issued in the
target context (`src/expressions.x:1341`). Open free references therefore
have no target binding identity until consumption. Open recognition resolves
the same fixed references using the subject's Compiler and compares identities;
it must not accept another reference simply because its name is equal.

### What the compiled-in open probe establishes

The isolated `macro open Expression` is compiled into the compiler binary.
Its definition refers to an `int(int)` function in that compiler; the target
program defines a same-named `double(double)` function with an observable
call counter. The resulting bound call has the target binding and double
signature, and the executable observes one target call. The already bound
argument survives insertion. See `.context/dual-macro-phase3/compiler-use/open-policy.md`, the native
log and transformed-code log. This uses private caller plumbing, not yet the
complete public `m(args)` routing. The default closed hygiene regression also
passes in the new parser.

A second compiled-in template casts through `CompilerOpenType`: the compiler
has an int typedef, the target has a global long-double typedef, and the caller
has a same-named local int typedef. Base-only ordinary Type resolution produces
an explicit long-double cast; native execution passes and the local remains int.
Root independently reproduced it. This proves one cast Type role resolving to
an existing primitive, not aggregate/tag coverage or preservation of typedef
labels in emitted C. See `.context/dual-macro-phase3/compiler-use/open-type-*` and `open-policy.md`.

### Shadowing is baseline behavior, not a rewrite blocker

The original open probe injected a call to `_compiler_open_target`; the baseline
has no such injected call, so running its unchanged fixture cannot establish
equivalent native compilation failure. The comparable control is the existing
runtime helper `x2c_exception_push`, shadowed by a caller-local int around try.
Root reran Gary's exact program against the unmodified baseline and bound-hole
control, with common home and identical source path. Both native builds fail
at the generated helper call with `called object type int is not a function or
function pointer`; generated C is byte-identical. Logs and source are in
`.context/dual-macro-phase4/`. This is current lowering behavior, not a regression
introduced by templates. The open-template control is at parity on this case.

There is no recommendation to retain per-unit parser scope stacks. The
phase5 proof prepares the open definition's free-reference inputs once per
target unit at the enclosing try/defer parse or ordinary binding operation,
with live scopes. Managed-initializer cleanup also prepares them when its
producing declaration is bound: its later defer can become a synthetic try.
The lowering receives prepared inputs through the common application owner;
it never resolves free references late or reads the preparation map.
The cache is private per Compiler, not global across target units.

**Contract rule: generated-header-only function references emit as native
String callees with the producer's declared result Type.** This applies to
exception runtime calls and sigsetjmp. Native runtime references require an
explicit distinction from ordinary open source-function references. `_catch_call` currently constructs native String
callees and supplies result Types. `lib/exception.x` declares push/landed with
`ExceptionFrame *`; its generated `exception.h` includes `<setjmp.h>` and defines
the frame's `env` field. `generate._primary_include` adds that header only when
`needs_exception` is set. The isolated resolver preserves these existing native
callee/result facts: void for push/landed and int for sigsetjmp, plus the native
frame Type in the prepared frame reference. It does not parse exception.h,
create substitute source declarations, issue fabricated program binding IDs,
move includes, or introduce a second type checker. The C compiler still sees
those declarations at the existing generated-header boundary.

The phase5 adapter records `Sym.resolve_global` facts while scopes are live,
but these three known native roles retain the String-call projection even when
an x2c declaration is visible. Projecting a typed source callee instead emitted
extra push/landed forward declarations, breaking raw C parity. Ordinary open
source references should retain resolved binding/Type holes and ordinary call
conversion; the earlier value/primitive Type probes establish that separate
case. Native roles must be identified by the authoritative producer table,
not by failure to find a Type or by a guessed function signature. **Contract rule: general free-role extraction is required in the production
application owner before any lowering other than try migrates.** The current
`_prototype_open_code` recognizes three call names by hand. That bounded
adapter is not a general value/Type/tag resolver. Its extra resolved-fact rows are audit scaffolding;
the production owner should keep only facts its projection or recognition uses.

Preparation applies to definition free roles before parameter substitution;
it does not reinterpret retained hole code. Compile-time producer callees
remain closed. The native String projection preserves baseline shadow behavior:
fully hygienic emission under caller-local helper names remains a follow-up.
First-use visibility, later declarations, aggregate/tag roles and arbitrary
open recognition need further implementation evidence; they are not silently
settled by these three native roles.

Rejected defaults: infer open from being in src/, make all macros open, or
silently replace unresolved closed identities by same-named globals.
Supplying every fixed runtime callee and Type as a hole is a viable control
prototype but hides the intended code behind plumbing; it is not the chosen
long-term compiler surface.

## 3. Bound holes and ordinary binding

The application has two inputs with different responsibilities: an unbound
source skeleton, and already bound/typed logical hole values. The application
owner must retain those boundaries until `Compiler.bind_syntax` consumes it.
Flattening all substitutions first loses the distinction.

At each skeleton position, ordinary binding, lexical declaration publication,
scope, typing and conversions run as today. At a bound hole boundary the
binder returns the original subtree and does not recursively bind, publish,
convert or lower its contents. This includes whole Statement and Decl holes,
not only Expr values. Type holes retain their existing Type value; they must
not be reinterpreted through a newly shadowing typedef. Param holes preserve
issued parameter identities and feed the ordinary function owner.

The enclosing skeleton operation may still require a conversion of an Expr
hole: for example a target call parameter or initializer asks the ordinary
conversion owner for its expected Type. That conversion surrounds the operand
once; it does not mutate/rebind the operand internally. Already-converted
content stays as supplied. A blanket rule to skip all conversions around a
hole would generate wrong calls; a rule to re-type its complete contents would
break the trust boundary.

Use invocation-local hole slots and existing capture-role information in the
ordinary binder. These slots are private temporary structure and must be
consumed completely; they are not an origin certificate or a second validator.
Ordinary legal hand-built Lists remain accepted. Direct `bind_syntax` callers
without an application boundary retain existing behavior.

Current behavior establishes less than this requirement. `bind_syntax`
documents trust in types/identities (`src/parse.x:2454`), but visits statements,
declarations and return context. `resolve_expression` returns a typed Expr
unchanged only when `_expression_requires_resolution` finds no work remaining
(`src/expressions.x:1004,2450`). This is not a whole-hole shortcut.
Parsed `(return CONTEXT EXPR)` and lowered `(return EXPR)` have different
arities (`src/transform.x:3068`). Rebinding a completed lowering through the
parsed return case is wrong; preserving a lowered Statement hole is necessary.

For try/defer/catch parity, retain `_region_binding` allocation and its order.
Pass its issued identities as Name holes; do not introduce a second frame or
handler through a literal template declaration. Ordinary declarator binding
accepts an existing binding (`src/parse.x:2326`). Existing fresh rows do not
freshen explicit Name inputs a second time.

The intended try template uses meta producers for semantic pieces and effects.
For example, this is an interface sketch, not a probe that already works:

```x2c
macro open Statement $try_region(Name $frame, Statement $declarations,
  Statement $body, Statement $landing, Statement $cleanup) {
  {
    $frame_declaration($frame)...
    $declarations
    x2c_exception_push(&$frame);
    if (!sigsetjmp($frame.env, 0)) $body
    else { x2c_exception_landed(&$frame); $landing }
    $place_cleanup($cleanup)...
  }
}
```

The phase5 body writes the three runtime calls directly. The common owner
supplies prepared native free-reference projections; they are not whole call
holes built by `_region_call` or `_catch_call`. The frame declaration and
cleanup placement remain meta slots. Pure shape does not decide cleanup
ancestry, staticness or conversion.

### Stage attachment at the producer

| Try producer | Result stage | Established fact / retained responsibility |
| --- | --- | --- |
| Literal parsing or canonical unmarked List | source | Ordinary binder still resolves and types it. No stage guessed from its head. |
| Frame/new-name consumer | bound | Allocates the original fresh binding, returns its typed native frame reference; declaration producer extracts the same binding. |
| Catch declaration assembly | lowered sequence | Completes existing typed declarations, filtering and preparation code before returning. |
| Region body driver | lowered | Runs the existing `_inside` walk and exit rewriting before returning. |
| Landing assembly | lowered | Builds the existing catch choice and unhandled cleanup after their children are lowered. |
| Cleanup computation | lowered sequence | Computes placement/exit code with existing region owners; also retains raw code internally for unwind bookkeeping. |
| Frame declaration meta slot | lowered | Returns canonical native declaration for the supplied binding. |
| Cleanup meta slot | lowered plus cleanup effect | Returns prepared cleanup placement data; consumer sets needs_exception. |
| Macro application / skeleton | source | Common application evaluates slots/effects then uses ordinary binding. |

The isolated client's actual application is:

```x2c
Macro shape = $compiler_try_shape;
return c.bind_syntax(shape(frame_code, declarations, body, landing,
  cleanup_code), AST_BLOCK, c.return_type);
```

`frame_code` and `cleanup_code` are already producer results; clients need no
`Prototype_bound`, `Prototype_lowered` or `Prototype_sequence` calls. Their
raw counterparts remain inside ordinary region bookkeeping. Private helpers
such as `_region_call` still return raw Lists where raw canonical consumers
need them; a boundary producer must attach the stage before supplying that
result to a Macro. No global change to List meaning or unrelated callers is
needed. Probe-only explicit wrapper calls remain disposable test scaffolding.
The specific typed frame reference demonstrates address/member use and the
same declaration binding; generic mixed Name projections remain limited.

The earlier phase3 parity control supplied declarations, runtime calls,
condition, body, landing and cleanup as bound/lowered holes; it did not
implement slot calls or effects. The phase4 combined candidate now uses actual
meta slot calls for the frame declaration and cleanup, carries stages on slot
results, and applies the three effects under the extended transaction. Its
62 outcomes and raw C/H files match the baseline, as detailed below.

The evidence required for this narrowed proof is a compiled-in template
applied to a target unit with prepared free references, retained bound/lowered
holes, transaction rollback, and byte-identical C/H on the corpus. That proof
passes. Successful matching under local shadows is a hygiene follow-up:
current baseline behavior also fails for the shadowed native helper. Generic
open resolution, Type-shadow coverage and conversion-count instrumentation
remain unproved. The corpus covers 46 lexical-try fixtures, the seven-file
compiler/tokenizer corpus, and exception-hot-paths in default/live modes.
The earlier invalid `seq{`, wrong Expr/Statement categories and lost origins
were fixed in the construction/binding path, without output normalization.
Alpha-equivalent C was not substituted for the requested byte comparison.

## 4. Canonical grammar and stage policy

The grammar appendix below records ordinary canonical Lists, not a new AST
language. Source fields are written in x2c templates. Derived fields remain
owned by the parser, binder, resolver, transform and emitter. Templates match
source-bearing structure. Source/derived is a field classification, not a rule
to erase all derived information: local binding IDs are compared by an
injective lexical alpha-renaming relation, repeated references preserve that
relation, and external/free IDs compare rigidly. Derived Expr types, return context and diagnostic
wrappers do not become user holes accidentally. Explicit cast/declaration
Types and literal payloads are semantic/source content and must remain.

Recognition supports parsed/bound code and a declared projection of equivalent
lowered forms, such as the two return arities. It does not invert arbitrary
lowering or meta computation. A closure record is not recognized as a lambda
merely because it arose from one. Exact internal matching lives in meta producers using `%()`; clients use
their returned facts or source Macro cases.
Retained invocation matching compares descriptor/value structure; expanded
body matching uses the body and binding relation. These are distinct input
stages selected internally, with the same `case m(...)` surface.

No public source grammar is added solely to name an IR tag. Give a production
a source form only when it has language-level behavior worth expressing.
For existing source forms, reuse their parser and ordinary compiler owners.

## 5. Shared meta rule driver and compiler orchestration

Provide one `rewrite_code` meta function operating on canonical code with an
ordered set of rule functions. Each rule uses Macro cases, returns no-change
or code plus ordered effects, and can prune a semantic boundary. The driver
uses the existing `Ast.rewrite_children` copy-on-change machinery; export/reuse
that owner for native meta instead of keeping a copied walker. Keep rule
selection order explicit. For the initial compiler contract use preorder,
first matching rule, stop at its replacement, and recurse once through children
only when no rule matches and the node is not pruned. Do not automatically
revisit a replacement. Existing fixed-point normalization
remains the compiler driver's job. Avoid a configurable visitor framework or
arbitrary recursive meta expansion disguised as a traversal policy.

`.context/dual-macro-phase3/stages/driver.x` demonstrates one actual transform family: bare-return
normalization from `_block_returns` (`src/transform.x:1422`). A named `$bare`
Macro is selected as a value, `case rule()` recognizes it, a meta producer
creates the existing lowered Var/void return, and the driver handles a nested
if while pruning a nested lambda. It uses one active Macro rule and one fixed meta producer, not multiple
rule functions or effect aggregation. It checks structural output and unchanged
identity on a second pass. This applies in the existing owner context where
Var return behavior was selected; it is not a rewrite of every void function.
The isolated fixture copies child rebuilding only to make the native-helper
probe executable; that copy must not become a second production owner.

Compiler `_node`/`_step`/`_finish` still owns normalization order, block/sequence
placement and newly generated declarations. Region `_rewrite` still owns loop,
switch and function boundaries, cleanup ancestry and origin restoration until
those facts are supplied to equivalent meta rules. There are roughly fourteen
clients of shared child rebuilding, not fourteen independent implementations.
The pure meta driver cannot discover a cleanup barrier by walking arbitrary
List fields, or interpret every nested Type/descriptor as program code.

Typed dispatch belongs in meta slot functions using compiler-supplied resolved
facts. Compiler queries, effect application and transaction ownership remain
compiler-side. `regions.x` supplies analysis; it is not merely a template.
Survey sites follow this boundary: try/defer/catch and wrappers have large
source skeletons; Func calls have a reusable construction/recognition shape;
scope cells combine shape with allocation; lambda source patterns coexist
with derived capture layouts. Type serialization, protocol selection and
cross-arm unification remain existing semantic owners, exposed as supplied
facts rather than duplicated helper validators.

Meta computations are not automatically invertible. Structural Macro bodies
remain dual; meta slots with known arguments can supply fixed structural parts.
A requested capture occurring only inside an arbitrary computation cannot be
recovered by running that computation backward. Recognition must not execute
registration/allocation effects. The compiler's first recognizers must use
structural templates and already supplied slot facts; recognition of genuinely
computed slots needs an explicit dependency/comparison projection and remains
unproved. This limitation must not change the meaning of an existing Macro
case when the full feature lands.

## 6. Cost and preparation

Construction must not run a recognition match just to map positional arguments
to formals. Prepare both directions from the one formal/role table: indexed
substitution for construction, ordinary prepared Match for recognition.
Prepare immutable source body, formal projections, introduced binder slots,
open-reference roles and Match program/layout once per definition in a compiler
process. Per application: fill slots, allocate genuinely introduced bindings,
bind the skeleton, and perform required parent conversions. Do not rescan
already typed hole contents.

Target-unit bindings, resolved Types, origins and issued IDs are not globally
cacheable. They belong to the target Compiler/session; reuse existing symbol
resolution and Match/cache owners rather than a new cross-unit cache. Anonymous
values with different captures are distinct preparations unless the existing
canonical cache establishes equality. No new recurring checkpoint is proposed.

The historical phase4 combined candidate has five alternating paired samples after warmup,
using the same source paths, home, flags and binary throughout. All 62 comparison
outcomes/raw C/H outputs and all 32 final timed C/H files match baseline without
normalization; binary hashes are unchanged before/after. Root independently
reran the manifest comparator and recomputed all four group medians.

| Translation workload | Baseline median s | Combined median s | Change |
| --- | ---: | ---: | ---: |
| Seven compiler/tokenizer files, default | 6.263 | 6.347 | +1.34% |
| Same corpus, live | 7.864 | 7.611 | -3.21% |
| Exception-heavy translation, default | 0.574 | 0.576 | +0.42% |
| Exception-heavy translation, live | 0.640 | 0.636 | -0.60% |

The ranges overlap. Compiler live-mode samples are particularly noisy:
baseline 7.158-9.811 s, candidate 7.487-10.753 s. A transient stage-1 compiler
process was observed, but its owner could not be established. Session builds
were stopped; strict host isolation is not claimed. Negative deltas are not
proved speedups, and these samples do not establish precise overhead. They
measure actual construction, existing invocation Match/capture extraction,
substitution, allocation, source binding and meta slot/effect work, not a
substitution proxy. Diagnostic text, runtime exception execution, cold
preparation and allocation counts were not measured. No recurring checkpoint
or new target is proposed.

Prepare the immutable body/role layout, existing Match program, introduced
binding layout and compiler-native producer bindings once per process. Keep
unit-specific references/origins/types and transaction deltas per Compiler.
The proof deliberately reuses legacy invocation Match extraction; indexed
construction projections are a later optimization of that same role owner,
not a second implementation or a prerequisite for capture-table consolidation.
Do not walk already bound/lowered payloads to rediscover facts. Prototype stage
constructors, string-tag dispatch and per-call origin stripping must be replaced
by the common prepared owner before production lowering clients use them.
The current cost evidence supports proceeding with the narrow design; it does
not promise that all migrations will keep performance unchanged.

Earlier phase-3 bound-hole control samples are preserved under
`.context/dual-macro-phase3/stages/cost/`; current combined evidence is
`.context/dual-macro-phase4/comparison/results.md`, with parameterized scripts,
samples, ranges, hashes and comparison manifests.

### Phase5 cost on the final open-body candidate

The same runner repeats five alternating pairs after warmup, with common
absolute source paths, home locations and flags, no effect probe, and unchanged binary hashes.
All 32 timed C/H files are identical between labels. Session builds were held
throughout timing; unrelated host activity is not fully controlled.

| Translation workload | Baseline median s | Phase5 median s | Change |
| --- | ---: | ---: | ---: |
| Seven compiler/tokenizer files, default | 6.061 | 6.146 | +1.40% |
| Same corpus, live | 7.178 | 7.317 | +1.94% |
| Exception-heavy translation, default | 0.565 | 0.572 | +1.37% |
| Exception-heavy translation, live | 0.625 | 0.648 | +3.69% |

Default compiler ranges are 6.018-6.084 s versus 6.116-6.168 s: they do not
overlap, and every paired candidate observation is slower. Report this as
observed modest overhead, not zero cost or a proved noise-only change. Live
compiler ranges overlap (7.151-7.416 versus 7.283-7.345 s); exception live
ranges do not (0.610-0.637 versus 0.642-0.652 s). Five samples in one window
do not establish a stable long-run distribution. No runtime exception execution,
full build timing, cold preparation, allocation counts or application counts
were measured. This is the total cost of the one migrated lowering plus its
supporting path, not an isolated transaction microbenchmark.

Evidence: `.context/dual-macro-phase5/samples.json`, `paired-summary.json`,
`timed-artifact-digests.json` and `checksums-after.json`. The immutable body,
formal projections, native free-role plan and producer bindings should be
prepared once per process; target reference facts/projections once per unit.
The prototype still scans/clones the open body per application and uses legacy
invocation Match extraction. Those are concrete preparation opportunities,
not evidence of an already achieved saving.

### Running migration cost and recommended budget

Keep one ledger row per migrated lowering, with the candidate and baseline,
corpus, number of applications, transaction count, paired median/range and
observed incremental delta. Replacing a prior candidate replaces its ledger
row: do not count successive versions of try twice. The current entry is:

| Ledger row | Candidate / baseline | Default total / increment | Live total / increment | Applications | All / extended transactions | Measured per-try spans ms |
| --- | --- | --- | --- | --- | --- | --- |
| Original baseline | original / original | 0% / baseline | 0% / baseline | 0 template applications | Historical transaction counts not instrumented | Not measured |
| Try/defer/catch, first migration including selective core | phase7 final / original | +0.133% / +0.133 pp | -1.318% / -1.318 pp | 2 each mode | 2119 / 2 default; 2124 / 2 live | 1.488 default / 1.818 live |
| Same candidate, exception workload | phase7 final / original | +0.869% / separate workload | +0.122% / separate workload | 4 each mode | 265 / 4 each mode | 0.931 default / 0.857 live |
| Historical unconditional-support control | phase5 / original, rerun in phase7 window | +1.625% / not an additional migration | -0.117% / not an additional migration | 2 each mode | 2119 / 2119 default; 2124 / 2124 live | Historical phase6 profile |
| Try/defer/catch, production on dev (2026-09-27) | try migration / dev af3354b8, same window | +0.15% / first production row | +0.29% / first production row | 2 each mode | 2540 / 347 default; 2517 / 347 live | Not measured |
| Same production candidate, exception workload | try migration / dev af3354b8, same window | +1.43% / separate workload | +1.04% / separate workload | 4 each mode | 323 / 57 each mode | Not measured |
| Try client, wrappers, scope cells and Func calls (2026-09-27) | dual-macro-lowerings / dev af3354b8 (before try), same window | +0.26% / cumulative | +0.61% / cumulative | Not counted | Not counted | Not measured |
| Same batch, exception workload | dual-macro-lowerings / dev af3354b8, same window | +0.76% / separate workload | +1.90% / separate workload | Not counted | Not counted | Not measured |
| Readable form: Func, try, wrappers, scope cells (2026-09-28) | readable-sites / dev c2f06700, same window | increment +0.80% | increment +0.69% | Not counted | Not counted | Not measured |
| Same batch, exception workload | readable-sites / dev c2f06700, same window | increment +0.25% | increment +0.44% | Not counted | Not counted | Not measured |
| Lambda source recognition and construction (2026-09-28) | c99dd68d / prerequisite dev 799875a8, same corpus and home | increment +3.24% | increment +2.30% | Not counted | Not counted | Not measured |
| Defer record and registration (2026-09-28) | f99136f8 / prerequisite dev a9f6d566, same corpus and home | increment +2.46% | increment +4.11% | Not counted | Not counted | Not measured |
| Callable-defer helper synthesis (2026-09-28) | 308709aa / dev 2807858c, binary paths differ | confounded raw +18.10% | confounded raw +15.45% | Not counted | Not counted | Not measured |
| Var array/map literal calls (2026-09-28) | aaba3ca4 / dev 534722aa, binary paths differ | confounded raw +18.24% | confounded raw +16.16% | Not counted | Not counted | Not measured |
| Try/defer cleanup calls (2026-09-28) | 4f89a063 / dev cb6605a4, binary paths differ | confounded raw +13.63% | confounded raw +15.56% | Not counted | Not counted | Not measured |
| Inline captured-lambda factory (2026-09-28) | 4576e25e / dev 4f89a063, binary paths differ | confounded raw +15.04% | confounded raw +11.54% | Not counted | Not counted | Not measured |
| Shared captured-environment typedef (2026-09-28) | d546a124 / dev 4576e25e, binary paths differ | confounded raw -56.40% | confounded raw -47.94% | Not counted | Not counted | Not measured |
| Func bridge factories (2026-09-28) | a4c18301 / dev d546a124, binary paths differ | confounded raw -56.79% | confounded raw -47.95% | Not counted | Not counted | Not measured |
| Managed declaration cleanup (2026-09-28) | c00397af / dev a4c18301, distinct output dirs | confounded raw -60.16% | confounded raw -52.37% | Not counted | Not counted | Not measured |
| Discarded destructuring assignment (2026-09-28) | 1d5c9b0a / dev c00397af, distinct output dirs | confounded raw -61.37% | confounded raw -52.63% | Not counted | Not counted | Not measured |
| Protocol descriptor storage (2026-09-28) | 6a3674bf / dev 1d5c9b0a, same staged path and cleared output dir | raw -60.99%, cause unassigned | raw -53.42%, cause unassigned | Not counted | Not counted | Not measured |
| Protocol direct-update body (2026-09-28) | 7e8abade / dev 6a3674bf, same staged path and cleared output dir | raw -61.48%, cause unassigned | raw -53.67%, cause unassigned | Not counted | Not counted | Not measured |
| Parsed if, while/do, return, defer recognition (2026-09-28) | 0e0006f4 / dev 7e8abade, same staged path and cleared output dir | raw -61.41%, cause unassigned | raw -53.44%, cause unassigned | Not counted | Not counted | Not measured |
| Bound loop/truth and region restore recognition (2026-09-28) | fe8fd71a / dev 0e0006f4, same staged path and cleared output dir | raw -61.11%, cause unassigned | raw -53.48%, cause unassigned | Not counted | Not counted | Not measured |
| Bound switch and region statement recognition (2026-09-28) | f6606dbf / dev fe8fd71a, same staged path and cleared output dir | raw -61.09%, cause unassigned | raw -53.45%, cause unassigned | Not counted | Not counted | Not measured |
| MatchRow and expression origin preflight (2026-09-28) | 89da87d0 / dev f6606dbf, same staged path and cleared output dir | raw -61.51%, cause unassigned | raw -53.83%, cause unassigned | Not counted | Not counted | Not measured |
| Match binder and cold raw-symbol repair (2026-09-28) | 65344a45 / dev 89da87d0, same staged path and cleared output dir | raw -61.21%, cause unassigned | raw -53.28%, cause unassigned | Not counted | Not counted | Not measured |
| Later lowerings | Not migrated | Not measured | Not measured | Not measured | Not measured | Not measured |

The six rows from callable-defer through Func bridge factories are raw
timing records, not valid migration cost estimates. Their baseline binary
ran from `debug/dual-macro-baseline-x2c` and the candidate from
`builds/0/x2c`. `x2c_stage_dir` in `src/utils.x` recognizes only a compiler
under `<home>/builds/<stage>`; `x2c_home_libexec` then selects that stage's
helper directory. The `d546a124` revision appears as the fast candidate in
one run and the slow baseline in the next, consistent with a binary-location
confound. Those adjacent builds are not byte-identical saved binaries, so
the path effect's exact share is unmeasured. Do not use these raw differences
as a regression or speedup verdict. Earlier lambda/defer cost rows predate
this script and need method review before comparison. Future timing must run
both compiler revisions as staged executables with equivalent helper state.

The managed-cleanup attempt used the same staged executable path and home.
Its saved binaries were the a4c18301 compiler (SHA-256 prefix `6efa67dc`)
and the c00397af compiler (`ffbb9cdb`), installed in turn at
`builds/0/x2c`; the script restored the candidate byte-for-byte afterward.
Five alternating pairs yielded 8.375224 / 3.337080 s default and
9.729676 / 4.634577 s live. Generated C and H for the seven-source corpus
were identical between the two binaries. The baseline and candidate wrote to
different output directories, which may change cache/resource state. The
saved baseline's build provenance and helper/cache equivalence have not been
demonstrated. This is not a cost estimate for the managed cleanup edit.
Samples are in `debug/managed-paired-results.json`.

The destructuring attempt used the same script and five alternating pairs.
It yielded 8.472154 / 3.273020 s default and 9.556581 / 4.526578 s live,
with matching generated C/H. The exact `ffbb9cdb` compiler binary was the
fast candidate in the managed attempt and the slow baseline in this next
attempt, while the script assigned it a different output directory. This
cross-run observation makes a source-change attribution untenable. The script
now installs both compilers at the same staged path and uses one freshly
cleared output directory for each sample; that correction has not been timed.
The destructuring raw samples are in `debug/destructure-paired-results.json`.

The protocol-descriptor attempt installed both binaries at `builds/0/x2c`
and cleared the same output directory before every sample. Five alternating
pairs yielded 7.981082 / 3.113130 s default and 8.977372 / 4.181696 s
live. The `383495cd` binary was the fast candidate in the prior attempt and
the slow baseline here, despite the staged path being the same in both.
The source tree and helper/cache state changed between those attempts, and
their effects are not isolated. These samples cannot attribute a cost or
speedup to descriptor templates. The candidate binary was restored exactly;
samples are in `debug/protocol-descriptor-paired-results.json`.

The protocol direct-update attempt used the same staged path and freshly
cleared output directory for both binaries. Five alternating pairs yielded
8.875153 / 3.418313 s default and 10.279318 / 4.762153 s live. The baseline
binary (`29a483b2`) was the fast candidate of the preceding attempt, but is
slow here. Source-tree, helper, or cache effects remain unisolated, so the
samples do not establish the update body's compiler cost. The candidate
binary (`c88095c2`) was restored exactly. Samples are in
`debug/protocol-update-paired-results.json`.

The combined parsed-form batch used the same staged path and freshly
cleared output directory. Five alternating pairs yielded 8.956399 /
3.456621 s default and 10.386815 / 4.836183 s live. The exact `c88095c2`
binary was the fast candidate in the protocol-update attempt and the slow
baseline in this attempt. The source tree and helper/cache state changed
between them, so these samples do not assign a cost or speedup to the four
recognition changes. The candidate (`384e7249`) was restored exactly;
samples are in `debug/parsed-batch-paired-results.json`.

The combined transform and region attempt used the same staged path and
cleared output directory. Five alternating pairs yielded 8.980016 /
3.492604 s default and 10.402797 / 4.839246 s live. The exact `384e7249`
compiler was the fast candidate in the parsed-form run and the slow baseline
here. Source-tree and helper/cache effects remain unisolated, so the raw
differences do not assign cost or speedup to these three recognition changes.
The candidate (`eb8fb6aa`) was restored exactly; samples are in
`debug/transform-region-batch-paired-results.json`.

The switch and region-statement attempt used the same staged path and
cleared output directory. Five alternating pairs yielded 9.168247 /
3.567525 s default and 10.577174 / 4.923508 s live. The exact `eb8fb6aa`
compiler was the fast candidate in the preceding attempt and the slow
baseline here. Source-tree and helper/cache effects remain unisolated, so
the raw difference does not assign cost or speedup to these two recognition
changes. The candidate (`eaa301d5`) was restored exactly; samples are in
`debug/switch-region-batch-paired-results.json`.

The MatchRow and expression-origin capability batch used the same staged path
and cleared output directory. Five alternating pairs yielded 9.260695 /
3.564551 s default and 10.841318 / 5.005338 s live. The exact `eaa301d5`
compiler was the fast candidate in the preceding attempt and the slow
baseline here. Other agents completed focused builds early in this timing
window, so this run also lacks a quiet-host comparison. The raw difference
cannot be assigned to either capability. The candidate (`6910daf2`) was
restored exactly; samples are in
`debug/matchrow-origin-batch-paired-results.json`.

The match-binder and cold raw-symbol batch used the same staged path and
cleared output directory. Five alternating pairs yielded 9.246507 /
3.586844 s default and 10.659795 / 4.980025 s live. The exact `6910daf2`
compiler was the fast candidate in the preceding attempt and the slow
baseline here. Source-tree and helper/cache effects remain unisolated; these
raw values cannot be assigned to either change. The candidate (`6cbfa1d3`)
was restored exactly; samples are in
`debug/matchbinder-raw-batch-paired-results.json`.

The production rows are medians of five alternating pairs on one host
against the dev compiler the migration started from, with the same source
root and home. Compiler corpus medians are 6.555 / 6.565 s default and
7.705 / 7.727 s live; exception medians are 0.612 / 0.621 s and
0.682 / 0.689 s. Counts come from a temporary count-only build of the
candidate, then reverted. Extended transactions count every transaction
opened while any macro value application is active. A second throwaway
build attributed the 49 per translation outside try lowering: each is one
template call from a staged `meta` body in the prelude's macro families
(28 in lib/typed-array.x, 20 in lib/typed-map.x, one in lib/array.x).
`x2c_template_call` returns an application, so its binding opens an
extended transaction at depth one and closes it at its boundary. It is
expected, not a leak. The baseline was not instrumented, so the increment
per try is not measured. The source grew since the phase7 counts.

Production follow-ups (2026-09-27). Producers a template calls in its
slots are compiled into the compiler in src/builtins.x and registered in
`builtin_targets`, so any unit can call them by name; the declaring
source unit must declare them, or declaration collection fails on the
template. The try template now calls its frame declaration and cleanup
placement producers this way, with unchanged 62-case C/H. Recognition
resolves a free reference against the base-scope binding the compiler
sends with each `meta` call, so a shadowing local fails the case.

The 2026-09-27 batch rows are medians of five alternating pairs against
the compiler from before the try migration, so they are cumulative for
try, wrappers, scope cells and Func calls; generated C/H is byte-identical
to the previous dev on every fixture. Wrapper functions share one
`macro open Unit` template whose Type argument carries the storage class.
Scope cells use four small templates: the initialized, braced and empty
cells call different runtime functions, and a sequence hole is not legal
inside braces. The Func call is built from five templates and recognized
in `Compiler.func_call_parts` with `case` on the same values, the first
recognition consumer in the compiler; its outer statement expression and
storage array stay hand-built, since x2c source has no statement
expressions and an initializer takes no sequence hole. Recognition needed
two fixes in lib/meta.x: a Name hole read as an expression now derives
`(expr ? (ident ?x))`, and captures publish in the matched pattern's slot
order.

The readable-form rows are medians of five alternating pairs against
the dev compiler that carries the template capabilities (c2f06700): the
compiler from before the try migration cannot translate the corpus's own
src/transform.x any more, since its templates use those capabilities, so
the cumulative ratio is estimated by adding windows (about +1.1% default
and +1.3% live since before try, plus the unmeasured capability step).

The lambda source-form migration landed at `c99dd68d`. Its single run used
five alternating pairs per mode after warmup, the seven-source compiler
translation corpus, the same source root and `X2C_HOME`, and saved baseline
and candidate binaries. Default medians were 5.758805 / 5.945371 s
(+3.24%); live medians were 6.810948 / 6.967717 s (+2.30%). Default ranges
were 5.713885--5.809097 / 5.911796--6.012758 s; live ranges were
6.736723--7.071650 / 6.886104--7.132623 s. No builds or worker probes ran
during timing. Raw samples and summary are in
`debug/lambda-paired-799875a8/`. No counts or extra timing were taken.
This is an observed incremental compiler cost, not an isolated measurement
of matching versus reconstruction. Earlier cumulative estimates exclude
unmeasured prerequisite changes; do not turn their sum into an exact total.
The former capture-hole, cached-pattern and retained-construction blockers
are resolved. Captured-lambda C helper synthesis remains later work.

Defer registration's single run used the same seven-source corpus and
five alternating pairs after warmup, saved binaries and one source/home.
Default medians were 6.052123 / 6.200805 s (+2.46%); live medians were
7.073042 / 7.363418 s (+4.11%). Default ranges were 6.039657--6.146991 /
6.135763--6.238836 s; live ranges were 7.038766--7.097293 /
7.250071--7.383362 s. No builds or worker probes ran during timing.
Raw samples and summary are in `debug/defer-paired-a9f6d566/`. These are
incremental compiler costs, not measurements of runtime defer performance.
No additional timing or instrumentation was run.

Callable-defer's same-checkout run used five alternating pairs per mode after
warmup, optimized baseline and candidate compilers built in the same checkout,
with one seven-source tree and `X2C_HOME`. Default medians were
6.404748 / 7.563947 s (+18.10%); live medians were 7.617784 / 8.794784 s
(+15.45%). Default ranges were 6.148572--6.628238 / 7.243557--7.854959 s;
live ranges were 7.463306--7.636833 / 8.671259--8.883321 s. The compilers
generated identical C/H for all seven sources. The earlier negative row was
invalid because its baseline binary was built in a different checkout and
run against this one; two cross-checkout trials showed that disparity.
Samples are in `debug/callable-paired-corrected-results.json` in the
integration checkout. This run also used unequal executable locations and
does not establish an added compiler cost.

Var array/map literal calls used the same five-pair, same-checkout method.
Default medians were 6.774885 / 8.010428 s (+18.24%); live medians were
7.717925 / 8.965257 s (+16.16%). Default ranges were 6.591425--7.158917 /
7.739842--8.161179 s; live ranges were 7.455660--7.766287 /
8.689038--9.331436 s. Samples are in `debug/var-paired-valid-results.json`
in the integration checkout. A cross-checkout control was stopped before
completion for the same reason as the callable-defer trial. These are raw
compiler-translation times with the executable-location confound.

Try/defer cleanup calls used the same five-pair, same-checkout method.
Default medians were 6.997246 / 7.951023 s (+13.63%); live medians were
7.989776 / 9.232746 s (+15.56%). Default ranges were 6.607302--7.057842 /
7.756784--8.403932 s; live ranges were 7.934081--8.217640 /
8.906374--9.407776 s. Samples are in
`debug/cleanup-paired-valid-results.json` in the integration checkout.
The extra macro application enters a semantic transaction, but this raw
timing difference cannot attribute a cost to it.

Inline captured-lambda factory reuse used the same five-pair,
same-checkout method. Default medians were 6.857994 / 7.889616 s
(+15.04%); live medians were 8.209702 / 9.156937 s (+11.54%). Default
ranges were 6.525932--7.558985 / 7.654610--8.163958 s; live ranges were
7.908140--8.648371 / 8.876117--9.772955 s. Samples are in
`debug/factory-paired-valid-results.json` in the integration checkout.
Focused generated C and H were unchanged; this raw timing difference is
not a compiler-cost estimate.

Shared captured-environment typedef binding used the same five-pair,
same-checkout method. Default medians were 7.054045 / 3.075359 s
(-56.40%); live medians were 8.441934 / 4.395214 s (-47.94%). Default
ranges were 6.881619--7.201908 / 2.988293--3.254974 s; live ranges were
8.237435--8.603484 / 4.187018--4.467973 s. Samples are in
`debug/environment-paired-results.json` in the integration checkout.
Every run translated all seven sources and reported the same generated
C/H sizes. This unusually large difference prompted the executable-location
review above; it is not evidence that the typedef template saved that time.

Func bridge factories used the same five-pair script. Default medians were
7.197587 / 3.110135 s (-56.79%); live medians were 8.419454 / 4.382558 s
(-47.95%). Default ranges were 6.943234--7.358694 / 3.064308--3.116450 s;
live ranges were 8.151518--8.791723 / 4.187525--4.519509 s. Samples are
in `debug/bridge-paired-results.json`. The binary-location confound makes
these raw times unsuitable for a migration-cost claim.

The client pattern for every migrated lowering is the try case in
`_rewrite`:

```x2c
Macro shape = $compiler_try_shape;
return c.bind_syntax(
  shape(frame, declarations, body_out, landing, cleanup),
  AST_BLOCK, c.return_type);
```

Each argument is what its producer returns: plain source, a bound
reference, or lowered code, marked by the producer. The client writes no
carrier, transaction, application context or result unwrapping;
`bind_syntax` owns all of them. A template with a sequence hole puts it
last, and one List passed as the last argument supplies the whole
sequence, as `Compiler.wrapper_function` does for generated functions.

The first per-lowering row is the selective try candidate, not the old phase5
fixed support cost. Its total includes necessary shared support and any
unclassified remaining cost; it is not proof that every millisecond is spent
in the two try calls. Post-removal per-application timing is reported below.
Candidate counts come from actual count-only execution. The seven-file corpus
is seven translations; exception-heavy translation is a separate workload.
Historical phase4 +1.34% and phase5 +1.40% / +1.94% remain evidence for their
original windows, not costs to add to later migrations.

Track total candidate/original-baseline ratios separately for default and live.
Derive a later migration increment by subtracting its predecessor's cumulative
ratio, rerunning original, predecessor and new candidate in the same window
if earlier measurements came from another window. Phase7's support-removal
increment is -1.492 pp default / -1.201 pp live relative to its phase5 control;
it is not a second lowering. Keep application, total transaction and extended
transaction counts in each new row. Do not add separate-workload medians.

### Phase6 per-application profile

[Profile evidence](https://github.com/gwf/x2c/blob/1e2d5607be514c7205507d3f6e39c889e0cff7ec/.context/dual-macro-phase6/profile/README.md) contains the
instrumentation patch, three timed repeats, count-only controls, raw output
hashes and summaries. All 67 translations retain their phase5 raw C/H output.
The representative `defer-try-cleanup.x` has three applications, three try
transactions and six producer calls. The middle total-duration sample is
2.876 ms for snapshot plus application; this exact non-overlapping split is:

| Work | Three applications, ms | Per application, ms | Share |
| --- | ---: | ---: | ---: |
| Current scope symbol Map copy | 1.151 | 0.384 | 40.0% |
| Other transaction snapshot | 0.051 | 0.017 | 1.8% |
| Macro_apply carrier construction | 0.002 | 0.001 | 0.1% |
| x2c.template invocation rows | 0.268 | 0.089 | 9.3% |
| Template replacement | 0.110 | 0.037 | 3.8% |
| Skeleton binding excluding producers | 0.457 | 0.152 | 15.9% |
| Two producer evaluations including native bodies | 0.090 | 0.030 | 3.1% |
| Application residual: open projection, Match, freshening, bookkeeping | 0.747 | 0.249 | 26.0% |

The native producer bodies account for 0.013 ms of their 0.090 ms evaluation
cost. Inclusive application binding contains that evaluation; the table uses
exclusive binding so it is not counted twice. Three fixture samples total
2.733--2.924 ms. Scope copying is the largest individual part; the whole
snapshot is 41.8% in the selected sample. Compiler-corpus median snapshot /
application totals are 1.720 / 1.313 ms default and 2.541 / 1.397 ms live;
separately calculated medians need not sum to a particular run's total.

The phase6 recommendation to optimize the per-try scope copy and raise the
planning aim to 5% is withdrawn. It did not measure the fixed support costs.
Two try applications contribute about 3 ms measured default work, compared
with roughly 85 ms of whole-candidate difference. Ordinary transactions and
per-node checks must be measured separately before assigning costs to later
lowerings. Phase7 below supersedes that cost recommendation.

### Phase7 fixed-cost measurement and removal

[Fixed-cost evidence](https://github.com/gwf/x2c/blob/1e2d5607be514c7205507d3f6e39c889e0cff7ec/.context/dual-macro-phase7/README.md) times
all extended snapshot work separately from the pre-existing snapshot, stage
checks before recursion (including effect consumption on successful hits),
and parse-time open preparation including cache hits.
Three repeats and count-only controls preserve all 67 raw C/H outcomes.

| Work, seven-file corpus | Default ms | Share of historical 85.088 ms | Live ms | Share of historical 139.123 ms |
| --- | ---: | ---: | ---: | ---: |
| Extended snapshot: adapters, base maps, queue lengths, origin/exception | 5.070 | 6.0% | 5.387 | 3.9% |
| bind_syntax added slot/pending checks | 5.753 | 6.8% | 5.771 | 4.1% |
| resolve_expression added slot/wrapper check | 12.605 | 14.8% | 12.967 | 9.3% |
| Open preparation, including cached entry checks | 0.043 | 0.05% | 0.046 | 0.03% |

These are raw span medians, not a complete causal attribution. Per-run sums
have median 23.457 ms default and 24.098 ms live. Per-process empty-clock
interval adjustment estimates 19.515 / 19.979 ms, about 22.9% / 14.4% of the
historical differences. That adjustment does not remove all profiler API,
cache or execution disturbance. Roughly 65.6 / 119.1 ms remains unattributed
on those provisional estimates. Pre-existing snapshot work is approximately
224 / 226 ms aggregate; it is not new overhead. Commit and surrounding work
are not included in the snapshot measurement. The individual extended fields
are measured together rather than assigned separate subfield timings.

Default/live execute 105245/105485 added bind checks and 122912/125983 added
expression checks. Preparation has 80 entry calls in each mode, including
cache hits; cold preparation is not separately counted. The 2119/2124 total
transactions cover seven translations, not each translation.

The isolated candidate selects extended coverage in existing SymTxn only
while a template-construction context is active, established before the outer
try transaction and frame allocation. Nested transactions inherit it, and
stored coverage guards snapshot, commit and rollback. Outside that context
there are no added map copies or queue snapshots; the cheap context branch
remains. Current-scope symbol copying is unchanged. This replaces the broader
lazy-write-hook proposal with the smaller proved selective extension.

New carrier and pending checks execute only in application binding. A cheap
context branch remains on ordinary nodes, but ordinary nodes no longer perform
those added shape matches. The bounded prototype retains its existing private
application flag; production must enter automatically at the first-class
application boundary, separately from origin policy and native dispatch.
Do not activate every legacy macro invocation or require client wrappers.
General automatic application entry and legacy effect-bearing slots are not
proved by this timing prototype.

The final binary passes the 62-case raw C/H comparison and failing-skeleton
rollback, independently rerun by the root agent. Extended transactions are
now 2 of 2119 default / 2 of 2124 live in the compiler corpus; exception has
4 of 265 in each mode. Application counts remain 2 / 2 and 4 / 4. No baseline
ordinary transaction guarantee is silently expanded; existing rollback gaps
outside the construction context remain baseline behavior.

### Post-removal per-try work

[Current-candidate profile](https://github.com/gwf/x2c/blob/1e2d5607be514c7205507d3f6e39c889e0cff7ec/.context/dual-macro-phase7/post-try/README.md)
measures only actual try snapshots and applications, with scope-symbol copy
as a snapshot child. All 19 translations preserve final candidate raw C/H.
The seven-file compiler has two applications: 2.976 ms total default / 3.636 ms
live, or 1.488 / 1.818 ms per application in one run per mode. Default snapshot
is 1.627 ms (scope copy 0.945), application 1.349 ms; live snapshot 2.257 ms
(scope copy 1.598), application 1.379 ms. The snapshot plus application spans
are disjoint; do not add the scope-copy child again.

The three-try fixture repeats total 2.643, 3.220 and 2.767 ms: median 0.922 ms
per try, range 0.881--1.073. Exception benchmark has four applications, 3.722 ms
default / 3.426 ms live in one run each. Instrumentation overhead is retained;
commit/rollback, frame allocation and region/preparation work are outside these
spans. These measured windows are per-try costs, not a complete transformation
marginal cost. They remain far smaller than the old fixed support difference.

The collector's summary initially failed on zero-application rows with no timer
output. It was repaired from the retained successful translation records,
without another build or translation run. No compiler/prototype failure was
involved. The old log and repaired aggregation are retained.

### Same-window throughput and target

[Three-way results](https://github.com/gwf/x2c/blob/1e2d5607be514c7205507d3f6e39c889e0cff7ec/.context/dual-macro-phase7/comparison/summary.json)
compare the original baseline, phase5 and phase7 after warmup, with five
rotating-order samples per mode/workload, identical input paths and home.
No builds ran during timing. All final timed raw C/H digests agree across all
three binaries and their hashes remained unchanged. No output normalization
or sample exclusions were used.

| Workload | Baseline median s | Phase5 median s | Phase7 median s | Phase7 versus original | Phase7 minus phase5 ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| Compiler default | 6.311873 | 6.414413 | 6.320251 | +0.133% | -1.492 pp |
| Compiler live | 7.289804 | 7.281302 | 7.193741 | -1.318% | -1.201 pp |
| Exception default | 0.585854 | 0.587982 | 0.590944 | +0.869% | +0.506 pp |
| Exception live | 0.654379 | 0.665897 | 0.655178 | +0.122% | -1.638 pp |

Default compiler ranges overlap: baseline 6.303874--6.338763 s, new candidate
6.290987--6.336089 s. Its phase5 control is 6.399838--6.435478 s, entirely
above both. The controlled patch reduces their median difference by 94.162 ms;
the remaining median difference from original is 8.379 ms. That supports
removing the unnecessary support work, but the diagnostic spans do not fully
attribute that 94 ms to snapshot fields versus checks or commit work.

Live compiler ranges are broad and overlap (baseline 7.166489--7.533066 s;
new 7.174852--7.584677 s). Retain the negative measured ratio in the ledger,
but do not claim a stable speedup or credit it against default cost. Exception
default is slightly worse than the control: candidate 0.588079--0.594368 s,
baseline 0.579757--0.587718 s. Exception live overlaps, including a 1.200863 s
baseline observation. All observations remain in the evidence. Five samples
in one host window do not establish long-run distributions.

**Keep the 2% cumulative default translation-overhead aim.** The new first
migration sits well below it; raising the aim to 5% on phase5's total was
unjustified. This does not prove that three lowerings will fit: later application
counts and shared preparation costs must be measured in their actual combined
candidate. Track live and exception workloads separately, including regressions.
The target for the production try change is the phase7 result (+0.133% default
compiler total, +0.869% exception default, and the qualified live observations),
not phase5 +1.40%. This is a measured reference and recommendation, not a new
gate or per-run numerical pass/fail threshold. Preserve the existing advisory
performance checkpoint.

## Readable form

The acceptance test for every later migration is
[lowering with macros](../agents/lowering-with-macros.md): its rules, and
the try lowering it shows, are the standard a migrated lowering meets.

A migrated site is done when a reader sees the generated C in the template
and almost nothing in the client: one application call, no carrier
literal, and no positional hole list longer than the C it writes has
parameters. Typed expressions are already bound and pass to holes as they
are. Loops and type-dependent choices live in compiler-internal meta
functions registered in src/builtins.x and called from template slots;
each sub-shape is its own macro, so recognition mirrors construction
element by element. A slot whose arguments include one sequence hole
captures its output under that hole's name when the macro is recognized.
The derived pattern is cached per macro value.

### A. Func call (src/expressions.x)

Each argument asks the runtime signature whether it passes by reference,
so an element of the argument array is not a plain boxed value: one macro
writes one element, choosing at run time. The array is declared and
indexed, which replaces the compound literal of named locals in the
generated C.

```x2c
macro open Statement $func_call(Expr $callee, Expr $count,
    Expr $arguments...) {
  {
    Func function = $callee;
    FuncArg storage[$count];
    $x2c_func_call_arguments(function, storage, $arguments)...
    Func_apply(function, $count, storage);
  }
}

macro open Statement $func_argument(Expr $function, Expr $storage,
    Expr $count, Expr $index, Expr $address, Expr $type, Expr $value) {
  if (x2c_func_reference_type($function, $count, $index))
    $storage[$index] = FuncArg_reference($address, $type);
  else $storage[$index] = $value;
}

macro open Statement $func_null_argument(Expr $function, Expr $storage,
    Expr $count, Expr $index, Expr $value) {
  {
    List reference = x2c_func_reference_type($function, $count, $index);
    if (reference) $storage[$index] = FuncArg_reference(0, reference);
    else $storage[$index] = $value;
  }
}

macro open Expression $func_value(Expr $argument) => FuncArg_value($argument);
macro open Expression $func_opaque(Expr $function, Expr $index,
    Expr $type) => x2c_func_unrepresentable_argument($function, $index, $type);
macro open Expression $func_apply(Expr $callee) => Func_apply($callee, 0, 0);
```

`x2c_func_call_arguments` (src/expressions.x, registered in
src/builtins.x) applies `$func_argument` or `$func_null_argument` once per
argument, choosing the address, type and by-value alternative from the
argument's type through `Compiler.expanding()`. The count is a hole: a
`$` call in an expression position inside a `meta` body is an ordinary
call, so a count slot would not run when a `meta` function makes a Func
call. Client:

```x2c
if (!arguments) {
  Macro apply = $func_apply;
  return compiler.bind_syntax(apply(callee), AST_EXPRESSION, NULL);
}
Macro call = $func_call;
return %(expr ("Var") (parens ${compiler.bind_syntax(
  call(callee, arguments.len(), arguments), AST_BLOCK, NULL)}));
```

x2c source has no statement expressions, so the `(parens ...)` value of
the block is the one form the client still writes; the call with no
arguments is a second C shape. Recognition in `Compiler.func_call_parts`
mirrors construction: `case call(?callee, ?count, *arguments)`, then per
statement `case prepare(...)` or `case absent(...)`, and `case
boxed(?value)` on the by-value alternative.

### B. Try (src/transform.x)

The template writes the whole region: the frame, the catch site, the
push, the landing and the cleanup. Slot functions in src/builtins.x
build the catch site, the landing and the placed cleanup from the facts
the lowering computed; each writes its C through its own macro.

```x2c
macro open Statement $compiler_try(Name $frame, Expr $clause,
    Statement $body, Statement $cleanup) {
  {
    ExceptionFrame $frame;
    $builtin_try_catch_site($frame, $clause)...
    x2c_exception_push(&$frame);
    if (!sigsetjmp($frame.env, 0)) $body
    else {
      x2c_exception_landed(&$frame);
      $builtin_try_landing($frame, $clause, $cleanup)...
    }
    $builtin_try_cleanup_placement($cleanup)...
  }
}

/* One catch arm of several, chosen by its index. */
macro open Statement $catch_arm(Name $selected, Expr $index,
    Statement $arm, Statement $rest) {
  if ($selected == $index) $arm else $rest
}
```

The catch-site and landing sub-shapes live in src/builtins.x beside the
slot functions that apply them:

```x2c
/* One catch site: its patterns prepared once, its handler pushed with
   them. */
macro open Statement $catch_site(Name $frame, Name $handle, Name $patterns,
    Expr $count, Expr $fallback, Expr $state, Statement $preparation...) {
  static MatchCaptureSite arms[$count];
  Var $patterns[$count];
  static ErrorCatchSite site = {arms, $fallback, $count, $state, -1};
  if (x2c_error_catch_site_pending(&site)) { $preparation... }
  volatile ErrorHandler $handle =
    x2c_error_catch_site_push(&$frame, &site, $patterns);
}

/* One arm's pattern, prepared into its slot. */
macro open Statement $catch_pattern(Name $patterns, Expr $index,
    Expr $pattern) {
  $patterns[$index] = $pattern;
}

/* A landing no catch arm handles: the region's exits run, and control does
   not come back. */
macro open Statement $try_unhandled(Statement $cleanup) {
  { $cleanup __builtin_unreachable(); }
}

/* A landing that hands a raised error to its catch arms. */
macro open Statement $catch_landing(Name $frame, Name $handle,
    Statement $unhandled, Statement $choice, Statement $selection...) {
  if (x2c_exception_is_error_target(&$frame)) {
    $selection...
    x2c_error_catch_detach($handle);
    x2c_exception_mark_handled(&$frame);
    $choice
  }
  else $unhandled
}

/* The arm the handler selected, when there are several. */
macro open Statement $catch_selected(Name $selected, Name $handle) {
  int $selected = x2c_error_catch_selected($handle);
}
```

`builtin_try_catch_site` applies `$catch_site` with one `$catch_pattern`
per filtered arm. `builtin_try_landing` applies `$try_unhandled`, and
with a clause applies `$catch_landing`, with `$catch_selected` when there
are several arms. The slot functions keep the `builtin_` prefix of every
name in the shared compile-time Lisp session, so a user `meta` function
cannot take their names.

Client, after the label diagnostic:

```x2c
Macro shape = $compiler_try;
return c.bind_syntax(
  shape(frame, _catch_clause(c, clause, arms.list_free()), lowered,
        cleanup),
  AST_BLOCK, c.return_type);
```

`lowered`, `cleanup` and each arm come from the region driver as lowered
code; the frame is the binding `_region_binding` allocates. The clause is
passed as facts, `(HANDLE PATTERNS SELECTED STATE CHOICE PATTERN...)`.
`_catch_clause` computes the site's initial state, which needs the
compiler's static-pattern test, allocates the pattern array and the
selected arm, and builds the choice among the arms.

Two parts do not meet the standard:

- The arm choice is a loop in the region driver (`_catch_choice`), not in
  a slot function. It applies `$catch_arm` once per arm and binds each
  application before the one that holds it. A slot returning the nested
  chain expands one application inside the next, and the compiler rejects
  an expansion deeper than 64 (`macros.x`, "macro expansion depth exceeds
  64"), so `catch-many-arms` (65 arms) failed; the report of that limit
  also crashed in `Token_repr`. Building the chain as nested pending
  applications also cost exponential time before the limit: each nested
  application holds its hole value in several capture rows, and building
  the next application walks the whole value (`_source_unwrap`), so 12
  arms took 75 s. Binding each test first keeps both costs linear and the
  C unchanged.
- The pattern array and the selected arm are compiler-allocated Names,
  not macro locals. A slot argument cannot name a macro local ("an
  argument must be a constant, captured syntax, or a meta call"), so a
  slot inside `$catch_site` cannot write the pattern assignments, and the
  driver-bound arm tests must name the selected arm before the landing
  declares it. The arm and site arrays, which only the catch site reads,
  are macro locals and now spell `_x2c_macro_arms_N` and
  `_x2c_macro_site_N`. The same limit applies to A's
  `$func_arguments(function, storage, $arguments)`.


### C. Wrapper functions and scope cells

The wrapper template stays one template; its callers pass lowered bodies
through `Compiler.wrapper_function`, the one place that marks them, and a
parameter List passes as the whole trailing sequence:

```x2c
Macro wrapper = $compiler_wrapper;
List function = c.bind_syntax(
  wrapper(result, binding, %(code-value "lowered" (seq @body) ()), params),
  AST_UNIT, NULL);
```

The mark is needed: without it, rebinding a lambda body that holds
lowered cell declarations fails with "syntax cannot be constructed at this
position" (lambda-parameter-mutation, lambda-local-macro-captures). The
try lowering still has other `lowered` producers, so the wrapper is not
the only one.

A scope cell is copied from its initializer or allocated empty, two C
shapes:

```x2c
macro open Statement $compiler_cell(Type $type, Name $cell, Expr $value) {
  $type *$cell = Scope_memdup((const void *)&($type)$value, sizeof($type));
}
macro open Statement $compiler_empty_cell(Type $type, Name $cell) {
  $type *$cell = Scope_malloc(sizeof($type));
}
```

A plain initializer is written as a one-element compound before the
application, so the braced and plain cells are one template. The typed
initializer needs no carrier. Applying the empty cell ignores the extra
argument. Client:

```x2c
List compound = initializer;
if (initializer && !initializer.match(%(expr ? (composite ?))))
  compound = %(expr () (composite (commas $initializer)));
Macro shape = initializer ? $compiler_cell : $compiler_empty_cell;
return c.bind_syntax(shape(type, cell, compound), AST_BLOCK, NULL);
```

### D. Lambda

The next capability is a `Captures` hole for a complete lambda capture
clause. It carries the binder's rows as one value, leaving the existing
trailing `Param` sequence for parameters. It introduces no new capture
representation and does not change ordinary `using &name` source syntax.
Target source forms, before adoption:

```x2c
macro Expression $lambda_expression(Expr $body, Param $params...) =>
  %!($params...) => $body;
macro Expression $lambda_captured(Expr $body, Captures $captures,
    Param $params...) => %!($params...) using $captures => $body;
```

Target recognizer:

```x2c
Macro captured = $lambda_captured, lambda = $lambda_expression;
match (expression) {
  case captured(?body, *captures, *params):
    return lower_captured(c, params, captures, body);
  case lambda(?body, *params):
    return lower_plain(c, params, body);
}
```

The capability batch adds only the hole, its parser insertion point and
focused construction/recognition coverage. The adopter batch replaces
lambda recognizers in expressions.x, regions.x and transform.x and the
construction in literals.x. Bound type selection and lexical capture
operations retain their current owners. Before adoption, spell out each
construction client here, including any type-dispatch exception that source
syntax cannot express. The wrapper-preserving, cached macro matcher is
already on dev; the earlier copy-on-miss blockers are historical.

The capability reuses the scalar splice projection (also used by Type
holes), substitution, and the existing lambda binder. Template lambda
signatures wait until their parameter holes are supplied, and body holes
accept expressions or blocks without an expression-only wrapper. No extra traversal, validator or diagnostic is
needed. `Captures` is a complete clause because two ungrouped sequence
holes cannot share the existing macro calling convention.

### Lambda adoption sites

The capture capability landed at `b59b8ade`. Recognition moves to the full
expression before a walker descends to its payload. The target cases above
replace the lambda alternatives in `_expression_requires_resolution`,
`_resolve_content`, `lift_func_expression`, region ownership and capture
walks, and `lower_lambda_expr`. A caller which previously unwrapped casts
or parentheses retains that behavior before recognition.

The constructors in `bind_lambda_expression` and `parse_lambda_literal`
are not ordinary lowering clients: they produce the bound lambda that
applying either source-form template asks this same binder to produce.
Their result type is the supplied native signature or `Func`, chosen by
capture and meta-body state. The current template application interface
binds its result and cannot express that producer boundary without
re-entering the binder. The next capability batch adds a narrow compiler-only
construction path through the shared template projection, preserving already
established type and binding facts. Normal macro application is unchanged.
The same
boundary applies to rebuilding a lambda with a prepared body or rewritten
capture expressions while retaining its existing type and stage. This is
not a claim that all possible template-construction interfaces fail.

Target producer client (the capability batch owns the final internal name):

```x2c
Macro captured = $lambda_captured, lambda = $lambda_expression;
if (captures)
  return c.rebuild_expression(type, captured(body, captures, params));
return c.rebuild_expression(type, lambda(body, params));
```

The producer has already selected the result type and resolved its parameter,
capture and body facts. Rebuilding after a body/capture rewrite uses the same
forms and retained root type. No parallel hand-built lambda arm remains.

The consumers' target client is one source-form case. The grammar file
owns both templates; no parallel lambda literal recognizer remains at an
adopted site. Bound reconstruction is listed separately from recognition
and is not reported as migrated.

Current adoption: expressions/regions/transform recognize the shared source
forms; literals and transform reconstruct through those same templates.
The five literals constructors and four transform constructors are gone,
as is `_lambda_params_node`. Rewriters traverse root position wrappers
before recognition, retaining the actual expression's type and wrappers.
The supplied-but-unused capture case still keeps its established Func type;
native lifting uses the computed native signature. Fifteen focused fixtures
passed, then six affected fixtures passed after wrapper dispatch changed.
No generated C expectations were changed. The publication gate passed at
`c99dd68d`; the one five-pair cost run measured +3.24% default / +2.30% live.

The two `ast_contains_head(..., <lambda>)` traversal prefilters remain for
now; they are not shape recognizers. Captured-lambda C environment/helper
synthesis remains in the architecture survey's later transform work. Neither
is counted as fully migrated merely because lambda source construction is.

### E. Defer record and registration

Landed at `f99136f8`: this batch replaces `_defer_block`, keeping cleanup ancestry and capture
selection in their existing owners. Source recognition in `_rewrite_defer_list`
uses the grammar-owned unary form; the extended lowered record remains an
internal producer form:

```x2c
macro Statement $deferred(Statement $body) { defer $body }
Macro deferred = $deferred;
match (head) case deferred(?final_stmt): { /* lower this region */ }
```

Target client:

```x2c
Macro shape = $compiler_defer;
return c.bind_syntax(
  shape(record, callback, environment, records,
        _try_region(walk, cleanup, body), cleanup),
  AST_BLOCK, c.return_type);
```

Target C shape:

```x2c
macro open Statement $compiler_defer(Name $record, Expr $callback,
    Expr $environment, Expr $records, Statement $body, Statement $cleanup) {
  {
    $builtin_defer_record($record, $callback, $environment, $records)...
    x2c_cleanup_push(&$record);
    $body
    $builtin_try_cleanup_placement($cleanup)...
  }
}
```

The record slot selects a plain record or an environment plus record. The
captured template declares `environment = {0}`, calls one assignment template
per captured address, then declares
`X2CCleanup record = {.fn = callback, .env = &environment}`. The plain
record uses `.env = 0`. Assignments avoid unsupported initializer-item
sequence splices; capture addresses retain source order. The callback passes
as an already typed expression. Body and cleanup use lowered carriers.

Before adopting this shape, resolve generated environment type visibility
through the existing declaration binder: `add_early` only queues syntax and
has not bound the generated typedef. Do not introduce a second type registry
or duplicate environment synthesis inside the slot. The callable-defer
helper/environment construction remains a separate subsequent shape.

### E2. Callable-defer environment and helper (target readable form)

The callable pass still selects captures, checks whether their types can be
hoisted, records writes, and rewrites typed references. Its output construction
reads as one producer call for each generated unit:

```x2c
if (records)
  c.add_early(_defer_environment_unit(c, env_binding, records));
c.add_early(_defer_callback_unit(
  c, callback, opaque, env_binding, env_local, rewritten));
return %(defer $body $env_binding $callback $records $written);
```

The adjacent source templates express `typedef struct NAME { FIELDS... }
NAME` and the two file-static `void CALLBACK(void *OPAQUE)` helper shapes,
with and without a typed environment-pointer declaration. The environment
producer supplies canonical `const void *FIELD` rows. A separately bound
`Field` template was tried but lost the member type in the enclosing record;
the generated C was unchanged while the transform sidecar lost its type.
Keep the field rows with the producer until a direct `Field` projection
preserves that type fact.
The final lowered `defer` record is the existing internal producer form and
retains the current stage. Ordinary binding publishes the generated typedef;
`add_early` preserves the current unit order. Capture discovery, type
hoistability, write/volatile semantics, and the unsupported-capture try
fallback remain with their existing owners. No new parser or runtime behavior
is intended.

### E3. Var array and map literal calls (target readable form)

The transform converts each source element to `Var` in its existing source
order. The resulting expression template makes the C call visible before
emission:

```x2c
macro open Expression $var_array(Expr $count, Expr $values...) =>
  Array.update_n(Array.new(), $count, $values...);
macro open Expression $empty_var_array() => Array.new();
macro open Expression $var_map(Expr $count, Expr $entries...) =>
  Map.update_n(Map.new(), $count, $entries...);
macro open Expression $empty_var_map() => Map.new();

List transform_array_literal(Compiler c, List ast) {
  Array values = [];
  foreach (List element, ast.cdr())
    values.push(_literal_element(c, element));
  return _var_array_literal(c, values.list_free());
}

List transform_map_literal(Compiler c, List ast) {
  Array entries = [];
  foreach (List pair, ast.cdr()) {
    entries.push(_literal_element(c, pair.cadr()));
    entries.push(_literal_element(c, pair.caddr()));
  }
  return _var_map_literal(c, entries.list_free());
}
```

The two narrow producers choose the empty template or pass an already typed
count and converted arguments to the nonempty template. They return the
lowered expression content at its established Array or Map type and stage.
`cache.x` continues to materialize cached values through these producers.
The `varray`, `vmap`, `vpair` emitter arms and `_var_collection` disappear
once no lowerer emits those nodes. The generated call should retain the
existing argument order and empty constructor-only form. C's argument
evaluation rules remain the same; the migration does not introduce staging
temporaries or new order guarantees.

Focused checks show the same generated constructor calls and successful
execution. Binding those calls in the transform adds
`Array_new`/`Array_update_n` and `Map_new`/`Map_update_n` declarations to
generated C where they are used. Transform expectations record the newly
explicit call nodes and shifted binding numbers. The affected fixture
sidecars were reviewed and refreshed at integration; generated C differs
only by constructor prototypes, not executable calls.

### E4. Try and defer exit calls (target readable form)

The region walk still decides which exits run cleanup, in what order, and
where each result is placed. Its lowered code carrier is produced by the
cleanup operation after one ordinary binding of an adjacent C template:

```x2c
Macro leave = $defer_cleanup_call;
List call = c.bind_syntax(
  leave(_address_of(_record_type, record)), AST_BLOCK, c.return_type);
return %(code-value "lowered" (seq $call) ());

Macro close = $try_close_handler;
List before = has_clause
  ? %(${close(%(expr $handler (ident $handle)))}) : NULL;
List address = _address_of(_frame_type, frame);
List syntax;
if (finalizer) {
  Macro finish = $try_finish_cleanup;
  syntax = finish(address,
    %(code-value "lowered" (seq $finalizer) ()), before);
}
else {
  Macro leave = $try_leave_cleanup;
  syntax = leave(address, before);
}
List result = c.bind_syntax(syntax, AST_BLOCK, c.return_type);
return %(code-value "lowered" $result ());
```

The complete target templates are:

```x2c
macro open Statement $defer_cleanup_call(Expr $record) {
  x2c_cleanup_leave($record);
}

macro open Statement $try_close_handler(Expr $handle) {
  x2c_error_catch_close($handle);
  $handle = NULL;
}

macro open Statement $try_leave_cleanup(Expr $frame,
    Statement $before...) {
  $before...
  x2c_exception_leave($frame);
}

macro open Statement $try_finish_cleanup(Expr $frame,
    Statement $finalizer, Statement $before...) {
  if (x2c_exception_claim($frame)) {
    $before...
    $finalizer
  }
  x2c_exception_leave($frame);
}
```

The producer supplies typed frame/record addresses and a typed handler use
because these region-owned names are declared only when the enclosing region
template binds. The finalizer is already lowered and enters its Statement
hole as a retained carrier, once. The templates call the existing runtime
functions in their established order; no region or finalizer analysis moves
into the templates.

### E5. Inline captured-lambda factory (target readable form)

The captured-lambda pass owns capture discovery, first-use order, storage
types, value conversions, context construction, and the bridge identity. Its
inline-header branch keeps those facts and applies the existing wrapper
operation to its already lowered factory body:

```x2c
List factory_body = %(block $factory_storage
  (stmnt (return $factory_construction)));
compiler.add_early(compiler.wrapper_function(
  %("Func"), bridge, declaration_params.cdr(), factory_body.cdr()));
```

`Compiler.wrapper_function` in `src/protocol.x` binds this existing template;
its producer passes the body as a `code-value "lowered"` carrier:

```x2c
macro open Unit $compiler_wrapper(Type $result, Name $name,
    Statement $body, Param $params...) {
  $result $name($params...) { $body }
}
```

The function remains in the early queue after its context storage and call
are prepared. The bridge's typed parameter declarations retain their order,
and the generated factory remains an external `Func` function for inline
header callers. `_publish_func_adapter` already uses this wrapper for the
static callback; this batch deletes only the duplicate raw factory function
skeleton. `function-to-func-inline` passes with identical generated C and H,
including its bridge prototype and identity. `captured-lambda-lowering` and
`lambda-adapt-direct-function` also pass unchanged.

### E6. Shared captured environment typedef (target readable form)

The captured-lambda loop still chooses each field's storage type, introduces
its binding, and supplies canonical `Field` rows in first-use order. One
adjacent Unit template writes the completed typedef for both lambda and
callable-defer environments:

```x2c
macro open Unit $capture_environment(Name $name, Field $fields...) {
  typedef struct $name { $fields... } $name;
}
```

The lambda producer replaces its raw typedef skeleton with one binding of
that whole template at the existing early-declaration point:

```x2c
Macro environment = $capture_environment;
compiler.add_early(compiler.bind_syntax(
  environment(environment_typedef, fields.list_free()), AST_UNIT, NULL));
```

The callable-defer producer keeps its field-row construction and changes
only the selected template name:

```x2c
Macro environment = $capture_environment;
return c.bind_syntax(
  environment(env_binding, fields.list_free()), AST_UNIT, NULL);
```

Move the existing whole-typedef template beside lambda lowering and remove
its defer-specific definition; do not bind fields separately, which loses
their member types. Captures, conversion and storage decisions, generated
name spelling, early-declaration order, and the inline bridge stay with their
current owners. Focused C/H and transform comparisons must check mixed
`Var` and reference fields and the callable-defer shape.

Focused checks compile and run the mixed-field lambda with unchanged C. Its
transform sidecar now records the struct tag as the introduced typedef
binding, where the raw skeleton recorded a spelling string; field types and
emitted tag/typedef spellings are unchanged. The inline C/H fixture and four
callable-defer fixtures pass exactly. Reference and nested-capture fixtures
also pass exactly. The transform sidecar records the reviewed tag identity
change.

### E7. Inline Func bridge factories (target readable form)

The direct-function getter and the indirect-function-pointer factory both
publish an external `Func` bridge whose body returns one already typed
expression. Their memo blocks continue to allocate the bridge, prepare its
parameters and value, and queue it at the same point. Each uses the existing
wrapper operation rather than constructing a raw `function` node:

```x2c
/* Direct getter, inside its existing memo block. */
compiler.add_early(compiler.wrapper_function(
  %("Func"), bridge, parameters.cdr(),
  %(block (stmnt (return $handle))).cdr()));

/* Indirect pointer factory, inside its existing memo block. */
compiler.add_early(compiler.wrapper_function(
  %("Func"), bridge, parameters.cdr(),
  %(block (stmnt (return $value))).cdr()));
```

The operation binds the already existing template in `src/protocol.x` and
retains the body as lowered code:

```x2c
macro open Unit $compiler_wrapper(Type $result, Name $name,
    Statement $body, Param $params...) {
  $result $name($params...) { $body }
}
```

The result type, parameter types and order, bridge binding, memo keys, early
declaration order, and inline header API remain with their present producers.
This batch deletes the two duplicate raw external-function skeletons. The
indirect context typedef stays in its current form. Focused
`function-to-func-inline` C/H, `function-to-func`, and direct-adapter fixtures
pass unchanged; the indirect-adapter rejection fixture also passes.

### E8. Indirect Func context typedef exception

`_build_indirect_func_adapter` still constructs its function-pointer context
typedef as a raw file-level unit. Reusing `$capture_environment` preserved
the field type but failed a positive `function-to-func` fixture. The template
bound while the adapter's local scope was active, so generated C declared
`_x2c_local_typedef_0`; the context construction later used the intended
`_x2c_func_pointer_context_0`. The baseline fixture compiles; the prototype
fails native compilation at the first mismatched use. `Sym.define` and
`Sym.bind_identity` in `src/compiler.x` assign local typedefs an emitted
`local_typedef` name. The prototype was discarded without source or sidecar
changes. This shape needs a proved file-scope binding path or a deliberate
identity projection before migration; neither belongs in a typedef-only
replacement.

### E9. Protocol discard helper template prototype

`Compiler.discard_helper` already delegates its generated function to
`Compiler.wrapper_function`; its remaining body selection is six lines of
canonical lowered statement construction. A prototype replaced that selection
with adjacent void and value Statement templates. `make build` and the
`protocol-operator-discard` and `protocol-operator-direct-update` fixtures
passed with unchanged generated C expectations. The source change added 33
lines and removed six for this compact body, roughly doubling the machinery
without clarifying ownership. The prototype was discarded and the source and
sidecars remain unchanged. This rejects that narrow implementation, not other
protocol helpers or a different consolidation that removes more machinery.

### E10. Protocol descriptor registration

The adapter loop decides which thunks exist and preserves their member order.
The descriptor producer still chooses the participant tag, explicit tag,
zero-thunk case, and `<protocol>` versus `<early>` initializer queue. Its
descriptor declaration and assignment can be read in two adjacent templates:

```x2c
macro open Unit $protocol_methods(Name $methods) {
  static VarMethods $methods;
}

macro open Statement $protocol_methods_value(Name $methods, Expr $value) {
  $methods = $value;
}
```

The client retains one canonical designated-initializer row per thunk. The
current macro hole kinds cannot splice a `dotinit` row into a C composite
initializer, so the value is the one structural AST island; the declaration
and assignment become source templates. The client prepares the typed value,
binds the shapes, and queues them at the existing positions:

```x2c
Macro methods_shape = $protocol_methods;
Macro assign_shape = $protocol_methods_value;
List methods = compiler.sym.introduce(
  compiler.fresh_name("_x2c_protocol_methods"));
Array fields = [];
foreach (List row, thunks) {
  (String member, List thunk, Type type) = row;
  fields.push(%(dotinit ($member) (expr $type (ident $thunk))));
}
List value = %(expr ("VarMethods")
  (cast (decl ("VarMethods") (bindings (bind () ())))
    (expr () (composite (commas @{fields.list_free()})))));
Symbol queue = central_initializer ? <protocol> : <early>;
compiler.add_early(compiler.bind_syntax(
  methods_shape(methods), AST_UNIT, NULL));
if (thunks) compiler.add_init(queue,
  compiler.bind_syntax(assign_shape(methods, value), AST_BLOCK, NULL));
/* Existing typed call nodes and `if` block remain, then: */
List call = explicit_tag ? explicit_call : early_call;
compiler.add_init(queue,
  central_initializer || explicit_tag ? %(stmnt $call) : registration);
```

The cast and member rows keep their current bound types and method names.
For an explicit tag, `name` retains its original case and the registration
call remains direct. With no thunks, the table remains zero-initialized and
there is no C23-only empty composite assignment. A first implementation also
templated the registration calls. `protocol-static-descriptor` then emitted
new `x2c_register_builtin_descriptor` and `x2c_register_descriptor`
prototypes and removed the fallback `if` braces, changing its generated C.
Those call templates were removed; their typed call nodes and fallback block
are a concrete exact-output exception to this batch. Ten focused fixtures,
including static, private, no-thunk, and package cases, pass with unchanged
expected artifacts after retaining them. The protocol boundary probes also
pass, including their explicit-tag checks.

### E11. Discarded destructuring assignment (target readable form)

The `list-destructuring` fixture assigns `(first, missing) = %(7)` and
checks the two writes. The existing transform gives the expression one
`List` conversion, stores it in an issued temporary, then writes each
target from its index in order. The statement has its own block scope.

```x2c
macro open Statement $destructure_statement(Name $temporary, Expr $source,
    Statement $assignments...) {
  {
    List $temporary = $source;
    $assignments...
  }
}

static List _destructure_statement(Compiler compiler, List ast) {
  match (ast) {
    case %(stmnt (expr ?
             (dstrasgn (targets *targets)
                       (!set ?source (expr ?source_type ?))))): {
      List temporary = compiler.sym.introduce(
        compiler.fresh_name("destructure"));
      Macro shape = $destructure_statement;
      return compiler.bind_syntax(
        shape(temporary, _destructure_source(compiler, source, source_type),
              _destructure_assignments(targets, temporary)),
        AST_BLOCK, compiler.return_type);
    }
  }
  return ast;
}
```

`_destructure_assignments` remains the shared left-to-right element owner;
the expression-valued path and declaration paths retain their existing
forms. The template replaces the raw block and temporary declaration,
without introducing another source conversion or changing target bindings.

### E12. Managed declaration cleanup (target readable form)

The existing `_append_managed_declaration` owner keeps eligibility, declaration
splitting, installed identity, protocol participation, and source order. After
it emits the managed initializer declaration, an adjacent Statement template
writes the cleanup in the same enclosing lifetime:

```x2c
macro open Statement $managed_cleanup(Expr $receiver) {
  defer $receiver.cleanup();
}
```

The client supplies its already installed receiver binding and applies the
whole statement without creating another block:

```x2c
List receiver = %(expr $type (ident $binding));
Macro cleanup = $managed_cleanup;
output.push(c.bind_syntax(cleanup(receiver), AST_STATEMENT, c.return_type));
```

The focused comparison must retain the generated call target, one cleanup
per managed binding, ordering across mixed declarations, and its existing
scope boundary. If binding the template changes any of these, retain the
current resolved-call owner and record the limitation here.

The managed-init runtime fixture and no-protocol/static rejection fixtures
pass. Translating the runtime fixture with the prior bootstrap compiler and
the candidate produces byte-identical C and H. The adjacent source template
replaces the nested raw member call and defer construction without changing
the declaration-splitting owner.

### E13. Region call-recognition boundary

A narrow `$called(Expr function, Expr arguments...)` recognizer in
`src/regions.x` passed `region-safe` but missed escape calls. The region scan
peels the typed `(expr ...)` wrapper before examining raw `(call ...)` nodes;
the Expression matcher needs that wrapper. In the prototype,
`region-escapes` lost all 64 expected diagnostic lines and
`region-local-escapes` lost its `_field_of(&box)` warning and changed a
borrowed sink's region. Restoring the original source made all three fixtures
pass again. This rejects the narrow typed-matcher substitution. A future
shared recognizer must account for the raw-node boundary and retain those
escape diagnostics without a parallel raw fallback.

### E16. Synthetic file initializer: sequence-hole exception

The executable `conditional-type-initializer` fixture establishes the
important boundary: a type initializer compiled out by preprocessor arms
still leaves the file's cache and shutdown behavior reachable. The generator
continues to select a constructor or lazy entry, track conditional arms,
order `<early>`, `<mid>`, and `<late>` statements, and place shutdown last.
The trial template tried to write the generated function shape and its
once-only guard:

```x2c
macro open Unit $file_initializer(Type $result, Name $name, Name $guard,
    Statement $entry..., Statement $early..., Statement $mid...,
    Statement $late..., Statement $shutdown...) {
  $result $name(void) {
    $entry...
    if ($guard) return;
    $guard = 1;
    $early...
    $mid...
    $late...
    $shutdown...
  }
}
```

The trial client kept the existing `_file_init` selection and replaced
`_make_file_init_func`; all phase lists and conditional rows were already
produced by their current owners:

```x2c
static List _make_file_init_func(
  Compiler compiler, List type, List entry, List guard, List initializer,
  List shutdown) {
  Macro shape = $file_initializer;
  return compiler.bind_syntax(
    shape(type, initializer, guard, entry,
      compiler.init_statements(<early>),
      compiler.init_statements(<mid>),
      compiler.init_statements(<late>), shutdown),
    AST_UNIT, NULL);
}
```

`make build` rejected this shape at the second sequence parameter:
`sequence macro hole must be the final argument`. Multiple distinct ordered
phase and conditional sequences therefore cannot be separate holes in a
single current template. Combining them into one sequence would move their
visible order and the guard back to the client; it would not provide the
intended readable generated function. Also, `entry` and `shutdown` may
contain `preproc` rows from `_within_definitions`, which a Statement sequence
hole has not been shown to preserve. The `src/generate.x` trial was restored.
The existing native constructor remains the owner of preprocessor placement,
guard identity, phase order, and shutdown. No generated C/H comparison of the
trial was possible because the source could not compile.

### E17. Cache-slot assignment exception

`literal-cache-init` exercises the source cache's String, List, Array,
Map and boxed-Var slots. `_generate_cache_initializer` still selects each
slot's type from `Compiler.id_keys`; `_generate_cache_val` still resolves
references in the graph, and `Compiler.convert_expression` still prepares
one stored value. The assignment's C shape is this template:

```x2c
macro open Statement $cache_assignment(Expr $slot, Expr $value) {
  $slot = $value;
}

static List _generate_cache_assignment(
  int id, List value, List type, Compiler compiler, String prefix) {
  String ident = _generate_cache_ident(id, prefix);
  List binding = compiler.sym.reference(%($ident), NULL);
  List rhs = _generate_cache_val(value, compiler, prefix);
  rhs = compiler.convert_expression(rhs, type);
  Macro assignment = $cache_assignment;
  return compiler.bind_syntax(
    assignment(%(expr $type (ident $binding)), rhs), AST_BLOCK, NULL);
}
```

The caller would continue to append each statement to its existing header
or source initializer, preserving cache identity, graph dependency order
and early/late phase decisions. The attempted migration built and passed
`literal-cache-init`, `promoted-string-cache`, and `cache-reachability`; their
checked C, H, and transform sidecars did not change. It added seven lines
to `src/cache.x` to replace one compact AST assignment statement and
removed no shared machinery. The extra template and binding step do not
earn their cost for this single statement, so the source edit was restored.
The declarations and initializer functions remain separate potential shapes.

### E19. Static cache slot declaration exception

`literal-cache-init` emits grouped file-static String and Var slots. Both
header and source setup call `_generate_cache_declare` once per nonempty
List, String and Var group. `Compiler.cache` still assigns the ids; the
helper still turns each id into the current region's referenced binding.

```x2c
macro open Unit $cache_slots(Type $type, Name $names...) {
  static $type $names...;
}

static List _generate_cache_declare(
  List ids, String type, Compiler compiler, String prefix) {
  if (!ids) return NULL;
  Array names = [];
  foreach (Var id, ids)
    names.push(compiler.sym.reference(
      %(${_generate_cache_ident(id, prefix)}), NULL));
  Macro slots = $cache_slots;
  return compiler.bind_syntax(
    slots(%($type), names.list_free()), AST_UNIT, NULL);
}
```

The existing header and source callers would retain their type order and
nonempty checks. The attempted template built, but `literal-cache-init`
emitted `static String;` and `static Var;` instead of the grouped slot
declarations. Clang then reported undeclared `_0` through `_4` references.
The generated header matched its checked expectation; the generated C did
not. A `Name...` splice in this declarator position does not materialize
the names with the current template capability. The source edit was
restored. Splitting each slot into a separate declaration would change the
generated C and lose the existing compact grouping, so this batch does not
force that shape. Cache identity, graph and initializer phases remain with
the current owner.

### E20. Direct protocol update helper

`protocol-operator-direct-update` executes compound, prefix, and postfix
updates and observes their stored and returned values. The existing helper
decides the member signature, memo key, volatile pointer parameter, name,
and converted unit RHS. Two adjacent templates describe the two bodies:

```x2c
macro open Statement $protocol_update_body(Expr $current, Expr $call) {
  $current = $call;
  return $current;
}

macro open Statement $protocol_postfix_body(Type $type, Name $old,
    Expr $current, Expr $call) {
  $type $old = $current;
  $current = $call;
  return $old;
}
```

The complete client keeps the existing lookup, signature check,
memoization, bindings, and parameter rows. It builds the typed current value
and method call exactly once, then asks one template for the body and passes
its lowered statements to `wrapper_function`:

```x2c
String Compiler.protocol_update_helper(
  Compiler c, Type participant, String member, int postfix) {
  List key = %("protocol-update-helper" $participant $member $postfix);
  Var stored;
  if (c.protocol_helpers.try_get(key, stored)) return stored;

  List resolved = c.resolve_protocol_member(participant, member);
  if (!resolved) return NULL;
  List (source_binding, source_type) = resolved;
  List parameters = source_type.car().list().cadr();
  Type result = source_type.cdr();
  Type rhs_type = NULL;
  match (parameters)
    case %(?receiver ?rhs):
      if (List.equal(receiver, participant) &&
          result.equal(participant))
        rhs_type = rhs;
  if (!rhs_type) return NULL;

  String suffix = postfix ? "postfix" : "update";
  String name =
    %"_x2c_proto_${participant.car().str().lower()}_${member}_$suffix";
  List helper_binding = c.sym.introduce(name);
  List lhs_binding = c.sym.introduce("lhs");
  List op_binding = c.sym.introduce("op");
  Type pointer = cons(<*>, cons(<volatile>, participant));
  Type pointer_base = cons(<volatile>, participant);
  List lhs_pointer = %(expr $pointer (ident $lhs_binding));
  List zero = %(expr (int) (literal (int) "0"));
  List current = %(expr $participant (index $lhs_pointer $zero));
  List call_rhs = NULL, old_binding = NULL;
  Array declarations = [];
  declarations.push(%(param $pointer_base (bind $lhs_binding (*))));
  declarations.push(%(param ("Symbol") (bind $op_binding ())));

  if (postfix) {
    List one = %(expr (int) (literal (int) "1"));
    call_rhs = c.convert_expression(one, rhs_type);
    old_binding = c.sym.introduce("old");
  }
  else {
    List rhs_binding = c.sym.introduce("rhs");
    declarations.push(%(param $rhs_type (bind $rhs_binding ())));
    call_rhs = %(expr $rhs_type (ident $rhs_binding));
  }

  List call = %(expr $result
    (call
      (expr $source_type (ident $source_binding))
      (args $current $call_rhs)));
  Macro ordinary = $protocol_update_body;
  Macro saved = $protocol_postfix_body;
  List shape = postfix
    ? saved(participant, old_binding, current, call)
    : ordinary(current, call);
  List body = c.bind_syntax(shape, AST_BLOCK, participant);
  c.add_early(c.wrapper_function(
    %(static @participant), helper_binding, declarations.list_free(),
    body.cdr()));
  c.protocol_helpers[key] = name;
  return name;
}
```

The `current` expression deliberately retains `lhs[0]`, which the existing
emitter writes; changing it to `*lhs` would alter generated C even though C
values agree. The bound body is a `seq` of already typed statements, so its
tail supplies the wrapper's lowered body without a second body constructor.
The direct update fixture's C and H match the pre-edit bytes exactly;
compound, prefix, and postfix output and evaluation order are unchanged.
Four focused operator fixtures pass, including the direct update and index
matrix cases. Binding the template retains the `volatile` type on four
`lhs[0]` expression annotations in each of two transform sidecars. Their
generated C remains byte-identical, and both fixtures compile and run; the
transform sidecars are rebaselined to the bound type.
### E14. Parsed if statement recognition (target readable form)

`Compiler.bind_syntax` owns condition resolution, optional-reference facts,
branch scope, and termination promotion. The shared grammar names its two
parsed source forms:

```x2c
macro Statement $if_then(Expr $condition, Statement $yes) {
  if ($condition) $yes
}

macro Statement $if_else(Expr $condition, Statement $yes,
    Statement $no) {
  if ($condition) $yes else $no
}
```

The complete binder client retains the current semantic operations and
their order, replacing only the two raw input patterns:

```x2c
Macro if_then = $if_then, if_else = $if_else;
match (input) {
  case if_then(?condition, ?ontrue):
    if (statement_position) {
      List test = _.resolve_expression(condition, _.token);
      int true_is_present = 1;
      List binding = _.optional_reference_test(test, true_is_present);
      List yes = _bind_optional_reference_arm(
        _, ontrue, binding, true_is_present);
      if (binding && !true_is_present && reference_guard_exits(yes))
        _.mark_reference_present(binding);
      return %(if $test $yes);
    }
  case if_else(?condition, ?ontrue, ?onfalse):
    if (statement_position) {
      List test = _.resolve_expression(condition, _.token);
      int true_is_present = 1;
      List binding = _.optional_reference_test(test, true_is_present);
      List yes = _bind_optional_reference_arm(
        _, ontrue, binding, true_is_present);
      List no = _bind_optional_reference_arm(
        _, onfalse, binding, !true_is_present);
      if (binding &&
          ((reference_guard_exits(yes) && !true_is_present) ||
           (reference_guard_exits(no) && true_is_present)))
        _.mark_reference_present(binding);
      return %(if $test $yes $no);
    }
}
```

The enclosing `at` case still binds first and reattaches its anchor. No
output template is added: these macros are recognition forms, and the binder
continues to produce its bound if node. `optional-reference` covers one-arm
promotion and macro-produced guards; `c-body-directive` covers two-arm if
syntax and its emitted C.

### E15. Parsed while and do recognition (target readable form)

`c-body-directive` contains both `while (total > 100)` and a `do` body
followed by `while (total < 5)`. The binder continues to own statement
position, condition resolution, body binding, loop control, and diagnostics.
The source forms in the shared grammar are:

```x2c
macro Statement $while_loop(Expr $condition, Statement $body) {
  while ($condition) $body
}

macro Statement $do_loop(Statement $body, Expr $condition) {
  do $body while ($condition)
}
```

The complete replacement client in `Compiler.bind_syntax` is:

```x2c
Macro while_loop = $while_loop, do_loop = $do_loop;
match (input) {
  case do_loop(?body, ?condition):
    if (statement_position)
      return %(do
        ${_.bind_syntax(body, AST_STATEMENT, _.return_type)}
        ${_.resolve_expression(condition, _.token)});
  case while_loop(?condition, ?body):
    if (statement_position)
      return %(while
        ${_.resolve_expression(condition, _.token)}
        ${_.bind_syntax(body, AST_STATEMENT, _.return_type)});
}
```

The enclosing `at` case still reattaches source anchors. The output remains
the binder's canonical node; no output template is added. `for` stays with
its existing raw pattern because its three clauses can each be absent (all
eight combinations are in `for-omitted-clauses`), while an `Expr` source
hole requires an expression. `c-body-directive`, `comptime-lowering`, and
`cleanup-loop-boundary` check the two loop forms and transfer behavior.
The `do` form omits a template trailing semicolon so a macro-produced
`do ... while` statement matches the same binder case;
`macro-statement-production` checks that constructed path.

### E18. Parsed return recognition (target readable form)

`macro-string-return` has both a source `return "NaN"` and the same return
through a Statement macro. `Compiler.finish_return_statement` resolves the
expression, checks its conversion, and writes the active `return_type` into
the bound node. An empty return has no type child. The source forms are:

```x2c
macro Statement $return_empty() { return; }
macro Statement $return_value(Expr $value) { return $value; }
```

A return expression parsed inside a function already carries its current
type annotation. That annotation is binder context, not source syntax. The
Statement source matcher recognizes both the annotated source form and an
unannotated macro-produced return without a separate projection operation;
the binder still writes the active return type after resolving the value.

The complete client in `Compiler.bind_syntax`, before its main match, is:

```x2c
Macro return_empty = $return_empty, return_value = $return_value;
match (input) {
  case return_empty():
    if (statement_position) return _.finish_return_statement(NULL);
  case return_value(?expression):
    if (statement_position) return _.finish_return_statement(expression);
}
```

The enclosing `at` case reattaches source positions. The binder continues
to use its active return type for conversion. `macro-string-return`,
`macro-statement-production`, `managed-init-return`, and
`class-init-wrong-return` check source and macro returns, empty return,
conversion, and rejection diagnostics.

### E21. Parsed defer recognition (target readable form)

The shared grammar already writes the source form used by transform:

```x2c
macro Statement $deferred(Statement $body) {
  defer $body
}
```

`Compiler.bind_syntax` can use that same form for parsed and constructed
defer statements. Its complete client keeps body binding and the canonical
output node with their existing order and statement-position check:

```x2c
Macro deferred = $deferred;
match (input) {
  case deferred(?body):
    if (statement_position)
      return %(defer ${_.bind_syntax(
        body, AST_STATEMENT, _.return_type)});
}
```

The enclosing `at` case retains source anchors. `defer-only-cleanup` checks
assignment and increment cleanup, `defer-try-cleanup` checks transfer order,
and `managed-init-runtime` checks compiler-produced deferred cleanup.

### E22. Aggregate descriptor rendering guard: binding exception

The `class-private` executable probe generates all four aggregate `Var`
rendering thunks. Their current bodies each declare a `RenderPath`, fall back
on recursive entry, defer leaving the path, then run the original member
call. The trial adjacent template showed that C shape while retaining the
producer's already typed calls and member-specific fallback:

```x2c
macro open Statement $render_guard(Name $path, Expr $enter,
    Expr $fallback, Statement $leave, Statement $body) {
  RenderPath $path;
  if (!$enter) return $fallback;
  defer $leave
  $body
}
```

The trial client replaced only `_guard_value_rendering`. It
keeps the generated function's result, binding, parameters, and original
body; selection of the `String` or `Buffer` fallback remains adjacent:

```x2c
static List _guard_value_rendering(
  Compiler compiler, List function, String member) {
  match (function)
    case %(function ?result
           (!set ?declarator
             (bind ? ((fnmod (params
               (param ? (bind ?boxed ?)) *remaining)) *)))
           (block *body)): {
      Type returns = result.type().declared();
      List value = %(expr ("Var") (ident $boxed));
      List fallback = NULL;
      if (member == "str" || member == "repr")
        fallback = %(expr ("String")
          (call "Var_pointer_string" (args $value)));
      else match (remaining)
        case %((param ? (bind ?output ?))):
          fallback = %(expr ("Buffer")
            (call "Var_write_pointer_repr"
              (args $value (expr ("Buffer") (ident $output)))));
      List path = compiler.sym.introduce("render_path");
      compiler.semantic_binding_facts()[%(automatic $path)] = 1;
      compiler.semantic_binding_facts()[%(type $path)] = %("RenderPath");
      List address = %(expr (* "RenderPath")
        (op & (expr ("RenderPath") (ident $path))));
      List enter = %(expr (int)
        (call "RenderPath_enter" (args $address
          (expr (* void) (call "Var_pointer" (args $value))))));
      List leave = %(stmnt (expr (void)
        (call "RenderPath_leave" (args $address))));
      Macro guard = $render_guard;
      List guarded = compiler.bind_syntax(
        guard(path, enter, fallback, leave,
          %(code-value "lowered" (seq @body) ())),
        AST_BLOCK, returns);
      return %(function $result $declarator (block @guarded.cdr()));
    }
  return function;
}
```

The trial deleted the hand-built declaration, conditional return and defer
body while keeping typed `RenderPath` calls and the function skeleton.
`make build` passed, but the exact C/H comparison failed: in both
`class-private-a.c` and `class-private-b.c`, the last `write_repr` thunk
changed `RenderPath render_path` to
`RenderPath _x2c_binding_shadow_0`; its enter call and deferred capture used
that renamed binding. The other generated C/H files matched. Binding the
template therefore changed the emitted local identity after repeated thunk
construction. The source trial was restored instead of adding special
binding machinery. Keep `_guard_value_rendering` as the native AST owner for
this shape; no template migration or artifact rebaseline was accepted.
### E23. Parenthesized expression `sizeof` recognition exception

`expressions.x` resolves a parenthesized expression operand while retaining
the parsed `sizeof (parens ...)` form, the caller's result type and origin.
The readable source-form replacement would be:

```x2c
macro Expression $sizeof_value(Expr $operand) => sizeof($operand);

/* In _resolve_content, before the content match. */
Macro sized = $sizeof_value;
match (input)
  case sized(?operand):
    return %(expr $input_type
             (sizeof (parens ${c.resolve_expression(operand, origin)})));
```

An isolated matcher probe captured `sizeof(1 + 2)` as the typed `1 + 2`
expression, and `sizeof((1 + 2))` as the typed inner parenthesized
expression. Unary `sizeof 1` did not match. However, `sizeof(int)` also
matched and captured `(decl (int) (bindings (bind () ())))`. The proposed
client would resolve that declaration as an expression and change the
type-operand behavior. Distinguishing the forms needs another structural
guard or a more precise matcher capability, so no compiler source edit was
made. The existing raw cases remain until one source macro separates the
expression and type forms without new client-side shape inspection.

The existing `sizeof-expression-operand` fixture passed on the clean base,
including parenthesized, unary and type operands. Its checked stdout is
`4 8 8 4 8 8`; diagnostics are empty. It declares no C/H sidecars, so
those generated files were retained as baseline artifacts rather than
rebaselined.

### E24. Bound while and do transfer recognition (target readable form)

The E15 shared Statement forms also describe the bound loops that
`_rewrite` receives. This pass owns transfer-region barriers, so it keeps
its `_bounded(body, 1)` call and the condition rewrite in their current
positions. Its complete client is:

```x2c
Macro caught = $caught, tried = $tried;
Macro while_loop = $while_loop, do_loop = $do_loop;
match (node) {
  case while_loop(?condition, ?body):
    return %(while ${_rewrite(walk, condition)}
                  ${_bounded(walk, body, 1)});
  case do_loop(?body, ?condition):
    return %(do ${_bounded(walk, body, 1)}
               ${_rewrite(walk, condition)});
}
```

The `at` case still sets the origin before either matcher runs. This is
recognition only; output remains the canonical bound loop node, and `for`
continues to handle its optional clauses separately. The checked
`cleanup-loop-boundary`, `macro-statement-production`, and
`c-body-directive` fixtures cover transfer boundaries, constructed do, and
direct while/do C output.

### E25. Bound conditional truth conversion (target readable form)

The binder emits one-arm `(if test yes)` and two-arm `(if test yes no)`
nodes; the transform's `_truthy` reads these before rewriting their
children. The E14 and E15 Statement forms recognize them without changing
condition conversion or branch ownership. The complete client is:

```x2c
static List _truthy(Compiler compiler, List ast) {
  Macro if_then = $if_then, if_else = $if_else;
  Macro while_loop = $while_loop, do_loop = $do_loop;
  match (ast) {
    case if_then(?condition, ?yes):
      return %(if ${_truthy_expression(compiler, condition)} $yes);
    case if_else(?condition, ?yes, ?no):
      return %(if ${_truthy_expression(compiler, condition)} $yes $no);
    case while_loop(?condition, ?body):
      return %(while ${_truthy_expression(compiler, condition)} $body);
    case do_loop(?body, ?condition):
      return %(do $body ${_truthy_expression(compiler, condition)});
  }
  // The existing for, operator, and default cases follow unchanged.
}
```

The `at` owner retains the anchor around the node, and `_truthy_expression`
still makes the sole condition conversion. Branch bodies and loop bodies
pass through in the same order. `optional-reference`, `c-body-directive`,
`percent-after-condition`, and `macro-statement-production` check bound
one- and two-arm if forms, direct loops, expression parsing after a
condition, and constructed statements.
### E26. Parsed bracket index recognition: origin-wrapper exception

`_parse_postfix_index` supplies a full `(expr type (index receiver selector))`
to `Compiler.resolve_expression`. The trial shared grammar macro was:

```x2c
macro Expression $indexed(Expr $receiver, Expr $selector) =>
  $receiver[$selector];
```

`_resolve_content` already matches lambda source macros against full `input`.
The trial index client placed the following case in that same `match (input)`,
before `match (content)`, and deleted the raw-content index case:

```x2c
Macro indexed = $indexed;
match (input) {
  /* Existing captured and ordinary lambda cases stay first. */
  case indexed(?receiver, ?selector): {
    receiver = c.resolve_expression(receiver, origin);
    selector = c.resolve_expression(selector, origin);
    if (receiver.cadr().car() == <opt-ref>)
      c.report_error(
        <type>, "check optional reference before indexing its value",
        origin, NULL);
    if (_deferred_receiver(receiver) ||
        _deferred_receiver(selector))
      return %(expr (<macro-expr>) (index $receiver $selector));
    List resolved = c._postfix_index_expression(receiver, selector);
    if (resolved) return resolved;
    Type receiver_type = receiver.cadr();
    // A field of a foreign struct has no x2c type; C indexes it alone.
    if (!receiver_type &&
        List.match(receiver, %(expr () (op (!or . ->) * *))))
      return %(expr () (index $receiver $selector));
    c.report_error(
      <parse>, receiver_type.is_typedef_name()
        ? %"type $receiver_type does not support getindex"
        : %"type $receiver_type does not support indexing",
      origin, %());
  }
}
```

The parser kept its immediate resolution. This trial client kept operand
order, optional-reference rejection, deferred syntax, native pointer
indexing, foreign-field fallback, and the existing diagnostics in one owner.
`Array` and `Map` source brackets resolve to `getindex` before this case; the
source macro does not claim their distinct semantic nodes. An inert matcher
probe found `$indexed` matches the full parsed pointer index and preserves
both captures, including under an `<macro-expr>` root; it does not match the
inner `content` alone. The trial passed `make build` and the focused
`index-slice-lowering`, `macro-generated-index`, and
`protocol-operator-index-matrix` fixtures. Their generated C/H files
match pre-edit bytes, and the checked AST, transform, C warning, stdout and
status artifacts remain unchanged. `macro-deferred-free-index`,
`string-typedef-bracket-assignment`, and `bracket-index-incompatible` retain
their checked diagnostics; `typed-alias-own-getindex` still passes.

The inert matcher also matches `(expr () (at m-origin (index receiver
selector)))`. `Macro_case_capture` unwraps that source marker, so this
input-level case would run before the existing `match (content)` marker case.
That owner returns the original expression when source maps are disabled or
macro holes are active, and otherwise replaces the marker with `c.origin`.
The trial instead resolves the index and loses or reorders that behavior.
Preserving the boundary requires another marker guard or changed case order,
adding machinery beyond this one-shape replacement. Both source edits were
restored; the raw-content index case remains, with no `$indexed` grammar macro.
The passing fixtures establish ordinary index parity, not parity for this
constructible marked form. No migration or generated-artifact rebaseline is
accepted for E26.

### E27. Deferred restore statement recognition (target readable form)

`regions.x` reads bound, typed statements before transform. In
`region-safe`, `defer current_value = saved;` restores a static place after
the block. Recognition needs only the expression statement wrapper; the
existing assignment inspection and `_target_place` still decide whether
the store restores a place.

```x2c
macro Statement $expression_statement(Expr $value) { $value; }

static int _note_restored(Walk w, Var body) {
  Macro statement = $expression_statement;
  match (body) case statement(?expression):
    match (_unwrap(expression)) case %(op (!quote =) ?target ?): {
      Var place = _target_place(w, target);
      if (place == _unwrap(target)) return 0;
      w.restored = w.restored.copy();
      w.restored[place] = 1;
      return 1;
    }
  return 0;
}
```

The case must capture exactly the bound expression from `(stmnt EXPRESSION)`;
it must leave the enclosing source position and `w.origin` untouched.
An isolated matcher probe built the bound expression from the
`region-safe` AST dump, including its two issued binding identities and
pointer type. The macro captured a structurally equal expression, with no
statement wrapper or extra parentheses. `_walk` continues to set and
restore `w.origin` around the outer `at` node; this match only sees the
inner statement. This batch changes no other region walker case or
restoration rule.

### E28. Region control-walker boundary

`Compiler.check_regions` walks the bound, typed unit before transform. Its
single `src/regions.x` control case gives if, while, do, for, switch, try,
match, and other control children one nested depth and restored-state scope.
`cleanup-loop-boundary` exercises a try containing loop and switch transfers
whose cleanup depends on that shared scope. Replacing just while/do or try
with source matchers would duplicate the depth/restored handling while the
heterogeneous raw case remained. A whole-case source form would also need
to represent optional for clauses and the different bound try and match
children; with is consumed into a block, and finally belongs to try.
Keep this combined walker as a current bounded exception. This records the
present representation boundary, not a claim that a later cohesive change
is impossible.

### E29. Iter-chain outer-call recognition exception

`Compiler.complete_iter_chain` in `src/expressions.x` recognizes a typed
direct identifier call whose callee has a `func` signature. It uses the
signature's formal parameters, the result type, and the callee binding to
complete nested `Iter` calls and append a missing destination. The
`iter-chain-completion` fixture checks AST, transform, C, stdout, and status
for fluent, nested, and explicitly stored chains.

An inert matcher probe tried this shared source form:

```x2c
macro Expression $called(Expr $callee, Expr $arguments...) =>
  $callee($arguments...);
```

It compared a typed direct `Iter_map` call with indirect,
native-string-callee, untyped-callee, and non-`Iter`-result controls. Its
output was `1111 100 100 100 1111`:
the shared macro matched every call, while the current raw case matched only
the typed direct call and the non-`Iter`-result control. The later result-type
test rejects that last control. The macro preserved callee and argument
captures for the direct call.

A complete client would still match the captured callee against
`(expr ((func parameters) result) (ident binding))` and read the outer result
type, before running the existing semantic body. It would retain raw signature
destructuring while adding a grammar macro, a macro binding, a nested match,
and result extraction. This proposed outer-call replacement removes too
little structural code to justify those additions. Keep the current case;
this finding does not reject other call-form consumers or a different shared
projection.
### E30. Bound switch transfer recognition (target readable form)

`_switch_statement` parses a subject and body, and `bind_syntax` publishes
the same two-child `(switch subject body)` shape with a resolved subject.
The shared source form is:

```x2c
macro Statement $switched(Expr $subject, Statement $body) {
  switch ($subject) $body
}
```

The complete `_rewrite` client retains the current child order and switch
break boundary:

```x2c
Macro caught = $caught, tried = $tried;
Macro while_loop = $while_loop, do_loop = $do_loop;
Macro switched = $switched;
match (node) {
  case switched(?subject, ?body):
    return %(switch ${_rewrite(walk, subject)}
             ${_bounded(walk, body, 0)});
}
```

The outer `at` case still owns source origins, and the result stays a
canonical switch node. `cleanup-loop-boundary` checks break/continue
cleanup, `c-body-directive` checks native C output, and
`comptime-lowering` checks switch execution.
### E31. Remaining region expression statement recognition (target readable form)

`regions.x` also reads expression statements in the deferred-effect walker
and the main region walker. The E27 source matcher supplies the same bound
expression from each `(stmnt EXPRESSION)` node:

```x2c
macro Statement $expression_statement(Expr $value) { $value; }

static void _walk_defer(Walk w, Var body) {
  List arguments = NULL;
  String callee = NULL;
  Macro statement = $expression_statement;
  match (body) case statement(?expression):
    callee = _callee_of(expression, arguments);
  // Existing fact, effect, ownership, and deferred-store handling follows.
}

static void _walk(Walk w, Var node) {
  Macro statement = $expression_statement;
  match (node) {
    // Existing origin and other statement cases precede this case.
    case statement(?expression): {
      List arguments = NULL;
      String callee = _callee_of(expression, arguments);
      if (callee && _walk_region_call(w, callee, arguments)) break;
      match (_unwrap(expression)) {
        case %(op (!quote =) ?target ?value): _store(w, target, value);
        default: _scan(w, expression, 0);
      }
    }
  }
}
```

Only the two outer wrapper cases change. `_callee_of` still receives the
bound expression and retains call argument identity and order. `_walk_defer`
continues to resolve the same fact and effect before its ownership cases.
`_walk` continues to set and restore `w.origin` at the enclosing `at` node;
its region call handling, `_store`, and `_scan` keep the same expression,
targets, values, and diagnostic origins. The matcher adds no fallback raw
statement case. The E27 probe established exact capture of a bound typed
assignment in `region-safe`. After this edit, `make build` and the
`region-safe`, `region-local-escapes`, and `goto-cleanup-regions` fixtures
passed. Their checked diagnostics, and the latter fixture's generated C and
transform sidecar, matched byte for byte.

### E32. Parsed member access: marker and Name-shape exception

`_parse_postfix_dot` and `_parse_postfix_arrow` produce full expressions with
`(op . receiver field)` and `(op -> receiver field)`. The field is a one-item
list containing its spelling. `_resolve_content` recognizes both with one raw
content case, then retains `resolve_postfix_member` as the owner of field and
method selection, native access, deferred typing, and diagnostics.

The proposed shared forms and complete client were:

```x2c
macro Expression $dotted(Expr $receiver, Name $member) =>
  $receiver.$member;
macro Expression $arrowed(Expr $receiver, Name $member) =>
  $receiver->$member;

Macro dotted = $dotted, arrowed = $arrowed;
List receiver = NULL, field = NULL;
Symbol operator = 0;
if (!List.match(content, %(at m-origin ?))) match (input) {
  case dotted(?target, ?name): {
    receiver = target;
    field = %($name);
    operator = <.>;
  }
  case arrowed(?target, ?name): {
    receiver = target;
    field = %($name);
    operator = <"->">;
  }
}
if (operator) {
  receiver = c.resolve_expression(receiver, origin);
  Type receiver_type = receiver.cadr();
  List resolution = c.resolve_postfix_member(
    receiver_type, field, operator, 0);
  match (resolution)
    case %(field ?access ?field_type):
      return %(expr $field_type (op $access $receiver $field));
  Type type = _deferred_receiver(receiver) ? %(<macro-expr>) : NULL;
  return %(expr $type (op $operator $receiver $field));
}
```

An inert direct dot/arrow probe matched each full input, preserved its
receiver, and captured the exact member spelling. It also matched both nodes
inside `(expr () (at m-origin ...))`: the probe printed `11111 11111`, with
the last bit denoting that marker overcapture. The Name capture is the
spelling, while the current resolver consumes the one-item field list, so
the client must rebuild it. Full-input matching would run before the existing
`match (content)` origin case, which returns the original expression when
source maps are off or macro holes are active and otherwise reanchors it.
The guard, field reconstruction, and two-arm dispatch enlarge the current
compact case. No source migration or output rebaseline is accepted for this
proposed pair. `macro-postfix-members` and `method-pointer-receiver` remain
the focused behavior fixtures; their artifacts were not rerun for this
inert-only exception.

### E33. Shared expression source-form preflight

`Compiler.resolve_expression` remains the sole caller of `_resolve_content`.
It first consumes staged code and returns already-resolved expressions that
need no further resolution. Inside `_resolve_content`, the existing captured
and ordinary lambda cases must remain first: they already match full `input`
and bind or retain their bodies according to `macro_holes`.

Source-form cases for index, member, and `is` also need full `input`. A macro
case looks through `at`, `src`, and nested macro-expression shells, while the
current content matcher handles a direct `at m-origin` marker before those
parsed nodes. The shared client preflight belongs after the lambda cases and
before future full-input source-form cases. The complete local shape is:

```x2c
match (input) {
  case captured(?body, *captures, *params): {
    if (c.macro_holes) return input;
    return c.bind_lambda_expression(
      input_type, %(params @params), captures, body);
  }
  case lambda(?body, *params): {
    if (c.macro_holes) return input;
    return c.bind_lambda_expression(
      input_type, %(params @params), NULL, body);
  }
}
if (content &&
    (content.car() == <at> || content.car() == <src>)) {
  match (content) case %(at m-origin ?inner): {
    if (!c.source_map || c.macro_holes) return input;
    return %(expr $input_type (at ${c.origin} $inner));
  }
  return input;
}
if (content && content.car() == <expr>)
  match (content) case %(!set ?inner (expr ? ?)):
    return c.resolve_expression(inner, origin);
/* Future full-input source-form cases belong here. */
match (content) {
  /* The remaining existing content cases stay in their current order. */
}
```

The `at` branch preserves direct `m-origin` reanchoring and the unchanged
fallback for every other outer `at`. The `src` branch preserves its unchanged
fallback. Nested expressions still recurse before any future macro case.
The ordinary content matcher loses only those two leading cases. The outer
head check avoids a second full matcher on ordinary expressions; only rare
wrapper and nested-expression heads run a focused match. This is resolver
ordering, not a change to global macro matching or source-origin validation.
It is a capability checkpoint preceding any index/member/`is` adopter, whose
capture and output parity remain separate decisions.

The source diff adds six net lines. `make build` passes. A temporary native
probe linked the current compiler objects and called `resolve_expression`
on constructed direct `m-origin`, numeric `at`, `src`, and nested-expression
inputs for all four `source_map`/`macro_holes` combinations. It printed
`1111 1111 1111 1111`: direct `m-origin` stays identical except for the
existing source-map reanchor when `source_map` is on and `macro_holes` is
off; the other wrappers retain identity, and nested expressions recurse.
The probe and output are retained under `/tmp/x2c-e33-resolver-probe`.

Focused checked artifacts pass for `is-type-macro`, `macro-generated-index`,
`macro-postfix-members`, `lambda-lowering`, `provenance-generated-lambda`,
`is-type-non-var`, `macro-postfix-missing-method`,
`index-slice-lowering`, and `method-pointer-receiver`. Source-map C/H from
the first three fixtures match pre-edit bytes after normalizing only the
different output-directory path written in C `#line` directives. This
checkpoint changes resolver ordering alone; no source-form adopter or global
matcher behavior changed.

### E34. Parsed match statement recognition (target readable form)

`parse.x::bind_syntax` receives `(match SUBJECT CASES)` from the ordinary
statement parser and from constructed canonical Lists. The `MatchRow` hole
now captures each complete arm or directive row. In `match-arm-directive`,
those rows interleave preprocessor directives, guarded cases, and conditional
defaults; `match-typed-guards` adds typed capture declarations. Recognize only
the outer source form:

```x2c
macro Statement $matched(Expr $subject, MatchRow $rows...) {
  match ($subject) { $rows... }
}

Macro matched = $matched;
match (input) {
  case matched(?subject, *cases): {
    if (!statement_position) goto construction_error;
    Array bound = [];
    foreach (List row, cases) {
      if (row.car() == <preproc>) {
        bound.push(row);
        continue;
      }
      List pattern = row.car();
      int binds = pattern !== %(*);
      if (binds) pattern = _.resolve_expression(pattern, _.token);
      _.begin_match_arm(pattern, _.token, binds);
      {
        defer _.sym.pop_scope();
        List body = row.cadr();
        match (body) {
          case %(guarded ?statements):
            body = %(guarded ${_.bind_syntax(
              statements, AST_STATEMENT, _.return_type)});
          default:
            body = _.bind_syntax(body, AST_STATEMENT, _.return_type);
        }
        bound.push(%($pattern $body));
      }
    }
    return %(match ${_.resolve_expression(subject, _.token)}
                   ${bound.list_free()});
  }
}
```

The macro is shared in `grammar.xmacro`; `parse.x` keeps the entire existing
row loop, scopes, guarded-body path, subject resolution, and error route.
No raw fallback or row projection is added. `bind_syntax` continues to accept
constructed canonical Lists by structure, without authenticating their
origin or adding a validator. Before adoption, compare the macro's captured
subject and rows with the raw shape for both fixtures using `List.compare`,
including typed binding identities and every directive/default row. After
the one-case edit, require byte-identical checked C/H, transform, stdout,
status, and diagnostics for those fixtures. Review the two-file authored
source diff before committing. This batch does not lower or emit match arms.

### E35. Parsed bracket index recognition after origin preflight

`_parse_postfix_index` produces `(expr () (index receiver selector))` and
immediately calls `resolve_expression`. The E33 preflight handles outer
`at`/`src` markers and nested expression shells before the following
full-input source match. The shared form and complete resolver client are:

```x2c
macro Expression $indexed(Expr $receiver, Expr $selector) =>
  $receiver[$selector];

/* After the existing lambda cases and E33 preflight, before match(content). */
Macro indexed = $indexed;
match (input) case indexed(?receiver, ?selector): {
  receiver = c.resolve_expression(receiver, origin);
  selector = c.resolve_expression(selector, origin);
  if (receiver.cadr().car() == <opt-ref>)
    c.report_error(
      <type>, "check optional reference before indexing its value",
      origin, NULL);
  if (_deferred_receiver(receiver) ||
      _deferred_receiver(selector))
    return %(expr (<macro-expr>) (index $receiver $selector));
  List resolved = c._postfix_index_expression(receiver, selector);
  if (resolved) return resolved;
  Type receiver_type = receiver.cadr();
  // A field of a foreign struct has no x2c type; C indexes it alone.
  if (!receiver_type &&
      List.match(receiver, %(expr () (op (!or . ->) * *))))
    return %(expr () (index $receiver $selector));
  c.report_error(
    <parse>, receiver_type.is_typedef_name()
      ? %"type $receiver_type does not support getindex"
      : %"type $receiver_type does not support indexing",
    origin, %());
}
```

The raw-content index case is removed; this client keeps its body unchanged.
The parser retains token order and immediate resolution. The resolver retains
operand order, optional-reference rejection, deferred syntax, protocol lookup,
native pointer and foreign-field fallbacks, and diagnostics. The template owns
only the parsed index skeleton. Constructed syntax remains legal and enters
the same resolver. Compare direct `m-origin`, numeric `at`, `src`, and nested
expression index nodes under all source-map/macro-hole states against the
pre-edit compiler; compare bare index output and focused fixture C/H, AST,
transform, diagnostics and native behavior exactly. A marker mismatch stops
the migration, with no raw fallback or additional validator.

The pre-edit compiler and the rebuilt candidate gave byte-identical output
from a temporary direct resolver probe. It exercised a typed native-pointer
index bare and under direct `at m-origin`, numbered `at`, `src`, and nested
`expr` wrappers in all four `source_map`/`macro_holes` combinations. The
bare index resolves through the new sole index case; no raw case remains.
`make build` and seven focused fixtures pass: `macro-generated-index`,
`index-slice-lowering`, `protocol-operator-index-matrix`,
`macro-deferred-free-index`, `string-typedef-bracket-assignment`,
`bracket-index-incompatible`, and `typed-alias-own-getindex`. The first
three fixtures' generated C/H pairs are byte-identical to pre-edit output
from the same output paths. Their checked AST, transform, warning, stdout,
and status artifacts, and the latter fixtures' diagnostics, remain unchanged.

### F. Static-local initialization exception

The survey traced this shape to `Emitter._local_static` and `_static_copy`
in emit.x, rather than the distinct file-initialization paths in cache and
generate. Inferred arrays depend on native `__typeof__(formal)` after
preprocessing; native aliases and `static_objects` substitutions also preserve
the initializer's original expansion position and stable payload address.
Current source templates cannot express that type-dispatch boundary directly.
Skip this whole-shape migration under the campaign's explicit exception rule;
retain its existing native owner. This is not a migrated shape or a claim
that a future native-template capability is impossible. Do not create that
capability merely to force this migration.

### Migration defect tasks

- **Expansion depth diagnostic:** open; reported by the previous migration.
  Source and macro-value finite-chain probes reach the 64-level limit with
  a normal diagnostic on this checkout. The compiler-generated path may
  have a null invocation token (`macro_invocation_site`), and rendering the
  whole stack row calls `Token_repr`, which dereferences it. The capability
  batch reports the first definition location instead of rendering internal
  stack storage. The synthetic-call crash has not yet been reproduced here.
- **Parameter redeclaration:** landed in `799875a8`, including the
  `fff7eec6` repair that isolates each invocation's Param argument scope. Ordinary,
  bare/typed lambda and constructed lambda redeclarations now fail at the
  existing declaration check. Nested shadowing and parameter-template
  replay pass. Outer callable bodies share parameter scope; nested blocks
  keep their own scopes.
- **Standalone raw-symbol sweep:** open and already filed in
  [raw-symbol translation of macros.x](raw-symbol-macros-translation.md).
  Keep this independent from the capture-hole capability; the current
  standalone raw translation failure is not evidence against that hole.


## 7. Name, positions and sequences

Name is one logical argument with role-specific existing projections, not one
raw binder duplicated into every field. Declaration/reference positions use
the same issued binding when supplied; a plain name introduced by declaration
uses ordinary declaration ownership. Member positions use the source-name
projection, including `semantic_binding_facts[(source-spelling BINDING)]`
when fresh emission names differ. Member-only names remain ordinary labels.

Recognition correlates declaration/reference identities and member labels
through those projections. Alpha normalization renames local bindings, not
member fields. A candidate declaring `subtotal`, referencing it and selecting
member `subtotal` can satisfy one mixed Name hole; selecting `total` cannot.
Two distinct local declarations cannot collapse to one identity. These checks
belong inside Match's retry relation, not after committing the first candidate.
Mixed-role constraints now have a working probe on actual named-macro output:
`grammar-mixed-name.x` gives hit/miss/renamed/wrong-reference results 1/0/1/0.
That probe uses a private raw-pattern recognizer, not the automatic Macro case
adapter; the complete source-case integration is still missing. The member-only tests alone do not prove that larger case.

Comparison ignores `at`/`src` wrappers, while captures and reconstruction must
retain original subtree correspondence. A newly constructed skeleton inherits
the user's construct origin, with definition/generated ancestry through the
existing compiler diagnostic owner. Bound hole content retains its original
origins. Compiler clients supply/restore the existing origin context; there is
no new source-marker API. Never fabricate exact source text from structural
equality. Existing complete-argument source records do not establish exact
text for every interior capture.

The phase 3 hygiene projection preserves binding records but loses some
wrappers. Retaining comparison-to-original subtree paths is the recommended
fix; it is per-attempt capture bookkeeping, not semantic origin validation.
Recursive optional-wrapper patterns exceeded the existing Match capacity and
are a rejected implementation, not evidence against origin preservation.

Sequence recognition through the retained/expanded path is now independently
reproduced: `sequence-cases.x` captures two operands in either stage and
reconstruction returns 42. Pending sequences need one grouped List argument;
logical `*items` publishes that List directly, not a nested tail. Type capture
is likewise one logical Type, despite an internal splice representation.
General Param/Decl/Statement sequence recognition and simultaneous mixed Name
constraints remain narrower evidence than this Expr sequence proof.

Helper-boundary transport of closed binding environments and REPL interpreter
isolation are separate tracks. A compiler-owned open template applied locally
does not cross the project-meta process boundary. Neither work should become
a prerequisite for rewriting compiler construction sites that use only the
local path. The shared application/capture owners must nevertheless retain
their ordinary canonical List contract so later transport does not change
these public forms.

## 8. Effects and caller-owned transactions

Meta functions return ordinary data: code, ordered effects and logical result
references. They never receive a Compiler handle or query one through a hidden
callback. The canonical result is a private `(code-value STAGE VALUE EFFECTS)`
envelope, not a second AST: VALUE is the existing canonical code/List or
Name/Type/scalar value. Kind/position comes from the existing formal role and
AstPos; origin comes from ordinary caller context and retained `at` wrappers.
Do not duplicate those derived facts as mandatory envelope fields. The isolated
prototype uses a temporary string head `"x2c.slot"` for this same four-field
layout; this tag is not a public API or a new program AST production.
Lowering clients never unpack it. Ordinary bare List returns retain legacy
binding behavior; explicit marks distinguish compiler slots where trust matters.

Stages are `source`, `bound` and `lowered`. `source` enters ordinary binding;
`bound` preserves identities/types/content; `lowered` additionally bypasses
source-only productions and conversions already completed inside the value.
The skeleton still binds. A surrounding source call/initializer may request
one normal conversion around a bound Expr, never recursive retyping. Validate
slot placement through existing formal-role/AstPos machinery, not a recursive
stage validator or origin certificate. The stage is a producer contract,
just as typed canonical AST annotations already are. The control demonstrates
bound/lowered retention using private slots, not the complete envelope ABI.

Proposed effects are canonical data records, private to meta producers and the
ordinary compiler application owner. A result reference is a transaction-local
logical token, not a forged program binding or cache ID.

For the first combined try proof the effect vocabulary is **new-name, early,
cleanup**. The transaction extension covers `early_decls`, `names.adapters`,
`needs_exception` and origin, while proving preservation of scope/global
bindings, counters and `inits`. Broader queue/cache/global effect implementation
is not a prerequisite. The existing records below are an inventory: all records
other than those three are added only by a migration that needs them. Likewise,
no producer family is implemented in advance of its first consumer.

| Effect record | Producer intent | Compiler application point / owner | Phase |
| --- | --- | --- | --- |
| `(new-name REF STEM)` | Allocate one requested binding/name shared by later code. | Ordinary fresh_name + sym.introduce in original allocation order, before dependent binding; existing counters/IDs remain transaction-owned. | First try proof |
| `(global REF NAMESPACE NAME)` | Resolve an open fixed reference. | Ordinary target base-scope value/Type/tag lookup before dependent skeleton binding; global scope changes must join the transaction. | Inventory; add when first demanded |
| `(early CODE SITE)` | Register an adapter/helper declaration. | Pending early-declaration overlay; publish through add_early only after successful insertion. Existing transform drains it in order. | First try proof |
| `(memo KEY REF)` | Associate an adapter with its generated binding. | Pending names.adapters overlay visible to later planning in the same expansion, committed once insertion succeeds. Supplied prior hit remains authoritative. | Inventory; add when first demanded |
| `(constant REF VALUE)` | Intern canonical immutable constant data. | Existing constant/cache owner before code references REF; cache/name writes must be transactional or postponed until success. | Inventory; add when first demanded |
| `(initializer CODE DEPENDENCIES SITE)` | Schedule source/static initialization. | Existing init/dependency owner, buffered until successful insertion, preserving its order. | Inventory; add when first demanded |
| `(location SITE)` | Attribute newly constructed shape/diagnostics. | Dynamically scoped origin during construction/binding, restored on success or failure; original hole wrappers remain unchanged. | Inventory; add when first demanded |
| `(cleanup REGION EXIT CODE)` | Place cleanup at a particular region/exit. | Existing region/transfer owner at the named insertion, not a global append. Order includes unhandled branch, normal completion and transfer exits. | First try proof |
| `(require FEATURE)` | Request current generated runtime/header support such as exception support. | Existing needs_exception/emission owner, staged until successful insertion. | Inventory; add when first demanded |

Each REF is scoped to one application result bundle, including nested slot
results. A nested result remaps its local references on aggregation; unrelated
expansions never share them accidentally. Effects hydrate each logical reference
once before the binder can stop at a bound/lowered slot. Relocation follows the
existing hole-role table: declaration/reference roles share one issued binding;
Type roles use the target canonical Type; member roles project the requested
source name, not an emitted fresh alias. Relocation visits private placeholders,
not every binding record in borrowed hole code. A value still containing such
placeholders is pending preparation, not yet an already-bound trust boundary.
No user-supplied positive binding IDs are authenticated or rewritten merely
because they resemble the private token. The common adapter and its role
coverage beyond the narrow new-name/cleanup/early path remains unproved.
In particular, repeated early slots use the same binding/key; this proves
deduplication and read-your-writes, not relocation from a different requested
binding. Production memo keys include producer/template identity and relevant
arguments, using existing memo ownership rather than a fixed probe key.

Effects execute in declared dependency order. Template traversal order must not
silently move a frame allocation after nested regions: `_region_binding`
currently allocates the outer frame before walking its body. A dependency plan
must preserve that order or byte-identical names will change. Reused bindings
remain shared across code and cleanup records. Global lookup and allocation
results needed by later slots are supplied by the compiler in a subsequent
planned step; a helper cannot synchronously read an effect it has just returned.
Simple cases should instead pass facts the compiler already prepared.

Current `SymTxn` is not sufficient to claim this works. Source
`src/compiler.x:2574-2700` snapshots the current scope, counters, next_binding,
statics, binding/source facts and initializer names. It does not snapshot
`early_decls`, `names.adapters`, `file_scope_owners`, `origin/origins`, `inits`
or `needs_exception`. Global reference creation can touch base scope while
a transaction snapshots a local scope. Failure can therefore leak proposed
effects under the current implementation.

Extend the **existing caller-owned transaction** for the narrow try path:
cover early-declaration writes, adapter memo state, exception support and origin.
Preserve existing scope/counter ownership and verify unchanged global maps and
initializer queues. Broader cache/global mutation coverage follows its first
actual migration, not this proof. Preserve
read-your-writes within that transaction. No parallel transaction framework or
helper-side state mirrors are proposed. Apply provisional new-name effects
inside it; bind the result; commit early/cleanup/memo/support only on success; rollback
all provisional compiler state on failure. Nested insertions share the caller's
ordering/ownership and must not publish effects the outer transaction can lose.
Existing macro invocation creates its transaction in `_invoke_definition`,
not in `expand_macro_invocation_node` or `bind_syntax`; mid-transform callers
must own the same boundary explicitly.

The executable current-transaction probe reports
`binding=1 fresh=1 early=0 init=0 memo=0 global=0 origin=0 exception=0`,
where 1 means restored. Root reproduced these results using the ordinary
transaction methods. The probe cleans leaked state afterward; that cleanup
is not transaction coverage. See `.context/dual-macro-phase3/compiler-use/effects.md` and its fixture/log.
That was the phase-3 result. The narrowed phase-4 extension now passes the
requested rollback proof; see the combined proof below.

The narrowed failure probe compares scope/global bindings, counters,
`early_decls`, `inits`, `names.adapters`, `needs_exception` and origin before
and after a deliberately failing skeleton. A successful effect probe observes
its provisional early/memo state before commit and confirms publication once.
Cache/global mutation effects are inventory for later migrations, not a
requirement of this proof. The phase-3 shape control did not establish these properties. Phase 4 tests
real early/memo writes, a nested committed base reference/init/origin mutation,
a parsed source-slot failure and outer rollback. It compares every requested
store and checks borrowed adapter ownership on rollback and commit. These
narrow properties now pass; broader effects remain migration inventory.

Queries not already passed by current callers: per-catch pattern staticness;
resolved runtime callee signatures; adapter memo hit; alias/protocol/layout
classification; conversion results; precise origin; constant/init dependencies.
Existing compiler owners must prepare those arguments. `_try_block` currently
queries staticness mid-loop; wrapper/adaptation construction queries conversions
and memoization; source init/literal construction queries placement/cache state.
Do not reproduce those semantic owners in the helper. Facts needed only during
ordinary skeleton binding stay there. A complete dependency plan for cases
whose queries depend on a newly produced Type remains unprototyped.


## Combined proof: phase 4

Final compiler result: [phase4 binary checksum](https://github.com/gwf/x2c/blob/1e2d5607be514c7205507d3f6e39c889e0cff7ec/.context/dual-macro-phase4/combined/candidate.sha256), SHA256
`fa2fd1f67c31f07c486fb68acc6d1edcb9fdc2d7b23250d812935f28c00c1148`.
Sources, incremental patch, reproduction commands and failures are in
`.context/dual-macro-phase4/combined/`; comparison/timing evidence is in
`.context/dual-macro-phase4/comparison/`.

The compiled-in template is selected as `Macro shape = $compiler_try_shape`
and applied through `shape(args)`, then ordinary `bind_syntax`. The Macro call
owner creates a pending application using existing SDK capture rows, expansion
and binding. Actual parsed `$Prototype_frame($frame)...` and
`$Prototype_cleanup($cleanup)...` calls travel through the ordinary macro-slot
and explicit-meta evaluator. The producer result remains marked until the
common slot consumer applies effects and preserves bound/lowered payloads.
Native runtime calls are prepared bound inputs; no new hygiene work is done.

New-name allocation runs at the old pre-body point and delegates to ordinary
fresh_name/introduce. Cleanup uses the existing region decision and code.
A separate opt-in macro exercises two real early slots with one memo/queue row:
ordinary try has no new file early declaration. A nested transaction mutates
base bindings, inits, origin and support state and commits. A later source slot
returns an invalid skeleton; ordinary binding raises malformed. Recovery catches
it, then outer rollback compares all scoped symbol/binding/enumerator maps,
global binding maps, counters/next binding, early_decls, inits, adapters,
origins/scalar origin and needs_exception. Copied Map contents are compared
structurally; borrowed adapter owner identity is checked separately.

Root independently reproduced the final opt-in probe and native fixture:
`phase4 effects: early-read-write rollback-all borrowed-map-commit`, followed
by successful build and runtime `17 1 1 23`. With the opt-in flag removed, all
62 baseline/candidate statuses and raw C/H hashes match without normalization.
Diagnostic text is not compared. The same binary completed five paired timing samples; section 6 records them.

Remaining implementation detail is explicit: private stage constructors and
four-callee native producer dispatch demonstrate plumbing, not a public API
family or generic helper ABI. Production reuses the ordinary native-meta owner
for compiler-owned producer execution and marks values at producing boundaries.
No new parallel dispatcher, descriptor reader or stage getter is frozen for
lowering clients. The probe's successful early row is removed before fixture
emission, so separate emitted early-declaration C is not demonstrated.
Append-only queue restoration is proved; arbitrary clears/edits and mutations
inside shared map values are not. Bound and lowered payloads both bypass binding
in this prototype; correctness relies on this caller supplying owner-produced
values at the proper position. General category/conversion behavior is not
inferred from that success. Template-origin masking preserves supplied hole
origins for C parity, but precise failed-skeleton diagnostic attribution is thin.

## Combined proof: phase 5

The final isolated binary result, recorded in
[phase5 binary checksum](https://github.com/gwf/x2c/blob/1e2d5607be514c7205507d3f6e39c889e0cff7ec/.context/dual-macro-phase5/candidate.sha256), has SHA256
`ed6eb83bfb2e8977554ade3b95baaa75df123f58e3d76e9f6b646322e56252c5`.
The true `macro open` descriptor retains its policy on both provisional and
completed parser outputs; no name-based bootstrap bypass remains in the final
source. The template contains runtime calls, the client has no stage wrappers,
and frame/cleanup remain parsed meta slots using the same three-effect,
stage-carrier and transaction path as phase4.

All 62 outcomes and raw C/H files match the unmodified baseline, without
normalization. The same binary passes the failing-skeleton rollback probe and
then builds/runs defer-try-cleanup with `17 1 1 23`. Closed macro lexical hygiene
also builds/runs with `28 28`. The native-helper shadow check still fails
identically; its raw C matches the preserved baseline output. Evidence, source
checksums and the incremental
six-owner patch are in `.context/dual-macro-phase5/`; no further full source
copies were added. Paired timing is complete on this same binary; the running
ledger reports this candidate instead of adding it to the older try version.

The new preparation points are ordinary literal/canonical try and defer
owners, plus declaration binding that creates managed-initializer cleanup.
They prepare once per target Compiler while scopes are live. This matters:
defer lowering's lexical-transfer and unsupported-capture paths synthesize try
later; a resolver hooked only to literal try misses them. There is no late
resolution fallback and no scope-stack retention.

The earlier typed-global callee attempt emitted extra push/landed declarations.
The corrected native-role projection reuses the existing String-call branch,
so generated exception.h and normal C binding retain declaration/ABI ownership.
Program free roles are projected before hole substitution. Definition-site
meta callees and hole identities are preserved. The specific frame producer
returns a bound typed reference; its declaration producer extracts that same
binding, and ordinary address/member binding builds the native call arguments.

Failed attempts are preserved, not generalized into design rejection: an
unsupported long Symbol literal; my bootstrap condition edit failing to apply;
a resolver missing synthetic tries; native typed-callee declaration drift;
and the parser's final descriptor reconstruction dropping its open flag.
The successful intermediate sequence uses the older phase4 compiler to build
new parser/owners with a temporary runtime open policy on the named proof
shape, then that binary compiles the true open definition. This is disposable
bootstrap scaffolding, not a production convention or checked-in refresh.
Diagnostic-only instrumentation of generated C was used to inspect one body
and an absent preparation map; the final clean build regenerates that C and
contains no instrumentation.

The narrowed client semantics can now be frozen. General open value/Type/tag
role preparation, later-declaration visibility, recognition of computed slots,
full helper transport and arbitrary producer composition remain unproved;
these limits neither change the client forms nor justify a parallel validator.
Native String emission still has baseline caller-local shadow limitations.

## Alternatives and recommendation

| Alternative | Strength | Cost or limit | Decision |
| --- | --- | --- | --- |
| Shared Macro body/role table, ordinary AST, meta producers and caller effects | Same forms construct and recognize; ordinary compiler owns semantics; clients hide IR detail | Needs common stage/effect adapter; inserted-name hygiene is a follow-up | Recommended; prove integration before src/ migration |
| All runtime callees/declarations supplied as typed holes | Actual byte-identical try control; avoids unresolved native signatures | Makes compiler source carry plumbing and does not establish open templates | Keep as baseline/control, not final surface |
| Rebind the fully substituted tree | Reuses binder without explicit hole boundary | Reinterprets lowered returns and typed holes; can change scope/type/conversion behavior | Reject this implementation; preserve ordinary binding only for skeleton |
| Canonical raw builders everywhere | Works today, direct construction cost | Exposes IR fields and repeats construction/recognition logic across clients | Confine to meta producers; retain ordinary canonical contract |
| Separate pattern DSL or semantic validator | Could independently specify recognition | Duplicates Macro structure and ordinary binding/type ownership; adds a public model | Reject; share Macro preparation and existing Match |

## Remaining decisions and limits of this spike

The freeze includes the four forms, the explicit `open` modifier, common
slot-call result semantics, producer-attached `source`/`bound`/`lowered` stages
and the producer table below. Generated-header native references retain String
callees and producer-declared result Types; general free-role extraction is
required before any lowering other than try migrates. The stage marks belong
to producer/application values;
compiler lowering clients do not inspect them. Producers are implemented by
the migration first needing them, not as an up-front family. In particular:

* Compiler-inserted value shadowing is reproduced baseline behavior and is a
  follow-up, not a blocking integration question. Parse-time preparation now
  covers the three native roles; general hygienic emission remains a follow-up.
  Per-unit scope retention is dropped.
  The primitive cast Type shadow control passes; broader roles remain thin.
* The narrowed compiled-in try path with parsed meta slots, three effects and
  stage carriers passes its transaction probe and 62-case comparison. The client
  now has no wrapper calls; generic producer dispatch still uses private scaffolding.
  Parent conversion counts across broader categories and diagnostic attribution
  outside this bounded fixture remain thin.
* Mixed Name role projection works through a private constraint adapter; its
  automatic public Macro-case integration is not demonstrated. Expr sequences
  work through retained/expanded cases; broader category combinations are thin.
* The grammar appendix records field layouts and an observed literal-head
  census. It is not a mechanically complete census of dynamic/string heads or
  every protocol/Type subrecord. Missing layouts must be resolved at existing
  producer/consumer owners before their migration, not with a new validator.
* Meta computation is not generally reversible. On recognition, a computed
  slot whose inputs are already supplied can produce its structural subpattern;
  a computation depending on an unknown capture cannot run backward. Such a
  producer needs a pure structural Macro shape with capture outputs, or the
  rule first matches source structure and computes afterward. Effects from
  speculative recognition are never applied. The general computed-slot
  recognition adapter remains unprototyped.
* Transaction coverage for cache writes, imports/native actions, parser token
  movement and diagnostic output is not established. Producers on this path
  must use prepared inputs or existing rollback-capable owners. A failed
  expansion may report its diagnostic; it must not publish generated code or
  compiler mutations. Helper transport and REPL isolation stay separate.

These are bounded integration limits, not evidence against the frozen forms.
Both phase5 contract gaps now have executable evidence; general feature
coverage is not claimed. No full self-host comparison of the combined path was
run. This work changes research records and isolated prototypes, not production
consumers or bootstrap outputs.

## First independent production change: shared capture roles

Independent production work is authorized separately and can proceed now on
its own branch under the ordinary dev rules. It does not depend on phase5.
It is scoped here and is not implemented by this research prototype.
`src/macros.x:_capture_pattern` and `_capture_row` share the current capture
projection schema; `_forwarded_capture` and `_forwarded_prefix_list` consume
that same policy. A compact private static role table owns projection names,
scalar/sequence cardinality and storage location. Keep the two direction-specific
entry points thin, with ordinary explicit Function, Unit and Name branches.
Delete duplicated key/row assembly, not their different responsibilities.

Preserve exact canonical rows: scalar source/value/expression/splice order;
sequence source/value rows with expression/splice aliased from value by `!and`;
Function return/declarator virtual subfields; Unit construction suffix and its
current activation condition; Name member labels as separate direct projection.
Reuse `_replacement_binder`, source unwrap/capture, Match, List replacement and
ordinary freshening. Do not change inference, Type capture semantics, source
access authority or member/binding correlation in this refactor.

Existing macro-argument-kinds, sequence/source-forwarding, Function decorator,
Unit-obligation, Name member/hygiene and meta-template fixtures cover its owners.
Use exact canonical row/pattern and generated-C comparison on current inputs,
then the ordinary existing production gate. This needs no language-transition
bootstrap stage: the schema uses existing static constructs. Normal generated
bootstrap publication still follows existing rules when implementation is
separately authorized. No new gate or recurring test target is proposed.
Details and source consumers are in
`.context/dual-macro-phase4/capture-scope.md`. Open resolution, slot stages and
transaction effects are not prerequisites; subsequent migrations reuse this
owner instead of delaying it behind their proof work.

## Rewrite and bootstrap order

1. Consolidate `_capture_pattern` and `_capture_row` behind one shared role
   table as the first independent production change, on a separate branch.
   It does not depend on open names, stage envelopes or effect integration.
   Preserve current capture/forwarding semantics, then use the ordinary source
   review, gate and dev delivery rules in its later authorized implementation.
   This research branch only scopes it; no production change is made here.
   After that consolidation, establish runtime Macro application/recognition
   behind the frozen forms and common result adapter. Reuse the role table;
   do not keep the phase-3 callbacks as parallel permanent implementations.
2. Produce an intermediate compiler that parses the forms and their modifier
   while src/ still uses the old builders. Only after that compiler is available
   can src/ consume the new forms. Separate anonymous capture/registration
   handling and retain existing named meta computations.
3. Complete slot-result aggregation, stage consumption and the existing
   transaction extension first, including rollback/read-your-writes probes.
   Prove try/defer/catch with actual meta slot calls on isolated copies first. Preserve `_region_binding`,
   region effects and include/declaration order; replace fixed output shapes.
   Compare all fixture C/H bytes and diagnostic/negative results, then the
   self-host C comparison. Measure the same candidate before claiming cost.
4. Migrate wrapper functions, protocol helper skeletons and scope-cell shapes
   using existing Param/Type/Name holes; retain allocation, memoization and
   `add_early`. Compare self-host C at this step too.
5. Migrate the Func call construct/recognize pair after combined sequence and
   role constraints are proved for its actual canonical inputs. Retain resolved
   type dispatch and conversions. Compare self-host C.
6. Migrate lambda source recognizers after capture-layout stage projection and
   origins are proved; confine lowered closure IR builds to their meta producers. Compare self-host C.
7. Review the complete authored diff for duplicate projection, substitution,
   traversal and stage machinery, fix it, then use ordinary existing delivery
   validation only when production implementation/publication is authorized.

This requests no bootstrap work now. During a later authorized implementation,
the intermediate compiler, generated bootstrap and first consumer source must
be sequenced so the checked-in compiler never has to parse unsupported forms.
The requested per-step self-host comparison is the compatibility proof; this
plan adds no recurring gate or validation target.

## Canonical grammar appendix

This is a descriptive grammar of the existing canonical List contract, not a
new language or validator. `S(x)` marks a field supplied by source syntax;
`D(x)` marks a compiler-derived field. `SD(x)` means the same positional field
holds a source name before resolution and a derived representation afterward.
A sequence marker applies its classification to every element. Head tags are
fixed discriminants and have no source/derived field. Children retain their
own field classifications recursively. `()` means absence, not a new node.
Types remain ordinary Lists in their existing grammar; nonterminals below
name compiler roles, not new runtime representations.

`S(Node)` does not imply that every annotation within Node was source-written;
it means the child occurrence corresponds to an ordinary source operand/body.
`D(Node)` denotes synthesized scaffolding as a whole. A production may be
reachable only through `%()` construction or an internal producer and still
be canonical. Exact validity remains the ordinary owner operation's decision.

### Root, origins and identities (ast.x:9-65; parse.x:2470-2490)

```
AstSequence ::= S(Node)*                         // outer List, no tag
Node ::= SourceNode | ExpansionNode | LoweredNode | OriginNode
OriginNode ::= (at D(OriginID|m-origin) SD(Node))
             | (src D(SourceRecord) S(Node))
             | (api-source D(Line) D(Doc) S(Node))
SourceRecord ::= (source D(File) D(BeginOffset) D(EndOffset))
OriginRecord ::= (source D(File) D(Line) D(Column) D(Length) D(Offset))
Binding ::= (binding D(PositiveID) S(NameLabel))
Name ::= S(String) | (S(String)) | Binding
       | "x2c.ident"-node | SD(TemplateNameSlot)
MethodName ::= ((S(Owner)) S(Member))
"x2c.ident"-node ::= ("x2c.ident" S(NameLabel))
```

The emitted binding name can become generated: the binding producer then supplies
D(NameLabel), retaining original S labels in existing compiler facts. PositiveID
is never a source name or positional binder index. SourceRecord
fields exist for exact complete captures; new Lists do not acquire source text.

### Expressions (expressions.x:2039-2440; literals.x:1205-1254)

```
Expression ::= (expr D(SemanticType|()|<macro-expr>) S(Content))
             | (expr D(SemanticType) D(LoweredContent))
Content ::= (ident SD(Name))
          | (literal D(LiteralType) S(LiteralText))
          | (literal D(LiteralType) S(LiteralText) D(AtomOrSymbolValue))
          | (op S(UnaryOperator) S(Expression))
          | (op S(BinaryOperator) S(Expression) S(Expression))
          | (op S(?Operator) S(Condition) S(OnTrue) S(OnFalse))
          | (op S(.|->) S(Expression) S(MemberName))
          | (postfix S(++|--) S(Expression))
          | (call S(CalleeExpression|RawCalleeName) S(Arguments))
          | (index S(Expression) S(Expression))
          | (getindex S(Expression) S(Expression))
          | (slice S(Expression) S(Expression|())
                   S(Expression|()) S(Expression|()))
          | (parens S(Expression|Declaration|Block))
          | (sizeof S(Expression|Declaration|RawTokenSequence))
          | (offsetof S(TypeSyntax) S(MemberName))
          | (cast S(Declaration) S(Expression))
          | (cast D(SemanticType) S(Expression))
          | (generic S(Expression) S(Association)*)
          | (va-arg S(Expression) S(Declaration))
          | (commas S(Expression)*)
          | (array S(Expression)*)
          | (map S(MapEntry)*)
          | (map-entry S(Expression) S(Expression))
          | (composite S(InitializerItems))
          | (dotinit S(MemberName) S(Initializer))
          | (indexinit S(Expression) S(Initializer))
          | (segments S(Segment)*)
          | (splice S(Expression))
          | (dstrasgn S(Targets) S(Expression))
          | (is-type S(Expression) S(TypeSyntax))
          | (is-symbol S(Expression) S(Expression))
          | (type-tag S(TypeSyntax))
          | (lambda S(Parameters) S(Expression|Block))
          | (lambda S(Parameters) D(LambdaCaptures) S(Expression|Block))
          | (tadapt S(TargetExpression) S(SourceExpression))
Arguments ::= (args S(Expression|MacroSlot)*)
MemberName ::= (S(NameLabel|TemplateMemberSlot))
Association ::= (association S(TypeSyntax|default) S(Expression))
Initializer ::= Expression | Content
InitializerItems ::= (commas S(Initializer)*)
Targets ::= (targets S(Expression|Name)*)
Segment ::= (segvar S(Expression)) | (segexp S(Expression))
          | D(CacheReference) | S(RawText)
LambdaCaptures ::= (captures D(LambdaCapture)*)
LambdaCapture ::= (capture D(Binding) D(CapturedType) S(CapturedExpression))
```

Lambda captures may be explicitly prescribed reference captures in source;
in that case `CapturedExpression` is the source binding expression with a
compiler-generated address operation and CapturedType reflects reference mode
(literals.x:1120-1140). Raw constructor producers can supply canonical capture
rows and ordinary binder preserves that mode (literals.x:1020-1044).

The `op` tag covers source punctuation and x2c operators selected by the
operator parser, not just C arithmetic. MemberName is a name slot even
when the receiver contains a bound program identifier. It is not Binding.
Source LiteralType is inferred from text/suffix and must not automatically be
ignored by every semantic comparison. Generated literals can have D text.

### Declarations, type syntax and declarators (parse.x:220-585, 850-1080,
### 2180-2340, 2601-2735; type.x:149-154, 848-878)

```
Declaration ::= (declare S(BaseTypeSyntax) S(Bindings))
              | (typedef S(BaseTypeSyntax) S(Bindings))
              | (decl S(BaseTypeSyntax) S(Bindings))
              | (dstrdecl S(BaseTypeSyntax) S(NameTargets) S(Expression))
              | (dstrdecl S(Parameters) S(Expression))
              | (function S(ResultBase) S(Declarator) S(Block))
              | (falias S(Declaration) SD(Binding))
              | (named-type S(NameLabel) S(TypeSyntax|()))
Bindings ::= (bindings S(DeclaratorOrInitializer)*)
DeclaratorOrInitializer ::= Declarator | (op S(=) S(Declarator) S(Expression))
Declarator ::= (bind SD(Name|MethodName|()) S(Modifiers))
Modifiers ::= S(Modifier)*
Modifier ::= S(*|&|opt-ref|Qualifier)
           | (dim S(Expression)?)
           | (bitfield S(Expression))
           | (fnmod S(Parameters))
           | (fnmod S(Parameters) S(Modifiers))
           | (S(AttributeText))
Parameters ::= (params S(Parameter)*)
Parameter ::= (param S(BaseTypeSyntax) S(Declarator)) | (...)
NameTargets ::= (targets SD(Name)*)
TypeSyntax ::= S(TypeComponent)*
TypeComponent ::= S(TypeKeyword|Qualifier|StorageClass|TypeNameLabel)
                | Modifier | Aggregate | Enum
                | SD(TemplateTypeSlot)
Aggregate ::= (struct S(TagName) S(Fields)?)
            | (union S(TagName) S(Fields)?)
            | (struct S(Fields)) | (union S(Fields))
Fields ::= (fields S(Declaration)*)
Enum ::= (enum S(TagName) S(EnumeratorList)?)
EnumeratorList ::= S(Enumerator)*
Enumerator ::= SD(Name) | Declarator
             | (op S(=) SD(Name|Declarator) S(Expression))
TagName ::= S(Name|()) | (gensym D(Role) D(GeneratedName))
SemanticType ::= D(CanonicalModifier)* D(BaseSemanticTypeComponent)*
CanonicalModifier ::= Modifier | (func D(SemanticTypeList))
SemanticTypeList ::= D(SemanticType)*
```

`BaseTypeSyntax` is a List of components, not `(type ...)`. SemanticType shares
the same underlying ordinary List grammar; canonicalization maps source fnmod
parameter AST to func semantic parameter Types. Existing base keywords and
qualifiers are leaf Symbols (void, numeric keywords, struct/union/enum storage,
const/volatile/restrict, static/extern/inline/threaded/meta etc.), not one new
production each. `opt-ref` and reference modes are existing Type grammar, not
new public syntax-template categories. `Type.declaration_parts` and parameter_ast
own the inverse presentation; do not reconstruct modifiers independently.

Unnamed params and array dims have empty Name/Expression fields. C `(void)` is
an explicit param `(param (void) (bind () ()))`; `(params)` must not be assumed
semantically equivalent without the ordinary parameter owner. Member fields,
bitfields, tags and enumerators bind in their existing compiler contexts.

### Statements (statements.x:125-240,330-429,462-490; parse.x:2744-2913)

```
Statement ::= (stmnt S(Expression)) | (empty)
            | (block S(Node)*) | (group S(Node)*) | (seq S(Node)*)
            | (return) | (return D(ReturnContextType) S(Expression))
            | (return S(Expression))                 // transformed
            | (if S(Expression) S(Statement))
            | (if S(Expression) S(Statement) S(Statement))
            | (while S(Expression) S(Statement))
            | (do S(Statement) S(Expression))
            | (for S(Declaration|Expression|()) S(Expression|())
                   S(Expression|()) S(Statement))
            | (switch S(Expression) S(Statement))
            | (case S(Expression)) | (default)
            | (break) | (continue)
            | (goto S(Name)) | (label S(Name))
            | (defer S(Statement))
            | (raise S(Expression) S(Arguments))
            | (try S(Statement) S(Catches|()) S(Statement|()))
            | (match S(Expression) S(CaseRows))
Catches ::= (catchcases S(CatchRows) D(HandlerBinding))
CatchRows ::= S((S(PatternExpression) S(Statement))) *
CaseRows ::= S((S(PatternExpression) S(Statement|GuardedBody))) *
           | S(PreprocessorNode) *                    // interleaved
GuardedBody ::= (guarded D(GuardExpandedStatement))
GuardExpandedStatement ::= (if S(GuardExpression) D(Block))
```

Catch bodies receive generated binder declarations; Match typed captures
receive generated temporaries/declarations. The source pattern and source
body remain distinct fields. Patterns are ordinary Match data expressions,
not a new AST syntax-variable language. Guarded marks control flow after
source guard rewriting and must not be dropped in a lowered-stage match.

#### Complete match-row hole (capability implemented; adoption pending)

`match-arm-directive` has a guarded `case %(big ?n) if (...)` between ordinary
arms, with `#ifdef`/`#else` rows and conditional defaults. Today
`statements.x::_match_case` makes `(PATTERN BODY)`, changes a guard into
`(guarded (if GUARD (block BODY (break))))`, and may wrap the body in typed
capture declarations. `_match_cases` inserts `(preproc TEXT)` rows in their
token order and tracks defaults across directive branches. Later,
`parse.x::bind_syntax` recognizes the raw `(match SUBJECT CASES)` shape and
walks those rows to resolve patterns, open arm scopes, and bind bodies:

```x2c
case %(match ?subject ?cases): {
  if (!statement_position) goto construction_error;
  Array bound = [];
  foreach (List row, cases.list()) {
    if (row.car() == <preproc>) {
      bound.push(row);
      continue;
    }
    List pattern = row.car();
    int binds = pattern !== %(*);
    if (binds) pattern = _.resolve_expression(pattern, _.token);
    _.begin_match_arm(pattern, _.token, binds);
    {
      defer _.sym.pop_scope();
      List body = row.cadr();
      match (body) {
        case %(guarded ?statements):
          body = %(guarded ${_.bind_syntax(
            statements, AST_STATEMENT, _.return_type)});
        default:
          body = _.bind_syntax(body, AST_STATEMENT, _.return_type);
      }
      bound.push(%($pattern $body));
    }
  }
  return %(match ${_.resolve_expression(subject, _.token)}
                 ${bound.list_free()});
}
```

The `MatchRow` argument kind has sequence spelling
`MatchRow $rows...`. Its sole template slot is a match arm list:

```x2c
macro Statement $matched(Expr $subject, MatchRow $rows...) {
  match ($subject) { $rows... }
}

Macro shape = $matched;
match (input) case shape(?subject, *rows): {
  // Keep the existing pattern resolution, arm scopes, guarded-body binding,
  // and subject resolution, using rows in place of cases.list().
}
```

The sequence captures each complete canonical row without splitting its
pattern, guard, binder declarations, or body: either `(PATTERN BODY)` or
`(preproc TEXT)`. A default is `(* BODY)`, not a different hole kind. The
matched rows retain order, binding identities, source positions, and their
current parser/binder stage. The hole neither reconstructs source guard text
from `guarded` nor rebinds a row during recognition. Construction still uses
ordinary `bind_syntax` once. In a template, its splice occupies
the whole `match { ... }` row list; it cannot appear as an expression or a
standalone statement. This is analogous to `Catch $arms...`, but cannot reuse
`Catch`: match rows include directives and have different binder and guard
semantics. A fixed guarded arm is already expressible, as `$typed_arm` in
`match-typed-guards` demonstrates; that does not capture arbitrary rows.

Ownership: `statements.x` parses source arms, typed captures, guards,
directives, and conditional-default diagnostics. `macros.x` registers the
kind, accepts its sequence argument and template slot, and projects complete
rows for structural recognition and unchanged construction. `parse.x` keeps
the existing `bind_syntax` arm loop and scope behavior; adopting the shared
grammar macro for its outer raw match recognition remains separate.
`transform.x` still derives match binder records, and `emit.x` still
uses `guarded` to choose retry/fallthrough emission. Constructed canonical
AST Lists remain accepted by structure, as the language reference promises.

Capability proof: an inert probe beside the fixtures captured all six
directive-rich rows and both typed guarded/default rows. `List.compare`
matched the original rows and a pending template call, and ordinary expansion
ran both guarded forms; its output was `6 2 4 9 9 9`. The existing
`match-arm-directive` and `match-typed-guards` fixtures passed. Their transform
dumps matched the pre-edit compiler byte for byte; the former's checked C
sidecar and the latter's C/H against the unchanged bootstrap compiler also
matched. Both fixture diagnostics were empty. No recurring fixture was added.
Before binder adoption, repeat exact row and binding comparison in that
client, and stop if it needs reconstruction, a second binder, or fallback
recognition.

Design review: a `Statement` body hole loses the arm pattern and guard, while
an `Expr` pattern plus fixed body can cover only a fixed arm layout. One
opaque row sequence uses the existing parse/bind owners and avoids parallel
semantics. Its cost is a new grammar slot and capture kind, so adopt it only
if the focused proof shows exact projection across guarded and interleaved
rows. Gary approved the capability; binder adoption remains a separate step.

### Compile-time source items (parse.x:1760-1775,2717-2735;
### protocol.x:150-154, 525-558,2350-2567; macros.x:3370-3390)

```
PreprocessorNode ::= (preproc S(Text))
Import ::= (import S(PackageName) S(Alias|()))
CAssertion ::= (c-assert) | (c-assert S(Expression) S(Expression))
Protocol ::= (protocol S(ProtocolRecord) SD(StorageMode) D(Location))
ProtocolRecord ::= ("protocol-record" S(BaseType) S(ParticipantBinder)
                    S(AssociatedTypes) S(ProtocolMembers))
AssociatedTypes ::= (associated S((S(Name) SD(TypeSyntax))) *)
ProtocolMembers ::= (members S((S(Name) D(SignatureType) S(NativeName|()))) *)
Adoption ::= (adopt S(BaseType) S(ParticipantType) SD(StorageMode) D(Location))
           | (adopt S(BaseType) S(ParticipantType) SD(StorageMode)
                    S(RepresentationType) D(Location))
           | (adopt S(BaseType) S(ParticipantType) SD(StorageMode)
                    S(TagExpression) D(Location))
TagExpression ::= (tag S(Expression))
MetaProtocol ::= (meta-protocol S(Adoption))
               | (meta-protocol S(BaseType) S(ParticipantType)) // retained
MacroDefinition ::= (macrodef S((name S(Atom))) S((kind S(ResultKind)))
 S((target S(TargetKind|()))) S((targetp S(HoleDescriptor|())))
 S((parameters S(HoleDescriptorList))) D((fresh D(FreshRows)))
 D((captures D(BindingList))) D((pattern D(MatchPattern)))
 S((template S(Node|()))) D((origin D(Location))) D((file D(Path)))
 D((imported D(Bool))) D((builtin D(Bool))) S((local S(Bool))))
HoleDescriptor ::= (macro-param S((binder S(Atom))) S((kind S(HoleKind)))
                    S((sequence S(Bool))))
FreshRows ::= D((D(PlaceholderBinding|Atom) S(SourceLabel) D(LispFlag))) *
```

MacroDefinition assoc rows are the current complete descriptor, not a newly
invented opaque template AST. Hole inference can derive kind/sequence facts
from source slot use; those fields are then D in the recorded descriptor even
though explicitly authored kinds/sequence markers are S. Pattern is the current
construction-capture projection pattern, not the proposed recognition projection.

### Pending expansion and declaration production
### (macros.x:2490-2510,2838-2869,2965-3029,3971-3985,4160-4269;
### parse.x:2470-2557,2675-2716)

```
ExpansionNode ::= (macro-invoke SD(StoredDefinition) D(InvocationInput) D(Site))
                | (macro-slot S(SpliceFlag) S(MetaExpression|LispText)
                              D(ConstructionState)*)
                | (macro-bind D(ProjectionAtom))
                | (meta-call S(CalleeExpression) S(Arguments))
                | (meta-cap D(ProjectionAtom))
                | (tpl-call SD(StoredDefinition|CalleeExpression) S(Arguments))
                | (local-macro S(Atom))
InvocationInput ::= (args D(MacroCapture)*)
                  | (target D(Arguments) S(MacroCapture))
MacroCapture ::= (capture S((source S(Node)*)) D((value D(Value)*))
                   D((expression D(Expression)))? D((splice D(List)*))?
                   D(ConstructionState)*)
StoredDefinition ::= MacroDefinition | S(Atom) | D(QuotedDescriptor)
Site ::= D(Token|m-invoke)
DeclarationProduction ::= (declaration-bundle D(Rows))
 | (syntax-recipe S(Callback) S(Arguments))
 | (declaration-recipe S(Callback) S(Arguments))
 | (declaration-pending S(Callback) S(Arguments) D(FrozenMacroStack)
                        D(PrivateMode))
 | (default-forward S(Child) S(Parent) S(Member) S(Fallback)*)
 | (declaration-forward S(Child) S(Parent) S(Member) D(FallbackList)
                        D(PrivateMode))
 | (default S(Function))
 | (declaration-default S(Function) D(FrozenMacroStack) D(PrivateMode))
 | (declaration-function D(Declaration) S(Body) D(FrozenMacroStack))
Rows ::= (rows SD(Node)*)
```

ConstructionState and FrozenMacroStack are existing administrative data,
not program AST grammar or user syntax to invert. They preserve lifetime,
source-order and capture context. Arbitrary LispText/callback computation is
not structurally invertible. See source owner for positional construction
rows that travel beside source/value rather than inventing a semantic validator.

### Lowered and emission productions (transform.x:165-255,1836,2037-2057,
### 3076-3088,3528-3551,3755-3818; cache.x:265,451-468; emit.x:1024-1200)

```
LoweredContent ::= (cache D(CacheID))
 | (var D(Expression)) | (nil)
 | (string SD(String|Expression))
 | (cons SD(Expression) SD(Expression))
 | (append SD(Expression) SD(Expression))
 | (varray D(Expression)*) | (vmap D(VarPair)*)
 | (tadapt D(OriginID) S(Expression))
 | (managed-init S(Expression))
 | (initval D(InitializerInput)? D(InitializerChoice)*)
VarPair ::= (vpair D(Expression) D(Expression))
InitializerInput ::= (input D((D(Placeholder) S(Expression))) *)
InitializerChoice ::= (D(Expression|()) D(SelectorPath)
                       D(DestinationType) S(Expression))
SelectorPath ::= D(Selector)*
Selector ::= (dotinit S(MemberName)) | (indexinit S(Expression))
LoweredNode ::= (localinit S(Declaration) S(Block))
 | (sourceinit D(Function))
 | (initcode D(InitializerInput) D(Block))
 | (matchcases S(Expression) D(LoweredCaseRows))
 | (defer S(Statement) D(EnvironmentBinding) D(CallbackBinding)
           D(CaptureRecords) D(WrittenBindings))
LoweredCaseRows ::= D((D(LogicalBinderList) S(PatternExpression)
                       S(Statement|GuardedBody))) *
EmissionDecoration ::= (comment SD(Text)) | (space D(Text))
SourceMapTokenStream ::= src-at D(OriginID) D(EmittedTokens)*
                         src-at D(PreviousOriginID)
```

`src-at` is emitted token/source-map output, not accepted source AST input.
`comment` and `space` are emitted/presentation fragments. Compiler-generated
calls can have raw C callee String and declarations can contain raw attribute
text; these use existing emitter fallback rather than a new AST head enum.
The grammar contract is intentionally open to ordinary canonical C token
leaves in generated forms. There cannot be a finite “every accepted List”
validator grammar consistent with the current generic emitter fallback.

### Census coverage and exclusions

The companion head census records 215 literal `%(` head names in
ast/parse/expressions/statements/literals/type/transform/emit/cache/macros/
generate/protocol. It is a *miss detection aid*: it includes Match patterns,
semantic maps and diagnostics, misses dynamic `$tag` heads and String heads,
and is not automatically a grammar. The rows above explicitly include dynamic
op/member/aggregate/type forms and protocol-record/x2c.ident String heads.
The census classification distinguishes AST families, Type leaf names,
presentation output and registry/diagnostic metadata. `fadapt`, `findirect`,
`fhandle`, `fgetter`, `fpointer-factory`, `iadapt` are adapter memo keys, not
AST expression productions (`transform.x:511,645,659,716,796`;
expressions.x:3791). `indirect-adapter` is a helper result record
(transform.x:639), `field/method/delegate/step/ambiguous` are member resolution
results (expressions.x:454-480,1862-1889), `func-arg` is extraction data from
_func_call_arguments, not an emitted program node (expressions.x:1733).
`unit/module` are dump-definitions records, `native` is a generated-reference
set key and `attributes` is a binding-fact key (generate.x:629,840-844,895).
`with`/`with-name` are macro-like substitution facts, not AST nodes
(statements.x:604-617). Other metadata rows are listed in census with references.

The table does not claim a mechanically proven closed grammar for every
Lisp/metadata List that happens to travel through the compiler. Source
positions/types are context-sensitive, and source/native crossing operations
remain authoritative. Consolidating this inventory into the one specification
should retain these distinctions rather than claim an invented complete
semantic validator.

### Named meta producers for internal productions

This is a migration inventory, not an up-front implementation requirement.
The migration first using a production implements its producer. For the first
try proof only frame-declaration and cleanup-placement producers are required;
all other entries remain deferred until demanded.


Each function receives ordinary supplied code/data arguments. Stage marks and
effects are conveyed by the common private result adapter; client source never
opens that envelope. `%()` appears only inside the named producer (or its
private structural helper), not at lowering call sites.

| Canonical production | Proposed producer and argument facts | Current authoritative owner / client use |
| --- | --- | --- |
| frame declaration | `_frame_declaration(frame, frame_type)`; issued Name and prepared target Type; returns canonical declaration code with stage | First try proof. Existing `_value_declaration` semantics; no new declaration binder. |
| placed cleanup | `_place_cleanup(cleanup, placement_facts)`; already lowered cleanup and existing region/exit decision; returns cleanup effect/reference | First try proof. Existing region driver remains placement owner; no inferred ancestry or new control-flow analysis. |
| cache constant graph reference | `_constant_syntax(value)`; receives immutable value, returns code plus intern-constant effect instead of inventing process-local ID | compiler.x:2248-2326; stage.x:119-136. Template slot calls it for constant data. Compiler applies interning and supplies the cache reference. |
| localinit declaration/body | `_local_static_region(declaration, body)`; already bound declaration and remainder body, lower-stage result | transform.x:2037-2057,1836; emitter local-static. Static planner passes both; template contains only slot call. |
| sourceinit helper function | `_source_initializer(function, order)`; function syntax plus caller-supplied initializer order/dependency facts | cache.x:451-468; emit.x:1060. File-initializer producer owns wrapper and effect scheduling. |
| guarded Match case body | `_guarded_match_arm(condition, body, capture_plan)`; returns arm control shape with guard retry/fallthrough intent | statements.x:368-373; parse.x:2877; emit.x:586. Existing `case ... if (...)` source template can generate it directly; compiler migration never spells guarded. |
| resolved tadapt origin/source | `_typed_callback_adapter(target_type, source, adapter_facts, site)`; compiler supplies resolved target/source facts and memo lookup/allocation plan | expressions.x:2420-2437, transform.x:165-264. Existing `$adapt` can remain source route; producer owns resolved marker/helper effects, not a second adaptation validator. |
| matchcases subject/derived binder rows | `_lower_match_cases(subject, arms, capture_layouts)`; compiler passes existing MatchCaptureLayout-derived facts | transform.x:3076-3088. Client uses ordinary match template or slot producer; producer owns derived rows. |
| varray converted elements | `_var_array_literal(elements)`; receives already converted Var expressions | transform.x:3528-3535. Conversion facts supplied by ordinary owner before meta; producer emits lowered literal node. |
| vmap/vpair converted pairs | `_var_map_literal(pairs)`; ordered already converted key/value expressions | transform.x:3538-3551. Same, single producer owns vpair child rows too. |
| initval input/alternatives tables | `_initializer_alternatives(inputs, alternatives)`; compiler supplies destination types, selector paths, native condition facts and converted values | expressions.x:3922-4003, ast.x:241-249. Meta producer builds exact alternative table without repeating conversion/type rules. |
| initcode input/body | `_initializer_code(inputs, body)`; previously computed input placeholders and initialization statements | cache.x:265, emit.x:1057. Producer owns emission-macro representation. |
| managed-init value marker | `_managed_initializer(value, ownership_facts)`; caller supplies current ownership/placement decision | expressions.x:2059-2062, parse.x:2593, transform.x:4125. Existing source ownership macros remain source surface. |
| lowered callable defer with env/callback/capture records | `_callable_cleanup_region(body, capture_plan, cleanup)`; compiler passes written/reference mode/type facts; result effects allocate/register environment and helper in stable order | transform.x:3755-3818. Client unary defer template plus slot call; producer owns capture record layout. |
| var boxing / cons / append / string / nil cache graph internals | `_literal_value(value, conversion_facts)` shared with `_constant_syntax`; no new producer per cons cell unless ordinary owner requires it | compiler.x:2275-2326, transform.x:4250-4253. Ordinary source literals/List operations are preferred client forms. Raw graph construction stays inside literal producer. |
| at/src/api-source wrapping | `_located_code(code, site)` and `_captured_source(code, capture_facts)`; precise complete-source facts only when supplied by compiler | parse.x:2477-2489,2738, macros.x:3778-3820. Common producer/result adapter attaches ancestry; templates never author origin IDs. |
| pending template invocation / macro-slot / meta-call captures | `_template_slot_result(value, stage)` common internal adapter; generated by four forms and meta slot calls, not an explicit client operation | macros.x:2490-2510,2965-3029,3971-3985,4160-4269. Compiler source never opens records; source syntax selects operations. |
| declaration bundle/recipe/pending/forward/default/function | `_declaration_result(code, production_facts)` common declaration producer; separate private `_default_forwarder(child,parent,member,fallback)` when semantic owner needs it | parse.x:2505-2557,2675-2716. Compiler client uses ordinary Declaration/NamedType source templates or meta producer calls; once-only production facts remain ordinary owner data. |
| comment/space/src-at emission decorations | `_emission_origin(site)` and existing formatter/emission operations; not syntax-template transforms | emit.x:1024-1030, generate.x:1150. If refactored, producers alone build token decorations; no invented source keyword. |
| generated C helper function, static record, guard, forward tag | named source templates `_callback_function`, `_func_adapter_function`, `_protocol_guard`, `_file_initializer`; producer fills type/name/value slots and returns registration effects | transform.x:139-162,434-505; generate.x:124,254; protocol.x helper synthesis. These **do** have source grammar and need no lowered AST producer head. Source templates replace their raw function/declaration skeletons. |

This includes administrative shapes for completeness, while distinguishing them
from strictly lowered-only nodes. `tadapt` and `guarded` are not entirely
lowered-only: existing source operations already produce their resolved forms.
The corrected field grammar documents both stages. Metadata such as adapter
memo keys, semantic binding facts and protocol conformance maps is not program
AST and need not receive public syntax-template forms. Meta producers can
construct their effect/argument data privately.


### Classification and comparison policy for internal productions


| Production | Existing producer / consumer | Recommendation |
| --- | --- | --- |
| `(cache ID)` | compiler.x:2248-2254, 2275-2326; stage.x:119-136; emit.x:1082. ID indexes compiler-owned constant graph, not syntax binding. | Meta producer only; clients call its slot function. Public source literal template already covers value creation. Matching requires owner cache context or projecting its actual constant, never comparing unrelated cache IDs as code identity. |
| `(localinit DECLARATION BODY)` | transform.x:2037-2057 inserts runtime static initialization region; emitter dispatch emit.x:1059. | Meta producer only for lowered stage. Source `static T name = value;` and block template owns public behavior; no new region keyword. Must not simply erase wrapper because entry/jump semantics matter. |
| `(sourceinit FUNCTION)` | cache.x:451-468 generates file-static initialization helper; emit.x:1060-1061. | Meta producer only. Source file-static declaration remains user surface. It has source-placement/order semantics; recognition cannot treat generated helper as the original declaration without an explicit inverse/owner projection. |
| `(guarded BODY)` in a Match case | statements.x:368-373 inserts guard-dependent break marker; parse.x:2877-2881; emit.x:586 removes marker to choose arm flow. | Meta-producer-only raw form for exact case-control IR; public `case PATTERN if (condition):` already exists. Source template should use guard syntax, not new guarded keyword. Do not erase in lowered recognition: fallthrough/retry distinction matters. |
| `(tadapt TARGET SOURCE)` -> `(expr TARGET (tadapt ORIGIN SOURCE))` | etc/builtin-macros.xmacro:12 constructs `$adapt`; expressions.x:2420-2437 resolves; transform.x:165-255 emits typed helper. | Not wholly lowered-only: use existing `$adapt` public macro for source construction/recognition; use a private meta producer for resolved origin/helper details. Definition/invocation stages must be explicit. No duplicate adapter syntax or validator. |
| `(matchcases SUBJECT (BINDERS PATTERN BODY)...)` | transform.x:3076-3088; emit.x:1237. | Meta-producer-only lowered form; public `match` source form owns code. Derived BINDERS should come from existing MatchCaptureLayout, never a second capture analyzer. |
| `(varray ...)`, `(vmap (vpair ...)...)` | transform.x:3528-3551 lowers array/map elements to Var; emit.x:1033-1041. | Meta-producer-only lowered form; public []/{} literal grammar. These are not source-preserving aliases if conversion calls or ordering changed. |
| `(initval [input ...] (CONDITION PATH DESTINATION EXPRESSION)...)`, initcode | expressions.x:3922-4003 produces initializer alternatives; ast.x:241-249; cache.x:265; emit.x:759-764, 1057-1062. | Meta-producer-only raw form for alternative tables/emission macros. Public source expressions/initializers remain templates; exact derived initializer decisions require compiler context. Do not invent a new public conditional-init grammar. |
| `(managed-init INITIALIZER)` | expressions.x:2059-2062; parse.x:2593-2597; transform.x:4125. | Meta-producer-only marker; source initialization/ownership constructs continue through ordinary owners. Not a freely ignorable grouping. |
| lowered `(defer BODY ENV CALLBACK RECORDS WRITTEN)` | transform.x:3755-3818; original unary defer source becomes callable region. | Meta-producer-only lowered form; use existing unary `defer statement` publicly. Generated environment/callback identities are compiler facts, not user holes by default. |
| `(var E)`, cons/append/string/nil, c-assert | compiler.x:2275-2326 caches literal graphs; transform.x:4250-4253 converts; emit.x:1042-1056. Some source List literal/Lisp construction lowers through these. | Exact-form access belongs to meta producers. Source ordinary literal/append/assertion machinery is sufficient; do not create one new public AST constructor per backend convenience. |
| src, at, api-source, binding | macros.x:3778-3820 captures source; ast.x:33-65 identities; parse.x:2477-2489, 2738-2743; emit.x:1024. | Keep ordinary canonical metadata accessible but no new source wrapper syntax. Recognition compares an origin-insensitive view while returning original captures; identities retain compiler ownership. Binding is semantic content, not removable metadata. |
| declaration-bundle, declaration/syntax-recipe, declaration-pending/forward/default/function | parse.x:2505-2557, 2675-2716 retains once-only shallow declaration production; compiler.x:1302 onward. | Meta-producer-only phase/administrative form, preserving source-order/lifetime semantics. Public Declaration/NamedType and existing macros own surface. Matching cannot rerun arbitrary recipes backwards. |
| macro-invoke, macro-slot, macro-bind, meta-call/meta-cap, tpl-call | macros.x:2924-2963, 3011-3029, 3971-3985, 4247-4270; expressions.x:2071-2089. | Existing canonical stage records. Public named/anonymous template and invocation forms should generate them. Raw List inspection belongs to meta producers and implementation owners; only structural template callees compose bidirectionally. No inverse of arbitrary meta computation. |

“Meta producer only” means retaining `%()` as normal expressive structural
access for that compiler production, not hiding it behind opaque objects,
authenticating producer origin, or denying ordinary legal constructed Lists.
A new public source form requires its own user semantics; merely eliminating
a raw internal AST match is not sufficient reason.



## Plan review

Existing binding producers establish issued identities; Type/expression
owners establish annotations and conversions; origin owners establish source
anchors. Hole insertion must trust those facts instead of revalidating them.
Ordinary compiler context still checks the skeleton at its legal position.
There is no new semantic AST validator, identity authentication layer or
dedicated diagnostic proposed.

Reuse canonical immutable Lists, ordinary Match and layouts, fresh rows,
capture/member projections, `bind_syntax`, existing conversion owners and the
current transform driver. Delete duplicated direction-specific projectors and
client knowledge of stage markers as the shared owner becomes real. A private
hole-boundary mechanism is necessary because substitution alone loses binding
stage information; origin correspondence is necessary to return original
captures, not merely prettier diagnostic messages.

Templates make source-bearing skeletons ordinary x2c; semantic work remains
ordinary x2c beside them. Meta-producer-only `%()` avoids a second source language for IR. Negative probes protect actual public resolution, capture
correlation and stage behavior: local/global capture, wrong references,
collapsed distinct binders, mismatched descriptors and sequence grouping.
They do not justify extra runtime validation or process requirements.
