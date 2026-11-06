/*  notes-database.x -- database work shared by the Notes comparison servers */
#pragma once
#include "system-macros.x"
import "sqlite" with Database, Prepared;
#include "channel.x"
#include "json.x"

class Notes { Channel requests; Thread database; String path; } *;

typedef struct NotesRequest {
  Symbol operation, cause;
  List arguments, detail;
  Var result;
  Channel reply;
  Scope output;
  Pool pool;
} NotesRequest;

void Notes.init(Notes app) {
  app.requests = NULL; app.database = NULL; app.path = NULL;
}

/* The caller keeps the job, reply Channel, output Scope, and Pool alive
   until this thread finishes the accepted job. Its last job access precedes
   terminal delivery. Closing the queue drains accepted jobs before join. */
Var Notes.database_worker(Var value) {
  Notes app = value.pointer();
  auto Database db = NULL;
  foreach (Var message in app.requests) {
    NotesRequest *job = message.pointer();
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
    catch %(?cause *detail): save_failure(job, cause, detail);
    try reply.send(<done>);
    catch %(?cause *detail): {
      save_failure(job, cause, detail);
      reply.close();
    }
  }
  return void;
}

Map Notes.note_json(List row) =>
  {"id": row[0].str(), "title": row[1], "body": row[2],
   "tags": Json.parse(row[3]), "created": row[4], "updated": row[5]};

static void save_failure(NotesRequest *job, Symbol cause, List detail) {
  job.cause = cause;
  job.detail = Error.snapshot_in(detail, &job.output, job.pool);
}

static void database_request(Database db, NotesRequest *job) {
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
