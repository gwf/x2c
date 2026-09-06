/*  khashl-map.c -- Map's public shape over pinned khashl storage

    A spike, not a shipped backend. It keeps everything Map charges for -
    Var keys and values, production Var_hash and Var_equal, Var_update for
    numeric update, and Scope-owned allocation - and replaces only the split
    slot/record table with khashl's single packed bucket array. That isolates
    the storage layout from the value layer.

    khashl allocates exclusively through four macros, so routing them at
    Scope keeps the allocation model identical to Map's.
*/

#include "x2c.h"

#define Kmalloc(km, type, cnt) \
  ((void) (km), (type *) Scope_malloc((cnt) * sizeof(type)))
#define Kcalloc(km, type, cnt) \
  ((void) (km), (type *) Scope_calloc((cnt), sizeof(type)))
#define Krealloc(km, type, ptr, cnt) \
  ((void) (km), (type *) Scope_realloc((ptr), (cnt) * sizeof(type)))
#define Kfree(km, ptr) ((void) (km), Scope_free(ptr))

#include "khashl.h"

#include "khashl-map.h"

static khint_t khashl_map_hash(Var key) {
  return Var_hash(key);
}

static int khashl_map_equal(Var left, Var right) {
  return Var_equal(left, right);
}

KHASHL_MAP_INIT(
  KH_LOCAL, KhashlMapTable, khashl_map_table, Var, Var,
  khashl_map_hash, khashl_map_equal
)

KhashlMap khashl_map_new(void) {
  return khashl_map_table_init();
}

KhashlMap khashl_map_new_capacity(unsigned capacity) {
  KhashlMap map = khashl_map_table_init();
  khashl_map_table_resize(map, capacity);
  return map;
}

void khashl_map_free(KhashlMap map) {
  khashl_map_table_destroy(map);
}

unsigned khashl_map_len(KhashlMap map) {
  return (unsigned) kh_size(map);
}

void khashl_map_set(KhashlMap map, Var key, Var value) {
  int absent;
  khint_t bucket = khashl_map_table_put(map, key, &absent);
  kh_val(map, bucket) = value;
}

int khashl_map_try_get(KhashlMap map, Var key, Var *out) {
  khint_t bucket = khashl_map_table_get(map, key);
  if (bucket == kh_end(map)) return 0;
  *out = kh_val(map, bucket);
  return 1;
}

Var khashl_map_updateindex(KhashlMap map, Var key, Symbol op, Var rhs) {
  int absent;
  khint_t bucket = khashl_map_table_put(map, key, &absent);
  if (absent) {
    kh_val(map, bucket) = rhs;
    return rhs;
  }
  return Var_update(&kh_val(map, bucket), op, rhs);
}

int khashl_map_try_del(KhashlMap map, Var key, Var *out) {
  khint_t bucket = khashl_map_table_get(map, key);
  if (bucket == kh_end(map)) return 0;
  *out = kh_val(map, bucket);
  khashl_map_table_del(map, bucket);
  return 1;
}

int khashl_map_try_next(
  KhashlMap map, unsigned *cursor, Var *key, Var *value
) {
  khint_t end = kh_end(map);
  while (*cursor < end) {
    khint_t bucket = *cursor;
    *cursor += 1;
    if (!kh_exist(map, bucket)) continue;
    *key = kh_key(map, bucket);
    *value = kh_val(map, bucket);
    return 1;
  }
  return 0;
}
