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
- the build cost score from `make bm-build-scaling`;
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

## Build cost score

The stage 3 time grows when the compiler gets slower and when there is more
code to compile. The build cost score removes the second cause. Each snapshot
builds one stage from HEAD three times with `make bm-build-scaling`, takes
the median child-inclusive CPU seconds around the waited `make`, and divides
by authored source lines. Generated `src/linked-meta.x` and `lib/x2c.x`
lines are reported separately, with the total. The score is that cost per
authored line as a percentage of the baseline in
`unittest/benchmarks/build-scaling-baseline.json`.

Scores carry metric and baseline IDs. Snapshot reports compare build-cost
scores only when both IDs match; the old driver-cycle baseline and history
remain identifiable as legacy data. The baseline records the calibration
source tree and informational compiler/toolchain provenance. After the
measurement correction, rebaseline in a quiet window with a fixed translator:

```sh
tools/build-scaling.py --rebaseline --ref COMMIT --compiler /path/to/x2c
```

The first lines of `latest.md` show the score and its change since the
previous snapshot. A rise means the commits in between made each line more
expensive to build. Repeat scores of one tree span about 4 points under
heavy host load, so smaller changes are noise. Replayed over the August
2026 Pool.promote regression, the score rose from 128 to 176 at #230 and
fell from 186 to 140 at the #265 fix. Instruction counts are steadier but missed the fix, because
that slowdown was memory stalls.

`tools/build-scaling-history.py` prints saved metrics as CSV without building.
It keeps rows with different metric or baseline IDs separate. Explicit
`--replay COMMIT...` builds only the requested commits and saves CPU rows in
`replay-child-cpu-v1.csv`; it leaves legacy `replay.csv` intact.

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

Compare only converged trees. After an incremental `make build`, the
compiler's identity no longer matches the prelude interface stage 0 wrote,
so every translation walks the prelude source; on 2026-09-30 that made two
good changes look 32% and 50% slower. Run `make bootstrap-refresh && make
build-safe` in each tree and check that `builds/0/x2c env` prints a
non-empty `prelude`. Then compare instruction counts from alternating runs
of the same inputs.

Specialized full Map campaigns and the Match-cache acceptance benchmarks
remain change-triggered. They are not part of the nightly snapshot.

Run snapshots in quiet windows. Do not benchmark while another agent is
building or profiling in the same checkout or while the host is under an
unrelated sustained load.
