# Private async performance and regression validation - 2026-10-31

Status: functional and memory checks completed; clean performance comparison
is incomplete. The existing full check target fails on two integration
issues described below. No performance tradeoff is accepted by this report.
No pushes or dev/main integration are authorized.

## Comparison and method

The full pre-async baseline is
`1355503543801f6565150a00c779668ab1d2d1bb`. The candidate is
`552465165`, including the agreed lifetime-analysis boundary. The earlier
`142a3496b` owner-state checkpoint does not measure the complete async change.

Both revisions were checked out separately beneath
`/tmp/x2c-async-validation-20261031/`. Each ran `make build-safe`,
`make bootstrap-refresh`, then `make build-safe`. Both compilers report a
valid prelude and an empty prelude_missing. Generated bootstrap differences
and compiler/archive hashes are retained with the evidence. The authored
candidate source stayed unchanged.

Host: macOS 15.7.9 arm64, Apple clang 17.0.0, 16 KiB pages. Runtime probes
use `-O2 -fsigned-char -pthread`, no LTO, and allocation accounting disabled.
Scope accounting is measured separately with accounting enabled. File timing
uses the same disabled-accounting setting; its allocation counters are not
interpreted as allocation measurements.

Five independent processes per revision and workload alternate baseline and
candidate order. `/usr/bin/time -l` records retired instructions, CPU, and
RSS separately from each benchmark's own timing and counter output. The
seven representative compiler input files are byte-identical between trees.

Other worktrees began sustained benchmark and build workloads during this
pass. The initial measurements are exploratory. Guarded repeats stopped
when unrelated load returned. Clean translation, build-cost, and timing
comparisons remain pending a quiet window. No elapsed-time conclusions are
drawn from contaminated runs.

## Synchronous cost: exploratory instruction counts

These are observed medians from the initial run, in millions of retired
instructions for the entire process. They are not nanoseconds per operation
or confirmed clean-window regressions.

| Workload | Baseline M instructions | Candidate M instructions | Change |
| --- | ---: | ---: | ---: |
| Existing Scope hot paths | 2,521.917 | 2,510.090 | -0.47% |
| Scope hot paths, accounting enabled | 2,633.667 | 2,622.913 | -0.41% |
| 10 million Scope.top calls | 443.740 | 464.152 | +4.60% |
| 1 million double-open/double-close cycles | 1,776.758 | 1,767.234 | -0.54% |
| 100,000 regions, each destroying 16 allocations | 1,771.701 | 1,768.672 | -0.17% |
| 1 million malloc/realloc/free cycles | 1,914.221 | 1,930.798 | +0.87% |
| 100,000 Context open/close cycles | 1,153.165 | 1,154.413 | +0.11% |
| 100,000 preconstructed Lisp evaluator entries | 461.307 | 462.358 | +0.23% |
| 1 million buffered Channel send/receive pairs | 1,030.815 | 1,109.218 | +7.61% |
| Block and Buffer benchmark | 355.759 | 362.646 | +1.94% |
| Scanner benchmark | 3,100.230 | 3,100.212 | -0.00% |
| String benchmark | 2,225.268 | 2,220.689 | -0.21% |
| List benchmark | 973.197 | 970.172 | -0.31% |
| File benchmark | 346.743 | 347.855 | +0.32% |
| Logger benchmark | 357.779 | 357.714 | -0.02% |
| Iterator benchmark | 5,760.815 | 5,744.022 | -0.29% |
| Exception benchmark | 84,033.683 | 83,760.404 | -0.33% |
| Var benchmark | 9,328.319 | 9,328.660 | +0.00% |
| Var operator benchmark | 10,291.659 | 10,291.154 | -0.00% |
| Match capture benchmark | 7,466.808 | 7,402.412 | -0.86% |
| Native request/reply, 1 client | 146.680 | 147.914 | +0.84% |
| Native request/reply, 8 clients | 642.580 | 649.495 | +1.08% |
| Native request/reply, 64 clients | 5,134.001 | 5,180.045 | +0.90% |

The existing Scope benchmark includes one million operations in each of its
first five lanes and 200,000 List-cons misses. Its process count includes
startup and cleanup. The broader probes supplement it with root-slot access,
nested regions, populated destruction, and realloc.

The native request/reply rows use 4,096 exchanges per client and check the
result sum. They include process startup, native thread startup, service
execution, and shutdown, using the full pre-async baseline.

The clearest cost candidates are Scope.top and uncontended native Channels.
The first difference is about 2.04 instructions per Scope.top call. The
second is about 78.4 instructions per send/receive pair. Both need clean
same-host confirmation before an acceptance decision.

Source review identifies the relevant changes:

- Scope's `_thread` adds a base_slot load/check. Ordinary allocation still
  uses the installed active slot directly; it does not call `_thread`.
- Native Channel operations read the current task token and notifications
  test the task-waiter list. Native rendezvous records now live on the caller
  stack instead of in one native TLS record.
- Lisp outer entry reads the installed task stack bound before falling back
  to pthread stack discovery.
- Context, Error, Exception, and Match backing exchanges run at task
  boundaries. Their existence does not establish an ordinary-path cost.

The exploratory run does not establish a general allocation-path regression
or prove that synchronous execution has no cost. Small differences in other
lanes remain unclassified.

## Program footprint

These are file bytes for the probe executables, built with the same flags:

| Program | Baseline bytes | Candidate bytes | Difference |
| --- | ---: | ---: | ---: |
| Empty program | 474,232 | 475,640 | 1,408 |
| Native request/reply program | 522,000 | 526,848 | 4,848 |
| Combined synchronous probe | 1,053,816 | 1,058,696 | 4,880 |

The compiler's Mach-O text segment grows from 3,063,808 to 3,080,192 bytes
(16 KiB). Its TLS zero-fill section is 384 bytes in both revisions; TLS
descriptor storage grows from 360 to 456 bytes. The old Channel TLS waiter
was removed, so counting only newly added TLS fields would overstate growth.
Mach-O PAGEZERO reservation is not resident memory or executable file size.

## Task stack reservation, residency, and cleanup

Each process creates N blocked waiters and one observer task. The observer
runs last, after all waiters park, and holds the process for external RSS
and virtual-size snapshots. Three processes per row are reported as median
increases over that same process before Task.run.

| Usable stack per job | Blocked waiters | Jobs | Usable stacks MiB | Parked VM increase MiB | Parked RSS increase MiB | Post-batch VM increase MiB | Post-batch RSS increase MiB |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8 MiB | 0 | 1 | 8.000 | 8.016 | 0.047 | 0.000 | 0.031 |
| 8 MiB | 64 | 65 | 520.000 | 521.016 | 1.281 | 0.000 | 0.281 |
| 8 MiB | 1,024 | 1,025 | 8,200.000 | 8,346.016 | 19.859 | 130.000 | 3.875 |
| 64 KiB | 0 | 1 | 0.063 | 0.078 | 0.047 | 0.000 | 0.031 |
| 64 KiB | 64 | 65 | 4.063 | 5.078 | 1.281 | 0.000 | 0.281 |
| 64 KiB | 1,024 | 1,025 | 64.063 | 210.078 | 19.859 | 130.000 | 3.875 |

The post-batch VM reduction equals all task stack mappings, including one
16 KiB guard per job. The large process still retains 130 MiB of non-stack
virtual reservation and 3.875 MiB of added RSS. This report does not classify
those remaining mappings or accept that retention cost. Reserving a smaller
usable stack does not reduce the shallow parked workload's touched pages.

Scope accounting after the batch has a fixed first-use increase of six
allocations and 712 requested bytes for every tested job count. A separate
probe warms Task.run once, then executes 1,000 further batches. Live Scope
accounting remains exactly 83 allocations and 29,656 requested bytes across
those repetitions. This is not a general leak proof for raw allocations.

## Regression checks

The following checks passed on the isolated candidate:

- Full ordinary suite: 1,148 tests, 99,489 assertions.
- Full freshly instrumented ASan/UBSan suite: 1,148 tests, 99,489 assertions.
  Leak detection remains disabled as in the existing runner.
- Instrumented task suite with stack-use-after-return detection: 13 tests,
  57 assertions.
- Full compiler fixtures: 1,355 fixtures and 2,994 artifacts, plus the
  existing boundary and meta probes reached by `make verify`.
- Thirty repetitions of the task suite, alternating default and minimum
  stack capacities, all passed.
- Task suite and task-local Lisp probes at the default 8 MiB, 1 MiB, 64 KiB,
  minimum 32 KiB, and page-rounded 65,537-byte capacities all passed.
  Lisp evaluates ordinary calls and 10,000 tail calls, then catches the
  expected call-stack Error from unbounded non-tail recursion.
- Invalid capacities 1, -1, abc, and UINT64_MAX report the selected bad-arg.
- Bootstrap recovery, the stage comparisons reached by precommit,
  documentation checks, documentation output checks, and artifact atomicity.
- The native adapter compiles to a macOS x86_64 object. This is compile
  evidence only, not x86_64 execution evidence.

### Existing full check target: failed

`make agent-pr-check` fails on the candidate. All five component checks
finished; doc-check, verify, and doc-outputs passed. Two components failed:

1. `proof-cold-collection`: stage 1 contains the copied native files
   lib/task-native.c and lib/minicoro.h, but the cold scratch translation
   does not copy them. The file-set comparison stops there. The pre-async
   baseline passes the unchanged check. A temporary diagnostic reproduction
   that includes the same two native source copies compares all 475 C/H/.xi
   files successfully. The checked-in check was not weakened or changed.
2. `commands-check`: lint exceeds the existing baseline with four new
   findings: restates-name at lib/task.x lines 148 and 293,
   wrapped-opening-line at lib/task.x line 265, and stacked-doc at
   lib/thread.x line 64. The baseline's own lint command and tests pass.

The gate-state wrapper declined to issue a receipt for private delivery, so
the existing Make target was run directly without changing delivery mode.
There is no successful publication receipt. These failures require a small
local integration follow-up; no source fixes were included in this validation
pass.

## Evidence and remaining work

Local evidence is retained in `.context/async-validation-20261031/`: raw
per-process output, interrupted pilot and guarded runs, probe preparation and
measurement scripts, instruction summaries, memory snapshots, provenance,
and full check logs. Native probe source remains in
`/tmp/x2c-async-validation-20261031/probes/`. Isolated trees are retained.

Remaining performance work is the clean alternating runtime comparison,
representative translation, and existing normalized build-cost measurement.
The temporary harness resumes completed sample pairs rather than restarting
the entire campaign. The earlier request/reply performance report remains
Channel-only and does not establish native network or timer performance.

Linux arm64/x86_64 execution, macOS x86_64 execution, TSan, and wider hardware
and hardening configurations remain unvalidated. No new recurring gate was
added. The dev/main and push hold remains in force.
