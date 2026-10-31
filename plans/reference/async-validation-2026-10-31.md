# Private async performance and regression validation - 2026-10-31

Status: the local paired performance, build-cost, functional, and memory
checks are complete on macOS arm64. Allocation, comparable compiler
translation, and whole-build cost are close to baseline. Buffered native
Channels have a measured local cost. The existing full check target still
fails on two integration issues described below. No tradeoff is accepted by
this report. No pushes or dev/main integration are authorized.

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
pass. Initial measurements and interrupted attempts are retained separately.
The final data excludes attempts flagged for concurrent load. Gary authorized
coordination with the active chats; the remaining samples ran while those
chats deferred new heavy work. All holds were released after measurement.
Normal desktop activity remained. Retired instructions are the primary
work measure; small elapsed-time differences do not establish improvements.

### Compiler cache comparability correction

The first stage-zero compiler-source comparison appeared to require 22.59%
more instructions in the candidate. That comparison was invalid: both runtime
preludes were current, but the candidate's compiler-source interfaces were
foreign to its compiler. Source collection fell back to cold walks.

| Tree | Running compiler identity | Stage-zero compiler.xi identity | Stage-one compiler.xi identity |
| --- | --- | --- | --- |
| Baseline | 293be295a8e0ab04 | 293be295a8e0ab04 | 293be295a8e0ab04 |
| Candidate | c4bcd515bbdb6622 | 4cca433734d4f87a | c4bcd515bbdb6622 |

Sampling exposed the cold collection. The pre-analyzer prototype at
586d51146 had the same cache mismatch, so its apparent slowdown did not
attribute a cost to either the runtime or analyzer. Parsed-only comparisons
also carried this mismatch and are retained as diagnostic data, not valid
performance comparisons.

The correction uses stage one in both trees, with matching runtime and
compiler-source interfaces. Within each tree the stage-zero and stage-one
executables are byte-identical, including SHA-256. This changes the interface
search directory without changing executable code. The corrected comparison
is 19.031 billion baseline versus 18.987 billion candidate instructions,
not a 23% runtime regression. A valid runtime prelude alone was insufficient
to establish comparable cache state for compiler-source workloads.

## Synchronous cost: paired instruction counts

These are final medians of five processes per tree, in millions of retired
instructions for the entire process. They are not nanoseconds per operation.

| Workload | Baseline M instructions | Candidate M instructions | Change |
| --- | ---: | ---: | ---: |
| Existing Scope hot paths | 2,521.860 | 2,509.580 | -0.49% |
| Scope hot paths, accounting enabled | 2,635.147 | 2,622.623 | -0.48% |
| 10 million Scope.top calls | 444.211 | 464.237 | +4.51% |
| 1 million double-open/double-close cycles | 1,776.291 | 1,767.253 | -0.51% |
| 100,000 regions, each destroying 16 allocations | 1,771.900 | 1,768.538 | -0.19% |
| 1 million malloc/realloc/free cycles | 2,039.849 | 2,033.200 | -0.33% |
| 100,000 Context open/close cycles | 1,153.617 | 1,154.494 | +0.08% |
| 100,000 preconstructed Lisp evaluator entries | 461.465 | 462.443 | +0.21% |
| 1 million buffered Channel send/receive pairs | 1,030.876 | 1,109.348 | +7.61% |
| Block and Buffer benchmark | 356.794 | 363.718 | +1.94% |
| Scanner benchmark | 3,100.247 | 3,100.320 | +0.00% |
| String benchmark | 2,231.917 | 2,222.761 | -0.41% |
| List benchmark | 970.637 | 964.630 | -0.62% |
| File benchmark | 345.744 | 347.169 | +0.41% |
| Logger benchmark | 357.850 | 357.892 | +0.01% |
| Iterator benchmark | 5,761.699 | 5,734.127 | -0.48% |
| Exception benchmark | 84,059.464 | 83,927.561 | -0.16% |
| Var benchmark | 9,329.012 | 9,328.934 | -0.00% |
| Var operator benchmark | 10,292.886 | 10,292.675 | -0.00% |
| Match capture benchmark | 7,435.083 | 7,415.486 | -0.26% |
| Native request/reply, 1 client | 146.613 | 147.798 | +0.81% |
| Native request/reply, 8 clients | 643.667 | 647.518 | +0.60% |
| Native request/reply, 64 clients | 5,112.333 | 5,163.237 | +1.00% |

The existing Scope benchmark includes one million operations in each of its
first five lanes and 200,000 List-cons misses. Its process count includes
startup and cleanup. The broader probes supplement it with root-slot access,
nested regions, populated destruction, and realloc.

The native request/reply rows use 4,096 exchanges per client and check the
result sum. They include process startup, native thread startup, service
execution, and shutdown, using the full pre-async baseline.

The repeatable instruction increases are Scope.top and uncontended native
Channels. The first difference is about 2.00 instructions per Scope.top call.
The second is about 78.5 instructions per send/receive pair. Acceptance is
still Gary's decision; elapsed time must be considered separately.

Selected inner-loop timings use the benchmark's own clock, in ns/operation:

| Operation | Baseline ns/op | Candidate ns/op |
| --- | ---: | ---: |
| Scope malloc/free | 16.016 | 15.386 |
| Scope region open/close | 21.202 | 19.301 |
| Push/malloc/free/pop | 20.368 | 19.711 |
| Explicit-slot malloc/free | 15.325 | 15.167 |
| Scope.top | 1.931 | 1.688 |
| Buffered Channel send/receive pair | 36.957 | 39.344 |
| Context open/close | 356.440 | 376.500 |
| Lisp evaluator entry | 149.060 | 151.360 |

The Channel pair takes 2.387 ns more, or 6.46%, in this workload. Scope.top
retires more instructions but was not slower in these samples. Context and
Lisp timing changes exceed their much smaller instruction changes. These
short timings do not establish small general speedups or regressions.

Source review identifies the relevant changes:

- Scope's `_thread` adds a base_slot load/check. Ordinary allocation calls
  this inline helper and uses the installed active slot directly. It does
  not consult the task scheduler, but the extra check reaches allocation.
- Native Channel operations read the current task token and notifications
  test the task-waiter list. Native rendezvous records now live on the caller
  stack instead of in one native TLS record.
- Lisp outer entry reads the installed task stack bound before falling back
  to pthread stack discovery.
- Context, Error, Exception, and Match backing exchanges run at task
  boundaries. Their existence does not establish an ordinary-path cost.

The measured workloads do not show a general allocation-path regression.
They do not prove that synchronous execution has no cost. Small differences
in other lanes remain unclassified.

## Compiler translation and build cost

The seven-file batch is transform, emit, expressions, generate, parse, type,
and tokenizer, in one process with -j1. Stage-one interfaces are current in
both trees. Five samples per row alternate tree order.

| Workload | Baseline M instructions | Candidate M instructions | Baseline elapsed seconds | Candidate elapsed seconds |
| --- | ---: | ---: | ---: | ---: |
| Seven-file translation batch | 19,031.182 | 18,987.440 | 1.282649 | 1.267593 |
| Tiny translation | 1,131.802 | 1,141.759 | 0.083533 | 0.083272 |

The batch instruction difference is -0.23%; elapsed time differs by -1.17%.
The tiny translation uses 0.88% more instructions with similar elapsed time.
These results do not establish a general compiler speedup.

The existing tools/build-scaling.py target makes three sequential stage
builds per revision and reports median child-inclusive CPU seconds. It uses
fresh extracted source trees and the fixed translator from each revision,
so it does not reuse the asymmetric compiler-header cache above. Native
compilation is included; this is not translation-only time.

| Build metric | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| Median child-inclusive CPU seconds | 39.318143 | 38.871002 | -1.14% |
| Authored source lines | 98,381 | 98,896 | +0.52% |
| CPU microseconds per authored line | 399.652 | 393.049 | -1.65% |
| Existing build-cost score | 55.704 | 54.783 | -1.65% |

Both scores use metric child-cpu-seconds-per-authored-line/v1 and baseline
ID child-cpu-seconds-per-authored-line/v1:639c9cad5943. The existing target
reports a median, not its individual three CPU samples. The result shows no
whole-build CPU regression in this comparison; it does not accept every
possible workload or small timing difference.

## Request/reply execution comparison

Each client performs 4,096 integer exchanges; the result sum is checked.
CPU and wall clocks cover batch startup, service execution, and shutdown.
Peak RSS is for the entire process. Five processes per row are medians.

| Clients | Mode | Process CPU seconds | Wall seconds | Peak RSS MiB |
| ---: | --- | ---: | ---: | ---: |
| 1 | Baseline Thread | 0.022360 | 0.021299 | 1.750000 |
| 1 | Candidate Thread | 0.022565 | 0.021490 | 1.781250 |
| 1 | Candidate Task | 0.001021 | 0.001021 | 1.578125 |
| 8 | Baseline Thread | 0.191673 | 0.061936 | 2.312500 |
| 8 | Candidate Thread | 0.183842 | 0.058849 | 2.265625 |
| 8 | Candidate Task | 0.006251 | 0.006250 | 1.718750 |
| 64 | Baseline Thread | 1.482039 | 0.448319 | 3.421875 |
| 64 | Candidate Thread | 1.468073 | 0.444168 | 3.421875 |
| 64 | Candidate Task | 0.049132 | 0.049129 | 2.828125 |

At 64 clients and 262,144 requests, candidate Task uses much less CPU and
wall time than candidate Thread in this Channel-only workload. Its 65 jobs
reserve 520 MiB of usable stacks. RSS does not describe that reservation,
and these measurements do not establish native network or timer performance.

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

The alternating runtime, comparable representative translation, and existing
normalized build-cost measurements are complete. Raw cache-mismatched
compiler attempts remain available but must not be treated as a runtime
regression. The temporary harness resumed completed valid pairs rather than
restarting the entire campaign.

The next local integration work is the native-file copy omission and the
four lint findings. The measured native Channel cost, default stack
reservation, and large-batch residual memory require an explicit acceptance
or mitigation decision. No architecture change is needed merely to collect
more evidence, and this pass included no compiler or runtime source fixes.

Linux arm64/x86_64 execution, macOS x86_64 execution, TSan, and wider hardware
and hardening configurations remain unvalidated. No new recurring gate was
added. The dev/main and push hold remains in force.
