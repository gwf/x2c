# Improve agent onboarding without adding process

> Status: blocked - implemented locally; behavioral acceptance is unmet.
> 2026-09-08. Gary subsequently requested a draft PR for review; delivery to
> main remains blocked, and this plan stays active for the remaining work.
> Baseline: `11fd2fb`. Frozen evaluation inputs and raw evidence remain outside
> tracked source; `.context/onboarding-repair/` locates local verification.

## Result and implementation

Make guidance accurate, publication evidence reliable, workflow selection
proportionate, and measurements honest. Preserve canonical skills, shared
discovery, authorization and delivery rules, and current publication targets.
Change no compiler/runtime semantics. Add no dependencies, hooks, recurring
gates, or mandatory reading steps.

In value order:

1. Correct debugging examples for Var/Symbol comparison, optional compound
   List selectors, and diagnostic flags. Link include-cycle semantics to the
   book and publication to root instructions. Repair demonstrated adjacent
   drift without rewriting unrelated guides.
2. Compare content, file type, executable permissions, and symlink targets in
   gate records. Preserve evidence across staging, commits, and staged
   deletion. Keep index-based content hashes for unchanged files. Refuse
   evidence when Git inventory fails. Bump the record format; each workspace
   with an old record must validate again once.
3. Let current-behavior questions finish with an evidence-backed answer in
   plan-x2c-change, including its description and UI prompt. Keep durable plans
   for proposed changes. Link the source graph from onboarding and relevant
   skills; keep runnable caller, allocation-return, and repeated-walk examples
   in its existing README. Analysis remains optional and cannot prove safety
   merely by returning no findings.
4. Report explicit Make gate requests as `make_gate_requests` and ensure
   requests as `ensure_gate_requests`; ensure is not Make. Remove unsupported
   redundant-build counts and percentages, retaining other measurements and
   target counts. Document renamed fields and historical recomputation. Use
   the corrected reporter for both sides of this comparison rather than
   introducing outcome parsers.

## Verification

Freeze the baseline, prompts, rubric, models/settings, authentic extended
history and evaluation point, and limits before edits. Use complete isolated
Git checkouts and shared skill links, retaining private raw transcripts and
temporary runners outside the repository.

Extend existing tests with real temporary Git repositories for content, mode,
type, symlinks and dangling links, additions/deletions, staging, commits,
ignored files, failed inventory, and old records. Exercise ensure through its
CLI and a real small Make target: cached requests run nothing, relevant
changes rerun, and failed targets never record green evidence. Verify both
transcript parsers distinguish Make and ensure requests and ignore quoted
command text. Check links/discovery/metadata, compile corrected complete
examples, and run documented source-graph commands.

Run five scenarios against both versions with Claude and Codex, three times:
60 planned sessions. The cases are a current-behavior question, routine repair
followed by requested-PR steering, an unresolved semantic choice, source-tool
discovery, and an authentic extended conversation followed by a task change.
Use neutral identical prompts/settings within each agent, five minutes per
short session and ten per extended session, and at most three concurrent
sessions. The initial maximum is six agent-hours. Child exercises may inspect
and plan but not edit, build, or publish. Their results establish planning
behavior; executable probes establish tool behavior. Preserve timeouts and
failures. After repairs repeat only affected cases and disclose added usage.

Each revised trial must meet task, factual, and authorization expectations;
aggregate success cannot hide a failure. Compare time, reported tokens, calls,
documents read, and proposed builds by case and agent. Investigate consistent
increases and retain only necessary costs. Measure clean-tree gate-check
latency before/after, cache-hit build count, and unchanged-file rehashing.
Review the diff for extra reading, duplicated facts, automatic graph builds,
dependencies, and recurring validation changes; remove those additions.
Report the one-time gate migration cost and evidence limits: three repetitions
and one replayed extended history are not universal long-session proof.

## Delivery

Review and fix the completed authored diff and finish behavioral evaluation
before final publication validation. Fetch and integrate origin/main, inspect
generated changes, run git diff --check, and ensure agent-pr-check on the final
tree. Keep Make targets/sequencing unchanged and run focused tooling tests
explicitly. Gary subsequently requested a draft PR: push the workspace branch
to the same-named remote branch and use main as the base. Leave it available
for review. Archive this plan with outcomes, measured costs, and remaining
limitations when acceptance is met.

## Plan review

Source, generated C, and the book establish technical facts; guidance links
to those owners. Git and filesystem metadata supply missing gate facts.
Transcript commands establish requests, not successful or wasted builds.
Existing skills, graph tools, tests, and temporary evaluation scripts supply
the implementation. Remove stale instructions and derived metrics rather than
adding another framework. New gate regression cases protect demonstrated
false evidence; metrics cases protect incorrect reports. No compiler/runtime
validator, diagnostic, negative fixture, or recurring check is introduced.


## Implementation results

Corrected the comparison/selectors example, diagnostic flags, include-cycle
advice, and publication link. Added answer-only skill completion and optional
source-graph discovery with runnable caller, allocation, flow, and walk queries.
Fixed source-backed adjacent errors about catchable void operations and
canonical List allocation; regenerated API pages and header input hashes.
The graph can report a dangling return for an ancestor-owned canonical List
that survives the inner Context. Its README now describes that limitation.
No analyzer, compiler, or runtime behavior changed.

Gate records now include type, executable permission, and lexical symlink
targets; staging/commit/deletion invariance and index-hash reuse are preserved.
Git inventory failures cannot record or reuse evidence. Format 4 invalidates
older records. Metrics distinguish Make and ensure requests and remove the
unsupported redundant-build inference; historical reports must be regenerated.

Repeated expansions of the planning skill's choice paragraph did not repair
Claude's refusal to consider a requested alternative. Removed those unproved
instructions, retaining the original consequential-choice rule and the approved
answer-only completion. This deletion avoids making the failed experiment a
permanent reading cost.

## Verification results and remaining work

Focused tooling tests passed: 17 gate-state tests and 8 harness tests. Real Git
repositories and real Make executions cover the stated content, mode, type,
symlink, deletion, staging, commit, inventory-failure, migration, cache, and
failed-target cases. Unchanged cache requests execute no Make target.
All 11 skills' metadata/discovery and affected references were checked.
Corrected examples and ownership/catch probes were compiled and executed;
documented graph queries ran against current source. An initial Context probe
had an incorrect native pointer comparison; its corrected strcmp assertion
passed with an explicit exit check. Its earlier failure remains in local logs.

The controlled comparison stayed on 11fd2fb; local native verification also
integrated origin/main through 7557534. The 60 initial trials passed 23/30 on
baseline and 25/30 on the first candidate. After 42 affected-case reruns, the
latest tested case set was still 25/30: behavior, repair/PR follow-up, and
extended-task change each passed 6/6; semantics passed 3/6 and analysis 4/6.
Every failure remains recorded. No trial timed out or changed its worktree.

Three substantive Claude failures remain: refusing the requested Null option,
misstating current truth tests and requiring two publications, and claiming
canonical List conversion always creates fresh caller-owned cells. Two final
Claude trials hit its session limit, which reported a 5:10 pm Pacific reset on
September 8. Later canonical-allocation documentation corrections and removal
of ineffective choice instructions have no final-tree agent evaluation yet.
These changes do not turn failed trials into passes.

The next work is to resolve the remaining semantic failures and repeat the
semantic/analysis cases on the final authored tree after Claude is available.
Do not merge or archive this plan as completed while acceptance is unmet.
A decision to relax that acceptance belongs to Gary. The existing code gate
still validates local implementation; its current record and full log live in
`debug/gate-state.json` and `debug/onboarding-final-gate.log`.

## Measured costs and limits

The initial 60 trials consumed 1.170 agent-hours; the 42 reruns added 1.106,
for 2.276 controlled agent-hours. Two preflights, four invalid-history/setup
attempts, and three interrupted superseded attempts are additional. Known
Claude CLI cost estimates total $123.78 including those extras, with incomplete
partial usage beyond that; these are not billing records. Codex supplied no
dollar estimate. Controlled cumulative input totals were about 20.0 million
Claude tokens and 15.5 million Codex tokens, including cache rereads.

The corrected reporter found 456 baseline tool calls and 448 in the latest
tested set, with zero actual Make/ensure requests throughout. Some behavior
and source-analysis trials read more and used more tokens; relevant source
investigation explains the reads, but three repetitions do not establish that
every added token was necessary. Fast quota failures are not efficiency gains.
Unsupported proposals for extra publication/build work were scored as failures.

On a clean seed, 21 interleaved warmed gate checks had median 133.34 -> 154.59 ms
and p95 137.31 -> 175.68 ms, including Git/compiler processes but excluding
Python startup. Metadata added about 21 ms; unchanged files had zero content
rehashes. Each workspace with an old gate record must validate once again.
The authored affected guidance/API pages add 383 prose words and 70 physical
lines, excluding this plan and fenced code from the word count. No dependency,
mandatory reading, automatic graph build, or recurring validation changed.

Scratch peaked at an observed 699.6 MiB; roughly 233 MiB of seeds and evidence
remains after removing all trial checkouts, plus at least 56.9 MiB of managed
CLI transcripts. The authentic history replay held 785,372 UTF-8 bytes; peak
reported request inputs were 355,892 Claude and 240,179 Codex tokens. Its first
serialization mistakenly included opaque internal records; the corrected
serialization preserved visible history at the same frozen endpoint on both
versions, retaining invalid attempts as costs. The PR follow-up used native
resume; the long history was replayed. Three repetitions and one history do
not prove universal long-session reliability.

Detailed local evidence is in `.context/onboarding-evaluation.md`,
`.context/onboarding-repair/`, and `/tmp/x2c-onboarding-value-eval/` (frozen
inputs, manifests, native transcripts, scores, comparisons, and usage). No
runner, transcript, or evaluation framework was added to tracked source.
