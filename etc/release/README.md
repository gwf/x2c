# Public release operations

The source workflows live in `.github/workflows`: `candidate.yml` builds an
exact source commit, `stage.yml` publishes and verifies staging, `promote.yml`
promotes tested archives, `verify.yml` supplies the shared platform checks, and
`restore-pages.yml` restores a previously verified production site. This
folder owns their transport helpers and the staging repository's Pages
template.

Everyday integration uses `dev`; `main` is the published-release branch.
Release tasks follow [releasing](../../agents/releasing.md) and this document.
The source repository is the public `gwf/x2c`. The public `gwf/x2c-staging`
stores generated output and immutable candidates; it is not a development
source tree.

The release owner approves production publication, advances `main`, and
creates release tags. The workflows never create or move `main` or a
production tag.

## Account setup

The release setup consists of these account settings. They hold
permissions and one credential, not values embedded in source.

1. `gwf/x2c-staging` has a `main` branch with its minimal Pages workflow
   (the `staging-pages.yml` template installed as
   `.github/workflows/pages.yml`). Actions are enabled, and GitHub Actions is
   its Pages source. The output publisher requires an existing `main` commit.
2. A GitHub App installed only on the staging repository has Contents and
   Actions read/write access. Its App ID is `STAGING_APP_ID` and its private
   key is `STAGING_APP_PRIVATE_KEY` in the source repository's protected
   `staging-publication` environment. Build jobs never receive this key.
3. The staging repository's `github-pages` environment permits its `main`
   branch and grants `pages: write` and `id-token: write`. Source
   publication jobs cannot use their own Pages token to deploy another
   repository.
4. Staging Pages serves `staging.x2c-lang.dev` over enforced HTTPS, through a
   DNS CNAME to `gwf.github.io` and a domain verified by the owning account.
   Production Pages serves `x2c-lang.dev` from `main`.
5. In the source repository, `staging-publication` permits `dev`, and
   `production-publication` permits `main` and requires the release owner's
   review. Repository settings allow the workflow token to write release
   assets.
6. Allowed Actions, App policy, and branch and tag rules match these
   workflows. Workflow artifacts expire after 30 days; publicly staged assets
   and promoted candidates are kept indefinitely, so artifact expiration
   never deletes a durable asset.

The App key is the only transport credential. Rotate or revoke it in the
account settings, and never put it in logs, checkout files, or chat.

Dispatch promotion and restoration with `--ref main`. The `pages.yml` source
workflow builds the site from source; its registration is disabled, so it is
not a publication path. The release owner can re-enable it for a site
recovery that has no retained site archive. These manually requested release
jobs are never required statuses for ordinary changes.

## Candidate and release operation

Run `candidate.yml` from `dev` with a full reviewed source SHA. Each compiler
and package job checks out that SHA; its matrices come from
[the released set](../../agents/releasing.md#released-packages). Assembly
uses the built Linux compiler once and retains the resulting archives,
manifest, two index variants, and two complete site archives. Native
archive bytes never change during promotion.

A candidate ID contains the source SHA, run ID, and attempt. A fresh full
build gets a fresh ID even for the same compiler version. Download-only
publication jobs use reviewed workflow and helper code, not source scripts
from the candidate. Select the exact successful build run and identity for
staging, plus the currently observed output-repository `main` SHA. The
publisher uploads complete immutable assets first, then compare-and-swaps the
entire generated `public/` tree, dispatches its exact commit, and waits for
Pages completion. Existing same-name assets must match; there is no clobber
operation. Never infer the selection from "latest". A superseded staging
dispatch fails before deployment.

Verify staging with a fresh scratch prefix and the candidate's explicit
package index. Compiler version checks cannot tell apart two candidates with
the same version. Keep
`--index https://staging.x2c-lang.dev/packages/index.txt` on staging package
commands; an ordinary compiler's default index is production. Do not use
`--force` to hide mismatches.

Complete the final full rebuild before the final live staging verification.
Retain successful aggregate receipts for all four platforms with their
manifest and site hashes, run URLs, and attempts. Receipts use append-only
names per run and attempt, so a failed receipt upload cannot replace a prior
receipt. Promotion accepts only a receipt whose exact staging workflow attempt
completed successfully.

The release owner selects one exact verified candidate, fast-forwards `main`
preserving commits, and creates its annotated version tag. Promotion checks
that both point to the selected source, uploads those same bytes to a draft
release, verifies the remote assets, publishes the release, and deploys the
retained complete production site. Production success requires live
verification, not only a successful upload or Pages job. `dev` may continue
throughout candidate testing.

## Recovery

Publication is coordinated, not atomic across `main`, tags, Releases, and
Pages. Keep partial deployment receipts and inspect the last completed step
before retrying. Missing matching assets can be resumed; conflicting bytes
stop the operation. Never rebuild an expired candidate during promotion, move
an exposed tag, or force-reset `main`. If durable candidate assets are lost,
build and verify a new candidate.

If the output commit was written but dispatch failed, dispatch staging Pages
with that recorded exact output SHA while holding the staging publication
lock. Do not replay an old expected-output SHA and overwrite a newer
selection. If a Pages run is still running after a timeout, let it finish or
have the release owner resolve it before starting another publication.
Publication workflows serialize per destination without cancelling a running
publication.

`restore-pages.yml` is the production rollback path for a previously promoted
candidate. The release owner selects its exact identity and the currently
observed production version, then dispatches from `main`:

```sh
gh workflow run restore-pages.yml --repo gwf/x2c --ref main \
  -f identity="$candidate" -f expected_version="$current_version"
```

Set those two shell variables to the selected candidate and the observed
current version first. The workflow retrieves the retained site and
production verification receipts, requires a successful original promotion
attempt, guards the current site version, deploys the complete previous site,
and runs the four-platform live checks. Only after those succeed does it
restore the latest-release designation. It does not build the compiler or
packages, reupload archives, or move `main` or tags. Its run summary and
retained restoration receipt state both the `main` and restored source SHAs;
a discrepancy requires a patch release and return of that fix to `dev`. A
failure after site restoration leaves a partial recovery; inspect the run
before retrying with the now-current site version.

Restoration requires an earlier candidate with production receipts, so it
restores only releases that this pipeline promoted. A site rebuilt from source
is a new site, not the previously deployed one.

A release may become visible before Pages succeeds; report this partial state
and retry the retained site. If production verification fails, restore the
previous site, version, index, and latest-release designation; keep immutable
assets and tags available for lockfiles. Report that `main` may lead the
restored site, and follow with a patch release. Production fixes return to
`dev` without discarding later `dev` work.

## Cost

Each requested full candidate costs one build job per compiler platform and
per released bundle. Tags do not trigger a rebuild. Live checks add four
small install-and-run jobs after staging and four after production.

## Local verification

Run `python3 tools/test-release-candidate.py` for offline candidate integrity,
conflicting upload, receipt retry, and restoration-proof cases. Run
`npm --prefix site test` for destination rendering. The installer check
(`tools/check-install-script.sh`) covers same-version candidate selection as
well as production defaults. Run `actionlint` against the source workflows.
Validate the `staging-pages.yml` template in a temporary workflow tree as
needed. None of these adds a gate. Finish a change to the release workflows
or helpers with `tools/gate-state.py ensure agent-pr-check`; in a sandboxed
checkout, set `X2C_CACHE_DIR` to a writable scratch directory.

## Website-only staging

To update the website from dev without replacing the staged compiler or
packages, dispatch `stage.yml` from dev with `mode=website`, a full
`source_sha`, and the current staging repository `main` as `expected_output`.
The candidate inputs are unused in this mode. The existing staging publication
concurrency group and output compare-and-swap also protect this path.

`staging-website.yml` builds only Astro and mdBook. It copies the staged
installer, version, release-candidate identity, package directory, domain,
and existing release PDF byte for byte. It never uploads release assets.
`website-deployment.json` records the website source and hashes of retained
files; HTML separately identifies its website source and staged candidate.
The resulting website is not a newly verified compiler candidate and does not
alter immutable candidate archives or promotion receipts. Full-candidate
staging will replace this website-only update on its next deployment.

Local checks are `python3 etc/release/test-prepare-website.py` and
`node --test site/tests/release-destination.test.mjs`.
