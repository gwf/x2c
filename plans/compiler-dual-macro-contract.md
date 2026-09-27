> Status: active -- contract research; production rewrite is not ready.
> The decisions below are recommendations for the stable compiler contract.
> The compiled-in bound-hole try control now has 62-case raw C/H parity
> and paired timing. The revised slot-call/effect-record contract, open names,
> explicit stage carriers and rollback still need combined integration evidence.
> Open target-value lookup works; late lexical shadowing currently fails.
> Investigation only: no production edits, bootstrap refresh, commit or push.

# Compiler contract for dual-purpose macros

The compiler should write lowering shapes using the four Macro forms and
meta function calls in slots. Meta functions produce non-source nodes and
return effects as data; the compiler applies those effects and retains sole
ownership of binding, typing, scope, regions and diagnostics. Raw `%()` for
internal productions belongs inside their meta producers, never lowering
template clients. This recommendation follows the revised pasted request at
`/Users/gary/.codex/attachments/645ec637-6471-4b94-a632-4914d2cbe2f4/Pasted text.txt`.

This plan is based on `1b23aaa7e103461c3b219b9e10546aeb35384b60`.
The requested survey was found at
`/Users/gary/Git/x2c/.claude/worktrees/x2c-pythonic-syntax-spike-07ba2e/.context/dual-macro-compiler-opportunities.md`.
Its original survey baseline is `553429f`; current source, rather than its
line numbers or capability assumptions, is authoritative here.
The prototypes remain in `.context/dual-macro-phase3/` and managed isolated
worktrees. Nothing in this plan claims that its proposed semantics already
ship in x2c.

The complete production rewrite is **not ready**. The simple forms remain
viable; the missing proofs concern insertion context and result/effect
integration, not additional public descriptor APIs.

| Requested decision/proof | Result in this spike | Evidence |
| --- | --- | --- |
| Four forms plus meta slot calls | Recommended client contract; open modifier and common slot adapter still proposed | parser3, capture and stage patches; sections 1/8 |
| Internal-node producers | Named owner/producer policy; no raw internal builds in clients | grammar-producer-policy.md; appendix |
| Effects with rollback | Existing rollback demonstrably incomplete; extension specified, not proved | compiler-use/effects.md and executable failure probe |
| Source/bound/lowered insertion | Bound/lowered control preserves holes; complete stage ABI and slot-effect try path missing | compiler-use/bound-hole-control.patch; 62-case manifests |
| Open versus closed names | Compiled-in target value signature and primitive cast Type lookup succeed; caller-local value collision fails; closed regression passes | compiler-use/open-policy.md and logs |
| Tree rules | One bounded return-normalization rule works with nested traversal and pruning | stages/driver.x |
| Field grammar | Source/derived layouts and 215-head census recorded; dynamic-head reconciliation incomplete | grammar-fields.md, grammar-head-census.md |
| Cost | Five paired warm samples for bound-hole control; full meta/effects path unmeasured | stages/cost/paired-summary.json |
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
  addition, not a phase 3 parser capability.
* Existing `Compiler.bind_syntax(value, AstPos, return_type)` for consuming
  constructed code in a specified target compiler. Callers also retain
  ordinary compiler origin context. A runtime Macro call cannot guess which
  target Compiler owns the result; binding supplies that context explicitly.
* Private meta producer functions for internal forms, listed below. Their
  calls use ordinary existing slot-call syntax; there is no public getter,
  stage-marker method, descriptor API or new x2c-prefixed API family. `%()`
  is confined to those producers and their private canonical helpers.

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

This must apply to value, typedef and tag roles, not member labels. Existing
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
argument survives insertion. See `compiler-use/open-policy.md`, the native
log and transformed-code log. This uses private caller plumbing, not yet the
complete public `m(args)` routing. The default closed hygiene regression also
passes in the new parser.

A second compiled-in template casts through `CompilerOpenType`: the compiler
has an int typedef, the target has a global long-double typedef, and the caller
has a same-named local int typedef. Base-only ordinary Type resolution produces
an explicit long-double cast; native execution passes and the local remains int.
Root independently reproduced it. This proves one cast Type role resolving to
an existing primitive, not aggregate/tag coverage or preservation of typedef
labels in emitted C. See `compiler-use/open-type-*` and `open-policy.md`.

A caller-local integer with that function's name makes the generated C fail:
`called object type int is not a function or function pointer`. Global lookup
selected the right identity, but `_try_block` runs after the parser popped the
caller scope. Ordinary hygiene cannot see the local to rename its emitted name.
Target global lookup alone is therefore insufficient.

The recommended insertion context includes the parser-owned lexical scope
stack, return context and origin, retained for the unit's lifetime. The existing
traversal/application owner re-enters these scopes through `Sym.push_scope`
and restores them afterward. Existing binding/hygiene remains the owner of
local aliases; hole contents are not rebound. Scope-map ownership, effects
on those retained maps and nested traversal require a positive prototype.
Reconstructing another resolver from arbitrary ASTs is not recommended.
The same requirement applies to local typedef/tag shadows. Until proved,
passing existing typed native calls as holes remains a viable migration control,
but does not satisfy the chosen complete open-template contract.

Native runtime functions create another boundary. `_catch_call` presently
builds a native callee String and supplies its result Type; some declarations
come from generated `exception.h` (`src/generate.x:1178`). Open resolution
must preserve ordinary compiler treatment of native declarations and include
placement. It cannot invent a binding/type or require a declaration earlier
than the present pipeline does. A source-built call and today's explicitly
typed native call are not yet proved interchangeable.

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
macro open Statement $try_region(Name $frame, Statement $body,
  Statement $landing, Statement $cleanup...) {
  $frame_declaration($frame)
  x2c_exception_push(&$frame);
  if (!sigsetjmp($frame.env, 0)) $body
  else {
    x2c_exception_landed(&$frame);
    $landing
  }
  $place_cleanup($cleanup...)
}
```

`frame_declaration` receives prepared target Type/name facts and returns
canonical declaration code plus support effects. `place_cleanup` receives the
prepared region/exit decision; it does not discover placement from code.
Their exact signatures must include these facts (omitted above for readability).
Pure template shape does not decide cleanup ancestry, staticness or conversion.
The actual parity prototype supplies declarations, runtime calls, condition,
body, landing and cleanup as bound/lowered holes; its source skeleton is the
conditional. It does not implement those slot calls or their effects. Do not
rewrite `_try_block` against the illustrative interface until the combined
path demonstrates it.

Required evidence before using this contract in src/: compiled-in descriptor
applied to a target unit, local shadows of value and Type globals, lowered
returns/declarations surviving hole insertion, unchanged IDs, unchanged
conversion count, and byte-identical C/H on the try/defer/catch fixture corpus.
The repaired compiled-in control now matches all 62 outcomes and raw C/H
bytes: 46 lexical-try fixtures, the seven-file compiler/tokenizer corpus, and
exception-hot-paths in default/live modes. Its fixed runtime calls remain
typed holes, so it does not prove open free resolution or meta slot effects.
The initial invalid `seq{`, wrong Expr/Statement categories and lost origins
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

`stages/driver.x` demonstrates one actual transform family: bare-return
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

The repaired compiled-in bound-hole control has five alternating paired
samples after warmup, identical source paths and explicit common `X2C_HOME`.
All 62 comparison cases and final timed C/H outputs match without normalization.
The comparator checks exit status and raw generated files, not diagnostic text;
negative cases do not establish byte-identical diagnostics.
Seven-file medians: default 6.113 -> 6.146 seconds (+0.54%); live 7.501 ->
7.496 (-0.07%). Exception translation: default 0.591 -> 0.589 (-0.37%);
live 0.652 -> 0.679 (+4.25%), with overlapping noisy ranges. These support
feasibility of this control, not a precise overhead claim or a performance
improvement. They do not measure meta slot calls, effect plans, full open
resolution, additional fresh declarations, runtime exception performance or
cold helper build. Those costs remain unmeasured. The
existing translation corpus is transform, emit, expressions, generate, parse,
type and tokenizer (`unittest/benchmarks/run-compiler-translation.sh`);
`exception-hot-paths.x` supplies exception-heavy language code. The paired
measurement used the same source paths, flags, process settings and host,
compared C/H bytes first, then measured repeated quiet-host warm translations.
Report cold preparation separately and count applications/typed-hole visits.
Do not promise that a preparation strategy keeps the checkpoint quiet before
those samples exist.

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
callback. The canonical result is a private `(code-value STAGE KIND NODE
ORIGIN EFFECTS)` envelope, not a second AST: NODE is the existing canonical
List, and Name/Type/scalar slot values use their ordinary canonical values.
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

| Effect record | Producer intent | Compiler application point / owner |
| --- | --- | --- |
| `(new-name REF STEM)` | Allocate one requested binding/name shared by later code. | Ordinary fresh_name + sym.introduce in original allocation order, before dependent binding; existing counters/IDs remain transaction-owned. |
| `(global REF NAMESPACE NAME)` | Resolve an open fixed reference. | Ordinary target base-scope value/Type/tag lookup before dependent skeleton binding; global scope changes must join the transaction. |
| `(early CODE SITE)` | Register an adapter/helper declaration. | Pending early-declaration overlay; publish through add_early only after successful insertion. Existing transform drains it in order. |
| `(memo KEY REF)` | Associate an adapter with its generated binding. | Pending names.adapters overlay visible to later planning in the same expansion, committed once insertion succeeds. Supplied prior hit remains authoritative. |
| `(constant REF VALUE)` | Intern canonical immutable constant data. | Existing constant/cache owner before code references REF; cache/name writes must be transactional or postponed until success. |
| `(initializer CODE DEPENDENCIES SITE)` | Schedule source/static initialization. | Existing init/dependency owner, buffered until successful insertion, preserving its order. |
| `(location SITE)` | Attribute newly constructed shape/diagnostics. | Dynamically scoped origin during construction/binding, restored on success or failure; original hole wrappers remain unchanged. |
| `(cleanup REGION EXIT CODE)` | Place cleanup at a particular region/exit. | Existing region/transfer owner at the named insertion, not a global append. Order includes unhandled branch, normal completion and transfer exits. |
| `(require FEATURE)` | Request current generated runtime/header support such as exception support. | Existing needs_exception/emission owner, staged until successful insertion. |

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
coverage are specified here but not implemented by the control probe.

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

Extend the **existing caller-owned transaction**, with pending queues/memo
writes and coverage of every scope/name/cache store actually mutated. Preserve
read-your-writes within that transaction. No parallel transaction framework or
helper-side state mirrors are proposed. Apply provisional name/global effects
inside it; bind the result; commit queues/memo/support only on success; rollback
all provisional compiler state on failure. Nested insertions share the caller's
ordering/ownership and must not publish effects the outer transaction can lose.
Existing macro invocation creates its transaction in `_invoke_definition`,
not in `expand_macro_invocation_node` or `bind_syntax`; mid-transform callers
must own the same boundary explicitly.

The executable current-transaction probe reports
`binding=1 fresh=1 early=0 init=0 memo=0 global=0 origin=0 exception=0`,
where 1 means restored. Root reproduced these results using the ordinary
transaction methods. The probe cleans leaked state afterward; that cleanup
is not transaction coverage. See `compiler-use/effects.md` and its fixture/log.
No positive extension of rollback was implemented.

A focused failure probe must compare scope/global bindings, counters, cache
entries, queues, memo maps, feature flags and origins before/after a deliberately
failing skeleton. A second probe must observe an adapter created earlier in the
same expansion. **These effects/rollback properties are not established by the
62-case shape control.** They remain an implementation-blocking proof gap.

Queries not already passed by current callers: per-catch pattern staticness;
resolved runtime callee signatures; adapter memo hit; alias/protocol/layout
classification; conversion results; precise origin; constant/init dependencies.
Existing compiler owners must prepare those arguments. `_try_block` currently
queries staticness mid-loop; wrapper/adaptation construction queries conversions
and memoization; source init/literal construction queries placement/cache state.
Do not reproduce those semantic owners in the helper. Facts needed only during
ordinary skeleton binding stay there. A complete dependency plan for cases
whose queries depend on a newly produced Type remains unprototyped.


## Alternatives and recommendation

| Alternative | Strength | Cost or limit | Decision |
| --- | --- | --- | --- |
| Shared Macro body/role table, ordinary AST, meta producers and caller effects | Same forms construct and recognize; ordinary compiler owns semantics; clients hide IR detail | Needs late lexical context and common stage/effect adapter | Recommended; prove integration before src/ migration |
| All runtime callees/declarations supplied as typed holes | Actual byte-identical try control; avoids unresolved native signatures | Makes compiler source carry plumbing and does not establish open templates | Keep as baseline/control, not final surface |
| Rebind the fully substituted tree | Reuses binder without explicit hole boundary | Reinterprets lowered returns and typed holes; can change scope/type/conversion behavior | Reject this implementation; preserve ordinary binding only for skeleton |
| Canonical raw builders everywhere | Works today, direct construction cost | Exposes IR fields and repeats construction/recognition logic across clients | Confine to meta producers; retain ordinary canonical contract |
| Separate pattern DSL or semantic validator | Could independently specify recognition | Duplicates Macro structure and ordinary binding/type ownership; adds a public model | Reject; share Macro preparation and existing Match |

## Remaining decisions and limits of this spike

The four forms remain the client contract. The proposed `open` modifier,
slot-result ABI and meta producer signatures are additions that must be settled
before freezing compiler consumer source. In particular:

* Positive late insertion scope restoration, including local value shadows and general typedef/tag
  roles, is missing. The primitive cast Type shadow control passes. The failure and an ordinary-owner alternative are known.
* The complete try/defer/catch path with meta slot calls, effect aggregation,
  explicit stages and rollback is not implemented or timed. The 62-case proof
  covers its bound-hole control only. Parent conversion count and failed
  skeleton diagnostic attribution need dedicated combined probes.
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

These are specific integration questions, not evidence that simple Macro forms
cannot express the complete design. They prevent declaring the production
rewrite ready. No self-host comparison of the revised complete path was run;
no production consumer, bootstrap output, commit or remote ref was changed.

## Rewrite and bootstrap order

1. Establish the runtime Macro application/recognition owner behind the four
   forms, open definition policy, explicit target binding, typed-hole boundary,
   original capture origins and role-specific Name projections. Consolidate
   `_capture_pattern`/`_capture_row` behind the same role table. The phase 3
   callbacks are prototypes, not parallel permanent implementations.
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


Each function receives ordinary supplied syntax/data arguments. Stage marks and
effects are conveyed by the common private result adapter; client source never
opens that envelope. `%()` appears only inside the named producer (or its
private structural helper), not at lowering call sites.

| Canonical production | Proposed producer and argument facts | Current authoritative owner / client use |
| --- | --- | --- |
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
