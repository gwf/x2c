# Releasing x2c

A release publishes one compiler version: tarballs for each platform, package
bundles, a package index, and a site that points users at them. This page
explains how those pieces fit and the order to produce them. The
[release-x2c skill](skills/release-x2c/SKILL.md) is the task workflow; the
[installation guide](../docs/src/guide/installation.md) is what users read.

Gary publishes. Merging a pull request and pushing a tag are his. An agent
prepares the version change, dispatches dry runs, verifies what was
published, and hands him exact commands at each step.

## The pieces

- **Version.** `cli_version` in `src/cli.x` is what `x2c --version` prints.
  `unittest/probes/run-cli-boundary.sh` asserts the same string.
- **Tag.** Pushing a tag named `v<version>` starts
  `.github/workflows/release.yml` at the tagged commit. A manual run of the
  same workflow is a dry run: it builds everything and publishes nothing.
- **Workflow stages.**
  - `compiler` builds `x2c-<version>-<platform>.tar.gz` and its `.sha256` on
    `macos-15`, `macos-15-intel`, `ubuntu-24.04`, and `ubuntu-24.04-arm`. It
    fails when the compiler's version differs from the tag, and proves each
    tarball with `tools/check-install-script.sh`.
  - `bundles` runs `make -C packages/<name> bundle` for pcre2, yyjson,
    libcurl, termbox2, libuv, and blis on all four, and for torch on
    `macos-15` and `ubuntu-24.04`, the platforms PyTorch ships prebuilt CPU
    libtorch for. torch is also run against an installed copy with
    `packages/tools/check-bundle.sh`. raylib is not released.
  - `publish` runs only when every job above succeeded. It writes the
    package index with `tools/gen-package-index.py`, creates the GitHub
    Release if absent, uploads every asset with `--clobber`, commits
    `site/public/x2c-version.txt` and `site/public/packages/index.txt` to
    `main`, and dispatches `pages.yml`. On a dry run it stops after
    assembling the release.
- **Site files.** `x2c-version.txt` is what `site/public/install.sh` treats as
  the latest version; `install.sh --version <n>` bypasses it.
  `packages/index.txt` is what `x2c install <name>` resolves. Both describe
  only the newest release; the assets of every tag stay downloadable by URL.

Runner images are pinned rather than `-latest`, because a published
executable carries the deployment target and C library of the machine that
built it.

## Cut a release

1. **Land the work** on `main` through ordinary pull requests.
2. **Change the version** in its own pull request: `cli_version` in
   `src/cli.x`, both strings in `unittest/probes/run-cli-boundary.sh`, and
   the `--version` example in the comment at the top of
   `site/public/install.sh`. `tools/gate-state.py ensure agent-pr-check`
   regenerates the bootstrap copy of the string. Gary merges it.
3. **Dry run** the commit to be released and note its SHA:

   ```sh
   gh workflow run release.yml --ref main
   gh run list --workflow release.yml --limit 1 --json databaseId,headSha
   ```

   Every job must succeed, `publish` included. A green build with a failed
   `publish` is a failed dry run.
4. **Tag that exact commit** and push the tag. Gary runs this:

   ```sh
   git tag -a v<version> -m "x2c <version>" <sha>
   git push origin v<version>
   ```

   Tag the SHA the dry run built, not `main`. If `main` moved since, the tag
   publishes commits no dry run tested.
5. **Verify** once the tag run and the pages deploy finish:

   ```sh
   tools/check-release.sh <version>
   tools/check-release.sh <version> torch
   ```

   It checks that the site names the version, that the site's installer
   installs that compiler into a scratch prefix, and that the site's index
   installs a bundle for this platform. Run it on each platform available.

Users upgrade by re-running `install.sh`, which replaces the compiler and
keeps installed packages.

## Versions and tags

While x2c is `0.x`, bump the last number for fixes and the middle number when
behavior users depend on changes.

Never move a tag once anyone may have installed from it. Moving a tag
rebuilds and replaces its assets under the same version, with different
checksums. Earlier installs then hold different binaries than new ones, and
an `x2c.lock` written against the old assets fails verification. Correct a
published release with the next patch version. Moving a tag is acceptable
only while its run has published nothing, or before anyone outside the
project has installed from it.

## Bundles follow the compiler

A bundle records the exact compiler version that built it, and
`x2c install` refuses a bundle from another version unless `--force`. The
site index always names the newest release's bundles, so a user on an older
compiler must upgrade before installing packages by name. A project lockfile
names specific asset URLs and keeps working for the release it was written
against.

## When something fails

- **A build job fails.** Nothing was published. Fix it on `main` and tag the
  fixed commit. Moving a tag whose run published nothing is fine.
- **`publish` fails partway.** Re-run the workflow for the same tag from the
  Actions page. Uploads replace existing assets and the site commit is
  skipped when nothing changed, so a re-run is safe.
- **A published release is broken.** Publish the next patch version. To
  withdraw a release entirely, delete the GitHub Release and its tag; the
  site keeps naming it until the next release rewrites the site files.
- **The first push to `main` is rejected.** The workflow token needs write
  access to contents and actions. The repository default is read-only; the
  job requests its own scopes, as `pages.yml` does.

Two release steps can run only on a real tag: uploading assets and updating
the site. A dry run cannot exercise them, so verification after publishing
is required, not optional.
