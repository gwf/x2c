> Status: done
> Graph serve implemented through `0420f333` on 2026-10-26. Focused parity
> and lifecycle acceptance passed. Normal publication uses agent-pr-check.
> The separate provenance investigation remains an unpublished scratch report.

# Serve reusable project analysis

## Design and scope

Add `x2c graph serve SNAPSHOT`: one foreground process loads one immutable
snapshot, builds entity/binding/relationship indexes, and answers ordered
newline-delimited JSON queries on stdio. Preserve the one-shot query schema
and response values. Report readiness on stderr. Invalid queries return JSON
errors without terminating the session. EOF closes the server.

The shared engine receives a session by value. A request owns its reachability
cache, Match plan, parsed JSON, results, and canonical allocations in an
isolated Context. The session builds all retained indexes before request
contexts open. No live compiler, automatic reload, background daemon, network
listener, or new semantic resolver is introduced.

Review confirmed the existing query evaluator needs only request-local mutable
state plus read-only indexes. Preserve one-shot lazy indexing. The server pays
relationship indexing at startup to keep all durable allocations in its own
lifetime. This trades startup and retained memory for repeated-query latency.

## Acceptance and delivery

Verify every query operation against one-shot output, recovery after invalid
JSON and query patterns, repeated distinct reachability queries, snapshot
replacement while serving, EOF, and an unterminated final line. Measure
startup, warm queries, and resident memory across hundreds of requests using
the same saved snapshot and queries for both execution modes. No recurring
memory threshold or new gate is added. Review the authored diff, then run the
existing publication gate and publish normally.

After implementation, another agent uses graph serve to investigate whether
compiler source-provenance data can be released earlier. Its queries, probes,
and report remain scratch artifacts. It must distinguish static reachability
from execution order and alias effects. No proposed production changes from
that experiment are implemented or published without later direction.


## Measured evidence

On Apple M4 Max, arm64, at `0420f333`, the same 179-unit saved snapshot and
identical query JSON were used for one-shot and persistent requests. Each
one-shot query ran three times; each warm query ran ten times. All responses
compared equal. Startup to the stderr readiness message took 6.851 seconds,
including datum loading and retained index construction.

| Query | One-shot median | Warm median | Total results |
| --- | --- | --- | --- |
| Find `Compiler.bind_syntax` | 3.800 s | 0.04569 s | 1 |
| Its transitive callees | 7.391 s | 0.16435 s | 3,611 |
| Calls within its AST | 3.951 s | 0.09266 s | 17 |

Traversal and Match returned ten rows with explicit truncation. Match used
`(expr ?type (call ?callee (args *args)))`. Warm timings exclude startup and
include request/response pipe transport. These are observed samples, not
latency guarantees or an isolated measure of algorithm speed.

Resident memory sampled with `ps -o rss` was 2,151,360 KiB at readiness,
2,248,624 KiB after 30 requests, 2,333,648 KiB after 100, 2,357,088 KiB after
300, and 2,357,424 KiB after 530. The mixed workload included repeated find,
traversal, and Match queries, distinct reachability queries, and invalid
operations. The last 230 requests added 336 KiB RSS. This bounded run supports
memory stabilization after warm-up; it is not an unbounded leak proof.

Raw inputs, revision, query files, and samples are retained locally under
`/private/var/folders/ys/92c9nxl16ds47h6mhvb9w_cm0000gt/T/x2c-serve-measure-9b8nkjfj`.
Snapshot construction overlapped unrelated host activity early in its run;
no snapshot-build performance comparison is claimed. The other graph process
finished before the paired query measurements.

Read-only review checked request ownership, immutable indexes, snapshot
replacement, and exception paths. It found a NUL-line recovery gap; moving
line decoding inside request handling fixed it while I/O failures still
terminate through the existing command diagnostic. Acceptance now includes
NUL followed by a valid request. No new publication gate was added.
