# Public release operations

The source workflows live in `.github/workflows`: `candidate.yml` builds an
exact source commit, `stage.yml` publishes and verifies staging, `promote.yml`
promotes tested archives, `verify.yml` supplies the shared platform checks, and
`restore-pages.yml` restores a previously verified production site. This
folder owns their transport helpers and the staging repository's Pages template.

Gary has cleared the fresh-main checkpoint and dev cutover. Everyday integration
uses dev; main remains the published-release branch. Do not inspect or alter the
two unrelated lowering/metafunction sessions. Workflow installation does not
publish a release or supply the staging App credential and domain configuration.
The legacy `pages.yml` source remains unchanged, but its workflow registration
is disabled. Retain it until first-release baseline recovery is settled.

The governing design is [public-release-workflow.md](../../plans/public-release-workflow.md).
The source repository stays public at `gwf/x2c`. `gwf/x2c-staging` stores generated
output and immutable candidates; it is not another development source tree.

## Provisioning state (2026-09-19)

Local GitHub authentication is `gwf` with ADMIN access to `gwf/x2c`; it already
covers repository administration. No additional personal token is needed.
Remote `dev` was created at fresh main
`b265e2582df4e6d9172f70de3add039e7df3b41b`. The public staging repository exists,
with its Pages workflow installed at
`294be71157d8b809c5f346d90b5f44a55715ac0d`. Pages is configured for
`staging.x2c-lang.dev`.

Source `staging-publication` permits dev; `production-publication` permits main
and requires Gary's review. Production Pages still permits only main and keeps
its existing `x2c-lang.dev` configuration. Dispatch promotion and restoration
with `--ref main`, after Gary's separately authorized main advance has carried
their source there. They cannot run from pre-cutover main, which lacks them.

The legacy tag-driven release and Pages workflow registrations are disabled.
The legacy Pages source remains unchanged, so Gary can explicitly re-enable it
for an agreed baseline recovery operation. It is not a callable competing
publication path while disabled. No production deployment or release was run.
Disabling a workflow leaves the currently served site intact.

Remaining setup: Name.com DNS CNAME `staging` -> `gwf.github.io`, GitHub HTTPS
provisioning, and the staging App ID/private key in source environment settings.
The initial DNS query returned no staging records. Never paste the key in chat.
These prerequisites must be verified before claiming live staging success.

## Account setup

Gary needs account access, not secrets pasted into a conversation:

1. Create the authorized public `gwf/x2c-staging`. Initialize `main` with its
   minimal Pages workflow (the staging-pages.yml template installed as
   `.github/workflows/pages.yml`). Enable Actions and select GitHub Actions as
   its Pages source. The output publisher requires an existing main commit.
2. Create/install a GitHub App limited to that staging repository with Contents
   read/write and Actions read/write. Install its App ID as `STAGING_APP_ID`
   and its private key as `STAGING_APP_PRIVATE_KEY` in the source repository's
   protected `staging-publication` environment through GitHub's settings UI.
   Build jobs never receive this key. An expiring fine-grained token is an
   alternative only if Gary explicitly selects that design.
3. Give the staging repository's `github-pages` environment access to its
   main branch. Enable Pages token permissions (`pages: write`,
   `id-token: write`) there. Source publication jobs cannot use their own Pages
   token to deploy another repository.
4. Configure staging Pages' domain as `staging.x2c-lang.dev`, add its DNS CNAME
   to `gwf.github.io`, verify the domain with the owning account, and enable
   HTTPS. Keep production's domain assignment unchanged.
5. Configure source `production-publication` and `github-pages` environments
   with Gary's release approval authority. Confirm repository settings allow
   the workflow token to write release assets. The workflow never creates or
   moves `main` or a production tag; Gary performs those explicit operations.
6. Confirm allowed Actions, artifact retention (30 days), App policy and the
   branch/tag rules using real account settings. Keep publicly staged assets
   and promoted candidates indefinitely until a different retention contract
   is explicitly approved. Artifact expiration must not delete durable assets.

The App key is the only additional transport credential in the recommended
setup. Domain access and repository/environment administration are account
permissions, not values to embed in source. Rotate/revoke the key in account
settings, and never put it in logs, checkout files or chat.

## Activation checklist

- The approved initial dev baseline is fresh origin/main at
  `b265e2582df4e6d9172f70de3add039e7df3b41b`. Preserve individual commits when
  integrating this preparation and future work. Existing sessions retain their
  own routing until Gary explicitly transitions them.
- Dev is the chosen default branch for everyday integration and PR bases.
  Keep main release-only and retain Gary's existing tag/promotion authority.
  Configure the publication environments before dispatching their workflows.
- Disable the legacy release workflow before activating candidate.yml; the
  legacy release.yml is removed from dev. A v-tag must not trigger a second
  compiler/package build through a workflow still registered on main.
- Keep legacy pages.yml unchanged until the first-cutover recovery prerequisite
  below is resolved. The new promotion/restore workflows deploy retained site
  archives directly and never dispatch legacy pages.yml.
- Install staging-pages.yml only in the output repository as
  `.github/workflows/pages.yml`. Review the installed template revision and
  ensure it is dispatchable from that repository's default branch.
- Finish repository/account provisioning, routing documentation and the existing
  applicable gate before publication. Keep ordinary precommit, sanity-check,
  agent-pr-check and doc-check unchanged. These manually requested release jobs
  are never required ordinary statuses.

## Candidate and release operation

Run `candidate.yml` from dev with a full reviewed source SHA. Each compiler
and package job checks out that SHA; the existing four compiler and 26 package
matrix jobs remain intact. Assembly uses the built Linux compiler once and
retains the resulting archives, manifest, two index variants and two complete
site archives. Native archive bytes never change during promotion.

A candidate ID contains source SHA, run ID and attempt. A fresh full build gets
a fresh ID even for the same compiler version. Download-only publication jobs
use reviewed workflow/helper code, not source scripts from the candidate.
Select the exact successful build run and identity for staging, plus the
currently observed output-repository main SHA. The publisher uploads complete
immutable assets first, then compare-and-swaps the entire generated `public/`
tree, dispatches its exact commit and waits for Pages completion. Existing
same-name assets must match; there is no clobber operation. Never infer selection
from "latest". A superseded staging dispatch fails before deployment.

Use a fresh scratch prefix and the candidate's explicit package index. Compiler
version compatibility checks cannot establish identity between same-version
candidates. Keep `--index https://staging.x2c-lang.dev/packages/index.txt` on
subsequent staging package commands; an ordinary compiler's default index
remains production. Do not use `--force` to hide mismatches.

Complete the final full rebuild before the final live staging verification.
Retain successful aggregate receipts for all four platforms with their
manifest/site hashes, run URLs and attempts. Receipts use append-only names
per run/attempt; a failed receipt-upload run cannot replace a prior receipt.
Promotion accepts only a receipt whose exact staging workflow attempt has
completed successfully. Gary selects one exact verified candidate, fast-forwards
main preserving commits and creates its annotated version tag. Promotion
checks both point to the selected source, uploads those same bytes to a draft
release, verifies remote assets, publishes it and deploys the retained complete
production site. Production success requires live verification, not merely a
successful upload or Pages job. Dev may continue throughout candidate testing.

## Recovery and rehearsal

Publication is coordinated, not atomic across main, tags, Releases and Pages.
Keep partial deployment receipts and inspect the last completed step before
retrying. Missing matching assets can be resumed; conflicting bytes stop the
operation. Never rebuild an expired candidate during promotion, move an exposed
tag or force-reset main. If durable candidate assets are lost, build and verify
a new candidate.

If the output commit was written but dispatch failed, dispatch staging Pages
with that recorded exact output SHA while holding the staging publication lock.
Do not replay an old expected-output SHA and overwrite a newer selection. If a
Pages run is still running after a timeout, let it finish or have Gary resolve
it before starting another publication. All ordinary publication workflows
serialize per destination without cancelling running publication.

`restore-pages.yml` supplies the executable production
rollback path for a previously promoted candidate. Gary selects its exact
identity and the currently observed production version, then dispatches from
the approved trusted workflow ref (dev), for example:

```sh
gh workflow run restore-pages.yml --repo gwf/x2c --ref main \
  -f identity="$candidate" -f expected_version="$current_version"
```

Set those two shell variables to the deliberately selected candidate and
observed current version first. The workflow retrieves the retained site and
production verification receipts, requires a successful original promotion
attempt, guards the current site version, deploys the complete previous site,
and runs the existing four-platform live checks. Only after those succeed does
it restore the latest-release designation. It does not run compiler/package
builds, reupload archives, move main or move tags. Its run summary and retained
restoration receipt state both main and restored source SHAs; a discrepancy
requires a patch release and return of that fix to dev. A failure after site
restoration leaves an explicitly partial recovery; inspect the run before
retrying with the now-current site version. This is a manually requested
recovery operation, not an additional ordinary gate.

This command requires an earlier candidate with production proof. It cannot
claim to restore a legacy release that predates retained candidate/site
artifacts. Record a separate approved legacy-site recovery route before the
first cutover if that is the production baseline.

A release may become visible before Pages succeeds; report this partial state
and retry the retained site. On failed production verification restore the
previous entire site/version/index and previous latest-release designation;
keep immutable assets/tags available for lockfiles. Report that main may lead
the restored site and follow with a patch release. Production fixes return to
dev without discarding later dev work.

Before the first release, stage two same-version candidates and verify old URLs
still work, production did not move, and each staging installer/index selects
its own bytes. Rehearse interrupted upload, conflicting bytes and stale output
selection using mocks/local data. Then rebuild the final candidate, verify it
on all four platforms (torch on its two supported platforms), inspect HTTPS,
site/book/search and the retained production variant, and promote that identity.
Compare archive digests across staging and production and check prior URLs.

Release cost remains 30 build jobs per explicitly requested full candidate;
removing tag rebuilds avoids repeating that matrix. Live checks add four small
install/run jobs after staging and four after production, with torch on two
platforms. First-release fault/two-candidate rehearsal is one-time. Activation
must have the agreed cost approval; do not invent a new ordinary gate.

## First-cutover recovery prerequisite

The restoration workflow accepts releases produced and verified by this new
pipeline. The pre-cutover production release has no such receipt. Before
retiring the old Pages workflow, capture its exact deployed Pages artifact,
record its SHA-256 and deployment/run ID, and rehearse deploying that retained
artifact through Pages without rebuilding the site. Preserve that baseline
and its separate Gary-approved recovery procedure for the first release.
The currently inspected legacy Pages artifact has expired. Baseline capture
and its recovery procedure remain unresolved and must be settled with Gary
before the first production promotion; do not label a fresh site rebuild the
previously deployed site. Keep the legacy Pages source available with its registration disabled until
this recovery decision is
settled. It does not authorize inspection or changes to ongoing sessions.

## Local verification

Run `python3 tools/test-release-candidate.py` for offline candidate integrity,
conflicting upload, receipt retry and restoration-proof cases. Run
`npm --prefix site test` for destination rendering. The existing installer
check covers same-version candidate selection as well as production defaults.
Run `actionlint` against the installed source workflows. Validate the separate
staging-pages.yml deployment template in a temporary workflow tree as needed. None of these adds a gate. Finish with the unchanged
`tools/gate-state.py ensure agent-pr-check`; a sandboxed checkout can set
`X2C_CACHE_DIR` to a writable scratch directory.
