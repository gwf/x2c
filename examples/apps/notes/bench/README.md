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
