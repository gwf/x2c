/*  typed-map.x -- typed `Map`s generated from shared storage

    Copyright (c) 2026 Gary William Flake

    These optional families store keys and values in native record fields.
    Their static operations do not box through `Var`. Separate methods provide
    `Var` conversion and `Iter` traversal.
*/

#pragma once
#include "x2c.x"
$(import "error-macros.xmacro")

#include <limits.h>
#include <stdlib.h>
#include <string.h>
$(import "map-generics.xmacro")

/** A mutable, `Scope`-owned map from native `int` keys to `int` values.
    Keys and values are copied into native entry fields; assignment shares the
    map, while `MapIntInt.copy` makes an independent table. Compound indexed
    updates support arithmetic, remainder, bitwise, and shift operators, plus
    postfix increment and decrement.
*/
typedef struct MapIntInt {
  Scope *scope, Bytes hashes, entries;
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
  Scope *scope, Bytes hashes, entries;
  unsigned used;
  unsigned capacity;
  unsigned mask;
} *MapLongDouble;

/** A mutable, `Scope`-owned map from canonical `String`s to canonical
    `String`s.
    The native entry fields borrow the supplied `String` pointers. Exporting a
    map owned by a `Context` recanonicalizes only `String`s owned by that
    `Context`
    in the destination pool before moving the map. Borrowed or outer-owned
    `String`s retain their existing pool lifetime, which must outlive the map.
    Compound indexed update supports only concatenation; postfix update is
    unsupported.
*/
typedef struct MapStringString {
  Scope *scope, Bytes hashes, entries;
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
  Scope *scope, Bytes hashes, entries;
  unsigned used;
  unsigned capacity;
  unsigned mask;
} *MapStringInt;

struct MapIntIntRecord { int key, val; };
struct MapLongDoubleRecord { long key; double val; };
struct MapStringStringRecord { String key, val; };
struct MapStringIntRecord { String key; int val; };

static void _int_reinsert_error(unsigned capacity, int probe) {
  raise %(invariant (owner "MapIntInt.reinsert") (capacity $capacity)
          (probe $probe));
}

static void _int_insert_error(unsigned capacity) {
  raise %(invariant (owner "MapIntInt.insert") (capacity $capacity));
}

static void _long_reinsert_error(unsigned capacity, int probe) {
  raise %(invariant (owner "MapLongDouble.reinsert") (capacity $capacity)
          (probe $probe));
}

static void _long_insert_error(unsigned capacity) {
  raise %(invariant (owner "MapLongDouble.insert") (capacity $capacity));
}

static void _string_reinsert_error(unsigned capacity, int probe) {
  raise %(invariant (owner "MapStringString.reinsert") (capacity $capacity)
          (probe $probe));
}

static void _string_insert_error(unsigned capacity) {
  raise %(invariant (owner "MapStringString.insert") (capacity $capacity));
}

static void _string_int_reinsert_error(unsigned capacity, int probe) {
  raise %(invariant (owner "MapStringInt.reinsert") (capacity $capacity)
          (probe $probe));
}

static void _string_int_insert_error(unsigned capacity) {
  raise %(invariant (owner "MapStringInt.insert") (capacity $capacity));
}

static int *_int_key(MapIntInt map, unsigned index) {
  struct MapIntIntRecord *records = map.entries;
  return &records[index].key;
}

static int *_int_value(MapIntInt map, unsigned index) {
  struct MapIntIntRecord *records = map.entries;
  return &records[index].val;
}

static long *_long_key(MapLongDouble map, unsigned index) {
  struct MapLongDoubleRecord *records = map.entries;
  return &records[index].key;
}

static double *_double_value(MapLongDouble map, unsigned index) {
  struct MapLongDoubleRecord *records = map.entries;
  return &records[index].val;
}

static String *_string_key(MapStringString map, unsigned index) {
  struct MapStringStringRecord *records = map.entries;
  return &records[index].key;
}

static String *_string_value(MapStringString map, unsigned index) {
  struct MapStringStringRecord *records = map.entries;
  return &records[index].val;
}

static String *_string_int_key(MapStringInt map, unsigned index) {
  struct MapStringIntRecord *records = map.entries;
  return &records[index].key;
}

static int *_string_int_value(MapStringInt map, unsigned index) {
  struct MapStringIntRecord *records = map.entries;
  return &records[index].val;
}

/* The three iterators each yield one boxed key or value, so a family needs a
   plain function per stored type. */

static Var _box_int(int value) => value;

static Var _box_long(long value) => value;

static Var _box_double(double value) => value;

static Var _box_string(String value) => value;

static MapIntInt _prepare_int_export(MapIntInt map, Context source) {
  (void) map; (void) source;
  return NULL;
}

static MapLongDouble _prepare_long_export(
  MapLongDouble map, Context source) {
  (void) map; (void) source;
  return NULL;
}

static unsigned _hash_int(int *key) => x2c_hash_word((unsigned) key[0]);

static unsigned _hash_long(long *key) => x2c_hash_word((unsigned long) key[0]);

/* A canonical String caches its content hash, so a lookup reads it instead of
   walking bytes. Zero marks an empty bucket and the empty String hashes to
   zero, so that one key borrows the reserved value, as Var.hash does for the
   same String. */
static unsigned _hash_string(String *key) {
  unsigned hash = key[0].hash();
  return hash ? hash : -1;
}

static int _equal_int(int *a, int *b) => a[0] == b[0];

static int _equal_long(long *a, long *b) => a[0] == b[0];

static int _equal_double(double *a, double *b) => a[0] == b[0];

/* Canonicalization makes identity the content test, as it does for a Var. */
static int _equal_string(String *a, String *b) => a[0] == b[0];

static int _map_compare_int(int a, int b) => (a > b) - (a < b);
static int _map_compare_long(long a, long b) => (a > b) - (a < b);
static int _map_compare_double(double a, double b) => Var.compare(a, b);
static int _map_compare_string(String a, String b) => a.compare(b);

static void _valid_int(int *value) {
  (void) value;
}

static void _valid_double(double *value) {
  (void) value;
}

/* NULL is the empty String, not a missing one, so every String is storable. */
static void _valid_string(String *value) {
  (void) value;
}

static void _bad_arg(String owner) {
  raise %(bad-arg (owner $owner));
}

static void _bad_op(Symbol op) {
  raise %(bad-op (op $op));
}

static int _capacity_valid(unsigned capacity) =>
  capacity >= 2 && !(capacity & (capacity - 1));

static void _bad_shift(Symbol op, int count) {
  raise %(bad-shift (op $op) (count $count) (width 32));
}

static void _div_zero(Symbol op) {
  raise %(div-zero (op $op));
}

static int _update_int(volatile int *slot, Symbol op, int rhs) {
  int current = slot[0];
  unsigned a, b, raw;
  memcpy(&a, &current, sizeof a);
  memcpy(&b, &rhs, sizeof b);
  switch (op) {
    case <+>: raw = a + b; break;
    case <->: raw = a - b; break;
    case <*>: raw = a * b; break;
    case <&>: raw = a & b; break;
    case <|>: raw = a | b; break;
    case <^>: raw = a ^ b; break;
    case </>: case <%>:
      if (!rhs) _div_zero(op);
      if (current == INT_MIN && rhs == -1)
        raw = op == </> ? (unsigned) INT_MIN : 0u;
      else raw = op == </> ? (unsigned) (current / rhs)
                           : (unsigned) (current % rhs);
      break;
    case <"<<">: case <">>">:
      if (rhs < 0 || rhs >= 32) _bad_shift(op, rhs);
      if (op == <"<<">) raw = a << rhs;
      else if (!rhs) raw = a;
      else if (!(a & 0x80000000u)) raw = a >> rhs;
      else raw = (a >> rhs) | (~0u << (32 - rhs));
      break;
    default: _bad_op(op);
  }
  int result;
  memcpy(&result, &raw, sizeof result);
  slot[0] = result;
  return result;
}

static double _update_double(
  volatile double *slot, Symbol op, double rhs) {
  double current = slot[0], result;
  switch (op) {
    case <+>: result = current + rhs; break;
    case <->: result = current - rhs; break;
    case <*>: result = current * rhs; break;
    case </>: result = current / rhs; break;
    default: _bad_op(op);
  }
  slot[0] = result;
  return result;
}

/* Concatenation is the only update a String value has. The family supplies
   no increment value, so both postfix operators report a bad operator. */
static String _update_string(
  volatile String *slot, Symbol op, String rhs) {
  if (op != <+>) _bad_op(op);
  String current = slot[0], result = current + rhs;
  slot[0] = result;
  return result;
}

$map.core.family(
  MapIntInt, struct MapIntInt, int, int,
  unsigned, struct MapIntIntRecord,
  _hash_int, _equal_int, _equal_int,
  _valid_int,
  _int_key, _int_value,
  _int_reinsert_error, _int_insert_error);
$map.typed.family(
  MapIntInt, int, int,
  _update_int, _bad_arg, _bad_op,
  _capacity_valid, _int_value, mapintint,
  0, 1, 1, "MapIntInt");
$map.core.observe(
  MapIntInt, int, int, struct MapIntIntRecord,
  _box_int, _box_int, _map_compare_int, _map_compare_int);
$map.typed.observe(MapIntInt, int, int, _box_int, _box_int);
$map.typed.publish(
  MapIntInt, int, int, mapintint, <mapintint>,
  _box_int, _box_int, _prepare_int_export);

$map.core.family(
  MapLongDouble, struct MapLongDouble, long, double,
  unsigned, struct MapLongDoubleRecord,
  _hash_long, _equal_long, _equal_double,
  _valid_double,
  _long_key, _double_value,
  _long_reinsert_error, _long_insert_error);
$map.typed.family(
  MapLongDouble, long, double,
  _update_double, _bad_arg, _bad_op,
  _capacity_valid, _double_value, maplongdouble,
  0.0, 1.0, 1, "MapLongDouble");
$map.core.observe(
  MapLongDouble, long, double, struct MapLongDoubleRecord,
  _box_long, _box_double, _map_compare_long, _map_compare_double);
$map.typed.observe(MapLongDouble, long, double, _box_long, _box_double);
$map.typed.publish(
  MapLongDouble, long, double, maplongdouble, <maplongdou>,
  _box_long, _box_double,
  _prepare_long_export);

$map.core.family(
  MapStringString, struct MapStringString, String, String,
  unsigned, struct MapStringStringRecord,
  _hash_string, _equal_string, _equal_string,
  _valid_string,
  _string_key, _string_value,
  _string_reinsert_error, _string_insert_error);
$map.typed.family(
  MapStringString, String, String,
  _update_string, _bad_arg, _bad_op,
  _capacity_valid, _string_value, mapstringstring,
  0, "", 0, "MapStringString");
$map.core.observe(
  MapStringString, String, String, struct MapStringStringRecord,
  _box_string, _box_string, _map_compare_string, _map_compare_string);
$map.typed.observe(MapStringString, String, String, _box_string, _box_string);

static MapStringString _prepare_string_export(
  MapStringString map, Context source) {
  /* Recanonicalization can change key hashes or collapse equal keys, so stage
     a complete destination table before export swaps the backing arrays. */
  MapStringString staged = MapStringString.new_capacity(map.capacity);
  MapStringString result = NULL;
  defer if ((void *) result == NULL) staged._core_free();
  foreach (String (key, value), map) {
    key = source.export_nested(key);
    value = source.export_nested(value);
    staged.set(key, value);
  }
  return result = staged;
}

$map.typed.publish(
  MapStringString, String, String, mapstringstring, <mapstrings>,
  _box_string, _box_string,
  _prepare_string_export);

$map.core.family(
  MapStringInt, struct MapStringInt, String, int,
  unsigned, struct MapStringIntRecord,
  _hash_string, _equal_string, _equal_int,
  _valid_int,
  _string_int_key, _string_int_value,
  _string_int_reinsert_error, _string_int_insert_error);
$map.typed.family(
  MapStringInt, String, int,
  _update_int, _bad_arg, _bad_op,
  _capacity_valid, _string_int_value, mapstringint,
  0, 1, 1, "MapStringInt");
$map.core.observe(
  MapStringInt, String, int, struct MapStringIntRecord,
  _box_string, _box_int, _map_compare_string, _map_compare_int);
$map.typed.observe(MapStringInt, String, int, _box_string, _box_int);

static MapStringInt _prepare_string_int_export(
  MapStringInt map, Context source) {
  MapStringInt staged = MapStringInt.new_capacity(map.capacity);
  MapStringInt result = NULL;
  defer if ((void *) result == NULL) staged._core_free();
  unsigned cursor = 0;
  String key;
  int value;
  while (map.try_next(&cursor, &key, &value)) {
    key = source.export_nested(key);
    staged.set(key, value);
  }
  return result = staged;
}

$map.typed.publish(
  MapStringInt, String, int, mapstringint, <mapstrint>,
  _box_string, _box_int,
  _prepare_string_int_export);
