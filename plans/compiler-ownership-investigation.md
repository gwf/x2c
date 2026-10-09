> Status: reference
> Ownership and dependency investigation completed 2026-10-09 against
> 548b381f18653089b0285082881f27d65df3bf94. Recommendations below are design
> candidates, not an approved compiler refactor or reproduced defect report.

# Compiler ownership and dependencies

The compiler has useful existing owners, but several operations distribute
aliasing, restoration, and destruction obligations across callers. Improve
those operations before choosing new component records. A whole-compiler
ownership model is useful; a whole-compiler rewrite does not follow from it.

The clearest small candidates are a shared operation for borrowing a unit's
Lisp session and meta group, and separating diagnostic storage from rendering.
The most consequential larger question is temporary backend emission's writable
state. Its isolation depends on more than copying the Compiler record.

## Scope and evidence

Three isolated investigations covered lifetimes, transactions and declaration
transport, and source dependencies. Integration checked the findings against
current source, corrected unsupported test-coverage claims, and distinguished
existing owners from proposals. The [ownership appendix](reference/compiler-ownership-evidence.md)
classifies all 109 Compiler fields and traces thirteen operating modes,
including the REPL, failed segments, and delayed inline providers.

This was a static investigation. Existing tests were inspected, not executed.
A baseline `make build-safe` passed to prepare documentation tooling. That
build is not evidence of rollback completeness, failure-path safety, or speed.
No exhaustive backend mutation audit, leak probe, incremental-build timing,
or refactor equivalence experiment was performed.

## Preserve the owners that already exist

| Existing owner | Responsibility to preserve |
| --- | --- |
| Frontend and ParsedUnit | Request configuration, sequential units, unit Context and explicit closure. |
| SourceView | Request overlays; disk text is not retained as a request cache. |
| Scope and Pool | Mutable allocation versus canonical value lifetime; shallow container copies do not isolate payloads. |
| Sym and SymTxn | Semantic visibility, binding facts, in-place mutation and selective undo. |
| GenNames and Pending | Shared binding allocation, selected generated naming, and staged output destinations. Their sharing policies differ. |
| Collection process cache | Retained declaration rows and dependency proof; explicit promotion before unit storage disappears. |
| Lisp and native modules | Explicit Lisp session destruction versus process-lived native code and function handles. |

Relevant boundaries are in [frontend.x](../src/frontend.x#L157),
[sourceview.x](../src/sourceview.x#L13), [symbols.x](../src/symbols.x#L100),
[collect.x](../src/collect.x#L1035), and [meta-native.x](../src/meta-native.x#L1138).
A replacement Session should not duplicate these owners.

## The central problem is nonuniform sharing

`new_shared` does not mean that every field stays shared. Package registration
can detach `package_roots`. Cold collection temporarily replaces counters on
the shared GenNames record. Temporary emission copies origins and selected
maps. Segment parsing returns replacement handles and can transfer a newly
created Lisp session to its owner.

These exceptions are intentional operations, not defects inferred from their
complexity. Moving their fields into uniformly shared component pointers would
change behavior. The important question is which operation establishes each
alias, detaches it, returns a replacement, or ends its lifetime.

See [package registration](../src/collect.x#L576),
[cold collection](../src/collect.x#L617),
[segment transfer](../src/compiler.x#L2636), and
[emission isolation](../src/meta-group.x#L283).

For example, a new consumer of a unit's staged meta functions must currently
associate `macro_lisp`, `borrowed_lisp`, and the matching meta group. Three
existing setup paths repeat that obligation. A borrowing operation can remove
that repetition without replacing the compiler's architecture. Returning a
newly created owned session is a different operation and must remain distinct.

Failure-path tracing found that aborted segments destroy newly owned Lisp or
preserve borrowed Lisp. Delayed providers retain a Compiler allocation finalizer
even after removal from the work queue. No missing cleanup was reproduced.
The fallback runs after Context Pool release; arbitrary Lisp-owned finalizers'
access to canonical payloads remains an unverified teardown-order question.

## Keep three restoration and transport contracts distinct

### Semantic speculation

SymTxn already logs overwritten and deleted rows with their actual Map identity.
Nested completion selectively preserves undo rows for an enclosing transaction.
It is not an append-only checkpoint. Extended capture is selected by
`macro_application`, while recovery callers decide whether to open transactions.

Ordinary commit preserves semantic map identity. Extended commit merges staged
adapters into the original map. `commit_transient` also restores the original
counter-map identity so REPL scratch storage can close. Completion always rolls
back. Submission can commit accepted declarations while interpreter side effects
on previously published globals persist after a later failure.

The controlling code is [transaction completion](../src/symbols.x#L1353),
[REPL completion](../commands/repl/repl-session.x#L200), and
[REPL submission](../commands/repl/repl-session.x#L391).
These callers do not have one universal publication policy.

[Initializer speculation](../src/initializers.x#L735) separately snapshots
adapters, Pending, and the paired literal key/index state. Adapters and Pending
overlap extended SymTxn, but this caller can run without extended capture.
Removing its snapshots outright is incorrect. Factoring those two existing
snapshots is worth considering. Extending literal rollback to every macro
transaction is an unresolved behavior change, not part of that factoring.

Some macro map writes bypass Sym's journal operations. Membership in the
transaction's tracked-map set does not intercept arbitrary writes. No escaping
mutation was reproduced; this remains a coverage question, not a defect claim.

### Temporary backend emission

[Meta-group emission](../src/meta-group.x#L210) snapshots the whole Compiler and
GenNames records, opens SymTxn, copies selected mutable containers, and resets
output state. It restores both records before transaction rollback.

A record copy restores handles, but cannot undo mutations through an inherited
handle. The existing copied set includes adapters, file-scope owners, literal
keys, origins, definitions, protocol helpers, and meta regions. An exhaustive
reachable-write trace is needed before replacing this boundary.

The valuable design direction is explicit backend emission isolation using
existing semantic owners. A generic transaction over all reachable state is
not established as necessary. A new child Compiler is also insufficient unless
it receives the backend environment currently borrowed from the owner.

### Portable declarations

[Freeze/thaw](../src/compiler.x#L699) is declaration transport with relocation.
It converts token pointers to rows, origins to locations, local literal IDs to
portable keys, and binding identities inside those keys to consumer-global
references. It escapes marker-headed Lists and preserves source-spelling facts.

Imported macros land lazily and rebind in the consumer scope on first lookup.
Local retained declaration bundles deliberately keep their unit identity.
Process-cache publication separately retains canonical values. Encoding a
portable representation does not itself extend its storage lifetime.

A dedicated declaration-transport owner could make these contracts easier to
maintain. It should preserve lazy landing, local replay, and ordinary constructed
AST acceptance. A universal serializer, origin authentication, or new content
hash identity is not justified by this evidence.

## Dependencies and build cost

The literal include inventory contains 128 top-level src/lib files and 730
quoted `.x` edges. The compiler-only graph contains 52 files and 252 edges,
with one strongly connected component of 32 files and 20 singleton components.
There are no direct runtime-to-compiler edges in this inventory.

The inventory resolves including directory, working directory, lib, then src.
It includes generated top-level sources and counts conditional directives
without evaluating them. Macro-generated includes, configured extra search
paths, imports, and optional subdirectories are outside its scope.

Four representative cycles have different causes:

| Dependency | Actual reason | Useful treatment |
| --- | --- | --- |
| Parser and expressions | Declaration initializers need expressions; casts, function types, and statement expressions need other grammar operations. | Preserve semantic recursion; a type-header move cannot remove it. |
| Symbols and Compiler | Binding IDs, package names, source facts, diagnostics, and rollback. | Preserve one semantic identity owner; separate declarations only where it simplifies real consumers. |
| Diagnostics and Compiler | Storage holds a Compiler printer and saves it in holds; rendering reads compiler source state. | Separate storage emission from source rendering. |
| Cache and generation | Cache calls source-prelude placement implemented in generate.x. | Give shared placement analysis one concrete owner. |

The placement candidate comprises `place_source_prelude`, `Anchors`, `_anchors`,
`_is_function`, `_needs_errors`, and the shared `_spelled_types` walker. None
reads Compiler fields. The walker also serves header/forward analysis. Keep
one conditional-aware scan for both function placement and exception ABI
placement; extracting one helper while duplicating that scan would worsen
ownership. See [placement](../src/generate.x#L884) and
[type spelling](../src/generate.x#L394).

Build speed is a separate question. [stage.mk](../builds/stage.mk#L162) batches
all compiler sources when its translation stamp invalidates. Native jobs use
header depfiles. [file_publish](../src/utils.x#L362) writes and renames generated
files without preserving timestamps for equal content. The ordinary
[Build path](../src/build.x#L641) can preprocess a scheduled job and then skip
native compilation using its content record.

Therefore include fanout alone does not predict translation work, native jobs,
or elapsed time. Sampled generated headers retain the source cycles. No timing
claim or whole-graph acyclicity requirement follows from this investigation.

## What to consider next

| Candidate | Concrete obligation removed | Design status |
| --- | --- | --- |
| Unit Lisp/session borrowing | Three callers independently associate session, destruction responsibility, and meta group. | Best small ownership simplification. Preserve NULL-session creation and return transfer. |
| Diagnostic storage/rendering separation | Aggregation callers and tests need Compiler solely for the printer. | Strong independent boundary. Use one borrowed emitter/context pair; preserve hold, routing, and lifetime behavior. |
| Backend emission isolation | Backend changes must account for both whole-record restoration and selected pointee copies. | Highest-value larger investigation. Complete the reachable-write inventory before choosing representation. |
| Produced-effect snapshots | Initializer and macro recovery repeat adapters/Pending restoration knowledge. | Bounded factoring candidate; caller policies and literal rollback remain distinct. |
| Shared source placement | Cache depends on generation for an operation with no Compiler state. | Concrete dependency improvement; preserve shared type and conditional analysis. |
| Declaration transport owner | Portable encoding and consumer landing are embedded among other Compiler operations. | Coherent navigation/contract improvement; preserve relocation and lazy behavior. |
| Binding allocator versus generated naming selection | One record combines shared live IDs with temporarily replaced counters and emission caches. | Lower-confidence structural candidate; settle identity and output determinism before moving fields. |

This order reflects confidence and maintenance benefit, not benchmark results.
Small candidates can proceed independently. The larger emission investigation
should inform any later component architecture. There is no requirement to
complete all candidates or make the include graph acyclic.

For diagnostic separation, existing tests cover ordering, limits, reset,
streaming, and single holds. They do not establish identical-report deduplication,
nested holds, or Pool lifetime safety. Store entries and snapshots borrow
canonical values. A callback does not change that ownership contract.

For any future implementation, use the relevant existing tests and focused
probes for the changed boundary. Compare emitted output where placement,
identity, or temporary emission changes. These are design proof obligations,
not new recurring gates. No implementation has yet been validated.

## Plan review

Existing constructors, Sym operations, canonical retention, and unit closure
establish the facts this assessment relies on. Proposed callers should reuse
those facts, not revalidate them. The useful candidates remove repeated
association, snapshot, or placement knowledge; they must demonstrate that
removal in their final design.

No new Session facade, generic transaction protocol, universal serializer,
arbitrary collaborator limit, validator, diagnostic, negative fixture, or
recurring process is proposed. Any later implementation should use concrete
x2c records and existing operations only where they reduce caller obligations.
