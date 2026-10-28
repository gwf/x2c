# Notes with a dedicated database thread

`threaded-notes.x` runs the same Notes API with one thread that opens, uses,
and closes the SQLite connection. HTTP handlers send database requests to a
bounded Channel and wait on a separate reply Channel for each request. The
ordinary `notes.x` application keeps its Mutex design.

This executable is a benchmark alternative. It uses the same CLI, schema,
prepared SQL, native SQLite package, browser assets, validation, response
logging, and durable-write completion as the ordinary application. It does
not add an application database Mutex or serialize response JSON in the
database thread.

## Build and check

After building x2c and preparing the SQLite package, run from the repository
root:

```sh
make -C packages/sqlite build
SQLITE_PREFIX="$(python3 packages/tools/deps.py path \
  packages/sqlite/dependency.json prefix)"
./builds/0/x2c build -O2 -o /tmp/threaded-notes \
  --package-dir packages --c-include-dir packages/sqlite/src \
  --c-include-dir "$SQLITE_PREFIX/include" \
  examples/apps/notes/bench/threaded-notes.x
python3 examples/apps/notes/tests/test_notes.py /tmp/threaded-notes
python3 examples/apps/notes/bench/test-threaded.py /tmp/threaded-notes
```

The first check exercises the shared API, CLI, concurrent creation,
persistence across restart, and incompatible-store behavior. The second uses
SQLite triggers to cause one statement failure and to keep writes outstanding
while SIGTERM stops the server. It verifies error replies, subsequent
recovery, and completion of accepted writes during shutdown. These checks are
separate from timed measurements.

For interactive use, start `/tmp/threaded-notes` from the repository root.
The default address is <http://127.0.0.1:8080/> and the database is `notes.db`.
The same `--host`, `--port`, `--workers`, `--store`, and `--public` options
select other values.

## Request lifetime

Before sending a job, its HTTP handler creates a child output Scope and a
buffered reply Channel with capacity one. The handler keeps the job record,
input arguments, output owner, and canonical Pool alive while it waits.
Only the database thread allocates into that output owner.

For each job, the database thread temporarily selects the output Scope with
`Scope.push` and borrows the handler's Pool through `x2c_pool_exchange`. It
prepares, steps, copies rows, and finalizes the statement there. It restores
its own Scope and Pool before posting the reply. The terminal send uses a
cached Channel handle and performs no later reads of the borrowed job.
The HTTP handler then constructs note Maps, filters lists, computes tag
statistics, and encodes the response. Its existing request Context reclaims
the output child and canonical values when the request ends.

SQL failures copy Error details into the same request owners with
`Error.snapshot_in` before the catch arm ends. The HTTP handler raises that
cause after receiving the reply, using the ordinary HTTP error response.
If allocating the terminal reply message fails before delivery, the database
thread records that failure and closes the reply Channel to wake the caller.
Initialization reports database-open and schema failures through this same
request path before the HTTP server starts.

Normal shutdown closes the HTTP server and joins its handlers first. It then
closes the database request Channel, joins the database thread, and frees the
Channel. The private synchronous borrow therefore ends before its owners are
released; shutdown does not use `Thread.stop` on a waiting handler.

Per-request Channel construction, output Scopes, and queue handoffs add work.
Benchmark this executable against an equally optimized ordinary Notes build
and the same SQLite archives, fixtures, clients, logging, and workload before
drawing a throughput conclusion.
