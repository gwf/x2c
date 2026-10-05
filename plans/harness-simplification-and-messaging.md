# Harness simplification and cross-platform collaboration

> Status: active
> Implementation authorized, 2026-10-05. Tool repairs, guidance simplification,
> and the host messaging pilot were delivered to dev at 3459d664 on 2026-10-05.
> External runtime repairs and a real-PR messaging trial remain open.
> Continuation requires no original worktree or pilot session.
> Planning baseline: origin/dev fe7123f3bb659b3e6624bdfb1e356d1999d38a5c.

## Intended result

Agents start from the intended revision, perform proportionate verification,
preserve failures, and explain observed behavior without inventing a contract.
An integrator can contact a submitting author on either platform, explain a
hold, request a repair, and receive a concrete answer in the original session.

Prefer deletion and reuse. Keep the existing integration queue, PR metadata,
publication guards, and validation targets. Messaging carries collaboration;
it does not own readiness, design authority, validation, or publication.

The October 5 session audit supplies the evidence. It found 20 rejected
terminal handoff calls across five workers, isolation false positives,
discarded benchmark reproductions, incorrect starting revisions, repeated
checks, correction-handling failures, and incomplete metrics. Full raw session
history remains outside the repository. The delivered tool changes repair the observed
benchmark cleanup and metrics defects.
The tracked [evidence record](harness-evidence-2026-10-05.md) preserves the
observations, validation, transport limits, and external reproduction reports.
Private raw transcripts are supporting evidence, not a continuation dependency.

## Decisions

1. Correct existing tools and remove competing instructions before adding
   mechanisms. Add no gate, daemon, scheduler, second queue, or mandatory
   planning step.
2. Keep same-platform subordinate workers on their native messaging and
   private handoff paths. Initially enable cross-platform mail only for
   top-level integrators and submitting author sessions.
3. Pilot Postbag 2.3.0, pinned to its reviewed release, before adoption.
   Research supports a candidate, not a claim of reliability on this host.
4. Extend the existing submission metadata with an optional contact. Keep
   older submissions valid. Absence of a contact must not block enrollment.
5. Do not build replacement runtime enforcement inside the repository.
   External defects require a configurable removal or an upstream repair
   proved against the recorded failure.

## Delivery 1: remove duplication and repair the existing tools

### Preserve benchmark failures

Change `tools/performance-snapshot.py::run_ref` and extend
`tools/test-performance-snapshot.py`.

Remove unconditional worktree deletion from `finally`. Clean up only after a
confirmed successful child run. Keep a failed, cancelled, or exceptional run's
successfully created worktree, compiler, and generated output. A setup failure
before worktree creation leaves no compiler reproduction; clean its unused
temporary directory and report the setup failure separately.
Report the retained absolute path
alongside the existing run summary and failing step. Reuse existing logs and
receipts; add no failure archive or retention database.

Align the existing nightly automation's cleanup wording with this behavior.
Inspect its saved prompt first; update that automation rather than create
another. Successful runs keep their current cleanup. Failed trees remain
until investigated and explicitly cleaned up.

Extend the existing performance report rather than add a new report format.
Remove the first-success early return that hides absolute measurements.
Include workload and units with the existing previous/current values. Identify
partial translation, native compilation, full-build time, CPU time, and CPU
instruction counts separately when those measurements exist. A ratio never
substitutes for an unmeasured workload.

### Repair metrics discovery and parsing

Change `tools/harness-metrics.py`.

- Remove the hard-coded project skill set. Read names from current skill
  frontmatter.
- Remove the filename-start-date exclusion. Select activity by record
  timestamp across live logs, archives, and nested worker logs.
- Parse current final-message records and supported older records. Suppress
  duplicate event/message representations of the same reply.
- Keep the original session metadata when later records replay another
  session's history. Merge available live/archive records by full session
  identity and deduplicate represented events; do not discard complementary
  history merely because two files have the same session ID.
- Extend existing `--since`/`--until` to accept timezone-aware timestamps
  for an exact half-open interval. Preserve inclusive UTC calendar-date
  behavior for existing date-only invocations. Normalize timestamps to UTC.
- Report corpus coverage and unavailable fields separately for each platform.
  Preserve invocation counts as invocations, not executed checks or waste.

Keep raw content private. Use small synthetic or redacted record fixtures for
parser checks. These checks remain focused tool tests, not a new build gate.
Retain the historical word-count metric as descriptive evidence; it is not
a communication target or a verdict on reply quality.

### Shorten existing guidance

Edit the existing files, without creating another workflow guide:

| Location | Remove or replace | Behavior retained |
|---|---|---|
| `agents/skills/orchestrate-x2c-work/SKILL.md` | Copied generic proof lists and launch overrides; unclear dependence on current checkout | Resolve the requested remote ref once, pass its full SHA, specify named focused checks, and collect private handoffs. |
| `agents/skills/beautify-x2c-source/SKILL.md` | Unconditional per-file repetition when one coherent worker change covers several files | Existing behavior-preserving comparison and checks for the actual changed behavior. |
| `.claude/output-styles/x2c.md` | Duplicated writing-style and technical-reporting prose already owned by global user guidance/root guidance | Autonomy, permission handling, and skill routing that this platform still needs. |
| Root guidance and task skills | Conflicting assurances or duplicated rules found during implementation | Existing scope, design succession, correction-stop, source review, and publication ownership. |

Do not edit Gary's global communication instructions. Do not replace existing
scope and correction rules with additional slogans. Check the complete diff
and fresh-session behavior before removing platform-specific autonomy text.

For a requested `origin/dev` base, pass that ref or its resolved SHA to the
existing worktree creation interface. Never switch an unrelated local `dev`
checkout or accept an implicit remote-default-branch selection. Reuse the
existing starting revision and `role`/`delivery` context; add no context registry.

## Delivery 2: prove the smallest messaging transport, then connect it

### Candidate decision

[Postbag](https://github.com/parasxos/postbag/tree/v2.3.0) exposes five MCP
tools and uses native session input without another daemon, polling loop,
or hooks. The installed Codex CLI exposes `codex queue`. These facts make
Postbag the preferred small pilot, rather than established infrastructure.

Its [native compatibility record](https://github.com/parasxos/postbag/blob/v2.3.0/docs/native-compatibility.md)
documents two-way macOS exchanges on disposable persisted sessions. It does
not verify Gary's existing Desktop daemon. Local CLI versions inspected during
planning were 0.160.0 and 2.1.266; the recorded peer test used 2.1.288. Verify
capabilities on installed versions before proposing an upgrade.

The [MCP contract](https://github.com/parasxos/postbag/blob/v2.3.0/docs/mcp.md)
distinguishes `not_submitted`, `submitted`, and `unknown`. Submission is not
recipient acceptance or action. Native submission precedes ledger recording,
so missing history cannot prove non-delivery. Names can be taken over by a
new join; the public interface does not enforce an immutable recipient ID.

Alternatives reviewed:

| Candidate | Relevant property | Decision |
|---|---|---|
| [agent-loom](https://github.com/osteele/agent-loom), formerly agent-mail | Durable mail; Codex receives through pull/reminder mechanisms | Reserve for a deliberate asynchronous-mail choice. It does not establish immediate idle-session wakeup here. |
| [cross-agent-teams-mcp](https://github.com/jtianling/cross-agent-teams-mcp) | Mailbox and wake support | Do not replace the Desktop launch path/configuration to add correspondence. |
| [cross-agent_mcp](https://github.com/whooperlove/cross-agent_mcp) | Existing-session messaging | Do not adopt editor executable shims and development settings that can break on updates. |
| [mcp_agent_mail](https://github.com/Dicklesworthstone/mcp_agent_mail) | Broad durable coordination service | Its larger surface is unnecessary for this first transport. Reconsider only if the small transport fails a required condition. |

The plugin catalog search found hosted AgentMail email inboxes, not proof of
delivery into existing coding sessions. Do not confuse that service with the
local MCP candidates or install it for this purpose.

### Pilot acceptance

Install the pinned candidate only for a controlled pilot after this plan is
approved. Use temporary client configuration and disposable persisted sessions
first. Then exercise explicitly designated Desktop and terminal test sessions
on this host, preserving their permissions and normal launch path.

Verify:

- An idle recipient starts a turn and replies in both directions, with its
  existing context and working directory.
- Busy recipients receive the request without starting overlapping edits.
- Two authors in different worktrees receive only their intended requests.
- Leaving, process restart, stale registration, and name takeover are visible;
  an old route cannot silently authorize a different task.
- Clearing or switching the recipient conversation does not authorize repair
  under an unrelated task. Withdraw the old contact when its scope ends.
- `unknown` submission never produces an automatic duplicate send. A received
  duplicate event does not cause a second repair.
- A blocker reply and final acknowledgement end the exchange without an
  automatic reply loop.
- Messages preserve peer provenance and existing human authorization. Tokens
  remain in the plugin's private store, outside PRs, logs, and source.

Use unique, never-reused bag/peer names for each author enrollment, within the
plugin's 16-character name limit. A recipient confirms repository, PR, head,
and assigned worktree before editing. A restarted author establishes a new
contact explicitly. These conventions reduce accidental routing errors; they
are not a claim that the broker enforces immutable destination identity.

Adopt only if the actual idle Desktop/terminal repair exchange passes. If it
fails, retain the observed failure, remove pilot configuration, and decide the
smallest demonstrated correction. Do not hide the failure behind a new app
server, executable shim, broad upgrade, or an untested custom broker.
Terminal-only success does not satisfy the pilot. Leave contact metadata
unimplemented unless delivery into the existing Desktop launch path succeeds.

### Reuse the PR handoff

After the pilot passes, change `tools/integrate-dev.py`,
`tools/test-integrate-dev.py`, the integration skill, and the existing
quick-start submission instructions.

Add optional `--contact-file` to `submit`. Its JSON value is:

```json
{"transport":"postbag","bag":"<unique bag>","peer":"<unique author name>"}
```

Store `contact` in the existing version-1 submission block. Older blocks with
no contact remain valid. Do not put a native inbox socket, authentication
token, provider credential, or session link in the PR. Do not expand
`debug/agent-context.json`; its role and delivery fields continue to protect
publication.

Keep contact validation limited to usable transport/address fields. The
coordinator already establishes PR eligibility, submitted head, dependencies,
and focused evidence; do not reimplement those checks in a messaging helper.

On an author-owned blocker:

1. Preserve the failing candidate and park it through the existing command.
2. Read the existing reason, pinned PR head, and contact. If the head has
   changed, process the new submission through the existing lifecycle first.
3. Send one addressed request through the MCP tool. Include repository, PR,
   pinned head, batch ID, concrete blocker, exact focused reproduction and log
   location, and the requested repair. For a remote recipient, provide the
   command and relevant evidence; a local path alone is insufficient.
4. The author responds with a repair revision and focused evidence, a verified
   disagreement, or a precise reason it cannot act. The repair stays within
   submitted intent and uses the normal resubmission path.
5. The integrator verifies that handoff and follows the existing head/readiness
   rules. A reply or send receipt never releases the hold or validates the PR.

Use the existing batch ID, PR number, head, and request kind as the event key
in correspondence. Reference it in replies and before any deliberate resend.
Reuse the plugin history for correspondence; do not add a delivery database,
retry scheduler, or repair-status machine. An unknown result requires reading
the history and obtaining recipient evidence before resending.

If the contact is missing or the recipient is unavailable, keep the candidate
parked, report the exact unresolved route/blocker, and continue independent
work unless Gary has prioritized that blocked change. Do not select the most
recent session, resume arbitrary saved history, or use queue order as design
authority.

Replace the integration skill's claim that messaging is unnecessary and its
generic delegated-worker paragraph with this shared boundary procedure.
The orchestrator still uses native worker messages. Authors and integrators
actively discuss overlapping files, design succession, and required repairs;
they do not silently edit each other's worktrees.

Messages are peer work requests within Gary's approved collaboration scope.
They do not enlarge scope, override a review stop, or grant new publication
authority. Use a substantive blocker reply as evidence of engagement; do not
add acknowledgement chatter to every message.

## Delivery 3: close the externally owned gaps

The repository contains no implementation for the observed terminal handoff
enforcer, provider isolation classifier, or Desktop permission-toggle state.
New repository prose cannot complete these repairs.

| Gap | Required removal or correction | Verification |
|---|---|---|
| Impossible terminal handoff | Remove mandatory calls to unavailable tools; select the existing supported report path | Non-auto worker completes once and the coordinator receives its report. |
| Isolation false positives | Remove classification of paths/heredoc text as Git invocations; keep actual worktree isolation | Replay the harmless scaling command and a real cross-worktree write attempt. |
| Permission synchronization | Propagate the effective mode to active sessions/workers; remove repeated stale escalation cycles | Toggle the mode and observe actual parent/worker tool behavior, not an assurance. |

Locate configurable enforcement and its owner during implementation. Where a
supported setting removes the redundant mechanism, use it without weakening
actual isolation. Where source is unavailable, prepare a minimal redacted
issue/reproduction for Gary to forward. Do not send an external issue without
authorization. Mark the gap unresolved until a supported version or setting
passes the original scenario.

Cross-platform mail mitigates missing coordination; it does not by itself
repair these runtime defects.

## Verification, cost, and delivery

Extend existing snapshot and integration tests. Run a focused, one-off metrics
fixture suite and representative fresh-session comparisons. Reuse the captured
long-history correction cases for design precedence and semantic claims; a
short fresh prompt cannot prove those conditions.

Check a behavior-preserving refactor, a real runtime change, an explicitly
requested full-corpus task, and a 3-5-file prototype. The refactor uses focused
proof; the integration owner gates once. The sample remains bounded. Proposed
semantics remain distinct from observed output, and change assurances follow
diff inspection.

Measure agent-facing text before and after. The guidance changes should remove
more prose than they add. This measure reports simplification; it is not a new
readiness requirement. Added transport cost is the five-tool MCP integration
and optional contact, replacing cross-platform manual relay and copied
handoff instructions. Do not adopt the candidate's unrelated workflow features.

Review the authored diff, integrate current origin/dev, and use the existing
publication gate once per coherent code/tool batch. Documentation-only edits
use the existing doc-check rule. Keep all broad targets and optional checks
unchanged. Report repository delivery, messaging adoption, and external repairs
separately; do not declare the whole plan complete with external gaps open.

## Implementation evidence, 2026-10-05

The repository repairs are implemented. Publication uses the existing gate.
The existing nightly automation now retains failed or uncertain clones.
Snapshot checks cover real disposable worktrees, failure, signals, exceptions,
setup failure, successful cleanup, absolute measurements, and metric identity.
Nineteen snapshot tests, sixteen metrics fixtures, and forty-two offline
integration tests pass. None was added to a recurring gate.

The repaired metrics scan uses the original half-open audit window,
2026-09-28T07:00:00Z through 2026-10-05T14:46:21Z. Full recursive discovery finds 390 active Desktop identities and 283 active
terminal identities for x2c. Forked parent records can carry rewritten
timestamps; recorded task-start boundaries now exclude those replays. The
validated aggregate records discovery, deduplication, and field coverage. These are transcript identities, not
independent tasks or a quality score. Successful execution, wasted time, and
arbitrary shell edits remain unavailable fields.

Postbag 2.3.0 is installed in a dedicated host environment and registered in
both hosts. Its installed core and MCP module hashes match the reviewed
release. Two disposable Desktop sessions and terminal sessions exercised the
normal native queue and inbox, without a delivery daemon or executable shim.
The initial request woke idle Desktop, created the synthetic repair, and sent
an observed reply into idle terminal. Fresh Desktop MCP discovery and delivery
also passed. A duplicate received during an active turn preserved the repair
file's bytes and modification time. An unrelated-task request was rejected.
A withdrawn contact refused delivery. A stopped terminal process returned
`transport_unavailable` and `not_submitted`; no retry occurred. Explicit name
takeover reported the previous holder. Restart used a new contact. Native
`/clear` changed the conversation while the registration survived; the
recipient rejected repository work without current human authorization.
Final letters produced no reply in the observed exchange.

These checks establish the tested host path, not general reliability or a
security boundary. An actual `unknown` transport outcome was not forced.
The two author scopes used separate disposable task directories, rather than
real PR worktrees. A peer request cannot expand their native permissions.
The restart probe sent one unnecessary readiness letter; prompt compliance
and loop prevention remain model behavior, not broker enforcement.

The guidance diff removes 76 lines and adds 53 lines across the five affected
agent-facing files. Eleven fresh short planning sessions compared the affected
answers. A discovered per-file build interpretation was corrected and the
focused recheck used one sequence for the coherent change. Both style variants
still produced unsupported performance claims in some probes. No improvement
in long-history correction handling is claimed.

Two publication attempts exposed an existing harness defect: Make exported
its help-rendering Python script into every child process. The extra environment
payload caused `var-chain-stack` to fail under its requested 256 KiB stack.
A focused nested-Make probe reproduced the failure; removing only that variable
made it pass. The export now belongs only to `help`. Six repeated nested-Make
probes passed, and `make help` output matches the original byte for byte.
The stack limit and checked-in expectations remain unchanged. Failed gate
logs and focused results are retained.

The three external runtime defects remain unresolved. No supported editable
owner was found for handoff enforcement, isolation classification, or active
permission synchronization. Redacted reproduction notes and acceptance cases
are preserved in the tracked evidence record. No binary was patched, protection weakened,
or external issue posted. The plan remains active for these external repairs.

## Plan review

- The selected transport infers caller provenance from native metadata/inbox
  inputs; the pilot must verify that inference on these sessions. Effective
  runtime permissions are distinct from a user's expected mode. The
  coordinator establishes PR heads, readiness, dependencies, and publication
  proof. Consumers reuse those facts. Postbag does not establish recipient
  acceptance, immutable names, or action; the design does not claim otherwise.
- Delete unconditional failed-run cleanup, the hard-coded skill catalog,
  filename-date filtering, first-run measurement suppression, and competing
  instruction copies. Reuse current summaries, tests, PR metadata, candidate
  records, native messaging, and the existing gates.
- The only lasting new mechanism is a selected external transport and an
  optional PR contact. Both are necessary to reach an existing author on the
  other platform. There is no second queue, lease system, cache, daemon, or
  provider-specific publication state. No compiler/runtime representation
  changes are proposed; x2c source remains untouched.
- Contact validation rejects unusable address fields. Recipient scope checks
  protect against wrong-task edits; they do not make aliases immutable.
  Focused negative cases protect failed-state retention, stale/unknown
  delivery, and existing worktree isolation. No new compiler validator,
  dedicated language diagnostic,
  or recurring negative fixture is proposed. Parser tests cover observed
  telemetry omissions without creating another product gate.

## Continue from any checkout

Read this plan and the linked evidence record from current origin/dev. The
repository implementation is delivered; do not rerun it or recreate the pilot.
No action from Gary is required to preserve or deliver this handoff.

1. The next integrator and PR author can run the real messaging trial through
   the existing integration skill and optional submit --contact-file interface.
   The author joins with fresh Postbag names inside the assigned session.
   Use a real human-authorized PR and existing blocker; do not invent a defect.
   When a blocker exists, retain and park the candidate, send one scoped repair
   request, observe the substantive reply and resubmitted head, and follow
   ordinary review and publication. Record the outcome here. If no blocker
   exists, no repair trial is due. There is no new recurring requirement.
2. A runtime maintainer must replay reports 1 and 2 from the evidence record
   in the supported incident environment, or establish the current equivalent.
   Confirm the owner before submitting; no external issue has been posted.
   The original isolation command and a real disallowed cross-worktree Git
   write must both be tested. The reduced harmless input alone is insufficient.
3. Report 3 needs an optional joint experiment because an agent cannot change
   the app access setting for Gary. Use disposable parent/worker sessions and
   scratch writes; capture effective policy before and after Gary changes
   access through the UI. Until arranged, mark the cause and repair unverified.

The live GitHub check on 2026-10-05 found no open PRs targeting dev. The
persistent integrator queue had no active batch or ready submission. Historical
parked batches are preserved; that history does not authorize reopening closed
PRs. A future agent checks current queue state rather than trusting this snapshot.

Host messaging registration survives removal of this worktree. Pilot contacts
are withdrawn and sessions archived. Private evidence is preserved outside the
worktree as described in the evidence record. After this documentation is
published and remote ancestry verified, this worktree holds no unique required
handoff. Remove it through the normal managed-worktree interface when desired;
check for subsequent work before deletion.
