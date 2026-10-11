> Status: reference; paused at Gary's request on 2026-10-11.
> Initial timings are affected by host load and are not comparative evidence.
> Starting candidate: ed1e83032b9bfc8073db5a6a79377e42eeb53b5d.
> Original dev baseline: c09d9a917f4ab1afc072b3fb2ece71e7bb2a6e04.
> Continue individual/private isolation. GitHub branch backup is authorized; adoption, PR and integration are not.
> Current implementation and gaps: [integration handoff](nested-modules-integration-handoff.md).

# Nested modules: second research iteration

The next iteration must make the existing design correct and substantially
cheaper before splitting another compiler subsystem. Keep the seven-file macro
implementation as the real workload. Keep structured bootstrap output.
The original language specification remains the acceptance contract; this plan
does not remove requirements that the first prototype failed to implement.

## Starting evidence

The existing correctness gate passes, including bootstrap recovery and
self-hosting. The optional module matrix passes 79/80 cases. The valid acyclic
by-value aggregate case fails in either member order. Anonymous source relocation
changes private emitted identities. Explicit declaration SCC scheduling is
absent. Native-meta prerequisite-cycle evidence remains incomplete.

An independently relocated bootstrap compiles 141 C units without dependencies
on the original checkout. Keep that structure-preserving implementation.

Three-round, single-worker full compiler translation medians are:

| Workload | Source units | Fresh seconds | Retained seconds |
| --- | ---: | ---: | ---: |
| Untouched original baseline | 55 | 8.267 | 6.707 |
| Completed first prototype | 63 | 15.772 | 13.778 |

The full relocated candidate also fails cold/retained artifact parity in all
three rounds. Seventy-two provider proofs retain original-home ancestor absence
paths through the executable's preferred baked prelude records. Source and
definition hashes match; a runtime miscompile has not been demonstrated.
Full native build timing and controlled compiler object sizes were not measured.

The synthetic comparison used 26 flat units and 34 nested units. It therefore
does not isolate nesting from the cost of eight additional entry files.

Evidence: [first report](nested-modules-spike-report.md), and retained workspace
records in `.context/nested-modules/final-evaluation.md` and
`.context/nested-modules/acceptance-review.md`.

## Questions, experiments, and decisions

### 1. Where does the extra translation work come from?

Measure before changing scheduling. Attribute time and operation counts to
ownership discovery, ancestor searches, collection/replay, preamble processing,
body binding/transformation, support projection, and emission. Count source
reads, parsed units, replay hits, producer executions, and retained contexts.
Use temporary profiling or workspace instrumentation, not shipped debug APIs.

Compare four controls: original compiler; experimental compiler on ordinary
sources; experimental flat module; experimental nested module. Flat and nested
controls must have identical declarations, file counts, and emitted public ABI.
Keep the empty entry files in the flat control as enrolled ordinary members.
Change ownership depth, not workload size. Also vary breadth at fixed depth.

This determines whether discovery, repeated interface work, serial staging,
or header growth dominates. Optimize the measured owner. Candidate deletions
include repeated ancestor walks and repeated support projection, but neither is
assumed to be the cause. A retained build must report which units actually
translated; elapsed time alone cannot establish cache reuse.

### 2. Can replay describe the current source location correctly?

Repair `collect.x` interface replay before using relocated measurements as
performance evidence. Prefer portable ownership-search queries resolved against
the consuming compiler home. If the existing record cannot express them safely,
invalidate and recollect that provider rather than trusting stale absence facts.
Keep source hashes and compiler-identity validation in their existing owners.
Version the experimental record if its interpretation changes.

Compare original-home, physically copied-home, and direct-member invocations.
Use matching nonempty preludes. Verify cold/retained C/H/XI equivalence with
logical-path normalization only where deliberately specified. Mutation controls
must create a nearer owner candidate or header after an initial warm run.
Rebinding an absence query must not turn it into an assertion of continued
absence. Filesystem XI regeneration alone is insufficient because baked records
take precedence in `_interface_read`.

### 3. How do complete aggregate layouts reach every consumer?

Start with the failing two-member example: `Outer` contains `Inner` by value.
Use `Sym.field_order` and normalized bound field types to project actual
complete-layout prerequisites and the file supplying each definition.
Pointers require declarations; values and arrays can require complete layouts.
Cover typedef chains, anonymous fields, and nested ownership.

First test placement within existing `Partition` header/source outputs. If own
header suppression still prevents a provider's layout from appearing first,
prototype a separately guarded generated type projection from the same bound
definitions. Both C and H consumers must receive prerequisite layouts before
aggregate ancestor support. Emit each body once. Compare output growth and
native include work before retaining this additional artifact kind.

Do not treat sorted member includes as the fix: both list orders already fail.
Do not rerun producer macros to obtain type facts. Preserve directive placement
through existing Partition operations. A real by-value cycle must reject from
its complete-layout prerequisites; a pointer cycle must remain valid.

### 4. Which cycles can become a DAG, and which cannot?

Use a declaration dependency graph to compute strongly connected components.
Collapse those components into a DAG for declaration collection and body work.
Ownership remains a separate tree. SCC membership grants no visibility.

Keep edge meanings explicit:

| Dependency | Required treatment |
| --- | --- |
| Mutually referring declarations | Collect as an SCC; bind after declarations |
| Complete aggregate layout | Order complete definitions; reject an actual cycle |
| Runtime initialization | Keep existing initializer queue and guards |
| Ordered compile-time producer | Preserve source/include order; execute once |
| Native-meta build prerequisite | Schedule available implementations; reject impossible prerequisites |

An SCC is not permission to execute ordered effects arbitrarily. There is no
single graph whose arbitrary cycles all become legal. Reuse the existing build,
collection, and initializer owners; add only the missing directed SCC operation
and the dependency facts those owners need. Union-find is not an SCC algorithm.

Explore replacing all-module serial staging with declaration-component staging.
Release contexts when their bound contributions and emission dependencies permit
it. Parallel work is an experiment only after compile-time effect ordering and
context ownership are proven. Do not introduce concurrent access to existing
process-global state merely to recover throughput.

### 5. What gives a relocated module a stable identity?

Decision: anonymous trees use the outer entry filename and relative member
paths. Diagnose collisions before native linkage. Gary selected this rule;
distinct entry names or existing package/project roots can disambiguate trees.
This does not authorize new source syntax or a new manifest field.

Keep canonical location for reads, ownership verification, diagnostics, and
invalidation. Use logical identity for private C names, support aliases, and
initializer guards. All three must use the same identity operation.

Package identity plus package-relative paths is the first boundary. Compiler
home-relative paths are the second. A configured project can use a source-based
manifest root, independent of invocation cwd. Test alias changes, symlink
spellings, relocation, repeated basenames, and direct-member invocation.

Anonymous roots use outermost entry-relative identity. Two roots with colliding
emitted identities reject before native linkage. Existing package/project
namespaces or distinct entry names disambiguate them. Source edits, invocation
cwd, and physical relocation do not change this identity.

### 6. Which capabilities are implemented but insufficiently proven?

Close the acceptance gaps with executable cases rather than more source splits:

- Direct entry/member cold and warm binding/output equivalence.
- A pre-block declaration producer that actually runs, with counters proving
  one contribution per consumer and no speculative discovery execution.
- Multiple consumers observing ordered public effects and alias capture.
- A separately compiled native C consumer of public inline hidden support and
  an opaque public pointer ABI. Private x2c lookup must remain rejected.
- Multi-hop cross-file initialization, shared object identity, and global
  initialization/shutdown counts under reversed native object order.
- Genuine native-meta prerequisite cycles and a comparable valid ordering case.
- Public collision rejection during language collection, unchanged package C
  names, nested package privacy, and the remaining modifier/syntax combinations.

Retain all existing privacy, preamble, include-cycle, cleanup, and invalidation
controls. Map the original specification to final evidence again. A green
general gate cannot replace these module-specific proofs.

## Performance to retain and enhance

The performance aim is to recover baseline full-compiler translation throughput,
make unchanged retained work materially cheaper than fresh work, and keep
ordinary nonmodule workloads unaffected. These are research targets, not an
approved slowdown allowance. Any remaining adoption tradeoff needs measured
cost and a later explicit decision.

Run matched original-baseline, first-prototype, and revised-candidate workloads
with the same toolchain, physical home layout, nonempty prelude, and worker count.
Use repeated interleaved runs and report medians and ranges. Do not claim a cold
OS cache. Keep hashes and executable checks outside timed translation sections.

Measure fresh translation, retained translation, unchanged retained build,
one private member body edit, one shared declaration edit, one ancestor preamble
edit, and one membership edit. Record actual invalidated/transformed units.
Privacy alone does not prove an interface is unaffected by an edit.

Add the missing controlled full native compile/link timing and object/archive
sizes. Record C/H/XI sizes, peak resident memory, parsed unit counts, and authored
line changes. Count support duplication and native header processing. Preserve
structured bootstrap portability, byte-identical stage self-hosting, public ABI,
and execute-once compile-time behavior while pursuing these improvements.

## Execution and delivery

1. Preserve `ed1e8303` and its evidence as the first-prototype checkpoint.
   Continue the existing private spike from that revision. Record any fetched
   dev changes as comparison information; do not silently integrate a moving
   baseline or change another checkout.
2. Capture cost attribution and equal-unit flat/nested controls. Repair replay
   correctness, then rerun matched measurements with trustworthy preludes.
3. Implement complete-layout placement and explicit declaration SCC scheduling
   in bounded steps. Keep ordered producers and native-meta prerequisites separate.
4. Resolve logical identity for established roots. Present the anonymous-root
   choice if experiments show a new external obligation is necessary.
5. Close the capability gaps and optimize the measured causes. Reassess context
   retention and parallelism only after their dependencies are explicit.
6. Review and fix the completed authored diff. Regenerate bootstrap through
   documented targets. Run the existing complete correctness command once on
   the finished candidate, plus the optional research matrix and relocation
   proofs. No new recurring gate or process requirement is proposed.
7. Deliver a report separating implemented behavior, passing evidence, failures,
   unattempted requirements, and measured performance. Recommend adopt, revise,
   or reject this implementation. Retain the private worktree; do not publish.

Stop an unsuccessful experiment without weakening fixture expectations. Record
which mechanism failed and what a replacement would require. If the combined
repair grows disproportionately, present a smaller implementation boundary or
the exact tradeoff before building a general compiler framework.

## Plan review

Ownership discovery establishes enrollment; binding establishes visibility;
bound fields establish type dependencies; parsed providers establish initializer
facts. Consumers reuse those facts instead of rescanning source or authenticating
AST origin. Replay must re-resolve location-dependent search queries because a
fact about the old home does not establish a fact about the new home.

Reuse collect, symbols, Type, Context, Partition, initializer queues, interface
validation, and native build operations. Replace obsolete all-module staging
only when component scheduling proves equivalent. The missing SCC operation,
logical identity, and possible type projection each address an observed gap;
they are not reasons to introduce parallel parsers or dependency frameworks.

New cycle classification protects valid acyclic output and deliberate rejection
of impossible layout/native prerequisites. Identity collision handling protects
against wrong native linkage. Replay checks protect against stale dependencies.
Other negative fixtures exercise existing visibility, syntax, ownership, and
package contracts. No additional AST validator or producer-origin check is
proposed. Binding-aware facts, Match, and existing emission operations keep the
implementation direct and idiomatic x2c.
