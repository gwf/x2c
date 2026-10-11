> Status: active research; full specification unproven.
> Private branch: codex/nested-modules-spike. Context: individual/private.
> Original baseline: c09d9a917f4ab1afc072b3fb2ece71e7bb2a6e04.
> First prototype: ed1e83032b9bfc8073db5a6a79377e42eeb53b5d.
> No adoption, integration, push, PR, or global installation is authorized.

# Nested modules: iteration two evidence

Keep this implementation private and revise it before adoption. Ownership,
relocatable identity, inherited compile-time effects, and ordinary cross-file
layouts work in focused executable controls. The expanded layout contract is
not satisfied: guarded native headers still change later source macro state.
Native-meta prerequisite staging also remains incorrect in a valid control.

The seven-file compiler macro split remains the real module workload. The
outer entry is `src/macros.x`; `src/macros/quotations.x` is its nested entry.
Public package names retain their existing prefixes. This iteration adds no
package resolver, user-authored support headers, or child public-name prefixes.

## Implemented changes

- Ownership discovery caches canonical entry and ancestor results. Unit startup
  establishes ownership once; borrowed compiler contexts share the existing
  tree rather than constructing another tree during initializer setup.
- Experimental interface format 11 records portable ownership-search queries,
  logical identity, and resolved dependencies. Replay resolves location-sensitive
  queries against the current home.
- Anonymous private native names use the outer entry filename and entry-relative
  paths. Distinct canonical trees with the same logical identity diagnose a
  collision before native linkage, as Gary selected.
- Directed Tarjan components order deferred inline-provider binding. This is
  one actual collection consumer, not general component-based compilation.
- Bound aggregate fields supply value/array prerequisites; pointers terminate
  complete-layout demand. Private projected type and enum names retain their
  defining file identity. Alias chains and public hidden inline support use
  ordinary bindings and generation owners.
- Each active aggregate family has one generated support header. Dependency
  includes replace recursively copied bodies. Separate visiting/completion
  guards reject selected complete-layout cycles and permit inactive alternatives.
  These artifacts use existing per-unit publication and bootstrap copying.
- Field directives now survive parsing and emission. They do not enter semantic
  field rows. Complete-layout prerequisites retain their field conditions;
  mutually exclusive field edges are not treated as an unconditional cycle.
- Full member parsing installs inherited Lisp prefix effects through the
  existing full-parser replay path. Shallow collection no longer substitutes
  queued effects for that full environment. Later suffix effects stay later.

## Executable evidence

All new research fixture builds request one worker. The host was running hot;
fixture and build durations are not comparative performance evidence.

| Check | Result | Evidence and scope |
| --- | --- | --- |
| General module matrix at 1027d5bc | 98/98 | `/tmp/x2c-module-probes-ecbgywvt/results.json`; before the field-directive repair |
| Field conditional controls at 92f62c50 | 8/8 | `/tmp/x2c-layouts-k9vtckvl`; module and ordinary controls, both flags, active-cycle rejection |
| Bounded family-header controls | 15/15 | `/tmp/x2c-layouts-a5db9qez`; alternative layouts, selected cycles, aliases, private enums, native inline ordering |
| Inherited Lisp and producer controls | 9/9 | `/tmp/x2c-module-probes-62n1_5ru/results.json`; privacy, source ordering, direct-member equivalence |
| Native preprocessing region experiment | 2/2 | `/tmp/x2c-native-layout-regions-v9ovdfyk/results.json`; inert C skeletons, guarded and pragma-once headers |

The native region experiment is not an integrated compiler feature. Its input
was hand-authored C, and it does not prove native declaration closure, arbitrary
pragma state, binding privacy, cache behavior, or bootstrap portability.

Final full matrices, current-candidate replay, bootstrap recovery, self-hosting,
and the existing research correctness gate are pending. Earlier gate success
belongs to the first prototype; it cannot validate this changed implementation.

## Remaining correctness failures

### Native header effects

The positive public/static controls `guarded_header_macro_effects_public` and
`guarded_header_macro_effects_static` fail in the module implementation. Their
ordinary-file controls pass. A projected prefix includes a guarded native
header early. The projection restores an explicit feature macro but retains
the native header guard. At the authored include, the guard suppresses the
header's feature definition, and the later function observes the wrong value.

Saving more macro names alone is insufficient. Restoring the guard repeats
native type bodies; retaining it loses effects. `#pragma once` adds include
state beyond macro names. The current prefix-copy mechanism is therefore
insufficient for this demonstrated flat-module case. This is not evidence
that nested modules are impossible.

Faithful native preprocessing can resolve macros in original order before
moving emitted declarations. The region experiment proves that narrow operation.
A complete implementation still needs native declaration identity/closure,
provider-local native bindings, residual pragma state, and exported native
macro behavior. It must retain the original authoritative x2c binding identities.

Generation is not idempotent. The current reverse Context lifetime requires
generating each provider once, exporting immutable emitted regions and graph
facts, then assembling text after its semantic context closes. Calling the
generator twice or replaying declaration producers would violate the contract.

Freezing native-expanded C into shipped bootstrap would bake in host system
types, target macros, and ABI. A portable repair instead needs original C/H
and layout metadata, with target-specific projection before native compilation.
Bootstrap must have that projection operation before the experimental compiler
exists. A standalone helper and its declaration/pragma handling are unresolved.

This crosses generation, Toolchain, Build receipts/fingerprints, bootstrap/stage
rules, copying, and stage comparison. If native closure needs a C parser, the
bootstrap must supply that parser independently. Its implementation size and
native processing cost are unmeasured. No speculative second parser or unused
API was added. Detailed owner stages are retained in
`.context/nested-modules/iteration-two/native-layout-emission-design.md`.

### Native-meta prerequisites

The valid acyclic native-meta control builds but exits 1. A provider enum calls
another provider's meta function; helper construction substitutes an integer
zero before that implementation is available. The same ordinary baseline
control fails, so the defect is inherited, but the requested contract remains
unsatisfied. The rejecting cycle control does not prove a deliberate call-cycle
diagnostic. Records are `/tmp/x2c-meta-prerequisites-3lx61mdv/results.json` and
`/tmp/x2c-meta-baseline-upfcbwtw/results.json`.

Repair requires demand-driven provider readiness before publishing immediate
enum values, retained parsed declarations, and incremental native availability
without restarting helper state. Reordering the current all-parse/all-compile
loop does not supply those semantics. That repair is not implemented.

### Additional limits

Conditional field directives now emit correctly in the tested configurations.
Semantic field lookup still contains declarations from feasible native branches;
branch-specific semantic layout, header-injected fields, and arbitrary pragma
state are unproven. Native packed-attribute controls and ordinary body-order
controls also failed in the expanded matrix before the field repair. Their
ordinary counterparts fail too. Expectations were not weakened to make the
matrix green.

## Measured cost

The first prototype was measured before scheduling changes. Gary then warned
that the host was running hot. No starting or revised wall-clock samples are
used to claim slowdown, speedup, or retained throughput.

Temporary instrumentation changed one ownership object in otherwise frozen
binaries. All six translations succeeded. These counts measure candidate
presence probes, not total filesystem operations or elapsed time.

| Matched workload | Units | First prototype probes | Early cached probes |
| --- | ---: | ---: | ---: |
| Ordinary files | 26 | 31,822 | 2,365 |
| Flat module control | 34 | 87,730 | 4,343 |
| Three-level nested control | 34 | 149,178 | 4,343 |

Raw record: `/tmp/x2c-modules-iteration-two-counts-v2/results.json`. Later
constructor, ancestry, scheduling, identity, and layout changes are outside
this count comparison. The equal-unit flat/nested pair isolates ownership
depth for this operation only; it does not explain all translation cost.

The layout size comparison translates identical diamond source graphs with
the retained recursive-render binary and the bounded family-header binary.
All six translations succeed. Header totals include generated support headers.

| Depth / unique families | Recursive C bytes | Recursive H bytes | Bounded C bytes | Bounded H bytes |
| --- | ---: | ---: | ---: | ---: |
| 2 / 5 | 7,072 | 13,044 | 3,342 | 8,584 |
| 5 / 11 | 60,370 | 118,728 | 6,876 | 19,288 |
| 8 / 17 | 483,520 | 964,116 | 10,410 | 29,992 |

Raw record: `/tmp/x2c-layout-growth-2qmqsolw/results.json`. This establishes
bounded aggregate-body duplication on those workloads, not bounded alias-prefix
work, native execution performance, or full compiler throughput.

| Authoritative compiler source | Files | Lines | Bytes |
| --- | ---: | ---: | ---: |
| Original dev baseline | 55 | 53,225 | 1,994,997 |
| First prototype | 63 | 54,457 | 2,041,253 |
| Candidate 92f62c50 | 65 | 55,389 | 2,078,120 |

The macro implementation occupies seven files and 5,511 lines, compared with
one file and 5,461 lines originally. The candidate has 2,164 more compiler
source lines than the baseline. Source movement is not counted as new code.
Records are `.context/nested-modules/iteration-two/source-size.json`.

Comparable full native object/archive sizes, quiet-host cold/retained timing,
peak memory, parse/replay/producer attribution, and mutation rebuild receipts
remain unmeasured. A baseline directory with only runtime objects was rejected
as an invalid comparison with the candidate's compiler and runtime objects.

## Unimplemented or insufficiently exercised requirements

- General declaration-component staging, binding-use dependency edges, and
  context lifetime reduction. SCC scheduling currently has one bounded consumer.
- Faithful native-header layout projection and native-meta prerequisite readiness.
- Fully conditional semantic field layouts, arbitrary native pragmas, and
  repeated private native-meta type spellings.
- Reversed actual native object link order for multi-hop initialization.
- Comprehensive declaration/definition visibility disagreement combinations.
- Ownership-query mutation receipts for newly enrolling ancestors and `.xp`
  competitors; existing membership/preamble/header mutations cover other paths.
- Precise transformed/recollected unit receipts for private body and public
  signature edits, plus the remaining performance measurements above.

## Recommendation and continuation

Revise this implementation. Preserve structured bootstrap, explicit membership,
separate ownership/package identity, binding-based privacy, entry-relative
anonymous names, and bounded family headers. Preserve the failed checkpoints
and their positive/negative controls for comparison.

The unresolved native layout failure also occurs in a flat module. Removing
nesting would not repair it. The ancestor tree remains a proportionate ownership
model, but no final timing result proves its cost acceptable. Do not integrate
the spike or claim that the full original specification is implemented.

The next structural experiment must demonstrate portable original-order emission
plus target-specific projection through one standalone native build operation.
It must resolve native declaration closure and pragma state before replacing
the current projection. Native-meta staging requires a separate actual readiness
model. Neither can be represented as arbitrary SCC execution order.
