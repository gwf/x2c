# Performance checkpoints

Performance evidence is advisory and separate from the correctness publication
gates. A failed or missing snapshot does not weaken `agent-pr-check`, and a
green correctness gate is not performance evidence.

## Nightly development snapshot

Run one successful snapshot of `origin/dev` per local day in a clean, isolated
checkout on the calibrated Apple M4 Max host:

```sh
make performance-snapshot \
  PERFORMANCE_ARGS="--ref origin/dev --fetch --skip-if-success-today"
```

The command prepares a fresh bootstrap without timing it, then records:

- the clean four-stage build time and all stage comparisons;
- the language shootout's structured results and raw samples;
- every focused runtime observation in `bm-all`; and
- the representative compiler-translation CSV and medians.

Each run has an immutable directory beneath `runs/YYYY/MM/DD/`.
`history.jsonl` retains a compact longitudinal row, `latest-attempt.json`
records the latest attempt, and `latest.json` and `latest.md` change only after
success. The Markdown report compares headline measurements and the ten largest
runtime-suite changes with the preceding successful snapshot. By default these
live under the main checkout's ignored
`debug/performance-history/`, even when the command runs from a linked
worktree. Pass `--output-root` when another persistent location is needed.
Only one snapshot may write that history at a time, and each suite command has
a two-hour timeout so a hung nightly run records failure and releases the next
attempt.

## Authored changes

Run a performance checkpoint before publishing a coherent batch that changes
compiler throughput, generated-code performance, runtime hot paths, build
orchestration, or that claims a performance improvement. Documentation,
tests-only work, generated-only refreshes, and plainly non-hot-path changes do
not need one. Commit the exact candidate tree before measuring it.

During the initial baseline period, inspect and report deltas without making
them a publication gate. Establish regression thresholds only after at least
one to two weeks of fixed-host observations. Confirm a suspected regression
with a same-host rerun before treating it as real.

Specialized full Map campaigns and the Match-cache and Lisp-AUTO acceptance
benchmarks remain change-triggered. They are not part of the nightly snapshot.

Run snapshots in quiet windows. Do not benchmark while another agent is
building or profiling in the same checkout or while the host is under an
unrelated sustained load.
