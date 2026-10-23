/*  substring-map.x -- native counts of borrowed String views */

#pragma once
#include "substring.x"
#include "map/map.x"
#include "context.x"

/** A scope-owned count table that borrows Substr keys. Keep every source
    String alive and unchanged until the table's final use. Counting copies
    only the view; strings() materializes each unique key once. Context export
    preserves the table and exports the source Strings used by its views. */
typedef struct MapSubInt {
  Scope scope, Bytes hashes, entries;
  unsigned used, capacity, mask;
} *MapSubInt;

struct MapSubIntRecord { Substr key; int val; };

$map.scaffold(
  MapSubInt, struct MapSubIntRecord, Substr, int,
  _key, _value, _reinsert_error, _insert_error,
  "MapSubInt.reinsert", "MapSubInt.insert");

static unsigned _hash(Substr *key) {
  unsigned hash = key[0].hash();
  return hash ? hash : -1;
}
static int _equal_key(Substr *a, Substr *b) => a[0].equal(b[0]);
static int _equal_value(int *a, int *b) => a[0] == b[0];
static void _valid(int *value) { (void) value; }

$map.core.family(
  MapSubInt, struct MapSubInt, Substr, int,
  unsigned, struct MapSubIntRecord,
  _hash, _equal_key, _equal_value, _valid,
  _key, _value, _reinsert_error, _insert_error);

/** Creates an empty count table in the current Scope. */
MapSubInt MapSubInt.new(void) {
  MapSubInt map = NULL;
  return map.new_table(2);
}

/** Adds one occurrence without copying or interning the word's bytes.
    The aggregate count must fit in int. */
void MapSubInt.increment(MapSubInt map, Substr word) {
  int one = 1, inserted;
  int *count = map.get_or_insert(&word, &one, &inserted);
  if (!inserted) ++*count;
}

/** Yields each unique view and its count without allocating. */
int MapSubInt.try_next(
  MapSubInt map, unsigned &cursor, Substr &word, int &count) =>
  map.try_next_entry(&cursor, &word, &count);

/** Copies counts to a Map with canonical String keys in the active pool. */
Map MapSubInt.strings(MapSubInt map) {
  Map result = {};
  unsigned cursor = 0;
  Substr word;
  int count;
  while (map.try_next(cursor, word, count)) result[word.str()] = count;
  return result;
}

static Var _box_key(Substr word) => word.str();
static Var _box_value(int count) => count;

/* Source pointers may change during export, but contents and hashes do not.
   Reuse the table; consecutive views of one text share its export. */
static MapSubInt _prepare_export(MapSubInt map, Context source) {
  unsigned *hashes = map.hashes;
  struct MapSubIntRecord *entries = map.entries;
  String previous = NULL, exported = NULL;
  for (unsigned i = 0; i < map.capacity; ++i) {
    if (!hashes[i]) continue;
    Substr *word = &entries[i].key;
    if (word.source != previous) {
      previous = word.source;
      exported = source.export_nested(previous);
    }
    word.source = exported;
  }
  return NULL;
}

$map.typed.publish(
  MapSubInt, Substr, int, mapsubint, <mapsubint>,
  _box_key, _box_value, _prepare_export);
