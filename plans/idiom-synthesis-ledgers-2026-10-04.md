> Status: reference
> Research snapshot, 2026-10-04, against origin/dev
> 4107b60af83a67abb4ceb058d4d327ce13e36ce7; original baseline 272ba77c.
> Gary subsequently authorized private implementation. The main synthesis
> owns the current dev refresh, binder decision, changes, and verification.
> Historical statements below describe the investigation before implementation.
> Publication and a PR remain held for Gary.

# Synthesize ledger, callback, and literal-reader idioms

## Result and evidence boundary

Prefer one owner of fixed facts, with projections appropriate to each stage.
Keep runtime lifetime, source registration, native conversion, and Lisp truth
differences explicit. Uniform spelling alone does not justify another owner.

This investigation searches all hand-authored lib/ and src/ occurrences of
static Map declarations, meta Map/List functions, scalar-ledger references,
callback wrapper registrations, and the two literal readers. It also follows
REPL consumers and native binding construction outside those directories.
Source and history establish the findings below. No timing, instruction,
allocation, generated-C comparison, or runtime result was measured here.
Candidate replacements need the focused feasibility checks specified below.

## Refresh against current dev

Reviewed the complete change inventory from 272ba77c to 4107b60a and the
relevant lib/src/docs/test diffs, intermediate histories, and current
producer/consumer source. No
compiler, runtime, fixture, or performance check was run in this refresh.
The scalar ledger, fourteen access invocations, 36 callback wrappers and
registrations, Literal readers, and tag List builder remain unchanged.
Their source ranges and file counts below remain current. meta-native.x
now has 1003 lines; its compiler target producer moved from 745 to 780.

### New working compositions strengthen L1 and refine L2

The compound selector family now generates both declarations and spellings.
list-selectors.xmacro:9-29 builds a chain through quotations and two named
Unit templates. Lines 33-66 enumerate depths two through four, omit the four
prelude selectors, and pass the two Macro values into a meta producer.
There are 24 generated spellings with List and Var forms, or 48 operations.
The authored family changed from list-selectors.x alone, 113 lines, to 16
lines plus 67 template/helper lines: 83 lines, a net reduction of 30.
Generated linked-meta.x is derived output and is not another authored owner.
These are source counts, not runtime or translation improvements.

Commits 9636ee2a/0bbb29d6 introduced the selector templates and replaced
handwritten operations; 4a1921af/d9440161 then replaced manual enumeration
with meta generation. Reuse this present, concrete Macro-value composition
as the implementation exemplar for L1. It settles that deferred Unit
application and generated name enumeration are current capabilities; the
scalar-specific equivalence checks still remain unrun.

fields.xmacro, 32 lines, supplies _field_copies/_field_sets and their source
Stmt templates. Compiler consumers now select groups of fields instead of
repeating assignment statements. The helper evaluates its value expression
once for each generated assignment, not once for the whole set. Its segment
state macro owns the shared macro/import/Lisp/declaration-effect field list.
Do not turn these helpers into a runtime record-copy framework or infer that
all fields have the same lifetime or rollback contract.

Whole-statement meta results are now supported both in expansions and in
ordinary code (0be5eee9, d9cd258d, 55582335). The book and meta-statement-result
and meta-statement-ordinary fixtures distinguish raw Lists inside expansions
from ordinary code data Lists; ordinary returned statements use quotations
or pending Stmt templates. e863fffc also permits a Stmt arrow body to invoke
a Stmt macro. L2 can therefore use the shortest source-shaped statement
producer for a wrapper body. This does not automatically supply Unit
definitions, Param result quotations, native signatures, or registration.
L2 remains a bounded catalogue experiment, with all 36 policy differences
and callable identity checks preserved.

0b721a6c adds Macro.declared and Macro.inserted_items and broadens Macro-value
sequence grouping for scalar Lists. Type holes now reject non-keyword Symbol
type names through lib/meta.x:358-373; use %("NativeScalarAccess") or source
Type holes rather than %(NativeScalarAccess). Fixture macro-quotation-
scalar-splice exercises value lifting and Name behavior. It constructs Array
expressions with `%[$items...]`; this is not the List-expression cons chain
returned by native.scalar.list or _tag_list. L4's List-stage comparison
therefore remains necessary; do not claim the new scalar lifting removes it.

### New set representations are justified distinctions

efc7f318 replaces the Lisp nonreturning-cause list/constructor with a direct
SymbolSet literal in error-macros.xmacro:1-8. All 31 cause names are retained.
The declaration in ast.x:205-206 and its membership consumer are unchanged.
The family changes from 43 to 15 authored lines, 28 fewer. This is a newer
idiom to adopt for a closed Symbol membership vocabulary: the source states
the set directly, without a Lisp representation and compiler-private builder.
It is not evidence that Map-valued scalar rows should become a SymbolSet.

ef8bfbf1 replaces Pool's Map intern table with PoolTable. pool.x now has 1035
lines, up from 990. Its 71-99 projection reuses the existing Map scaffold,
Var hash/equality policies, and core algorithm with a one-Var union record.
The key and value denote the same stored Var. Lookup, fused insertion,
promotion, ancestor search, locking, Scope ownership, and canonical identity
remain distinct obligations; no general public mutable-set API is introduced.
The source documents 12 bytes per bucket versus Map's 20; this refresh did
not measure allocation totals or performance. Keep the specialization: a
closed SymbolSet, canonical Var key set, and scalar metadata Map serve three
different representations. PoolTable is also a newly added current consumer
of map.scaffold/map.var.family/map.core.family, so container-generator plans
must include it before changing those interfaces.

Existing test-list.x:606-618 compares optional List and Var selectors.
test-pool.x covers outward lookup, fused-probe accounting, pointer stability,
promotion, capacity reuse, and release. Their source supports the intended
contracts; passing results are not claimed. New nonfinite meta transport,
file-scope meta constants, weak public meta definitions, field-state copying,
and source-location/import repairs preserve additional consumers of binding,
numeric families, and compiler context. L1/L2 must test on the refreshed
compiler rather than restoring earlier staging assumptions.

## Inventory and findings

Counts are physical lines at the baseline, including comments and blanks.
Ranges describe existing code, not deletion estimates.

| Family | Files, total lines | Relevant ranges | Verdict |
| --- | --- | --- | --- |
| Native scalar facts/access | lib/native-scalar-types.xmacro, 92; lib/lisp.x, 1913; src/type.x, 976 | ledger 21-38; access template 60-78; Lisp invocations 43-56; lookup 58-63; Type lookup 604-645 | Remove repeated type enumeration; retain the existing meta Map representation initially. |
| Lisp callback declarations/registration | lib/lisp.x, 1913; lib/lisp-targets.x, 230 | context and makers 1388-1451; wrappers 1457-1549; registrations 1568-1608; target resolution 1612-1617 | Prototype one explicit source catalogue; do not collapse truth or ownership policies. |
| Literal tag extraction | lib/var-unbox.xmacro, 31; lib/varops.xmacro, 77 | positional readers 17-20; structural reader 47-51; common.x invocations 625-633 | Adopt structural capture locally; keep ledger confinement. |
| List-expression construction | lib/native-scalar-types.xmacro, 92; lib/var-tags.xmacro, 395 | Lisp recursive builder 40-43; meta iterative builder 267-272 | Coordinate with sequence quotation work; current forms need canonical AST construction. |
| Fixed/runtime/generated tables | src/operator-ledger.xmacro, 51; src/type-ledger.x, 42; src/meta-native.x, 1003; lib/var-tags.xmacro, 395 | operator rows 9-32; type tables 16-36; compiler target producer 780; tag type construction 357-370 | Classify by stage, mutation, and ownership; do not mechanically rewrite every Map. |

### L1. The scalar ledger is authoritative, but access declarations repeat it

Fourteen exact C spellings have ledger entries and fourteen independent
`$native.scalar.access` invocations. The access lookup already iterates the
sorted ledger entries. Adding a type can therefore produce a lookup reference
without its corresponding record declaration.

The ledger values hold tag, native extractor, and native update helper.
`src/type.x` uses these through `_scalar_row` and `_scalar_numeric_info`.
`lib/lisp.x` uses the tag and exact Type to generate sizeof, alignment, load,
and store operations. Loads copy native bytes, then move wide boxes into the
supplied owner. Stores convert the Var to the exact native type before copying.

The separate declaration enumeration is not a requirement of those consumers.
The data representation is a different question. Commit d96c4098 replaced a
Lisp row list and six selector helpers with the meta Map, simplifying this
file from the historical form: 38 lines added and 72 removed, a net 34 lines.
The whole commit changed five files; its
148 added/95 removed lines are not the scalar file's independent savings.
Commit 57095793 then sorted access entries to remove hash-layout dependence.
Commit 8517ce33 removed signature-type data after consolidating native policy.
These changes demonstrate useful ownership reduction. Returning to an
immutable ledger is not automatically an improvement.

REPL consumers also require exact native bytes: repl-runtime.x:116,132 and
repl-lower.x:2664,2725 call native_scalar_access. Keep them in validation scope.
The narrower i48/u48 numeric payload families remain intentionally absent.
Aliases must continue to canonicalize through Type.scalar before lookup.

Competing choices:

- Keep the Map and derive the declarations from its sorted keys. This deletes
  the duplicate enumeration without changing the ledger's callers.
- Replace the Map with immutable List rows, then project runtime lookup Maps.
  This aligns operator/tag ledgers, but adds a projection and changes current
  direct meta lookup. Neither lower cost nor smaller source is established.
- Keep manual declarations. This avoids a generator, but preserves two
  independently maintained lists with no semantic reason for their difference.

Adopt the first choice. A meta helper iterates `List.sort(Map.list(
native_scalar_types()))`, calls the existing Unit template as a deferred value
for each row's Type, and returns the sequence. A small Unit macro inserts it.
The existing template, access record names, sorted lookup, and alignment
builder stay unchanged. Current list-selectors.xmacro demonstrates the
deferred Unit/Macro-value composition directly. The book section "Source
templates from meta functions" specifies it independently.

Do not generate typed meta prototypes as a side effect. Their separate literal
declarations remain necessary; typed-array.x:168 and typed-map.x:344 document
that family macros cannot emit those registrations.

### L2. Callback wrappers and registration repeat one association

There are 36 private wrapper definitions and 36 alias rows. Of these, 27 serve
native/meta callbacks, and nine adapt the Lisp predicate surface. Registration
names must resolve to parsed function references because builtins.x:794-825
derives the Func signature from the referenced definition. Alias spellings
are externally observed by binding construction even when the wrapper is
private.

The wrappers are not all one algorithm:

- Unary/binary callbacks preserve native Var truth and argument order.
- Predicate callbacks convert interpreted results through Lisp truth.
  Zero and empty String remain true; nil and void are false.
- Iter.init adapts the native pull ABI, supplies an output-cell Var, and
  stores the Func in Iter.aux. Its callback is moved to session lifetime.
- Iterator `_into` operations reuse caller-supplied destination storage.
- Lisp Iter.filter creates destination storage with Iter.new rather than
  consuming the native `_into` destination contract.

All callback calls enforce their originating active Lisp session. Call budgets
remain shared with the interpreted invocation. Collection adapters must not
be moved to lisp-targets.x merely to align filenames: lisp.x owns session state;
lisp-targets.x owns optional module bindings outside the implicit prelude.
Callback target lookup precedes the library target lookup deliberately.

Historical evidence separates real improvements from residual duplication.
Commit 0702b8d1 shared the Func maker and session check, replacing arity flags
with named unary/binary makers. Keep that improvement. Commit 74c2df78 only
reordered sections and is not the origin of the algorithms blamed there.
Commit 476a62c0 consolidated general native targets into lisp-targets.x and
retained session callbacks in lisp.x. Later table consolidation must preserve
this architectural boundary, rather than undo it for visual uniformity.

Preferred experiment: one immutable catalogue owns each public bind name and
an explicit source-shaped wrapper body. The name of the private wrapper is
derived from that bind name using the current `_lisp_` prefix. A named Unit
template takes return Type, generated Name, a parameter sequence, and body.
A meta projection emits declarations before registration; a second projection
feeds the existing lisp.native.targets row format. Keep explicit unary,
binary, predicate, and Iter initialization source in rows. Infer signatures
through the existing native binding owner; never add a second signature table.

This is a bounded prototype, not approval for a generic adapter framework.
Prototype three representatives first: List.map, Lisp_List_filter, and
Iter_init. These cover ordinary unary adaptation, Lisp truth, and retained
pull callbacks. Test generated Name identity and prototype lookup before
moving the other 33 definitions. If a source catalogue requires a sizeable
custom AST interpreter or hides the bodies, retain direct wrappers and their
registration. Report that implementation failure without rejecting all future
compositions. Net reduction remains unmeasured.

### L3. Capture a Literal's Symbol by structure

The Literal hole's producer resolves the canonical shape
`(expr TYPE (literal TYPE TEXT SYMBOL))`. Var-unbox reads its last two elements
through List_last and casts. Varops matches the shape and captures the Symbol.
Both need the same represented value, but they consume different row facts.

Commit ed863ce0 introduced the structural varops reader on September 18.
Commit cd53416b introduced positional var-unbox readers on September 25 while
moving the full Var ledger into leaf units. The newer code improved module
ownership; its positional extraction is not therefore a preferable idiom.
Preserve the ownership improvement and adopt the existing structural reader.

Add one private meta Symbol extraction operation inside var-unbox.xmacro.
Capture the Symbol with `%(expr ? (literal ? ? ?key))`, then call Var_tag_top
and Var_tag_bottom from the existing integer helpers. Remove its List_last
meta prototype if no longer used. Keep Var_tag_top/Var_tag_bottom prototypes,
the unbox mask, return types, nine common.x accessors, and compiled ledger
lookups unchanged. Do not import var-tags.xmacro or introduce a shared public
SDK helper for two small consumers.

The helper may return `(Symbol) 0` on an impossible structural miss. This is
not an established public absence contract: compiled tag queries reject an
invalid tag. Verify legal Symbol literals and preserve compiled tag-query
behavior without adding a validator or dedicated diagnostic.

### L4. List-expression builders repeat a canonical construction

native.scalar.list recursively constructs an expression whose Type is List
and whose content is a cons chain. `_tag_list` constructs the same family
iteratively. These are code-producing operations, not runtime List builders.
Using List.append, cons on their outer data, or a quoted List of AST nodes
would change the returned syntax.

This family also occurs in Compiler.literal_cell, literals.x:265,275;
Compiler._template_calls, meta-group.x:489; _list_form, stage.x:332;
Compiler._quoted_cons, macros.x:1387; and Compiler._captured_pair,
macros.x:3703-3706. Those compiler operations additionally
perform typing, conversion, and staging. They are comparison consumers, not
automatic candidates for a common library helper. A low-level typed cons
node is valid where no source quotation can preserve its resolved state.

The quotation-adoption audit records historical failed List/composite
spellings. Current expression-sequence scalar lifting, Array literal
splicing, and braced initializer splicing are available; this is not an
established missing generic sequence capability. None of those forms alone
proves a quotation produces the canonical List-expression cons chain needed
by these two library consumers. `%[$items...]` produces an Array expression,
not that List-expression chain.

Reconcile the two sites with the existing quotation-adoption record. Prototype
current List-producing source spellings against their actual insertion sites,
first with empty, single, and several already-built expression elements.
Compare the resolved result, Type, order, and identities; do not require the
unresolved quotation carrier to be structurally identical to the old builder.
Adopt a direct quotation only if this proves the consumers' existing contract.
Retain current construction otherwise and record the precise unsupported
shape or stage; do not infer a new language requirement before that evidence.
Compiler resolved-node construction remains until a measured structural
rebuild preserves conversion and binding identities without resolving twice.

### L5. A constant definition and a process table are different stages

The exhaustive Map declaration search includes several distinct families:

| Family | Current owners | Decision |
| --- | --- | --- |
| Closed compile-time facts | native_scalar_types, _operator_rows, _update_rows, _tag_groups, _tag_validated_ids | Keep local data forms readable for their consumers; no single mandatory container. |
| Runtime read-only indexes | scalartypes, native_scalars, native_targets, callback_targets, typetags, varrows, regions runtime/pooled_results | Keep process-lifetime indexes. Generate from shared facts only when several consumers need them. |
| Mutable caches/registries | var declared/cells; compiler real_paths; collect process_cache/source_hashes; meta-native linked_hashes/native_modules; meta-helper failures/units; macros library maps; type declared_typetags | Retain mutation, initialization, synchronization, and owner policies. These are not constant-map inconsistencies. |
| Membership and interning sets | error.nonreturning.causes SymbolSet; PoolTable canonical Var keyset | Keep direct SymbolSet for closed Symbol membership and specialized Var storage for canonical identity; reuse the shared Map algorithm without restoring redundant value storage. |
| Request-dependent returned data | frontend preprocessing/collection maps, build/project/editor maps, SDK definition hashes, macro bookkeeping maps, generated reachability/position maps | Retain functions and request ownership; their output depends on arguments or active compiler state. |
| Generated module suppliers | build.x source module/extension templates; meta-native _compiler_targets | Preserve module construction and call lifetime; investigate repeated allocation separately before caching. |

A runtime Map is mutable storage even when current callers only read it.
A List literal is canonical immutable structure. A meta function is a producer
at compile time; it does not imply a runtime singleton. Uniform adoption means
choosing by stage, identity, lookup workload, and mutation, rather than spelling.

Additional nearby inconsistency: the comment above src/type.x:608 still says
the scalar row includes a Func signature spelling, but 8517ce33 removed it.
Correct that stale comment in the scalar batch. Do not restore a deleted field
to satisfy old prose. src/type-ledger.x independently lists 28 native pointer
type/tag pairs. Scalar and pointer families overlap, but p48, pointer-to-pointer,
and boxed-class cases add distinct facts. Defer generating those rows until a
complete mapping proves the representation and supported pointer set; do not
infer a universal scalar-to-pointer rule from similar names.

## Remediation sequence and acceptance

1. Implement L1 and its stale-comment correction as a small connected batch.
   Compare the fourteen declarations, record identities, table entries, native
   C size/alignment, load/store conversion, and deterministic output order.
   Compare generated C, allowing private declaration order changes only.
2. Implement L3 locally after a focused import/translation probe establishes
   structural capture works without carrying the full ledger into common.x.
   Check all nine accessors for matching and nonmatching tags. Keep pointer
   masks and returning NULL behavior unchanged.
3. Prototype L2 in temporary/private implementation work, count catalogue,
   templates, projections, and remaining wrappers together, and review source
   visibility. Adopt only if the representative prototype preserves binding
   lookup and policies with proportionate machinery. Otherwise retain it as a
   measured/reproduced rejected implementation and keep direct wrappers.
4. Fold L4 into the existing quotation-adoption record as a current-capability
   comparison, not a presumed sequence-hole language blocker. Compare the
   cold library insertion sites first; retain their builders if equivalence
   is not established. Compiler hot paths remain separately measured work.
   Reconcile rather than duplicate the active record's remaining entries.
5. Review and fix each completed authored diff before applicable publication
   validation. Delivery follows current root guidance only after implementation
   is authorized; this investigation creates no new recurring gate.

Existing verification scope includes test-lisp.x's generated collection tests,
iterator budget/session/storage tests, test-var.x boxed and wide scalar tests,
test-varops.x numeric update families, callback-adapt and meta-iterator-callback
fixtures, meta-record-native-scalars, meta-native-alias, meta-native-scalar-pointer,
and existing wide scalar fixtures. Run REPL focused checks because it directly
consumes native_scalar_access. Use the existing harness and checked-in fixture
expectations; no tests were executed during this planning investigation.
Use the refreshed meta-statement-result/ordinary and macro-quotation-scalar-
splice/type-values fixtures when L2 adopts those capabilities. Preserve the
new Type-name diagnostics rather than bypassing them in generated Type data.
Include meta-nonfinite-results and meta-file-scope-constants when comparing
scalar insertion and linked-meta behavior on the refreshed compiler.
Container-generator rewrites must include PoolTable's private core calls and
the existing Pool identity/probe tests; no Pool rewrite is selected here.

Where existing coverage misses a concrete behavior, extend its owning test
with that scenario. Do not add invalid-AST fixtures for contracts established
by Literal production or separate table-completeness gates. Performance work
for a generator or callback-path change follows current performance guidance;
source line counts alone cannot establish runtime or translation improvements.

## Existing work, limits, and decisions

Source-consolidation-research.md retains unpublished typed-family and evaluator
prototypes. Do not assume them integrated, reject them through this report, or
reimplement their work. Rebase approved changes on the actual dev source and
reconcile callback registrations if those prototypes later alter API exposure.
Its private-template visibility experiment failed on storage-qualified Type
holes; the callback prototype must test Name and Param construction before
depending on an unverified equivalent capability.

The scalar Map remains the default. No new public APIs, data types, source
syntax, truth rule, ownership contract, or typed meta registration mechanism
is approved here. Callback generation and List sequence syntax remain bounded
feasibility work, with explicit acceptance criteria rather than invented savings.
Counts measure current authored source; all proposed reductions are unmeasured.

## Plan review

- Literal production establishes the tag expression shape. Existing Type
  normalization establishes scalar spelling. Native binding construction owns
  Func signatures. The proposed consumers do not add a validator for these facts.
- L1 reuses the access Unit template and deletes fourteen repeated invocations.
  L3 reuses match and compiled tag queries. L2 must delete a registration mirror
  without adding a second signature/truth/ownership model. L4 reuses canonical
  AST and quotation work; it creates no parallel syntax representation.
- Source remains ordinary x2c: local data, named source templates, meta iteration,
  and structural capture. A generic adaptation framework, new cache, or public
  AST helper is unnecessary for these current consumers.
- Current selector generation demonstrates combined meta enumeration and
  source templates. Direct SymbolSet literals and PoolTable reuse strengthen
  the representation-by-role rule; neither creates a universal table owner.
- No new validator, dedicated diagnostic, or negative fixture is proposed.
  Existing session mismatch checks protect retained callbacks from the wrong
  session; they remain. Existing null/absence and conversion behavior remains.
