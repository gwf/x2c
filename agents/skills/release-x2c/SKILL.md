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
files, versioning, and recovery; read it before starting.

Gary merges pull requests and pushes tags. Do everything else, and at each
point that needs him, give the exact command and what it will do.

## Prepare the version

Confirm the work to ship is on `main`. Branch, set `cli_version` in
`src/cli.x`, update both strings in `unittest/probes/run-cli-boundary.sh`
and the `--version` example atop `site/public/install.sh`, and run
`tools/gate-state.py ensure agent-pr-check`. Open the pull request as the
root instructions describe. Skip this step when the version already names
an unpublished release, such as a re-run after a failed build.

## Dry run the commit

After Gary merges, fetch `main`. When integrating changed `bootstrap/`, run
`make build-safe` before any local check. Dispatch the dry run, record the
SHA it built, and wait for it:

```sh
gh workflow run release.yml --ref main
gh run list --workflow release.yml --limit 1 --json databaseId,headSha
```

Every job must succeed, `publish` included. On a failure, read the failing
job's log, fix the cause through an ordinary pull request, and dry run
again.

## Hand over the tag

Give Gary the tag command pinned to the dry run's SHA, not `main`:

```sh
git tag -a v<version> -m "x2c <version>" <sha>
git push origin v<version>
```

If the tag already exists, check whether its run published anything with
`gh release view v<version>`. Moving it is acceptable only when nothing was
published or nobody outside the project has installed from it; otherwise
prepare the next patch version instead. Say which case applies.

## Verify the release

Watch the tag's run and the `pages` run it dispatches. Then run
`./x2c script tools/check-release.x <version>`, and again with `torch` as
the package on a platform torch supports. Report failures with the step that
failed.

The release is complete when both runs succeeded and the check passes. A
merged pull request or a green build is not completion.
