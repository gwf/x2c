# Language features as loosely coupled components

> Status: retired
> Historical record at 5b7a7769. The active plan is ../language-components-foundation.md.
> Branch `gwf/language-components` from `origin/dev` 7e946b86. Salvage is
> implemented and verified locally through 0e61a65d, but remains unpushed.
> Gary's 2026-10-08 API correction supersedes the salvaged SDK surface.
> Next work is use-case-driven design across operators, dot methods,
> indexed reads/writes/updates, and declaration/statement features. Author
> representative extensions before choosing their shared API or integration.
> Registration classifies macro patterns once for operation-specific dispatch.
> The salvaged hook/claim/member contract is superseded. Gary authorized a
> second executable spike covering these premises and declaration sequences.
> The third iteration replaces the rejected authoring layers and tests the
> components together; see the current experiment report and log below.
> Gary authorized collection-access builtin migration as the next bounded
> extraction on 2026-10-08. Publication remains held. `dev` and `main` stay
> untouched. Experimental changes stay local on this branch.

## Current milestone: access, managed declarations, and delegation

Gary approved this milestone on 2026-10-09. Complete these three cases through
ordinary decorators, macro patterns, quotations, and Code/Type methods before
extracting more features. Justified total authored LOC growth is acceptable;
removing kernel lines alone does not establish simplification.

Collection mutations and the superseded pattern/node/effect cleanup are local
at `945ac5ee`. The next deliverable is a claim-free `$auto` feasibility
prototype, not adoption of an incomplete replacement. Compiler experiments and
raw evidence stay outside tracked repository state. The tracked compiler,
bootstrap, library, and expectations remain unchanged during this experiment.

### Demonstrated declaration boundary

The temporary compiler extends ordinary `$rewrite` classification to a
complete declaration pattern. It retains an expression macro application only
when the application occupies the complete initializer, through parentheses.
Argument parsing remains ordinary. The existing declaration owner installs the
binding, resolves initialization, checks explicit conversions, splits comma
rows, preserves shared type identity, and places quoted deferred cleanup.
Existing after-initialization registration retains its postlude-only contract.

The 24-line component matches a declaration, recognizes the pending `$auto`
application, checks storage and Cleanup participation through Type methods,
and returns a quoted declaration followed by cleanup of the declared binding.
Its two-line Type.member_in method delegates to the existing protocol-specific
SDK query, because finding any member named cleanup does not establish Cleanup
participation. This temporary method bridge is not an adopted SDK interface.
It uses no raw AST constructors or new source hook syntax. Kernel code reuses
ordinary pending invocations, macro recognition, quotation rebuilding, and
rewrite registration. No emitter exception or claim-shaped replacement exists
on this prototype's accepted path.

The prototype does **not** replace `$auto` successfully. A forwarding macro
expands through the ordinary expression binder, which resolves the inner
`$auto` before declaration interception can recognize it. An `$auto` supplied
as an argument to an identity macro expands during ordinary argument parsing.
The historical constructed-claim case also remains unsupported after removing
the auto claim registration. These are failures of this implementation, not a
rejection of every possible declaration boundary.

Stop this prototype without adopting it. Completing forwarding requires a
concrete comparison at the existing macro expansion owner. That comparison
must preserve expansion frames, hygiene, source locations, expression typing,
and deliberate rejection of nested expressions. Retaining arbitrary expression
macros or introducing another claim marker is not an acceptable repair.

### Behavioral and output evidence

Baseline: `945ac5ee991be4077800b1254fefe7faacced3c5`.
Temporary build: `/tmp/x2c-auto-feasibility/candidate/builds/0/x2c`.
Raw sources, harnesses, results, and logs: `/tmp/x2c-auto-feasibility/`.
Preserved patch and workspace evidence:
`.context/language-components/auto-boundary/`.

The compatibility comparison contains 22 cases:

- Eight successful executions agree: mixed managed/unmanaged declarations,
  repeated parentheses, constructed declarations, quoted declarations,
  initialization once and earlier-variable visibility, reassignment cleanup,
  reverse cleanup, later-initializer failure, returned aliases, runtime
  collection/resource types, and shared qualified struct/enum identity. Some
  cases cover several requirements.
- Eleven rejections preserve the diagnostic category and principal message:
  argument, assignment, return, nested expression, `for` initializer,
  static/extern/threaded storage, unsupported type, a different protocol with
  a cleanup member, and direct statement
  expression placement. Source locations are not established as identical.
- Three accepted baseline cases fail: forwarding, an identity macro receiving
  `$auto` as its argument, and the historical constructed claim.

The unmodified defer corpus runs 17 tests and 64 assertions on baseline.
The prototype cannot compile that corpus because of the forwarding gap; it
has no full-corpus runtime pass. No expectations have been changed.

A seven-program repository workload compiles successfully with the external
component: Lisp, tiny Lisp, maximum tiny Lisp, literate Lisp, and iterator,
Block/Buffer, and exception benchmarks. Matched source paths and neutral
component imports give **16 byte-identical C/H files**. Four Lisp executions
also agree. There are no accepted semantic C differences in that comparison.
The unmatched-import experiment differs only by the added component include
and diagnostic line offsets; it is retained separately, not a rebaseline.
Two further generation/replay rounds preserve all 24 C/H/.xi artifacts at
240,940 bytes. Their hashes are identical across those rounds.

The repository's seven compiler-unit translation workload was attempted. The
prototype's project helper fails to link `_Type_builtin_var_tags`; adding its
provider to the inputs did not resolve the failure. Therefore no complete
compiler-build or self-host performance result exists for this prototype.
That helper failure remains an unresolved limitation, separate from forwarding.

### Source cost and performance

Prospective production changes relative to baseline, excluding generated code:

| Layer | Added | Deleted | Net |
| --- | ---: | ---: | ---: |
| Compiler | 71 | 11 | +60 |
| Library | 2 | 0 | +2 |
| Builtin support | 2 | 6 | -4 |
| Component | 24 | 0 | +24 |
| Total | 99 | 17 | +82 |

These are experimental changes, not an adopted reduction. Retained executable
harnesses add 171 lines. The standalone probe adds 14. Exploratory patch and
packaging scripts and the earlier replay harness add 125. Those 310 support lines stay outside tracked state
and are separate from the proposed production footprint. Private generated
C/H changes are +3,064/-2,910 across eight files; these include regeneration
and source-location changes, not a bootstrap refresh or authored simplification.

The largest new mechanism is the complete-initializer token lookahead in the
existing macro owner. It reuses name recognition and token groups but creates
a second timing boundary before declaration completion. It handles direct
applications; it does not replace the existing expansion owner's treatment of
forwarding or argument macros. Its incompleteness prevents adoption regardless
of its small source footprint. An unused pending shortcut in MacroMatcher was
removed during review; existing macro-case recognition supplies that operation.

Final matched-import measurements use the same `cc`, one job, source-prelude
conditions on both snapshots, alternating runs, one warm-up, and three measured
pairs. The seven programs contain 1,838 physical input lines. The prototype
also translates its 24-line component; the baseline imports a neutral provider
with identical runtime imports. Both snapshots lack a usable prelude interface
in this controlled comparison, so these are not converged publication timings.

| Workload | Baseline seconds | Prototype seconds | Change |
| --- | ---: | ---: | ---: |
| Seven-program translation batch | 0.972951 | 1.019777 | +4.8% |
| Seven clean program builds | 6.776979 | 7.099010 | +4.8% |

These elapsed times include the external component/helper deployment. They do
not measure a linked builtin, CPU instructions, runtime throughput, or a full
compiler build. Earlier access synthetic results remain separate evidence:
`a56da260` native 0.272705 -> 0.296150 seconds; access 0.625364 -> 0.919493
seconds. They cannot be combined with this prototype's timings.

### Adoption sequence and acceptance

1. Establish a complete `$auto` boundary with the forwarding and constructed
   cases, full compatibility corpus, diagnostic locations, and representative
   compiler builds. Preserve the existing spelling and semantics.
2. Only after successful replacement, remove the auto claim registration and
   old component target, claim expression/transform dispatch, claim-only parse
   handlers, and claim-tag hook parsing. Keep declaration scanning/splitting,
   shared type handling, initialization conversions, and ordinary defer.
   Claim inspection in the declaration scan would become generic pending
   inspection. Keep member hooks while delegation still uses them.
3. Complete delegation through the same authoring principles. Preserve
   recursive lookup, ambiguity, precedence, and completion, then retire the
   remaining salvage hook infrastructure.
4. Compare region-row lowering independently. Its single producer does not
   establish that direct lowering is simpler.
5. Resolve the five known fixture failures before accepting the combined
   architecture: foreign-alias-body, generated-name-hygiene, keyword-aliases,
   macro-construction-regressions, and macro-template-lexical-shadow.
6. Review the three-feature implementation, total authored source cost,
   generated output, and representative performance. Then resume extraction
   with printf Var formats. Retain features in the kernel when moving them
   increases the total burden without a concrete benefit.

Everything remains local on `gwf/language-components`. No push or dev/main
integration is authorized. The existing build remains available for testing;
the incomplete prototype does not replace it.

## Third iteration acceptance

Gary requested an executable revision after reviewing the second spike. The
review demonstrated four failures: registration discarded exact patterns,
replacement binding suppressed independent rewrites, the local Code.type
adapter failed ordinary meta linking, and declaration splitting duplicated
shared qualified structs and enums. The revision must correct those cases.

- Components use parsed macro patterns and quotations. Remove the access
  constructor wrappers and the component's raw declaration splitter.
- Registration derives a cheap candidate key but retains the complete
  structural/type pattern. Test rejection as well as acceptance, and compose
  independent rewrites through their quoted replacements.
- Give fundamental Type operations one library owner. Compiler-dependent
  Code queries use actual compiler-supplied methods, not local adapters.
- Keep shared declaration identity and initialization order with their
  existing compiler owner. Exercise comma sequences and shared inline types
  through the new extension path, not merely through unmodified declarations.
- Exercise access, delegation, arithmetic, statements, and sequences together.
  Identify kernel responsibilities and unsupported cases explicitly.
- Review the authored source before accepting the results. Green examples
  alone do not approve an interface or establish performance.

This iteration stays local on `gwf/language-components` for Gary's review.
It does not authorize production extraction or publication to `dev` or `main`.

## Current iteration

The [executable revision](../../experiments/language-components/README.md) is the
review entry point. It removes access constructor wrappers and the component's
raw declaration splitter, moves pure Type operations to `lib/type.x`, and uses
compiler-backed Code methods. Ordinary source operations activate the included
components. Typed/literal applicability and independent composition are tested.
The registry retains macro recognition, including binding identity policy.

Read the report's kernel boundaries and remaining scope before approving an
API. In particular, post-initialization policy is not initializer-only `$auto`,
and late access selection retains the getter signature established by the
kernel. Full SDK migration and production feature extraction remain held.

The second spike passed eight examples and 40 focused fixtures but omitted
cases that exposed its pattern, composition, method-linkage, and declaration
identity defects. Those results are historical evidence, not API approval.

## Goal

The compiler kernel keeps the core language machinery. The working goal is
to move language policy into loosely coupled components, with a concrete case
for each additional responsibility retained in the kernel. Each component is one single-purpose file,
written with ordinary code literals and methods on captured code and types,
wired into the compiler by a registration
that says "when you meet this construct, call this, and use its result."
A user can write a component in the same form and include it; a shipped
component is the same idea compiled into the compiler. Everyone uses the
same library types and compiler-backed methods. Components do not reach
compiler internals directly.

## Kernel

1. Lexer and C parser.
2. Binder: scopes, names, identifier resolution.
3. Typing: the conversion engine. Ordinary member resolution is a proposed
   retained responsibility, subject to the boundary comparison below.
4. Control flow and cleanup: `defer`, `try`, `catch`, `finally`, regions,
   transfers, label ancestry, and volatile preservation.
5. Macro and meta substrate: expansion, hygiene, quotations, meta
   execution.
6. Unit assembly: imports, interfaces, pending-code destinations, emission.
7. Generic pattern dispatch justified by the demonstrated components.

`try`/`catch`/`finally` stay in the kernel on this branch, as on `dev`.
Whether they later become a component is Gary's open decision; nothing in
this plan depends on it.

## Component authoring and dispatch direction

The salvaged `hook node`, `hook claim`, and `hook member` declarations are
implemented branch state, not the approved developer-facing contract.
Renaming their parameters to Code and Type does not resolve their design.

The settled direction is:

- One feature owns its algorithm in `src/component-NAME.x`; an included
  user component must use the same authoring facilities.
- Registration uses ordinary macros, decorators, and meta operations rather
  than introducing a new `hook` keyword. A decorator can capture the
  following translator function and register it for the relevant construct.
  The underlying registration operation still requires design and proof.
- Authors recognize code with parsed macro patterns: named or anonymous
  macros with binder patterns supplied to their holes. Examples must not
  require knowing the internal declaration/operator/call List layout.
- Authors build replacements with code literals and query Code/Type methods.
  Do not mix public constructors, Lisp AST building, and raw AST matching
  into a purported ordinary developer example.
- Declaration handling must demonstrate how `$auto` finds its enclosing
  declaration, preserves its binding and initialization, and contributes
  the deferred cleanup. An unexplained `claim` marker is not an accepted
  answer. Establish whether current capture/decorator facilities suffice
  before proposing any primitive that they lack.
- Delegation must be expressed through declared receiver/field relationships
  and normal method/signature lookup. Do not assume every missing method
  should scan a global chain of arbitrary callbacks. Trace the existing
  symbol-table operations before choosing registration and dispatch.
- Use current behavior and generated C as the comparison baseline. Gary
  permits deliberate semantic revisions; present each proposed difference
  and its rationale before implementation. Unaffected behavior stays stable.
  Report kernel lines removed against component lines added for each move.

### Kernel boundaries and semantic flexibility

Gary's latest direction permits justified kernel responsibilities and deliberate
language changes. Extraction is not an absolute requirement. Present the case
for retaining an operation before committing to that boundary. Existing tests
and generated C establish the baseline; they do not prohibit a chosen semantic
change. Record any chosen change in the specification and its expectations.

The [boundary comparison](language-components-authoring.md#proposed-kernel-boundaries)
recommends initially retaining ordinary call resolution and shared update
mechanics. Delegation and arithmetic/access selection remain component policy.
These are recommendations for discussion, not approved compiler changes.

The next design experiment must compare delegation, indexed updates, and
statement rewriting together. Establish the complete authored pattern and
replacement for each, the smallest missing operation, and the normal compiler
continuation. Resolve typed-pattern derivation and preservation of relevant
source structure before implementing the shared registration system. Do not
make full dot-method extraction a prerequisite for proving useful extensibility.

### Survey authored extensions before choosing a common API

The first [authoring study](language-components-authoring.md) contains
executable probes for registration, dot calls, indexing, updates, and cleanup,
with exact distinctions between existing facilities and missing connections.

Binary plus illustrates dispatch; it does not define the architecture.
First survey several different uses. Author enough of each extension to
expose its required captures, queries, replacement, and compiler phase.
Then compare them before choosing the shared interface. Do not complete a
plus-specific framework and attempt to fit the remaining cases into it.

| Use case and source shape | What its component must do | What the example must establish |
| --- | --- | --- |
| Typed binary operation: `a + b` | Match operand/type constraints and build the appropriate operation call. | Native operations fall through; unrelated operators never consider the registration. |
| Dot method: `receiver.method(args)` | Resolve a function binding and signature, adapt its receiver through existing conversion rules, and construct the call. | Assess moving dot-method interpretation itself, not merely handling a lookup miss; preserve ordinary fields, callable fields, aliases, protocols, imports, and ambiguity behavior. |
| Indexed getter: `receiver[index]` | Select the getter from receiver/key types and construct the read. | Native pointer/array indexing stays native; result typing comes from the selected signature. |
| Indexed setter: `receiver[index] = value` | Recognize the complete assignment, resolve the setter, and construct the store. | The left side remains an assignment target until its use is known; assignment result and conversions retain current semantics. |
| Update: `receiver[index] += value`, `++receiver[index]`, `receiver[index]++`, and direct `Var` updates | Select existing update operations or construct the required update while retaining the target. | Evaluate base/key/target expressions once, preserve applicable operand ordering, distinguish old versus stored result, and preserve failure-without-mutation behavior. Do not assume getter-plus-setter is equivalent. |
| Managed local: `T local = $auto(value)` | Obtain the declaration's binding and contribute deferred cleanup in its enclosing scope. | Establish how context is supplied without an unexplained claim marker; retain initialization and cleanup order. |
| Statement rewrite: string or pattern switch | Recognize the statement and replace its control flow. | Preserve subject evaluation, label ownership, and nested control flow; expose requirements not covered by expression rewrites. |

Field delegation extends the dot-method case. Describe eligible receiver/field
relationships declaratively and use ordinary binding/signature lookup. Do
not turn this into a global callback scan. Property getters/setters, if
supported by the proposed mechanism, must distinguish field reads, writes,
and updates without silently promising a new language feature.

The shapes in the table describe source cases; they are not a new macro
syntax or finalized registration spelling. Author the real patterns through
named or anonymous macros, including typed expressions and binder holes.
The same macro definition serves construction and structural/path matching.
The example modules must use ordinary parsed code literals for replacements
and Code/Type methods for required semantic information.

For each representative case show the included module, macro definition,
decorator and registration call, rewrite body, user program, and resulting
compiler path. Identify existing operations and precise missing primitives.
A schema, raw AST construction, or body containing placeholders does not
complete the example. Compare the examples' requirements before fixing
public names, callback signatures, or dispatch families.

### Derive compiler placement from the semantic context

A uniform authoring style need not imply that every rewrite runs in one
late pass after the entire expression has a type. Current source establishes
several distinct contexts:

- Dot calls resolve the receiver and method signature before finishing the
  call's result type (`src/expressions.x`, `CallSite._lookup` and
  `Compiler.resolve_postfix_member`). Recognize the call/member path with
  the necessary receiver facts; do not require an already resolved method
  call before permitting the component to resolve that method call.
- Index admission resolves receiver/key information before later getter
  lowering (`Compiler._resolve_indexed` and `src/transform.x`). An indexed
  target may subsequently appear under assignment or prefix/postfix update.
  Do not eagerly erase its target structure by replacing every occurrence
  with a getter call.
- Existing indexed and Var updates use specialized runtime operations.
  They preserve conversion, failure, storage, and result semantics described
  under dynamic compound assignment in the language reference. Reuse these
  operations when extracting the language interpretation; a generic
  read/compute/write expansion is not automatically equivalent.
- Managed declarations and statement rewrites expose scope and control-flow
  requirements that an expression-only survey cannot establish.

Use the existing enclosing syntax and semantic operations to preserve these
contexts. Introduce a new context object or target abstraction only if the
authored examples establish a need that existing Code/Type operations cannot
serve. Define applicability and placement together; do not accumulate ad hoc
exceptions to a prematurely chosen universal callback.

### Classify patterns once; dispatch at the relevant operation

The developer supplies the structural pattern, not a duplicate dispatch key.
At registration, match that pattern against a small set of metapatterns
using the existing macro-pattern machinery. For example, recognizing the
outer form as binary `+` places its registration in the binary-plus registry.
This examines the pattern's structure; it does not execute the rewrite.

At compilation, use the compiler's existing classification of the source
operation and its enclosing use where relevant. Once ordinary processing
reaches binary `+`, it checks the binary-plus registry and invokes the generic
evaluator only for those candidates. A dot-call pattern can use the call's
member-access shape; an indexed setter or updater can use the enclosing
assignment/update plus its indexed target. These are candidate derivations
to prove with the survey, not separate author-maintained registrations. Other expression kinds and operators do not test these patterns
or call their functions. An empty registry has a cheap no-handler path.
Do not walk all patterns or run user predicates at every expression.

Coarse dispatch is not a full match. The candidate evaluator applies the
registered structural/type pattern, and an applicable rewrite receives the
whole expression. A binary-plus pattern constrained to particular types
must not rewrite every addition. Demonstrate an accepted plus expression,
a plus expression rejected by its type pattern, and an unrelated operation
that never considers this registration. This work happens during compilation;
it adds no runtime dispatch to the generated program.

Derive the small set of internal dispatch families from the full survey
and existing compiler branches. Binary operators are one family, not the
model all other cases must follow.
Gary expects a small set, potentially fewer than a dozen; that is a design
expectation, not an established inventory or a reason to invent categories.
The registration classifier owns the mapping from structural patterns to
these internal families. Do not make authors maintain both descriptions.

The worked examples must establish the phase at which the relevant types
are available, preservation of binding identity and evaluation order,
replacement placement, overlapping registrations, and how a replacement
avoids being reapplied indefinitely. Reuse current language semantics for
these issues wherever possible; do not hide unresolved choices in a new
marker, callback, or undocumented helper.

The current branch only supports switch node hooks. That limit does not
establish general pattern registration. The current member hook runs after
a method lookup misses, trying handlers in order until one accepts; it is
not receiver-indexed. Claims are internal initializer markers consumed when
a complete block-local declaration is processed. These are observations of
the salvage, not arguments for retaining it.

## API correction before extraction

The salvage proves the hook mechanism and behavior preservation. It does
not approve the existing SDK organization or the pattern helper contract.
This correction replaces that organization before more components adopt it.
The component registration/dispatch redesign above must be established first;
the implementation sequence below does not authorize retaining the rejected
contract merely while changing SDK names.

### Representations and names

- `Code` names captured code: an alias for the existing immutable List-based
  AST representation. Reuse the representation and its lifetime; add no
  wrapper, origin marker, ownership protocol, or parallel AST.
- `Macro` continues to mean a macro definition that builds or recognizes
  code. It is not the name for every captured AST node.
- `Type` remains the existing canonical semantic type representation.
  Share its declaration and reusable methods between compiler and library.
- Keep `Source` and `TypeInfo` distinct where their current capture behavior
  supplies metadata rows rather than one AST node or semantic type. Their
  contents are not made into Code by renaming them.
- A Code's `category()` reports its syntax category. Its `type()` returns
  its semantic Type using the current typing owner. Do not confuse an
  expression's syntax category with its value type.

### Construct code with the language

Replace the literal, expression, statement, block, declaration, and parameter
constructors in `lib/meta.x` with existing parsed code literals at their
callers. Use type holes, name holes, and sequence splices already supported
by quotations. Use typed quotations where a component contributes already
lowered expressions. Preserve the plan's placement and binding order.

Delete the redundant public constructor definitions after migrating their
callers, documentation, compiler adapters, and generated inventory. Do not
leave a second permanent constructor vocabulary or a compatibility wrapper
layer. Keep direct canonical List composition where the algorithm actually
manipulates AST structure; it is not grounds for another public builder API.
Identifier spelling checks and hygienic fresh bindings are separate operations
from building an expression and retain their existing compiler guarantees.

### Candidate query owners, justified by clients

The following table maps the existing SDK to likely owners. It is not an
API implementation checklist. Add or move only operations required by the
authored examples and their real consumers; reuse existing methods first.

| Current family | Revised owner and operations |
| --- | --- |
| Captured syntax | `Code.category()`, `Code.type()`, `Code.literal_value()`, `Code.binding_spelling()`, and `Code.source_text()` |
| Captured function | Code methods for `name()`, `parameter(name)`, `body()`, and forwarding `arguments()` |
| Semantic type | Type methods for `fields()`, `layout()`, `parts()`, `resolve()`, `members()`, `is_value()`, `is_integral()`, `is_pointer()`, `element()`, `parameters()`, and `return_type()` |
| Member and protocol lookup | Methods on the participating Type, preserving current binding identities, ambiguity results, and lookup order |
| Recorded facts | Methods on the subject Type, preserving the existing scope lifetime and visibility |
| Pattern expression inspection | A Code method for its pattern value, preserving the current static/dynamic distinction |

Reuse existing Type methods and their algorithms; do not create matching
implementations with different names. Move context-independent operations
needed by clients into a library owner, such as `lib/type.x`. Compiler-state
queries remain backed by the current compiler context through method
prototypes and the existing nested meta request. Expose no symbol table,
Compiler object, or new session context to the component author.

Method spelling alone does not complete the correction. Update parameter and
return types so captured code is Code and semantic types are Type at the
public boundary. Preserve List for genuine sequences and metadata rows.
Prove that method dispatch and quotation hole classification retain those
roles for typedef aliases before adopting the declarations throughout clients.

Keep invocation location, expansion effects, dependency-tracked file reads,
and fresh-name allocation as a small set of helpers where no captured value
owns the operation. Compiler provider hashes belong to compiler plumbing,
not the ordinary component authoring surface. Do not invent receiver objects
just to turn every remaining helper into a method.

### Establish the purpose of pattern lowering

The salvaged `meta-patterns.x` emits ordinary tests for a static subset of
List patterns. Runtime Match already recognizes patterns; these helpers
serve a different purpose: generating control flow inside a component.
That purpose must justify their existence and placement.

The current public `(STEPS BINDERS CURSORS)` return contract is not accepted
as the final component API. It makes the caller manage lowering internals,
cursor declarations, fresh-name effects, and nesting separately.

Use the included switch component as the concrete client when revising it.
Keep pattern inspection on Code. Keep lowering helpers private to their
actual algorithm until an existing second client establishes shared work.
A shared library operation must produce usable Code with its required
name effects accounted for, rather than require the caller to reconstruct
cursor machinery from three lists. Preserve binder scope, capture order,
first-match behavior, and exactly-once subject evaluation. Do not broaden
the supported pattern subset or port the spike's catch selector or try
component. If ordinary quotations and existing Match operations can replace
this machinery while preserving generated C, prefer that deletion.

### Work sequence

1. Survey the authored cases above together: operators, full dot-method
   interpretation, getters, setters, updates, managed declarations, and a
   statement rewrite. Use the advanced macro and quotation forms; record
   each case's captures, semantic queries, placement, and output obligations.
2. Compare the cases and derive the smallest shared API. Separate shared
   Code/Type capabilities from operations required by only one case. Choose
   representative complete examples that establish each distinct semantic
   context; do not let the first example determine the whole architecture.
3. Work backward through registration-time metapattern classification,
   operation/context-local dispatch, full pattern matching, replacement,
   and normal compiler processing. Use focused probes to establish meaning
   and candidate-call behavior. Settle overlap, decline, and replacement
   reprocessing without adding feature-specific registration languages.
4. Map affected consumers and reusable Code/Type operations. After the
   concrete design is established, implement its minimal compiler connections,
   migrate clients to code literals and methods, and delete superseded
   constructors and registration machinery. Update native and nested-request
   paths together. Surveying dot methods is not authorization to silently
   expand the subsequent extraction batch.
5. Reassess `meta-patterns.x` against demonstrated consumers. Retain no
   public cursor/step bookkeeping solely because the salvage implemented
   it. Update library registration and documentation with the final design.
6. Review and fix the completed authored diff. Run the existing focused
   and handoff checks below, regenerate through the owning targets, and
   record generated-C comparison coverage and source counts.

This is an API migration on the held branch, not a new language feature.
Binding identity, type queries, existing feature diagnostics, completion,
and generated program behavior keep their existing semantics. The component
registration contract and public call spelling change intentionally under
Gary's correction. Inventory external
or documented consumers rather than silently leave them on the old surface.
If a literal replacement changes generated C, isolate the specific lowering
or placement cause instead of assuming quotations cannot replace builders.

## Salvage from `gwf/hooks-spike`

Each item is ported into the structure above, not cherry-picked. Spike
commits are cited for reference.

| Step | Item | Spike source |
| --- | --- | --- |
| S1 | Effects as x2c calls: `x2c_code`, `x2c_fresh_name`, `x2c_effect_name`, `x2c_effect_support`, `x2c_effect_initialize` | e548e06a |
| S1 | Node diagnostics with a category: `x2c_diagnostic_fail_at(node, category, message, notes)` | e548e06a, d45c110b |
| S1 | Typing queries from project meta code through a nested request | eb89dcf6 |
| S1 | Region interface in the cleanup walk, with the `try` lowering kept in the kernel on it and `defer`'s landing lowered in the kernel | 4a0b198e (without its move into builtins.x) |
| S2 | The single hook mechanism with the `node`, `claim`, and `member` points, replacing the spike's five separate mechanisms | 87354c57, 441eaece, 1f7618fe |
| S2 | Built-in registration fixes: keys survive the cached reinstall; built-in targets name compiled-in functions; the typed-hook flag is set on both install paths | 441eaece, 9cae0fa1 |
| S2 | Fact registration and lookup: `x2c_fact_record`, `x2c_fact_lookup`, `x2c_member_resolve` | 1f7618fe |
| S2 | `$auto` as `src/component-auto.x` on the `claim` point; the `managed-init` node and its five special cases deleted | 441eaece |
| S2 | `delegate` as `src/component-delegate.x` on the `member` point; the kernel delegate search deleted | 1f7618fe |
| S3 | Pattern values and the shared static-pattern lowering: `x2c_pattern_value`, `x2c_pattern_steps`, `x2c_pattern_nest`, with a fixture client | 2e1bde62, c1ba2997, df25119f |

### Not carried over

- The `try` component and the catch selector built inside it.
- The parse-phase hooks (`hook switch $m;`, `hook function $m;`) and the
  spike's separate `claim:`, `cleanup:`, and `fallback:` mechanisms.
- Components placed in `src/builtins.x`.
- `Compiler.convert_at` (kernel-internal; Gary's open decision).
- The user-space prototypes in plans/hooks-spike/; they stay on the spike
  branch as references.

## Feature extraction order (for the next agent)

After the API correction is implemented and reviewed, move one feature per
change into its own component file,
in this order: printf Var formats, collection literals, `raise`,
destructuring, string interpolation, runtime static locals, `foreach`,
`with`, `class` defaults, `match` (reusing only the pattern operations justified above), lambda
lowering, protocols with their adapters. Each move follows the contract
and its proof. Classification and touch points per feature are in
`plans/hooks-spike/feature-modules.md` on the spike branch.

## Validation

- Per salvage step: `make build`, focused fixtures for the step, and
  byte-identical generated C for src and lib (a two-round local bootstrap
  refresh, then `make stage-diff-0`).
- Before handoff: `make verify`, `make doc-check`, converged bootstrap,
  generated docs refreshed, clean tree, branch pushed.

## Plan review

The parser establishes code-literal structure; the binder establishes name
identity; typing establishes semantic types. Code methods reuse those facts
and existing lookup owners. This plan adds no second AST validator, syntax
origin test, or consumer recheck of established typing facts.

The correction deletes redundant constructor vocabulary and prefixed query
wrappers. It reuses canonical List-based ASTs, Type methods, quotations, hook
dispatch, and the existing compiler-state meta bridge. The Code alias gives
captured syntax a public owner without changing storage. Library moves share
pure algorithms rather than duplicating compiler implementations.

Pattern lowering must earn its shared placement through concrete clients.
Its cursor machinery is implementation detail, not a caller obligation.
Registration derives candidate dispatch from the authored macro pattern once;
existing compiler operation dispatch narrows the candidates before matching.
This avoids a second author-maintained description and global callback scans.
Ordinary literals, methods, and included modules keep the design idiomatic
x2c. No framework, registry beyond existing hooks, cache, new validator,
dedicated diagnostic, or recurring gate is proposed. Existing diagnostics
and negative fixtures continue to protect their established public behavior.

## Log

- 2026-10-08: plan written on `gwf/language-components` from 7e946b86.
- 2026-10-08: S2 salvaged on `s2-hooks`: one `hook` form and dispatch path
  for `node`, `claim`, and `member`; facts; `$auto` in
  `src/component-auto.x` and `delegate` in `src/component-delegate.x`; the
  `managed-init` node and the kernel delegate search deleted.
- 2026-10-08: continuation applied the S2 authored patch from 8c16e887
  through 802db199 onto b933e6b9 with `git apply --index -3`; no conflicts
  and no changes to `src/cleanup.x`. `make build`, two rounds of
  `make bootstrap-refresh` and `make build-safe`, and `make stage-diff-0`
  passed (260 C/H files). All 228 selected compiler fixtures passed,
  each through `run.sh check --fixture NAME`.
- 2026-10-08: baseline comparison against b933e6b9 found 112 unedited
  generated C modules byte-identical and three different: `compiler.c`
  (imported keyword-parser return type), `meta-native.c` (new compiler API
  targets), and `linked-meta.c` (dependency metadata). The baseline copies
  of all three matched the shipped bootstrap. Work paused for clarification
  of the byte-identity requirement before further implementation. The local
  S2 integration is uncommitted and unpushed. Completion restoration, a
  reported delegated-ambiguity note ordering difference, S3, and final
  handoff checks remain. Existing src files have 274 removed and 291 added
  lines (net +17); the two new component files add 184 lines. Full deltas
  and logs are in `debug/s2-*`; fixture names and comparison details are in
  `.context/language-components/`.
- 2026-10-08: Gary accepted the reviewed prototype, API-adapter, and
  dependency-metadata differences. Those deltas persist in the completed
  compiler; they are not transient bootstrap drift. S2 now restores direct
  member completion. A baseline probe established that delegated imported
  method notes already matched S2 (delegate path before package notes);
  the proposed order change was rejected and reverted. A REPL API check
  covers delegated calls with unchanged completion output.
- 2026-10-08: S1-A is recorded by 8ebbceae with bootstrap 8c16e887;
  S1-B by 43c63b27 with bootstrap b933e6b9. This continuation preserved
  both and verified their meta and cleanup fixtures in the requested S2
  set and in the final complete verification.
- 2026-10-08: S2 integrated as ee5b1c94; 7cfd5f60 restores the original
  imported-delegate diagnostic order after a baseline probe rejected an
  incorrect review suggestion. The REPL checks passed, including delegated
  calls while completion continues to list only direct members.
- 2026-10-08: S3 integrated as b428f271 from worker 9a54ea77. The optional
  `lib/meta-patterns.x` provides pattern steps and nesting, and the SDK
  provides pattern values. The included `hook-node-patterns` component uses
  the existing switch hook. No catch selector or try component was ported.
  a1ecee20 (worker f575ca4d) fixes a reproduced missing-element case: a void
  type predicate previously matched an absent List cell although runtime
  Match rejected it. The fixture now proves that agreement. 7fe1b4a4
  documents the compile-time-only steps API in the module design notes,
  because the existing API table projects runtime function definitions.
- 2026-10-08: 8924481e refreshes bootstrap, linked meta, and generated
  references. Final `make doc-generate`, `make doc-check`, `make verify`,
  and `make stage-diff-0` passed. Verification completed 1113 compiler
  fixtures (2488 artifacts), 942 unit tests (25024 assertions), and the
  existing boundary probes. Bootstrap and stage 0 match in 262 C/H files.
  An earlier unconverged run failed AST/symbol snapshots; the converged
  run passed without changing any existing fixture expectation.
- 2026-10-08: the final compiler generates byte-identical C for 113 unedited
  src/lib modules, all 91 examples, and 134 package source specimens.
  The reviewed imported prototype and compiler API inventory deltas remain;
  linked-meta changes are generated provider data and the new pattern code.
  All 231 tracked example/package inputs were attempted. Six produced no
  standalone C in either compiler: two intentional autodiff rejection
  fixtures and four Cstar proof inputs; their ordinary Cstar clients match.
  Evidence and exact commands are in `.context/language-components/`;
  full validation and failure logs remain in `debug/salvage-*` and
  `debug/s2-*`/`debug/s3-*`.
- 2026-10-08: final authored src counts against b933e6b9, excluding generated
  linked-meta and the new components: 274 lines removed, 296 added (net
  +22 for the hook/fact/query infrastructure). The auto and delegate
  components add 184 lines. S3 adds the optional pattern library and six
  SDK adapter lines; it removes no kernel feature. Salvage and handoff
  are complete. The next work is the listed feature extraction order,
  starting with printf Var formats, one feature per change and component.
- 2026-10-08: paired performance checkpoint on the same host used four
  alternating runs of each unchanged example with both converged preludes.
  Median retired instruction counts (baseline b933e6b9 versus candidate
  8924481e), including the translation command and its native work:
  `examples/power/bindings.x`: 1,953,385,580 versus 1,967,183,230
  (+0.71%).
  `examples/power/scopes.x`: 2,031,508,664 versus 2,041,154,414
  (+0.47%).
  `examples/power/exceptions.x`: 1,985,307,702 versus 1,991,637,030
  (+0.32%).
  `examples/love/methods.x`: 1,913,680,042 versus 1,924,121,486
  (+0.55%).
  This is translation evidence for four examples, not a full-build timing.
  Raw samples are in `.context/language-components/performance.json`.
  Delivery remains limited to `gwf/language-components`; dev and main
  are not integrated or advanced by this continuation.

- 2026-10-08: after local salvage and before publication, Gary requested
  an API redesign. Parsed code literals replace redundant constructors;
  captured Code and semantic Type own query methods. Macro retains its
  macro-definition meaning. The current pattern helper bookkeeping is
  superseded as a public contract. This revision records the correction;
  no implementation of the revised API has begun and nothing was pushed.
  Feature extraction remains held until this correction is reviewed.

- 2026-10-08: Gary rejected the component contract as insufficiently
  designed, not merely difficult to explain. The earlier revision retained
  the hook/claim/member machinery and therefore did not address that concern.
  Registration through decorators/meta calls, recognition through macro
  patterns, declaration capture for auto, and declarative delegation need
  complete developer examples and traced execution before a replacement
  contract is selected. The plan now marks that design as unsettled; no
  compiler implementation was changed or published.

- 2026-10-08: Gary specified use-case-driven authoring and operation-specific
  dispatch. Begin with a typed binary-plus macro pattern; derive the minimal
  API from the complete extension. Registration recognizes its outer shape
  through metapatterns once and selects the binary-plus registry. Existing
  compiler dispatch reaches that registry only at plus expressions; full
  structural/type matching determines applicability. The revised work order
  now puts this concrete example before API inventory and migration.

- 2026-10-08: Gary broadened the design survey so binary plus cannot become
  the architecture by default. The cases now include complete dot-method
  interpretation, indexed getters/setters, direct and indexed updates,
  managed declarations, and statement rewriting. Source review identifies
  call typing and indexed-target preservation as requirements absent from
  simple binary replacement. Public APIs and dispatch families must follow
  the compared use cases, with no new feature implementation in this revision.

- 2026-10-08: completed the first compared authoring study in
  `language-components-authoring.md`. Independently ran decorator/metapattern,
  dot-call, getter/setter, update, and declaration-cleanup probes. Discovered
  that ordinary Expr capture is too late for source dot/index patterns and
  current typed quotations do not construct binder-aware typed patterns.
  No compiler or library source changed; automatic dispatch remains unproved.

- 2026-10-08: second spike checkpoints: `d2ab80dd` typed-pattern composition;
  `5e31716b`/`b9fd3be0` declaration and statement sequences;
  `3b054707`/`657f3614`/`00a8fcbf` receiver-scoped forwarding and access probes;
  `d355b75b` automatic decorator registration plus capture/rollback repairs;
  `83eadac3` scope-preserving explicit sequence macros. Integrated runner: 8/8
  programs, including the combined client. Existing focused fixtures: 40/40.
  Compiler delta against `7cde13c9`: +58/-5 lines; pattern library +4; six
  component/support modules 239 lines. No kernel feature removed. Everything
  remains local; bootstrap and dev/main were not changed.

- 2026-10-08: third executable iteration, following Gary's source review.
  Local checkpoints: `eccd5fa6` moves pure Type operations and retains complete
  pattern dispatch; `2ef2114e` exercises ordinary source and typed patterns;
  `a3b2e215` reuses macro recognition with binding identity and source views.
  Review entry: `experiments/language-components/README.md`; start with
  `combined.x` and its four included components.

  Removed access constructor wrappers, component AST splitting, local Type
  forwarding, the separate forwarding registration, and global rewrite
  suppression. Registration retains a Macro and hole patterns, derives its
  operation key once, and uses the existing macro matcher before calling a
  translator. Typed constant quotations fold at their existing producer.
  Unsupported ordinary assignment patterns reject at registration. The
  declaration owner preserves binding and shared type identity; components
  return only post-initialization statements. Late access replacements retain
  the getter result type; a double replacement for an int getter now rejects
  at the source statement rather than silently changing its parent's result.

  Root verification: `make build`; 14/14 executable examples with exact stdout,
  empty stderr, and successful exits; eight focused fixtures rerun after final
  matcher integration; `make doc-generate`, `make doc-check`, and diff whitespace
  checks. Example logs: `/tmp/x2c-components-44_3yhx4`.
  The broader 269-fixture sweep passed 263 after renaming a test-only `Code`
  typedef to `Nonrecord`. Six failures reproduce with byte-identical actual
  artifacts on baseline `0e114f9a`: catch-filter-arms, defer-only-cleanup,
  defer-try-cleanup, keyword-aliases, meta-globals, and meta-records. Their
  checked-in expectations were not changed.

  Bounded generated-C comparison against `0e114f9a`: seven unchanged fixtures
  produced byte-identical C (managed-init-runtime, macro-declaration-helper-controls,
  delegate-fields, protocol-typedef-inherited-adoption, meta-sdk,
  meta-type-parameter, protocol-operator-direct-update). Two macro-value cases
  differed only in checkout-derived source paths or include guards. This is
  not a whole-tree equivalence result. Full logs remain in `debug/iteration3-*`.

  Physical source-line delta against `0e114f9a`: compiler +297/-673, including
  src/type.x +5/-616 and the 617-line library Type owner. Excluding that move,
  compiler integration is +292/-57. Seven component/support modules total 160
  lines, down from 245 (the earlier six plus the new initialization adapter).
  No production feature was extracted from the kernel in this iteration.

  Retained kernel boundaries and unfinished cases are explicit in the review
  entry. Initializer-only auto, ownership transfer, recursive delegation and
  ambiguity, full dot-method extraction, complete string switch, and older SDK
  removal remain unfinished. No throughput claim, bootstrap convergence, full
  publication gate, or push was attempted for this local review iteration.
  Everything remains on `gwf/language-components`; dev/main are untouched.

- 2026-10-08: Gary authorized the first builtin migration: collection access.
  Compare against a56da260. Preserve nominal read overrides, alias-aware
  Array/Map mutation, all compound operators, numeric operand rejection,
  stored tags, failure atomicity, and native/custom-protocol boundaries.
  Generic getter admission and protocol sequencing remain kernel owners.
  Use ordinary macro registration and quoted helper calls, remove replaced
  collection mutation branches, compare generated C, and measure converged
  compilers. Keep the change local on gwf/language-components.

- 2026-10-08: first builtin collection-access candidate, checkpoints
  `fa68a538` and `bdcbfea1`, against `a56da260`. The
  [measurement report](../../experiments/language-components/builtin/README.md)
  records the implementation, kernel boundary, source counts, and evidence.
  Explicit protocol adoption, self-call suppression, user-before-builtin
  ordering, installed payload, and script dependency classification were
  repaired. Sixteen examples and 942 runtime tests pass. Selected fixtures
  pass 21/23; bootstrap converges across 268 C/H files. Documentation checks
  pass. Full verification was attempted but fails on changed output; fixture
  expectations remain unchanged and publication stays held.

  Two seven-pair warm translation runs measure about 7.5% native overhead
  and 1.62x access-heavy time. `src/transform.x` shrinks by 60 lines, but the
  132-line component and 68 net lines elsewhere in the compiler leave a
  net compiler increase of 140 lines, excluding generated code. Native C/H
  matches exactly; collection C adds helper prototypes while the measured
  function bodies match. This does not satisfy byte-identical generated C.
  The next review must address these costs and that output condition before
  treating this candidate as an accepted extraction. No push or dev/main
  change occurred.


- 2026-10-08: continued the held builtin candidate with profiling, optimization,
  and complete fixture coverage. Checkpoint `c1e06211` prepares registered
  macro patterns once when independent of subject bindings. Context-dependent
  patterns retain per-subject derivation and the existing identity rules.
  A new shadowing example returns `99 3 99`; all 17 component examples and
  942 runtime tests (25,024 assertions) pass. Two refresh/safe-build rounds
  converge across 268 C/H files. Documentation and whitespace checks pass.

  Two seven-pair measurements give access baseline/candidate elapsed times
  of 0.619467/0.896729 seconds and 0.620214/0.902955 seconds: 1.45x baseline,
  improved from the previous 1.62x. Native overhead remains about 7-9%.
  These measure warm translation of the documented synthetic workloads,
  not whole builds. The matcher adds 7 net compiler lines and 24 library
  lines; the overall compiler delta against a56da260 is now +147 lines.
  The kernel reduction remains 60 lines against the 132-line component.

  Individually checked all 1,113 fixtures: 1,108 pass. Three failures also
  occur on baseline a56da260. Candidate-specific failures are
  atomic-container-ops and var-helper-compound; bound helper calls change
  transform output and add prototypes. Native workload C/H is identical;
  access bodies and H are identical, with four additional C prototypes.
  No expectations changed. The complete publication gate remains unpassed,
  and strict generated-C parity remains unresolved. No push or dev/main
  change occurred. See the builtin measurement report for commands and limits.


- 2026-10-08: Repair declaration ownership for builtin collection migration.
  Source forwarding now credits public function rows of actual includes and
  runtime umbrella modules using the existing collector cache. Private include
  closures, semantic components, and meta-only signatures do not establish
  runtime declaration availability. Cyclic header inline forwards remain.
  Bound calls retain binding identity checks; no helper-name exception exists.

  The four added helper prototypes are removed. Native synthetic C/H remains
  exact; access H/bodies remain exact and C deletes seven older prototypes.
  Reviewed 129 C expectation deltas delete prototypes only, plus the migration's
  atomic-container transform and one header parameter diagnostic note.
  Authored compiler net is +197 against a56da260; component 132 / kernel -60.
  Final bootstrap matches all 268 C/H files. Runtime 942 / 25,024, threads
  23 / 89, and component examples 17 / 17 pass. Full individual fixtures are
  1,108 / 1,113; five failures reproduce on unchanged c6129e75. `make verify`
  remains failed on foreign-alias-body. No unrelated expectations changed.

  Twelve generation rounds preserve all 18 C/H/.xi artifacts (14,805 bytes),
  including fresh provider-interface replay. Cyclic inline headers compile and
  execute; three meta-helper runs preserve cache hashes. Final seven-pair warm
  synthetic times are native 0.272705 -> 0.296150 seconds, access 0.625364 ->
  0.919493 seconds (1.470x). This is not whole-build or runtime evidence.
  See the builtin report for exact output effects and logs. No further
  extraction, push, or dev/main integration occurred. Work remains review-held.

Local repair checkpoint: `afce06ef` (`track declarations supplied by emitted headers`).


- 2026-10-09: Remove the superseded pattern-step library, node-hook path,
  public effect builders, helper wrappers, and added initialization effect.
  Keep the internal carrier and its preexisting new-name/early operations.
  Port string-switch coverage to ordinary rewrite registration and static
  pattern cases to match; remove abandoned API-only tests. Net hand-authored
  production deletion: 325 lines (47 compiler, 262 library, 16 helper/build).
  Generated linked-meta removes another 170 lines. Bootstrap matches stage 0
  across 266 C/H files. Active auto/delegate mechanisms and region-row lowering
  stay for separate replacements. See the experiment report's cleanup section
  for behavioral coverage and final evidence. Work remains local and unpushed.
  Final checks: fixtures 1,106 / 1,111 with the same five baseline failures;
  examples 17 / 17; runtime 942 / 25,024; threads 23 / 89; documentation,
  whitespace, and bounded output/replay checks pass. Full verify remains
  failed on foreign-alias-body. Compiler-build timing was not attempted.
