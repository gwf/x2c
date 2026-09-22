# Internal adoption campaign

> Status: ready tranche and system-macro follow-up complete and validated;
> generalized-meta and lifetime-certified tranches remain dependency-gated.
> Refreshed against dev at `2d188c42` on 2026-09-22. Generalized meta adoption
> depends on rebasing, reviewing and landing `codex/meta-values-types`;
> lifetime-sensitive adoption depends on the certification work described
> below.

## The result

x2c's compiler, runtime and repository tools should be convincing users of the
features the project now recommends. This campaign replaces internal
boilerplate with shipped macros, runs the remaining x2c tools under their
ordinary extensionless script names, and makes new meta capabilities delete
parallel binding registries instead of adding a third way to describe them.

The work is deletion-led. It does not broaden public semantics, add a second
script launcher, expose every method of a meta type, or treat an advisory
lifetime analysis as a safety proof. Each delivery leaves dev healthy and can
stand alone; later phases start only when their stated dependency has landed.

## Current baseline

The September 22 refresh records the first three campaign deliveries.

- Dev now includes safe runtime formatting, but `String.format` is already
  used by the runtime/meta session and its probes. There is no production
  hand-formatter with runtime format text and a boxed `List` worth replacing.
  Typed interpolation and `printf` remain the more direct operations.
- Phase 3 replaced 47 high-confidence
  `defer local.free/destroy/cleanup/close()` sites with `$auto` and four exact
  `Scope.push` / deferred `Scope.pop` pairs with `$scope`.
- Meta-capable protocols are documented on dev, but generalized meta values,
  adopted records/types and bodyless native prototypes are not. They exist on
  the independently moving `codex/meta-values-types` branch. That work is a
  dependency to land, not a capability the campaign may assume from dev.

The ready-tranche findings now stand as follows:

- Phase 2 converted all 23 multiline command-help literals to `$dedent`; the
  three leading separators are explicit blank writes and help output remains
  byte-identical.
- Phase 1 removed the 18-line `lib/system-macros.xlisp` compatibility shim for
  `dedent.expand` and `macros.location` using current meta functions.
- Phase 4 renamed the two executable x2c tools to `tools/check-release` and
  `tools/gen-package-index`. Both use the existing suffix-independent script
  classifier and launcher.
- The ready-tranche follow-up adopted `$switch` in the two largest CLI
  dispatches, deleting 62 explicit terminal `break`s, and replaced eight
  manual temporary parser and analysis state bindings with `$let`.

## Campaign boundaries

This plan owns internal adoption and the deletion it enables. It coordinates
with, but does not absorb, these existing efforts:

- [Tooling ports](x2c-scripting-ports.md) owns translations of Python and shell
  tools. This campaign only renames the two already-native x2c scripts.
- [Meta authoring and coverage](meta-authoring-and-coverage.md) owns the method
  inventory and representation boundaries. This campaign consumes its
  classifications after the generalized capability lands.
- `codex/meta-values-types` owns its current generalized-meta implementation.
  Its rebase, design review and exact-tree proof precede adoption that relies
  on it.
- [Meta-function Lifetime
  Equivalence](../docs/src/internals/meta-lifetime-equivalence.md) owns the
  safety model. This campaign will consume a proved effect inventory; it will
  not weaken the model to make more methods eligible.

The campaign explicitly holds the following work:

- no blanket conversion from interpolation or `printf` to `String.format`;
- no textual replacement of defer sites and no conversion of consuming
  parameters, out-parameter `ParsedUnit` values, unsupported `ReplInput`,
  conditional rollback, state restoration, raw-pointer ownership or custom
  locks;
- no new launcher or suffix-specific fallback for extensionless scripts;
- no public `protocol Meta(T)` and no implicit exposure of every method on a
  meta type;
- no native-prototype expansion while declarations duplicate the trusted
  target registry;
- no meta exposure of resources or callbacks before lifetime certification;
  and
- no `lib/var-tags.xmacro` rewrite. The current experiment remains below its
  recorded translation-cost acceptance condition.

## Ready tranche

These deliveries depend only on capabilities already on dev.

### 1. Make the system macros x2c-first (delivered)

Move `dedent.expand` and `macros.location` from
`lib/system-macros.xlisp` into `meta static` helpers in
`lib/system-macros.xmacro`, using the existing source-text and invocation
file/line operations. Remove the Lisp import and delete the `.xlisp` file.
Keep the existing macro names, literal/fallback behavior and source-location
attribution.

The implementation must cover literal, escaped, interpolated and nonliteral
`$dedent` inputs. Verify `unittest/test-system-macros.x`, the registered
system-macros example and expected output, and existing source-location
diagnostics. This delivery is the small independent proof that current meta
functions can replace a remaining Lisp helper without generalized meta types.

### 2. Adopt `$dedent` in command help (complete)

Import the system macro where `src/cli.x` defines command help and replace all
23 awkward multiline literals with `$dedent`. Preserve help output byte for
byte. For the three blocks whose current value deliberately begins with a
newline, either represent that separator explicitly inside the dedented text
or leave the literal direct if the result is less clear.

`unittest/probes/run-cli-boundary.sh` is the acceptance proof because it covers
all command help snapshots. No new help formatter or fixture is needed.

### 3. Adopt managed-lifetime macros (complete)

Convert the 47 high-confidence managed locals to `$auto` with a binding-aware
edit. The count is reproducible from the 56 direct local cleanup defers after
excluding three consuming API wrappers, four out-parameter `ParsedUnit`
locals, one `ReplInput` without a `Cleanup` conformance, and one intentional
lifetime-escape fixture. Preserve declaration order so multiple managed
locals retain LIFO cleanup.

In the same delivery, replace the four exact compiler-source push/pop pairs
with `$scope`. Do not turn nearby policy-dependent or conditional pushes into
decorators merely because their spelling is similar.

A second, separately reviewed delivery may adopt the three production
push/pop sites in `src/macros.x` and `lib/lisp.x`; the Lisp decorator should
use `$let` as well as `$scope` only if the resulting ownership remains direct.
Two `tools/repl-spike` sites are optional examples, not acceptance criteria.

Focused validation is the defer and system-macro unit suites, the existing
REPL spike check for REPL-owned locals, and generated-output inspection where
multiple resources share a scope. The final exact-tree gate remains the
publication proof.

### 4. Name x2c tools like scripts (complete)

Rename `tools/check-release.x` to `tools/check-release` and
`tools/gen-package-index.x` to `tools/gen-package-index`. Preserve their
shebangs and executable bits. Update live callers, usage text and current
documentation; do not rewrite archived plans merely to erase the historical
names.

`tools/release-candidate.py` must continue to invoke the generator explicitly
through its selected `x2c script <path>`. Direct execution is an additional
user-facing proof, not a replacement for toolchain selection in release
automation. Validate both scripts through explicit `x2c script`, direct
execution with the intended compiler on `PATH`, the release-candidate dry run,
and the existing CLI boundary coverage for extensionless scripts.

Editor association by first line is a useful follow-up, but it is not a
condition for the rename: the VS Code extension is suffix-oriented and lives
in its own Node environment. Plan that behavior separately if ordinary editor
use proves the missing association material.

### Ready-tranche system-macro follow-up (complete)

Use `$switch` for `_print_help` and `_apply_option` in `src/cli.x`, which
already imports the system macro pack for `$dedent`. Remove only each case
run's terminal switch `break`; preserve grouped labels and any early or nested
control transfer. The remaining return-only switches and switches with
deliberate fallthrough gain no useful deletion and stay direct.

Use `$let` for the exact temporary-state regions in the list, raise and catch
literal parsers, aggregate-member binding, and the two recursive
`lifetime.origin` walks. This makes their documented temporary state restore
on every exit without adding helpers or another state owner. Raw pthread
locks, native assertions, structured timing and native unreachable markers
retain semantics that `$lock`, `$assert`, `$time` and `$unreachable` do not
replace.

Acceptance is CLI boundary parity, focused literal/match/error and aggregate
fixtures, the existing system-macro suite, graph-tool translation, and the
final exact-tree gate. The nested computed-capture replay limitation found in
`$lisp.entry` remains tracked separately and is not worked around here.

## Generalized-meta tranche

These deliveries begin only after `codex/meta-values-types` or its successor
lands on dev with a review of its stated representation limits and an
exact-tree proof. The dependency supplies per-unit meta values, adopted meta
types and records, bodyless native prototypes, and a curated native-record
bridge. Evaluator records are not native layout, ordinary calls do not fold,
and native crossings still require trusted descriptors.

### 5. Make Autodiff the first generalized-meta adopter

First replace the remaining forward/reverse sibling Lisp registries and their
four wrappers with per-unit `meta static List` state and x2c meta helpers.
Then replace the string-keyed state map threaded through Autodiff with a typed
`meta struct AdState`, splitting forward and reverse state only if doing so
actually removes fields or branches.

The early dummy Lisp definitions used for mutual recursion are a distinct
installation-order constraint. They remain unless this work also supplies a
general predeclaration design; the campaign must not count them as deletion by
association.

Acceptance covers every Autodiff unit and registered example, generated output
and result parity, and a before/after translation-time comparison. The typed
state is successful only if it removes dynamic field spelling without
replacing it with adapter machinery.

### 6. Give native meta targets one owner

Before marking more native prototypes, make the marked declaration or its
protocol witness generate the descriptor, callable adapter, name, signature
and session registration now repeated in `lib/lisp.x`. Delete the
corresponding trusted-target rows. The 53 scalar cmath prototypes on the
generalized branch are the proof set: they currently demonstrate execution
but duplicate the manual registry, so they are not yet complete dogfooding.

Bootstrap order is the design constraint. The compiler needs a trusted target
before it can consume declarations that describe that target, so this phase
must identify the compiled seed and the point at which generated metadata
becomes authoritative. It must not solve the cycle by retaining two full
inventories.

Validate missing-target, signature and pointer rejection; explicit calls from
meta bodies; the guarantee that ordinary calls do not fold; and cross-platform
size, alignment and mutation for the curated native-record bridge. These
checks protect unsafe native crossings and current phase behavior, not a new
origin-authentication rule.

### 7. Generate meta surfaces from existing conformance

Design meta-capable protocols as composition with existing protocol witnesses:
`meta` continues to mark translation-time availability, while `Var(T)`,
`Cleanup(T)` and other protocols remain the owners of representation,
ownership and behavior. Availability stays explicit per method or deliberately
meta-capable protocol.

Use the 44 already-classified declarative candidates as the first bounded
proof: 16 Buffer writers/converters, `Array.block`, `Var.block`, 22 packed
Array/Map conversions, and the four Var JSON/regex operations. Generated
metadata must delete their manual binding rows. The same seam may then
consolidate the compiler's native-operation bindings, builder aliases and name
exceptions; it is not complete while those inventories remain parallel.

This phase needs its own syntax and bootstrap design before implementation.
The illustrative `meta protocol` spelling in the current research is not a
settled public decision.

## Lifetime-certified tranche

### 8. Expand only from proved effects

Implement the lifetime research in its recorded order:

1. add opt-in certification that combines the whole-project `region-escapes`
   result with a capability-table effect inventory;
2. treat any reachable unknown call as unproved in certification mode while
   keeping ordinary advisory warnings compatible;
3. repair resource types whose allocation is not yet paired with an attached
   finalizer; and
4. measure the certified subset against the requested meta subset.

The effect inventory records native target, meta implementation, result
provenance, parameter effects, owner and finalization. Only then generate the
six callback/allocation candidates and the four borrowed or finalized handles
classified in `meta-authoring-and-coverage.md`. File and Job finalization must
occur at evaluator region boundaries, not be delayed until session teardown.

This phase does not add a recurring gate. Certification is opt-in until its
compatibility and cost justify a separately approved process change.

## Delivery order and campaign completion

Phases 1-4 are ready and may be delivered independently in that order; phase
3 may proceed in parallel after phase 1 because it does not depend on
`$dedent`. The generalized-meta dependency may land independently, after which
phases 5-7 proceed in order. Phase 8 waits for the lifetime proof regardless
of the generalized-meta schedule.

Every code delivery ends with a review and repair of its authored diff, then
`git diff --check` and `tools/gate-state.py ensure agent-pr-check` on the final
tree. Focused checks answer the phase-specific questions; the existing gate is
the publication proof. The campaign adds no gate, planning step or recurring
requirement.

The campaign is complete when the ready tranche has landed, the generalized
meta capability has at least one typed adopter and one generated registry with
the former manual rows deleted, and every lifetime-sensitive adoption is
either certified or remains explicitly classified outside the meta surface.
Parked experiments and optional tool ports do not hold completion open.

## Plan review

- **Facts established elsewhere.** `x2c_source_file` already establishes
  whether a shebang file is source; the rename adds no classifier. Cleanup
  conformances establish the 47 managed destructors, and exact push/pop pairs
  establish the first `$scope` set; consumers do not recheck either fact.
  Protocol witnesses and the lifetime effect inventory remain the owners of
  representation and safety rather than new meta-side validators.
- **Reuse and deletion.** The ready tranche reuses `$dedent`, `$auto`,
  `$scope`, `$let`, the existing script launcher and current probes. It deletes
  `lib/system-macros.xlisp`, 47 explicit cleanup defers, selected push/pop
  pairs and two `.x` suffixes. Later phases delete Lisp Autodiff registries,
  string-keyed state and manual native/binding rows. The only new lasting
  representation is typed Autodiff state; it replaces an existing dynamic
  map and is required to exercise represented meta records.
- **Idiomatic x2c.** The campaign composes shipped decorators, protocol
  conformances, ordinary x2c scripts and meta declarations. It does not import
  a foreign registry framework, add source-origin authentication or create a
  second ownership model.
- **Validators, diagnostics and negative fixtures.** No new validator or
  dedicated diagnostic is proposed in the ready tranche. Existing help,
  script, defer, macro and REPL checks preserve deliberate output and cleanup
  behavior. Native-meta rejection tests remain necessary to prevent wrong
  signatures and unsafe pointer crossings. Lifetime certification rejects an
  unknown reachable call only in opt-in certification mode because otherwise
  the claimed escape/finalization proof would be unsound; ordinary warning
  behavior remains unchanged.
