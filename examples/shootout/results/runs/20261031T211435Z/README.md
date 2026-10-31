# Three idiomatic source improvements

Run `20261031T211435Z`, observed 2026-10-31 14:14 PDT / 2026-10-31 21:14 UTC, measures clean source
`3318f8d8aea057e95b9a9dbf1ccc09d8e7a36d4a`. Valid results first appear in report checkpoint
`9c8fbbe8bc2976c1e85db7e6259a847e91671374`; later archive/documentation commits preserve those bytes.
These are configured local measurements, not official published timings or
canonical-size timing.

## Full calibration

All 75 admitted programs pass official fixtures and local output checks.
56 fresh-process samples per program give 4,200 observations. Complete Latin
rotations balance coverage groups of 8, 7 and 4 programs. The same eight
problems are shared by all eight columns; per-problem tables retain all
available k-nucleotide and binary-trees entries. No missing cell is zero.

Measurement follows six consecutive ten-second aggregate-idle samples at
least 90 percent, after all builds and fixtures. Exact observations and process
receipts are preserved in `raw/` and `current.json`. Java includes fresh-JVM
startup and JIT; a separate warmup process does not warm measured JVMs.
The pre-run window does not establish zero background activity throughout. Brief
unrelated compiler/application bursts were recorded during the full run. The three
changed programs' quarter medians span less than 1.8 percent; their controlled
improvements come from the separate quiet source experiment. No observations were
removed. See `../../evidence/three-idiomatic/timing-review.json` and the preserved
process log; unchanged-program differences are not claimed as source gains.

## Controlled source experiments

Seven timed variants were compiled against the same compiler/runtime: the three
previous sources, three requested candidates, and a batched-serial Mandelbrot
control. All 142 official/edge/oracle checks pass. Padding/wave/cutoff dimensions
and the 47 saved reverse-complement oracle cases are included. Additional
per-workload parity checks precede timing. The 12-round quiet experiment has
372 observations and complete rotating orders for both two- and three-variant
groups. It is separate from this 56-sample full calibration. The earlier
int-index Buffer draft is retained as a review artifact; the tested Buffer
source uses ptrdiff_t/get and avoids the narrowing identified in review.

| Experiment | Input N | Before elapsed ms | Candidate elapsed ms | Before CPU ms | Candidate CPU ms | Paired wins / 12 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| regexredux | 100000 | 50.900 | 24.202 | 50.547 | 56.156 | 12 |
| revcomp | 100000 | 11.654 | 10.958 | 11.306 | 10.670 | 12 |
| mandelbrot | 512 | 9.899 | 4.369 | 9.591 | 12.153 | 12 |

CPU is total user plus system time, including workers. Parallel elapsed-time
wins consume more total CPU in these probes; the Buffer change reduces both.
All three local candidates win all 12 paired rounds. The larger workloads also
show gains. Small regex N=1000 increases about 0.090 ms; its serial N=6500 path
is unchanged within variation, while N=6600 benefits from the parallel path.

Regex-redux uses nine ordinary Threads for independent counts at cleaned
sequence lengths of at least 65,536 bytes. Each worker owns its Regexp and
retains only a scalar count. The main thread runs the ordered substitution
chain concurrently, joins workers, and prints counts in specification order.
Smaller inputs use the serial path. No Regexp or match-data block is shared.

Reverse-complement keeps the existing input Buffer through `_write`, instead
of converting each complete record into a canonical String. A native
`ptrdiff_t` cursor and the ordinary Buffer.get API avoid narrowing the Buffer
length to int. Complement rules, output lines and record order are unchanged.
The output-line Buffer still uses the existing ordinary String conversion.

Mandelbrot uses at most six ordinary Threads on 16-row chunks per wave at
N>=256. Caller-owned Arrays are filled before startup; each worker replaces
only existing byte-valued slots in its own Array. Joins precede ordered output.
The next wave releases the previous wave's storage, bounding retained output
to 96 rows. Pixel arithmetic and PBM padding are unchanged. Smaller inputs run
serially. A same-batching serial control separates threading from buffering.

The tuned sources and all 55 foreign reference programs remain unchanged.
No compiler/runtime/package code, typed container, borrowed substring, raw
collection access, custom allocator, or literal-C implementation was added.

## Docker and rejected timing attempts

Gary explicitly authorized temporarily pausing Docker, then restoring it.
The first full attempt passed output checks but late Contacts/Spotlight work
and another validation job overlapped timings. It is retained under the
experiment's `interfered-attempts/`, and supplies none of the final figures.
Docker was restored before waiting again. The guarded retry waits for other
work to settle while Docker runs, then bounds the actual pause-window wait.
Its finally block restores Docker immediately after measurement or an error,
before rendering and publication checks. Pause/resume and container-state
receipts are retained. The preliminary recent-ps readiness estimate is distinct
from the final aggregate-idle criterion. No other apps or jobs were paused.

## Recovery and website integration

- `current.json`, `current.md`, `baseline.json.gz`, `benchmarks.json`: exact run.
- `raw/`: original 4,200 observations, build/check/machine/summary receipts,
  quiet and process observations, log, and the exact one-off wrapper.
- `charts/`: three standard forms and `three-idiomatic-probes`, each in
  PNG/SVG/PDF, plus CSV data, renderers and provenance.
- `website.json`: curated metadata/measurements without host process listings.
- `../../evidence/three-idiomatic/`: before/candidate/control sources, generated
  C, inputs, build/check/oracle receipts, initial and quiet raw samples,
  decisions, Docker evidence, rejected timings and scripts.

To rerender focused probes, decompress `raw-quiet.jsonl.gz`, `build.json.gz`,
`decisions.json.gz` and `quiet-receipt.json.gz` from that evidence directory
into one temporary directory, then run `charts/render-probes.py INPUT_DIR OUT`.
Renderers read saved data only; they do not execute archived binary paths.
Use `../../requirements-charts.txt` for an isolated plotting environment.
The Docker-control wrapper is one-off host-specific evidence, not a recurring
benchmark requirement or an instruction to pause another computer's services.
Follow the normal suite instructions for collecting new data.

All earlier immutable runs remain unchanged. Verify `../../SHA256SUMS`;
see [recovery](../../README.md) and [website notes](../../../../../site/BENCHMARKS.md).
Canonical-size timing remains unrun. No website page or deployment was added.
