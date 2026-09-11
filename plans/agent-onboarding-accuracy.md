# Improve agent onboarding without adding process

> Status: active - implementation shipped; fresh acceptance failed.
> Implementation merged as 352d4d8 (#32). On 2026-09-10 Gary approved
> a fresh current-tree evaluation if the original inputs are unavailable.
> Historical failures below remain historical failures, not passing evidence.
> Baseline: `11fd2fb`. Frozen evaluation inputs and raw evidence remain outside
> tracked source; `.context/onboarding-repair/` locates local verification.

## Result and implementation

Make guidance accurate, publication evidence reliable, workflow selection
proportionate, and measurements honest. Preserve canonical skills, shared
discovery, authorization and delivery rules, and current publication targets.
Change no compiler/runtime semantics. The original scope added no
dependencies, hooks, recurring gates, or mandatory reading steps. The
separately approved startup-guide hook is recorded below.

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

## Fresh acceptance, 2026-09-10

Historical result: this cohort was later found to omit project onboarding
settings in one launcher. Its failures and costs remain evidence of those
settings, not the current comparison. The corrected comparison is recorded
below.

The approved current-tree fallback did not meet acceptance. The bounded search
did not recover the original inputs, so this is fresh acceptance, not a
historical comparison or an extended-history replay. Private evidence is
preserved outside the worktree at
`/Users/gary/Documents/x2c-evidence/closeout-20260910/onboarding/`.

The two installed CLI agents used their configured model and effort defaults,
fixed read-only settings, unchanged prompts and rubric, three repetitions of
each of five cases, five minutes per trial, and at most three concurrent
trials. The source snapshot contains 4,083 files based on `2d29fe9` plus the
authored closeout changes. Hashes, native transcripts, settings, timings,
provider usage, scores, and temporary runners are retained with the evidence.
CLI A and CLI B below are mapped to the installed tools in that private record.

| Case | Original A | Original B | Repaired A | Repaired B |
| --- | --- | --- | --- | --- |
| Semantic choice | 3/3 | 0/3 | unchanged | unchanged |
| Truth tests | 3/3 | 1/3 | 3/3 | 2/3 |
| Canonical ownership | 3/3 | 2/3 | 3/3 | 1/3 |
| Source-backed investigation | 3/3 | 3/3 | unchanged | unchanged |
| Answer-only completion | 3/3 | 3/3 | unchanged | unchanged |

The original safe cohort passed 24 of 30 trials. Two source-owner comments
were clarified after observed mistakes: `List.truth` and `String.truth` now
state the null canonical empty representations, and `Context.export` states
that retained-region values must be exported before releasing their Scope.
No executable behavior changed. A separate snapshot with only those comment
changes passed 9 of 12 affected-case retries. The original release-before-
export mistake was corrected, but other answer errors remained. No overall
improvement is established by these small samples.

Remaining failures replace the user's explicit semantic choice with an
invented API choice, confuse length with allocated presence, contradict
correct per-branch reasoning with an incorrect branch count, invent an Array
alias restriction, or misidentify the pool that closes after promotion.
Current owners already establish the correct behavior. No further guidance
expansion or repeated sampling is justified by those mistakes. This plan
remains open under its every-case acceptance rule.

There were 48 attempts: 45 completed and three were interrupted during a
runner-settings repair. Initial native plan mode demanded a private plan
write, conflicting with the read-only task; two denied Write attempts and
all setup records are preserved. Safe settings retained the read-only tool
allowlist and removed that mode conflict. Three completed trials with
unchanged settings were reused; setup failures were not counted as passes.
Every completed trial finished within five minutes.

The original safe cohort used 931.257 summed trial seconds and 133 tool calls
for A, and 723.572 seconds and 206 calls for B. The twelve retries added
701.041 seconds and 139 calls; setup-excluded attempts added 289.311 seconds.
Native token counters remain separate because the providers define cached
input differently. Direct Read path counts cannot be compared with shell
inspection counts. The existing harness command classifier found zero Make
or ensure requests. Raw tool events show read-only inspection throughout the
safe cohorts. Final content and symlink manifests and the frozen prompt/rubric
hashes match; observer-created bytecode caches were documented and removed.
No dependency, mandatory reading, recurring gate, or tracked runner was added.

## Corrected startup comparison, 2026-09-11

The earlier six-of-thirty result is historical and superseded for current
acceptance by a corrected launcher comparison. The corrected run restored
project settings and skill discovery and held the five questions, rubric,
three repetitions, five-minute limits, and low/medium/high efforts fixed.
CLI A passed 15/15 at each effort; CLI B passed 7/15, 7/15, and 9/15. The
private model and launcher records identify each CLI. This is a comparison
of those configured workflows, not a universal model ranking.

Gary then authorized one startup hook to supply the general
`agents/README.md`, leaving task-specific skill selection to the agent.
Commit e3884ae implements the hook; the duplicate native import was omitted,
and the superseded proposal was closed. The full agent-pr-check passed.
Unscored fresh-session checks established that either import alone or hook
alone supplies the guide; hook-only checks passed at all three efforts
without a model file-reading action. This establishes receipt, not adherence.
No Codex-specific injection was added: its corrected prior trials already
read the router and planning skill in all 45 sessions.

The user narrowed the new scored rerun to CLI B only. It uses fresh main
e3884ae, unchanged questions and rubric, the same model and CLI version,
three repetitions per case and effort, five-minute limits, and at most three
concurrent trials. The only behavioral launcher change enables project
hooks. Each trial must record exactly one successful startup receipt with
the complete frozen README. The unscored marker and duplicate import are
absent from the scored snapshot. The earlier CLI A results are historical
references, not fresh same-tree measurements.

Private corrected evidence: `/Users/gary/Documents/x2c-evidence/`
`closeout-20260910/onboarding/matched-effort-20260911/`.
New hook evidence: the sibling `startup-hook-matched-20260911/`; startup
preflights and publication evidence: `startup-import-20260911/`. Each run
retains its own frozen inputs, native transcripts, source manifests, and
scoring records. No evaluation runner or new recurring gate was added.

| Effort | Corrected prior CLI B | Startup-hook CLI B |
| --- | --- | --- |
| Low | 7/15 | 9/15 |
| Medium | 7/15 | 9/15 |
| High | 9/15 | 2 pass, 13 incomplete |

The client hit its session limit during high effort. The 13 unfinished
trials are not answer failures; their partial work and quota notices remain
recorded. Low and medium each have six failed answers under the original
rubric. Five of those failures substitute a different decision for the
user's public-truth choice; the others contain specific factual errors,
often in extra explanation after a correct central answer. The report
distinguishes core errors, peripheral claims, and ambiguous statements.
No complete effort level meets acceptance.

Every attempt received the exact guide through the hook. All 32 completed
answers finished within five minutes; the frozen source and input hashes
match, and raw actions show read-only investigation. Low and medium median
times were 46.725 and 54.572 seconds. All 45 attempts report $23.476 in native
list-price estimates; five unscored startup checks add $1.144. These are not
billing records. Quota-rejected attempts are not efficiency evidence.

The next bounded work is to retry only the 13 incomplete high cases after
quota is available, preserving the original attempts and explicitly reusing
the two completed high cases. The client reported a noon local reset. The
private report and `resume-required.json` identify the pending work. Do not
resample completed failures or archive this plan as accepted. The root
closeout record now reflects these results instead of the stale six-of-thirty
cohort.

## Follow-up configuration: import and hook

Gary subsequently requested the original `@agents/README.md` import alongside
the startup hook. The import is now present in root `AGENTS.md`, reached
through the existing `CLAUDE.md` symlink. The guide and task-specific skills
are unchanged. Earlier preflights established that each mechanism delivers
the guide on its own; they did not establish equivalent answer behavior or
test both mechanisms together. The combined configuration has no scored
acceptance evidence yet because the provider session limit remains active.

The results above remain results of the frozen hook-only configuration.
Trials with both mechanisms must form a separate recorded cohort; they must
not fill the 13 gaps in the hook-only cohort or be mixed into its score.
