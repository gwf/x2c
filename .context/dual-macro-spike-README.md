# Compiler dual-macro research branch

This branch publishes investigation artifacts, not a production feature.
The authoritative current recommendation and its missing proofs are in
`plans/compiler-dual-macro-contract.md`. The earlier two plans retain the
history of the design; their surface proposals are superseded where the current
contract differs.

## Baseline and scope

The measured compiler baseline is
`1b23aaa7e103461c3b219b9e10546aeb35384b60`. Publication preserves that baseline
rather than rebasing prototype patches onto a compiler they have not tested.
At publication, fetched `origin/dev` was `171bec53`; the baseline and that ref
have diverged. This branch must not be merged into dev as a feature patch.
No production source or bootstrap artifact is changed by the research commit.

These selected `.context/` files are deliberately tracked on this research
branch so its reports do not depend on ignored local evidence. They are not
build inputs, installed code, new tests or recurring validation requirements.

## Evidence map

- `dual-macro/`: initial models and probes; historical evidence.
- `dual-macro-phase2/`: shared Match relation, parser/value prototypes,
  construction/recognition probes and transport investigations.
- `dual-macro-phase3/capture/` and `hygiene/`: logical captures and binding-aware
  recognition, including mismatch cases.
- `dual-macro-phase3/stages/`: retained/expanded calls, sequence reconstruction,
  a bounded tree-rule driver, raw generated-file comparisons and paired timings.
- `dual-macro-phase3/compiler-use/`: compiled-in bound-hole control, open target
  value/Type probes, the failing local-shadow case, and the current transaction
  rollback gap. The `.patch` files are experiments to apply only to disposable
  copies. They are not changes applied to this branch's production source.
- `dual-macro-phase3/grammar*.md`: observed canonical productions, field roles,
  owner census and producer policy. Completeness limits are in the current plan.

## Narrowed combined proof (phase 4)

`dual-macro-phase4/` records the later baseline shadow check, the combined
compiled-in template/meta-slot/effect/stage candidate, rollback probe, final
62-case comparison and five paired timing samples. The unchanged native-helper
shadow case fails identically and is a follow-up; per-unit scope-stack retention
is not recommended. The first proof supports new-name, early and cleanup only.
Other producers/effects are built when a migration first needs them.

Final candidate SHA256:
`fa2fd1f67c31f07c486fb68acc6d1edcb9fdc2d7b23250d812935f28c00c1148`.
The combined patch is incremental on the preserved phase-3 bound-hole control.
Its README records private adapter scaffolding and coverage limits. Timing
ranges overlap; noisy live-mode medians are not evidence of a speedup.
`capture-scope.md` scopes the first independent production consolidation for
another branch; it is not implemented here.

## Open body and producer-stage proof (phase 5)

`dual-macro-phase5/` records the true-open try body, wrapper-free client,
parse/bind preparation including synthetic-try origins, same-binary rollback
and 62-case raw C/H comparison, and paired timings. Its historical observed
compiler cost total is +1.40% default and +1.94% live; it replaced the older try
candidate's ledger row. The plan freezes stage attachment at producing owners.
Its README includes the native declaration boundary and failed attempts.

**This research branch must not be merged as is.** Phase4 tracks full copies of
five compiler sources. Phase5 adds an incremental patch and source hashes,
not production implementation. Capture-role consolidation remains independent
and authorized for a separate ordinary production branch.

## Reproduction limits

The integrated value prototype used `relation.patch`, `parser3.patch`,
`stages.patch` and `capture.patch` in that order on an isolated baseline copy.
The compiler-use control patch is incremental on that integration. Open policy
and Type patches require intermediate parser/producer builds before compiler
source can consume their new forms; see `compiler-use/open-policy.md`.
Earlier parser patch variants and failed probe logs are retained as history,
not an instruction to apply every patch consecutively.

Reports and logs record absolute paths from the original worktrees. Recreate
those roles in disposable copies or adjust paths deliberately. Comparison
requires both binaries to use identical source paths and explicit common
`X2C_HOME`; otherwise resource discovery and diagnostic path differences make
raw C comparison invalid. Do not normalize generated output to obtain parity.
Native binaries, complete temporary generated trees and bootstrap outputs are
not included. JSON manifests preserve generated-file hashes and statuses;
timing samples are observations from the original host, not portable thresholds.
The comparator does not compare diagnostic text. The narrowed try meta-slot/effect/stage path is proved by phases 4 and 5;
generic role extraction, helper transport and arbitrary conversion contexts
remain separate unproved areas.


## Research closure and production hand-off (phase 6)

The production hand-off consists of three independent scoped plans:

- `plans/dual-macro-core-support.md`: reusable support with old lowerings intact,
  then ordinary bootstrap refresh before consumers.
- `plans/dual-macro-try-migration.md`: depends on delivered, bootstrapped core;
  preserves the 62-case raw C/H proof and ordinary self-host comparison.
- `plans/macro-capture-role-consolidation.md`: independent refactor deliverable
  on dev now under ordinary rules.

`.context/dual-macro-phase6/profile/` contains one-off instrumentation and
measurements, not production code or recurring checks. All `.context` evidence
is reference only. **Do not merge this branch.** In particular phase4 contains
full copies of five compiler sources. Implement the plans fresh on current dev;
do not transplant those snapshots or the intermediate name bypass.


## Fixed support cost and selective candidate (phase 7)

`dual-macro-phase7/` separates extended snapshot work, ordinary-node carrier
checks and open preparation from per-try application work. The selective
candidate protects effects only inside the construction context and recognizes
stage carriers only inside application binding. It preserves the 62-case raw
C/H comparison, rollback proof and original total transaction counts, while
reducing extended snapshots from 2119/2124 to two in the compiler corpus.

The phase6 recommendation to raise the planning aim to 5% is withdrawn.
The production core plan starts with selective transaction and application
contexts; the try plan uses phase7's same-window baseline/phase5/new timings.
The 2% cumulative aim remains a recommendation, not a new recurring gate.
Automatic standalone application entry and legacy effect-carrier ownership
remain production implementation work rather than claims of this bounded
performance prototype. Do not merge this branch or transplant its snapshots.
