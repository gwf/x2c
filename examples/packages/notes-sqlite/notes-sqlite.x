/*  notes-sqlite.x -- the notes HTTP service backed by prepared SQLite */
import "sqlite" with Database, Prepared;
#include "../../apps/notes/service.x"
#include <assert.h>
#include <signal.h>
#include <unistd.h>

class SqliteStore { Database db; Mutex mutex; long next_id; } *;

static SqliteStore SqliteStore.new(void) =>
  xcalloc(1, sizeof(struct SqliteStore));

SqliteStore SqliteStore.open(String path) {
  SqliteStore store = SqliteStore.new();
  store.db = Database.open(path);
  store.mutex = Mutex.new();
  store.db.execute("CREATE TABLE IF NOT EXISTS note ("
    "id TEXT PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL, "
    "tags TEXT NOT NULL, created INTEGER NOT NULL, updated INTEGER NOT NULL)");
  Prepared maximum = auto store.db.prepare(
    "SELECT COALESCE(MAX(CAST(id AS INTEGER)), 0) + 1 FROM note");
  List row = maximum.next();
  store.next_id = row[0];
  return store;
}

Map SqliteStore.snapshot(SqliteStore store) {
  $lock(store.mutex) {
    Map notes = {};
    String columns = $note_columns();
    Prepared query = auto store.db.prepare(%"SELECT $columns FROM note");
    foreach (List row in query) {
      Note note = {0};
      note.id = row[0]; note.title = row[1]; note.body = row[2];
      note.tags = Json.parse(row[3]);
      note.created = row[4]; note.updated = row[5];
      notes[note.id] = note.to_map();
    }
    return notes;
  }
}

Map SqliteStore.save(SqliteStore store, Note note) {
  $lock(store.mutex) {
    if (!note.id) note.id = %"$(store.next_id++)";
    String columns = $note_columns();
    String sql = %"INSERT INTO note ($columns) VALUES (?, ?, ?, ?, ?, ?) ";
    sql = sql + "ON CONFLICT(id) DO UPDATE SET title=excluded.title, "
      "body=excluded.body, tags=excluded.tags, created=excluded.created, "
      "updated=excluded.updated";
    Prepared insert = auto store.db.prepare(sql);
    insert.bind(note.id, note.title, note.body ? note.body : "",
                ((Var) note.tags).json(), note.created, note.updated).execute();
    return note.to_map();
  }
}

int SqliteStore.erase(SqliteStore store, String id) {
  $lock(store.mutex) {
    Prepared remove = auto store.db.prepare("DELETE FROM note WHERE id = ?");
    remove.bind(id).execute();
    return store.db.changes() != 0;
  }
}

NoteStore SqliteStore.note_store(SqliteStore store) => NoteStore.new(
  %!() => store.snapshot(),
  %!(Map values) => store.save(Note.from_map(values)),
  %!(String id) => store.erase(id));

protocol NoteStore(SqliteStore);

void SqliteStore.close(SqliteStore store) {
  store.db.close();
  store.mutex.free();
  xfree(store);
}

static volatile sig_atomic_t stopping;
static void _stop(int signum) { stopping = 1; }

int main(int argc, char **argv) {
  int check = argc > 1 && String.new(argv[1]) == "--check";
  String database = argc > 1 && !check ? argv[1] : "notes.db";
  SqliteStore store = SqliteStore.open(check ? ":memory:" : database);
  defer store.close();
  if (check) {
    Map saved = store.save(Note.from_map({"title": "SQLite", "tags": ["sql"]}));
    assert(saved["id"].string() == "1");
    Map notes = store.snapshot();
    assert(notes["1"].map()["title"].string() == "SQLite");
    assert(notes["1"].map()["tags"].array()[0].string() == "sql");
    Note update = Note.from_map({"id": "1", "title": "Prepared"});
    store.save(update);
    assert(store.snapshot()["1"].map()["title"].string() == "Prepared");
    assert(store.erase("1") && !store.erase("1"));
    puts("SQLite notes: create, read, update, delete");
    return 0;
  }
  NoteStore interface = store.note_store();
  defer interface.close();
  Router routes = notes_routes(interface,
    "examples/apps/notes/public", "examples/apps/notes/policy.xlisp");
  HttpServer server = HttpServer.new(routes, {port: 8080});
  server.start();
  defer server.close();
  signal(SIGINT, _stop);
  signal(SIGTERM, _stop);
  printf("SQLite notes listening on port %d\n", server.port());
  while (!stopping) usleep(50000);
  return 0;
}
