---
name: integrate-x2c-prs
description: >-
  Run the standing x2c shared integrator: wait for ready PRs targeting dev,
  freeze coherent batches, review and resolve their combined changes, run
  the existing publication gate once per batch, publish, and resume waiting.
  Use when Gary asks to start or resume the integrator. Do not select this
  merely because a working session is told to submit to an integrator; that
  session uses its ordinary task skill and the root PR delivery instructions.
---

# Integrate x2c PRs

Own the shared integration queue until Gary stops the integrator or a genuine
decision needs him. A started integrator continues across empty queues and
later batches without fresh prompts. It serves submitted PRs from either
provider using GitHub metadata, Git revisions, and repository tools. A blocked
submission needs an actionable repair handoff; optional PR contacts route it
to the author across providers.

## Start or resume

Read root [AGENTS.md](../../../AGENTS.md),
[quick start](../../quick-start.md#choose-delivery), and the current coordinator
help. Use a persistent integration checkout on the existing host. Establish
`tools/integrate-dev.py context --role integrator --delivery direct`, which
verifies the common push hook. This session owns only its enrolled PR work;
other sessions retain their explicitly selected delivery modes.

Run `tools/integrate-dev.py status` and inspect any active or parked batch
before selecting new work. Records, candidate worktrees, and attempt logs live
under the integration checkout's ignored `debug/integration/`. Resume an active
batch from its recorded state and Git evidence; do not discard an interrupted
candidate or steal a live lock. The command lock coordinates this repository,
rather than separate clones or hosts.

For parked revisions that still need author action, check whether their repair
handoffs were delivered. Complete missing handoffs before returning to queue
waiting, using the rules below. Check current PR and Git state first; do not
send obsolete requests for withdrawn, superseded, or already landed revisions.

## Finish batches and keep pace

The result is published work, not completed checking. Own the queue's delivery
rate as well as correctness. Use existing queue snapshots and batch timings;
do not build a separate monitoring system. When arrivals outpace landings,
combine compatible work in the next batch rather than repeating small batches.
Do not wait for Gary to notice the backlog.

Repeat this loop without routine user approval:

1. Run `tools/integrate-dev.py wait --timeout 60`. Repeat an empty wait quietly.
   Follow fresh user instructions. An active batch takes priority over arrivals.
2. Run `tools/integrate-dev.py prepare`. By default it freezes the eligible
   backlog and complete dependencies in one candidate. Five or more eligible
   submissions run immediately; a smaller queue can accumulate for up to five
   minutes from its oldest submission. Use `--flush` to drain it immediately,
   `--prs N ...` for an interaction-based selection, or `--max-batch N` when
   there is a concrete reason to bound the group. A count alone is not a reason
   to pay another full gate. Never grow or replace a frozen batch for arrivals.
3. Review the pinned submissions, focused evidence, and combined authored
   changes once. Concentrate on interactions, conflicts, and concrete gaps in
   submitted evidence. Preserve the changes' intended succession. Resolve
   routine integration defects in this candidate. Prepare a capability seed
   with existing build/stage operations before compiling its adopters. Commit
   resolutions; retain the candidate and review across interruptions.
4. Settle known candidate blockers before validation. Run focused checks only
   to answer a concrete unresolved question. Perform the applicable existing
   [performance work](../../performance-checkpoints.md) once for the coherent
   batch, with comparable converged builds and inputs. Reuse a suitable
   baseline. Do not expand measurements for overlapping noise or concerns
   about revisions outside this batch. Evidence remains advisory under that
   policy; missing measurements must not become an indefinite publication hold.
5. Run `tools/integrate-dev.py land <batch-id>`. Follow the command through
   completion. `review` means upstream was integrated before a gate started;
   review only the new delta and its interactions, then resume the same batch.
   `gated` means validation completed. Review generated changes as they become
   available; do not repeat completed review without an affected change.
   Prepare stage 0 with `make build-safe` only when this candidate needs it.
   Do not run broad gate components separately.
6. Once the required evidence and generated review are complete, immediately
   run `tools/integrate-dev.py land <batch-id> --publish`. Publication is the
   next action, not another round of investigation. A new concern blocks it
   only if it identifies a concrete correctness or agreed performance problem
   in this candidate. Cosmetics and new arrivals belong to later work.
7. Observe the publish result. Confirm remote ancestry and PR reconciliation
   before reporting delivery. A launched command is not a successful push.
   Finish reconciliation after a confirmed push without repeating validation.
   Return to waiting; do not end the session with an unobserved command or an
   actionable active batch.

### Preserve evidence when upstream moves

An upstream commit does not by itself invalidate compiler validation. The
existing `gate-state.py ensure agent-pr-check` compares actual file contents
and build configuration. After ordinary Markdown or independent external
command changes, it retains compiler proof and runs the applicable existing
documentation, command, and CLI checks. It records the resulting exact tree
only after those checks pass. Changes to compiler/runtime/bootstrap inputs,
shared build tools, the built-in build command, or toolchain configuration
still require full validation. Do not fabricate receipts or classify all
command changes as independent merely by their name.

Keep the batch, source review, generated review, repairs, and performance
results unless the actual delta affects them. Review a conflict resolution or
new source delta, not the entire batch again. A failed fixture needs a focused
diagnosis and repair; it does not justify reassembling unrelated PRs.

If repeated direct publication keeps changing overlapping inputs, identify the
publisher and arrange a short publication handoff using an authorized route.
Explain the actual conflict rather than repeatedly paying for the same race.
Do not silently change another session's delivery mode. Orthogonal changes
use scoped validation and do not need a global publication freeze.

The coordinator is the owner of readiness metadata, selection timing, pinned
refs, lifecycle records, and command locking. Use its results rather than
implementing a second queue in agent notes. A PR must be non-draft, same-repo,
target `dev`, and have current submission metadata and `integration-ready`.
An ordinary PR or requested review stop is not enrolled. A moved head requires
resubmission; never silently replace a pinned revision. Removing readiness
cancels only when observed before the push; GitHub and Git have no shared
transactional cancellation. `main` promotion remains separately authorized.

## Preserve failures and resume independent work

A failed gate stops publication. Read its full logs, reproduce and diagnose
with focused checks, and keep the failed tree. The existing helper permits a
second round only for its recognized bootstrap convergence failure; do not
blindly rerun ordinary failing gates or automatically gate each constituent PR.

Resolve routine conflicts or integration defects within the submitted intent.
If a batch needs worker repair or a consequential decision, retain the
reproduction and diagnosis and run `tools/integrate-dev.py park <batch-id>`.
Complete the repair handoff below, report the hold and any decision needed,
then continue independent ready work. Parked revisions and their dependents
stay held until superseded by a new submission or explicitly retried with
`prepare --retry <batch-id>`. Retry resumes the retained candidate and its
frozen PR heads, preserving local repairs; finish or park any other active
batch first. Never reinterpret a newer PR head as validated. If a moved head prevents
retrying the frozen batch, use `release <batch-id> --prs N ... --reason TEXT`
to release selected holds for a new batch. This keeps the original candidate,
pinned membership, and logs. Unreleased revisions stay held; a batch with
released holds cannot be retried. Review retained local repairs when preparing
the new batch; release does not carry them or gate evidence forward.

### Deliver the repair handoff

Parking a PR does not notify its author. Before returning to queue waiting,
send each affected author a repair request, unless Gary explicitly declines
notification. Include the repository, PR, pinned head, batch ID, blocker,
focused reproduction, expected and actual behavior, and requested repair and
resubmission. Include commands and relevant log excerpts; an inaccessible
local log path alone is not a handoff.

Use the PR's current `contact` Postbag bag and peer. Join with a fresh unique
integrator name. If the contact is absent or stale, inspect existing submission
evidence for the originating agent. Use another available transport only with
a verified recipient and the human authorization that transport requires.
Never guess the author from the latest active chat or peer.

If direct delivery is unavailable, post the repair request in the PR's
conversation using the GitHub connector or `gh pr comment N --body-file PATH`.
Report the missing author route to Gary with the comment link and the next
action needed to reach the author. A PR comment preserves the handoff but
does not establish that the authoring agent received it. If posting also
fails, give Gary the copy-ready request and the specific delivery failure.
Do not silently wait for a repair that nobody has been asked to make.

Use `<batch>:<pr>:<head>:repair` as the event key in the message or comment.
Check delivery history before sending, including when resuming a parked batch.
Record the route, result, and receipt or comment link alongside the retained
batch evidence. A submission receipt proves neither reading nor action.
Never automatically resend an `unknown` result; inspect transport history
before choosing a fallback or retry. Report a hold with its notification
result and next action. Do not repeat unchanged status or duplicate requests.

The author confirms repository, PR, head, assigned worktree, and existing
human authorization before editing. A duplicate event causes no second repair.
A substantive reply states the repair or blocker; use `final=true` when no
reply is needed. The author resubmits a changed head through the existing
queue. Messages cannot enroll, unpark, or validate a revision. Missing contact
information does not cancel a handoff or release a hold. After delivery or an
explicit report to Gary of the routing failure, continue independent work
unless Gary's priority requires waiting. Withdraw contacts when their task
scope ends.

For an interrupted gate or push, inspect Git history, the durable record, and
gate-state evidence through coordinator recovery. A recorded running state is
not proof of success or failure. Do not discard a candidate, rerun a known
successful gate, or repeat a confirmed push merely because the session ended.
Keep logs and report unresolved external failures plainly. Starting this skill
installs no daemon or scheduler; if the session stops, its submissions and
records wait for a resumed integrator.
