> Status: done - launch-readiness review of `dev` `8529c449a` on 2026-10-17,
> one commit past v0.15.0 (`main` `314994819`). All items closed on `dev` by
> `f38fbfbfc` the same day: A9 at `90de35133`, the one-line uncaught report
> at `f38fbfbfc`, hygiene at `af9accb0d`, SECURITY.md at `43a9e9398`.
> Gary set topics and enabled secret scanning; discussions and push
> protection stay off. The 0.15.0 release body still awaits the prepared notes.

# Public launch mitigation

## What the review established

v0.15.0 was promoted on 2026-10-17 through `candidate.yml`, `stage.yml`, and
`promote.yml`. From a fresh prefix on macOS arm64 the live `install.sh`,
`x2c run`, `x2c package install pcre2`, and `x2c new` work. On current `dev`
`make build-safe`, `make verify` (955 suites), `make examples` (60),
`make site-check`, and `make doc-build` pass. The repository is public with
issues enabled, no topics, no discussions, no issue or PR templates, and
secret scanning off.

## Findings and owners

| Item | Observed on the shipped 0.15.0 binary | Mitigation | Owner |
| --- | --- | --- | --- |
| A1 return inside `defer` | Refuted on 2026-10-17: the review probe used `catch %(bad-arg):`, which matches only a bare payload; with `%(bad-arg *)` the raise is caught. A1 itself was fixed on 2026-10-12 by `f92e94c94`, pinned by fixture `finalizer-return-frame`. | None needed. | Closed by the A1 session without a change |
| A9 repeated `$auto` | `Block b = $auto(a)` on an `$auto`-managed `a` segfaults (139); the review record shows a double release under ASan. | `$auto` on an already managed local is a compile-time error naming the local (`5dc58b273`, fixture `managed-twice`); the nested form was already rejected. | Done, `90de35133` |
| Uncaught error report | A logger `error/err-report` line with structured detail and, for runtime raises, `../../lib/...` paths prints before `x2c error floor: ...`. | One line: `x2c: uncaught <code> in fn (file:line): key value, ...`; runtime-internal locations omitted; `X2C_DEBUG`, a custom Logger, or an added sink keeps the structured event (`6fda2c3b7`). | Done, `f38fbfbfc` |
| Private paths in public files | `packages/torch/README.md` and the torch benchmark reports print `/Users/gary/Git/Bonsai-demo/...`; `plans/archive/memory-retention.md`, linked from the torch chapter, cites `/Users/gary/Documents/...`. | Paths neutralized; archive links dropped from the book (`49a96ff0e`). | Done, `af9accb0d` |
| Release notes | The v0.15.0 release body is the generated `Source ...; candidate ...` line; no human summary exists. | `docs/src/reference/release-notes.md` added; paste-ready copy in the hygiene worktree's `.context/release-notes-0.15.0.md`. | Done; release body pending Gary |
| Stale checked-in site values | `site/public/x2c-version.txt` and `site/public/packages/index.txt` say 0.14.0; candidate assembly rewrites them, so production is correct. | Checked-in copies at 0.15.0; `site/README.md` notes the rewrite. | Done, `af9accb0d` |
| Templates | No `.github/ISSUE_TEMPLATE` or PR template although CONTRIBUTING.md declines code contributions. | `.github/ISSUE_TEMPLATE/` and `PULL_REQUEST_TEMPLATE.md` added. | Done, `af9accb0d` |
| A8 self-meta copy | Not a defect: repository review decision 7 (2026-10-12) records that a function rule rewrites the program's definitions while the copy the compiler runs is compiled as written; `docs/src/guide/meta-functions.md` states it. | None. | Settled |

## Decisions for Gary

- SECURITY.md: replaced on 2026-10-17 (`43a9e9398`) with the early-release
  policy; only the latest release receives security fixes.
- Repository settings, 2026-10-17: eight topics set, secret scanning
  enabled with no alerts; Discussions and push protection left off.
- Pasting the prepared 0.15.0 notes into the GitHub release body remains.

## Validation and delivery

Each code session delivered directly to `dev` after
`tools/gate-state.py ensure agent-pr-check`. Reverified on `dev` `f38fbfbfc`
from a fresh `make build-safe`: the repeated `$auto` probe is rejected with
`managed initializer cannot manage an already managed local`, the uncaught
probes print one line, and the defer-return probe exits 0.
