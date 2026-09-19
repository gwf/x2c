# Releasing x2c

Everyday work integrates on `dev`. A release selects one exact source commit,
fully builds and verifies it at `https://staging.x2c-lang.dev`, then promotes
those same compiler and package archives to production. `main` advances only
for a deliberate release, preserving individual commits, preferably by
fast-forward. Development may continue after candidate selection.

Gary authorizes production promotion, advances `main`, and creates release
tags. Plan or implementation approval does not authorize those actions.
Agents prepare candidates and carry out explicitly authorized staging or
verification. The [release skill](skills/release-x2c/SKILL.md) owns task
execution; [deployment operations](../etc/release/README.md) owns provisioning,
recovery commands and the first-release rehearsal. Ordinary validation gates
and their costs are unchanged.

## The pieces

- `cli_version` in `src/cli.x` identifies the compiler version. The CLI
  boundary probe and installer example carry corresponding version strings.
- `candidate.yml` manually builds the selected full source SHA. It retains
  the existing four compiler platforms and 26 native package bundles, then
  assembles immutable archives, destination indexes and both complete sites.
  It publishes nothing. Tags do not trigger a rebuild.
- Candidate identity is `candidate-<full-sha>-<run-id>-<attempt>`, separate
  from compiler version. A rebuild creates a new identity and requires fresh
  verification, even when its version is unchanged.
- `stage.yml` uploads the candidate to `gwf/x2c-staging`, deploys its complete
  site, verifies live installation on four platforms, and retains proof.
  Staging uses its own installer defaults, candidate URLs and explicit index.
- `promote.yml` checks the selected candidate's proof and Gary's main/tag
  state, uploads exactly the retained archives, publishes the release, deploys
  the retained production site and verifies it. It builds nothing.
- `verify.yml` supplies the release-only install/package checks;
  `restore-pages.yml` restores a previously verified production site.

The compiler matrix uses `macos-15`, `macos-15-intel`, `ubuntu-24.04`, and
`ubuntu-24.04-arm`. Native packages are pcre2, yyjson, libcurl, termbox2, libuv,
and blis on all four, plus torch on macos-15 and ubuntu-24.04. raylib is not
released. Pinned runners preserve known deployment targets and C libraries.

`candidate.json` binds archives to source SHA, workflow revision, run,
version, sizes and hashes. Site and verification receipts bind destination
output to that manifest. Named staging/production indexes preserve their
separate URLs; the site publishes its selected index as `packages/index.txt`.
Version, index, installer and site deploy together. They are no longer release
pointer commits on `main`.

## Cut a release

1. Land intended work and version preparation on `dev`, including generated
   bootstrap updates and the existing source gate. Update `src/cli.x`, the
   version expectations in `unittest/probes/run-cli-boundary.sh`, and the
   installer comment example when changing the version. Select a full source
   SHA containing that work and the published history.
2. Dispatch the full candidate build at that exact SHA:

   ```sh
   gh workflow run candidate.yml --repo gwf/x2c --ref dev \
     -f source_sha="$source_sha"
   ```

   Record the specific successful run ID and candidate identity from its
   manifest. Do not infer identity from whichever run happens to finish last.
3. Stage the selected build using the current staging output commit:

   ```sh
   gh workflow run stage.yml --repo gwf/x2c --ref dev \
     -f build_run="$build_run" -f identity="$candidate" \
     -f expected_output="$staging_output_sha"
   ```

   This step needs the provisioned staging repository, Pages domain and
   scoped publication credential described in deployment operations. A failed
   stage or verification is not a promotable candidate. The final full build
   must precede final staging verification; never rebuild after testing and
   substitute the new bytes.
4. Give Gary the exact candidate, version, source SHA, proof and current main
   SHA. He checks ancestry and deliberately advances main and creates the
   annotated tag. With those values confirmed, his commands are:

   ```sh
   git fetch origin
   git merge-base --is-ancestor origin/main "$source_sha"
   git push origin "$source_sha:refs/heads/main"
   git tag -a "v$version" -m "x2c $version" "$source_sha"
   git push origin "refs/tags/v$version:refs/tags/v$version"
   ```

   Stop on a rejected push, ancestry conflict or existing conflicting tag.
   Never force main or move a public tag. This action does not publish assets
   by itself and can temporarily put main ahead of the production site.
5. With Gary's explicit promotion authorization, dispatch the selected
   candidate against the observed current production version:

   ```sh
   gh workflow run promote.yml --repo gwf/x2c --ref main \
     -f identity="$candidate" -f expected_version="$current_version"
   ```

   Follow that exact run through upload, Pages, live checks and retained
   proof. Report completion only after production verification succeeds.

The retained legacy `pages.yml` source is only a baseline recovery tool during
the first-release transition; its workflow registration stays disabled. It is not part of normal candidate promotion;
never dispatch it as an alternative to deploying the selected site archive.
The first release must establish its production baseline and recovery path
under deployment operations before Gary advances main.

## Versions and packages

While x2c is `0.x`, bump the last number for fixes and the middle number when
behavior users depend on changes. Correct defective published bytes with a
new patch release. Preserve public tags, candidate assets and production
archives for lockfiles; never overwrite them or delete them as rollback.

A bundle records its compiler version, not candidate identity. Install matched
candidate packages with an explicit staging index in a fresh prefix, without
`--force`. Bare `x2c install <name>` defaults to production even when the
compiler came from staging. A production user on an older version must upgrade
before installing packages from the current index; lockfiles retain exact URLs.

## Recovery

Publication spans branches, tags, Releases and Pages and is not atomic.
Upload and verify all assets before exposing release/site pointers. Repeating
an interrupted upload accepts existing identical bytes and adds missing files;
a digest conflict stops it. Rebuilding cannot repair a partial publication:
resume from the retained candidate, or prepare a new candidate.

If assets are complete but Pages failed, retry the retained site deployment.
If production verification fails, restore the previous complete verified site
and latest-release designation using `restore-pages.yml`. Keep tags/assets
available and report any discrepancy between main and the restored site.
Legacy releases without retained candidate proof need the explicit baseline
recovery procedure, not a fabricated receipt. A rollback cannot uninstall
already downloaded bytes; prepare a patch release for broken public archives.

Production fixes normally land on `dev` and select a new candidate. An urgent
fix based on published main must merge back into dev before the next normal
selection. Do not reset dev or discard newer integration commits.
