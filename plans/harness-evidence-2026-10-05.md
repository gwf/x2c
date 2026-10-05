# Harness audit evidence and remaining runtime work

> Status: reference
> Recorded 2026-10-05. Repository corrections were published to dev at
> 3459d664e6b0393eebec5d07aeb3e24972b88dbd. This record preserves the
> observed failures, validation, and unresolved runtime reproductions.
> It is sufficient to continue without the original worktree or session.

## Evidence boundary

The audit window is [2026-09-28T07:00:00Z, 2026-10-05T14:46:21Z).
The repaired recursive parser found 390 active Desktop transcript identities
and 283 active terminal identities for x2c. These are not independent tasks.
It counted 49,538 versus 39,524 tool requests and 1,852 versus 960 final
replies, respectively. Counts establish corpus coverage, not time wasted,
execution success, or an agent quality ranking.

The observations below came from actual requests, tool results, and user
corrections. Raw transcripts remain private because they can contain unrelated
work and sensitive content. Redacted behavior and exact diagnostic identifiers
are preserved here. Workspace-specific transcript links are not required to
understand or resume the work.

## Observed failures and delivered corrections

| Observed failure | Correction or remaining limit |
| --- | --- |
| Twenty prohibited terminal handback calls across five workers; one loop delayed a completed report about 88 seconds. | External runtime report below. Repository orchestration already uses ordinary private handoffs. |
| A shell command with paths containing Git and heredoc text, but no executable Git invocation, was rejected by worktree isolation. | External runtime report below. 911 matching refusals across 168 files do not mean 911 proven false positives. |
| Nightly benchmark failures were followed by deleting the failed clone. | Snapshot cleanup now preserves failed/cancelled/uncertain worktrees and reports paths. Existing automation updated. |
| Worktree creation used an implicit remote default despite an explicit starting ref. | Orchestration resolves the requested ref to a full SHA and passes that SHA. |
| Copied proof lists and ambiguous per-file checks encouraged repeated validation. | Removed generic proof lists; coherent worker changes use focused checks and one publication owner. |
| First successful performance report hid absolute values. | Reports include workload, absolute values and units; incompatible identities are not compared. |
| Filename-date filtering, hard-coded skills, old reply parsing and replayed histories distorted metrics. | Recursive activity selection, current skill catalog, current/legacy reply parsing, identity merging and explicit replay-boundary exclusion. |
| Competing writing guidance duplicated the user's communication instructions. | Removed duplicated style sections. Fresh-session tests do not establish improved long-history correction behavior. |
| User reported full access while tools still denied an index lock. | External runtime report below. Effective policy and UI timing were not captured. |
| Publication failed var-chain-stack under its requested 256 KiB stack. | Make help Python text was exported to every child. Restricting export to help passed six comparable nested-Make probes; help output stayed byte-identical. |

The original audit also found unsupported semantics/performance assurances
and poor responses to corrections. Existing scope and correction rules already
address those behaviors. No additional slogans were added, and no causal
improvement in those behaviors is claimed.

## Validation and delivery

Nineteen snapshot tests, sixteen metrics fixtures and forty-two offline
integration tests passed. The final existing agent-pr-check passed, including
verify, documentation, cold-collection proof and external command checks.
No new recurring gate was added. Five affected agent-facing files removed
76 lines and added 53 lines. Eleven fresh short planning sessions compared
relevant answers. Both writing-style variants still made unsupported performance
claims in some probes; the record does not claim those failures are solved.

## Messaging installation and observed limits

Postbag 2.3.0 and MCP SDK 2.3.0 were installed in an isolated host environment:
`~/.local/share/x2c-harness/postbag-2.3.0`. Both native clients register the
same stdio `postbag-mcp` executable. This host installation is outside the
repository and does not depend on the original worktree. Another machine
needs its own installation and native client registration.

The reviewed release is [Postbag v2.3.0](https://github.com/parasxos/postbag/tree/v2.3.0).
Installed core SHA-256:
`2f5cbf04d0b6e05a308466c8e45857482050406f05257400931347d285152f5c`.
Installed MCP module SHA-256:
`f35766d4053051203048f301bee2bc7f2b76fd1864c940f1add09c3390133f25`.

Disposable persisted sessions exercised idle wakeup, a synthetic repair,
substantive replies in both directions, duplicate delivery during active work,
withdrawal, a stopped recipient, name takeover, restart with a fresh contact,
and native conversation clear. Wrong-task and unauthorized repository-edit
requests were rejected. The duplicate did not change the repaired file again.
Final letters did not create reply loops in the observed exchange.

An actual unknown submission outcome was not forced. The author scopes used
separate disposable directories, not real PR worktrees. Scope checks and loop
prevention remain model behavior; the transport is not a security boundary.
A restart probe sent an unnecessary readiness letter. All pilot contacts were
withdrawn, terminal pilot processes stopped, and disposable Desktop chats
archived. Continuing does not require reactivating those chats.

## External runtime reports

Reports below are ready to forward to a supported runtime owner. None was
submitted. Incident behavior is observed; current-version reproduction and
repairs remain unverified. A report is not evidence that a defect is fixed.

Host inventory captured 2026-10-05T16:42:04Z: Desktop 26.930.31730, build
12947; native CLI 0.160.0; terminal executable resolves to version 2.1.289.
Retained terminal versions are 2.1.240, 2.1.259, 2.1.266 and 2.1.289.
The handback incident identifies 2.1.286, which is not retained.
A changed installed version does not establish a correction.

Repository settings and user settings contain no implementation of the
handback enforcer or isolation classifier. Isolation diagnostic strings were
found in retained native binaries, but no supported editable source or setting
was identified. The handback enforcer's exact owner remains unknown. No
supported setting for active permission synchronization was found. Do not
patch binaries or weaken isolation/approval to make these tests pass.


### Report 1: impossible handback in non-auto mode

Observed sequence in a non-auto worker:

1. Worker calls SubagentHandback with its completed report.
2. Runtime rejects the tool with:
   "Only the auto-mode classifier can allow SubagentHandback: the session is not in auto mode"
3. Worker writes the report as plain text.
4. Enforcer injects:
   "[handback-send-enforce] Your report has not been delivered. Call SubagentHandback({message: <your full report>}) now; the call ends your run."
5. The repeated required call fails with the same mode denial.
6. A later reminder permits plain text and the report arrives.

Minimal supported-owner test: launch one disposable non-auto worker, give
it a trivial report task, and require completion once. Assert that the
coordinator receives that report without a rejected mandatory terminal call.
Repeat in auto mode. Preserve the report when selecting another delivery path.

Smallest correction: remove mandatory terminal calls when that capability is
unavailable in the worker's effective mode. Use the existing supported report
path. Do not relax classifier-only permission semantics to satisfy the enforcer.


### Report 2: isolation rejection without Git execution

Observed submitted Bash command performs fixture copying, writes a shell
script through a heredoc, and runs compiler translations three times. Its
path strings include /Users/<user>/Git/<repo>/... . There is no executable
git invocation. The tool returned:

"This agent is isolated in the worktree <worker-worktree>, but this command names git in a form too complex to verify that it stays inside the worktree. Refusing to run it - a worktree-isolated agent's git operations must target its own worktree. Split it into plain, separate commands and run them from <worker-worktree>."

The punctuation above is normalized to ASCII and private paths are redacted.

Recorded rejected command, with only private directory values replaced.
It is historical evidence, not a command to run in a live repository. The
fixture names and shell structure are retained. Prepare disposable input
files and replace TREE with the assigned disposable worker before replay.

```sh
Q=/private/tmp/worker-runtime/Git/example/scratchpad/qdesign; P=/private/tmp/worker-runtime/Git/example/scratchpad/ph3; cp $Q/limit9000.x $Q/rawlimit9000.x $Q/quote1000.x $Q/quote2000.x $Q/raw1000.x $Q/raw2000.x $Q/limit12000.x $Q/rawlimit12000.x $Q/gen.py $P/; cat > $P/run.sh <<'EOF'
#!/bin/sh
# usage: run.sh TREE NAME...   translates P/NAME.x with TREE's compiler; prints wall seconds
X=$1; shift
P=$(cd "$(dirname "$0")" && pwd)
cd "$X" || exit 1
for n in "$@"; do
  mkdir -p "$P/out/$n"
  /usr/bin/time -p ./builds/0/x2c translate -I lib --out-dir "$P/out/$n" "$P/$n.x" 2>&1 >/dev/null | awk -v n=$n '/^real/{printf "%s %s\n", n, $2} /error/{print n, $0}'
done
EOF
chmod +x $P/run.sh; W=/Users/<user>/Git/<repo>/.worktrees/worker; for r in 1 2 3; do $P/run.sh $W limit9000 rawlimit9000 quote1000 raw1000 quote2000 raw2000; done
```

Small inert input for an owner to submit in a disposable isolated worker:

```sh
P=/tmp/isolation-probe
W=/tmp/Git/example/.worktrees/worker
mkdir -p "$P"
cat > "$P/run.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$1"
EOF
sh "$P/run.sh" "$W"
```

This is a reduced candidate, not a reproduced rejection. The owner must also
replay the original audited command with disposable compiler fixtures,
retaining its command structure and paths. Splitting the original command
into separate calls succeeded, which does not explain the classifier's cause.

Smallest correction: classify actual executable Git invocations and their
working directories. Do not classify ordinary path components or heredoc
data as Git execution. Keep actual cross-worktree Git write protection.

Acceptance must include this harmless command and an actual disallowed Git
write aimed outside the worker's worktree. The latter must remain blocked.
No live or existing repository is an appropriate write target for that test.


### Report 3: effective permission state mismatch

Observed sequence, October 1:

1. User states that full access has already been enabled.
2. A subsequent tool invocation still fails to create a Git index.lock with
   "Operation not permitted".
3. Agent requests require_escalated again.
4. User repeats the full-access correction.
5. A later environment update finally describes permission_profile=disabled
   and file_system=unrestricted.

The transcript does not expose when the UI toggle occurred, which runtime
policy each failed call used, or whether the agent had received a refreshed
policy. Do not claim a proven app toggle race or a particular internal cause.

Supported-owner test: use an inert scratch directory and disposable parent
and worker sessions. Capture effective permission policy at each tool call,
toggle through the supported UI, and repeat the same harmless scratch-file
write. Verify the effective runtime state and refreshed instructions reach
both sessions. Observe actual tool behavior; a user's statement or agent
assurance does not prove that the runtime applied the policy.

Smallest correction, if the owner confirms stale state: propagate the existing
permission mode update to active sessions/workers and expose effective mode
on denials. Remove repeated stale escalation cycles. Do not globally disable
approval or enlarge tool access to bypass a synchronization defect.


## Private evidence retention

A private copy of workspace context, implementation/gate logs and pilot
research is preserved on the original host at
`~/.local/share/x2c-harness/evidence/2026-10-05/`. Directory permissions are
0700 and file permissions are 0600. Raw provider session logs retain their
normal host storage. The tracked observations and reproduction requirements
above are the continuation contract; the private archive is supporting detail,
not a prerequisite for another checkout to resume.
