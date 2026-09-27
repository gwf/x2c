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
The comparator does not compare diagnostic text. The full meta-slot/effect/stage
path remains unproved and unmeasured, as the plan states.
