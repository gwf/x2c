> Status: reference
> Research snapshot, 2026-10-04, against origin/dev
> 4107b60af83a67abb4ceb058d4d327ce13e36ce7; original baseline 272ba77c.
> Gary subsequently authorized private implementation. The main synthesis
> owns the current dev refresh, binder decision, changes, and verification.
> Historical statements below describe the investigation before implementation.
> Publication and a PR remain held for Gary.

# Compose container families without hiding their policies

## Recommendation

Keep the shared storage generators and the existing custom-family interface.
Apply the recent Array cleanup to the Map generator's unused internal slots.
Do not replace the Map callbacks with a family configuration framework.

The larger opportunity is to make each policy-bearing declaration explain
the generated behavior. Parameter count alone does not establish that a
generator is wrong. Maps have key, equality, hashing, traversal, and export
facts that contiguous Arrays do not have.

Keep the runtime effect table explicit for now. A new ledger solely to emit
its eleven paired typed-container conversion rows would add another owner
without eliminating the existing family declarations. Revisit that choice
when one shared row can replace declarations and effects together.

This plan settles the compatibility and ownership boundaries. It supplies
concrete implementation instructions for the small cleanup and a bounded
comparison for the larger policy presentation. It does not authorize either
implementation or a new recurring check.

## Baseline and method

The requested survey starts from origin/dev. The original investigation used
272ba77c3b3f02632d6ef7b633a2c861399e05ea. The parent session subsequently
pulled dev and fast-forwarded this checkout to
4107b60af83a67abb4ceb058d4d327ce13e36ce7. This refresh examines that complete
commit range, with detailed reads of the changes relevant to this plan.
Existing uncommitted planning documents were preserved.

The investigation read the container generators, all built-in invocation
families including the refreshed PoolTable consumer, custom-family fixtures,
their public documentation, integer and Var
update owners, and the relevant region table and its consumers. Repository
searches covered `.x` and `.xmacro` invocations outside bootstrap.

The shipped bootstrap C was inspected as historical generated evidence. It
is not a fresh translation or a current performance measurement. No compiler,
unit suite, fixture, benchmark, publication gate, or remote publication was
run for this planning-only task.

## Findings with exact source locations

Counts are physical source lines at the refreshed baseline, including
comments and blank lines. Range sizes describe the inspected mechanism, not proposed
deletions.

| File | Total lines | Relevant range | Range lines | Finding |
| --- | ---: | --- | ---: | --- |
| [map-generics.xmacro](../lib/map-generics.xmacro) | 961 | 354-618 | 265 | One operations generator mixes native and boxed policies through constant holes. Its `unbox` slot is never read. |
| [map-generics.xmacro](../lib/map-generics.xmacro) | 961 | 691-736 | 46 | The observation generator accepts five arguments but uses only `map`. |
| [map-generics.xmacro](../lib/map-generics.xmacro) | 961 | 503-556 | 54 | Update and postfix functions carry boxed/native admission, missing-key, numeric, and postfix policy branches. |
| [map-generics.xmacro](../lib/map-generics.xmacro) | 961 | 69-352 | 284 | Fourteen slots supply actual storage layout, callbacks, and error owners. These are not all incidental parameters. |
| [array-generics.xmacro](../lib/array-generics.xmacro) | 911 | 27-152 | 126 | Integer, floating, and String update generators state different native arithmetic policies separately. |
| [array-generics.xmacro](../lib/array-generics.xmacro) | 911 | 345-628 | 284 | Array also uses a boxed flag in common operations. It is not uniformly a policy-free counterpart to Map. |
| [array-generics.xmacro](../lib/array-generics.xmacro) | 911 | 668-708 | 41 | The observer already takes only the three facts it uses and calls ordinary Buffer owners. |
| [typed-map.x](../lib/typed-map.x) | 356 | 225-338 | 114 | Four built-in families repeat mechanical wiring, but String export bodies interrupt that family wiring for a real ownership reason. |
| [typed-array.x](../lib/typed-array.x) | 189 | 103-165 | 63 | Seven typed families compose storage, public operations, observation, update, publication, and iteration. |
| [list-generics.xmacro](../lib/list-generics.xmacro) | 102 | 23-102 | 80 | A typed List retains canonical List representation and inherits operations instead of generating storage algorithms. |
| [typed-list.x](../lib/typed-list.x) | 123 | 97-123 | 27 | Seven typed-list invocations state codecs and element tags explicitly. |
| [regions.x](../src/regions.x) | 1,455 | 165-180 | 16 | Four ordinary wrappers and eleven typed-container conversion pairs are explicit effects keyed by emitted C name. |

An initial survey called the Map operations signature fifteen arguments.
The checked count is fourteen: three Type slots, six Name slots, and five
Literal slots. The core signature also has fourteen: six Type slots and
eight Name slots. The Array core has two Type slots. Those counts describe
different algorithms and are not a direct complexity or cost comparison.

### Unused internal facts are the clearest inconsistency

`$map.typed.observation` at lines 691-736 accepts `map`, `key`, `value`,
`box_key`, and `box_value`. Its definitions reference only `map`. The
comparison and rendering work already belongs to methods generated by
`$map.core.observe`, which does need the field types and boxers.

`$map.typed.operations` at lines 354-618 accepts `unbox` but never reads it.
The enclosing `$map.typed.family` at lines 947-955 needs `unbox` because
`$map.typed.convert` names `Map.$unbox`. Keep that outer fact; stop forwarding
it into an owner that does not use it.

This is directly comparable to the October 1 Array change. Commit
27ee651f4 removed unused observer owner/new-buffer/finish-buffer slots, called
the ordinary Buffer operations, and moved typed Map scaffold generation to
the shared Map generator. The current Map observation split did not receive
the same unused-slot cleanup.

### Policy branches affect readability and generated text

Map `updateindex` selects absent-key insertion differently for boxed and
native values. Postfix selects the boxed Var operation or native update and
can reject postfix entirely. Common accessors select absence and diagnostics.
Those differences are public behavior, not interchangeable implementation
details.

The shipped `bootstrap/lib/typed-map.c:1548-1622` contains `if(0)` boxed
branches in native MapIntInt update and postfix. The String postfix body at
lines 3345-3380 contains the disabled boxed path and an unconditional
unsupported-postfix rejection before the remaining generated native path.

This demonstrates that the source template emits unused policy text. It
does not prove runtime overhead. A C optimizer can remove constant branches;
the earlier consolidation recorded assembly comparisons. Any proposed
specialization must compare compile cost and generated machine code against
the current baseline before claiming a performance benefit.

## Full family census

### Runtime Maps

| Family | Key / value | Core invocation | Public composition | Actual exceptional policy |
| --- | --- | --- | --- | --- |
| Map | Var / Var | map.x:79-83 | map.x:93-95 and 192-195 | `void` admission, boxed absence, dynamic numeric insertion, mutable-key identity, recursive Context export elsewhere |
| MapIntInt | int / int | typed-map.x:225-231 | 232-243 | 32-bit raw integer update, native missing-key failure, direct numeric export |
| MapLongDouble | long / double | typed-map.x:245-251 | 252-264 | long-key boxing lifetime, floating ordering, direct numeric export |
| MapStringString | String / String | typed-map.x:266-272 | 273-301 | concatenation only, no postfix, canonical key/value export and table rebuild |
| MapStringInt | String / int | typed-map.x:304-310 | 311-338 | integer update plus canonical-key export and table rebuild |

Each of these five standard Map families invokes core family and core
observe once. Every typed
Map invokes typed family, typed observe, and typed publish once. Boxed Map
calls the shared operations/observation/iterate pieces directly because its
conversion, export, and public surface differ.

There are six production scaffold invocations: one in map.x:60-63, four
in typed-map.x:84-100, and PoolTable in pool.x:73-76. The custom fixture deliberately retains its own slot
and diagnostic callbacks. Scaffold is useful sharing, not a requirement
that all storage owners lose their callback choices.

### PoolTable: a sixth production core consumer

The refreshed [pool.x](../lib/pool.x) has 1,035 lines. PoolTable's type at
lines 28-31 has the Scope, parallel hash/entry Blocks, used count, capacity,
and mask that the shared Map core expects. Its scaffold at 73-76, Var
callbacks at 78-79, and core family at 81-84 compose the existing owners.
Commit ef8bfbf1 introduced this specialization in the refreshed range.

`PoolRecord` at line 71 uses an anonymous union: `key` and `val` are two
names for the same Var slot. This is not the ordinary two-Var MapRecord
layout. Every entry maps its canonical value to itself, and the Pool owner
must preserve that invariant. `_setdefault` at 94-96 passes the same object
as key and initial value to the shared lookup-or-insert operation.
`_get_hashed` at 87-90 reads the canonical key after one prehashed lookup.

The generated definitions follow pool.x's `#pragma private` at line 53.
Pool deliberately omits core.observe, typed.operations, typed.observation,
typed.family, iteration, boxing, and typed publication. Pool owns interning,
pool lifetime, and promotion; a public general Map facade would permit writes
that violate its key-equals-value invariant and expose operations it does
not need.

This is a stronger example of useful synthesis than a uniform facade:
ordinary callback and layout slots allow one stored Var per bucket while
reusing probing and growth. No alternate Map algorithm or family framework
is needed. Preserve the actual entry width, aliased slots, single-probe
lookup-or-insert behavior, and Pool ownership if a core change is selected.
The selected unused operations/observation cleanup does not touch this
consumer.

### Runtime Arrays

Boxed Array uses core family at array.x:53, common operations and boxed
indexing at 72-73, and observer/iterator composition at 214-215. Its negative
index, void, functional, and heap behavior remains outside native indexing.

The seven typed families are ArrayChar, ArrayShort, ArrayInt, ArrayLong,
ArrayFloat, ArrayDbl, and ArrayString. Their invocation groups are
typed-array.x:103-110, 112-119, 121-128, 130-137, 139-146, 148-155, and
157-165. Each composes seven concerns. Four select integer updates, two
floating updates, and one String updates.

### Typed Lists

ListChar, ListShort, ListInt, ListFloat, ListDbl, ListString, and ListSymbol
use one family invocation each at typed-list.x:97-123. Canonical immutable
List cells already own storage, hashing, equality, and rendering. Their
codecs preserve element-tag representation and nil's silent-reader result.
Adopting the Array/Map generator architecture here would add owners.

### Custom families and compatibility

The two Map fixtures are `map-generator-family.x` and its live-symbols
variant. Each defines ProbeMapShortLong and invokes core family, typed
family, core observe, typed observe, and typed publish at lines 104-128.
The callbacks include counted custom hashing and a custom update owner.

The two Array fixtures similarly define ProbeArrayInt and compose the seven
family concerns at lines 30-37. They establish custom-family generation and
live-symbol collection, not just the built-in combinations.

Repository-wide invocation searches found the five standard runtime Maps,
the private PoolTable core consumer, the Array/List families, and these
fixtures as the concrete consumers of these generator interfaces. Hash-table benchmark
implementations do not establish permission to replace the custom interfaces.
External importing source was not inventoried.

## History and existing decisions

The current generator arrangement combines several successful changes.
History therefore matters when choosing which apparent inconsistency to
remove.

1. The pre-0f6676040 Map generator already exposed `$map.typed.family`,
   `$map.typed.observe`, `$map.typed.publish`, and the core macros. The
   September 26 source consolidation extracted operations/observation and
   composed the boxed public wrappers from them. It recorded 724 net
   production lines removed across the six family files after integration.
   That measurement belongs to that historical patch, not this proposal.
2. [Source consolidation research](source-consolidation-research.md), under
   "Readiness correction", records restoration of the original custom Map
   invocation forms. An earlier candidate broke the existing consumer; the
   repaired composed templates restored it. Name-hole forwarding needed a
   compiler correction. Keep those original forms and conformance rows.
3. [Self-expression](x2c-self-expression.md), decision 4, explicitly records
   Gary's choice to retain `$map.core.family` callback parameters. H8 shares
   scaffold generation instead. This plan follows that decision.
4. Commit 27ee651f4, "state family structure and let ordinary operations
   supply the rest", moved scaffold generation into map-generics and removed
   unused Array observer arguments. It added 73 and deleted 115 authored
   lines across nine files. Its useful principle can apply backward to the
   still-unused Map observer arguments.
5. The same commit moved `$scalar` boxing onto immediate boxers. Current
   common.x:573-605 composes a typed Param hole and ordinary conversion.
   Current varops.x:25-64 composes exact ABI names, typed holes, meta row
   projections, and a shared update owner. These are proven examples of
   small concepts working together without a family framework.

The V1/V2 discussion in source-consolidation-research.md:214-237 concerns
the complete Error/Logger/Context transfer experiment, not Map generation.
Its V2 Statement-policy composition failed because captured call-site names
did not bind generated function parameters. This is relevant hygiene evidence
for a proposed policy-hole implementation, but it does not reject all Map
policy composition or all decorators.

The earlier consolidation also caught hot owner String literals installing
first-use interning guards. Numeric null owners for boxed families and failure
path diagnostic construction were retained. A new nominally cleaner wrapper
must not restore those hot-path initialization costs.

Newer source is not automatically better. Array's separate update templates
encode a meaningful unchecked-native contract. Map's shared operations save
source while keeping boxed and native APIs compatible. Neither is a universal
model for the other.

## Refresh after pulling dev

The complete 272ba77c..4107b60a diff has 188 changed files, including
generated artifacts and documentation. The family generators, typed Map,
typed Array, typed List, region table, and four custom-family fixture sources
are unchanged. All corresponding line counts and ranges above still apply.
Map's header comment lost one line; its observer calls are now lines 192-195
and its total is 200 lines. The removal does not change a Map contract.

The PoolTable specialization above is another new consumer. Its record
aliases key/value storage and adds a sixth production scaffold/core instance;
it does not call the operations or observation helpers selected for cleanup.

The important new composition examples are below. They change the evidence
for a larger experiment, while leaving the small cleanup selected.

### Field lists already compose templates and meta projections

[fields.xmacro](../src/fields.xmacro) is 32 lines. Its helpers at lines 4-17
build assignment statements with source quotations. `copy_fields` and
`set_fields` at lines 19-25 splice their results. `segment_state` at 29-32
names one repeated seven-field relationship using the same copy primitive.

Compiler.borrow_unit_semantics, share_meta_group, take_unit_state, and
return_unit_state now use these operations at compiler.x:2491-2520. Local
table initialization and unit sharing use them at 2660-2690. The segment
relationship includes declaration effects and preserves the exact shared
objects; the other relationships remain separate field lists.

This is a useful model for mechanical projection: ordinary assignment stays
the semantic owner, while the list says which fields participate. It supplies
no generic ownership policy. `set_fields` expressly evaluates its value once
per field, so `{}` and `[]` produce distinct containers for each destination.
Hoisting a common value would change identity and is outside a style rewrite.

It does not prove that a policy hole captured at a call site binds newly
introduced parameters. The field macros take the receiver expressions from
their caller and use those same expressions in assignments. A Map generator
must connect captures to parameters introduced by a generated function.
The earlier binding concern therefore remains an exact separate boundary.

### Selector generation makes policy choice inspectable

[list-selectors.xmacro](../lib/list-selectors.xmacro) is 67 lines and
[list-selectors.x](../lib/list-selectors.x) is now 16 lines. Previously the
module alone was 113 lines. These two authoritative files total 83 lines,
30 fewer physical lines, excluding generated output and documentation.

The generated family has 24 optional selector spellings, with List and Var
operations for each: 48 functions. The middle-name helper enumerates depth
two through four and excludes the four prelude selectors. The car and cdr
templates at lines 16-29 state their different result contracts explicitly:
car returns Var, List cdr retains Self, and Var cdr returns List.

`_selector_units` at 53-60 selects one of those complete named templates
from the computed spelling, then returns deferred template invocations.
`_selector_chain` at 9-13 constructs a chain using source expression
quotations. This composes a mechanical vocabulary, explicit source templates,
meta choice, and ordinary binding without a runtime dispatch table.

The existing test-list.x:606-619 checks representative nested List and Var
selectors. Its source and registration are unchanged in this commit range.
Generated library documentation now describes the generated functions at
the outer invocation's location. These are inspected upstream artifacts,
not a test execution by this planning session or exhaustive proof of all
48 operations.

### Whole-statement meta returns remove one placement obstacle

Current meta-native.x:192-233 evaluates a whole-statement call once, then
binds a nonempty code List at the caller's AstPos. Statements and parsing
preserve the distinction between block-item and statement placement.
An expression embedded in a larger expression still needs an expression.

Inside an expansion, every returned List is code. Outside an expansion,
only expression nodes, identifiers, quotations, and pending macro applications
are classified as code; a plain data List stays data. Pattern insertion keeps
its own data boundary. These contracts appear in meta-functions.md:990-1028
and the result table at 863-873, and in meta-native.x:225-233.

The new fixtures cover arrow/braced Stmt wrappers, try/catch/defer carriers,
quoted statements, pending macro invocations, expression-position rejection,
and data Lists. In particular, meta-statement-result.x counts four helper
evaluations and four runtime carriers. meta-statement-ordinary.x uses
quotations outside expansion; meta-statement-data.x checks data classification.
Checked-in fixture results exist, but were not rerun for this plan.

### Revised larger experiment

Named source-template selection through a meta helper is now demonstrated
by the selector family and described for decorators in meta-functions.md:
1065-1117. Prefer that shape for the bounded Map policy comparison over
passing arbitrary statement fragments that mention generated local names.

Use a complete named template for the boxed/native update choice where
feasible. Supply the policy facts through its declared holes and let the
ordinary binder connect generated parameters. A whole-statement meta return
can select a statement template at statement position. A generated function
family needs Unit placement and a sequence of deferred Unit invocations;
the new statement feature does not turn an arbitrary block into declarations.

The example establishes selection and placement, not Map equivalence or a
source saving. Its 48 highly uniform selector operations have fewer policy
differences than Map update, missing-value, and export behavior. Keep the
storage callbacks and supported outer interfaces. Compare all added template
definitions and compatibility composition before retaining a Map prototype.

### Decisions after refresh

- Retained: remove unused internal operations/observation slots directly.
  They still have only the previously identified consumers; classification
  and supported custom-family interfaces are unchanged.
- Revised: the larger comparison starts with meta selection of named source
  templates. Statement placement is now demonstrated; parameter capture
  binding and total cost remain to be proved for Map's actual shape.
- Retained: no universal container framework, blanket split by parameter
  count, or new region metadata mechanism. No converter or effect ledger
  was added by this upstream range.
- Retained: the region table owns effect meaning. The new field and selector
  generators do not establish allocation, export, or ownership effects from
  a name or protocol relationship.

This refresh read the full changed-path inventory and selected relevant
source, book changes, generated family output, and fixture evidence. It does
not claim a fresh whole-repository review, a build, or test results.

## Required semantic boundaries

| Boundary | Current fact to preserve | Owner / evidence |
| --- | --- | --- |
| Key storage | Native Maps copy concrete key/value fields; boxed Map copies Var bits without retaining pointees. | map.x header; typed-map.x public type comments |
| Key identity | Boxed mutable Array/Map keys compare by identity. Canonical String keys can compare pointer identity. | map-generics.xmacro:17-29; typed-map.x:131-142 |
| Native absence | Zero is valid data. Status readers use an out slot; failing direct readers raise instead of manufacturing zero. | map-generics.xmacro:418-442, 558-578; typed-map tests |
| Boxed absence | `get` and `del` return `void`; status readers report no write. Update/postfix failures follow their current source branches. | map-generics.xmacro:430-436, 503-556, 573-578 |
| Admission | Boxed void keys/values are prohibited. Native null String is valid empty String. | map-generics.xmacro:454-484; typed-map.x:155-162 |
| Update insertion | Native `+` inserts rhs on absence, including String concatenation. Boxed insertion depends on valid numeric rhs. | map-generics.xmacro:503-526 |
| Integer arithmetic | Native Map int update uses 32-bit raw arithmetic and validates shift counts before writing. Narrow typed Arrays follow their documented generated C promotions. | typed-map.x:175-192; integer-ops.xmacro; array-generics.xmacro:27-84 |
| Floating arithmetic | Map floating update accepts four arithmetic operators; comparison delegates to Var ordering. | typed-map.x:139, 194-206 |
| Failure atomicity | Native update calculates before storing; allocation/growth stages before installed storage changes. Callback retry and displacement boundaries remain as documented. | typed-map.x:175-220; map.x:71-78 |
| Volatile access | Existing native update callbacks take volatile pointers and preserve their loads/stores. Public Var.update/postfix retain the published Var-pointer ABI. | typed-map.x:175-220; varops.x; research readiness correction |
| Iteration | Map bucket order and mutation invalidation differ from Array index traversal. Long-key boxing has Scope lifetime. | map-generics.xmacro:739-830; array-generics.xmacro:710-737 |
| Publication | Typed publication supplies boxing, cleanup, Iter and tagged Var conformance. Boxed owners avoid duplicate converters. | map-generics.xmacro:832-899; array-generics.xmacro:760-833 |
| Export | Numeric Maps move existing storage; String-keyed Maps stage a rebuilt table and preserve identity. Later source bucket wins canonical-key collapse. | typed-map.x:284-338; map-generics.xmacro:863-892 |
| Representation | Array is Block-backed contiguous storage; Map owns parallel hash/entry Blocks and a Scope value; List remains canonical immutable cells. | family type declarations and headers |
| Meta exposure | The literal meta prototypes after family composition stay explicit. Do not assume unit macros can generate their availability contract. | typed-array.x:167-189; typed-map.x:343-356 |

The book's typed Map description at collections.md:1158-1221 provides the
public contract. The exact source determines diagnostic order and branches
when broad prose is insufficient. This plan does not repair unrelated
documentation or change any missing-key result.

## Options and decisions

### A. Delete unused facts at the nearest owner: preferred first change

Reduce the internal observation generator from five slots to its single
used Type. Remove unbox from the operations generator. Keep typed.family
and typed.observe's original source forms because their other composed
operations use those facts.

The direct consumers are map.x and the wrappers at map-generics.xmacro:947-961.
No hash, update, boxing, or export policy changes. No new runtime helper,
record, traversal, cache, validator, or protocol is necessary.

Selected classification: `typed.operations` and `typed.observation` are
internal composition helpers. Change their signatures directly. Introduce no
compatibility wrapper or second owner for their existing bodies.

Evidence: commit 0f6676040 extracted both helpers while retaining the earlier
`typed.family` and `typed.observe` invocation forms through composed wrappers.
The only current direct consumers are map.x and those wrappers. Neither
helper appears in the book or the custom-family fixtures. The research
readiness correction explicitly restored the old outer forms; it did not
establish the new extracted helpers as a supported custom-family contract.

`core.observe` is a supported custom-family interface for this plan. It
predates that extraction and both custom Map fixtures invoke it directly at
lines 117-121. Preserve its eight slots, including the real field boxers and
comparators. Preserve `core.family`, `typed.family`, `typed.observe`, and
`typed.publish` for the same history and concrete consumer reasons.

The book specifies the generated container operations rather than every
importable generator helper. Importability alone does not classify a helper
as supported API. Outside repository consumers were not inventoried; the
internal classification follows the current contract evidence and intended
composition boundary, not proof that nobody has ever called those helpers.
This limitation is explicit and does not defer the selected design.

### B. Split all Map policies into sibling generators: do not prescribe

This could make boxed/native bodies easier to read, but duplicates shared
operation documentation and plumbing unless carefully composed. Splitting
all operations because the signature has fourteen slots is not justified.
Array also retains boxed flags in its common operations.

A bounded prototype may specialize update/postfix alone. Preserve the core
storage owner and the outer macro interface. Compare total definitions,
callers, projection helpers, documentation, and emitted functions. Prefer
the current flag form if specialization adds machinery without removing
enough text or making a specific policy materially easier to inspect.

### C. Select named templates through meta: preferred bounded experiment

The refresh supplies a working family model: complete named source templates
selected by meta functions, then expanded at their ordinary positions.
Start the larger Map comparison with that model. It avoids introducing a
policy representation solely to reduce the argument count.

Raw policy fragments passed as Stmt holes remain an alternative, with the
binding limitation below. New whole-statement meta returns improve placement;
they do not authenticate or automatically rebind captured parameter names.

Typed policy fragments could state admission and failure once while leaving
the storage operation direct. They must bind the generated receiver, key,
slot, and rhs identities correctly. The transfer V2 failure is an exact
warning about this boundary.

Do not begin with a recursive AST substitution pass or a new binder. Use
ordinary source templates and existing typed hole/binding operations. Probe
one boxed and one native update, including a custom family and live symbols.
If the natural fragment does not bind, record that exact unsupported shape.
Do not compensate by introducing a larger policy DSL.

### D. One Map family ledger and many projections: deferred

One row could theoretically drive declarations, wiring, converters, and
region names. However, four built-in typed Maps have public documentation,
different key/value layouts, different update policies, and two distinct
String export bodies. A table must make each policy explicit. It cannot
infer effect or export policy from a type spelling.

No existing Map family ledger currently owns those facts. Creating one
would add a representation and projection functions, not merely reuse a
known table. The typed declarations and meaningful callback names should
remain visible. Require a concrete total-source comparison before adopting
this option; the eleven region rows alone do not justify it.

### E. Universal Array/Map/List container framework: decline this scope

These owners have different identities, algorithms, and missing-value
contracts. Sharing a spelling does not make their storage policy common.
Retain existing ordinary owners and compose real shared operations. This
decision concerns the proposed universal framework, not every possible
cross-container simplification.

## Region names and explicit effects

The eleven paired typed-container rows are regions.x:170-180: seven Arrays
and four Maps. Each pair records box/unbox as `(wrap)`. The names repeat
family/unbox spellings already supplied to typed publication generators.
That is mechanical duplication worth tracking.

Effect meaning stays in regions.x. The table's `(alloc)`, `(alloc slot)`,
`(pool)`, `(store)`, `(wrap)`, `(free)`, and explicit summaries describe
runtime lifetime behavior. Different functions sharing a word or type can
have different effects. For example, wide scalar boxing allocates, while
immediate boxing does not. A converter name is not proof of its effect.

The table drives Walk.effect at lines 247-252, region_result at 258-267,
region_wrapper at 270, and has_region_row at 274. meta-native.x:500 also
uses row presence as evidence of a modeled native operation. A mistaken
generated effect therefore changes more than a style convention.

Current decision: preserve the compact explicit rows. Do not add compiler
registration state, runtime mutable metadata, origin tracking, another
reflection walk, or a second effect validator just to remove eleven lines.

Future viable composition: if a reviewed family ledger replaces the actual
publication invocations, include explicit emitted boxer/unboxer names and
explicit `wrap` participation there. Project those exact names into region
entries using a small Entry macro. Keep nonmechanical allocation, cleanup,
export, argument sinks, and pooled-result effects in the current owner.
Count ledger imports and projections in total source and translation cost.

Do not give all Var participants `wrap`: scalar converters can allocate,
and validation/conversion can copy storage. Generated typed Map and Array
boxing/unboxing rows are eligible because their current declarations and
implementations establish unchanged container identity.

## Concrete implementation instructions after review

1. Pin the implementation baseline and repeat the invocation search before
   editing. Preserve the approved core callback interface and unrelated work.
2. Apply the settled internal classification to typed.operations and
   typed.observation. Preserve core.observe and the original outer interfaces.
3. Remove unused internal forwarding at its owner. Keep core.observe's real
   types/boxers and typed.convert's real unbox name. Update direct boxed Map
   calls and wrapper calls coherently. Add no new runtime owner.
4. Compare the authored change against the untouched custom family fixtures.
   They must continue to request the same user-visible operations and names.
5. If the broader policy prototype is selected, copy only the changed generator
   and a minimal consumer into temporary space. Make one boxed update and one
   native update readable without changing their storage or failure policies.
   Select complete named templates through a meta helper first. Preserve the
   Unit/Stmt placement distinction and ordinary typed-hole binding. Spell
   nonkeyword Type names as Strings, as the refreshed quotation contract
   requires; do not construct them from case-losing Symbol spellings.
6. Inspect generated C/H, diagnostics, live-symbol results, and optimized
   assembly. Explicitly check disabled-policy output and owner-literal guards.
7. Retain the broader prototype only if all new helpers and wrappers earn
   their cost. Record additions/deletions across every affected authoritative
   source, generated surface, and required compatibility adapter.
8. Review the complete authored diff for redundant policy, boxing, lifetime,
   or validation owners before the existing publication proof. Publication
   remains governed by the implementation session's authorized delivery mode.

The broad prototype is a decision test within future implementation, not a
new project planning step or gate. This plan creates no requirement to run it
for ordinary unrelated work.

## Existing verification to reuse

No checks below were run for this plan. Select existing checks that exercise
the changed boundary; do not add a mirror test for deleting unused slots.

- Custom source generation: run the four existing Array/Map family fixtures
  through `unittest/compiler-fixtures/run.sh check --fixture NAME`. Both
  ordinary and `--live-symbols` variants preserve generated public names,
  conformance rows, custom codecs, and counted Map hashing.
- Typed Maps: reuse tests for zero data, missing/null status, numeric update,
  integer edges and atomicity, independent key/value widths, collision
  backshift, String concatenation, String-int, and common capability coverage
  in test-typed-map.x:53-589.
- Pool, only if core/scaffold or Var callbacks change: reuse
  pool_intern_uses_one_probe at test-pool.x:77, outward shadow lookup at 49,
  child table capacity reuse at 121, wholesale release at 135, and stable
  promotion at 189. Inspect the one-Var union record and identical key/value
  input separately. The internal unused-slot cleanup does not require a new
  Pool check or a broader Pool rewrite.
- Boxed Maps: reuse void admission at test-map.x:109, single-hash existing-key
  updates at 165, defaulting at 371-401, mutable-key identity at 438, null
  status/iteration at 523, and nested-region growth at 607.
- Arrays: retain native unchecked index behavior and checked readers. Reuse
  typed-array suite coverage and array negative-index/slice tests; a Map-only
  cleanup does not require an unrelated Array rewrite.
- Export: reuse context_exports_all_packed_containers at test-context.x:200,
  borrowed packed containers at 309, failed String-array staging at 331, and
  later-bucket String Map key collapse at 351.
- ABI and transfer: reuse atomic-container-ops, volatile-indirect-write,
  volatile-destructure, let-volatile-address, and the Var update owner checks
  if an update body or qualifier actually changes.
- Region changes, if separately selected: reuse region-safe, region-escapes,
  region-reference-parameters, region-number-values, meta-heap-regions, and
  meta-final-regions. Compare effect lookup results for every changed name.
- Performance for changed hot operations: use the current performance
  checkpoint guidance and existing Var/Varops or hash-table workloads. Pair
  identical generated programs and receipts. Report absolute sample values
  and workload, not a cross-workload percentage or a bootstrap-C line count.

The fixture runner owns expectations; check mode must not rewrite them. The
unit harness presently runs registered suites through test-all. Do not invent
an unsupported test filter or a new persistent standalone suite.

## Cost and remaining feasibility

Observed: unused slots do no semantic work; deleting internal forwarding
changes no algorithm. The expected effect is fewer facts to carry, not a
measured source or performance gain. The exact patch cost is still unknown.

Observed: the current shared Map body contains constant-disabled policies in
shipped C. Unknown: whether a smaller source composition improves translation
cost after accounting for additional macro applications and compatibility
projections. Unknown: whether that composition preserves useful diagnostic
locations and all custom-family bindings without extra AST machinery.

Observed after refresh: meta functions select named source templates for the
selector family, and whole-statement meta code returns bind at their actual
statement or block position. Unknown: whether the Map policy family can use
that composition without duplicate bodies, extra forwarding, binding drift,
or additional macro application cost. This experiment remains uncompiled.

Observed: a region name ledger could remove handwritten names. Unknown:
whether a connected declaration-and-effect ledger is smaller and clearer than
the current eleven paired rows and explicit family invocation groups.

No design option is rejected merely because it failed in an older compiler.
The current recommendation preserves what has proven value and identifies
exact experiments that can justify a larger synthesis. Any accepted prototype
must remain small enough that its generated behavior is still easy to inspect.

## Plan review

- Producing operations establish storage shape, canonical String identity,
  checked reader status, and allocation/transfer behavior. The proposed
  unused-slot cleanup consumes those facts without validating them again.
- The first change deletes unused forwarding and reuses the current core,
  conversion, rendering, and publication owners. Operations and observation
  are internal composition helpers; their signatures change directly with
  no new wrapper. The supported core.observe and original outer forms stay.
- The broader experiment must compose existing source templates, typed holes,
  meta selection of named templates, and ordinary conversion. New whole-statement
  insertion preserves AstPos; it does not rebind arbitrary captured names or
  make runtime data Lists into code outside an expansion. No new family object model, AST
  authentication, registration cache, binder, or universal container framework
  is proposed. Core callbacks remain as Gary selected.
- Region effects stay explicit. A future generated name projection may copy
  only effects established by reviewed implementations; it must not infer
  ownership from spelling or protocol participation.
- No validator, dedicated diagnostic, or new negative fixture is proposed.
  Existing compatibility, absence, failure, volatile access, and export tests
  protect the existing public behavior. No recurring process is added.
