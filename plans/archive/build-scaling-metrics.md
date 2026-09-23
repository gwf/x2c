# Build cost score

> Status: done 2026-09-23. `tools/build-scaling.py` and
> `make bm-build-scaling` run in the nightly performance snapshot, whose
> report opens with the score and its change. Guidance is in
> `agents/performance-checkpoints.md`.

## Goal

One number that says whether x2c got slower to build, independent of how
much code there is to build.

## Design

The score is the median CPU cycles per source line of three stage builds of
HEAD, as a percentage of a committed baseline. The report shows the score
and its change since the previous snapshot, without an alert threshold.

## Measurement choice

Measured on the M4 Max host, load average 9 to 19 from other sessions:

| Measure | Spread for one tree |
| --- | --- |
| Wall time, one serial build | 92 to 111 |
| CPU time, one build | 75 to 99 |
| Cycles, one build | 5.5% |
| Cycles, median of three | 3.7% |
| Instructions retired, one build | 0.2% |

`/usr/bin/time -l` counts only its direct child, so each translator and C
compiler process is wrapped.

## Backtest

Each commit was built with its own stage 0 from the private pre-release
history and scored in cycles per line, 100 at `97c2a9e1f`:

| Commit | Change | Lines | Cycles score | Instruction score |
| --- | --- | ---: | ---: | ---: |
| `97c2a9e1f` | #211 | 48437 | 100 | 100 |
| `94be93c16` | #220 | 48019 | 102 | 101 |
| `7496523be` | #231 typed map generation | 48539 | 128 | 126 |
| `d65acbb02` | #230 context-backed threads | 50246 | 176 | 165 |
| `ff7cc3125` | #241, after #234 | 50206 | 187 | 160 |
| `0fc7c0c8b` | #266 | 49744 | 186 | 159 |
| `1e0c90458` | #265 registry index | 49830 | 140 | 158 |
| `9fdd895c4` | #270 | 49863 | 141 | 156 |

The cycle score shows the known #230 regression and the #265 fix.
Instructions miss the fix, which removed memory stalls rather than
instructions. The #231 rise of 28 points was not noticed at the time and was
not investigated here. `e0fe15a68`, a merge of dev into a feature branch
before #234, scored 267 and is left out as unexplained.

## September replay

Replayed on 2026-09-23; these rows seed `replay.csv` for
`tools/build-scaling-history.py`,
in time order, with `b4b64c72` at 100:

| Commit | Date | Lines | Score | Note |
| --- | --- | ---: | ---: | --- |
| `4235c383` | 09-05 | 54078 | 127 | first public commit |
| `92a4c5a4` | 09-10 | 58484 | 89 | speedup, cause not identified |
| `26192820` | 09-13 | 60597 | 95 | |
| `1f6e3eaa` | 09-17 | 67498 | 111 | |
| `fd94c088` | 09-17 | 65741 | 115 | |
| `6bedf868` | 09-17 | 65569 | 110 | |
| `057b7648` | 09-17 | 66439 | 237 | Match plan cache broken by `8278d3fe` |
| `864beef8` | 09-18 | 69247 | 114 | after the `90685897` fix |
| `be34b485` | 09-20 | 71055 | 83 | speedup, cause not identified |
| `2d188c42` | 09-22 | 75505 | 88 | |
| `cdeadd9b` | 09-22 | 75482 | 90 | |
| `db86d4b7` | 09-22 | 76923 | 94 | meta recovery merge |
| `4a9096f8` | 09-22 | 77553 | 94 | |
| `b4b64c72` | 09-23 | 78206 | 100 | |

Total cycles grew 14% while source grew 45%. The rise since 09-20 came in
several steps of 4 to 7 points during the meta work and was not profiled.

## Limits

Line counts barely changed across the backtest window, so the assumption
that cost grows in proportion to source lines is not yet tested. A C
compiler upgrade changes cycle counts and requires `--rebaseline`. The count
depends on macOS `/usr/bin/time -l`.
