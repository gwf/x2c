> Status: active -- architectural survey and proposal, 2026-09-28.
> Source baseline: 87f6c5c1, including the private lambda consumer draft.
> The campaign contract owns sequencing, delivery rules and the cost ledger.
> This document distinguishes observed owners from proposed organization;
> illustrative target code is not a compiled capability claim.

The baseline survey predates the `0bccd679` support-owner reconciliation in
the contract's E44. In particular, `builtins.x` contains native macro
algorithms that construct user-program syntax before binding. They must be
classified as source producers rather than omitted as backend formatting.
The `$scope` family has a private one-template candidate; the `foreach`
trial was reverted after its origin-wrapper changes, and the `class` family
has no proved complete source-template replacement. None of those results
establishes campaign completion or changes the semantic ownership below.

# Compiler architecture with shared grammar macros

The desired compiler reads in language forms and transformations rather than
List layouts. Shared grammar macros remove repeated structural knowledge;
transformation templates expose the generated program. Semantic services
continue to establish the facts those transformations need. A successful
migration removes old recognition/construction arms and, where supported by
the source, duplicate helper machinery. Moving unchanged code alone does not
establish that result.

## Evidence and coverage

Two isolated Sol workers surveyed expression/statement/parser/type owners
and transformation/protocol/emission owners. The orchestrator inspected
literal construction, region analysis, shared traversal, macro application
and representative peripheral consumers. This is a responsibility survey,
not an exhaustive classification of every literal occurrence.

`rg -l -F '%(' src --glob '*.x' --glob '*.xmacro'` finds 34 files at the
baseline, including generated `linked-meta.x`: 33 hand-authored files.
This textual reach count includes comments, data and syntax. It is not a
migratable-site count. At that surveyed baseline the shared grammar defined
four source macros: tried, caught, lambda_expression and lambda_captured.
Later migration added more forms; the baseline count is not a current count.
No defensible
percentage of removable compiler lines follows from those numbers or the
historical 215-head census.

### Delivery overlay through `f6606dbf`

The contract's readable-form entries and cost ledger are the detailed
implementation record. Current `dev` has these family-level changes:

| Family | Shared form now used | Semantic owner retained |
| --- | --- | --- |
| Try, defer, callable and Func helpers, Var literals, managed cleanup and destructuring | Adjacent output templates replace their selected manual lowering skeletons | Transform still chooses captures, types, lifetime, evaluation order and placement. |
| Protocol descriptor and direct-update helpers | Templates express storage registration and update bodies | Protocol still chooses adapters, signatures, memo keys, volatile storage and registration phase. |
| Parsed `if`, `while`, `do`, `return` and `defer` | Shared Statement forms recognize their source shapes in the binder | Parser and binder retain positions, scopes, branch facts, type resolution and diagnostics. |
| Bound loop, switch and truth conversion, region expression statements | The same forms are reused downstream; an expression-statement form names region calls and stores | Transform retains transfer barriers and condition conversion; region analysis retains escape and restore facts. |

The contract records concrete exceptions where source templates would change
binding or origin behavior, lose native C behavior, or add more machinery than
they remove. This overlay is progress by transformation family, not a claim
that the source-form or C-producing inventories are complete.

Examples showing why the classification matters:

- `regions.x:_callee_of` unwraps expressions, recognizes calls, extracts
  argument rows and reads binding identity. The structural portions are
  grammar consumers; region ownership and escape analysis remain analysis.
- `stage.x:_meta_constant_leaf` recognizes casts, literals and calls, then
  converts or folds values. Shared forms can replace recognition, not the
  semantic evaluation rules.
- `meta-group.x:85-100,214-215` reads function structure and reconstructs
  declarations. These are downstream grammar clients, outside the obvious
  parser/transform pair, and belong in final source-form coverage.
- `collect.x:_renumber_bindings` rewrites binding identities for interfaces.
  Binding identity is semantic data with existing accessors, not a new
  language keyword.
- `meta-helper-client.x:224-256` uses lists as a helper wire protocol;
  `toolchain.x:120-191` uses them for process arguments. Neither is program
  AST, so neither should move into the language grammar.

The current `stage.x` and `meta-group.x` clients do not offer a bounded
source-form migration. `_meta_constant_leaf` reads typed, folded values and
cache/meta carriers; a cast source macro would replace only one case header
while still needing the bound result type and conversion. `meta-group.x`
rebuilds declarations from bound functions and compiler-created static
records with binding identities and exact modifier layout. A source
declaration template would discard those facts. Retain these current raw
cases as stage-specific consumers; revisit them only with a projection that
deletes their structural work while preserving identity and stage.

Two later inert probes narrow other source-form candidates. In `type.x`,
designation queries receive both typed expressions and bare operator
children. Five `macro Expression` candidates failed to match every bare
child because their patterns require an `expr` root; replacing the repeated
raw arms would need a justified projection of that mixed input. In
`expressions.x`, dot and arrow macros captured the member spelling as a
String while the compact combined resolver case uses a one-item field List.
Two templates, two dispatch arms and reconstruction would add machinery
without removing the existing semantic body. These are scoped exceptions
for the probed clients, not claims about all operator templates.

## Proposed ownership

| Concern | Target owner | What changes or disappears |
| --- | --- | --- |
| Language shape and recognition projection | grammar.xmacro | Shared source macros replace per-pass literal patterns. Recognition-only macros are legitimate. Derived fields use narrow existing or grammar-owned accessors. |
| Token consumption, precedence, source locations | Existing parser entry points | Parsing remains authoritative. Grammar macros reuse it; they are not a second parser or closed AST validator. |
| Binding and type resolution | Existing semantic operations | Callers request semantic facts instead of reconstructing declarations or interpreting Type lists independently. |
| Generated program shapes | Templates beside their transformation | C skeletons leave procedural List construction. Meta slot functions own loops and choices among those skeletons. |
| Region and capture analysis | Existing analysis owners | Shared grammar replaces syntax inspection; flow state and semantic boundaries stay explicit. |
| Traversal and normalization order | Ast child rebuilding and existing drivers | Reuse shared copy-on-change rebuilding. Do not add a visitor framework to replace already shared machinery. |
| Internal stage/effect representation | Macro application and named producers | Clients pass code/facts. They do not spell carriers, effect rows or compiler-internal node layouts. |
| Emission and interfaces | Existing output owners | Source-form inspection migrates where applicable; formatting, cache identity and wire formats remain their own responsibilities. |

`Ast.rewrite_children` delegates to `ast-rewrite.xmacro`; cache, collect,
type and transform already share that operation. The rewrite must preserve
unchanged-node identity, which the normalizer uses. Region analysis walks
typed source before transformation and reaches a function-summary fixpoint
(`regions.x` header and `_fixpoint`). Merging region analysis into lowering
would erase a useful stage boundary rather than remove duplicate ownership.

### Organization changes worth investigating

The existing module names understate their responsibilities: expressions.x
includes parsing, semantic resolution and generated call construction;
parse.x includes token parsing and constructed-syntax binding; protocol.x
includes registry/selection and generated helpers. The migration should
separate these responsibilities where a cohesive transformed family makes
the boundary concrete, rather than moving every function at once.

Keep one discoverable grammar entry point. Group its definitions by source
family and add each definition with its consumers; do not generate hundreds
of unused definitions from a head census. Keep output templates beside
their lowering, not in a giant global template warehouse. If a transformation
family warrants its own module, move its templates and supporting meta
functions together while retaining one normalizer/registration owner.

Do not merge expressions, literals and transform merely because each visits
lambdas. They currently act at distinct stages. First localize knowledge of
lambda shape and clarify the construction boundary below; then judge whether
capture preparation and closure helper synthesis have a cohesive extraction.

## Representative region client

Today `_callee_of` in regions.x understands expression/cast/parens wrappers,
the call node, the arguments node and the empty-argument marker. Its semantic
question is simply the direct callee and its arguments. An illustrative
target is:

```x2c
macro Expression $called(Expr $callee, Expr $arguments...) =>
  $callee($arguments...);

match (source_expression(value))
  case called(?callee, *arguments):
    return binding_identity_spelling(binding_of(callee));
```

The existing declaration of `source_expression` preserves the final typed
expression while looking through casts/parens. `binding_of` above denotes
the existing identity question, not a new source variable. The grammar
projection must normalize the empty-argument representation and retain
bindings; this example does not claim those call projections already ship.
Region flow, return provenance and alias tracking are intentionally absent
from the grammar. Reuse the same call form in other passes instead of
creating region-specific call macros.

## Shared initialization and the emission boundary

Verified duplicate shape owners:

- `cache.x:_make_header_cache_guard` and
  `generate.x:_declare_guard` both build the same static integer guard.
- `cache.x:_patch_header_cache_function` and
  `generate.x:Init.patch` both prefix a function body with a
  guarded call to an initializer.

An illustrative common template is:

```x2c
macro Statement $ensure_initialized(Expr $guard, Expr $initialize) {
  if (!$guard) $initialize();
}
```

The guard declaration and function-body wrapper can likewise have one source
template each. Template placement should have a shared initialization owner
because there are already two actual consumers; this is stronger evidence
for extraction than a file-size preference. Cache selection/dependency order
stays in cache.x. Translation-unit partitions, conditional preprocessor arms
and shutdown registration stay in generate.x. Do not merge those modules.

A current-tree check narrows this proposal. Both consumers patch already
bound functions after transform. `promoted-string-cache` exercises the
header-local and source-local guards and their lazy calls. A shared
conditional alone leaves the two function constructors intact; rebinding a
whole function template could change its identity, header placement or
preprocessor arms. Keep their present owners until one stage-preserving
construction is proved on both paths with exact C/H and runtime behavior.

There is also actual lowering in emit.x, not just formatting. For example,
`Emitter._var_collection` chooses a constructor alone for an empty collection
or an update call for nonempty elements. `_local_static` generates guarded
storage and initialization code and diagnoses switch entry bypasses. Thus a
transform-only conversion cannot claim that all C-producing shapes are
expressed by templates.

For each such family, trace the complete path into emission. Prefer making
the C shape explicit in its existing lowering with a template and reducing
the emitter to printing it, when source syntax can express that shape without
losing type, origin, ownership or placement behavior. Keep an explicit
backend exception for genuinely internal/type-dependent forms until there
is a supported template representation. Do not move diagnostics or invent
a second lowering pipeline just to remove the final raw match.

The source-grammar completion criterion and the C-template completion
criterion need separate records: no raw parsed-node recognition outside
grammar/parser does not imply there are no C-producing decisions in emit.x.

## Transformation inventory and expected deletions

This inventory groups observed families, not individual case arms. The
references identify the surveyed baseline; current function owners are
authoritative after edits.

### Source vocabulary and semantic finish operations

| Family | Current consumers and migration boundary |
| --- | --- |
| Calls/member/index access | expressions.x:313,652,670,1815 and region/type queries. Share source forms; retain receiver adjustment, method selection, arity and evaluation order. |
| Operators, casts, conditionals, parentheses, sizeof, commas | expressions.x:_resolve_content and conversions; type.x designation queries. Share fixed source spellings. No generic punctuation-hole capability is assumed. |
| Type tests | expressions.x:2239,2473 and require_var_tag. Recognize source `is`; exact-tag validation and native constant choices remain semantic. |
| Arrays/composites/designators | expressions.x:2076-2227,2586-2626 and initializer processing. Share source structure; keep initializer paths, layouts and converted alternatives internal. |
| Control statements | statements.x:115-535 and parse.x:2800-2964. Grammar shared across passes; parser consumes tokens and binder establishes scope/branch facts. |
| Declarations/functions | parse.x declaration and function finish operations, Type declaration/parameter presentation. Simple `$type $name` does not cover multiple declarators, attributes, fields and unnamed parameters. |
| _Generic associations | expressions.x:_parse_generic and resolution/conversion consumers. A whole association-sequence hole is not demonstrated; this is a capability prerequisite, not completed coverage through a single-arm example. |
| Match arms | statements.x:332-429 and parse.x:2920. Guarded bodies and interleaved preprocessor rows require a proved projection; Catch holes alone do not establish it. |

Two source-backed consolidation opportunities go beyond changing notation:

- `_parse_reference_arm` in statements.x and
  `_bind_optional_reference_arm` in parse.x both save reference presence,
  establish branch facts and restore them. Their `if` owners also duplicate
  promotion after terminating guards. A shared operation must run parsing
  or binding while those facts are active, not process a completed body.
- `_append_managed_declaration` in parse.x already serves both token and
  constructed declarations. Keep this shared transformation, put its output
  template beside it, and remove nested method-call/defer List construction.
  The output must not introduce a block that shortens cleanup lifetime.

Illustrative managed-cleanup output:

```x2c
macro open Statement $managed_cleanup(Expr $receiver) {
  defer $receiver.cleanup();
}
```

Eligibility, declaration splitting, installed identity and source order
remain with the existing managed-declaration owner. Likewise,
`_install_declarator_node` and `_finish_function_parts` already converge
token and constructed input paths; preserve that reuse instead of creating
another binder as part of a parser-file split.

### C-producing families

| Family and current owner | Migration and retained responsibility |
| --- | --- |
| Callback/Func adapters, transform.x:141-268,404-899 | Co-locate C helper/context templates with callable lowering. Keep ABI compatibility, conversion, memoization and early declaration order in existing services. |
| Lambda helpers, transform.x:1402-1642 | Keep adjacent to callable adapters they already reuse. Replace environment/helper skeletons after solving stage-preserving construction; retain capture analysis. |
| Scope cells, transform.x:1147-1400 | Cell output templates are landed. Binding identity, lifetime and reference-write checks remain semantic services. |
| Try and cleanup, transform.x:_try_cleanup, _lower_try | The outer try exemplar is landed; cleanup still has manual calls/assignments. Do not count the whole family complete merely because its outer template landed. |
| Defer, transform.x:_defer_block and 3754-3933 | One visible record/registration/body/cleanup template, with capture-field loops in slots. Keep capture selection and unwind placement separate semantic steps. |
| Destructuring and sequenced protocol calls, transform.x:2989-3140,3246-3274 | Templates for declarations, assignments and temporaries; retain ordered evaluation, result types and pre-cell lowering order. |
| Var arrays/maps, transform.x:3593-3622 | Ordinary constructor calls are landed; current emit.x has no varray/vmap/vpair or _var_collection path to delete. Retained transform/cache aliases can accept legal constructed syntax, so their removal needs a compatibility decision. |
| String conversion, transform.x:3649-3689 | Separate output shape from conversion/cache decisions and the native-depth segment boundary. Do not merge with collection conversion just because both are literals. |
| Protocol synthesis, protocol.x:1766-2363 | Template update/discard/adapter bodies and descriptor/registration shapes. Reuse wrapper_function; keep conformance, linkage, freshness and registration phases in protocol services. |
| Cache materialization, cache.x:35-474,508-707 | Template generated declarations/assignments; retain cache identity, dependency graph and initializer phase propagation. Share only actual duplicated initializer shapes with generate.x. |
| Unit initialization, generate.x:25-318 | Shared guard/entry templates; retain unit partition, preprocessor placement and shutdown decisions. |
| Native backend, emit.x:_local_static, _initializer_macro, _foreign_alias and match emission | Assign each C-producing family an explicit lowering owner or reasoned backend exception. Operator/declarator precedence remains emission. |

Protocol `_parameter_declarations` and transform `_auto_names` plus
`_named_decl_params` repeat parameter identity/declaration assembly. They
already use Type presentation operations; consider one shared operation
when migrating their callers, not a new general helper-generation framework.

Native local-static arrays use `__typeof__` and macro expansion whose final
shape is known by the C compiler. Foreign aliases emit preprocessor aliases
and signature checks, not ordinary wrapper functions. These are concrete
boundaries where a simple Type hole or callable template is not established
as sufficient. Record such exceptions per family; do not force a translation
that changes the native mechanism.

`Emitter._raise` also remains an emission boundary. It records the final
file, line and function name, including a generated defer callback's owner,
and appends `__builtin_unreachable()` only for a cause that
`Ast.never_returns()` recognizes. `raise-statement` checks the site and
runtime location. Moving the raise node into an earlier source template
would lose those emitter facts and the terminal marker used for `_Noreturn`;
retaining both paths would add machinery. This is a bounded backend
exception for the current representation.

### Protocol update example

`protocol_update_helper` builds a call, assignment, optional saved old value
and return before passing the body to the existing wrapper service. A target
postfix body reads:

```x2c
macro open Statement $compiler_postfix_body(Type $type, Name $old,
    Expr $lhs, Expr $source, Expr $one) {
  $type $old = *$lhs;
  *$lhs = $source(*$lhs, $one);
  return $old;
}
```

The slot selects postfix versus ordinary update from established facts.
The semantic owner still checks the protocol signature, converts the unit
operand, preserves volatile storage, memoizes and publishes the wrapper.
This removes the hand-built body without recreating those decisions in a
template library. As with initialization, construction must preserve the
existing stage; this is an illustrative target, not a tested replacement.

## Lambda construction: the first architectural boundary

Observed path:

1. `Macro_apply` in lib/meta.x:175 returns a pending template invocation.
2. Macro expansion in macros.x substitutes the template, then calls
   `bind_syntax` (around line 4421).
3. Binding a lambda reaches `Compiler.bind_lambda_expression` in literals.x.
4. That operation binds parameters/body, collects captures and selects the
   result type before constructing its final lambda node (1025-1100).

Calling the same ordinary source template at step 4 repeats the binding
operation. The parser's corresponding final construction appears in
`parse_lambda_literal` (1110-1192). Rebuilding an already-bound lambda after
capture/body rewriting also must retain type and stage. Shared recognition
does not, on its own, solve these construction sites.

There is existing machinery to reuse, not a reason to create a second macro
system: typed holes, shared template projections, the application transaction,
and bound/lowered carriers consumed by `take_code_value`. But a carrier marks
an already constructed result; it does not itself materialize a lambda
template without binding it. The private `_macro_instantiate` in lib/meta.x
is for recognition derivation and is not a proven replacement construction
API with equivalent hygiene, effects and stage behavior.

Recommended next investigation: a narrow, stage-preserving construction
projection of the same source macro for a producer that has already bound
its inputs. It must share existing substitution and identity ownership,
retain the known result type, and avoid new binding or effects. Prove it on
plain/captured lambda construction and reconstruction before considering
general exposure. Do not change normal macro application semantics.

Alternative: a grammar-owned canonical producer can localize the raw node
layout immediately, with an explicit exception for the binder/parser. That
removes duplicated layout knowledge, but does not meet the requested goal
of writing these constructors with the source template. It must not be
reported as equivalent completion.

The implementation direction is a narrow compiler-internal construction
operation, not a new public macro mode. The campaign authorizes this routine
capability choice; it does not need another permission round.
An illustrative producer client is:

```x2c
Macro captured = $lambda_captured;
return c.rebuild_expression(type, captured(body, captures, parameters));
```

`rebuild_expression` is implemented in prerequisite commit `40ea91c6`,
published in prerequisite batch `799875a8`. It materializes the same source template
while retaining established type and binding facts;
ordinary `bind_syntax` and normal macro application keep their semantics.
It must reuse the expansion/projection owner rather than add another macro
interpreter. Template-introduced bindings, computed slots and side effects
need explicit treatment before any broader interface is claimed.

### Focused feasibility probe

After the source survey, one temporary fixture in
`/tmp/x2c-bound-lambda-probe` reused `macro-lambda-captures.x` with a private
structural-template materializer. It substituted the existing expression,
source, value and splice projections, restored the input's resolved root
type, and returned an existing bound-code carrier. It did not modify compiler
or library source. The materializer was a probe, not a second production owner.

Returning that carrier directly through an ordinary named macro failed:
carrier consumption requires an active macro-value application. Returning it
through a macro-value identity template used that existing boundary and
passed `run.sh check --fixture bound-lambda` with the fixture's unchanged
expected output `17`, `5 5`, `11`. That exercises value/reference captures,
captured mutation, a block body and a plain typed lambda. The log is
`debug/bound-lambda-probe.log` in the orchestrator checkout.

This establishes a working narrow route from these source templates to a
retained bound result. It does not establish a general construction API,
hygiene for newly introduced names, arbitrary meta slots/effects, all type
forms, or compiler bootstrap compatibility. Those remain capability work,
not reasons to reject this successful narrow construction route.

The implemented internal operation reuses capture-row projection and the
descriptor's matching/substitution. Its retained-syntax path bypasses normal
invocation forwarding and source unwrapping, preserving bound children and
deferred parser holes. The native probe in
`unittest/probes/bound-template-expression.c` parses actual source templates
and lambdas and checks the operation directly: eight cases include captured
mutation, block/expression bodies, parameters, an established Func type,
source wrappers and deferred shells. It also checks unchanged binding facts,
scope/expansion state and body identity. This is a focused probe, not a new
recurring gate. Normal application still returns a pending invocation.

## Design review

This proposal reuses the existing parser, Type operations, identity accessors,
traversal and transaction owner. It introduces no new validators, registry,
visitor framework or recurring checks. The migration still removes both
manual constructors and recognizers at each adopted client. Exceptions
remain visible rather than weakening the completion claim.

Source reading establishes responsibility and call paths, not behavioral
equivalence of proposed code. Workers ran no builds or checks. The
orchestrator ran only the focused construction probe described above; no
compiler rebuild, gate or timing was run for this survey. Capability work
needs the campaign's focused checks and separate publication before adoption.
Final authored review precedes publication validation.

## Execution map

The bounded probe supports the construction proposal. Implement the narrow
capability, then retain the campaign's lambda, transform shapes, protocol,
and final source-vocabulary sequence. The ownership proposal guides where
each batch lives; it does not authorize mixing capability and cleanup work.

The first implementation batch after that investigation is either the
separate construction capability (if justified) or the explicitly agreed
producer exception, followed by lambda adoption. Defer remains the next
lowering batch. Within the later transform work, follow collection lowering
through emitter deletion and place shared initialization templates with
their actual cache/generate consumers. Source-vocabulary completion includes
region, Type designation, stage, meta-group and other downstream consumers,
not only expressions/statements.

For parallel work, assign semantic families with disjoint authored files;
the orchestrator owns shared grammar and plan integration. Do not dispatch
two migrations that both change transform.x or grammar.xmacro concurrently.
The two read-only survey workers finished. Their isolated worktrees are now
assigned to the construction capability and the parameter-redeclaration
repair, with disjoint source ownership. The orchestrator collects results
and lands these prerequisites in one integrated batch before lambda adoption.
This batch contains no adopters or cleanup and receives one publication gate.
