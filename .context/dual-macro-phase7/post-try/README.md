# Post-removal real-try profile

This measures the verified phase7 final candidate, not the earlier phase6
reference. Base source hashes were checked before instrumentation. Saved
uninstrumented final binary is unchanged; isolated source was restored afterward.
Instrumented binary `/tmp/x2c-dual-phase7-post-try` SHA is in candidate.sha256.
One isolated direct build used `/tmp/x2c-dual-phase7-final`, without bootstrap
refresh. instrumentation.patch dry-applies against verified phase7 source
(patch-check.log). Full source copies and generated trees remain only in /tmp.

Three spans cover actual try operations only: existing outer transaction begin,
its current-scope symbol Map copy child, and template application. Snapshot and
application are disjoint; symbol copy must not be added again. Ordinary nodes
and ordinary transactions are not timed. The application span includes
Macro_apply, invocation rows, Match/freshening/replacement, binding and producer
work; it has no internal split in this focused profile.

collect.py ran the actual seven-file compiler corpus and exception benchmark
once in default/live modes, plus three repeats of defer-try-cleanup. All 19
outcomes and raw C/H digests equal the final phase7 manifest without output
normalization. Commands, common home, absolute paths and every metric are in
commands.log/results.json. Generated files remain in
/tmp/dual-phase7-post-try-runs.

| Workload | Tries | Snapshot ms | Application ms | Scope-copy child ms | Nonoverlap total ms | Average ms/try |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Seven-file default | 2 | 1.627 | 1.349 | 0.945 | 2.976 | 1.488 |
| Seven-file live | 2 | 2.257 | 1.379 | 1.598 | 3.636 | 1.818 |
| Exception default | 4 | 1.846 | 1.876 | 1.773 | 3.722 | 0.9305 |
| Exception live | 4 | 1.705 | 1.721 | 1.644 | 3.426 | 0.8565 |

Corpus rows are single diagnostic samples, not medians or throughput evidence.
Fixture repeats each contain three applications. Nonoverlap totals are
2.643/3.220/2.767ms; median2.767ms and range2.643-3.220ms. Average per try
has median0.9223ms, range0.8810-1.0733ms. summary.json retains the separate
snapshot/application/copy totals for each repeat. These are aggregate averages,
not a median over individual try applications.

The first collection completed every translation successfully, then its
summary code raised KeyError because a zero-try corpus row had no lazily
initialized timer output. Missing metrics were corrected to zero in the
aggregator and summary recomputed from retained results, without repeating
translations or builds. collect-summary-failure.log preserves that failure.
This was a reporting bug, not a compiler or profiling-span failure.

Excluded: transaction commit/rollback, frame/new-name allocation, parse-time
preparation, region/declaration/landing/cleanup construction before application,
and unrelated compiler work. Timers perturb tiny values and these averages
cannot attribute whole-translation overhead or establish a migration budget.
No additional optimization was made. Root's uninstrumented three-way paired
measurements remain the throughput evidence.

Reproduce build in isolated checkout:

```
make -f ../stage.mk -C builds/0 \
  X2C_COMPILER=/tmp/x2c-dual-phase7-final >debug/phase7-post-try-build.log 2>&1
cp builds/0/x2c /tmp/x2c-dual-phase7-post-try
```

Then run collect.py from the research checkout. It uses the final phase7
comparison/final-manifest.json as reference, explicitly sets X2C_HOME and
X2C_DUAL_PROFILE=1, and unsets the opt-in effect probe/count instrumentation.
Base-hashes.json and instrumented-source-hashes.json record source provenance;
patch-check.log records successful dry application in
/tmp/dual-phase7-post-patch-check. No full source snapshots are tracked.
