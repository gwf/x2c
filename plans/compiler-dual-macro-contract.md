> Status: reference -- narrowed research complete; production hand-off scoped.
> The combined try template/slot/effect/stage candidate passes 62-case raw
> C/H and outcome comparison. The failing-skeleton rollback probe also passes.
> Five paired timing samples on phase5 show +1.40% default compiler translation
> and +1.94% live; the default ranges do not overlap in this window.
> Inserted-name shadowing is baseline parity and remains a follow-up.
> Phase6 profiles the try path and hands off three scoped production plans.
> Production implementation is not authorized by this research record.

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
The prototypes remain in `.context/dual-macro-phase3/` through phase6 and
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
baseline 7.158-9.811 s, candidate 7.487-10.753 s. A transient `../1/x2c`
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
`stages/cost/`; current combined evidence is
`.context/dual-macro-phase4/comparison/results.md`, with parameterized scripts,
samples, ranges, hashes and comparison manifests.

### Phase5 cost on the final open-body candidate

The same runner repeats five alternating pairs after warmup, with common
absolute source paths/home/flags, no effect probe, and unchanged binary hashes.
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

| Lowering | Candidate | Default / live delta | Applications | Try transactions / all transactions | Status |
| --- | --- | --- | --- | --- | --- |
| try/defer/catch skeleton | phase4 final | +1.34% / historical | Not counted in phase4 | One per try; totals not measured | Historical, not added to total |
| Same lowering, open body / producer stages | phase5 final | +1.40% / +1.94% | 2 / 2 | 2 / 2119 default; 2 / 2124 live | Current compiler-corpus total; replaces phase4 |
| Same candidate, exception-heavy translation | phase5 final | +1.37% / +3.69% | 4 / 4 | 4 / 265 both modes | Separate workload, not an additional migration |
| Later lowerings | Not migrated | Not measured | Not measured | Not measured | Add when migrated |

Counts come from phase6's instrumented phase5 candidate and independent
count-only runs, not inferred from source occurrences. The compiler corpus
is seven translations; exception-heavy translation is reported separately.
Keep each cumulative candidate/original-baseline ratio; replacing successive
try candidates does not add their deltas. Measure later increments against
the same original baseline/workload. Independent medians do not establish
actual cumulative cost.

### Phase6 per-application profile

[Profile evidence](../.context/dual-macro-phase6/profile/README.md) contains the
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

**Recommend one optimization: lazy first-write staging inside existing SymTxn
and authoritative Sym mutation operations.** Avoid eagerly cloning untouched
scope maps; preserve nested commit/rollback and borrowed Map identity. This
must cover actual writes rather than skip snapshotting on a presumed pure
call. Do not add a second transaction owner. Its saving is unmeasured: a write
may still require the copy. It must retain the failing-skeleton proof.

This profile does not time commit/rollback, region preparation, frame allocation
or parse-time open preparation. Only two compiler-corpus applications contribute
about 3 ms of measured default work, versus the earlier roughly 85 ms paired
increase. Extended snapshots also run at 2119 ordinary transaction sites, not
just two try sites; their contribution and other fixed costs are unclassified.
Do not attribute the full +1.40% to try snapshots or promise to recover it by
this optimization. Instrumentation overhead is not subtracted; no optimized
candidate or three-lowering combined candidate was built.

**Recommend knowingly raising the planning aim to 5% cumulative default
translation overhead for the first three lowerings.** The existing 2% aim is
not demonstrated achievable: try already consumes +1.40% default / +1.94%
live and the measured per-try saving cannot explain that total. Three equal
independent +1.40% costs would suggest about 4.2%, only a planning scenario,
not a prediction; later workloads and shared fixed costs may differ. Keep 2%
as an optimization aspiration, not a promised three-lowering target. These
numbers are recommendations, not approved policy or new gates. Use the
existing advisory performance checkpoint and report combined measured totals,
including live and exception-heavy results separately.

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
is not transaction coverage. See `compiler-use/effects.md` and its fixture/log.
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

Final compiler: `/tmp/x2c-dual-combined-final`, SHA256
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

The final isolated binary `/tmp/x2c-dual-phase5-final` has SHA256
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
