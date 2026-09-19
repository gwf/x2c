---
name: release-x2c
description: >-
  Prepare, stage, promote, and verify an x2c release, or recover from a failed
  or broken one. Use when Gary asks to cut, publish, tag, or check a release,
  to bump the compiler version for a release, or when a release workflow
  run or published release has failed. Do not use to change what the
  release workflow builds; use plan-x2c-change or execute-x2c-plan. Do not
  use to add a package bundle; use integrate-x2c-package.
---

# Release x2c

Take one selected commit from `dev` through staging to a verified production
release. Read [agents/releasing.md](../../releasing.md) for the sequence and
[deployment operations](../../../etc/release/README.md) for provisioning,
recovery and first-release constraints.

Gary authorizes production promotion, advancement of `main`, and release tags.
Keep those actions separate from ordinary implementation delivery to `dev`.
Give him exact candidate identities, source SHAs, effects and commands when
his action is required. Do not infer release authorization from plan approval.

## Prepare and stage

Land version preparation on `dev` through the root delivery policy and existing
gate. Skip a bump when the intended version remains unpublished. Dispatch
`candidate.yml` only for the selected full SHA; record its successful run,
manifest and independent candidate identity. Staging is a separate explicit
`stage.yml` operation, bound to the expected current staging output.

Wait for the entire staging workflow, including four-platform verification
and durable receipts. A final rebuild invalidates earlier verification and
requires a new candidate. Diagnose failed jobs and repair on dev; never
substitute fresh archives into a previously verified identity.

## Promote and verify

Hand Gary the main fast-forward and annotated-tag commands pinned to the
verified candidate SHA. Check ancestry and current main first; stop on a
conflicting published version or tag. A tag triggers no rebuild.

With explicit release authorization, dispatch `promote.yml` for that candidate
and the observed previous production version. Follow asset upload, complete
site deployment, live verification and retained proof. Report success only
after all finish; a green build, tag or visible release alone is insufficient.

## Recover

Use the recovery instructions in deployment operations. Preserve immutable
archives and resume missing identical uploads. Restore a previous verified
complete site when necessary, retaining public tags/assets and reporting any
main/site discrepancy. Prepare a patch candidate for defective published bytes
and ensure production fixes return to dev. Never force main, move a public tag,
clobber release assets or treat a fresh build as promotion of tested bytes.
