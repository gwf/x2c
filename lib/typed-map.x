/*  typed-map.x -- typed `Map`s generated from shared storage

    Copyright (c) 2026 Gary William Flake

    These optional families store keys and values in native record fields.
    Their static operations do not box through `Var`. Separate methods provide
    `Var` conversion and `Iter` traversal.
*/

#pragma once
#include "x2c.x"
#include "error-macros.x"

#include <stdlib.h>
#include <string.h>
#include "map/map.x"
#include "integer-ops.x"
#include "substring.x"

// representation

/** A mutable, `Scope`-owned map from native `int` keys to `int` values.
    Keys and values are copied into native entry fields; assignment shares the
    map, while `MapIntInt.copy` makes an independent table. Compound indexed
    updates support arithmetic, remainder, bitwise, and shift operators, plus
    postfix increment and decrement.
*/
typedef struct MapIntInt {
  Scope scope, Bytes hashes, entries;
  unsigned used;
  unsigned capacity;
  unsigned mask;
} *MapIntInt;

/** A mutable, `Scope`-owned map from native `long` keys to `double` values.
    Keys and values are copied into native entry fields; assignment shares the
    map, while `MapLongDouble.copy` makes an independent table. Compound
    indexed updates support `+`, `-`, `*`, and `/`, plus postfix increment and
    decrement.
*/
typedef struct MapLongDouble {
  Scope scope, Bytes hashes, entries;
  unsigned used;
  unsigned capacity;
  unsigned mask;
} *MapLongDouble;

/** A mutable, `Scope`-owned map from canonical `String`s to canonical
    `String`s. The native entry fields borrow the supplied `String` pointers.
    Exporting a map owned by a `Context` recanonicalizes only `String`s owned
    by that `Context` in the destination pool before moving the map. Borrowed
    or outer-owned `String`s retain their existing pool lifetime, which must
    outlive the map. Compound indexed update supports only concatenation;
    postfix update is unsupported.
*/
typedef struct MapStringString {
  Scope scope, Bytes hashes, entries;
  unsigned used;
  unsigned capacity;
  unsigned mask;
} *MapStringString;

/** A mutable, `Scope`-owned map from canonical `String` keys to native `int`
    values. Exporting an owned map rebuilds it with destination-canonical keys
    before replacing its storage. Compound indexed updates support arithmetic,
    remainder, bitwise, and shift operators, plus postfix increment and
    decrement.
*/
typedef struct MapStringInt {
  Scope scope, Bytes hashes, entries;
  unsigned used;
  unsigned capacity;
  unsigned mask;
} *MapStringInt;

struct MapIntIntRecord { int key, val; };
struct MapLongDoubleRecord { long key; double val; };
struct MapStringStringRecord { String key, val; };
struct MapStringIntRecord { String key; int val; unsigned cached_hash; };

// storage errors and entry slots

$map.scaffold(
  MapIntInt, struct MapIntIntRecord, int, int,
  _int_key, _int_value, _int_reinsert_error, _int_insert_error,
  "MapIntInt.reinsert", "MapIntInt.insert");
$map.scaffold(
  MapLongDouble, struct MapLongDoubleRecord, long, double,
  _long_key, _double_value, _long_reinsert_error, _long_insert_error,
  "MapLongDouble.reinsert", "MapLongDouble.insert");
$map.scaffold(
  MapStringString, struct MapStringStringRecord, String, String,
  _string_key, _string_value, _string_reinsert_error, _string_insert_error,
  "MapStringString.reinsert", "MapStringString.insert");
$map.scaffold(
  MapStringInt, struct MapStringIntRecord, String, int,
  _string_int_key, _string_int_value,
  _string_int_reinsert_error, _string_int_insert_error,
  "MapStringInt.reinsert", "MapStringInt.insert");

// families

#include "group-match.h"

$map.grouped.rehashed.records(
  struct MapIntIntRecord, _hash_int, _int_record_hash, _int_remember_hash);

$map.grouped.core.family(
  MapIntInt, struct MapIntInt, int, int,
  struct MapIntIntRecord,
  _hash_int, _equal_int, _equal_int,
  _valid_int,
  _int_key, _int_value,
  _int_reinsert_error, _int_insert_error,
  _int_record_hash, _int_remember_hash, 1, 0);
$map.grouped.typed.family(
  MapIntInt, int, int,
  _update_int, _bad_arg, _bad_op,
  _capacity_valid, _int_value, mapintint,
  0, 1, 1, "MapIntInt");
$map.core.observe(
  MapIntInt, int, int, struct MapIntIntRecord,
  _box_int, _box_int, _compare_int, _compare_int);
$map.typed.observe(MapIntInt, int, int, _box_int, _box_int);
$map.typed.publish(
  MapIntInt, int, int, mapintint, <mapintint>,
  _box_int, _box_int, _prepare_int_export);

$map.grouped.rehashed.records(
  struct MapLongDoubleRecord, _hash_long,
  _long_record_hash, _long_remember_hash);

$map.grouped.core.family(
  MapLongDouble, struct MapLongDouble, long, double,
  struct MapLongDoubleRecord,
  _hash_long, _equal_long, _equal_double,
  _valid_double,
  _long_key, _double_value,
  _long_reinsert_error, _long_insert_error,
  _long_record_hash, _long_remember_hash, 0, 0);
$map.grouped.typed.family(
  MapLongDouble, long, double,
  _update_double, _bad_arg, _bad_op,
  _capacity_valid, _double_value, maplongdouble,
  0.0, 1.0, 1, "MapLongDouble");
$map.core.observe(
  MapLongDouble, long, double, struct MapLongDoubleRecord,
  _box_long, _box_double, _compare_long, _compare_double);
$map.typed.observe(MapLongDouble, long, double, _box_long, _box_double);
$map.typed.publish(
  MapLongDouble, long, double, maplongdouble, <maplongdou>,
  _box_long, _box_double,
  _prepare_long_export);

$map.grouped.rehashed.records(
  struct MapStringStringRecord, _hash_string,
  _string_record_hash, _string_remember_hash);

$map.grouped.core.family(
  MapStringString, struct MapStringString, String, String,
  struct MapStringStringRecord,
  _hash_string, _equal_string, _equal_string,
  _valid_string,
  _string_key, _string_value,
  _string_reinsert_error, _string_insert_error,
  _string_record_hash, _string_remember_hash, 1, 0);
$map.grouped.typed.family(
  MapStringString, String, String,
  _update_string, _bad_arg, _bad_op,
  _capacity_valid, _string_value, mapstringstring,
  0, "", 0, "MapStringString");
$map.core.observe(
  MapStringString, String, String, struct MapStringStringRecord,
  _box_string, _box_string, _compare_string, _compare_string);
$map.typed.observe(
  MapStringString, String, String, _box_string, _box_string);

$map.typed.publish(
  MapStringString, String, String, mapstringstring, <mapstrings>,
  _box_string, _box_string,
  _prepare_string_export);

$map.grouped.cached.records(
  struct MapStringIntRecord,
  _string_int_record_hash, _string_int_remember_hash);

$map.grouped.core.family(
  MapStringInt, struct MapStringInt, String, int,
  struct MapStringIntRecord,
  _hash_string, _equal_string, _equal_int,
  _valid_int,
  _string_int_key, _string_int_value,
  _string_int_reinsert_error, _string_int_insert_error,
  _string_int_record_hash, _string_int_remember_hash, 0, 0);
$map.grouped.typed.family(
  MapStringInt, String, int,
  _update_int, _bad_arg, _bad_op,
  _capacity_valid, _string_int_value, mapstringint,
  0, 1, 1, "MapStringInt");
$map.core.observe(
  MapStringInt, String, int, struct MapStringIntRecord,
  _box_string, _box_int, _compare_string, _compare_int);
$map.typed.observe(MapStringInt, String, int, _box_string, _box_int);

$map.typed.publish(
  MapStringInt, String, int, mapstringint, <mapstrint>,
  _box_string, _box_int,
  _prepare_string_int_export);

// compile-time conversions

/* Compile-time code reaches the typed-map conversions through these literal
   `meta` prototypes; a family macro cannot emit one. */
meta Var MapIntInt.var(MapIntInt);
meta MapIntInt Var.mapintint(Var);
meta MapIntInt Map.mapintint(Map);
meta Var MapLongDouble.var(MapLongDouble);
meta MapLongDouble Var.maplongdouble(Var);
meta MapLongDouble Map.maplongdouble(Map);
meta Var MapStringString.var(MapStringString);
meta MapStringString Var.mapstringstring(Var);
meta MapStringString Map.mapstringstring(Map);
meta Var MapStringInt.var(MapStringInt);
meta MapStringInt Var.mapstringint(Var);
meta MapStringInt Map.mapstringint(Map);

/** Adds count using borrowed bytes for lookup. Only a missing key is
    converted to a canonical String; the map never retains the view.
    Integer addition and insertion follow updateindex.
*/
int MapStringInt.add_substr(MapStringInt map, Substr key, int count) {
  if ((void *) map == NULL) _bad_arg("MapStringInt");
  unsigned hash = key.hash();
  if (!hash) hash = -1;
  unsigned char *controls = map.hashes;
  struct MapStringIntRecord *entries = map.entries;
  unsigned group_mask = map.mask >> 4, group = hash & group_mask;
  unsigned lanes = map.capacity < 16 ? (1u << map.capacity) - 1 : 65535u;
  unsigned char fingerprint = hash >> 25;
  const char *bytes = key.length
    ? (const char *) key.source + key.offset : NULL;
  for (unsigned step = 0; step <= group_mask; step++) {
    unsigned start = group * 16;
    unsigned matches =
      x2c_map_group_match(controls + start, fingerprint) & lanes;
    if (matches) __builtin_prefetch(entries + start, 0, 3);
    while (matches) {
      unsigned index = start + __builtin_ctz(matches);
      if (entries[index].key.len() == key.length &&
          (!key.length || memcmp(entries[index].key, bytes, key.length) == 0))
        return _update_int(&entries[index].val, <+>, count);
      matches &= matches - 1;
    }
    if (x2c_map_group_match(controls + start, 128) & lanes) break;
    group = (group + step + 1) & group_mask;
  }
  return map.updateindex(key, <+>, count);
}

static void _bad_arg(String owner) {
  raise %(bad-arg (operation $owner));
}

static int _update_int(int *slot, Symbol op, int rhs) {
  $integer.update(int, slot, op, rhs);
}

/* The three iterators each yield one boxed key or value, so a family needs a
   plain function per stored type. */

// boxing, hashing, and comparison

static Var _box_int(int value) => value;

static Var _box_long(long value) => value;

static Var _box_double(double value) => value;

static Var _box_string(String value) => value;

static MapIntInt _prepare_int_export(MapIntInt map, Context source) {
  (void) map; (void) source;
  return NULL;
}

static MapLongDouble _prepare_long_export(MapLongDouble map, Context source) {
  (void) map; (void) source;
  return NULL;
}

static unsigned _hash_int(int *key) => x2c_hash_word((unsigned) key[0]);

static unsigned _hash_long(long *key) => x2c_hash_word((unsigned long) key[0]);

/* A canonical String caches its content hash instead of walking bytes.
   Zero is normalized as `x2c_hash_word` does, so equal inputs hash equally
   everywhere; grouped occupancy lives in control bytes, not in the hash. */
static unsigned _hash_string(String *key) {
  unsigned hash = key[0].hash();
  return hash ? hash : -1;
}

static int _equal_int(int *a, int *b) => a[0] == b[0];

static int _equal_long(long *a, long *b) => a[0] == b[0];

static int _equal_double(double *a, double *b) => a[0] == b[0];

// Canonicalization makes identity the content test, as it does for a Var.
static int _equal_string(String *a, String *b) => a[0] == b[0];

static int _compare_int(int a, int b) => (a > b) - (a < b);

static int _compare_long(long a, long b) => (a > b) - (a < b);

static int _compare_double(double a, double b) => Var.compare(a, b);

static int _compare_string(String a, String b) => a.compare(b);

// checks and updates

static void _valid_int(int *value) {
  (void) value;
}

static void _valid_double(double *value) {
  (void) value;
}

// NULL is the empty String, not a missing one, so every String is storable.
static void _valid_string(String *value) {
  (void) value;
}

static int _capacity_valid(unsigned capacity) =>
  capacity >= 2 && !(capacity & (capacity - 1));

static double _update_double(double *slot, Symbol op, double rhs) {
  $floating.update(double, slot, op, rhs);
}

/* The family supplies no String increment value, so both postfix operators
   report a bad operator. */
static String _update_string(String *slot, Symbol op, String rhs) {
  $string.update(slot, op, rhs);
}

static void _bad_op(Symbol op) {
  raise %(bad-op (op $op));
}

static MapStringString _prepare_string_export(
  MapStringString map, Context source) {
  /* Recanonicalization can change key hashes or collapse equal keys, so stage
     a complete destination table before export swaps the backing arrays. */
  MapStringString staged = MapStringString.new_capacity(map.capacity);
  MapStringString result = NULL;
  defer if (result == NULL) staged.free_table();
  foreach (String (key, value) in map) {
    key = source.export_nested(key);
    value = source.export_nested(value);
    staged[key] = value;
  }
  return result = staged;
}

static MapStringInt _prepare_string_int_export(
  MapStringInt map, Context source) {
  MapStringInt staged = MapStringInt.new_capacity(map.capacity);
  MapStringInt result = NULL;
  defer if (result == NULL) staged.free_table();
  unsigned cursor = 0;
  String key;
  int value;
  while (map.try_next(cursor, key, value)) {
    key = source.export_nested(key);
    staged[key] = value;
  }
  return result = staged;
}
