# Remaining Channel costs after the fast-path corrections

> Status: reference - profiling only; acceptance remains blocked.
> Original baseline: `56fd5ecc1518f40ac46f2c21f50936ae4ab53f93`.
> Current runtime: `360aab57fbf1fa46343ad514514fb3898dc40c5b`.
> No runtime, index, or contract changes. No merge or approved tradeoff.

## Findings

The local regression is additional user-space work. Its measured instruction
increase closely matches the emitted instruction increase on the ordinary
buffered send/receive path. The registration helpers are visible in the
profile, but the evidence does not isolate the latency of their CAS operations.

Shared rendezvous adds predominantly system CPU. Its explicit lock and
broadcast counts are unchanged, while sampled mutex acquisition takes longer.
Shared buffered operation has more waits and broadcasts in the diagnostic
runs, and longer sampled waits. Its user CPU decreases. Kernel handoff and
waiting costs are therefore relevant; extra fixed user-space work alone does
not explain slower completion. The precise kernel scheduling cause remains
unidentified. Buffered total-CPU deltas vary between counter runs.

These findings explain different costs in different workloads. They do not
authorize another design change or waive the existing acceptance failures.

## Measurement boundaries

All comparisons use the original baseline, not the previous failed candidate.
The host is the same Apple M4 Max Mac. Workloads and profilers ran one at a time;
no owned build or test ran concurrently. Unrelated desktop activity changed
during the session. Process snapshots do not establish a continuously quiet
host. Repeated measurements and their variability are reported separately.

Three evidence sets are kept distinct:

1. Two hardware-counter batches, each with five alternating samples for three
   Channel workloads in both accounting modes: 120 processes total. Identical
   benchmark C reads `proc_pid_rusage` around the workload. Uninstrumented
   Pool, Channel, and Thread objects link against the same remaining runtime
   archive. This is a matched runtime-object comparison, not full repository
   rebuilds. User/system ticks are converted with the measured Mach timebase
   of 125/3 nanoseconds per tick.
2. Twelve native stack samples of the unchanged baseline and candidate
   benchmark binaries: two reversed-order samples per variant/workload,
   accounting off, at 1 ms intervals for 3 seconds. Longer loops keep work
   active. Main-thread join stacks are excluded. Worker-stack occupancy
   includes blocked threads; it is not on-CPU attribution.
3. Sixty-six separately instrumented processes count native calls and sample
   their spans. Accounting off has five alternating runs per workload with
   counts only and five with spans. One accounting-on counts-only pair per
   workload checks whether the native operation pattern changes. Baseline
   input C was verified byte-for-byte against the original bootstrap sources.

The counter interval includes worker execution, joins, and Thread freeing.
It excludes Channel construction and final Channel freeing. Hardware reads
slightly surround the existing wall/CPU interval. Each metric has its own
median; user/system medians do not necessarily add to total-CPU medians.

Instrumentation changes execution. In particular, counts-only instrumentation
reverses the local elapsed ordering. No diagnostic elapsed value is used as
acceptance evidence or to rank implementations. Wait spans include sleeping,
scheduling, and mutex reacquisition. Spans from concurrent workers overlap
and cannot be summed into elapsed time.

## Local Channel: the emitted instruction gap explains the count increase

One managed worker performs 10 million borrowed integer round trips through
a capacity-one Channel. Confirmation counter medians are below, accounting off.

| Metric | Original baseline | Current candidate |
| --- | ---: | ---: |
| Instructions | 9,737,213,052 | 10,064,064,536 |
| Cycles | 1,360,783,594 | 1,383,206,430 |
| Elapsed | 336.922 ms | 343.541 ms |
| Process CPU | 336.885 ms | 343.436 ms |
| User CPU | 336.136 ms | 342.492 ms |
| System CPU | 0.783 ms | 0.766 ms |

The increase is 326,851,484 instructions, or 3.36%, and 6.551 ms process CPU.
The first batch showed 324,297,484 additional instructions and 7.195 ms CPU.
Accounting on showed 322-327 million additional instructions across the two
batches. The repeatable instruction gap is clearer than the small time delta.

Exact counts show 20 million explicit lock/unlock pairs and 20 million
broadcasts in both variants. Neither waits on a Channel condition. Both perform
20 million owner lookups. The baseline performs 20 million caller-stop checks;
the candidate performs 20 million registration entries and exits, containing
40 million successful CAS operations. It performs no separate caller-stop
getter on this uninterrupted immediate path.

Unchanged-binary worker samples put 656 of 5,205 candidate samples (12.60%)
under registration helpers. Baseline owner/stop checks occupy 377 of 5,186
(7.27%). The candidate helper includes TLS/owner work, initialization guards,
and CAS; the categories do not isolate atomic latency. Allocator and other
runtime work also shift, so helper shares cannot be equated to net overhead.

The selected normal path in the unchanged ARM64 binaries has these static
instruction counts, not complete dynamic instruction totals:

| Path | Baseline | Candidate | Difference |
| --- | ---: | ---: | ---: |
| Send, including relevant Thread helper bodies | 140 | 155 | +15 |
| Receive, including relevant Thread helper bodies | 98 | 115 | +17 |
| Round trip | 238 | 270 | +32 |

The assumptions are warm initialization guards, a managed caller, borrowed
integer payload, capacity one, initially empty buffer, successful allocation,
and no stop. Common allocator, native pthread, TLS resolver, and other common
runtime bodies are excluded equally; their call instructions count once.
Explicit address ranges and selected instructions are retained.
Generated cleanup callbacks are also excluded; independent review verified
that both successful-send callbacks execute the same nine instructions.

The caller/queue bodies add 34 instructions per round trip. Expanded baseline
lock/unlock/stopping helpers total 47 instructions per operation; candidate
enter/leave helpers total 46. Thus the net instruction increase is not simply
the count of two new CAS instructions. The instruction costs of surrounding
code and helper replacements must be considered together. Atomic latency is
not established by counting instructions.

Concretely, buffered send is now an out-of-line call with its own frame and
return sequence; the baseline inlined that work. Registration adds an owner
output slot, argument setup/reloads, and result checks. Receive spills and
reloads its value and ownership flag where the baseline kept them in registers.
These observations explain the surrounding code increase without assigning
all 34 instructions to one mechanism.

Thirty-two extra instructions times 10 million round trips predicts 320 million
extra instructions, close to the measured 322-327 million. This is evidence
for the ordinary generated path as the source of the instruction increase.
It is not a cycle-accurate explanation of every additional millisecond.

## Shared rendezvous: extra system CPU without more explicit locks

Eight sender/receiver pairs share one rendezvous Channel and transfer 160,000
messages. Confirmation medians below have accounting off.

| Metric | Original baseline | Current candidate |
| --- | ---: | ---: |
| Elapsed | 658.106 ms | 688.796 ms |
| Process CPU | 8038.903 ms | 8431.374 ms |
| User CPU | 219.009 ms | 236.593 ms |
| System CPU | 7821.398 ms | 8193.215 ms |

The first batch also added predominantly system CPU: 7778.683 to 8144.979 ms,
with user CPU 224.470 to 237.746 ms. Both accounting-on batches showed the
same direction. System CPU, not additional caller instruction execution alone,
dominates the measured extra CPU.

Counts-only medians show 320,000 explicit lock/unlock pairs and 160,000
broadcasts in both variants. Wait counts are similar: 191,553 baseline versus
191,135 candidate. The candidate adds 640,000 registration CAS operations but
reduces owner lookups from 863,106 to 320,000 and stop checks from 863,106
to 351,135.

Sampled mutex acquisition spans rise from 9.068 to 11.713 microseconds.
Condition-wait spans rise from 30.138 to 30.818 microseconds. The share of
sampled lock acquisitions lasting at least 10 microseconds rises from 13.44%
to 15.99%. These are instrumented observations of handoff behavior, not an
exact additive explanation of the uninstrumented time delta.

Native snapshots place roughly 57% of worker occupancy in `__psynch_mutexwait`,
24% in `__psynch_cvwait`, and 15% in `__psynch_mutexdrop` for both variants.
This identifies the dominant synchronization path. Similar percentages do not
mean equal costs; blocked occupancy is not process CPU, and kernel decisions
are not visible in these stacks.

## Shared buffering: more waits and longer wait spans, variable system cost

Eight pairs share a capacity-64 Channel and transfer 800,000 messages.
Confirmation medians below have accounting off.

| Metric | Original baseline | Current candidate |
| --- | ---: | ---: |
| Elapsed | 388.365 ms | 393.080 ms |
| Process CPU | 4998.823 ms | 5067.755 ms |
| User CPU | 239.754 ms | 201.952 ms |
| System CPU | 4758.476 ms | 4863.638 ms |

User CPU decreases in both batches and both accounting modes. System CPU
increases in this confirmation, but the first accounting-off batch had lower
candidate total CPU despite higher elapsed time: 5017.332 to 4893.196 ms CPU,
394.045 to 401.977 ms elapsed. Candidate elapsed in that first set ranged
from 384.968 to 478.182 ms. The data do not support one stable system-CPU
increment that explains every buffered result.

Counts-only accounting-off medians show:

| Native or helper operation | Baseline | Candidate |
| --- | ---: | ---: |
| Explicit lock/unlock pairs | 1,600,000 | 1,600,000 |
| Condition waits | 69,187 | 71,679 |
| Broadcasts | 45,208 | 47,205 |
| Owner lookup | 1,738,374 | 1,600,000 |
| Caller-stop checks | 1,738,374 | 71,679 |
| Registration CAS operations | 0 | 3,200,000 |

Waits increase by 3.60% and broadcasts by 4.41% in these diagnostic runs.
The policy is unchanged: empty-to-nonempty and full-to-not-full transitions
broadcast. More broadcasts here mean more observed queue-boundary transitions,
not a newly added notification site. A single accounting-on check shows the
same pattern: waits 69,096 to 71,964 and broadcasts 44,678 to 46,986.

Sampled condition-wait spans rise from 24.985 to 27.893 microseconds. The
share lasting at least 10 microseconds rises from 68.11% to 70.49%.
Mutex acquisition spans rise from 2.265 to 2.425 microseconds. These locate
additional exposure to waiting/handoffs. They do not establish why the native
mutex scheduler selected a different sequence or quantify a causal fraction
of elapsed regression. Notification spans have only 165 and 180 samples;
their averages are too weak for a precise notification-cost claim.

Native snapshots remain dominated by mutex wait, condition wait, and mutex
drop. `__psynch_mutexdrop` is classified explicitly as a kernel handoff, not
user-space runtime work. Buffered mutex-drop occupancy is 15,196/71,856
baseline samples versus 15,968/72,384 candidate samples. This modest shift
does not by itself prove that mutex release is the root cause.

## Evidence, review, and unchanged acceptance

All artifacts are under `.context/lock-contention/profiling-monitor/`:

- `counters/`: both raw 60-process batches, summaries, measured timebase,
  source/binary hashes, and host snapshots.
- `stacks/`: all twelve raw profiles, workload outputs, commands, and parsed
  worker occupancy. The parser explicitly recognizes mutex-drop stacks.
- `channel/`: instrumentation source, baseline source identity checks, raw
  counts/spans, clock calibration, native assembly, and hot-path selections.
- Root scripts preserve the counter build/run and stack-sampling commands.

Native span clocks were calibrated per worker at approximately 13-15 ns per
clock pair. Waits are sampled at about 1/16 and other native calls at about
1/1024. The spans are useful at microsecond scale; local native-call spans
near the clock cost are not used to explain nanosecond differences.

Independent evidence review checked the comparison boundaries and identified
two interpretation hazards addressed above: blocked stack occupancy is not
CPU time, and separately computed medians are not an additive decomposition.
The root inspected source, raw measurements, worker reports, and native
instruction selections. No runtime or index source changed during profiling.
Independent review also verified the selected instruction ranges and the
32-instruction difference, including the identical excluded cleanup callbacks.

The retained-index memory issue remains blocked and unresolved. The prior
[acceptance measurements](independent-lock-fastpath-monitor-performance-2026-10-30.md)
remain failures; diagnostic variation does not overturn them. No change is
proposed here, no tradeoff is accepted, and nothing is merged to dev.
