---
slug: service
section: power
tab: service
title: A real service, no framework harmed.
links:
  - label: Complete source
    href: https://github.com/gwf/x2c/blob/main/examples/apps/notes/notes.x
---

<!-- ignore: excerpt of the notes service; the full program needs the sqlite package. -->
```x2c,ignore
import "sqlite" with Database, Prepared;
#include "http.x"

class Notes { Database db; Mutex mutex; } *;

static Router router(Notes app, Path public_dir) {
  Router routes = Router.new();
  routes.get("/api/notes", %!(HttpRequest req, HttpResponse res) =>
    list_notes(app, req, res));
  routes.post("/api/notes", %!(HttpRequest req, HttpResponse res) =>
    create_note(app, req, res));
  routes.files("/", public_dir);
  return routes;
}

static void list_notes(Notes app, HttpRequest req, HttpResponse res) {
  String tag = req.query["tag"] is void ? NULL : req.query["tag"];
  Array notes = [];
  $lock(app.mutex) {
    Prepared select = auto app.db.prepare(
      "SELECT id, title, body, tags, created, updated FROM note ORDER BY id");
    foreach (List row in select) {
      Map note = note_json(row);
      if (tag && !(tag in note["tags"].array())) continue;
      notes.push(note);
    }
  }
  res.json(notes);
}
```

Two hundred and nine lines: an HTTP API with routes, JSON in and out,
SQLite persistence, regex search, a worker pool, and a clean shutdown.
`http.x` and `net.x` ship with the runtime; `import "sqlite"` brings the
database.

It has been measured against a Go server with the same API. Go wins the
64-client lookups; x2c wins the single-client ones and uses less memory in
every pair. The [report](https://github.com/gwf/x2c/blob/main/examples/apps/notes/bench/README.md)
has the numbers and the caveats.
