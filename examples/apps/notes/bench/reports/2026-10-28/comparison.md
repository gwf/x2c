# x2c and Go notes servers

Read [the interpretation](interpretation.md) alongside this table.
The durable-write samples do not establish a stable winner.

2026-10-28T18:33:49.423148+00:00

macOS-15.7.9-arm64-arm-64bit-Mach-O, 16 logical CPUs; 1000 notes.
Timed samples 5s, warmup 1s, 5 alternating pairs.

| Workload | Clients | Server | Requests/s | p50 us | p99 us | Peak MiB |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| lookup | 1 | x2c | 27616.3 | 36.0 | 57.0 | 4.0 |
| lookup | 1 | go | 25754.0 | 37.0 | 67.0 | 19.2 |
| lookup | 64 | x2c | 41263.8 | 1431.0 | 5050.0 | 11.8 |
| lookup | 64 | go | 58905.5 | 1095.0 | 3659.0 | 23.2 |
| update | 1 | x2c | 2226.6 | 248.0 | 2709.0 | 6.5 |
| update | 1 | go | 1985.0 | 246.0 | 2177.0 | 20.3 |
| update | 64 | x2c | 1398.3 | 14731.0 | 211823.0 | 16.8 |
| update | 64 | go | 2177.9 | 14838.0 | 231722.0 | 23.5 |

Rates and latency columns are medians of per-sample results.
Peak RSS covers each server lifetime, including startup and warmup.
Both use one native SQLite connection, the same copied fixture and SQL,
DELETE journaling/FULL synchronization, and per-request access logging.
PUT titles change on every request; these are real database updates.
The common closed-loop client runs on the same shared host. CPU/load
details, lifetime server CPU, load-process CPU, and every sample are in JSON.
This compares these applications and bindings on this host.
