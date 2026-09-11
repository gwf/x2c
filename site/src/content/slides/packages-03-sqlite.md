---
slug: sqlite
section: packages
tab: SQLite
title: Find the requests that need attention.
links:
  - label: Full source
    href: https://github.com/gwf/x2c/blob/main/packages/sqlite/examples/observations.x
  - label: Package guide
    href: https://github.com/gwf/x2c/blob/main/packages/sqlite/README.md
---

<!-- ignore: source excerpt; the complete example requires its optional package and setup. -->
```x2c,ignore
import "sqlite" with Database, Statement;

// The database and table are already open.
Statement insert = db.prepare(
  "INSERT INTO observation VALUES (?, ?, ?)"
);
defer insert.free();
foreach(List reading, %(
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
foreach(List row, report)
  printf("%s", %"${row[0]}: HTTP ${row[1]}, "
    + %"${row[2]} us\n");
```

Query endpoint observations with a bound parameter, then iterate over
copied row Lists. The report selects requests that either failed or took
more than three seconds, with the slowest first. Bind the threshold as a
value to change it without rebuilding the SQL string.

The complete example creates an in-memory database and inserts three
observations. Two need attention: `/source` succeeds but takes 3.1 seconds;
`/reference` returns HTTP 503. The fast, successful `/guide` request stays
out of the report. Deferred cleanup releases each statement and closes
the database.

Output:

```text
/source: HTTP 200, 3100000 us
/reference: HTTP 503, 40000 us
```
