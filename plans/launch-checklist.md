# Public launch checklist

> Status: Pending launch polish, recorded 2026-11-17. Gary reports that the
> release is already published to `main` and the production site, but has not
> been publicly announced. Release preparation, verification, and publication
> are complete. This checklist is not a new release campaign.

## Checklist

- [x] Review the landing-page gallery puns for sense and quality. The approved
  titles and Install edits landed on `dev` in PR #731.
- [x] Audit ordinary developer commands for unwanted side effects. The hook
  repair landed on `dev`; `make install` and other ordinary developer commands
  no longer change `core.hooksPath`.
- [ ] Edit the entire book for clear, direct language. Remove explanatory
  indirection, put cause before effect, prefer normal positive statements
  over unnecessary negative framing, and attribute actions to their actual
  actors rather than non-agentic things.
- [x] Consolidate the book's low-level Compiler API entries into an index.
  The book build change landed on `dev`.
- [x] Keep only the consolidated Compiler API index on the website. The
  staged website publishes the index and omits the former individual API
  pages. Production publication remains part of the website update below.
- [x] Publish the collaboration wording and issue templates. The policy
  welcoming bug reports, ideas, and pull requests landed on `dev` in
  [PR #728](https://github.com/gwf/x2c/pull/728). GitHub
  Issues and forks are enabled; Discussions remain disabled.
- [x] Audit obsolete files, assets, and directories throughout the repository.
  The unused on-demand Docker compilation service was removed. The stale
  `PLAYGROUND_URL` test override was already removed. The remaining Playground
  tests cover the live site. Shootout PNG charts have no repository references,
  but the chart script regenerates them with the SVGs, so they remain.
- [x] Review the installation instructions. Gary approved the revised Install
  section on localhost; its changes landed on `dev` in PR #731. Staging
  publication is a separate step.
- [x] Land the latest one-page cheatsheet redesign. The revised landscape sheet
  landed on `dev` in [PR #727](https://github.com/gwf/x2c/pull/727).
- [ ] Publish the current `dev` website to staging for final site review.
- [ ] After the remaining website changes are complete, review and approve a
  separate production website update.
- [ ] Prepare the public announcement after the desired patches.

## Scope and plan review

This record preserves Gary's pending checklist; it does not authorize
implementation of its items. Historical deferrals are not launch tasks.
The release-state statement comes from Gary; the staging evidence above
comes from the completed workflow and live checks. Completed items are marked only after their follow-up work was verified.

The checklist reuses existing repository plans and publication workflows.
It adds no source machinery, helpers, representations, traversals, caches,
validators, diagnostics, fixtures, recurring gates, or deadlines. No x2c
source changes are proposed here, so idiomatic source design is not at issue.
