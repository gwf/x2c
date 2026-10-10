> Status: experimental implementation; full specification unproven.
> Baseline: c09d9a917f4ab1afc072b3fb2ece71e7bb2a6e04, freshly fetched origin/dev.
> Branch: codex/nested-modules-spike. Context: individual/private.
> This report does not authorize adoption or integration.

# Nested modules research spike

The experimental compiler implements explicit, nested module ownership. The
real compiler macro implementation now uses the proposed seven-file layout.
Bootstrap regeneration and compilation from the nested generated C succeeded.
The full specification remains unproven. The recommendation is to revise this
implementation before considering adoption, for the reasons below.

## Developer workflow

`src/macros.x` is the entry. It includes compiler dependencies and declares
module-visible category operations and the shared `Definition` type. Its
comma-separated module block lists categories, definitions, expansion, and
quotation handling. `src/macros/quotations.x` owns parsing and construction
under `src/macros/quotations/`.

A helper used by one file stays `static`. A helper shared by the outer module
uses `module`. Descendant quotation members can resolve those declarations.
Quotation-private declarations use `module` in the nested module. Outer code
uses public quotation entry points. Members do not include each other to
obtain ordinary declarations. Compile-time effects retain explicit include
and source-order rules.

The prototype recognizes module blocks and declaration modifiers through
existing parsing owners. `module` remains an identifier in other positions.
The existing declaration collector supplies signatures; binding ownership
controls private access. Canonical paths identify ownership independently of
package identity. Public package names retain their existing package prefix.

## Bootstrap structure

Generated files preserve source-relative directories:

```
bootstrap/src/macros.c
bootstrap/src/macros/categories.c
bootstrap/src/macros/definitions.c
bootstrap/src/macros/expansion.c
bootstrap/src/macros/quotations.c
bootstrap/src/macros/quotations/parsing.c
bootstrap/src/macros/quotations/construction.c
```

Their headers occupy the same directories. Module support aliases are generated
from the same bindings; no hand-authored private interface is required. Native
rules enumerate C recursively and preserve relative object paths. The external
command build likewise includes nested compiler objects in its development
archive and enumerates generated header directories. Its old flat enumeration
failed in the gate; the focused corrected command build succeeds. Bootstrap
refresh cleans old generated files before copying the stage tree recursively.
Public C names are unchanged. Private linkage names are assigned during
ordinary translation. Bootstrap copying reconnects an absolute quoted include
only when its resolved target is a copied stage artifact. The replacement is
a relative path to that exact copied header; it does not flatten filenames.
The existing bootstrap comparison uses this same mapping for includes. Other
content must still match byte-for-byte; stage-to-stage comparisons are unchanged.
The final-gate attempts exposed a history-dependent provider dependency table.
Ownership discovery had copied its entire shared search history into each
provider record. Collection now retains only the file's own ownership-search
facts. A focused real linked-meta probe compares C/H/interface output with and
without a preceding module translation. The include mapping separately handles
the deliberate bootstrap path changes; it cannot hide dependency payload changes.

A separate native bootstrap snapshot test compiled repeated basenames in both
compiler and runtime directories. Both runtime archive members linked and
executed. Recursive clean retained C/H; realclean removed them. This was tested
on macOS, not Linux. The actual macro migration subsequently passed
`make bootstrap-refresh X2C_COMPILER=<private stage-0 compiler>`.
A relocated snapshot subsequently compiled all 141 C units independently.
Its 141 native dependency traces contained 738 unique dependencies, all under
the copied tree or system toolchain. No dependency reached the original
checkout. All 292 copied artifacts remained unchanged; the rebuilt compiler
ran `--help` successfully without X2C_HOME or X2C_IDENTITY overrides.

The source translation generated 63 units in 54.88 seconds with 16 requested
jobs, then compiled stage 0 and the copied bootstrap. This is one observed
build, not the final comparative performance measurement or self-host proof.

## Initialization and execution

The first initializer prototype retained expressions and reparsed them in
consumer contexts. That approach repeated an initializer macro and failed to
preserve provider-local compile-time state. It was replaced.

Module units now complete ordinary parsing and transformation once. Their
contexts remain nested until reverse-order emission. Existing initializer
dependency maps are projected into spelling rows, rebound in each unit, and
used by the existing initializer queue. File-static prerequisites remain local.
Cross-file object reads call the provider's guarded initializer before access.
The defining file retains initialization and cleanup ownership.

The final focused run passed 79 of 80 cases. Its exact results are
`/tmp/x2c-module-probes-kbk5jvp2/results.json`; its log is
`debug/modules-final-ownership.log`. The compiler remained unchanged during
the run. The added local-shadow fixture excludes an erroneous global initializer
guard from a local variable read. It covers owner-local macros and Lisp,
provider-local static helpers, one initializer macro invocation, reverse object
order, shared Map mutation, cleanup once, initializer cycles, and retained
membership changes. The failing positive case is the acyclic complete-layout
dependency described below. The harness preserves that failure.

## Known limitations and open evidence

Relocatable emitted identity is not implemented for anonymous external source
trees. Moving the same two-file module changed its private prefix, support
alias, and initializer guard. Both copies compiled successfully. Canonical
ownership and language privacy still worked, but that does not satisfy the
specified relocatable identity contract.

A coherent correction must distinguish logical source identity from canonical
file location. Existing package identity and compiler-home paths provide
boundaries. Configured project roots can provide another. Anonymous trees need
a deliberate stable namespace rule; using cwd or a common invocation input
prefix would violate direct-member equivalence. This spike does not silently
introduce a new namespace requirement.

The prototype stages enrolled module units in one process. It does not yet
implement an explicit SCC scheduling plan for all declaration groups. Existing
cyclic include collection is retained. A valid acyclic complete-layout dependency fails: Outer stores Inner by value
before the generated ancestor header makes Inner complete. Reversing the
member list also fails because a provider source predefines its own header
guard before including the parent. Include sorting alone cannot repair this.
The impossible by-value cycle rejects through the same native incomplete-type
diagnostic; that does not prove prerequisite-cycle classification. Native-meta
prerequisite cycles remain unattempted.

## Comparative measurements

Final comparative samples, compiler identities, prelude verification, generated
sizes, and native object sizes are recorded in the retained worktree's
[final evaluation](../.context/nested-modules/final-evaluation.md). That record
also identifies the exact gate result and self-host comparison. It is workspace
evidence rather than a recurring process requirement.

Earlier three-run timing samples used compilers without matching prelude
interfaces. Both fell back to reading prelude source. Those samples remain in
`.context/nested-modules/`, explicitly as transitional observations. They do
not establish a converged compiler regression or the final nesting cost.
Final comparisons must use nonempty prelude environments and a quiet window.

The compiler source starts at 53,225 lines in 55 files. Final file and line
counts are recorded in the final evaluation and its source-size record. Twenty-six source files change, including
six extracted macro members and two new ownership/access owners. The original
5,461-line macro file becomes an 1,888-line entry. Its seven-file family totals
5,511 lines, including new visibility declarations and file headers.

Existing native compiler objects total 3,552,792 bytes in the baseline worker
and 4,068,168 bytes in the migrated stage. The baseline object provenance was
not independently revalidated, so these totals are artifact observations,
not a controlled fresh-native comparison. Full native build timing is absent. The
flat and nested layouts contain identical 24 leaf declarations and main. The
nested layout adds eight empty entries: 34 units versus 26. Measurements use
fresh processes, one job, three runs, and the same host toolchain. They are not
cold operating-system-cache measurements. Shared-host variability limits exact
percentage claims.

## Evidence and delivery

Detailed logs remain under `debug/`; raw measurements and fixture results are
referenced from `.context/nested-modules/`. These are workspace evidence, not
shipped compiler machinery. Executable examples live in `examples/research/`.
The focused harness is optional and is not added to recurring repository gates.

The [acceptance review](../.context/nested-modules/acceptance-review.md) maps
requirements to implementation, fixture evidence, and uncovered behavior.
The [final evaluation](../.context/nested-modules/final-evaluation.md) records
the correctness gate, self-host results, and matched performance evidence.
The explicit research request authorizes the existing correctness gate despite
the default private-delivery wrapper restriction. A local wrapper retains
individual/private context and invokes the unchanged gate implementation.

No branch was pushed, no PR was submitted, and dev/main were not modified.
The private worktree and branch remain available for inspection.

## Recommendation and remaining work

Revise this implementation before adoption. The real nested macro split and
portable bootstrap demonstrate that nested source organization is practical.
They do not prove the complete language contract.

Three required implementation gaps prevent adoption:

- Complete aggregate layouts need provider dependencies and placement before
  dependent headers. A sorted include list does not suffice. Reuse bound field
  types and existing Partition operations; preserve pointer-only dependencies.
- Declaration collection needs an explicit SCC scheduling plan distinct from
  ordered compile-time, complete-layout, and native-meta prerequisites. The
  current staged parse group does not implement that plan.
- Emitted private identity needs a logical source boundary independent of the
  canonical filesystem location. Anonymous external trees still need a stable
  namespace decision consistent with direct-member translation.

Nesting itself adds ancestry lookup, inherited prefixes, transitive exports,
include roots, and cache dependencies. Complete-layout placement and initializer
staging are substantial flat-module costs too. The same failed layout occurs
without nesting; this prototype does not establish that nesting is infeasible.

Unattempted or incomplete proof includes genuine native-meta prerequisite-cycle
classification, cross-consumer compile-time effect counts, invocation of a
preamble declaration producer before its module block, direct-member versus
entry byte-equivalence, and a separately compiled C consumer of public inline
support. The acceptance review lists further syntax and visibility combinations
without independent fixtures. Passing covered cases must not stand in for these
requirements. A failed native incomplete-type diagnostic is not proof of proper
layout-cycle classification.

The next spike should first implement the complete-layout projection and logical
identity boundary, then add SCC scheduling and the missing prerequisite probes.
A new complete-type projection, typed prerequisite graph, and header/source
placement changes are the additional layout work. Identity propagation spans
ownership, guard generation, support aliases, and retained-build configuration.
A precise elapsed-time estimate for that work is not established. This report
identifies the mechanisms required rather than substituting an unmeasured cost.
Successful future checks still require explicit authorization before integration.
