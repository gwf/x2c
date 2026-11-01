# Independent Pool and Channel performance evidence

> Status: reference - current implementation fails mandatory performance acceptance.
> Measured 2026-10-30. No tradeoff approved; no dev publication performed.

## Revisions and method

Baseline runtime: `56fd5ecc1518f40ac46f2c21f50936ae4ab53f93`.
Initial integrated runtime candidate: `989978baf`.
Revised candidate after narrow Channel fixes:
`bdb8cdbbdb949ad156fb10f178f3b121ede9c0ac`.

The same temporary x2c harness was linked to each runtime with
`-O2 -fsigned-char -pthread`. All owned build, test, and profiler jobs stopped
before measurement. The earlier sustained VM and sysmond load had cleared;
normal desktop/browser activity remained. This host has 16 logical CPUs.

Each configuration has five runs per variant. Baseline and candidate alternate
within each configuration; the first variant reverses on alternate samples.
Tables show medians. Elapsed time and process CPU time are separate metrics.
Thread startup and the readiness barrier are excluded; completion and join
are included. Peak RSS covers the whole process, including initialization.

Pool and channel-local group counts are worker counts. Channel pair counts
mean one producer and one consumer per pair: eight pairs use 16 native workers.
Each paired worker uses its own Channel for independent workloads; all pairs
use one Channel for shared workloads. Buffered capacity is 64 unless specified.
The channel-local workload uses capacity one and sends then receives on the
same managed worker. This exercises the uncontended path with Thread stopping
enabled, rather than an unmanaged shortcut.

The initial matrix covers 1, 2, 4, and 8 groups with accounting both off and
on: 72 configurations and 720 process runs. The revised Channel matrix covers
40 configurations and 400 runs. Ten-times-longer Pool and channel-local
confirmations add 80 and 40 runs, respectively.

## Reproduced acceptance blockers

These rows use the revised candidate. Pool source is unchanged from the
initial candidate. Each comparison is the same workload and accounting mode.

| Workload | Accounting | Baseline elapsed | Candidate elapsed | Elapsed change | Baseline CPU | Candidate CPU |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| One worker, 1 million Channel send/receive round trips | off | 35.881 ms | 51.924 ms | +44.7% | 35.888 ms | 51.928 ms |
| Eight pairs, one shared rendezvous Channel, 160,000 messages total | off | 684.042 ms | 1505.918 ms | +120.1% | 8398.313 ms | 10368.158 ms |
| Eight pairs, one shared buffered Channel, 800,000 messages total | off | 392.734 ms | 659.488 ms | +67.9% | 5083.801 ms | 7631.620 ms |
| Eight independent Pools, 16 million allocate/free pairs total | on | 1736.810 ms | 3550.522 ms | +104.4% | 12339.394 ms | 27041.162 ms |
| Eight independent Pool parents, 80,000 child releases and 20.48 million allocations total | on | 1014.866 ms | 2637.127 ms | +159.8% | 7183.463 ms | 20236.066 ms |

The shorter initial matrix also showed the accounting regressions. Increasing
the work tenfold did not remove them. The narrow Channel repair improved its
uncontended result, but the longer confirmation still reproduces the penalty.
The repeated matrices also retain the shared-Channel regressions.

The initial eight-worker Pool growth workload performs 131,072 allocations of
512 bytes and then frees them. Median peak RSS was 84,721,664 bytes at baseline
and 113,541,120 bytes in the candidate, an increase of 28,819,456 bytes (34.0%).
All five candidate peaks exceeded all five baseline peaks. This is measured
peak memory for the workload, not a measurement of index storage alone.
Workers allocate and free independently, so scheduling changes live-allocation
overlap. Native allocator retention and concurrent speculative index copies
also contribute possibilities. Their individual contributions were not isolated.

## Improvements do not waive the blockers

| Workload | Accounting | Baseline elapsed | Revised candidate elapsed |
| --- | --- | ---: | ---: |
| Eight independent Pools, 16 million allocate/free pairs total | off | 1395.992 ms | 45.770 ms |
| Eight independent Channel workers, 8 million same-worker round trips total | off | 787.188 ms | 60.679 ms |
| Eight independent rendezvous pairs, 160,000 messages total | off | 941.381 ms | 280.335 ms |
| Eight independent buffered pairs, 800,000 messages total | off | 357.174 ms | 54.513 ms |

These are focused runtime observations, not whole-application or compiler
throughput results. No speedup is claimed for unmeasured workloads.

## Investigation and bounded repair

The Channel follow-up removed owned-send rollback registration from ordinary
sends, moved temporary-pointer cleanup to unmanaged blocking calls, deferred
condition lookup until blocking, and removed unnecessary rendezvous wakes.
Buffered notification now detaches its selected waiter so another opportunity
can notify the next waiter. Requeue clears its old next link. The worker's
focused tests and controlled failure/sleep/requeue probes passed; translation
is warning-free. Parent compilation and all benchmark result checks passed.

Source review identifies remaining costs, without isolating their timing:

- Immediate managed buffered commitment takes a Channel mutex and a participant
  mutex; baseline takes one completion mutex.
- Rendezvous commitment takes the Channel mutex and both participant mutexes.
- Blocking transfers from the Channel mutex to a private condition mutex and
  back. Baseline sleeps on its queue monitor directly.
- Accounting makes independent Pools update the same atomic counter words;
  requested-byte updates can retry a compare-and-swap. True sharing remains
  even if cache-line padding were to remove false sharing.
- Concurrent Pool index builders can allocate and copy the same prospective
  replacement before one publishes it. Retired published versions also remain
  until shutdown. Source supports duplicate work as a memory hypothesis, not
  attribution of the entire measured RSS increase.

No new accounting representation, builder-coordination protocol, or stop/commit
protocol was implemented to hide these results. Those require a revised design.
These findings reject the current implementation under the acceptance rule;
they do not establish that independent Pool/Channel synchronization cannot be
implemented without these regressions.

## Reproduction and retained evidence

Temporary files are in the orchestrator checkout's
`.context/lock-contention/`. They are not shipped runtime instrumentation or
a new benchmark framework. `bench.x` owns the workload, `run.py` owns execution,
and `summarize.py` computes medians. Baseline and candidate binaries are in
`baseline/`, `candidate/`, and `candidate-fixedcost/`.

`measurements/final-metadata.json` records revisions, binary/source hashes,
flags, host identity, ordering, and workload limits. Raw CSV and summary JSON
are retained in these directories:

- `measurements/matched/`: initial full matrix.
- `measurements/channel-fixedcost/`: revised Channel matrix.
- `measurements/pool-confirm/`: longer Pool confirmation.
- `measurements/channel-local-confirm/`: longer channel-local confirmation.

From the orchestrator checkout, the revised matrix command was:

```sh
python3 .context/lock-contention/run.py \
  .context/lock-contention/baseline/bench \
  .context/lock-contention/candidate-fixedcost/bench \
  --out .context/lock-contention/measurements/channel-fixedcost \
  --samples 5 --modes channel-local,channel-pairs,channel-shared
```

The longer confirmations used `--quick --scale 10 --samples 5`, with
`--modes pool-reuse,pool-release` and `--modes channel-local`, respectively.
Use a new output directory when repeating; do not overwrite these samples.

## Disposition

Merging remains blocked. No tradeoff is approved. The full compiler performance
checkpoint, lock-duration profiling, final current-dev integration, generated
artifact refresh, and publication gate have not run. They cannot make the
demonstrated runtime regressions acceptable, so they were not run merely to
prepare a merge that is already prohibited.

Next design work should address accounting-counter sharing, duplicate index
construction, and the extra Channel commitment/sleep handoffs. Any alternative
must preserve the original contracts and pass matched measurements. Obtain
Gary's explicit decision before changing those architectural choices or
accepting a measured regression.
