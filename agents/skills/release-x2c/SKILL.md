---
name: release-x2c
description: >-
  Prepare, dry-run, and verify an x2c release, or recover from a failed or
  broken one. Use when Gary asks to cut, publish, tag, or check a release,
  to bump the compiler version for a release, or when a release workflow
  run or published release has failed. Do not use to change what the
  release workflow builds; use plan-x2c-change or execute-x2c-plan. Do not
  use to add a package bundle; use integrate-x2c-package.
---

# Release x2c

Take one version from `main` to a verified public release.
[agents/releasing.md](../../releasing.md) explains the workflow stages, site
files, versioning, and recovery, and holds the commands for each step of
[Cut a release](../../releasing.md#cut-a-release). Read it before starting.

Gary merges pull requests and pushes tags. Do everything else, and at each
point that needs him, give the exact command and what it will do.

## Prepare the version

Confirm the work to ship is on `main`, then make the version change in its
own pull request (step 2). Skip this step when the version already names an
unpublished release, such as a re-run after a failed build. Gary merges it.

## Dry run the commit

After Gary merges, fetch `main`. When integrating changed `bootstrap/`, run
`make build-safe` before any local check. Dispatch the dry run (step 3),
record the SHA it built, and wait for it. On a failure, read the failing
job's log, fix the cause through an ordinary pull request, and dry run
again.

## Hand over the tag

Give Gary the tag commands from step 4, pinned to the dry run's SHA. If the
tag already exists, check whether its run published anything with
`gh release view v<version>`, apply
[Versions and tags](../../releasing.md#versions-and-tags), and say which case
applies: move the tag, or prepare the next patch version.

## Verify the release

Watch the tag's run and the `pages` run it dispatches, then run both checks
from step 5, the torch one on a platform torch supports. Report failures with
the step that failed.

The release is complete when both runs succeeded and the checks pass. A
merged pull request or a green build is not completion.
