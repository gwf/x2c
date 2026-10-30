# Pool fast path and Channel monitor measurements

> Status: reference - implemented locally; acceptance still fails.
> Original baseline: `56fd5ecc1518f40ac46f2c21f50936ae4ab53f93`.
> Measured candidate: `360aab57fbf1fa46343ad514514fb3898dc40c5b`.
> Index changes remain blocked. Nothing pushed or merged to dev.
> No performance, memory, or architectural tradeoff is approved.

## Delivered scope

Implemented only sections 1 and 2 of
[the reviewed corrections](../archive/independent-locks-profiled-corrections.md).
Pool allocation hits now avoid refill preparation through a local noinline
helper. Channel buffering uses dedicated loops and one mutex/condition pair
per Channel. Registration combines owner lookup with the existing CAS.
Stop, acknowledgement, commitment, and payload ownership contracts remain.

The Pool index, counters, and depot protocol are unchanged by these commits.
Historical index arrays still remain until shutdown. The proposed index
replacement and its global lookup mutex were not implemented.

The independent reviewer answered YES for both implementations matching the
reviewed design, with no blocking synchronization or lifetime finding.
The reviewer identified a scheduling gap in the new unrelated-wakeup unit
test. A controlled probe subsequently parked both receivers, stopped one,
required the other to re-enter its wait, and delivered its value successfully.

## Correctness and assembly

The combined candidate passed 154 tests and 1,505 assertions in each accounting
mode. Focused suites cover Pool, Channel, Thread completion/start/parallel
operations, borrowed pools, batches, Context, and storage ownership.

Controlled probes passed for surplus refill preparation, allocation failure
with locks released, Channel mutex/condition initialization rollback, Thread
startup failure, stop at sleep entry, stop acknowledgement before return,
commitment before stop, commitment during the prune unlock gap, and unrelated
shared-condition wakeups. Worker probes are supplemental evidence; they are
not new recurring gates.

The measured accounting-off bump path now emits 66 ARM64 instructions versus
72 in the original baseline and 93 in the preceding candidate. This static
count assumes size 24, initialized managed threading, a current block with
room, and no free-list slot. Calls count as one instruction; callee bodies
are excluded. Pool_malloc has a 112-byte frame and four saved register pairs,
instead of 192 bytes and six pairs. Index preparation addresses occur only
in the separately emitted refill helper. This establishes the intended code
shape, not whole-workload CPU instruction counts.

## Measurement method

Previously failing workloads ran first, followed by a separate confirmation.
Each run alternates five original-baseline/candidate pairs per configuration
and reverses variant order each sample. Both accounting modes are included:
160 processes per run, 320 total. No owned build, test, or profiler ran during
measurements. Builds and tests used one compute slot, at most two jobs.
Normal desktop activity remained; process snapshots accompany both runs.

The generated benchmark C, native flags (`-O2 -fsigned-char -pthread`), and
unchanged runtime archive match the preceding measurements. Fresh Pool,
Channel, and Thread objects precede that archive at link time. Metadata records
revisions and hashes. These are focused runtime builds, not publication gates
or shipped-bootstrap rebuilds.

Elapsed time excludes worker startup/readiness but includes completion/join.
CPU is total process CPU time. RSS is peak process resident memory, not index
ownership. The benchmark checks transmitted values and allocation outcomes.

## Previously failing workloads

All values below are medians from the second, confirmation run. Times are
milliseconds. Accounting 0 means off; 1 means on.

| Workload | Accounting | Baseline elapsed | Candidate elapsed | Change | Baseline CPU | Candidate CPU |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Local Channel, 1 worker, 10 million round trips, capacity 1 | 0 | 340.214 | 344.091 | +1.14% | 340.155 | 344.073 |
| Same | 1 | 336.951 | 342.529 | +1.66% | 336.936 | 342.496 |
| Shared rendezvous, 8 pairs, 160,000 messages | 0 | 710.714 | 708.461 | -0.32% | 8773.597 | 8753.696 |
| Same | 1 | 709.041 | 725.207 | +2.28% | 8742.150 | 8981.695 |
| Shared buffered Channel, 8 pairs, 800,000 messages, capacity 64 | 0 | 401.205 | 415.620 | +3.59% | 5229.936 | 5417.383 |
| Same | 1 | 405.451 | 417.353 | +2.94% | 5289.187 | 5448.474 |
| Pool release, 1 worker, 100,000 cycles, 25.6 million allocations | 0 | 309.313 | 307.384 | -0.62% | 309.301 | 307.359 |
| Same | 1 | 432.198 | 293.468 | -32.10% | 432.175 | 293.449 |
| Pool release, 8 workers, 80,000 total cycles | 0 | 388.708 | 339.727 | -12.60% | 2663.260 | 2186.796 |
| Same | 1 | 1023.097 | 367.094 | -64.12% | 7231.419 | 2385.961 |
| Pool reuse, 8 workers, 16 million allocation/free pairs | 0 | 1381.662 | 44.933 | -96.75% | 9763.578 | 351.545 |
| Same | 1 | 1747.168 | 44.470 | -97.45% | 12428.196 | 349.507 |

The first run also showed slower shared buffering: 395.466 to 405.884 ms
with accounting off (+2.63%), and 397.140 to 408.558 ms on (+2.88%).
Nine of ten paired off comparisons and eight of ten paired on comparisons
were slower across both runs. This is a reproducible blocker.

Local Channel accounting-off medians were slower in both runs, by 1.31% and
1.14%; eight of ten pairs were slower. Samples overlap, so this is a smaller
signal than the earlier 23.2% regression, not proof of exact overhead.
Rendezvous off is near baseline; on medians were slower in both runs, by
1.13% and 2.28%. No broad Channel no-regression claim is warranted.

The one-worker Pool-release slowdown did not recur: off medians improved by
1.17% and 0.62%. This corrects the measured allocation-path cost without
claiming a large single-worker speedup. Independent Pool gains remain large.
Earlier candidate percentages are historical comparisons, not concurrent
measurements against the preceding candidate.

## Independent scaling and shared Pool checks

A further 320 processes cover 1, 2, 4, and 8 workers or Channel pairs, both
accounting modes, and five alternating samples. Independent Pool reuse,
shared-Pool reuse, independent rendezvous Channels, and independent buffered
Channels all had lower elapsed and CPU medians in these 32 configurations.
This is workload-specific evidence, not whole-application acceptance.

Selected eight-worker/pair results below have accounting off. Times are ms.

| Workload | Baseline elapsed | Candidate elapsed | Baseline CPU | Candidate CPU |
| --- | ---: | ---: | ---: | ---: |
| Independent Pool reuse, 1.6 million allocation/free pairs | 140.916 | 4.662 | 985.904 | 35.676 |
| Shared Pool reuse, 800,000 allocation/free pairs | 200.488 | 47.913 | 1045.567 | 327.814 |
| Independent rendezvous Channels, 160,000 messages | 931.688 | 251.893 | 7736.794 | 2510.401 |
| Independent buffered Channels, 800,000 messages, capacity 64 | 349.290 | 47.808 | 3780.437 | 510.289 |

These gains coexist with the shared-Channel regressions above. They do not
authorize accepting those regressions or the memory cost below.

## Memory remains blocked

One-worker growth (16,384 allocations of 512 bytes) again used 11,894,784
baseline peak RSS bytes versus 12,058,624 candidate bytes: +163,840 bytes,
or +1.38%. Both accounting modes reproduce the difference. The index ownership
mechanism is unchanged; the earlier lifecycle measurements remain documented
in [the profile](independent-lock-profile-2026-10-30.md). No new reclamation
claim follows from these RSS runs.

Relative to the preceding candidate, relocating the condition adds 48 bytes
per Channel and removes 48 per Thread on this host. The STOP sentinel adds
48 static bytes, while the TLS waiter loses one 8-byte pointer. These are
representation changes, not evidence of lower application memory use.

## Evidence and limits

Parent scratch root: `.context/lock-contention/`.

- `candidate-fastpath-monitor/metadata.json`: revisions, flags, and hashes.
- `measurements/fastpath-monitor/`: first 160 processes, raw CSV and summary.
- `measurements/fastpath-monitor-confirm/`: confirmation 160 processes.
- `measurements/fastpath-monitor-scaling/`: 320 scaling/shared-Pool processes.
- `check-fastpath-monitor.py`: combined focused build and both-mode checks.
- `debug/locks-fastpath-monitor-tests-{0,1}.log`: combined test results.
- `/tmp/x2c-locks-ec97-pool/debug/pool-short-*`: Pool checks and assembly.
- `/tmp/x2c-locks-ec97-channel/debug/channel-broadcast-*`: Channel checks.
- `/tmp/x2c-shared-condition/`: controlled Channel probe sources and runner.

The root independently inspected the authored diffs, native assembly, and
worker logs, then rebuilt and tested the combined runtime. No new profiler
attribution is claimed for the remaining small Channel costs. Constructor
throughput, whole-compiler performance, publication validation, and a final
bootstrap refresh were not attempted because acceptance already fails.

No source changes beyond the two authorized corrections follow these results.
No timing improvement waives the Channel or retained-index blockers. Any
tradeoff still requires Gary's explicit approval before merging to dev.
