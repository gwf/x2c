> Status: implemented; publication and provider acceptance in progress,
> 2026-10-01. Original design baseline: origin/dev at ff9946c82.
> Tools, shared worktree context, and optional offline probes are implemented.
> The connected guidance is a separate submission in the first live batch.
> Local rollout evidence lives in `debug/integration/` and `.context/`.

# Batched dev integration

## Result and scope

Support three ways to work, selected by Gary's instruction to the session.

| Mode | What Gary does | Who integrates into dev |
| --- | --- | --- |
| Individual session | Ask an agent to make changes as usual. | That agent reviews, integrates, gates, and publishes its work. |
| Session orchestration | Invoke `orchestrate-x2c-work` as usual. | That orchestrator combines its workers' changes, gates the batch, and publishes it. |
| Shared integrator | Start an integrator session; tell individual agents or orchestrators to use it. | Those sessions submit ready PRs targeting `dev`; the standing integrator reviews, batches, gates, and publishes them. |

The first two modes keep their current behavior. Shared integration is an
optional delivery choice, not a repository-wide replacement. Starting an
integrator does not silently reroute existing sessions. An instruction such
as "make this change, but use the integrator" selects PR submission for that
session; an orchestrator propagates that choice to its workers.

In shared mode, the integrator owns publication of queued work across sessions
and coding-agent providers. It needs the PRs and their evidence, not visibility
into each worker's session. `main` promotion stays separate in every mode.

Version 1 must work with both Codex and Claude Code, including mixed-provider
workers and orchestrators. Either provider can run the standing integrator.
Both use the same tools, PR contract, and canonical repository skills; provider
support is an acceptance requirement, not a later follow-up.

Gary's workflow adds only starting the integrator and choosing to use it.
Submission metadata, readiness, batch selection, validation, and recovery are
agent responsibilities. Gary does not manually operate the coordinator commands
or approve every routine batch.

For five compatible submissions, one successful batch replaces five separate
publication gates. This is an example of the intended saving, not a measured
speedup. Workers still need development builds and meaningful focused checks.
Gate failures and necessary bootstrap rounds can require additional runs.

Deliver one coordinator command and the connected guidance changes in one
implementation batch. Start on the existing working macOS host, with a
persistent checkout and ignored state. Do not introduce a database, managed
merge service, dedicated server, new CI requirement, speculative builds, or
automatic failure bisection. A later host move must preserve this contract.

Add `agents/skills/integrate-x2c-prs/SKILL.md` as the entry point for a standing
integrator session. Once started, it keeps looking for ready PRs, applies the
batching policy, integrates batches, and returns to waiting without another
request from Gary. It continues until stopped or a decision genuinely needs
Gary. When one batch needs worker repair, it can park that batch and continue
independent work. Report meaningful landings, failures, and needed decisions;
do not emit repeated empty-queue updates.

The first version stays live in that agent session on the existing host. It
does not install an always-on daemon or schedule background wakeups. PRs and
batch records persist if the session stops; restarting the integrator resumes
the queue. An absent integrator leaves submitted work waiting, rather than
making a worker fall back to direct publication without Gary's instruction.

## Current owners and evidence

- [Root guidance](../AGENTS.md) currently gates shared tips, including PR
  branches, and authorizes routine direct delivery to `dev`. PR submissions
  need a deliberate exception in shared-integrator mode. Direct delivery in
  individual and session-orchestration modes remains valid.
- [Orchestration](../agents/skills/orchestrate-x2c-work/SKILL.md) already
  assigns focused verification to workers and batches their private handoffs.
  Preserve that mode and add its optional PR delivery route. The standing
  integrator skill owns the queue across independent sessions and providers.
- [land-dev](../tools/land-dev) serializes publication in one Git common
  directory, integrates upstream, generates docs, gates, commits generated
  output, and pushes. It does not collect independent waiting submissions.
  It now allows one second bootstrap round after a `stage-diff-0` failure.
- [gate-state](../tools/gate-state.py) owns exact file/configuration/tool
  identity and unchanged-tree reuse. Its ignored receipts are workspace-local.
- [The worker hook](../tools/hooks/pre-push) prevents `agent-*` worktrees
  pushing shared branches, but is not a remote access boundary. `make configure`
  sets Git's `core.hooksPath` to `tools/hooks`; that Git hook is shared by
  providers. Its current directory-name check does not prove coverage of
  either provider's differently named worktrees.
- [Agent guidance](../agents/AGENTS.md) owns one canonical `agents/skills/`
  directory. `.agents/skills` and `.claude/skills` both link there, and
  `CLAUDE.md` links to `AGENTS.md`. Preserve these shared owners rather than
  copy the new skill or delivery rules into separate provider versions.
- [Performance guidance](../agents/performance-checkpoints.md) already
  measures applicable coherent batches separately from correctness gates.
- [The tooling plan](x2c-scripting-ports.md#ruling-on-gate-tooling) keeps
  tooling that operates around bootstrap independent of the compiler.

Current local gate duration, queue arrival rate, and realized batching savings
have not been measured. The design reduces repeated complete candidates; it
does not claim to make an individual gate faster.

## Submission and ownership

Make these connected guidance changes in `AGENTS.md`, `agents/quick-start.md`,
and the execution, bug-fix, cleanup, simplification, and orchestration skills
where their delivery instructions conflict:

- Root guidance names the three modes and keeps individual direct integration
  as the default. Explicit shared-integrator instructions override delivery
  for that session, persist until changed, and pass to its delegated workers.
  The existence of a running integrator alone is not a mode switch. Ordinary
  implementation skills follow root delivery selection without duplicating
  the queue policy.
- Private checkpoints remain unrestricted. A work submission on a PR branch
  targeting `dev` may be pushed without a publication gate or a final shipped
  bootstrap in shared-integrator mode. Describe it as a submission, never as
  validated publication. Normal direct publication and ordinary review-held
  PRs retain their existing validation rules.
- Workers review their authored diff and use the cheapest complete focused
  checks for their change, following the current orchestration guidance.
  They do not refresh final generated artifacts solely to submit, merge a
  moving `dev` solely for publication, or run a full gate solely to push a PR.
- The integration owner reviews the combined change, owns final generated
  artifacts, runs existing applicable performance work once per coherent
  batch, and gates before publishing. Documentation-only batches use
  `doc-check`; batches containing code use `agent-pr-check`.
- A user request to leave a PR for review remains a review stop. Creating a
  PR alone does not enroll it for automatic integration. Ordinary completed
  implementation submissions in shared-integrator mode are enrolled by their
  agents; explicit local-only and review-stop requests take precedence.

An orchestrator in shared-integrator mode still chooses workers, file
boundaries, dependencies, and coherent changes. It collects their handoffs
and submits one or more cohesive PRs instead of gating and publishing to `dev`
itself. Its workers need no knowledge of other orchestrators or providers.
Either kind of submitting session branches from `dev` or its recorded
dependency revision and targets `dev` in GitHub, not `main` or an integrator
branch. Session-orchestration mode continues to gate and publish its own batch.

Use one readiness label, `integration-ready`, on non-draft, same-repository
PRs targeting `dev`. The PR body retains its authored explanation and includes
one machine-readable JSON block delimited by dedicated HTML markers. Version
1 contains the recorded starting revision, submitted head SHA, dependency
PR/head pairs, focused-check commands and results, and optional bootstrap
transition notes. A result may explain why no runtime check applies.

Provide a `submit` operation to write this block without replacing prose,
verify that it names the branch's current head, and add readiness last.
For resubmission, remove readiness before updating metadata and reapply it
last, so readiness age belongs to this revision rather than a previous head.
Changing the head requires another submission; stale metadata is not ready.
Readiness means the authored work is complete, not that its integrated tree
has passed the gate. Do not automatically enqueue draft or review-held PRs.

For dependent work, record the actual starting revision, including a local
capability commit when applicable. Pin the required dependency revision.
Unresolved dependencies remain waiting. Include dependencies first in the
same batch, or prove their pinned revisions already occur in `dev` history.
Cycles and incompatible dependency revisions need the owner's attention.

## Provider-neutral integration and worker setup

Keep queue selection, Git operations, gates, receipt handling, batch records,
and PR metadata independent of provider APIs, session IDs, or transcript
formats. No Codex-only messaging, launcher, or app feature may be required for
submission or integration. A Codex integrator must accept Claude submissions,
and a Claude integrator must accept Codex submissions using the identical
protocol. Provider-specific skill metadata may aid discovery, but the shared
`SKILL.md` must be sufficient to perform the work.

The common worker restriction belongs in `tools/hooks/pre-push`, not in two
agent-native hook implementations. Extend worktree setup to record an explicit
role and delivery choice in ignored `debug/agent-context.json`, instead of
relying on provider-specific directory names. A subordinate worker cannot
push `dev` or `main`; an individual or orchestrator using PR delivery cannot
push those branches either. Individual/direct orchestrator publication and
the integrator's `dev` publication retain their proper permissions. Use that
same context for the existing worker guard in `tools/gate-state.py`, rather
than invent another provider-specific gate rule. Keep the existing `agent-*`
fallback for legacy worker worktrees without an explicit context.

Agents establish or update this context when selecting a mode or preparing
delegated worktrees, through a shared coordinator operation. It is task-local
state, not a provider detector or a global mode switch. Switching modes must
update it; creating an ordinary branch does not grant integration ownership.
Preserve unrelated user Git configuration, and verify the effective hook path
and executable hook in the actual worktree rather than assuming configuration
succeeded. Any conflicting existing hook setup must be handled explicitly,
without silently replacing it.

Verify Codex's instruction/skill discovery and Claude's `CLAUDE.md`, skill
discovery, and existing `.claude/settings.json` startup configuration. Add a
small provider-specific setup adapter only if that provider's startup or
worktree lifecycle requires it to call the common setup. Any adapter must
invoke the same tools and preserve existing settings; it must not duplicate
queue, delivery, or gate policy. Gary still only starts the integrator and
tells chosen sessions to use it. These are setup differences to verify during
implementation, not reasons to deliver only one provider first.

## Coordinator and batch lifecycle

Add `tools/integrate-dev.py`, using Python's standard library plus existing
`git`, `gh`, `make`, and publication commands. It must run without a working
x2c compiler. Keep GitHub access, batch records, and sequencing in this single
tool; do not add a queue framework or a second gate receipt implementation.

Expose `submit`, `status`, `wait`, `prepare`, `land`, and `park` operations.
`wait` polls GitHub until work is eligible or a bounded timeout expires; each
call waits at most 60 seconds and is interruptible. The integrator skill loops
over waiting and processing, with no fresh user prompt between batches. The
coordinator schedules and records work; the agent handles review, conflicts,
bootstrap sequencing, and diagnosed failures. It never launches provider-
specific agents or requires access to their private session state.

`prepare` selects ready work and creates a candidate; it never gates or
publishes.
`land <batch-id>` gates the reviewed authored candidate and stops for generated
artifact review. `land <batch-id> --publish` publishes that same gated commit
after review. `park` retains a failed candidate and releases it from the active
slot. These operations express the existing authored-review, generated-review,
and publication sequence without another human approval ceremony.

Store each batch under the persistent integration checkout's ignored
`debug/integration/<batch-id>/`, outside `unittest/build/`. An atomically
replaced JSON record contains repository identity, selected `dev` SHA, ordered
PR/base/head/dependency revisions, checkout path, lifecycle state, candidate
commit, log paths, gate attempts and elapsed times, and landed commit when
known. Keep attempt logs immutable. A latest pointer is only a convenience.

Use a coordinator process lock in the integration checkout's Git common
directory for each command's mutations. Between commands, the durable batch
record reserves the active slot; `prepare` resumes or reports an unfinished
active batch rather than selecting another. Only landed or explicitly parked
batches release that reservation. Reuse land-dev's publication lock for its
own operation; do not acquire it twice. Another invocation reports the holder
and waits or exits without changing the batch. Do not steal a live lock or
discard an interrupted candidate.

1. **Select.** Query eligible PRs and their metadata. Order by GitHub's
   readiness-label event time, then PR number. Start with at most five PRs,
   with a five-minute collection window from the oldest eligible submission.
   An already old singleton runs immediately. Both limits are command options;
   an explicit flush bypasses waiting. These are initial tuning choices.
   Include a complete dependency group, counting it toward the cap. Oversized
   groups require an explicit larger selection; never split required work.
   Revisions in parked failed batches are held from automatic selection until
   explicitly retried or superseded by a new submission. Hold their dependents
   too, while allowing independent queued work to proceed.
   `prepare --retry <batch-id>` explicitly releases that hold for the selected
   revisions after diagnosis; it still requires current eligibility.
   Allow an explicit PR list when overlap or bootstrap sequencing needs an
   operator-selected batch. Do not infer semantic independence from paths.
2. **Freeze.** Fetch and retain each selected head under local batch refs.
   Check the fetched revisions against the selection before building. Pin
   the base and membership in the batch record. Arrivals go to the next batch.
3. **Assemble.** Create `codex/integration-<batch-id>` in an isolated persistent
   candidate worktree from the pinned `dev`. Merge pinned PR heads in dependency
   order with merge commits, preserving their ancestry and individual diffs.
   Do not squash or cherry-pick away submitted heads. On a conflict, preserve
   the worktree and record `needs-attention` for the integration agent.
4. **Prepare and review.** Resolve authored conflicts by preserving intent.
   Regenerate generated files from their owners rather than treating competing
   outputs as authored changes. For capability transitions, prepare the seed
   with existing local build/stage operations before compiling dependent
   callers. Use declared transition notes as review input, never as shell
   commands to execute automatically. Commit the combined authored result,
   review its diff against the pinned base, and run any focused interaction
   checks. Record the reviewed candidate commit.
   Choose the gate from the actual integrated diff against this reviewed base,
   including conflict resolutions, rather than from worker metadata. Default
   to the code gate. Allow `doc-check` only for non-executable regular Markdown
   files under `agents/`, `docs/`, or `plans/`, plus root `AGENTS.md` and
   `README.md`, with no type/mode change. Mixed or unknown paths use the code
   gate. Read Git's NUL-delimited path/status data so filenames cannot alter
   classification; recompute after authored edits or upstream integration.
5. **Land.** Refresh PR eligibility and require the selected heads still to
   match before publication; a closed PR, withdrawn readiness, or changed
   head parks the candidate. Do not silently incorporate a replacement head.
   Compare current `dev` with the reviewed base. If it advanced, integrate
   and return for review before gating. Then invoke `tools/land-dev` once for
   a code batch, or its documentation-only mode described below. Review the
   generated deltas before the actual push. Store that final gated commit in
   the record. On `land --publish`, recheck PR eligibility, upstream identity,
   the candidate commit, and gate-state without building or regenerating.
   Anything that changes the candidate returns to authored review/validation;
   it must not slip into the artifact-reviewed publication. Retain gate-state's
   final check.
6. **Reconcile.** Fetch `dev` and confirm the final candidate commit is its
   tip or an ancestor. Only then record `landed`. The merge ancestry lets
   GitHub recognize incorporated PR heads. Remove readiness only for a PR
   whose current head still matches the incorporated revision. If the PR
   advanced after the last eligibility read, record the older revision as
   landed and leave the newer work unresolved. Never mark a newer revision
   validated. A failed metadata update is retried without another gate/push.

Once gating begins, changes to PR heads cannot change the candidate. A later
withdrawal can race publication; document that readiness is a request to land
the pinned head and withdrawal is effective only when observed before push.
Do not promise transactional cancellation across GitHub and Git.

## Keep publication in land-dev

Extend `tools/land-dev` with optional flags while preserving its current
positional message and direct-use behavior:

- `--review-stop`: produce the gated candidate and generated commits, then
  stop before pushing. After generated-diff review, use
  `--publish-reviewed <gated-sha>` with the same gate and expected-dev options:
  check the exact commit, clean tree, unchanged proof and upstream, then push
  without build or regeneration. This supplies the existing required
  artifact review at the right point without another full gate.
- `--expected-dev <sha>`: for queued integration, stop if upstream differs
  from the reviewed base, including after a rejected push. Return to the
  coordinator for integration and review instead of automatically merging
  and regating an unreviewed candidate.
- `--gate doc-check`: for a documentation-only authored batch, omit compiler
  bootstrap refresh and self-host/code checks and run the existing documentation
  gate. Initialize a fresh candidate's stage 0 with normal `make build-safe`
  setup when required, as root guidance specifies. Do not regenerate unrelated
  documentation just to land a plans edit. Retain the code path as the default.

`doc-check` uses x2c scripts and has no build prerequisite. Its audit also
requires and invokes the candidate's `builds/0/x2c` directly, so merely passing
an external `STAGE0_X2C` does not prepare a fresh documentation candidate. Keep
the normal stage-0 setup above rather than add artifact-sharing machinery or
change the audit. Reuse that prepared compiler within the candidate; the
reviewed publication operation never rebuilds it. This is tool preparation,
not another publication gate.

Before pushing, require a clean tree, a valid matching gate receipt, and
`git diff --check`. Commit only known generated outputs owned by preparation;
stop on unexpected authored changes rather than broadly staging them as a
refresh. A source edit after review requires another authored review and the
normal exact-tree invalidation. Generated changes require artifact review.

Preserve the current bounded second round for the recognized bootstrap
stage-diff failure. Do not add retries for ordinary test failures. Gate targets,
step order, assertions, and configuration/tool identity remain unchanged.

An integration failure preserves the candidate and logs. The owner diagnoses
with focused checks, fixes the combined change or prepares a revised batch
excluding the suspect PR and its dependents, then reviews and gates the new
tree. Do not automatically run a full gate per constituent PR. Independent
ready work may proceed in a later batch after the failed candidate is parked.

Recovery reads Git history and gate-state rather than trusting a recorded
`running` state. A crash after push but before record update is reconciled
without republishing. A crash before push reuses proof only when gate-state
confirms it; missing proof requires normal validation. Never reset or delete
a failed worktree to make the queue appear healthy.

## Implementation and rollout

1. Implement coordinator selection, pinning, durable records, isolated
   candidates, recovery, and the small land-dev extensions. Keep queue policy
   inactive until the whole implementation is available.
2. Update the connected guidance and worker hook wording. Permit PR submission
   from worker worktrees while preserving their shared-branch prohibition.
   Implement the common role/delivery context and use it in pre-push and the
   existing gate-state worker guard. Verify effective setup for actual Codex
   and Claude worktree creation, including names outside `agent-*`. Keep any
   necessary startup adapters thin and preserve unrelated configuration.
   Preserve the existing orchestration skill's direct mode and add its shared-
   integrator delivery option. Add the standing `integrate-x2c-prs` skill,
   route it from `agents/README.md`, and expose it through the repository's
   existing skill directories. Put its wait/process/recovery loop there.
   Verify discovery through both `.agents/skills` and `.claude/skills`, and
   root guidance through `AGENTS.md` and `CLAUDE.md`; keep one canonical copy.
   Add short examples for the three user workflows in quick-start, with one
   owner for each rule. Do not add an independent approval or gate skill.
3. Validate with disposable local repositories and stub GitHub/gate commands.
   Exercise a successful multi-PR batch, a singleton, documentation-only work,
   pinned dependencies, moving heads, withdrawal, authored/generated conflicts,
   upstream advancement, ordinary gate failure, the existing bounded bootstrap
   round, and interruption before/after push. Verify no failed/unvalidated
   candidate pushes, no newer PR head is credited, and recovery does not repeat
   a successful gate or push. These are finite implementation checks, not a
   new recurring test requirement or added Make target.
4. Use fresh read-only sessions in both Codex and Claude for individual direct
   integration, normal orchestration, an individual session told to use the
   integrator, and an orchestrator told to use it. Verify skill discovery,
   delivery ownership, and inherited worker instructions. Also cover a
   review-stop PR, a private checkpoint, and a
   combined bootstrap capability/adoption batch. Exercise the standing loop
   with an empty queue followed by arriving PRs, and equivalent submissions
   from both providers; it must process them without another user prompt.
   Test a Codex integrator handling Claude work and a Claude integrator handling
   Codex work, including orchestrator submissions, using disposable repositories
   and stub gates for parity. Exercise the common Git hook from each provider's
   actual worktrees: worker/PR-mode shared-branch pushes fail, PR branch pushes
   work, and legitimate direct-mode/integrator pushes work. Perform these
   failure probes against disposable local remotes, not live shared branches.
   Review and fix the completed authored diff before final publication proof.
   Deliver the connected implementation once under the current `dev` rules.
5. Start a designated integration agent on the existing host and route the
   pilot's individual workers and orchestrators to it explicitly. Preserve
   direct delivery for sessions operating in the first two modes. The local
   lock coordinates this repository, not separate clones/hosts. A direct-mode
   session can advance `dev` while the integrator works; unexpected advancement
   stops queued publication for integration, review, and validation of the new
   tree. Do not claim remote enforcement while agents share Gary's credentials.
   Separate service
   credentials and remote restrictions are a later, explicitly scoped option.
6. Run one live multi-submission batch as the pilot's actual publication,
   reusing its gate as acceptance evidence. Record full gate attempts and
   elapsed time, landed changes per batch, retries and reasons, and readiness
   to landing time from existing logs/records. Compare with available similar
   single-change runs on the same host/configuration; if none exist, report
   counts and latency without inventing a measured speedup. Tune collection
   limits from this evidence. Do not add benchmark-only full gates or thresholds.

## Acceptance and compatibility

- Individual sessions still integrate directly by default. Invoking the
  existing orchestration skill still makes that orchestrator responsible for
  its workers' integration unless Gary selects the shared integrator.
- "Use the integrator" makes either type of session submit ready PRs on `dev`
  without doing final integration itself; the choice reaches delegated workers.
  Gary need not supply metadata, batch commands, or routine merge approvals.
- A started integrator waits for PRs and processes later arrivals and subsequent
  batches without repeated invocation. PRs from different providers use the
  same handoff; the integrator needs no visibility into their private sessions.
- Version 1 passes the three-mode and submission/integration scenarios with
  both Codex and Claude. Either can integrate the other's PRs. Skill discovery
  and worker restrictions work in each provider's actual worktrees, including
  worktrees whose names do not match `agent-*`. Provider setup has one shared
  policy owner and requires no extra workflow steps from Gary.
- Two or more ready compatible code PRs can land with one successful full gate
  on the final combined tree; necessary bootstrap rounds are separately counted.
- Submitted work does not run publication gates solely to push its PR. Review
  stops remain held, and ordinary code/runtime verification remains meaningful.
- Shipped `dev` tips rebuild from shipped bootstrap and retain the same complete
  publication checks. Gate-generated output and conflict resolutions land with
  the tested sources, with artifact review before push.
- No test failure, unknown gate receipt, wrong PR head, unresolved dependency,
  unexpected upstream movement, or interrupted bookkeeping silently validates
  or credits work that was not integrated and checked.
- A doc-only batch does not run the code gate. Existing manual local build,
  stage, performance, and release operations remain available.
- No Make gate expands or reorders. Shared-mode queue coordination replaces
  repeated per-agent publication work; it adds no recurring test/planning/commit
  gate and does not replace the other two operating modes.
  The plan does not authorize production promotion or install a scheduler.

## Plan review

Git establishes immutable commit identity and merged ancestry; GitHub supplies
current PR eligibility; workers supply revision-specific focused evidence.
The coordinator compares these facts only where changing remote heads or an
interrupted publication could land or credit the wrong work. It does not repeat
compiler semantic validation or infer contracts from changed filenames.

Reuse the existing orchestration, Git worktrees/merges, land-dev sequence,
gate-state identity/receipts, and performance checkpoints. Delegate publication
only for sessions selecting shared integration; preserve direct ownership in
the other modes. The one new integrator skill owns continuous cross-session
queue work; existing orchestration still owns worker management. One JSON
submission block transfers facts across sessions; one batch record preserves
pinning and recovery. Both are necessary
because a PR head and process state can change. No dependency cache, database,
alternate gate, compiler feature, or general agent framework is introduced.
The coordinator deliberately remains outside x2c's bootstrap dependency.

The existing Git hook remains the one push-policy owner across providers.
One ignored worktree context identifies role/delivery where directory names
cannot; the gate's existing worker restriction consumes that same fact.
Provider adapters, if needed after lifecycle verification, only install or
invoke common setup. Canonical skill and instruction links prevent competing
Codex/Claude copies. No provider-specific queue implementation is proposed.

Checks for stale submission heads, dependency identity, gate proof, clean tree,
reviewed upstream, and landed ancestry prevent wrong publication or false
credit. Eligibility checks protect deliberate review stops. Existing compiler
diagnostics remain unchanged; no new compiler validators or negative compiler
fixtures are proposed. Disposable failure scenarios verify publication safety
and recovery without becoming recurring gate requirements. The implementation
ends with authored and generated review before its existing publication proof.
