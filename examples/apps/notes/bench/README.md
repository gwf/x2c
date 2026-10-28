# Notes loopback benchmark

Build a current development compiler, then run from the repository root:

```sh
python3 examples/apps/notes/bench/run.py --record-baseline
python3 examples/apps/notes/bench/run.py
```

The first command measures the C reference and, when installed, Go. It pins
both source SHA-256 values and records the host, date, workload, raw samples,
and medians in `baseline.json`. An ordinary run measures only x2c. Reference
ratios appear only when source hashes, host, client count, duration, and run
count match the pinned baseline. Run products and server logs stay in a named
`/tmp/x2c-notes-bench-*` directory for diagnosis.

The default workload is 64 connections for 10 seconds, repeated five times.
`load.x` uses one native Thread and one persistent Socket per connection. Each
client sends `GET /api/notes/1`, validates 200 and Content-Length, consumes the
body, and records the round-trip latency with a monotonic clock. Requests/s
uses actual elapsed time, including connection startup and worker completion.
The report gives median requests/s and median per-run p50/p99 microseconds.
It does not combine percentiles from different runs.

The notes server is seeded through POST with one note. It runs 64 workers so
all 64 keep-alive clients can make progress. Access logging and the file-store
lookup remain part of the measured service. The C reference uses 64 blocking
workers; the Go reference uses `net/http`. Both references return fixed JSON;
they do not perform the notes service's synchronized lookup, record copying,
and JSON encoding. The x2c/C ratio compares those stated workloads.

For a shorter smoke run:

```sh
python3 examples/apps/notes/bench/run.py --record-baseline \
  --connections 2 --seconds 1 --runs 1 --output /tmp/notes-bench-smoke
```

A smoke baseline is not comparable to the default workload. Regenerate the
baseline with the default arguments before reporting a full comparison.
`ab` can provide an independent cross-check; its results are not recorded here.
The benchmark is informational and has no gate or test threshold.

Go is absent on the implementation Mac. The baseline records that absence;
a measured Go comparison requires rerunning `--record-baseline` on a host
with Go. No Go result is inferred from C or x2c measurements.


## Recorded run

Measured 2026-10-28 on Apple M4 Max (Mac16,5), 128 GiB RAM, macOS 15.7.9
arm64. These are the default 64-client, 10-second, five-sample medians.

| Server | Requests/s | p50 us | p99 us | x2c/server |
| --- | ---: | ---: | ---: | ---: |
| x2c notes | 42,455.1 | 1,472 | 5,502 | 1.000 |
| C fixed body | 203,584.8 | 312 | 434 | 0.209 |
| Go fixed body | unmeasured | - | - | - |

The x2c/C ratio compares the complete logged lookup route with a fixed
response. See [the report](results/current.md) and
[raw samples](results/current.json). The Go toolchain was absent.
