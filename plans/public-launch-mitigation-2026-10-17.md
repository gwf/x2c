> Status: active - launch-readiness review of `dev` `8529c449a` on 2026-10-17,
> one commit past v0.15.0 (`main` `314994819`). Four mitigation sessions were
> started the same day; one found its item already fixed; this file records findings, owners, and outcomes.
> Repository settings and the SECURITY.md wording are Gary's decisions.

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
| A9 repeated `$auto` | `Block b = $auto(a)` on an `$auto`-managed `a` segfaults (139); the review record shows a double release under ASan. | Reject a nested or duplicate `$auto` at compile time; state the rule in the book. | Session "Reject nested or repeated $auto instead of segfaulting" |
| Uncaught error report | A logger `error/err-report` line with structured detail and, for runtime raises, `../../lib/...` paths prints before `x2c error floor: ...`. | One user-facing line by default; keep the structured event for configured loggers. | Session "One-line uncaught error report for users" |
| Private paths in public files | `packages/torch/README.md` and the torch benchmark reports print `/Users/gary/Git/Bonsai-demo/...`; `plans/archive/memory-retention.md`, linked from the torch chapter, cites `/Users/gary/Documents/...`. | Neutralize or drop the links. | Session "Public-surface hygiene for the 0.15.0 launch" |
| Release notes | The v0.15.0 release body is the generated `Source ...; candidate ...` line; no human summary exists. | Add `docs/src/reference/release-notes.md` and a paste-ready copy for the release page. | Same hygiene session |
| Stale checked-in site values | `site/public/x2c-version.txt` and `site/public/packages/index.txt` say 0.14.0; candidate assembly rewrites them, so production is correct. | Update the checked-in copies and document the rewrite. | Same hygiene session |
| Templates | No `.github/ISSUE_TEMPLATE` or PR template although CONTRIBUTING.md declines code contributions. | Add a bug-report template and a PR template stating the policy. | Same hygiene session |
| A8 self-meta copy | Not a defect: repository review decision 7 (2026-10-12) records that a function rule rewrites the program's definitions while the copy the compiler runs is compiled as written; `docs/src/guide/meta-functions.md` states it. | None. | Settled |

## Decisions for Gary

- SECURITY.md says x2c "does not yet have a supported stable release". Keep
  or replace now that 0.15.0 is the launch release.
- Repository settings: topics, GitHub Discussions, secret scanning and push
  protection. Agents do not change these.
- Paste the prepared 0.15.0 notes into the GitHub release body.

## Validation and delivery

Each code session delivers directly to `dev` after
`tools/gate-state.py ensure agent-pr-check`; the hygiene session uses
`doc-check` unless it touches build inputs. Update the table's outcome when
each lands, then archive this plan.
