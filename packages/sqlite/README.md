# SQLite

Store ordinary x2c values in a file or in-memory SQLite database, bind
parameters without constructing SQL strings, and stream copied row Lists.
The complete pinned SQLite C interface remains available for advanced use.
The interface is accepted and verified on macOS.

## Start with an observation report

```x2c
import "sqlite" with Database, Statement;

int main(void) {
  Database db = Database.open(":memory:");
  defer db.close();
  db.execute("CREATE TABLE observation(url TEXT, status INTEGER, us INTEGER)");
  Statement insert = db.prepare("INSERT INTO observation VALUES (?, ?, ?)");
  defer insert.free();
  foreach (List reading, %(
    ("/guide" 200 12000)
    ("/reference" 503 40000)
    ("/source" 200 3100000)
  )) insert.bind(reading).execute();

  Statement report = db.prepare(
    "SELECT url, status, us FROM observation "
    "WHERE status >= 400 OR us > ? ORDER BY us DESC"
  );
  defer report.free();
  report.bind(%(3000000));
  foreach (List row, report)
    printf("%s", %"${row[0]}: HTTP ${row[1]}, ${row[2]} us\n");
  return 0;
}
```

Expected output:

```text
/source: HTTP 200, 3100000 us
/reference: HTTP 503, 40000 us
```

From the repository root, with the compiler built:

```sh
make -C packages/sqlite prepare
make -C packages/sqlite build short-example example lisp-example
make -C packages/sqlite test run run-lisp
```

The short application is [observations.x](examples/observations.x).
[observation-history.x](examples/observation-history.x) reads a file of URL,
HTTP status, and latency fields, inserts the batch in one transaction, then
closes and reopens the database to report counts, failures, and latency by URL.
Its optional arguments select the input file and database filename. Repeated
runs append observations. The `run` target starts from a fresh example database
for reproducible output.

## Connections, statements, and values

`Database.open(path)` opens or creates a database; use `":memory:"` for an
in-memory one. `open_with(path, flags)` accepts SQLite's own open flags, and
`busy_timeout(milliseconds)` sets SQLite's lock-wait timeout. `native()`
returns the same connection for advanced C calls. Release native resources
with `defer` beside acquisition; free prepared statements before closing the
connection. Wrapper storage belongs to the active Scope. Use each statement
and connection on one thread at a time.

`prepare(sql)` prepares one statement. `bind(values)` resets the statement,
clears old parameters, and binds a positional List. `bind_named(values)` does
the same for a Map whose String keys are SQLite parameter names, including
`:`, `@`, or `$`. Both binding methods require every parameter; bind Null
explicitly for a SQL NULL value. `reset()` keeps the current bindings for
another execution.
`execute()` consumes results until completion. `Database.execute(sql)` runs
SQL directly, including batches without bound parameters.

Iteration consumes the statement's rows; `next()` also returns one row List
at a time, or NULL at exhaustion. Each row is a copied positional
List; duplicate column names and column order are preserved. `columns()`
returns the separate names. Exhaustion stays exhausted until reset or
rebinding.
Do not interleave iterators or reset a statement during iteration.

| SQL value | x2c value |
| --- | --- |
| NULL | `Var.null()`, distinct from end of rows |
| INTEGER | Signed 64-bit integer |
| REAL | `double` |
| TEXT | Canonical `String`; text containing NUL returns `Bytes` |
| BLOB | Copied `Bytes`, including empty blobs |

Binding accepts Null, signed integers, unsigned integers within SQLite's
signed 64-bit range, floating values, Strings, and Bytes. Larger unsigned
integers, NaN, and finite values that overflow SQLite's double representation
raise `conv-range`. Text and blobs are copied into SQLite at binding;
returned values survive another step, reset, or statement release. Returned
Bytes belong to the Scope active when the row was read. SQL TEXT containing
NUL and SQL BLOB both become Bytes; use SQL `typeof(column)` when that storage
class distinction matters.

`changes()` reports rows changed by the most recent INSERT, UPDATE, or DELETE;
`last_insert_rowid()` reports the connection's last inserted row ID.

## Transactions and failures

`db.transaction(%!() => { ... })` begins a transaction, calls the body, and
commits on success. An Error rolls back and preserves the original Error
even if
cleanup also fails. Nested transactions are rejected; use SQLite's raw SQL
savepoints explicitly when that policy is needed. Do not commit, roll back,
or close the connection inside the managed transaction body.

Native failures preserve the SQLite result code, message, and operation in
structured Error details, with a native SQL error offset when available.
Null, closed, or freed wrappers are rejected
before use.
`Statement.free()` and `Database.close()` are idempotent while their wrapper
storage remains alive. Cleanup does not re-raise a statement's already reported
execution error. Drive `execute` or iteration to completion, or call `reset`,
to observe deferred execution failures before cleanup; freeing a partially
consumed result is not a completion guarantee. Closing invalidates the wrapper.
Free statements before closing the connection, including when using native
handles.

## Lisp

`SqliteLisp.install(lisp)` adds `sqlite-query`, `sqlite-execute`,
`sqlite-null`,
`sqlite-null?`, `sqlite-bytes`, and `sqlite-bytes-list` to an embedded Lisp
session. Query and execute take a database filename, SQL, and a parameter List.
Each call opens and closes its own connection; use a file to retain data
between calls. Query returns a List of row Lists, so ordinary `car`, `cdr`,
and `length` can inspect results. The byte helpers convert between Bytes and
Lists of integers from 0 through 255. SQL NULL remains distinct from Lisp nil.
See [inline-lisp.x](examples/inline-lisp.x).

## Native profile and distribution

SQLite 3.53.4 is built from its pinned amalgamation with `SQLITE_THREADSAFE=1`
and upstream defaults, linked statically with the platform threading and math
libraries. Extension loading remains disabled per connection unless explicitly
enabled through the raw API. Optional compile-time SQLite modules are not
added. [PROFILE.md](PROFILE.md) records source/header hashes, options, native
linkage, and license information. The package is initially verified on macOS.

The public `sqlite-3.h` shim includes the complete pinned `sqlite3.h`; raw
functions, constants, callbacks, and handles retain their SQLite spelling.
Virtual tables, custom collations, native extension loading, backups, and
other advanced operations use that interface. `Statement.native()` exposes
the same prepared statement. Native handle users retain SQLite's lifetime,
threading, and callback obligations.

For an application outside this repository:

```sh
/path/to/x2c build --package-dir /path/to/x2c/packages \
  --c-system-dir /path/to/x2c/packages/sqlite/deps/include \
  --output report report.x
```

Keep the prepared package's source, generated header/archive, link file, and
native dependency prefix together. The book's source-package recipe also
applies: distribute this directory with `package.mk`, `dependency.mk`, and
`tools/deps.py`; prepare its dependency in the consumer's selected cache.
No system SQLite installation is required.
