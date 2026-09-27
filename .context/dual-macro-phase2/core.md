# Executable core and contextual Match prototype

## Observed results

`core.x` runs under the unchanged baseline compiler/runtime. It passes shared-body arithmetic construction/recognition, repeated-value agreement/mismatch, empty/nonempty sequence reconstruction, body composition, alpha-equivalent declarations, shadow/free-reference failures, surrounding-local capture comparison, joint relocation across holes, independent copies of a closed declaration region, and closed-region sequence retry. The return forms retain the ordinary canonical return-type slot. Placeholder operand atoms in some data cases are comparison fixtures rather than bound executable expressions.

The body supplied to these core operations is one canonical List, shared for recognition and construction. `instantiate` uses existing `List.replace` after one joint capture-row identity relocation. `recognize` uses existing Match. Generic comparison visits Lists and recognizes only canonical binding leaves; ownership and boundary maps are supplied side metadata. The transient `local`/`boundary`/`free` records are comparison keys, not a program AST accepted by the binder.

The next integrated prototype in `relation.x` proves the previously open retry mechanism in REAL x2c code and the existing Match machine. It runs in the managed isolated checkout `/Users/gary/.codex/worktrees/dual-macro-match-probe/x2c`, exact starting baseline `1b23aaa7e103461c3b219b9e10546aeb35384b60`. Changes are retained in `relation.patch`: optional per-machine relation function/context, used by repeated-value comparisons and repeated sequence prefix/final comparisons. There is no separate search algorithm.

The callback reads the fixed surrounding declaration ID from an already captured machine slot. It computes an alpha comparison using private declaration ownership maps plus that boundary ID. The first candidate refers to a different same-labeled surrounding ID and fails; the engine retries and accepts a later candidate with a renamed private declaration and the correct surrounding ID. Separate tests exercise repeated value captures, a repeated final sequence span, and a repeated interior-prefix span. Each asserts at least two contextual comparisons and at least one rejection, checks that `between` captured exactly the wrong candidate, then finishes and checks a clean machine. A miss run rejects and finishes clean as well.

## Commands and retained evidence

```
builds/0/x2c run --build-dir /tmp/x2c-dual-phase2-core \
  .context/dual-macro-phase2/core.x
```

Root log: `debug/dual-macro-phase2-core.log` (root independently reran the original core; return-slot correction subsequently retained).

In the isolated Match checkout:

```
mkdir -p debug && make build-safe >debug/bootstrap.log 2>&1
make build >debug/relation-build.log 2>&1
make build >debug/relation-span-build2.log 2>&1
builds/0/x2c run --build-dir /tmp/x2c-dual-phase2-relation \
  .context/dual-macro-phase2/relation.x >debug/relation-final-run.log 2>&1
git diff --check
```

All final commands succeeded. Initial span-extension build failed because the Array constructor declaration was absent; adding the ordinary Array include fixed it. Root copied final log: `debug/dual-macro-phase2-relation.log`.

Final output:

```
core: shared body, sequences, composition, alpha scopes, joint relocation, closed contextual retry PASS
relation: actual Match retries contextual alpha equality with live local slot and shadow mismatch PASS
```

The prototype adds 31 lines/removes 2 across `lib/machine.x`, `lib/match-machine.x`, and `lib/match.x` IN THAT ISOLATED CHECKOUT ONLY. No root production source edits, commit, push, publication gate, or bootstrap source refresh occurred.

## Limits and implementation implications

- This extension demonstrates contextual failure joins existing value/span retry, using a read-only policy over journaled capture state. It does not need an extra journal for the policy shown. A future mutable bijection policy needs journaling or derivation from captured slots.
- Materializing comparison spans and temporary views is intentionally direct prototype code; no allocation/performance measurement was performed. Existing default relation behavior is retained, but the complete Match unit suite was not run.
- Ownership/scope metadata is supplied explicitly. Complete parser/binder discovery, all namespaces, source-category comparison and injectivity in a general derived template are not implemented here.
- Core body fixtures are authored canonical AST Lists; parser worker's real macro-value getter and source Match adapter must connect these operations to body/interface fields before claiming whole simple-form integration. This core alone does not prove the new getter, anonymous form, helper transport or executable ordinary rebinding.
- Joint relocation demonstrates one declaration from an earlier hole and a reference in a later hole remap consistently. Closed duplicate-region tests use separate insertion maps. Ambiguous cross-hole references to a region copied twice are not resolved; require an explicit occurrence map or fail.
- Boundary availability is demonstrated when the fixed local slot is already captured before repeated-hole comparison. Forward correspondence to a fixed declaration matched later must defer contextual obligations or compare after that slot becomes available INSIDE the retry transaction; it cannot be silently treated as a rigid free reference. This remains an isolated next case.
- Full roundtrip equality after ordinary binding remains the parser/insertion integration responsibility. The tests prove comparison equality and structural reconstructed reference incidence, not every contextual compiler effect.

## Deferred correspondence checkpoint, additionally executed

The later correspondence case now has a working bounded solution using existing Match grammar and the same relation hook, without a new opcode. Capture occurrences in separate `?first`/`?second` slots. At a fixed declaration captured later, lower its identity field to `(!and ?local ?local)`. The first local capture publishes the local ID into the attempt's journal; the repeated occurrence triggers the contextual policy, which can now read both prior occurrences and the known local slot. Rejecting this checkpoint follows the existing Match failure continuation and causes the earlier interior star to retry.

`deferred_obligations` in `relation.x` executes this strategy. It asserts exactly two completed checks and one rejection, selects the later acceptable capture, verifies `between` contains the rejected candidate plus the intervening declaration, and checks clean teardown. Final log adds:

```
deferred: later local equality checkpoint rejects prior captures and retries within Match PASS
```

This fixture supplies synthetic identity-bearing canonical AST data to isolate matching control flow. It does not establish that its declaration ordering/placement is a valid ordinary executable block. Its conclusion is specifically that an existing structural equality checkpoint can discharge earlier semantic obligations inside retry; producer-owned metadata and checkpoint placement remain compiler integration work. The prior statement that this requires a next experiment is superseded for this bounded control-flow case, not for all grammar/context obligations.

## Parser helper cross-review

Reviewed `/Users/gary/.codex/worktrees/dual-parser/x2c/.context/parser-spike/macro.x`. `Macro_pattern` and `Macro_apply` both obtain `template` and `parameters` from the actual descriptor, so arithmetic/repeated/sequence Expr cases genuinely share the real source macro body. The view removes macro-expression shells and derives hole mappings, rather than authoring a separate arithmetic pattern.

Before claiming complete alpha source integration, connect descriptor `fresh`/capture roles to construction freshening and recognition ownership/boundary metadata. `Macro_apply` currently replaces parameter projections only and does not itself consume fresh rows. `Macro_pattern` currently leaves introduced-local replacement binders to ordinary Match without the general namespace/injectivity/cross-hole relation interface. Mapping all Name projections to one selected binder is insufficient for mixed member-label, identifier-shell and declaration uses. These are concrete missing integration pieces, not evidence against the shared-body approach. Arithmetic Expr forms can be reported separately as completed parser/helper prototypes.
