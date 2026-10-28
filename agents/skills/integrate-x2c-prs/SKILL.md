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

Manage the whole eligible queue, including unaffected revisions held by parked
batches. Use coordinator snapshots and batch records, not a second queue in
agent notes. A failing submission must not hold unrelated delivery.

### Select the queue before validation

Before starting a broad gate, inspect `status` for the entire ready queue,
active candidate, parked holds, dependencies, and readiness times. In the
existing batch evidence, record the snapshot time, selected PR numbers and
pinned heads, and a concrete exclusion reason for each omitted eligible PR.
State that selection briefly before gating. Use existing PR evidence, source
interactions, and focused checks to establish compatibility. The coordinator
records the prepare snapshot and refreshes selection before a gate. It refuses
unexplained omissions, including parked holds. For a necessary exclusion, pass
`--exclude-file PATH` to `prepare` or `land`. The JSON list pins each reason:

```json
[{"number": 604, "head": "FULL_40_CHARACTER_SHA", "reason": "Reproduced helper staging failure; command and log reference"}]
```

Use the actual head, blocker, and evidence. The coordinator checks completeness
and pinned identity; the integrator must justify semantic incompatibility.
A selection refusal starts no build. Regroup compatible work rather than invent
an exclusion to bypass the refusal.

Combine all compatible eligible submissions. **Do not start a singleton gate
while another compatible submission is ready.** Apply the same rule to narrow
multi-PR selections. `--prs`, `--max-batch`, `--flush`, age, and a frozen
candidate are not exemptions. Valid exclusions identify a pinned dependency
that is unavailable, a reproduced blocker, an unresolved semantic conflict,
a withdrawal or moved head, or Gary's explicit delivery boundary. Shared files
or an inconvenient merge alone do not establish incompatibility. Record the
actual conflict and why it cannot be resolved within the submitted intent.

If compatible submissions arrive before the gate starts, regroup through
`park`, `release`, and a new `prepare` using all compatible work. Preserve and
review local repairs because release does not transfer them. Do not edit the
old record's pinned membership. Once validation starts, finish that attempt
without chasing arrivals; batch those arrivals next. A successful gate proceeds
to publication. Recheck selection before another broad attempt after failure,
not before a publish or recovery that reuses successful proof.

Repeat this loop without routine user approval:

1. Run `tools/integrate-dev.py wait --timeout 60`. Repeat an empty wait quietly.
   Follow fresh user instructions. Resume recorded work, subject to the
   queue selection and failure rules in this skill.
2. Run `tools/integrate-dev.py prepare`. By default it freezes the eligible
   backlog and complete dependencies in one candidate. Five or more eligible
   submissions run immediately; a smaller queue can accumulate for up to five
   minutes from its oldest submission. Use `--flush` to drain it immediately,
   `--prs N ...` for an interaction-based selection, or `--max-batch N` when
   there is a concrete reason to bound the group. A count alone is not a reason
   to pay another full gate. Apply the queue selection rule above before
   starting validation; never silently change pinned membership.
3. Review the pinned submissions, focused evidence, and combined authored
   changes once. Concentrate on interactions, conflicts, and concrete gaps in
   submitted evidence. Preserve the changes' intended succession. Resolve
   routine integration defects in this candidate. Prepare a capability seed
   with existing build/stage operations before compiling its adopters. Commit
   resolutions; retain the candidate and review across interruptions.
4. Settle known candidate blockers before validation. Run focused checks only
   to answer a concrete unresolved question. Perform the applicable existing
   [performance work](../../performance-checkpoints.md) once for the coherent
   batch. Select the checkpoint during review and reuse a converged baseline.
   If candidate convergence depends on the gate, measure after `land` finishes;
   do not add a separate bootstrap run merely to measure earlier. Compare the
   same inputs and build states. Do not expand measurements for noise or concerns
   about revisions outside this batch. Evidence remains advisory under that
   policy; missing measurements must not become an indefinite publication hold.
5. State the selected members and exclusions using the queue selection rule.
   Run `tools/integrate-dev.py land <batch-id>`. Follow the command through
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

A failed gate stops publication of that candidate. Read the full logs and
identify every known blocker. Before another broad attempt, record the changed
input or repaired cause and the focused result that clears each known blocker.
A new failure can require another repair; elapsed time or a coordinator error
alone cannot justify validation. Keep the helper's recognized bootstrap
convergence retry; do not run its broad components separately.

Resolve routine defects within the submitted intent. If author repair or a
consequential decision is needed, park the candidate and deliver the repair
handoff below. Identify the blocked revisions and their transitive dependents
from pinned dependencies and reproduced interactions. Release **all unaffected
revisions together**, then combine them with the rest of the compatible ready
queue in one new candidate. Do not release and gate them one at a time. A
parked hold alone is not a blocker for an unaffected revision. Do not wait for
the blocked author before delivering independent work.

Use `release <batch-id> --prs N ... --reason TEXT` with the whole unaffected
set and a reason that names the retained blockers. Use `--exclude-file PATH`
to name every retained revision and its blocker or blocked dependency. The
coordinator refuses unexplained retained peers and releases that depend on a
retained revision. Recorded retained reasons also explain those holds during
later queue selection. Preserve the original candidate and logs. Review retained repairs when assembling the new candidate;
release carries neither repairs nor validation proof. Keep blocked revisions
and dependents held until superseded or explicitly retried. `prepare --retry
<batch-id>` preserves the frozen heads and local repairs, requires no other
active batch, and cannot resume a batch whose holds were released. A changed
head requires a new submission and candidate, never reinterpretation of old
proof. Record where each held revision and useful local repair will continue.

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

## Recover validation and retire candidates

After an interrupted command or coordinator/Git failure, inspect the attempt
log, candidate HEAD and working tree, `debug/land-dev-review.json`, gate-state
proof, and remote ancestry before choosing another action. Distinguish a
failed check from successful checks followed by a failed generated commit,
record update, or push. Never manufacture a review receipt or treat exit
status alone as proof that validation failed.

Run `land <batch-id>` to recover `gating`, `needs-attention`, or `publishing`
when successful gate proof remains valid. The coordinator checks pinned
ancestry and proof. If the matching review receipt is missing, it uses
`land-dev --recover-reviewed` to commit only generated changes, check proof
again, and write the receipt. This path cannot build, run `ensure`, or push.
Review recovered generated changes before `land --publish`. An ordinary check
failure has no valid proof and is not recovered as successful.

If recovery fails, preserve the candidate and inspect the recovery log. Resolve
the specific Git or filesystem failure before retrying. Do not manufacture a
receipt or change state manually. Actual input changes require the applicable
existing checks; unchanged contents can retain proof across a commit. Confirm
remote ancestry and reconcile readiness after a successful push, without
pushing or validating again.

Keep active candidates through review, validation, and reconciliation. After
confirmed publication and PR reconciliation, mark their worktrees and build
outputs as eligible for retirement. Preserve batch metadata, pinned SHAs,
attempt logs, repair handoffs, and delivery evidence outside the candidate
before removing anything. A failed candidate remains retained while it owns
an unresolved reproduction or unique repair. Once superseded or resolved,
record its replacement and preserve the necessary patch and reproduction;
then mark its worktree and build outputs eligible for retirement too.

Use the existing batch evidence to record retention reason, owner or next
action, and retirement eligibility. Do this when the batch changes state;
do not add a scheduled cleanup or validation gate. Inspect retirement with
`retire <batch-id> --reason TEXT`; removal additionally requires `--apply` and
separate cleanup authorization. A resolved parked failure also requires
`--replacement LANDED_BATCH`. The command refuses unreconciled publication,
unresolved holds, pending changes, and ignored files outside known build-output
directories or Python bytecode caches. Unique unpublished commits also stop
retirement unless a reconciled replacement covers the old submissions and
`--archive-repairs` explicitly preserves that history. Review the replacement
and retention reason before using this option. The command verifies a full
candidate bundle and saves its binary patch before removal; a replacement
name alone does not authorize losing repairs.
The command retains batch records, attempts, pinned refs, a candidate bundle,
and candidate debug evidence outside the removed worktree. It uses ordinary
Git worktree removal without force. Never delete retained failures merely
because they are old, or remove records to release holds. Report remaining
retained candidates and their reasons at handoff. Starting this skill installs
no daemon or scheduler; stopped sessions leave records for the next integrator.
