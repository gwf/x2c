# Build cost score

> Status: done 2026-09-23. `tools/build-scaling.py` and
> `make bm-build-scaling` run in the nightly performance snapshot, whose
> report opens with the score and a verdict. Guidance is in
> `agents/performance-checkpoints.md`.

## Goal

One number that says whether x2c got slower to build, independent of how
much code there is to build.

## Design

The score is instructions retired per source line for one stage build of
HEAD, as a percentage of a committed baseline. The report calls a rise of
2 points since the previous snapshot a regression.

## Evidence

Measured at `8c0b1a92` on the M4 Max host, load average 12 to 19 from other
sessions:

- Wall time of one serial stage build: scores 92 to 111 across four runs.
- CPU time: 75 to 99 across four runs.
- Instructions retired, counted per translator and C compiler process:
  100.1, 100.2, 100.1. One build retires about 137 billion instructions.
- `/usr/bin/time -l` counts only its direct child, so counting `make`
  reported 571 million; each tool process is wrapped instead.
- A first version reported four normalized rates and a pinned-tree
  translation time. It was replaced because the rows needed interpretation
  and gave no decision.

## Limits

Instructions do not see cache or memory stalls. A C compiler upgrade
changes the count and requires `--rebaseline`. The count depends on macOS
`/usr/bin/time -l`.
