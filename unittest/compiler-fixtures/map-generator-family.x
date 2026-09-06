#include "x2c.x"
$(import "../../lib/error-macros.xmacro")
$(import "../../lib/map-generics.xmacro")

#include <stdlib.h>

typedef struct ProbeMapShortLong {
  Scope *scope;
  Bytes hashes, entries;
  unsigned used;
  unsigned capacity;
  unsigned mask;
} *ProbeMapShortLong;

struct ProbeMapShortLongRecord { short key; long val; };

static int probe_hash_calls;

static int _probe_reinsert_error(unsigned capacity, int probe) {
  raise %(invariant (owner "ProbeMapShortLong.reinsert")
          (capacity $capacity) (probe $probe));
}
static void _probe_insert_error(unsigned capacity) {
  raise %(invariant (owner "ProbeMapShortLong.insert")
          (capacity $capacity));
}

static short *_probe_key(ProbeMapShortLong map, unsigned index) {
  struct ProbeMapShortLongRecord *records = map.entries;
  return &records[index].key;
}

static long *_probe_value(ProbeMapShortLong map, unsigned index) {
  struct ProbeMapShortLongRecord *records = map.entries;
  return &records[index].val;
}

static unsigned _probe_hash(short *key) {
  const unsigned char *bytes = (const unsigned char *) key;
  unsigned hash = 0;
  probe_hash_calls++;
  for (size_t i = 0; i < sizeof key[0]; i++) {
    hash += bytes[i];
    hash += hash << 10;
    hash ^= hash >> 6;
  }
  hash += ~(hash << 9);
  hash ^= hash >> 14;
  hash += hash << 4;
  hash ^= hash >> 10;
  return hash ? hash : -1;
}

static int _probe_key_equal(short *a, short *b) {
  return a[0] == b[0];
}

static int _probe_value_equal(long *a, long *b) {
  return a[0] == b[0];
}

static int _probe_value_valid(long *value) {
  (void) value;
  return 1;
}

static void _probe_bad_arg(String owner) {
  raise %(bad-arg (owner $owner));
}

static void _probe_bad_op(Symbol op) {
  raise %(bad-op (op $op));
}

static int _probe_capacity_valid(unsigned capacity) {
  return capacity >= 2 && !(capacity & (capacity - 1));
}

static long _probe_update_long(volatile long *slot, Symbol op, long rhs) {
  if (op == <+>) return slot[0] += rhs;
  if (op == <->) return slot[0] -= rhs;
  _probe_bad_op(op);
  return 0L;
}

static Var _probe_box_short(short value) {
  return Var.box_i16(value);
}

static Var _probe_box_long(long value) {
  return Var.box_long(value);
}

static int _probe_compare_short(short a, short b) => (a > b) - (a < b);
static int _probe_compare_long(long a, long b) => (a > b) - (a < b);

static ProbeMapShortLong _probe_prepare_export(
  ProbeMapShortLong map, Context source) {
  (void) map;
  (void) source;
  return NULL;
}

$map.core.family(
  ProbeMapShortLong, struct ProbeMapShortLong, short, long,
  unsigned, struct ProbeMapShortLongRecord,
  _probe_hash, _probe_key_equal, _probe_value_equal, _probe_value_valid,
  _probe_key, _probe_value,
  _probe_reinsert_error, _probe_insert_error
);
$map.typed.family(
  ProbeMapShortLong, short, long,
  _probe_update_long, _probe_bad_arg, _probe_bad_op,
  _probe_capacity_valid, _probe_value, probemapshortlong,
  0L, 1L, 1, "ProbeMapShortLong"
);
$map.core.observe(
  ProbeMapShortLong, short, long, struct ProbeMapShortLongRecord,
  _probe_box_short, _probe_box_long,
  _probe_compare_short, _probe_compare_long
);
$map.typed.observe(ProbeMapShortLong, short, long,
  _probe_box_short, _probe_box_long);
$map.typed.publish(
  ProbeMapShortLong, short, long, probemapshortlong, <p48>,
  _probe_box_short, _probe_box_long, _probe_prepare_export
);

static void _find_collisions(short *keys) {
  int found = 0;
  for (short candidate = 0; found < 3; candidate++)
    if ((_probe_hash(&candidate) & 7) == 3) keys[found++] = candidate;
}

int main(void) {
  short keys[3];
  _find_collisions(keys);
  ProbeMapShortLong map = ProbeMapShortLong.new();
  map.set(keys[0], 10L);
  map.set(keys[1], 20L);
  map.set(keys[2], 30L);
  probe_hash_calls = 0;
  long updated = map.updateindex(keys[1], <+>, 5L);
  int update_hashes = probe_hash_calls;
  long removed;
  map.try_del(keys[0], &removed);

  unsigned cursor = 0;
  short key;
  long value, native_total = 0;
  int native_count = 0;
  while (map.try_next(&cursor, &key, &value)) {
    native_total += value;
    native_count++;
  }

  struct Iter storage;
  Iter iter = map.iter(&storage);
  Var element;
  long iter_total = 0;
  int iter_count = 0;
  while (iter.try_next(&element)) {
    iter_total += element.long();
    iter_count++;
  }

  Var boxed = map;
  printf(
    "%u %ld %ld %d %ld %d %ld %d\n",
    map.len(), updated, removed, update_hashes,
    native_total, native_count, iter_total, iter_count
  );
  return boxed is <p48> ? 0 : 1;
}
