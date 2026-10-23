/*  map.x -- hash table mapping `Var` keys to `Var` values

    Copyright (c) 2025 Gary William Flake

    `Map` uses Robin Hood hashing split across two scope-owned `Block`s. The
    hash `Block` holds one 32-bit hash per bucket, zero for an empty bucket;
    the entry `Block` holds the `Var` key and value at the same bucket
    index. Lookups probe the compact hash `Block` and touch an entry only
    when its hash matches. Capacity is always a power of two and probe
    distances are computed as needed.

    Deletion back-shifts hashes and entries together to close holes.
    Structural mutation invalidates traversal state. Keys and values are
    stored as `Var` bits; the `Map` does not free pointer-bearing payloads or
    canonical values reachable through them.
*/

#pragma once
#include "error-macros.x"
#include "common.x"
#include "iter.x"

/** Mutable hash table whose record and backing Blocks share one owner.
    `Map.scope` lazily creates a separate scope for explicitly owned contents.
    `Map.move_to` moves the record, backing storage, and owned contents.
    Stored `Var` bits are shallow and retain no pointee;
    those values must remain valid while the `Map` can read, compare, hash,
    or return them. A valid empty `Map` is allocated and distinct from NULL.
*/
typedef struct Map {
  Scope scope, Bytes hashes, entries;
  unsigned used;
  unsigned capacity;
  unsigned mask;
} *Map;

protocol Cleanup(Map);

#include <stdlib.h>
#include <stdarg.h>
#include <stdio.h>

#include "var/var.x"
#include "exception.x"
#include "scope/scope.x"
#include "block.x"
#include "buffer.x"
#include "varconvert.x"
#include "map-generics.x"

// buckets

/* A record and its parallel nonzero hash occupy the same bucket. Both Vars are
   shallow copies; insertion never adopts storage reachable through them. */
static struct MapRecord {  Var key, val; };

$map.scaffold(
  Map, struct MapRecord, Var, Var,
  _record_key, _record_value, _reinsert_error, _insert_error,
  "Map.reinsert", "Map.insert");

$map.var.family(
  _key_hash, _key_equal, _value_equal, _value_valid);

/* Var.hash normalizes zero because the hash array reserves it for an empty
   bucket. Array and Map keys hash and compare by identity, so changing their
   contents cannot strand a bucket or merge distinct keys. */
/* Generated growth builds and reinserts into two staged Blocks before changing
   the Map, so allocation failure leaves the installed table alone. A new entry
   is not written until hashing, equality, value validation, and any required
   growth finish. Growth is published before the incoming key's retry probe,
   so a callback transfer on that retry may leave capacity and bucket order
   changed. Final Robin Hood displacement writes as it walks; its invariant
   guard diagnoses a broken table and does not promise rollback. Deletion alone
   rearranges an installed cluster in place by back-shifting it. */
$map.core.family(
  Map, struct Map, Var, Var, unsigned, struct MapRecord,
  _key_hash, _key_equal, _value_equal, _value_valid,
  _record_key, _record_value,
  _reinsert_error, _insert_error);

static int _capacity_valid(unsigned n) => n >= 2 && !(n & (n - 1));
static void _bad_arg(String owner) {
  (void) owner;
  raise %(bad-arg);
}
$map.typed.operations(Map, Var, Var, _bad_arg, _capacity_valid, void, 0, 1);
Var Map.updateindex(Map, Var, Symbol, Var);
Var Map.postfixindex(Map, Var, Symbol);
meta native Map Map.new_capacity(unsigned);
meta native unsigned Map.len(Map);
meta native Var Map.getdefault(Map, Var, Var);
meta native Var Map.setdefault(Map, Var, Var);
meta native void Map.set(Map, Var, Var);
meta native Self Map.copy(Self);
meta native Self Map.merge(Self, Self);

/** Merges `other` into `map`, combines colliding values, and returns `map`.
    The borrowed synchronous `combine` receives the destination value first
    and the source value second. Its result replaces the destination value.
    Disjoint keys are copied without invoking `combine`. The callback must
    not structurally mutate either Map. Self-merge combines each value with
    itself once. A null `other` is a no-op; a null destination uses `Map.merge`
    to make a fresh copy without invoking `combine`.
    Completed entries remain if a later callback or insertion fails; the
    failing callback leaves its entry unchanged. A null callback raises
    `<bad-arg>` only when a collision invokes it.
    Raises: causes from `Map.merge`, lookup, `Map.set`, or `Func.apply`.
*/
Self Map.merge_with(Self map, Self other, Func combine) {
  if (!map || !other) return map.merge(other);
  foreach (Var (key, value) in other) {
    Var previous = map[key];
    if (previous is not void) value = combine.apply_values(previous, value);
    map[key] = value;
  }
  return map;
}

/** Applies `op` to the value for `key` and returns the stored result.
    `+` inserts a numeric `rhs` when the key is absent; other updates require
    an existing key. A failing value operation leaves the entry unchanged.
    Raises: `<bad-arg>` for a null map or missing required key, `<void-op>`
    for a void key or value, a cause from `Var.update`, or an allocation,
    size, or invariant cause while inserting.
*/
Var Map.updateindex(Map map, Var key, Symbol op, Var rhs) {
  if (map == NULL) raise %(bad-arg);
  X2CVarNumericInfo info;
  int insert = Var.encoding_valid(rhs) && Var.numeric_info(rhs.tag(), info);
  if (key is void || rhs is void) raise %(void-op);
  if (op == <+> && insert) {
    int inserted;
    Var *stored = map.get_or_insert(&key, &rhs, &inserted);
    if (inserted) return rhs;
    return Var.update(stored[0], op, rhs);
  }
  long index = map.find_index(&key);
  if (index < 0) raise %(bad-arg (key $key));
  Var *stored = _record_value(map, (unsigned) index);
  return Var.update(stored[0], op, rhs);
}

/** Applies postfix `++` or `--` and returns the previous value.
    The key must already exist. A failing value operation leaves the entry
    unchanged.
    Raises: `<bad-arg>` for a null map or absent key, `<void-op>` for a void
    key, or a cause from `Var.postfix` for an unsupported value or operation.
*/
Var Map.postfixindex(Map map, Var key, Symbol op) {
  if (map == NULL) raise %(bad-arg);
  if (key is void) raise %(void-op);
  long index = map.find_index(&key);
  if (index < 0) raise %(bad-arg (key $key));
  Var *stored = _record_value(map, (unsigned) index);
  Var old = stored[0], value = old;
  Var.postfix(value, op);
  stored[0] = value;
  return old;
}

/** Returns the value stored under `key`, or `void` when absent, probing with
    the caller's precomputed `key_hash`.
    `key_hash` must be `Var.hash` of `key`; another value reports the key as
    absent. This serves a caller that probes several `Map`s with one key,
    and is `Map.get` in every other respect. A null `Map` reports absence.
    Raises: a cause raised by custom key equality. Hashing happens in the
    caller, so a `void` key raises there instead.
*/
meta native Var Map.get_hashed(Map map, Var key, unsigned key_hash) {
  if (map == NULL) return void;
  long index = map.find_hashed(&key, key_hash);
  return index < 0 ? void : *_record_value(map, (unsigned) index);
}

/** Adds exactly `pair_count` key/value pairs to `map` in argument order.
    Arguments alternate `Var` keys and values. A null `Map` returns NULL
    without reading them. Each completed pair remains if a later pair fails.
    Inserting a new key invalidates active traversal; replacing an existing
    value does not.
    Raises: the same causes as `Map.set`.
*/
Self Map.update_n(Self map, unsigned pair_count, ...) {
  if (map == NULL) return NULL;
  va_list ap;
  va_start(ap, pair_count);
  for (unsigned i = 0; i < pair_count; i++) {
    Var key = va_arg(ap, Var), val = va_arg(ap, Var);
    map[key] = val;
  }
  va_end(ap);
  return map;
}

/** Exports every key and value and rebuilds the table under its record owner.
    The borrowed `export_value` callback runs synchronously for each stored
    key and value and may return replacement `Var`s. Rebuilding is required
    because an exported key may hash differently. On success the old backing
    `Block`s are freed and their replacements enter the record owner's scope.
    `Context` owns cycle detection and schedules record, backing storage, and
    owned-content scope moves after recursion.

    A failure while staging leaves the `Map`'s original records, backing
    storage, and recorded `Scope` unchanged. Effects of callbacks that
    already completed, including nested exports, are not rolled back. Any
    failure while moving the rebuilt `Block`s occurs after the table has
    replaced the original. A null `Map`, callback, or `Scope` pointer does
    nothing. Raises: `<alloc-fail>`, `<size-limit>`, or `<invariant>` while
    rebuilding, or any cause from export, key hashing, or moving the rebuilt
    `Block`s. */
void Map.export_to(
  Map map, Context source, VarExportContextFn export_value, Scope *scope) {
  if (map == NULL || !export_value || !scope) return;
  Bytes old_hashes = map.hashes, old_entries = map.entries;

  /* Stage both arrays without publishing either one. A transfer frees the
     staged Blocks and leaves the original table installed; callback effects
     that happened before it remain the caller's responsibility. */
  Bytes rebuilt_hashes = Bytes.new(sizeof(unsigned));
  Bytes rebuilt_entries = Bytes.new(sizeof(struct MapRecord)), int rebuilt = 0;
  defer if (!rebuilt) rebuilt_hashes.free();
  defer if (!rebuilt) rebuilt_entries.free();
  rebuilt_hashes = rebuilt_hashes.append(NULL, map.capacity);
  rebuilt_entries = rebuilt_entries.append(NULL, map.capacity);
  struct Map exported = *map;
  exported.hashes = rebuilt_hashes;
  exported.entries = rebuilt_entries;
  foreach (Var (key, val) in map) {
    struct MapRecord record = {
      .key = export_value(key, source),
      .val = export_value(val, source)
    };
    ((Map) &exported).reinsert(record.key.hash(), record, 0);
  }
  map.hashes = rebuilt_hashes;
  map.entries = rebuilt_entries;
  rebuilt_hashes = NULL;
  rebuilt_entries = NULL;
  rebuilt = 1;
  old_hashes.free();
  old_entries.free();

  Scope owner = Scope.owner(map);
  map.hashes.block().move_to(&owner);
  map.entries.block().move_to(&owner);
}

static Var _box_var(Var value) => value;
static int _compare_var(Var a, Var b) => a.compare(b);
$map.core.observe(Map, Var, Var, struct MapRecord,
  _box_var, _box_var, _compare_var, _compare_var);
$map.typed.observation(Map);
$map.typed.iterate(Map, Var, Var, map, _box_var, _box_var);
meta native Iter Map.keys(Map, Iter);
meta native Iter Map.enumerate(Map, Iter);

/** Destroys owned contents and frees the Map's record and backing Blocks.
    Referenced keys and values with independent owners remain unchanged.
    NULL does nothing. Every alias becomes invalid after destruction.
*/
meta native void Map.cleanup(Map value) { value.free_table(); }
