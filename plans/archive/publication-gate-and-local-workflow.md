# Lightweight local work and bounded publication

> Status: done
> Implemented on 2026-09-28 following Gary's instruction to deliver to dev.
> Guidance: `0899be3a`; fixture supervision: `d3a336b9`; publication tooling
> and this record close in `streamline publication and preserve failed attempts`.
> Shared delivery remains subject to the final-tree publication gate.

## Implementation result

Private commits and local capability adoption no longer require publication.
The ordinary gate retains bootstrap/stage proof and the existing focused
suites, but drops the full raw-symbol sweep and checks docs before tests.
Landings preserve each attempt's tree/logs, do not blindly retry gate failures,
and retry a rejected push only when origin/dev actually moved. Major gate
steps print elapsed times. Fixture workers retain parallel dispatch, enforce
configurable deadlines, clean up descendants, and stage expected updates.

Disposable harness checks covered success, ordinary failure, compiler and
native-program timeout, parallel overlap, direct/suite interruption, a
TERM-ignoring child, update preservation and write failure, and invalid limits.
Temporary-repository checks proved successful delivery, failed-gate no-push,
retained failed tree, and no retry for a server rejection without upstream
movement. Fresh planning checks confirmed the three workflow boundaries.

The historical compiler hang did not reproduce at the integrated base
`6b418055`: fresh stages 0/1/2 completed diagnostics-json in 0.90/0.14/0.27s
with unchanged expectations. No compiler repair was needed. The optional
full raw-symbol sweep took 131.66s on this host and compared 646 of 647
required sources successfully; src/macros.x failed standalone raw translation
with missing Compiler methods on unchanged source. After the publication
gate refreshed the compiler, a relative-path standalone src/macros.x raw
translation passed in 717 ms at `813a897d`. That isolated pass did not prove
the complete sweep passed or establish the cause of the earlier failure.
No expectations were rewritten. The required gate's final timings and corpus
summary are kept in its attempt log.

The full follow-up sweep at `be226450`, after a fresh `make build-safe`,
finished in 111.96s: 648 required sources, 409 classified exclusions,
647 successful comparisons, and one failure at src/macros.x. Separate bounded
invocations failed in raw mode with both relative and absolute source paths;
CPP mode succeeded. The failure is therefore still reproducible, and path
spelling does not explain this run. Its cause and relationship to the earlier
successful compiler remain unproved. The open work is recorded in
[Raw-symbol macros translation](../raw-symbol-macros-translation.md).
Logs remain in `debug/raw-symbol-followup.log` and
`debug/raw-symbol-{relative,absolute,cpp}.log` in the d40d worktree.
The fixture deadline remains 60 seconds; no nightly requirement was added.

## Result and policy

Private development must support a short loop: change the language, build
it, refresh bootstrap when callers need the new capability, and try those
callers. A local commit is a checkpoint, not a publication event.

- Agents may commit whenever useful in their own unshared worktrees,
  including incomplete experiments and intermediate bootstrap states.
  Committing alone requires no build, test, gate, performance checkpoint,
  generated-document refresh, or separate bootstrap commit.
- Keep the working compiler and bootstrap usable for the next development
  step. Refresh bootstrap before adopting syntax or capabilities that the
  seed cannot consume. This does not require every historical local commit
  to rebuild from its own bootstrap.
- Feature introduction and adoption may share one local branch and one
  publication batch. Dependent workers may start from a local capability
  commit; they do not wait for its publication to dev.
- Published tips on shared upstream branches must build from their shipped
  bootstrap. Validate the completed integrated tree before pushing it,
  including a requested PR branch. This does not impose independent gates
  on each intermediate commit included in that push. Main promotion keeps
  its separate release authorization.
- Use focused checks during implementation when they answer a question.
  Existing bootstrap and stage builds are useful, inexpensive experiments;
  they do not automatically trigger the full publication gate.

## Evidence and limits

At the inspected HEAD, `6b418055`, the orchestration skill forbids worker
commits, requires capability work on its own branch, and says callers follow
in a later batch. Its capability instructions invoke `tools/land-dev`.
These rules force full publication between local dependent steps.

On September 28, observed successful full gates in the compiler-warnings
worktree took at most 4m37s and 4m32s from launch to observed success. A
complete landing took at most 5m38s. A batch with four gate attempts took
16m35s through push; failures were a fixture, the raw-symbol sweep, and
generated documentation before the successful attempt. These are observed
bounds from session timestamps, not estimates from log modification times.

A later live gate waited over 32 minutes on `diagnostics-json.x`; its one
compiler process consumed a core and 12.8 GB. Fresh stage-0 and stage-2 runs
timed out after five seconds. Another built compiler processed the same
fixture and expected diagnostics in 0.13 seconds. A stack sample placed the
busy process in `Compiler.full_parse`. This establishes a regression in the
tested compiler, not its exact source-level cause. Recheck current dev
before repairing it; another session may already have fixed it.

The raw-symbol sweep separately translates every eligible source twice. A
recent successful run compared 637 sources, after the ordinary fixture and
stage checks. Fixture source count grew from 591 to 894 between September 5
and the inspected HEAD. Its wall-clock share has not been measured.

The broad gate predates most recent growth. Doc-output execution was added
September 17, cold collection September 23, and command checks September 24.
These facts do not establish that any of those additions accounts for an
hour. Do not promise a measured speedup before a comparable run.

## Parallelism already present

`unittest/compiler-fixtures/run.sh` launches one worker per fixture through
`xargs -P "${JOBS:-$(getconf _NPROCESSORS_ONLN)}"`. The observed run used
16 workers. Within a fixture, dump, translate, native compile, and execution
phases run sequentially so their artifacts remain attributable to that case.
The parent currently waits for every worker before reporting their tallies.

`src/cli.x` defaults ordinary translation to one job. `src/main.x` uses
translation workers only for multiple inputs with jobs greater than one,
outside dump and inspection modes. Fixture invocations generally pass a
single source, so adding `-j` there will not accelerate them. Native builds
can parallelize C compilation; under Make they default to one internal job
unless explicitly overridden because Make already owns concurrency.

`verify` also uses parallel Make for unit compilation and independent probe
targets. The raw-symbol sweep has its own CPU-count worker pool. Existing
Make and xargs pools do not share a jobserver, so increasing their widths
is not a justified fix. Preserve existing concurrency in this change and
measure with one explicit fixture `JOBS` value held constant. A hung final
worker still blocks the result regardless of pool size.

## Connected implementation

These are work items in one coherent batch, not mandatory separate landings.

### 1. Remove local publication requirements

Owners: `AGENTS.md`, `agents/skills/orchestrate-x2c-work/SKILL.md`,
`agents/skills/execute-x2c-plan/SKILL.md`, and `agents/quick-start.md`.

Put the local-versus-shared boundary in root guidance. Remove the worker
commit prohibition, the capability-only upstream landing, and the rule
that callers must wait for a later published batch. Replace them with the
local feature/bootstrap/adoption sequence above. Remove any requirement for
one commit per change or a separate bootstrap checkpoint during local work;
commit organization is an implementation choice.

Keep worker isolation and the orchestrator's ownership of shared delivery.
Workers may hand over commits or their existing authored patch. A patch
must include committed and uncommitted worker changes against its recorded
starting revision, not a newly moving upstream. When integrating dependent
changes, build the capability and refresh bootstrap locally before applying
callers that need it. No intervening full gate or push is required.
Replace the worker instruction to always branch from origin/dev with an
orchestrator-selected starting revision: current dev for independent work,
or the local capability commit for dependent work. Record that revision for
the handoff diff.

Explain that the existing `precommit` name denotes a readiness target, not
a Git commit prerequisite. Keep the target and its build behavior. Show
`make build`, `make bootstrap-refresh`, `make build-safe`, and
`make stage-2`/the relevant stage comparisons as available local tools, not
a mandatory sequence for every edit or commit. Do not introduce a new
"local gate", approval step, commit hook, or compliance checklist.

### 2. Reduce ordinary publication work

Owner: root `Makefile` and corresponding command documentation.

Remove `proof-raw-symbols` from `check-after-precommit`, so it no longer
runs under ordinary `check` or `agent-pr-check`. Retain the existing explicit
target and sweep implementation for collector/symbol-mode investigations.
Use existing header-cache and symbol-mode probes for focused regression
coverage; inspect their cases before claiming a particular guarantee.
Do not replace the removed sweep with another mandatory full-corpus pass,
nightly requirement, or a new suite that duplicates those cases.

Keep bootstrap refresh, clean rebuilds, self-host stage comparisons, cold
collection, unit suites, ordinary compiler fixtures and boundary probes,
artifact atomicity, doc checks/output checks, and command checks. Keep
existing optional suites optional. Gary's clarification supersedes the
earlier suggestion to prioritize removing duplicate bootstrap compilation:
clean bootstrap work is not the bottleneck this plan targets.

### 3. Bound fixture failures and repair the observed hang

Owners: `unittest/compiler-fixtures/run.sh`, its README, and the existing
compiler owner identified by diagnosis of `diagnostics-json`.

First reproduce the current behavior with a short bounded invocation and a
working comparator. If still present, repair the parser/recovery behavior
that prevents termination. Keep the existing fixture and expected error
limit behavior; do not delete it, raise its error limit, or bless a timeout.

Give each complete fixture worker a wall-clock deadline, initially 60
seconds, configurable through `FIXTURE_TIMEOUT_SECONDS` for an intentional
slow-machine investigation. Measure the healthy corpus to confirm adequate
headroom before choosing the shipped default. Timeout is a harness failure,
never an expected compiler exit status, and cannot update golden files.
Update mode currently writes expectations phase by phase. Stage a fixture's
proposed expectation writes with its existing scratch artifacts, and publish
them only after that worker completes successfully. A timed-out fixture
leaves its expectations unchanged; successful fixtures in the same update
run may still update normally. Do not add a suite-wide transaction.

Use one small process-group supervisor, reusing the termination pattern in
`tools/performance-snapshot.py`. Do not require GNU timeout on macOS or
build a scheduler framework. Retain xargs parallel dispatch. Supervise both
whole-suite and direct `--fixture` runs, including update mode. On expiry,
identify the fixture and elapsed limit, preserve its log, terminate its
process group, and escalate to kill after a short grace period. Record a
failure tally. Forward interruption and reap descendants so no compiler or
test child outlives the cancelled work. Print the timeout immediately;
ordinary completed-case summaries can remain aggregated.

### 4. Stop blind retries and preserve failure evidence

Owners: `tools/land-dev`, its orchestration documentation, and the existing
publication command in `tools/gate-state.py` where necessary.

Remove land-dev's unconditional second full-gate invocation. A failed check
stops publication on that attempt. If a language transition needs another
bootstrap round, prepare that round with the existing build/stage tools,
inspect the result, and then request the final gate. Do not rerun all tests
to discover whether an unexplained failure happens to disappear.

Keep final-tree invalidation after actual integration or source changes and
the existing unchanged-tree receipt reuse. Do not cache partial gate success
or introduce a dependency-inference system in this batch. An upstream push
race still requires integration and validation of the resulting tree.

Keep existing document generation before the gate. Move `doc-check` from
`check-after-precommit` to the top-level `agent-pr-check` immediately after
`precommit`, before cold collection and test suites. Have ordinary `check`
call it after its build and before the remaining checks as well. Each entry
point still runs it once, with a prepared compiler, but stale documentation
fails before the long test work. The documentation-only publication command
stays unchanged. Do not add a persistent cache or a skip-check switch.

Preserve the failed tree and logs rather than checking out `bootstrap/` and
`etc/` over them. Give each explicit landing attempt its own log location
and print it on failure; keep a convenient latest-attempt pointer. Avoid
discarding the first failure by overwriting its log during a retry.

Keep serialization for actual shared publication on this host. Private
commits, builds, and feature experiments never acquire that lock. Report
the lock owner and waiting state when another landing is active. Fixture
timeouts and normal failure/interruption must release the lock. Do not
remove a lock held by a live process or kill another session automatically.

### 5. Verify the completed change and deliver once

Use focused, disposable harness tests for normal success, an ordinary
failure, a sleeping/spinning fixture with a child, interruption, direct
fixture invocation, and update-mode timeout. Assert bounded completion,
nonzero failure, preserved output, no golden-file changes for a timed-out
fixture, and no surviving children. Exercise land-dev against a temporary
repository with stubbed commands: a gate failure runs once and never pushes,
while a successful
attempt retains normal delivery. Do not make these experiments an added
recurring gate requirement.

Use fresh read-only planning sessions to check the new instructions against
three neutral tasks: a private experimental commit, a language feature
followed by local adoption, and a completed batch ready for shared delivery.
The first must permit an immediate commit; the second must allow local
bootstrap work without publication; the third must retain final validation.
These are implementation-time checks, not a new ongoing approval process.

Run the existing healthy fixture corpus once to verify concurrency, timing
headroom, and unchanged expectations. Compare publication time on the same
host and build configuration, with the same corpus and worker count and
without a competing benchmark. Record elapsed time by existing major gate
step in the normal log, including the slowest fixture, to distinguish work
from waiting; avoid a new metrics service or database. Reuse a qualifying
final-gate run rather than repeating it solely for timing. Savings are
reported measurements, not a new performance threshold.

Review and fix the authored and generated diff before publication. Integrate
current origin/dev and use the existing final-tree publication command once
for the implementation batch. Follow the existing performance guidance for
build-orchestration changes without inventing another checkpoint. No
capability-only or policy-only intermediate landing is required. Update this
plan with measured results and archive it when the work is delivered.

## Acceptance

- An agent can make arbitrary local checkpoint commits without a gate.
- A feature, necessary rebootstrap, and its callers can be developed locally
  and delivered as one validated batch.
- Published tips retain bootstrap rebuildability and self-host proof.
- Ordinary publication does not run the full raw-symbol sweep or blindly
  retry a failed full gate.
- A hung fixture fails within the configured deadline plus termination
  grace, with an actionable preserved log and no orphaned descendants.
- Fixture parallelism remains available; neither local work nor a failed
  fixture silently holds publication forever.
- No tests are deleted to hide the diagnosed compiler regression, and no
  new recurring test suite, mandatory local sequence, or approval is added.

## Plan review

Local commits establish only recoverable history. They do not establish
publication readiness and need no consumer to demand that proof. The final
gate establishes the integrated published tree's consistency; duplicating
that proof between a private capability and its callers is unnecessary.

The design deletes worker commit bans, intermediate publication rules, the
mandatory broad symbol sweep, and blind retry. It reuses existing build,
stage, fixture, gate-receipt, and lock owners. One small timeout supervisor
is needed because shell/xargs dispatch currently cannot bound or reap a
stuck fixture's descendants. Attempt logs and elapsed output extend the
existing harness rather than adding a service or cache framework. Compiler
fixture update staging prevents a timeout from partially accepting that
fixture's new expectations; it reuses the fixture's scratch directory.
Compiler repair must stay in the existing recovery owner and use ordinary x2c
control flow; its precise edit remains subject to reproduction.

The only new failure condition is a harness deadline exceeded, protecting
bounded test completion and release of the shared publication lock. Its
message identifies an operational failure, not a new language diagnostic.
Use the existing diagnostics fixture for the compiler repair; no new
negative language fixture or validator is proposed. Disposable harness
probes test termination and evidence retention without expanding the gate.
