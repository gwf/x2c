> Status: needs author scoping
> Planned 2026-10-28 against `gwf/repo-survey-major-features-933090`
> (`f5d0eb2fb`). Nothing is implemented. The feasibility notes below come
> from reading `lib/` source; the compiler was not built for this plan.

# Networking runtime and a flagship service

## Requested behavior

x2c has no sockets and no HTTP server. Networking exists only through the
fetched `libuv` and `libcurl` packages, and the largest non-compiler program
is `examples/programs/literate-lisp.x` at 1026 lines. This plan adds:

1. `lib/net.x`: blocking TCP over the existing `File` abstraction.
2. `lib/http.x`: an HTTP/1.1 server with a router, JSON helpers, and a
   static-file handler.
3. `examples/apps/notes`: a notes service that uses collections, `match`,
   regions, exceptions, threads, channels, one compile-time record table,
   and a runtime Lisp policy hook, with a file store in core and a SQLite
   store as a package variant.
4. A pinned loopback benchmark against C and Go references.

Both modules are optional system modules like `path.x` and `json.x`: an
explicit `#include`, shipped and tested with the runtime, not part of the
prelude and not added to `scripting.x`. No event loop and no TLS enter core;
`libuv` stays the asynchronous package.

## Feasibility established from source

- `File.fdopen(int fildes, const char *mode)` exists in `lib/file.x`. The
  returned stream owns the descriptor; a failure raises `<io-fail>` and
  leaves the descriptor with the caller. `File.fileno` is in the protocol.
- `File.readline_into`, `File.read_into`, `File.read`, and `File.write_all`
  raise `<io-fail>` with the captured `errno` when stdio reports an error.
  A socket with `SO_RCVTIMEO` makes a timed-out `fread` fail with `EAGAIN`,
  so timeouts need no new reporting path: they are `<io-fail>` with
  `(errno EAGAIN)`.
- One `r+` stream on a socket is unsafe: stdio requires a positioning call
  between a read and a following write, and `fseek` fails on a socket. The
  module therefore holds two streams, `input` from the descriptor and
  `output` from `dup(fd)`, each in one direction.
- `Thread.stop` is cooperative. It sets `stop_requested` and broadcasts the
  registered condition; it does not interrupt native I/O (`lib/thread.x`,
  "Cooperative stopping"). `x2c_thread_wait_lock`, `x2c_thread_stopping`,
  `x2c_thread_cancel`, and `x2c_thread_wait_unlock` are public, so a blocking
  accept loop can poll with a short interval and observe a stop exactly as a
  `Channel` wait does. `Channel.receive` already wakes on stop, so workers
  that block on a `Channel` need nothing new.
- A started `Thread` must be joined and freed; `Thread.finish_all(pending)`
  joins an `Array` of handles and collects failures as `<join-fail>`.
  Workers start in the shared canonical pool with an isolated `Context`, so
  per-request `Context.open_isolated` inside a worker bounds temporary
  `String` and `List` storage (`docs/src/guide/contexts-and-threads.md`).
- `Job` in `lib/process.x` is the shape to copy for a native-resource class:
  `class Job { ... } *;` with `protocol Cleanup(Job)` and `$cleanup.by`.
- `grep` finds no `socket(`, `getaddrinfo`, or `SO_RCVTIMEO` under `lib/`
  or `src/`; nothing is reused or conflicted.
- Example checks are not part of `make check` (`Makefile`, "Example checks
  are optional"); `make verify` is. Gated coverage therefore lives in
  `unittest/`.
- On this Mac `wrk`, `go`, and `hey` are absent; `ab` is present.

## Phase 1: `lib/net.x`

### Surface

```x2c
#include "net.x"

Listener server = Listener.bind("::", 8080);     // dual-stack when the host allows
Socket peer = server.accept();                    // NULL after Listener.stop
peer.set_timeout(5000);                           // both directions, milliseconds
String line = peer.input.readline();
peer.output.puts("HTTP/1.1 200 OK\r\n");
peer.output.flush();
peer.close();

Socket client = Socket.connect("example.org", 80, 3000);
```

Public types and operations, documented with `/** */` comments so the module
page is generated:

- `class Listener { int fd; String host; int port; int stopped; } *` with
  `Listener.bind(String host, int port)`, `Listener.accept(Listener)`,
  `Listener.port(Listener)` (the bound port, so port 0 works in tests),
  `Listener.stop(Listener)` (callable from any thread; the blocked accept
  returns NULL within one poll interval), and `Listener.close(Listener)`
  (owner only, after the accepting thread has finished).
- `class Socket { int fd; File input, output; String peer; } *` with
  `Socket.connect(String host, int port, int timeout_ms)`,
  `Socket.adopt(int fd)` for a descriptor received elsewhere,
  `Socket.set_timeout(Socket, int ms)`, `Socket.shutdown_write(Socket)`,
  `Socket.peer(Socket)` (`host:port` text), and `Socket.close(Socket)`.
  Both classes adopt `Cleanup` so `auto` and `defer` release them.
- Reading and writing are `File` operations on `input` and `output`. No
  read or write wrappers are added; the `File` chapter already owns them.

### Decisions

- Name resolution: `getaddrinfo` with `AI_ADDRCONFIG`. `bind` tries each
  result in order; a `NULL` host means `AI_PASSIVE`. An IPv6 listener clears
  `IPV6_V6ONLY`. `connect` tries results in order with `SO_SNDTIMEO` for the
  connect timeout and raises the last `errno` as `<io-fail>`; a name that
  does not resolve raises `<not-found>` with the host.
- Accept blocks in `poll` with a 50 ms interval. Each wake checks
  `stopped` and the Thread stop request; a stop request raises through
  `x2c_thread_cancel` like a `Channel` wait. This reuses the stop contract
  instead of adding a wake pipe; the cost is up to 50 ms of stop latency.
- `SIGPIPE`: the first `bind` or `connect` sets `SIGPIPE` to `SIG_IGN`
  once. A write to a reset peer then raises `<io-fail>` with `EPIPE`. The
  guide states this process-wide effect.
- Accepted sockets set `TCP_NODELAY`; `output` is fully buffered and the
  HTTP layer flushes once per response.
- Errors follow `File`: `<bad-arg>` for null host text or an invalid port,
  `<not-found>` for a name that does not resolve, `<io-fail>` with
  `operation` and `errno` for every host failure.
- TLS is delegated. A TLS package supplies a `Socket` whose `input` and
  `output` are cookie streams (`funopen` on macOS, `fopencookie` on glibc)
  over its session object, created through `Socket.adopt` plus assignment
  of the two streams. `http.x` reads and writes only through those `File`s,
  so it is unchanged by TLS. A reverse proxy in front of the plain server is
  the documented deployment alternative.

### Tests, `unittest/test-net.x`

Bind `127.0.0.1` port 0, read the port, connect, exchange lines in both
directions, half-close and observe EOF, `set_timeout(100)` on an idle socket
raises `<io-fail>` with `EAGAIN`, `Listener.stop` from a second `Thread`
returns NULL from accept, `Thread.stop` on the accepting worker raises the
cancel cause at join, a bad port raises `<bad-arg>`, an unknown name raises
`<not-found>`, and `::1` when it binds (otherwise `TestHarness_skip`).
Register `net_suite` in `test-all.x`. About 450 lines of module and 250 of
tests.

## Phase 2: `lib/http.x`

### Book-chapter excerpt

```x2c
#include "http.x"

int main(void) {
  Map notes = {};
  Router routes = Router.new();
  routes.get("/api/notes/:id", %!(HttpRequest req, HttpResponse res) => {
    Var note = notes[req.params["id"]];
    if (note is void) Http.fail(404, "no such note");
    res.json(note);
  });
  routes.post("/api/notes", %!(HttpRequest req, HttpResponse res) => {
    Map note = req.json();
    notes[note["id"]] = note;
    res.status(201).json(note);
  });
  routes.files("/", "public");

  HttpServer server = HttpServer.new(routes, {port: 8080, workers: 8});
  server.serve();                       // blocks until server.stop()
  return 0;
}
```

A request arrives as an `HttpRequest`: `method` is a `Symbol` such as
`<GET>`, `path` is the decoded path, `query` and `headers` are `Map`s with
lower-cased header names, `body` is the `String` the `Content-Length` header
announced, and `params` holds the captures of the matched route. A handler
fills the `HttpResponse`: `status(code)`, `header(name, value)`,
`text(string)`, `json(value)`, or `bytes(block)` through a `Buffer`. The
server writes the response after the handler returns, with `Content-Length`
set from the buffered body.

A handler reports an expected failure with `Http.fail(status, reason)`,
which raises `%(http-fail (status 404) (reason "no such note"))`; the server
answers with that status and a JSON body `{"error": reason}`. Any other
`Error` that leaves a handler becomes a 500 response with no detail, and the
server logs the error's code and detail at `<error>` level in category
`<http>` through its `Logger`. Nothing has been sent when a handler fails,
because bodies are buffered, so the status is always honored.

### Decisions

- Parsing reads the request line and headers with `File.readline_into` on
  `socket.input`, then `File.read` for exactly `Content-Length` bytes. Limits:
  8 KiB request line, 64 KiB of headers, 1 MiB body by default
  (`body_limit` option). A malformed line answers 400, an oversize body 413,
  oversize headers 431, an unsupported method 405, a missing `Host` on
  HTTP/1.1 400. Chunked request bodies answer 411; chunked responses are not
  written. `Transfer-Encoding` support is out of scope.
- Router: segment matcher, not `regex.x`. A pattern is split on `/` once at
  registration; a segment starting with `:` captures one segment by name and
  a final `*rest` captures the remainder. Routes match in registration order
  within a method. Captures become `params`. This needs no compiled program
  per route, no byte offsets, and no `regex.x` include; a handler that needs
  a pattern inside a segment uses `regex.x` itself.
- Handlers are `Func` values of two parameters, so capturing lambdas carry
  application state. Direct functions bind as ordinary callables.
- Keep-alive: HTTP/1.1 keeps the connection unless `Connection: close`;
  HTTP/1.0 closes unless `Connection: keep-alive`. The idle read timeout is
  `idle_ms` (default 5000) through `Socket.set_timeout`; a timed-out or
  failed read ends the connection quietly.
- Concurrency: a worker pool fed by a `Channel`. The acceptor loop sends each
  accepted descriptor as an `<i32>` through `Channel.new(<i32>, workers)`;
  each of `workers` Threads (default 8) runs `foreach (int fd in channel)`,
  adopts the descriptor, and serves requests until the connection ends. Each
  request runs inside `Context.open_isolated_named("request")`, so its
  temporary Strings, Lists, and Maps are reclaimed per request, and the
  worker's outer storage holds only the `Socket`. The pool was chosen over a
  thread per connection because each `Thread` carries an 8 MiB stack, the
  bounded `Channel` gives backpressure with the kernel backlog holding the
  rest, and the `Channel` close-and-drain contract plus `Thread.finish_all`
  already define shutdown. `Thread.stop` wakes a worker blocked in the
  `Channel`; a worker inside a request finishes it first.
- Shutdown: `HttpServer.stop` calls `Listener.stop`; the acceptor returns,
  closes the `Channel`, and the server joins workers with
  `Thread.finish_all`, then closes the listener. `serve` runs the acceptor on
  the caller; `start` runs it on a Thread for tests and the flagship app,
  and `stop` then joins it too.
- `HttpServer.new(router, options)` takes a `Map` with `host` (default
  `"::"`), `port` (0 allowed; `server.port()` reports the bound port),
  `workers`, `idle_ms`, `body_limit`, and `logger` (default a stderr
  `Logger` at `<info>` logging one access line per request).
- JSON: `req.json()` is `Json.parse(req.body)` and raises `<malformed>` as
  `json.x` does, which the server maps to 400; `res.json(value)` sets
  `Content-Type: application/json` and `Var.json`.
- Static files: `routes.files(prefix, directory)` joins the remaining path
  under `directory` with `Path.join`, rejects any `..` segment with 404,
  requires `Path.is_file`, serves `index.html` for a directory, and sets
  `Content-Type` from a ten-entry extension table. Bodies are read with
  `Path.read_text` for text types and `File.read_into` otherwise.

### Tests, `unittest/test-http.x`

Parser tests run on `tmpfile` streams, with no sockets: request line, header
folding into lower-cased keys, query and percent decoding, `Content-Length`
body, each limit and its status, HTTP/1.0 and `Connection` decisions. Router
tests: literal, `:name`, `*rest`, order, 404 versus 405. Response tests:
status line, headers, `Content-Length`, JSON helper. One loopback
integration test: `HttpServer.start` on port 0 with two workers, requests
through `Socket.connect` covering a captured route, a POST with JSON, a
static file from `unittest/build/`, `Http.fail`, a handler that raises
`<bad-arg>` producing 500 and one `<error>` entry in a memory `Logger` sink,
two requests on one keep-alive connection, then `stop`. Register
`http_suite`. About 700 lines of module and 400 of tests. Both suites run
under `make verify`, hence `make check` and `agent-pr-check`.

## Phase 3: the flagship notes service

### Choice

The notes service was chosen over a metrics API and a link shortener because
it needs records with several fields, search, tags, a user interface, and a
store, so it exercises `Map`, `Array`, `List`, `match`, regions, exceptions,
threads and channels through the server, a compile-time record table, and a
runtime Lisp policy, while staying a program a reader recognizes.

### Layout

- `examples/apps/notes/notes.x`: the program, about 600 lines.
- `examples/apps/notes/record.x`: one compile-time table of note fields
  (`id`, `title`, `body`, `tags`, `created`, `updated`) and the macros that
  generate `struct Note`, `Note.to_map`, `Note.from_map` with validation
  errors, and the SQL column list. This is the derive-like mapping, written
  like `examples/magic/compile-time.x`.
- `examples/apps/notes/public/index.html` and `app.js`: a small page served
  by `routes.files` that lists, creates, searches, and tags notes.
- `examples/apps/notes/policy.xlisp`: a Lisp hook evaluated through
  `Lisp.new` and `$lisp.bind` as in `examples/magic/runtime.x`; it decides
  whether a note may be created, given its tags and size, so a policy can be
  changed without recompiling. It is optional: no file means allow.
- `examples/apps/notes/README.md`: run, API, and benchmark instructions.
- `examples/packages/notes-sqlite/`: the SQLite variant, reusing `record.x`
  and the handlers, with a `NoteStore` protocol implemented by
  `MapStore` (core) and `SqliteStore` (package). Its `Makefile` follows
  `examples/packages/http-json-releases`, and `make packages-check` runs
  its `test` target.

### Store and persistence

Core persistence is one JSON file: the store is a `Map` from id to note
`Map` under a `Mutex`; every mutation rewrites `notes.json` with
`Json.write_file` to a temporary path and `Path.move_to` for an atomic
replace. This keeps the gallery example inside `make examples` without a
network fetch. The SQLite variant stores notes in one table and uses
`Prepared` binding; it is checked by `packages-check`, outside `make check`,
as `packages/README.md` already states for SQLite.

### Routes

`GET /api/notes?tag=&q=` (`q` is a `regex.x` pattern over title and body),
`POST /api/notes`, `GET /api/notes/:id`, `PUT /api/notes/:id`,
`DELETE /api/notes/:id`, `GET /api/stats` (count per tag and total bytes),
and `GET /` for the page. Request bodies are validated through
`Note.from_map`; a validation failure is `Http.fail(422, reason)`.

### Example check

`apps/notes|showcase|run|--check|expected/apps-notes.stdout|...` in
`examples/manifest.txt`. With `--check` the program starts on port 0 with
two workers, runs a built-in client script over loopback (create three
notes, search, tag stats, a rejected note, delete), prints a deterministic
transcript, stops the server, and removes its temporary store. This makes
the check exercise `Socket.connect` as well. `examples/check.sh`
`list_sources` gains the `apps` directory. `make examples` remains optional,
as today.

### Benchmark

`examples/apps/notes/bench/` holds `load.x` (an x2c client: N threads,
keep-alive, `GET /api/notes/1` for a fixed duration, reporting requests per
second and p50/p99 latency), `server.c` (a C thread-pool server answering
the same route with a fixed JSON body), and `main.go` (`net/http` answering
the same route). `bench/run.py` runs each server on loopback, drives it with
`load.x` at 64 connections for 10 s, takes the median of 5 runs, and writes
`results/current.json` and `results/current.md`. `baseline.json` pins the
C and Go statistics to the SHA-256 of `server.c` and `main.go`, as
`examples/shootout/baseline.json` does, so an ordinary run measures only the
x2c server. The Go baseline is measured once on a machine with a Go
toolchain; this Mac has none, and the README records the date and machine.
`ab` is an optional cross-check, not the recorded tool. The benchmark is
informational and not gated; the README table records absolute requests per
second and the x2c/C ratio.

### Documentation

- `docs/src/guide/networking.md`, "Sockets and HTTP", after "Commands and
  Files" in `SUMMARY.md`: a listener and client, the server excerpt above,
  routing, errors and `Http.fail`, keep-alive and timeouts, the worker pool
  and `Context` per request, shutdown, and the TLS delegation statement.
- `docs/src/library/overview.md` gains "Serve HTTP" and "Open a socket".
- `make doc-generate` produces `library/modules/net.md` and `http.md` from
  the `/** */` comments; add both to `SUMMARY.md` and, if the generator
  lists modules explicitly, to its list.
- `site/src/content/examples/notes.md`, a custom page like
  `literate-lisp.md` pointing at `examples/apps/notes/notes.x`, and a
  `README.md` section in `examples/README.md` under "Further examples".

### Sizes and delivery

Phase 1 about 700 lines, phase 2 about 1100, phase 3 about 1500 including
documentation and the benchmark. Each phase is published to `dev` on its own
after `tools/gate-state.py ensure agent-pr-check`; phase 3's SQLite variant
and benchmark also run `make packages-check` and `bench/run.py` locally
before publication. The performance checkpoint applies to phases 1 and 2
because they add runtime modules; it is not expected to move compiler
throughput.

## Plan review

- Established facts relied on: `File` raises `<io-fail>` with `errno` on
  every failed read and write; `File.fdopen` ownership; `Thread.stop` is
  cooperative and `Channel.receive` observes it; `Channel` close drains;
  `Context` reclaims unexported storage; `Json.parse` raises `<malformed>`;
  `Path.join`, `Path.is_file`, and `Path.move_to` raise on host failure. No
  consumer rechecks these. The HTTP layer does not test `ferror` after
  `File` calls, does not null-check fresh collections, and does not validate
  descriptors it adopted from its own acceptor.
- Reuse and deletion: reading and writing reuse `File` entirely, so `net.x`
  adds no byte-moving code. Shutdown reuses `Channel` close and
  `Thread.finish_all`. JSON, paths, logging, argument parsing, and the Lisp
  session come from existing modules. Nothing is deleted. New lasting
  mechanisms: the two-stream `Socket` (required by stdio's read/write
  positioning rule), the polled accept (required because native I/O does not
  observe `Thread.stop`), the segment router (one `List` split per route),
  and the buffered `HttpResponse` (required so a failing handler can still
  change the status). Each is small and has a stated reason.
- Idiomatic x2c: resource classes follow `Job`; errors are raised causes with
  `operation` and `errno` details, not status codes; handlers are `Func`s
  and lambdas; requests and responses are ordinary `Map`s and `Buffer`s; the
  record table is a compile-time macro like the existing gallery example;
  no framework object model, middleware chain, or async abstraction is
  imported from another language.
- Validators, diagnostics, and negative fixtures: the HTTP limits (400, 405,
  411, 413, 431) protect the server from unbounded reads and from treating
  a partial request as complete; the `..` rejection in the static handler
  protects files outside the served directory; `Note.from_map` validation
  protects the store from records the page cannot render. `net.x` adds no
  validator beyond `<bad-arg>` for a null host or out-of-range port, which
  `getaddrinfo` would otherwise report as an opaque failure.

## Implementation steps

1. Phase 1: write `lib/net.x`, `unittest/test-net.x`, register the suite,
   run `make verify`, and review the authored diff against this plan before
   `tools/gate-state.py ensure agent-pr-check` and publication.
2. Phase 2: write `lib/http.x`, `unittest/test-http.x`, the guide chapter
   and overview sections, regenerate module pages, run `make verify` and
   `make doc-check`, review the diff, gate, publish.
3. Phase 3: write the app, record table, page, policy, manifest row and
   `check.sh` change, expected output, the SQLite variant and its Makefile,
   the benchmark with pinned baselines, the site page, and README updates;
   run `make examples`, `make packages-check`, and `bench/run.py`.
4. Before each publication validation, review the completed authored diff
   for facts already guaranteed by `File`, `Thread`, `Channel`, `Context`,
   and `Json`; for code that `File` or `Path` already supplies; for any
   helper, cache, or check that does not earn its keep; and for non-idiomatic
   shapes, and fix what the review finds before running the gate.
