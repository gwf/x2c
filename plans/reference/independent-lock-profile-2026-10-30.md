# Profile of the remaining Pool and Channel regressions

> Status: reference - profiling only; acceptance remains blocked.
> Original baseline: `56fd5ecc1518f40ac46f2c21f50936ae4ab53f93`.
> Revised runtime: `a6be0e6c49a995aed7d097a526235b2ef12e4c54`.
> Investigated 2026-10-30. No production code or design changed.
> No tradeoff approved. No merge, push, or publication validation performed.

This follows the [failed acceptance measurements](independent-lock-redesign-performance-2026-10-30.md).
The remaining costs have different locations: extra user-space work on an
uncontended Channel, longer synchronization spans and more kernel CPU on shared
Channels, extra instructions on ordinary Pool allocations, and retained index
versions whose lifetime extends to shutdown.

## Method and scope

All compute was serialized. No owned build, test, or competing workload ran
during a profile. The existing compiler and configured Apple toolchain were
used; no tools were installed and no system tracing configuration was changed.
The host is the same Apple M4 Max Mac used for acceptance measurements.

Three forms of CPU evidence were kept separate:

1. Unchanged baseline and candidate benchmark executables were sampled with
   `/usr/bin/sample`, at 1 ms intervals for 3 seconds. Each of four workloads
   received two profiles per variant, reversing variant order. Longer loop
   counts kept the workload active for the sample window. Main-thread join
   stacks were excluded from worker summaries.
2. Matched copies of the original benchmark read `proc_pid_rusage` immediately
   around the workload. These recorded process instructions, cycles, and user
   and system time. Five alternating samples were run per configuration.
   Runtime code was uninstrumented; exact original/revised Pool, Channel, and
   Thread objects linked against the same unchanged remaining runtime archive.
3. Separate scratch binaries counted helper/native synchronization calls and
   sampled native-operation spans. Channel lock/notification spans sampled
   approximately 1/1024 calls; condition waits sampled 1/16. These diagnostics
   alter execution and are not acceptance timings or kernel syscall counts.

All CPU profiles below use accounting off. Hardware-counter workloads match
the final acceptance workload sizes. Counts and sampled spans use the same
Channel configurations. Pool phase timers sampled every 1024th cycle without
changing retain -> 256 allocations -> release order.

`proc_pid_rusage` user/system time is in Mach ticks on this host. Conversion
uses `mach_timebase_info` (125/3 ns per tick). The raw counter JSON initially
named these two fields `user_ns` and `system_ns`; `units.json` records that
mislabel, and `summary.json` correctly names raw ticks and converted milliseconds.
Instruction and cycle values are unaffected. Counter-run timings are a separate
observation, not substituted for the preceding acceptance measurements.

## Uncontended Channel: additional CPU work, not condition waiting

For one managed worker performing 10 million send/receive round trips at
capacity one:

| Counter-run median | Baseline | Revised |
| --- | ---: | ---: |
| Process instructions | 9,733,641,859 | 11,354,378,332 |
| Process cycles | 1,345,460,092 | 1,655,104,453 |
| Process CPU | 331.018 ms | 399.817 ms |
| User CPU | 330.854 ms | 399.412 ms |
| System CPU | 0.210 ms | 0.411 ms |

Instructions increase 16.65%; cycles increase 23.01%. Almost all the additional
CPU is user time. Exact diagnostic counts show:

- Both variants acquire and release the queue monitor 20 million times.
- Neither performs a Channel condition wait or targeted signal.
- The revision performs 20 million registration entries and 20 million exits:
  40 million successful CAS operations in this no-stop workload.
- Baseline performs 20 million condition broadcasts with no waiters; the
  revision performs none.

The unchanged-binary profiles locate the additional work:

| Worker stack category | Baseline samples | Revised samples |
| --- | ---: | ---: |
| Registration helpers | 0 / 5210 | 492 / 5211 (9.44%) |
| Thread-owner and stop checks | 388 / 5210 (7.45%) | 545 / 5211 (10.46%) |
| Other runtime work, including Channel dispatch/queue helpers | 968 / 5210 (18.58%) | 1135 / 5211 (21.78%) |
| Native allocator paths | 2277 / 5210 (43.70%) | 1936 / 5211 (37.15%) |
| Condition notification | 293 / 5210 (5.62%) | 0 / 5211 |

Scaling these single-active-worker sample shares by the separate CPU medians
gives an approximate attribution: about 38 ms in the new registration helpers,
about 17 ms more in owner/stop checks, and about 26 ms more in other runtime
work, offset by roughly 19 ms of removed notification work. These are sampled
estimates, not isolated nanosecond measurements of an atomic instruction.
Registration includes function-call and initialization-guard overhead as well
as CAS. Allocator time is approximately similar after scaling, despite its
smaller percentage in the slower candidate.

The hot source paths are `lib/thread.x` registration entry/leave and owner/stop
helpers, plus `_communicate`, `_attempt`, and `_notify` in `lib/channel.x`.
Sparse native lock spans were near the clock floor (about 16 ns with a 13 ns
clock-pair reference). They cannot support a claim of increased uncontended
kernel mutex waiting.

## Shared Channels: kernel CPU and longer handoffs

Eight producer/consumer pairs share one Channel in each workload. Rendezvous
transfers 160,000 messages; capacity-64 buffering transfers 800,000.

| Counter-run median | Rendezvous baseline | Rendezvous revised | Buffered baseline | Buffered revised |
| --- | ---: | ---: | ---: | ---: |
| User CPU | 230.301 ms | 281.348 ms | 241.659 ms | 260.477 ms |
| System CPU | 8427.084 ms | 9957.913 ms | 4865.684 ms | 6305.164 ms |
| Process instructions | 5,802,051,843 | 6,564,806,500 | 3,846,525,951 | 4,864,011,037 |
| Process cycles | 31,913,601,255 | 37,574,026,624 | 18,803,698,901 | 24,047,367,588 |

The additional system CPU is about 1531 ms for rendezvous and 1439 ms for
buffering. Additional user CPU is only about 51 ms and 19 ms respectively.
These are CPU sums across workers, not elapsed time.

Counts-only diagnostics give these five-run medians. Worker completion
notification/locking is tagged separately and excluded from queue counts.

| Native operations | Rendezvous baseline | Rendezvous revised | Buffered baseline | Buffered revised |
| --- | ---: | ---: | ---: | ---: |
| Explicit queue lock/unlock pairs | 320,000 | 320,000 | 1,600,000 | 1,600,000 |
| Condition waits | 191,171 | 160,000 | 70,467 | 67,591 |
| Notifications | 160,000 broadcasts | 160,000 signals | 45,716 broadcasts | 67,591 signals |

Condition waits release and reacquire their mutex internally; the explicit
lock row does not count that internal reacquisition as another API call.
Fewer waits do not imply less waiting:

| Sampled native span | Rendezvous baseline | Rendezvous revised | Buffered baseline | Buffered revised |
| --- | ---: | ---: | ---: | ---: |
| Mean condition-wait span | 29.695 us | 43.163 us | 25.675 us | 38.802 us |
| Condition waits at least 10 us | 70.69% | 85.21% | 68.48% | 81.73% |
| Mean explicit lock acquisition span | 10.914 us | 11.210 us | 2.652 us | 3.009 us |

These pooled diagnostic samples include sleep, scheduling, and mutex
reacquisition. Lock acquisition spans include waiting and native lock work.
Instrumentation can affect scheduling, so these spans must not be summed with
process CPU or presented as an exact decomposition of acceptance elapsed time.

Unchanged-binary worker stacks independently concentrate in
`__psynch_mutexwait`, `__psynch_cvwait`, and `__psynch_mutexdrop`, with notification
paths in `__psynch_cvbroad` for baseline and `__psynch_cvsignal` for the revision.
These are stack occupancy observations, not on-CPU percentages.

Together, the evidence locates the shared regression in synchronization
handoffs: similar explicit lock counts, fewer but longer waits, and substantially
more kernel CPU. Buffered notification calls also increase. It does not isolate
which kernel scheduling decision causes the longer spans, or establish that
registration CAS alone causes the extra kernel time. No such causal claim or
replacement notification design is made here.

## Pool-release workload: the ordinary allocation path grew

This workload constructs and releases 100,000 child Pools, making 256 small
allocations before each release. Its name does not isolate destruction cost.

| Counter-run median | Baseline | Revised |
| --- | ---: | ---: |
| Process instructions | 8,421,962,910 | 8,934,965,926 |
| Process cycles | 1,259,204,044 | 1,298,840,404 |
| Process CPU | 310.259 ms | 314.832 ms |

Instructions increase by 513,003,016 (6.09%); cycles increase 3.15%. This
counter run's elapsed penalty is smaller than the preceding 4.4% acceptance
confirmation. It still records additional executed work rather than increased
kernel waiting. The raw observations remain separate.

Exact diagnostic counts rule out additional ordinary mutex acquisitions:

| Calls over the workload | Baseline | Revised |
| --- | ---: | ---: |
| Owner lock/unlock pairs | 26,700,009 | 26,700,000 |
| Depot lock/unlock pairs | 1,000,009 | 1,000,009 |
| Accounting-registry lock pairs | 0 | 0 |
| Pool-origin accounting-enabled queries | 26,500,000 | 25,900,000 |
| Slot allocations | 25,600,000 | 25,600,000 |
| Block resets | 1,800,000 | 1,800,000 |

The revised index takes nine cold registration lock pairs. The common path
does not acquire that mutex. Accounting-enabled queries decrease, so extra
disabled-accounting queries are not the net explanation.

ARM64 assembly identifies the extra common-path work. With a 24-byte request,
accounting off, threading enabled, an existing current block, no free-list
slot, and available bump space, the baseline executes 72 emitted instructions;
the revision executes 93. Calls count as one instruction, excluding their
unchanged callee bodies. Both paths use the same 192-byte frame, six saved
register pairs, and three calls: accounting check, owner lock, and owner unlock.

The extra 21 instructions are generalized-loop setup and bookkeeping. The
revised function prepares index mutex/condition/build-state addresses and spills
candidate, class, accounting, and current-block state before knowing whether
refill is needed. Existing-block success retains extra reloads, accounting
branches, and a candidate check. The baseline has a distinct accounting-off
success path that bypasses that setup.

Of 256 allocations per cycle, nine refill and 247 use existing bump space.
Across 100,000 cycles, 24.7 million common-path calls multiplied by 21 extra
instructions gives 518.7 million instructions. That closely accounts for the
observed 513.0 million net increase; other paths provide the net offset. This
is an instruction-count explanation, not equal-cycle pricing of instructions.

Unchanged-binary samples put roughly 71% of baseline worker occupancy and 73%
of revised occupancy beneath `Pool_malloc`. Pool release itself stays near 6%.
Sparse phase timers were directionally consistent, but their per-run deltas
were noisy and their approximately 112 ns CPU-clock cost is material for short
construction/destruction phases. They do not justify a precise time attribution.

## Retained index memory: allocation history stays live until shutdown

The prior equal-live evidence was independently checked, then extended with
32 lifecycle executions: baseline/revised, one/eight workers, 16,384/65,536
allocations per worker, accounting off/on, and two samples per combination.

| Growth workload | Baseline owned index requests | Revised owned requests | Revised allocator-usable bytes | Revised versions |
| --- | ---: | ---: | ---: | ---: |
| 1 worker x 16,384 allocations | 262,144 B | 520,304 B | 652,800 B | 7 |
| 8 workers x 16,384 allocations | 2,097,152 B | 4,190,368 B | 4,421,120 B | 10 |
| 1 worker x 65,536 allocations | 1,048,576 B | 2,093,200 B | 2,291,200 B | 9 |
| 8 workers x 65,536 allocations | 8,388,608 B | 16,773,312 B | 17,053,184 B | 12 |

In every run, these ownership totals remain unchanged after allocation frees,
worker joins, and Pool releases. Runtime shutdown frees the entire chain and
sets the owned index totals and version count to zero. The probe never inspects
freed index addresses.

The source reason is explicit: lock-free readers can retain a published index
pointer while a replacement becomes current. The replacement links the previous
table, and the current design provides no earlier reader-completion reclamation
point. `_storage_shutdown` owns freeing the chain. Pool release returns blocks
to the depot; it does not remove their index entries or retired versions.

Duplicate successful construction is absent in the measured growth runs:
successful allocation count equals retained version count. Historical geometric
rehashing remains in both implementations. For current slot capacity S and k
versions, 16-byte slots and 16-byte revised headers give:

- Baseline current requested storage: `16*S`.
- Revised current plus retired requests: `16*(2*S - 256) + 16*k`.
- Old-table slots scanned cumulatively during successful rebuilds: `S - 256`.

At S = 131,072, baseline construction temporarily needs 3,145,728 requested
bytes; revised construction retains 4,190,368. Allocator rounding adds a separate
cost: the revised current request of 2,097,168 receives 2,129,920 usable bytes.
At larger sizes rounding differs; it is not a fixed 32 KB penalty per version.

Resident ranges also confirm that retained arrays occupy physical pages. At
the largest workload, revised index-intersecting resident ranges total about
16.94-16.96 MB before shutdown. A zero owned-range total after shutdown means
the allocations were freed, not that their pages were returned to the OS.
Overall RSS remains affected by native allocator retention, shared allocation
pages, backing storage, and other runtime state. Requested bytes, usable bytes,
resident ranges, and process RSS must not be added or treated as interchangeable.

## Evidence and disposition

All source/runtime files remain unchanged. Profiling instruments only scratch
copies. No candidate repair, alternative design, or tradeoff was implemented.
Acceptance remains blocked by the previously measured regressions.

The parent checkout retains evidence under `.context/lock-contention/profiling/`:

- `counters/`: raw hardware-counter samples, corrected-unit summary, build log,
  source/executable/archive hashes, and `units.json`.
- `stacks/`: all 16 unchanged-binary profiles, workload outputs, commands, and
  parsed worker summaries. `parse-stacks.py` owns the category calculation.
- `channel/`: copies of instrumentation sources, exact build commands, raw
  per-thread counts/spans, calibration, and the diagnostic report.
- `pool/`: phase samples, clock calibration, exact counts, uninstrumented
  assembly, build metadata, and preparation/build scripts.
- `index/`: per-version and lifecycle samples, commands, hashes, and all 32
  successful phase assertions.

Original worker artifacts remain in `/tmp/x2c-channel-profile-20261030/`,
`/tmp/x2c-locks-ec97-pool/debug/pool-release-profile/`, and
`/tmp/x2c-locks-index-review/`. Parent commands are in `build-counters.py`,
`run-counters.py`, and `run-samples.py` in the profiling directory.
No profiler, workload, or worker build remains running.
