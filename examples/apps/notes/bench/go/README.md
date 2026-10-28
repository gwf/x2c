# Go notes server

This server implements the Notes application's page and JSON API with Go's
`net/http`, `encoding/json`, and `database/sql`. It uses the same SQLite
schema and SQL statements as `examples/apps/notes/notes.x`. It is a complete
application for the comparison, including validation, search, tag counts,
updates, deletion, persistence, and access logging.

## Build

Use the prepared native SQLite dependency from the repository. The
`libsqlite3` build tag selects that library instead of the Go driver's
bundled SQLite source. From this directory, with Go on `PATH`:

```sh
SQLITE_PREFIX="$(python3 ../../../../../packages/tools/deps.py path \
  ../../../../../packages/sqlite/dependency.json prefix)"
CGO_ENABLED=1 CGO_CFLAGS="-O2 -g -I$SQLITE_PREFIX/include" \
  CGO_LDFLAGS="-L$SQLITE_PREFIX/lib" \
  go build -tags libsqlite3 -o /tmp/notes-go .
```

`go.mod` pins `github.com/mattn/go-sqlite3` to v1.14.52, and `go.sum` records
its module checksums. The implementation was checked with Go 1.27.3 and the
repository's SQLite 3.53.4 static library. No Go installation is required to
build or run the x2c Notes application.

From the repository root:

```sh
/tmp/notes-go --host 127.0.0.1 --port 8080 --workers 8 \
  --store /tmp/go-notes.db --public examples/apps/notes/public
python3 examples/apps/notes/tests/test_notes.py /tmp/notes-go
```

The CLI accepts the same address, port, worker setting, database path, and
public-directory options as the x2c application. `--help` prints usage.
Go's HTTP server schedules a goroutine for each connection. `--workers` is
accepted and validated for the shared command interface; it does not limit
Go's connection concurrency.

## Comparison conditions

One connection is retained with `SetMaxOpenConns(1)` and
`SetMaxIdleConns(1)`. A Mutex covers preparing each statement, reading and
copying its rows, and closing the statement. Statements are prepared per
operation. INSERT and UPDATE exhaust their `RETURNING` rows before sending
a success response. No statement or response cache is added.

The DSN explicitly selects `journal_mode=DELETE`, `synchronous=FULL`, and
`busy_timeout=0`. This overrides the Go driver's defaults of a 5000 ms busy
timeout and NORMAL synchronization. Startup logs report the native SQLite
version and effective settings. The validated build reports SQLite 3.53.4,
`journal=delete`, `synchronous=2`, and `busy_timeout=0`. `otool -L` confirms
that this build uses no system SQLite dylib.

JSON responses are buffered before headers and have an explicit
`Content-Length`. The input-body limit is 1 MiB. Read-header, read, and idle
timeouts are five seconds. Each completed request emits one stderr access
line with status and path. Go's standard logger formats this line; the x2c
Logger uses its own timestamp and field formatter. Their formatting costs
remain part of their measurements.

The servers use their ordinary language libraries. Go's regular expressions
use RE2 syntax and Unicode semantics; the x2c regex module is byte-oriented
and has a smaller supported syntax. Go's JSON encoder escapes HTML-sensitive
characters. Its decoder permits strings containing NUL, which x2c's JSON
reader rejects. Go's URL parser selects the first duplicate query value; x2c's
query Map keeps the last. Go's standard router and file server also supply
their normal redirect and directory handling. The shared tests cover the application contract. Compare
common regex patterns and the same ASCII note values for a read workload;
a passing application test does not establish identical behavior for every
parser or transport edge case.
