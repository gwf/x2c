# Public launch checklist

> Status: Pending launch polish, recorded 2026-11-17. Gary reports that the
> release is already published to `main` and the production site, but has not
> been publicly announced. Release preparation, verification, and publication
> are complete. This checklist is not a new release campaign.

## Remaining work

- [ ] Review the landing-page gallery puns for sense and quality.
- [ ] Audit ordinary developer commands for unwanted side effects. Check
  whether Makefile targets such as `make install` alter agent hooks or
  unrelated configuration. This is a concern to investigate, not a confirmed
  defect. Remove inappropriate effects only in separately authorized work.
- [ ] Edit the entire book for clear, direct language. Remove explanatory
  indirection, put cause before effect, prefer normal positive statements
  over unnecessary negative framing, and attribute actions to their actual
  actors rather than non-agentic things.
- [ ] Revise book builds and API-reference coverage. Exclude low-value,
  low-level API descriptions from the book. Gary described roughly 350 pages
  of two-sentence API entries with little explanatory value. Decide separately
  whether the website should retain only their table of contents.
- [ ] Revise collaboration wording and GitHub issue settings. Welcome bug
  reports and explain one-person capacity without promising a response or
  fix; some reports may never be addressed. Decide separately whether to
  invite ideas or feature requests. Align issue settings and templates with
  those decisions.
- [ ] Audit obsolete files, assets, and directories throughout the repository.
  Establish purpose, history, references, and current use before recommending
  removal. `etc/playground` is a candidate old on-demand Docker compilation
  service. Distinguish it from the current precompiled WebAssembly assets and
  runners that serve runnable examples. This checklist authorizes no deletion.
- [ ] Review the [staged installation instructions](https://staging.x2c-lang.dev/#install)
  and promote the website when approved. The installation simplification and
  WebAssembly prerequisite repair in [PR #717](https://github.com/gwf/x2c/pull/717)
  merged into `dev` at `fee9387e0d697b1b0808a540de2643478a938287`.
  [Website-only staging run 43997682945](https://github.com/gwf/x2c/actions/runs/43997682945)
  succeeded. Desktop/mobile presentation, links, copied commands, and 28
  browser programs were verified. The staged compiler and packages were
  preserved. Production promotion was neither authorized nor performed in
  this work; review and approval remain pending.
- [ ] Fix cheatsheet formatting and enforce a one-page limit.
- [ ] Prepare the public announcement after the desired patches.

## Scope and plan review

This record preserves Gary's pending checklist; it does not authorize
implementation of its items. Historical deferrals are not launch tasks.
The release-state statement comes from Gary; the staging evidence above
comes from the completed workflow and live checks. No pending item is
marked complete on the strength of those narrower checks.

The checklist reuses existing repository plans and publication workflows.
It adds no source machinery, helpers, representations, traversals, caches,
validators, diagnostics, fixtures, recurring gates, or deadlines. No x2c
source changes are proposed here, so idiomatic source design is not at issue.
