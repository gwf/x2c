/*  service.x -- notes routes shared by the file and SQLite programs */
#pragma once
#include "http.x"
#include "regex.x"
#include "store.x"
#include <time.h>

Router notes_routes(NoteStore store, Path public_dir, Path policy) {
  Router routes = Router.new();
  routes.get("/api/notes", %!(HttpRequest req, HttpResponse res) => {
    Map notes = store.snapshot();
    String tag = req.query["tag"] is void ? NULL : req.query["tag"];
    String query = req.query["q"] is void ? NULL : req.query["q"];
    Regex pattern = query ? Regex.compile(query) : NULL;
    Array found = [];
    foreach (Var (id, value) in notes) {
      Note note = Note.from_map(value);
      if (tag && !(tag in note.tags)) continue;
      if (pattern && !pattern.match(note.title) && !pattern.match(note.body))
        continue;
      found.push(value);
    }
    found.sort_by(%!(Map note) => note["id"]);
    res.json(found);
  });
  routes.get("/api/notes/:id", %!(HttpRequest req, HttpResponse res) => {
    Map notes = store.snapshot();
    Var note = notes[req.params["id"]];
    if (note is void) Http.fail(404, "no such note");
    res.json(note);
  });
  routes.post("/api/notes", %!(HttpRequest req, HttpResponse res) => {
    Note note = _request_note(req);
    note.id = NULL;
    note.created = note.updated = time(NULL);
    _allow(note, policy);
    res.status(201).json(store.save(note));
  });
  routes.put("/api/notes/:id", %!(HttpRequest req, HttpResponse res) => {
    Map notes = store.snapshot();
    Var prior = notes[req.params["id"]];
    if (prior is void) Http.fail(404, "no such note");
    Note note = _request_note(req);
    note.id = req.params["id"];
    note.created = prior.map()["created"];
    note.updated = time(NULL);
    _allow(note, policy);
    res.json(store.save(note));
  });
  routes.delete("/api/notes/:id", %!(HttpRequest req, HttpResponse res) => {
    if (!store.erase(req.params["id"])) Http.fail(404, "no such note");
    res.json({"deleted": Json.bool(1)});
  });
  routes.get("/api/stats", %!(HttpRequest req, HttpResponse res) => {
    Map notes = store.snapshot(), tags = {};
    long bytes = 0;
    foreach (Var (id, value) in notes) {
      Note note = Note.from_map(value);
      bytes += note.title.len() + note.body.len();
      foreach (String tag in note.tags) tags[tag] += 1;
    }
    res.json({"notes": (int) notes.len(), "bytes": bytes, "tags": tags});
  });
  routes.files("/", public_dir);
  return routes;
}

static Note _request_note(HttpRequest request) {
  Var value = request.json();
  if (value is not <map>) Http.fail(422, "expected a note object");
  try return Note.from_map(value);
  catch %(note-error (reason ?reason)):
    $error.fallback(((Note) {0})) Http.fail(422, reason);
}

static int _body_size(String text) => text.len();

static void _allow(Note note, Path policy) {
  if (!policy.exists()) return;
  // Each evaluation owns its interpreter; handlers share no mutable Lisp state.
  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  $lisp.bind(lisp, "body-size", _body_size);
  lisp.eval_string(policy.read_text());
  lisp.set_global("note-tags", note.tags.list());
  lisp.set_global("note-body", note.body);
  if (!lisp.eval_string("(allow-note note-tags note-body)").truth())
    Http.fail(422, "note rejected by policy");
}
