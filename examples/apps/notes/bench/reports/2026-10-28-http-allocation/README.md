# HTTP allocation cleanup: 64-client lookup

The production Notes database-mutex variant allocates less, uses less CPU per
request, and improves throughput in the balanced repeat. The experimental
database-thread variant uses slightly less CPU but loses throughput. Its
regression is reported without an explanation; the source and disassembly
review did not identify a compiler-optimization mismatch or lost JSON writer
specialization.

## Balanced repeat

M4 Max, 64 clients/workers, copied 1, 000-note SQLite fixture, GET /api/notes/1.
Four rounds per binary, one-second warmup and five seconds timed. Both pair
orders occur twice for each x2c architecture. Every sample is retained.

| Server | Median requests/s | Server CPU cores | CPU us/request | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Database mutex, before | 62, 467 | 3.08 | 49.98 | 4.713 |
| Database mutex, after | 67, 387 | 2.81 | 42.47 | 3.929 |
| Database thread, before | 67, 311 | 4.48 | 67.77 | 1.341 |
| Database thread, after | 59, 581 | 3.88 | 66.03 | 1.683 |
| Go | 65, 814 | 3.39 | 52.50 | 2.203 |

Database-mutex Notes: 62, 467 -> 67, 387 requests/s (+7.9%); 50.0 -> 42.5 CPU us/request
(-15.0%). Its throughput is approximately Go's in this run; CPU/request is
19.1% lower than Go. These measurements do not establish a reliable throughput
lead over Go.

Database-thread Notes: 67, 311 -> 59, 581 requests/s (-11.5%); 67.8 -> 66.0 CPU us/request
(-2.6%). Throughput decreased in three of the four repeat pairs. The fourth
pair had severe outliers (20, 312 before, 39, 393 after). Go also had a 47, 994 RPS
outlier; its other three samples were 65, 136-66, 600 RPS. This is a regression
signal for the experimental architecture, not evidence that every path sped
up or a diagnosis of its cause.

CPU includes all server threads. CPU cores are lifetime user+system CPU /
lifetime elapsed time. CPU/request divides that same CPU by warmup+timed
request counts, including startup/shutdown. The table contains per-sample
medians; it is not isolated timed-region CPU attribution.

## Allocation verification

Two repeated diagnostic traces of the third lookup on one warmed keep-alive
connection produced identical before/after response bytes and repeated counts.
The diagnostic runtime is separate from timed binaries.

| Operation per lookup | Before | After |
| --- | ---: | ---: |
| Native allocation calls (malloc/calloc) |118|91|
| Native realloc calls |51|43|
| Scope allocation requests |116|89|
| Scope control structures |2|2|
| Pool slot requests |41|35|
| Pool block leases |6|4|
| Storage mutex acquisitions |12|8|
| Pool instance mutex acquisitions |245|209|

Scope allocations and native allocation calls overlap; do not add them.
Pool requests are suballocations, not additional native malloc calls. Leases
reuse existing blocks. This one-request trace establishes operation counts,
not 64-client contention or time saved per eliminated operation.

## Change and compatibility

- Skip body buffer/catch setup for zero-length bodies after validating framing.
- Scan Connection tokens once without lowercase copies or split Arrays;
  preserve case-insensitivity, whitespace trimming, and close precedence.
- Validate and reuse an unescaped URL; use the original decoder for escapes.
- Match routes without capture Maps, then capture only for the winning method
  and path. Preserve fresh req.params replacement and existing empty Maps
  exposed by HttpRequest.read.
- Write JSON into the existing response Buffer through the same generic JSON
  writer, retaining key sorting, escaping and all Var.json/pretty_json behavior.
  An internal x2c_json_write helper connects the modules. HTTP failure cleanup
  empties partially encoded bodies; successful encoding precedes header update.
- Set known valid lowercase content-type entries directly for text/JSON.
- Use existing String.printf with a fixed native-long format for content length,
  preserving the String-valued header Map and its write-time updates.

All 28 HTTP function declarations and public type layouts are unchanged.
The retained initial query/params Maps are required by the current public
request representation; they were not replaced with NULL. Access logging is
unchanged and enabled in both languages. No storage, allocator, thread,
channel, database or block-size policy changed.

## Comparison controls and limits

Both x2c runtimes use exactly the same application objects, SQLite adapter and
native SQLite archive, naming-disabled Scope object, Pool fast path, fixture
and load generator. Allocation accounting is disabled. An archive member
comparison verifies only http.o and json.o changed (apart from archive index).
The objects also byte-match the implementation checked by author stage2.
Binary hashes, order, host load, individual CPU/RSS and latency data are in
comparison.json.

The integration agent held its own expensive work during timing. Other
workspaces on this Mac were observed running compiler checks and benchmarks;
the host was not fully quiet. An initial three-round run was noisy and is
retained in initial-comparison.json. Its mutex CPU improvement was also 15%,
while database-thread throughput decreased. The four-round repeat reverses
pair ordering to reduce time-order bias, but cannot remove this host limitation.
No samples were discarded from either retained dataset. Unexplained
experimental database-thread throughput behavior remains a limitation.

prepare.py uses the retained local pre-change application objects/archive and
current built HTTP/JSON objects; run.py uses its prepared binaries. These are
local reproduction scripts, not a new benchmark framework. Temporary artifacts
remain at the scratch path recorded in the result JSON.

## Verification and delivery

- make build passed.
- Focused accounting-off suites: 28 passed, 311 assertions.
- Focused accounting-on suites: 76 passed, 908 assertions.
- API documentation audits passed for HTTP (28 callables/5 types) and
  JSON (15 callables/2 types); the added JSON helper is classified internal.
- Both Notes API/concurrency/restart/CLI/store suites passed. Database-thread
  SQL error recovery and shutdown with queued writes passed.
- New coverage checks routing aliases, failed/wrong-method captures, wildcard
  empties, malformed escapes, connection precedence, empty bodies, and JSON
  partial-write failure followed by successful nested/escaped retry.
- Two independent authored-diff reviews found no concrete correctness issue.
- Author make stage-2 passed; integration agent owns the full publication gate,
  final bootstrap/API regeneration and publication.
