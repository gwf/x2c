/*  notes.x -- a SQLite-backed HTTP notes server

    Copyright (c) 2026 Gary William Flake
*/
import "sqlite" with Database, Prepared;
#include "http.x"
#include "args.x"
#include "regex.x"
#include <signal.h>
#include <time.h>
#include <unistd.h>

class Notes { Database db; Mutex mutex; } *;
static volatile sig_atomic_t stopping;

int main(int argc, char **argv) {
  try return run(options(argc, argv));
  catch %(bad-arg *detail): {
    Stderr.printf("notes: %s\nTry --help for usage.\n", detail.str());
    return 2;
  }
  catch %(?cause *detail): {
    Stderr.printf("notes: %s %s\n", cause.str(), detail.str());
    return 1;
  }
}

void Notes.init(Notes app) { app.db = NULL; app.mutex = NULL; }

static int run(Map options) {
  if (options["help"]) return 0;
  int port = number(options, "port", 0, 65535);
  int workers = number(options, "workers", 1, 1024);
  Notes app = Notes.new();
  app.db = Database.open(options["store"]);
  defer app.db.close();
  app.mutex = Mutex.new();
  defer app.mutex.free();
  app.db.execute(
    "CREATE TABLE IF NOT EXISTS note ("
    "id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, "
    "body TEXT NOT NULL, tags TEXT NOT NULL, "
    "created INTEGER NOT NULL, updated INTEGER NOT NULL)");
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
  Regex pattern = query ? Regex.compile(query) : NULL;
  Array notes = [];
  $lock(app.mutex) {
    Prepared select = auto app.db.prepare(
      "SELECT id, title, body, tags, created, updated FROM note ORDER BY id");
    foreach (List row in select) {
      Map note = note_json(row);
      if (tag && !(tag in note["tags"].array())) continue;
      if (pattern && !pattern.match(note["title"]) &&
          !pattern.match(note["body"])) continue;
      notes.push(note);
    }
  }
  res.json(notes);
}

static void get_note(Notes app, HttpRequest req, HttpResponse res) {
  List row;
  $lock(app.mutex) {
    Prepared select = auto app.db.prepare(
      "SELECT id, title, body, tags, created, updated FROM note WHERE id = ?");
    row = select.bind(req.params["id"]).next();
  }
  if (!row) Http.fail(404, "no such note");
  res.json(note_json(row));
}

static void create_note(Notes app, HttpRequest req, HttpResponse res) {
  Map note = note_input(req);
  long now = time(NULL);
  $lock(app.mutex) {
    Prepared insert = auto app.db.prepare(
      "INSERT INTO note (title, body, tags, created, updated) "
      "VALUES (?, ?, ?, ?, ?) RETURNING id");
    List row = insert.bind(note["title"], note["body"],
      note["tags"].json(), now, now).next();
    note["id"] = row[0].str();
    note["created"] = now;
    note["updated"] = now;
    insert.execute();
  }
  res.status(201).json(note);
}

static void update_note(Notes app, HttpRequest req, HttpResponse res) {
  Map values = note_input(req), note;
  $lock(app.mutex) {
    Prepared update = auto app.db.prepare(
      "UPDATE note SET title = ?, body = ?, tags = ?, updated = ? "
      "WHERE id = ? RETURNING id, title, body, tags, created, updated");
    List row = update.bind(values["title"], values["body"],
      values["tags"].json(), (long) time(NULL), req.params["id"]).next();
    if (!row) Http.fail(404, "no such note");
    note = note_json(row);
    update.execute();
  }
  res.json(note);
}

static void delete_note(Notes app, HttpRequest req, HttpResponse res) {
  $lock(app.mutex) {
    Prepared remove = auto app.db.prepare("DELETE FROM note WHERE id = ?");
    remove.bind(req.params["id"]).execute();
    if (!app.db.changes()) Http.fail(404, "no such note");
  }
  res.json({"deleted": Json.bool(1)});
}

static void stats(Notes app, HttpResponse res) {
  Map tags = {};
  long count = 0, bytes = 0;
  $lock(app.mutex) {
    Prepared select = auto app.db.prepare("SELECT title, body, tags FROM note");
    foreach (List row in select) {
      String title = row[0], body = row[1];
      count++;
      bytes += title.len() + body.len();
      foreach (String tag in Json.parse(row[2]).array()) tags[tag] += 1;
    }
  }
  res.json({"notes": count, "bytes": bytes, "tags": tags});
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
