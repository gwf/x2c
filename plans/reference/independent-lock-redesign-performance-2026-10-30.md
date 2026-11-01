# Revised lock implementation: measurements and acceptance

> Status: reference - revised implementation still fails mandatory acceptance.
> Measured 2026-10-30 against original baseline `56fd5ecc1518f40ac46f2c21f50936ae4ab53f93`.
> Final measured runtime: `a6be0e6c49a995aed7d097a526235b2ef12e4c54`.
> Nothing merged or pushed to dev. No performance or memory tradeoff approved.

## Implementation and comparison

The [reviewed design](../archive/independent-locks-revised-design.md) was implemented
with private Pool traffic counters, one reserved index builder, and Channel
monitor registration instead of participant mutexes. Parent review moved Pool
counter retirement after parent unlock. Independent source review found no
additional correctness blocker in the final runtime.

The first revised runtime was `890ff100f59e8e88924dfd4f217352ff8443e3b7`.
Its measurements removed the Pool accounting penalty but retained Channel
regressions. A bounded follow-up deferred TLS waiter initialization until an
operation must block. Review caught and corrected a retry-path race before
that follow-up was measured: after releasing and reacquiring the queue mutex
to prune a stopped peer, a queued caller must recheck its committed outcome.
Controlled probes cover commitment during that gap.

All builds and tests were serialized with one compute slot and at most two
build jobs. All owned compute stopped during timings. The host had normal
desktop activity; no competing owned build, test, or profiler ran. Host process
snapshots are retained with the samples.

The same generated benchmark C and `-O2 -fsigned-char -pthread` flags were
used. Revised Pool, Channel, and Thread units were freshly translated and
compiled, then linked before the existing unchanged runtime archive. Archive,
source, and executable hashes are recorded. This focused build does not claim
a shipped-bootstrap rebuild or publication validation.

Five baseline/candidate samples were taken for every configuration. Variants
alternate, reversing order each sample. Elapsed time and process CPU time are
separate; RSS is process peak resident memory. Startup/readiness is excluded
from elapsed time, while completion and join are included.

The first revised runs comprise 120 long-workload and 120 shared/growth runs.
The final confirmation comprises 160 runs over 16 configurations, including
both accounting modes. The final local Channel workload is ten times longer
than the preceding one-million-round-trip confirmation. Pool release with
one worker is also ten times longer than the initial revised comparison.

## Remaining acceptance blockers

These medians compare the final measured runtime against the original baseline.
All timing rows below have accounting off.

| Workload | Baseline elapsed | Revised elapsed | Change | Baseline CPU | Revised CPU |
| --- | ---: | ---: | ---: | ---: | ---: |
| One worker, 10 million buffered Channel round trips, capacity 1 | 331.937 ms | 408.956 ms | +23.2% | 331.922 ms | 408.810 ms |
| Eight pairs, shared rendezvous Channel, 160,000 messages | 712.378 ms | 854.484 ms | +19.9% | 8824.114 ms | 10231.566 ms |
| Eight pairs, shared buffered Channel, 800,000 messages, capacity 64 | 411.807 ms | 518.026 ms | +25.8% | 5266.363 ms | 6705.862 ms |
| One worker, 100,000 child Pool releases and 25.6 million allocations | 304.506 ms | 317.832 ms | +4.4% | 304.498 ms | 317.827 ms |

Every final Channel candidate elapsed sample exceeds every matching baseline
sample in these three configurations. Each of the five paired single-worker
Pool-release comparisons is slower; the earlier shorter run showed +4.5%.
Accounting-on Channel results also regress. These are repeatable observations,
not a claim that a particular instruction explains their entire magnitude.

| Pool growth workload, accounting off | Baseline peak RSS | Revised peak RSS | Increase |
| --- | ---: | ---: | ---: |
| One worker, 16,384 allocations of 512 bytes | 11,894,784 B | 12,058,624 B | 163,840 B (1.38%) |
| Eight workers, 131,072 allocations of 512 bytes total | 84,738,048 B | 84,885,504 B | 147,456 B (0.17%) |

The one-worker RSS values repeat exactly across all five samples in both
accounting modes. The earlier eight-worker revised comparison also showed
higher RSS. The former 34% growth-memory penalty is greatly reduced, but the
remaining increase is not waived because it is smaller.

## Pool accounting improvements do not waive the blockers

| Workload, accounting on | Baseline elapsed | Revised elapsed | Baseline CPU | Revised CPU |
| --- | ---: | ---: | ---: | ---: |
| Eight independent Pools, 16 million allocate/free pairs | 1759.163 ms | 45.222 ms | 12492.127 ms | 355.003 ms |
| Eight independent parents, 80,000 child releases and 20.48 million allocations | 1020.847 ms | 371.480 ms | 7251.008 ms | 2463.271 ms |

The private counters eliminate the previous accounting-on throughput regression
in these workloads. No full-compiler or whole-application speedup is claimed.

## Equal-live memory attribution

A separate diagnostic build pauses every growth worker after allocation and
before freeing its item array or returning. Both variants therefore retain
the same live payload, item arrays, and worker lifetimes at the sample point.
These instrumented binaries are not used for acceptance timings.

The original harness already keeps each Pool alive until all joins complete.
Early slot frees do not reclaim its backing blocks or make those blocks
available to another Pool. The barrier mainly equalizes auxiliary arrays and
worker lifetime; it does not correct early reclamation of Pool backing.

The baseline diagnostic uses original generated Pool, Channel, and Thread
units from revision `56fd5ecc`, replacing all three together. The candidate
uses the final measured generated units. Both link the same verified archive
and identical diagnostic harness. There are three alternating samples per
variant for each worker count and accounting mode: 24 executions total.

| At the barrier | One worker | Eight workers |
| --- | ---: | ---: |
| Pool backing bytes, identical in both variants | 9,603,584 | 76,724,736 |
| Baseline current index requested bytes | 262,144 | 2,097,152 |
| Revised current index requested bytes | 262,160 | 2,097,168 |
| Revised retired index requested bytes | 258,144 | 2,093,200 |
| Unpublished candidate bytes, both variants | 0 | 0 |

Both variants perform the same seven or ten successful index allocations.
The revision has no duplicate construction, but retains published old tables.
The revised table's 16-byte inline header also changes allocator rounding:
current-table usable bytes rise from 262,144 to 294,912 with one worker, and
from 2,097,152 to 2,129,920 with eight workers.

At the barrier, median process RSS is higher by 163,840 bytes with one worker
in both accounting modes. With eight workers it is higher by 294,912 bytes
accounting off and 163,840 bytes accounting on. Resident index address ranges
also increase. The process RSS difference is smaller than the index-range
difference because other mapped allocator pages differ. These quantities must
not be added or treated as exact additive attribution.

The diagnostic establishes real retained index storage and a remaining
equal-live RSS regression. It does not justify removing tables while readers
can still reference them, or silently introducing a different index design.

## Correctness evidence and limits

Worker checks passed for Pool (27 tests, 441 assertions in each accounting
mode) and Channel/Thread-related suites (126 tests, 1032 assertions).
Controlled scratch probes exercised counter retirement and saturation,
single-builder reservation, allocation-failure fallback, unaffected existing
allocation/lookup during construction, initialization failures, owned rollback,
stop at sleep entry, stop/commit ordering, unregister acknowledgement, immediate
quiescent destruction, rendezvous peer commitment, and the prune-gap race.

The final parent combined checks passed 153 tests and 1473 assertions in each
accounting mode, with warning-free focused compilation. Full logs are
`debug/locks-redesign-combined-{0,1}.log`. No final publication gate, compiler
performance checkpoint, broader benchmark matrix, current-dev integration,
or final bootstrap refresh was run. Existing runtime failures already prohibit
publication. No tradeoff has been accepted.

## Reproduction and evidence

In the parent checkout, `.context/lock-contention/` retains:

- `candidate-redesign/`: first revised runtime and metadata.
- `candidate-redesign-lazy-fixed/`: final measured objects, executable, and metadata.
- `measurements/redesign-long/` and `redesign-shared-growth/`: first revised comparisons.
- `measurements/redesign-final/`: final raw CSV, configuration list, host snapshot, and summary.
- `build-redesign.py` and `run-failures.py`: exact focused build and confirmation scripts.

The final commands were:

```sh
python3 .context/lock-contention/build-redesign.py candidate-redesign-lazy-fixed
python3 .context/lock-contention/run-failures.py \
  .context/lock-contention/baseline/bench \
  .context/lock-contention/candidate-redesign-lazy-fixed/bench \
  .context/lock-contention/measurements/redesign-final
python3 .context/lock-contention/summarize.py \
  .context/lock-contention/measurements/redesign-final
```

Use a new output directory when repeating. Do not overwrite the retained samples.
Parent logs are `debug/locks-*redesign*` and `debug/locks-candidate-redesign-*`.
Pool diagnostic sources, build commands, hashes, samples, and summaries are in
`/tmp/x2c-locks-ec97-pool/debug/pool-memory-diagnostic/`. Its preparation/build
scripts are `/tmp/prepare-pool-memory-diagnostic.py` and
`/tmp/build-pool-memory-diagnostic.py`. Channel controlled-probe evidence is
in `/tmp/x2c-registered-channel/` and the worker's `debug/channel-prune-*` logs.

The candidate remains local and blocked. The results reject this implementation
under the acceptance rule, not all possible independent synchronization designs.

The [follow-up profile](independent-lock-profile-2026-10-30.md) locates the
remaining CPU/wait costs and measures index ownership through shutdown.
That investigation changes no production code or design and accepts no tradeoff.
