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
provider using GitHub metadata, Git revisions, and repository tools; it needs
no worker session visibility or provider-specific messaging APIs.

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

## Keep the queue moving

Repeat this loop without routine user approval:

1. Run `tools/integrate-dev.py wait --timeout 60`. When the bounded wait ends
   with no eligible work, call it again. Emit no repeated empty-queue updates.
   A fresh user instruction may stop or steer the loop.
2. Run `tools/integrate-dev.py prepare` when eligible work is ready. It freezes
   PR heads and dependencies and assembles a candidate in a separate worktree;
   it never gates or pushes. Default selection waits up to five minutes from
   the oldest ready submission and includes at most five PRs. An old singleton
   runs immediately. Use `--flush` when instructed to process pending work now,
   or `--prs N ...` to choose a coherent group based on actual interactions.
   Do not keep adding arrivals to a frozen batch or split required dependencies
   to fit the cap. For a larger complete dependency group, use the
   coordinator's batch-size option deliberately.
3. Inspect the batch record and the candidate path reported by the command.
   Review PR explanations, focused evidence, pinned heads and dependencies,
   and the combined authored diff against the recorded `dev` base. Resolve
   conflicts by preserving the changes' intent. Use authoritative sources to
   regenerate shared artifacts. Read transition notes as evidence, never as
   shell commands to execute automatically. For capability/adoption batches,
   prepare the seed through existing focused build or stage operations before
   compiling callers. Finish pending merges and commit the authored resolution.
4. Run focused interaction checks when they answer a current question. Review
   and fix the completed authored diff. Perform the applicable existing
   [performance work](../../performance-checkpoints.md) once per coherent batch;
   queue operation itself adds no new performance or correctness requirement.
5. Run `tools/integrate-dev.py land <batch-id>`. It checks eligibility and
   upstream identity, invokes the existing publication helper and gate, and
   stops before push for generated artifact review. Inspect the returned state:
   `review` after upstream advanced means no gate started; review the combined
   diff and run `land` again. `gated` means validation finished. Poll logs only
   while the command is actually running. A doc-only batch uses
   `doc-check`; code or unknown paths use `agent-pr-check`. Prepare stage 0 in
   a fresh candidate with normal `make build-safe` when needed. Do not run
   broad gate components separately or replace the existing gate receipt.
6. Inspect every generated delta and the recorded final gated commit. If the
   authored tree changed or current `dev` advanced, return to authored review
   and normal validation; do not credit the old proof. Once review is complete,
   run `tools/integrate-dev.py land <batch-id> --publish`. It publishes that
   exact gated commit without rebuilding or regenerating an unchanged tree.
   The coordinator rechecks PR heads, readiness, upstream, clean tree, and gate
   identity, then confirms landed ancestry before recording success.
7. Report a meaningful landing with its PRs and validation. Return to waiting
   without another user request. Metadata reconciliation may be retried through
   `land`; a confirmed push or successful unchanged gate is not repeated merely
   to repair bookkeeping.

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
Report that failure and any decision needed, then continue independent ready
work. Parked revisions and their dependents stay held until superseded by a
new submission or explicitly retried after diagnosis with
`prepare --retry <batch-id>`. Retry resumes the retained candidate and its
frozen PR heads, preserving local repairs; finish or park any other active
batch first. Never reinterpret a newer PR head as validated.

When waiting for a delegated repair, check the worker's status. Resume an
interrupted or idle worker explicitly. For Codex subagents, `followup_task`
starts a turn; `send_message` only queues text. Verify the handoff before use.

For an interrupted gate or push, inspect Git history, the durable record, and
gate-state evidence through coordinator recovery. A recorded running state is
not proof of success or failure. Do not discard a candidate, rerun a known
successful gate, or repeat a confirmed push merely because the session ended.
Keep logs and report unresolved external failures plainly. Starting this skill
installs no daemon or scheduler; if the session stops, its submissions and
records wait for a resumed integrator.
