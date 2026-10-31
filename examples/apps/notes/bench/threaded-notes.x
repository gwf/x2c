/*  threaded-notes.x -- Notes with one database thread and reply Channels

    Copyright (c) 2026 Gary William Flake
*/
#include "system-macros.x"

import "sqlite" with Database, Prepared;
#include "http.x"
#include "args.x"
#include "regex.x"
#include <signal.h>
#include <time.h>
#include <unistd.h>

class Notes { Channel requests; Thread database; String path; } *;

static typedef struct Request {
  Symbol operation, cause;
  List arguments, detail;
  Var result;
  Channel reply;
  Scope output;
  Pool pool;
} Request;

static volatile sig_atomic_t stopping;

int main(int argc, char **argv) {
  try return run(options(argc, argv));
  catch %(bad-arg *detail): {
    Stderr.printf($dedent(%"
      notes: %s
      Try --help for usage.
    "), detail.str());
    return 2;
  }
  catch %(?cause *detail): {
    Stderr.printf("notes: %s %s\n", cause.str(), detail.str());
    return 1;
  }
}

void Notes.init(Notes app) {
  app.requests = NULL; app.database = NULL; app.path = NULL;
}

static int run(Map options) {
  if (options["help"]) return 0;
  int port = number(options, "port", 0, 65535);
  int workers = number(options, "workers", 1, 1024);
  Notes app = Notes.new();
  app.path = options["store"];
  app.requests = Channel.new(<p48>, workers);
  defer app.requests.free();
  app.database = Thread.start(database_thread, Var.new(<p48>, app));
  defer {
    app.requests.close();
    app.database.join();
    app.database.free();
  }
  request(app, <open>, NULL);
  Router routes = router(app, options["public"]);
  HttpServer server = HttpServer.new(routes,
    {host: options["host"], port: port, workers: workers});
  defer server.close();
  signal(SIGINT, stop);
  signal(SIGTERM, stop);
  server.start();
  printf("Notes: http://%s:%d/\n", options["host"], server.port());
  fflush(stdout);
  while (!stopping) usleep(50000);
  return 0;
}

static Map options(int argc, char **argv) {
  List spec = %(
    (--host (value address) (default "127.0.0.1")
      (help "Listen on this address"))
    (--port (value number) (default "8080") (help "TCP port; 0 selects one"))
    (--workers (value number) (default "8") (help "HTTP worker count"))
    (--store (value file) (default "notes.db") (help "SQLite database file"))
    (--public (value directory) (default "examples/apps/notes/public")
      (help "Browser assets directory"))
    (-h --help (help "Show usage")));
  Map parsed = Args.parse(Args.from_argv(argc, argv), spec);
  if (parsed["help"]) puts(Args.usage("notes", spec));
  return parsed;
}

static int number(Map options, String key, int minimum, int maximum) {
  String text = options[key];
  long value;
  if (!text.try_long(value) || value < minimum || value > maximum)
    raise %(bad-arg (option $key) (reason "number out of range"));
  return value;
}

static void stop(int signal_number) {
  (void) signal_number;
  stopping = 1;
}

static Router router(Notes app, Path public_dir) {
  Router routes = Router.new();
  routes.get("/api/notes", %!(HttpRequest req, HttpResponse res) =>
    list_notes(app, req, res));
  routes.get("/api/notes/:id", %!(HttpRequest req, HttpResponse res) =>
    get_note(app, req, res));
  routes.post("/api/notes", %!(HttpRequest req, HttpResponse res) =>
    create_note(app, req, res));
  routes.put("/api/notes/:id", %!(HttpRequest req, HttpResponse res) =>
    update_note(app, req, res));
  routes.delete("/api/notes/:id", %!(HttpRequest req, HttpResponse res) =>
    delete_note(app, req, res));
  routes.get("/api/stats", %!(HttpRequest req, HttpResponse res) =>
    stats(app, res));
  routes.files("/", public_dir);
  return routes;
}

static void list_notes(Notes app, HttpRequest req, HttpResponse res) {
  String tag = req.query["tag"] is void ? NULL : req.query["tag"];
  String query = req.query["q"] is void ? NULL : req.query["q"];
  Regex pattern = NULL;
  if (query) {
    try pattern = Regex.compile(query);
    catch %(malformed *): Http.fail(400, "invalid search pattern");
  }
  Array rows = request(app, <list>, NULL), notes = [];
  foreach (List row in rows) {
    Map note = note_json(row);
    if (tag && !(tag in note["tags"].array())) continue;
    if (pattern && !pattern.match(note["title"]) &&
        !pattern.match(note["body"])) continue;
    notes.push(note);
  }
  res.json(notes);
}

static void get_note(Notes app, HttpRequest req, HttpResponse res) {
  List row = request(app, <get>, $(req.params["id"]));
  if (!row) Http.fail(404, "no such note");
  res.json(note_json(row));
}

static void create_note(Notes app, HttpRequest req, HttpResponse res) {
  Map note = note_input(req);
  long now = time(NULL);
  List row = request(app, <create>,
    $(note["title"], note["body"], note["tags"].json(), now, now));
  note["id"] = row[0].str();
  note["created"] = now;
  note["updated"] = now;
  res.status(201).json(note);
}

static void update_note(Notes app, HttpRequest req, HttpResponse res) {
  Map values = note_input(req);
  List row = request(app, <update>, $(values["title"], values["body"],
    values["tags"].json(), (long) time(NULL), req.params["id"]));
  if (!row) Http.fail(404, "no such note");
  res.json(note_json(row));
}

static void delete_note(Notes app, HttpRequest req, HttpResponse res) {
  long changed = request(app, <delete>, $(req.params["id"]));
  if (!changed) Http.fail(404, "no such note");
  res.json({"deleted": Json.bool(1)});
}

static void stats(Notes app, HttpResponse res) {
  Map tags = {};
  long count = 0, bytes = 0;
  Array rows = request(app, <stats>, NULL);
  foreach (List row in rows) {
    String title = row[0], body = row[1];
    count++;
    bytes += title.len() + body.len();
    foreach (String tag in Json.parse(row[2]).array()) tags[tag] += 1;
  }
  res.json({"notes": count, "bytes": bytes, "tags": tags});
}

/* The HTTP handler keeps its child output Scope and canonical Pool live
   while parked. Only the database thread writes the output. It restores its
   own allocation state before posting the buffered reply, after its last
   access to the borrowed job. Normal server shutdown joins handlers before
   closing the database queue; it does not cancel a handler's borrow. */
static Var request(Notes app, Symbol operation, List arguments) {
  Channel reply = auto Channel.new(<symbol>, 1);
  Request job = {.operation = operation, .arguments = arguments,
    .reply = reply, .output = Scope.child(), .pool = Pool.current()};
  app.requests.send(Var.new(<p48>, &job));
  reply.receive();
  if (job.cause) Error.raise(job.cause, job.detail);
  return job.result;
}

static Var database_thread(Var value) {
  Notes app = value.pointer();
  auto Database db = NULL;
  foreach (Var message in app.requests) {
    Request *job = message.pointer();
    Channel reply = job.reply;
    try {
      if (job.operation == <open>) {
        db = Database.open(app.path);
        db.execute($dedent(%"
          CREATE TABLE IF NOT EXISTS note (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            tags TEXT NOT NULL,
            created INTEGER NOT NULL,
            updated INTEGER NOT NULL
          )
        "));
      }
      else database_request(db, job);
    }
    catch %(?cause *detail): {
      save_failure(job, cause, detail);
    }
    try reply.send(<done>);
    catch %(?cause *detail): {
      save_failure(job, cause, detail);
      reply.close();
    }
  }
  return void;
}

static void save_failure(Request *job, Symbol cause, List detail) {
  job.cause = cause;
  job.detail = Error.snapshot_in(detail, &job.output, job.pool);
}

static void database_request(Database db, Request *job) {
  Scope.push(&job.output);
  defer Scope.pop();
  Pool previous = x2c_pool_exchange(job.pool);
  defer x2c_pool_exchange(previous);
  job.result = execute(db, job.operation, job.arguments);
}

static Var execute(Database db, Symbol operation, List arguments) {
  switch (operation) {
    case <list>: return rows(db,
      "SELECT id, title, body, tags, created, updated FROM note ORDER BY id");
    case <stats>: return rows(db, "SELECT title, body, tags FROM note");
    case <get>: {
      Prepared select = auto db.prepare(
        "SELECT id, title, body, tags, created, updated FROM note WHERE id = ?");
      return select.bind(@arguments).next();
    }
    case <create>: {
      Prepared insert = auto db.prepare(
        $dedent(%"
          INSERT INTO note (title, body, tags, created, updated)
          VALUES (?, ?, ?, ?, ?)
          RETURNING id
        "));
      List row = insert.bind(@arguments).next();
      insert.execute();
      return row;
    }
    case <update>: {
      Prepared update = auto db.prepare(
        $dedent(%"
          UPDATE note SET title = ?, body = ?, tags = ?, updated = ?
          WHERE id = ?
          RETURNING id, title, body, tags, created, updated
        "));
      List row = update.bind(@arguments).next();
      update.execute();
      return row;
    }
    case <delete>: {
      Prepared remove = auto db.prepare("DELETE FROM note WHERE id = ?");
      remove.bind(@arguments).execute();
      return (long) db.changes();
    }
    default: raise %(bad-arg (operation "database request"));
  }
}

static Array rows(Database db, String sql) {
  Prepared select = auto db.prepare(sql);
  Array result = [];
  foreach (List row in select) result.push(row);
  return result;
}

static Map note_input(HttpRequest req) {
  Var value = req.json();
  if (value is not <map>) Http.fail(422, "expected a note object");
  Map fields = value;
  if (fields["title"] is not <string> || !fields["title"].string())
    Http.fail(422, "title is required");
  if (fields["body"] is not void && fields["body"] is not <string>)
    Http.fail(422, "body must be text");
  if (fields["tags"] is not void && fields["tags"] is not <array>)
    Http.fail(422, "tags must be an array");
  Array tags = fields["tags"] is void ? [] : fields["tags"];
  foreach (Var tag in tags)
    if (tag is not <string> || !tag.string())
      Http.fail(422, "each tag must be nonempty text");
  return {"title": fields["title"],
          "body": fields["body"] is void ? "" : fields["body"], "tags": tags};
}

static Map note_json(List row) =>
  {"id": row[0].str(), "title": row[1], "body": row[2],
   "tags": Json.parse(row[3]), "created": row[4], "updated": row[5]};
