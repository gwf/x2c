/*  store.x -- the persistence boundary shared by both notes programs */
#pragma once
#include "record.x"

class NoteStore { Func read, write, remove; Scope scope; } *;

NoteStore NoteStore.new(Func read, Func write, Func remove) {
  NoteStore store = xmalloc(sizeof(struct NoteStore));
  *store = (struct NoteStore) {read, write, remove,
                             Scope.new_named("note callbacks")};
  read.move(&store.scope);
  write.move(&store.scope);
  remove.move(&store.scope);
  return store;
}

void NoteStore.close(NoteStore store) {
  store.scope.destroy();
  xfree(store);
}

Map NoteStore.snapshot(NoteStore store) => store.read.apply(0, NULL);
Map NoteStore.save(NoteStore store, Note note) =>
  store.write.apply_value(note.to_map());
int NoteStore.erase(NoteStore store, String id) => store.remove.apply_value(id);

protocol NoteStore(T) {
  Map T.snapshot(T);
  Map T.save(T, Note);
  int T.erase(T, String);
}

class MapStore {
  Map notes;
  Path path;
  Mutex mutex;
  Scope scope;
  long next_id;
  Pool pool;
} *;

NoteStore MapStore.note_store(MapStore store) => NoteStore.new(
  %!() => store.snapshot(),
  %!(Map values) => store.save(Note.from_map(values)),
  %!(String id) => store.erase(id));

protocol NoteStore(MapStore);

static MapStore MapStore.new(void) => xcalloc(1, sizeof(struct MapStore));

MapStore MapStore.open(Path path) {
  MapStore store = MapStore.new();
  store.path = path;
  store.mutex = Mutex.new();
  store.scope = Scope.new_named("notes store");
  store.next_id = 1;
  store.pool = Pool.current();
  auto (&store.scope) store.notes = {};
  if (path.exists()) {
    Context input = auto Context.open_isolated_named("load notes");
    Map saved = Json.read_file(path);
    foreach (Var (id, value) in saved) {
      Note note = Note.from_map(value);
      _retain_note(store, note);
      long next = strtol(note.id, NULL, 10) + 1;
      if (next > store.next_id) store.next_id = next;
    }
  }
  return store;
}

Map MapStore.snapshot(MapStore store) {
  $lock(store.mutex) {
    // The copy belongs to this request, so later store mutations cannot race it.
    return Json.parse(((Var) store.notes).json());
  }
}

Map MapStore.save(MapStore store, Note note) {
  $lock(store.mutex) {
    if (!note.id) note.id = %"$(store.next_id++)";
    Var before = store.notes[note.id];
    _retain_note(store, note);
    try _persist(store);
    catch %(?code *detail): {
      _free_note(store.notes.del(note.id));
      if (before is not void) store.notes[before.map()["id"]] = before;
      Error.raise(code, detail);
    }
    if (before is not void) _free_note(before);
    return Json.parse(((Var) note.to_map()).json());
  }
}

int MapStore.erase(MapStore store, String id) {
  $lock(store.mutex) {
    if (store.notes[id] is void) return 0;
    Var before = store.notes.del(id);
    try _persist(store);
    catch %(?code *detail): {
      store.notes[before.map()["id"]] = before;
      Error.raise(code, detail);
    }
    _free_note(before);
    return 1;
  }
}

void MapStore.close(MapStore store) {
  if (!store) return;
  foreach (Var (id, note) in store.notes) _free_note(note);
  store.scope.destroy();
  store.mutex.free();
  xfree(store);
}

static void _persist(MapStore store) {
  Path temporary = %"$(store.path).tmp";
  Json.write_file(store.notes, temporary);
  temporary.move_to(store.path);
}

static void _retain_note(MapStore store, Note note) {
  String encoded = ((Var) note.to_map()).json();
  Pool pool = store.pool.retain_named("stored note");
  int attached = 0;
  defer if (!attached) pool.release();
  Pool previous = x2c_pool_exchange(pool);
  defer x2c_pool_exchange(previous);
  Map values;
  auto (&store.scope) values = Json.parse(encoded);
  values["tags"].array().move_to(&values.scope);
  Pool *owner = Scope.malloc_finalized_in(
    &values.scope, sizeof(Pool), _release_pool);
  *owner = pool;
  attached = 1;
  store.notes.del(note.id);
  store.notes[values["id"]] = values;
}

static void _release_pool(void *owner) { (*(Pool *) owner).release(); }

static void _free_note(Map note) {
  note.cleanup();
}
