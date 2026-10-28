# Notes lookup load

After preparing SQLite and building x2c, run from the repository root:

```sh
python3 examples/apps/notes/bench/run.py
```

The runner builds Notes, starts a fresh database, creates one note through
POST, and drives GET /api/notes/1 over persistent loopback connections.
Each request performs a prepared SQLite lookup and encodes the returned
note as JSON. Access logging remains enabled. The default is 64 clients,
10 seconds per sample, and five samples. The HTTP worker count matches the
client count because each persistent connection occupies a worker.

`load.x` records each complete request's latency using a monotonic clock.
Requests/s uses actual elapsed time, including connection startup and worker
completion. The report gives median throughput and median per-sample p50/p99
microseconds. It does not pool percentiles from different samples.

Results are written to results/current.json and results/current.md, including
raw samples, source hashes, date, host, and SQLite version. Build products and
server logs remain in the named temporary directory for diagnosis. There is
no performance threshold or gate.

For a smoke run:

```sh
python3 examples/apps/notes/bench/run.py \
  --connections 2 --seconds 1 --runs 1 --output /tmp/notes-load
```

## Comparing another implementation

A Go or JavaScript version must implement the same API and perform the same
database work before a throughput comparison is meaningful. Use the same
native SQLite version and build options, schema, SQL, dataset, journal and
synchronous settings, connection count, logging, and request workload.
Notes uses one connection protected by a mutex and SQLite's default durable
journal settings. Set the other implementation's connection count explicitly.
A different SQLite engine or different durability settings changes the work
being compared.

This lookup workload measures a complete read route. Add separately reported
create/update/delete workloads when comparing durable writes. A fixed JSON
response does not perform the same operation. No cross-language performance
claim is made by this load tool.

## x2c versus Go

The [Go server](go/README.md) implements the same Notes operations with
`net/http`, `database/sql`, and the same native SQLite library. Build it as
that README describes, then run from the repository root:

```sh
python3 examples/apps/notes/bench/compare.py --go-binary /tmp/notes-go \
  --go-tool go --output examples/apps/notes/bench/reports/current
```

The comparison builds the x2c application, SQLite adapter, and common load
client with `-O2`. Go uses its ordinary optimized build, with Cgo's default
`-O2 -g` preserved. The pinned native SQLite library is already built with
`-O2`. The comparison does not change the application architecture or its
ordinary build defaults.

Both executables first pass the same external Notes tests. Preflight compares
normalized lookup, list, stats, and update results from copies of one fixture.
Recorded runs use 1,000 notes, one database connection, DELETE journaling,
FULL synchronization, and access logging in both servers. SQL statements are
prepared per operation. There is no response or statement cache. The logging
formatters differ, and their cost remains in each application's result.

The default matrix is lookup and update at one and 64 persistent clients.
Each server sample starts from an identical database copy, warms up for one
second, and runs for five seconds. Five pairs alternate execution order; the
first server is counterbalanced across cases. The update client uses a unique
fixed-width title on every request, so updates change database contents.
Request formatting is outside the round-trip timer but inside the throughput
interval. Geometric sample recording occurs between requests.

JSON records every sample, source/binary/native-library hashes, toolchain
versions, order, and host load. CPU and peak RSS cover the server's full
lifetime, including startup, warmup, and shutdown. Client CPU covers its full
process lifetime, including sorting samples; it is a saturation diagnostic,
not timed-request CPU. Latency values are closed-loop round trips measured by
the common client on the same host.

These are matched ASCII lookup/update workloads. The ordinary Go and x2c
libraries differ for Unicode regular expressions, escaped NUL, duplicate query
parameters, and path redirects, as documented with the Go implementation.
A shared-host application comparison does not isolate intrinsic language speed.

Dated reports live under [reports/](reports/). No benchmark is added to a gate.

The [2026-10-28 report](reports/2026-10-28/interpretation.md) contains the
measured comparison and its limits. Go led all five 64-client lookup pairs;
x2c led all five single-client lookup pairs and used lower peak RSS in every
pair. Durable-write results were too variable to rank. The dated directory
retains the full matrix, paired ratios, build/configuration verification, and
raw samples; no slow samples were removed.
