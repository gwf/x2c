> Status: blocked
> Gary approved this plan on 2026-09-19; local tooling and inactive templates
> are implemented. Local validation is recorded in the task; hosted validation
> and reconciliation with the later checkpoint remain outstanding.
> Live activation and cutover remain blocked; existing routing stays in force.
> Cutover awaits Gary's explicit clearance and identification of a stable
> checkpoint from the TWO ongoing X-to-C-to-Lisp and metafunctions sessions.
> Their relevant/shared branch is UNIDENTIFIED. Do not inspect, contact,
> interrupt, alter, rebase, or merge those sessions or branches for this plan.

# Public dev, staging, and production

## Result and authorization

Keep one public source repository, `gwf/x2c`. Eventually use `dev` for everyday
integration and `main` for the latest published release. Preserve individual
commits when advancing `main`, preferably by fast-forward to the tested source
commit. Publish repeated, explicitly selected candidates at
`https://staging.x2c-lang.dev`; production remains `https://x2c-lang.dev`.
Propose `gwf/x2c-staging` as a public deployment repository containing generated
site output, immutable candidate assets, and minimal deployment plumbing, not
another compiler source tree. No authentication or privacy layer is needed.

The initial planning task authorized only this document. Gary subsequently
approved isolated implementation in this checkout, without requiring the
stable checkpoint first. This authorizes local tooling, inactive workflow
templates and validation, but no commit, push, PR, repository creation, DNS
change, dispatch, branch-policy change or interference with active sessions.
Preparation must not change live routing. Cutover is
separately conditional on clearance; do not create `dev` now or guess its
starting branch. Gary's later identified stable checkpoint is his preferred
initial `dev`.

## Evidence at the planning checkout

Inspected source commit: `9068589741b4fa9d58f2aada022e6c8fcaf53317`.
These are checkout facts, not a claim about current remote settings or sessions.

| Owner | Current behavior and consequence |
| --- | --- |
| `.github/workflows/release.yml` | Manual runs build and assemble only. Tag runs repeat builds, publish with `--clobber`, commit pointers to current `main`, then dispatch Pages. This cannot promote exactly the already tested bytes. |
| Release `compiler` / `bundles` jobs | Four compiler platforms: macos-15, macos-15-intel, ubuntu-24.04, ubuntu-24.04-arm. Six packages on all four: pcre2, yyjson, libcurl, termbox2, libuv, blis; torch on macos-15 and ubuntu-24.04. Thus four compiler and 26 bundle jobs; raylib excluded. Preserve this matrix and pinned runners. |
| `.github/workflows/pages.yml` | Manual workflow always checks out `main`; Pages concurrency cancels an in-progress deployment. An arbitrary candidate SHA is not supported. |
| `site/public/install.sh` | `X2C_RELEASES` and `X2C_VERSION_URL` override production endpoints, but archive base is always `$releases/v$version`. A separate candidate tag cannot currently be selected. |
| `tools/check-release.x` | `X2C_SITE` selects fetched site files; installer subprocess sets only prefix and passes version. Package install has no `--index`. A staging check can install production compiler and packages with the same version and falsely pass. |
| `src/cli.x`, `src/install.x` | CLI already supports `--index`; `_index_row` defaults to production. `_check_bundle` compares the bundle compiler version with `cli_version`, not source SHA or candidate identity. |
| `tools/gen-package-index.x` | Existing `--base` controls archive URLs; it also creates source archives and copies bundles. Re-running it during promotion could recreate source archives. |
| `tools/check-install-script.sh` | Builds a distribution, proves install/upgrade/package survival, and rejects a bad checksum against a local release layout. Reuse this coverage. |
| `site/site-config.mjs`, `site/scripts/build-book.mjs` | URL/base configuration exists and is used for site/book metadata. Custom domain needs `SITE_BASE=/`, not the `/x2c` fallback. Source/download links and install examples also contain literal production/main URLs. |
| `AGENTS.md`, `agents/releasing.md`, release and execution skills | Ordinary delivery currently targets `main`; release guidance reserves merges/tags to Gary. Routing and release authority need coordinated documentation changes, not an implicit change by this plan. |

GitHub constraints checked against primary documentation on 2026-09-19:
[workflow tokens](https://docs.github.com/en/actions/concepts/security/github_token)
are repository-scoped; use a separate credential for cross-repository writes.
[Pages workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
deploy in their owning repository with Pages and identity-token permissions.
[Workflow artifacts](https://docs.github.com/en/actions/tutorials/store-and-share-data)
have configurable, capped retention; they are transport, not durable release
storage. [Custom domains](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site)
need repository configuration plus DNS. Verify actual account settings only
when that future work is authorized.

## Candidate contract

Select a full source SHA, not the moving `dev` ref. `dev` may keep advancing.
Version preparation and generated bootstrap changes must already be committed
and validated at that SHA. Compiler version remains the intended release
version, for example `0.15.0`. Candidate identity is separate:
`candidate-<full-sha>-<run-id>-<attempt>` in the staging repository. Every full
rebuild, including a retry, gets a fresh identity; same-version candidates
never overwrite each other. A promotion accepts one identity, never "latest".

Retain one simple JSON manifest with source repository/SHA, compiler version,
workflow revision, build run/attempt, platform/package inventory, asset names,
sizes and SHA-256 digests, source archive digests, and destination site build
configuration. Record site archive digests and verification results in
separate append-only receipts referring to that manifest digest. This allows
verification after build without mutating the candidate manifest. Receipts
include run links, platform, commands/outcomes and deployment identity.

A completed staging release holds all archives, checksums, manifest and site
output under its unique tag. Its tag identifies deployment-repository content;
the manifest, not that tag's source archive, identifies x2c source. Publish
candidates as prereleases. Upload all assets and verify them before making
staging's current site point to the candidate. Treat exposed candidate assets
as immutable: an existing same-name asset must have the same digest or fail;
never clobber. Checksums establish identity, not authorship: trust comes from
the authorized workflow and restricted publication credential.

Retain promoted candidates and public production assets indefinitely. Recommend
retaining all publicly staged candidates initially so staging lockfiles remain
usable. Workflow artifacts/logs can expire at a documented repository-supported
period (proposed 30 days); retain the manifest and verification receipts with
the candidate before that happens. Any later public-candidate garbage collection
is a separate decision with an explicit retention contract. A missing archive
blocks promotion; a rebuild produces a new candidate and new verification.

## Small connected implementation

1. **Candidate production: `.github/workflows/release.yml`.** Keep the existing
   compiler/bundle jobs and dependencies. Add explicit source SHA and operation
   inputs: build-only remains available; stage builds and publishes a candidate;
   promotion consumes an existing verified candidate. Resolve and checkout the
   exact SHA in every source-dependent job. Keep compilation jobs read-only.
   Remove the tag-triggered rebuild/publication path when cutover activates the
   replacement; a tag must never start a second unverified build. Assemble
   archives once with the existing index generator and retain the result.

2. **Destination metadata: existing index generator and a narrow release
   assembly helper under `tools/`.** Generate both staging and production
   index variants during candidate assembly from the same sorted rows and
   archive digests. Change URL bases only: staging uses the unique candidate
   tag; production uses `gwf/x2c/releases/download/v<version>`. Do not re-tar
   source packages or rebuild native bundles at promotion. Extend the existing
   generator only enough to emit the second URL variant without regenerating
   archives. Keep destination metadata digests distinct from invariant archive
   digests. The assembly helper owns manifest, pointer overlay and copy/verify
   operations; do not build a general release service or persistent database.

3. **Installer and verification: `site/public/install.sh`,
   `tools/check-release.x`, `tools/check-install-script.sh`.** Add optional
   `X2C_RELEASE_TAG`, defaulting to `v$version`, to select the download path
   independently of archive filename/version. Generate the staging installer
   with staging version URL, staging releases base and candidate tag defaults;
   explicit environment overrides still win. Production behavior stays the
   same. In the release checker, explicitly bind all three installer endpoints
   and `x2c install --index <site>/packages/index.txt`, with checked exit status.
   Also prove the no-version/latest installer route; today's `--version` check
   bypasses the version pointer. Compare downloaded digests to the selected
   manifest, since version output alone cannot distinguish candidates.

4. **Site owner: `pages.yml`, site configuration/content and build-book.**
   Build the full site/book at the exact candidate SHA with an explicit
   destination. Overlay version, index and candidate receipt into build output;
   stop committing release pointer updates to `main`. Treat checked-in pointer
   files as local fixtures or remove them when the build has explicit inputs;
   published output must always use the selected manifest. Emit one complete
   site archive per destination, not separate pointer uploads. Staging uses
   its custom domain, visible candidate identity and isolated scratch-prefix
   install examples; production uses production URLs. Review literal links in
   `site/src/content/install.md`, `core-setup.ts`, example/slides content and
   `site/src/pages/index.astro`. Release source links pin the selected SHA/tag;
   contributor links explicitly name `dev`.

5. **Deployment transport.** Keep authoritative workflow/templates in
   `gwf/x2c`; the staging repository contains generated output and a minimal
   Pages workflow only. An authorized source workflow uploads immutable release
   assets and commits the complete staged site tree to the deployment repo,
   then explicitly dispatches its Pages workflow with that exact output commit.
   The staging workflow packages/deploys that tree without rebuilding x2c.
   Production Pages consumes the selected production site archive, with no
   implicit checkout of moving `main`. Reuse existing Pages actions and site
   build commands. Serialize publication per destination without cancelling an
   active publication; record intended candidate in the deployment receipt.
   Do not let a late older staging job overwrite a newer explicitly selected
   candidate. Reject a stale expected-current receipt at pointer publication.

6. **Routing and documentation.** At authorized cutover, update root
   `AGENTS.md`, `agents/releasing.md`, execution/release skills,
   `agents/quick-start.md`, contributing/setup guidance, installation book and
   site examples as applicable. Search current tracked configuration for
   hardcoded main/base/default branch assumptions, including Conductor setup;
   inventory user-owned routing and leave it for Gary to change explicitly.
   Everyday integration, fetch/rebase instructions and PR bases become `dev`;
   `main` stays release-only. Do not rewrite historical plans. Preserve Gary's
   tag/promotion authority until he explicitly changes it. Preserve current
   ordinary gate targets and costs.

7. **Finish implementation with authored-source review.** Review and fix the
   completed diff for duplicate producers, URL leaks, stale routing and excess
   machinery before publication validation. Review generated output separately.
   Then run the existing applicable gate on the final tree; no new ordinary
   commit/precommit gate, planning step or required status check is introduced.

## Permissions and staging setup

Proposed transport credential: a GitHub App installed only on the staging
repository, granting contents write (candidate releases/output commits) and
Actions write (explicit deployment dispatch). Keep its key in an authorized
publication environment in the source repo. A narrowly scoped expiring token
is an alternative only if Gary selects it. Build jobs receive neither credential
nor write permissions. Do not execute untrusted candidate scripts in a privileged
upload job; use reviewed workflow code and download-only inputs there.

The staging repository's Pages job uses its own token with `contents: read`,
`pages: write`, `id-token: write`. Production promotion needs source-repo
contents write for assets and Actions write only if dispatching Pages; Gary's
branch/tag operation remains separate. No cross-repository Pages-token shortcut.
Confirm actual branch restrictions, environment access and workflow-dispatch
availability before activation. Provision only after explicit authorization.

Configure staging Pages for `staging.x2c-lang.dev`, DNS CNAME to `gwf.github.io`
(no repository path), and HTTPS; verify the domain in the owning account.
Check that the production domain remains assigned to its current repository.
Keep deployment configuration in source-controlled templates and document its
installed revision. No DNS or repository setup is performed during planning.

## Build, stage, verify, promote

1. Explicitly select candidate source SHA and version. Check source ancestry
   against the last published `main` and collect the existing source gate
   evidence. If not a descendant, reconcile source history on `dev` later with
   authorization and select a new SHA; do not squash or force-update `main`.
2. Run the full existing four-compiler/26-bundle matrix. Earlier staging runs
   may be useful, but the final full rebuild MUST precede final staging
   verification. A rebuild after verification invalidates that verification.
3. Assemble immutable candidate archives and both URL variants. Build staging
   site and production site from this SHA with destination-specific settings.
   Retain both outputs. Inspect production output locally before promotion;
   it need not be byte-identical to the staging site. Archive bytes must be.
4. Publish staging assets first, then deploy the whole staging site/version/
   index together. Verify live staging against this manifest. Use a fresh
   prefix per candidate and explicit candidate index for package operations.
   An ordinary staging compiler still defaults to production for later bare
   `x2c install`: document `--index`; do not silently change global compiler
   semantics or teach the compiler a release channel.
5. Record final staging verification and Gary's selected promotion identity.
   Recheck production's expected previous release and `main` SHA, immutable
   candidate hashes, complete inventory and version/tag availability. Freeze
   this candidate only, not `dev`. Reject promotion of a used production version
   with different bytes. Obtain Gary's explicit release action under the
   existing release policy, giving exact SHAs and effects.
6. Gary deliberately fast-forwards `main` to the candidate SHA and creates the
   annotated `v<version>` tag at that SHA. Use a normal explicit push, no force;
   recheck ancestry if the expected main changed. Preserve each individual
   commit. Upload the selected candidate archives to a draft production
   release at that tag, then verify remote archive digests and metadata.
   Publish the release only when assets are complete; set latest deliberately.
   Do not build any compiler or package during this operation.
7. Deploy the retained production site archive, including production version,
   installer defaults and package index in the same Pages deployment. Verify
   live production downloads, index and installation, then mark promotion
   complete and retain its receipt. Until then report "publication in progress"
   or the exact failed step, even if main/tag already advanced.

Same-version bundles do not prove cross-candidate ABI compatibility: existing
bundle validation is version-based. Never use `--force` for staging validation;
use matched candidate archives, isolated prefixes and candidate-specific
lockfile URLs. Production fixes should normally land on `dev` and make a fresh
candidate. An urgent fix based on published `main` gets its own patch candidate;
merge that history back into `dev` before the next normal selection. Never reset
`dev` or discard newer integration commits to match production.

## Recovery is coordinated, not atomic

Git branches, tags, Releases and Pages cannot advance as one transaction.
`main` represents the published release at rest; it can temporarily lead the
live site during promotion. Keep a receipt of old/new main SHA, tag, candidate,
release asset digests and old/new site artifact/deployment IDs. GitHub logs plus
these small receipts suffice; no separate orchestration database is needed.

| Failure | Recovery and user-visible state |
| --- | --- |
| Build/assembly failure | No pointer moves; retry as a new candidate. |
| Partial staging upload | No staging pointer moves. Resume missing identical assets; reject a digest conflict. |
| Staging verification failure | Not promotable. Restore the previous complete staging site if useful; fix source and build a new candidate. |
| Main/tag advanced, production upload incomplete | Report partial publication. Resume from the immutable candidate, filling missing assets only. Do not rebuild, move public tags or reset main. |
| Release complete, Pages failure | Old site continues pointing to old assets. Retry the retained complete new site archive; do not declare success. |
| Production verification failure | Redeploy the retained previous complete site, version and index, and restore the previous latest-release designation if changed. Keep published tags/assets for lockfiles. Main may now lead the restored site: report the discrepancy and resolve with a patch release. |
| Stale/concurrent promotion | Stop before mutation if expected previous release/main differs. Serialize; inspect any partial side effects before retry, never overwrite a different candidate. |
| Lost/expired transport artifact | Use durable candidate storage after digest verification. If the durable archive is missing, stop; rebuilding requires a new candidate and staging verification. |

A rollback of site pointers cannot uninstall a downloaded compiler. Prefer a
new patch release for defective public bytes. Never hide a failure by deleting
assets users may have pinned. Re-running promotion is idempotent only for the
same manifest, existing matching bytes and recorded publication state; remove
today's unconditional `--clobber` and blanket "rerun is safe" guidance.

## Sequencing and checkpoint handoff

**Initial planning:** this local source-grounded plan only. No remote inspection was needed;
no sessions or candidate branches were inspected. Do not apply future routing
rules to current sessions.

**Possible isolated preparation later:** only after separate authorization,
prepare tooling/docs/templates on an isolated branch rooted at a checkpoint
Gary supplies. Keep current live workflows/routing intact until activation;
local fixtures can exercise candidate assembly, routing and recovery. No
assumption that approval of isolated code preparation also approves dispatch,
repository creation, DNS changes or cutover.

**Cutover checklist, only after explicit clearance:**

- Gary identifies both sessions and their relevant branch/checkpoint himself,
  confirms they are stable and grants clearance. Record full source SHA and
  scope of clearance. This plan supplies no guessed branch name.
- Record last successful production version/tag/source SHA, actual main SHA,
  site/version/index, remote rules and pending release/deployment operations.
  Do not reset today's main to an old release just to establish the new model.
- Verify Gary's preferred checkpoint contains intended work and published
  history. If ancestry or release baseline differs, present the concrete
  reconciliation choice to Gary before any branch manipulation.
- Record authorizations for implementation delivery, staging repo/domain,
  credential ownership, default-branch/routing changes and first promotion.
  Settle open decisions below. Preserve existing release authority otherwise.
- Coordinate the handoff with Gary; active agents keep their original routing
  until he explicitly transitions them. Do not bulk retarget active work.
- Create initial `dev` at the approved stable checkpoint only now; integrate
  approved preparation with preserved commits. Activate docs/workflows/routing
  together and confirm new work targets `dev`. If default branch changes,
  verify dispatchable workflows exist there. Retain prior published assets.
- Run the first-release rehearsal below and select a fresh final candidate;
  perform the first deliberate main advance only through promotion.

## Validation and first-release rehearsal

Planning used static inspection. Approved isolated implementation now runs
local bootstrap, focused tests and the existing publication gate. No hosted
release or deployment has run; staging credentials, DNS and Pages remain
unprovisioned. See `etc/release/README.md` for activation and verification.

Implementation validation reuses the existing install-script checks, source
gate and site tests. Add focused cases to the existing tooling tests for a
non-version candidate tag, two candidates sharing a version, fully isolated
index/download routing, missing/conflicting archive, and a resumable partial
upload. Use local endpoints with distinct same-version bytes so falling back
to production cannot pass. Do not invent compiler-language fixtures for release
transport behavior. Ensure package command failure fails the checker.

First release rehearsal after authorized provisioning:

1. Record the production baseline. Stage two same-version candidates with
   distinct IDs; prove old URLs/digests remain available and production pointers
   stay unchanged. This specifically tests overwrite and routing failures.
2. Exercise local/mocked interrupted publication at upload, release visibility
   and site deployment boundaries; resume matching bytes, reject conflicts,
   and restore a whole previous site artifact. Avoid breaking live production.
3. Perform the final full matrix rebuild as a new candidate, then stage it.
   On all four supported platforms install from live staging in a fresh prefix,
   run a compiler example and pcre2 install/use; exercise installed torch on its
   two supported platforms. Existing bundle jobs retain all package coverage.
   Record unsupported/unavailable platform checks as gaps, never as passes.
4. Verify public HTTPS, homepage/book/assets/search, source links, latest and
   explicit-version installer routes, package URLs/digests and visible candidate
   identity. Verify version/index/site all describe the same selected candidate.
   Inspect the retained production variant for production URLs/base and links.
5. Gary selects this candidate. Promote the same archives, confirm SHA-256
   equality across staging and production, deploy the production variant, and
   repeat live install/package/site checks before reporting success. Confirm
   later `dev` commits were not included and prior release URLs still work.

Cost is explicit: every requested stage rebuild uses the existing 30 matrix
jobs; the final staging rebuild replaces today's redundant tag rebuild.
Publication adds metadata/hash transfer and site assembly, not another native
build. Proposed live verification adds four small install/run jobs per
candidate and four after promotion, with torch on two of those runners; site
checks add no native matrix. The two-candidate and fault rehearsal is one-time.
These are release-only checks, not ordinary commit/precommit/status gates.
Gary must approve their recurring cost before implementation; if budget is
insufficient, decide coverage explicitly rather than silently claiming full
verification. Existing `agent-pr-check`, `doc-check`, `precommit` and
`sanity-check` definitions stay unchanged.

## Decisions still requiring Gary

- The stable checkpoint and explicit clearance for the two ongoing sessions;
  unresolved ancestry/baseline reconciliation, if any, is a separate decision.
- Isolated implementation is approved. Permission/timing to provision the
  proposed public staging repository, DNS and credential remains held. Use the
  repository-scoped GitHub App described above.
- Whether `dev` becomes the GitHub default branch at cutover. Recommend yes
  for contributor/PR routing; `main` remains the release branch. Exact branch
  policies and any required bypass mechanism must be agreed, not invented.
- Confirm first version/candidate and Gary's promotion authority. Existing
  Gary-only merge/tag release guidance remains in force until explicitly revised.
- Plan approval includes the proposed release-only verification cost and
  durable retention contract. A later finite public-candidate retention policy
  changes lockfile promises and needs a separate decision.

## Plan review

The compiler jobs establish archive production and installer checks; bundle
producers establish package metadata and current installed-torch proof. The
existing runtime establishes compiler-version compatibility, not candidate
identity. Consumers reuse those facts rather than adding a second bundle
validator. Hash comparison at upload/download boundaries is necessary because
version strings cannot identify the bytes being promoted. Complete matrix
success is reused, not duplicated with another native build.

Reuse the release matrix, index generator, installer, explicit CLI `--index`,
site URL configuration and Pages actions. Delete tag rebuilds, clobber uploads,
source-tree pointer commits and implicit moving-main site builds. A manifest
is necessary to bind bytes to source; small receipts distinguish verified and
partially published states; one assembly helper and minimal staging deployment
workflow bridge existing owners. No compiler channel state, generic deployment
framework, new service, cache or AST traversal is needed. Any x2c helper changes
use existing Args, Path, JSON and process operations and ordinary errors.

Proposed checks/negative cases are limited to: missing or mismatched asset
inventory/digests (incomplete or untested downloads); conflicting reused
candidate/version identity (overwritten public bytes and broken lockfiles);
stale main/previous deployment (lost history or unintended pointer rollback);
wrong site/index/release routing (false staging success); interrupted publication
(recoverability without replacement builds); and live installation/site checks
(deliberate public release behavior). Reuse checksum and version checks already
owned by installer/runtime. No new language validator or dedicated compiler
diagnostic is proposed. Final authored-diff review precedes the unchanged
publication gate. The outstanding decisions above block activation, not the
usefulness of this local plan.
