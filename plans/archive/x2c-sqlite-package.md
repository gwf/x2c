> Status: done
> Gary approved the running applications and interface on September 9, 2026.
> The ordinary client, embedded Lisp interface, examples, native profile, and
> documentation are delivered by the commit that archives this plan.
> Package checks and the integrated repository publication check pass.

# SQLite through ordinary x2c values

## Proposed tasks

1. Open a file or in-memory database, close it beside acquisition, choose
   ordinary read-only/read-write flags, and set a busy timeout. Expose the
   same native connection for advanced SQLite operations.
2. Prepare one SQL statement, bind positional or named parameters, execute it,
   and reset/reuse it. Bind Null, signed integers, real numbers, Strings, and
   Bytes without building SQL strings. Reject unsigned values outside SQLite's
   signed 64-bit integer domain instead of silently changing their value.
3. Stream result rows through ordinary iteration. Each row is a positional
   List, preserving duplicate column names and column order; expose names
   separately. Copy text/blob results before stepping again. Keep SQL NULL
   distinct from exhaustion. Text containing NUL remains available as bytes
   rather than silently truncating into String.
4. Group writes in a transaction, commit on success and roll back on Error.
   Reuse SQLite's transaction state and SQL operations; no ORM or second
   transaction engine. Nested transaction policy must be explicit.
5. Read change counts and last-insert row IDs, inspect native error codes and
   messages, and keep statement/database ownership visible. A live prepared
   statement borrows its connection; cleanup must not erase the original
   operation's failure.
6. Provide value-oriented embedded Lisp query/execute operations over a
   database filename, SQL, parameters, and positional rows where useful.
   Returned blobs need an ordinary byte reader. Native extension loading,
   virtual tables, custom collations and callbacks stay on the complete raw
   SQLite API for this first package.

The first draft called task 6 "compile-time Lisp". Source inspection shows
that existing package installers extend explicit embedded Lisp sessions;
they cannot install a native package into the compiler's interpreter. The
implementation follows that existing package model. Gary approved the implemented embedded interface with the running application
review. No native compiler-extension mechanism is introduced by this package.

## Short application sketch

The first example records the URL, HTTP status and latency fields already
used by `packages/libcurl/examples/endpoint-report.x`, then queries slow or
failed observations. It runs independently from networking on deterministic
sample observations. The broader example imports observation batches from a
file into a persistent database, uses a reusable parameterized insert within
one transaction, and streams a grouped report after reopening the database.
Both are new programs designed to establish this package's usefulness.

The intended starting shape is:

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

This application now compiles and runs as `examples/observations.x`. Binding
resets the statement and replaces all prior bindings; row exhaustion remains
distinct from a row containing SQL NULL. The observed report is: `/source: HTTP 200, 3100000 us`, followed by
`/reference: HTTP 503, 40000 us`.

## Implementation and evidence

Use the existing package Make/dependency/cache owners. Pin the released SQLite
3.53.4 amalgamation and public header (verify archive and header hashes), keep
upstream notices and the full raw header shim, and initially verify macOS.
No system installation, package registry or new recurring gate is proposed.
The ordinary client should be one package entry over connection/statement
owners, with SQL's own types and statuses visible through existing x2c values.

Prove the short application first, then file persistence/reopen, prepared
reuse, transaction rollback, duplicate columns, empty results vs NULL, numeric
boundaries, copied text/blobs and empty blobs, native errors and cleanup.
Exercise actual imported operations and Lisp value traversal, then run the
existing optional package check and root publication proof. Package acceptance
and supported-release status remain Gary's application-review decision.

Upstream references: [C interface](https://www.sqlite.org/cintro.html),
[binding values](https://www.sqlite.org/c3ref/bind_blob.html),
[result values](https://www.sqlite.org/c3ref/column_blob.html), and
[release downloads](https://www.sqlite.org/download.html).

## Plan review

SQLite owns statement parsing, parameter indices, column types, transaction
state, and native statuses. The client reuses those facts and adds no SQL
parser, row-schema inference or ORM. Connection and statement wrappers are
needed only for native lifetime, ordinary values and errors; copied row Lists
avoid borrowed-pointer invalidation and preserve positional SQL semantics.
Checks belong at conversion/ownership boundaries: unsupported unsigned range,
NUL text-to-String loss, stale handles and native failures. They protect real
value loss or unsafe native access, rather than validating internal ASTs or
rechecking established SQLite results. No new recurring test is proposed.

## Current verification

The short application, persistent import/report application, and embedded Lisp
application run successfully. The 15 raw, ordinary, and Lisp tests pass with
133 assertions. A consumer outside the repository builds and runs the short
application using the documented package and native-header paths. Native
profile/header checks and the existing seven-package check pass. Evidence is
in `debug/sqlite-final-tests.log`, `debug/sqlite-acceptance.log`,
`debug/sqlite-outside-consumer.json`, and `debug/sqlite-all-packages.log`.
`tools/gate-state.py ensure agent-pr-check` also passes; its full log is
`debug/sqlite-integrated-gate.log`. Gary accepted the running applications
and interface on September 9, 2026.
