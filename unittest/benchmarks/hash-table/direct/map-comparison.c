/* map-comparison.c -- direct-C Map comparison with klib khashl */

#include "x2c.h"
#include "typed-map.h"
#include "khashl-map.h"
#include "flat-map.h"
#include "khashl.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct Inputs {
  Var *keys;
  Var *hit_keys;
  Var *missing;
  Var *values;
  Var *replacements;
  int *native_keys;
  int *native_hit_keys;
  int *native_missing;
  int *native_values;
  int *native_replacements;
  size_t count;
  size_t probes;
  unsigned capacity;
} Inputs;

typedef struct Measurement {
  const char *operation;
  size_t operations;
  uint64_t elapsed;
  uint64_t checksum;
} Measurement;

static khint_t reference_hash(Var key) {
  return Var_hash(key);
}

static int reference_equal(Var left, Var right) {
  return Var_equal(left, right);
}

KHASHL_MAP_INIT(
  KH_LOCAL, ReferenceMap, reference_map, Var, Var,
  reference_hash, reference_equal
)

/* The same fmix64 hash lib/typed-map.x gives MapIntInt, so the native pair
   differs only in table storage, as the Var pair does. */
static khint_t native_hash(int key) {
  uint64_t word = (unsigned) key;
  word ^= word >> 33;
  word *= 0xff51afd7ed558ccdull;
  word ^= word >> 33;
  word *= 0xc4ceb9fe1a85ec53ull;
  word ^= word >> 33;
  unsigned hash = (unsigned) word;
  return hash ? hash : -1;
}

static int native_equal(int left, int right) {
  return left == right;
}

KHASHL_MAP_INIT(
  KH_LOCAL, NativeReferenceMap, native_reference_map, int, int,
  native_hash, native_equal
)

static uint64_t now_ns(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
    perror("clock_gettime");
    exit(2);
  }
  return (uint64_t) now.tv_sec * 1000000000ull + now.tv_nsec;
}

static void fail(const char *message) {
  fprintf(stderr, "map-comparison: %s\n", message);
  exit(2);
}

static void *checked_calloc(size_t count, size_t size) {
  void *result = calloc(count, size);
  if (!result) fail("allocation failed");
  return result;
}

static uint64_t random_next(uint64_t *state) {
  uint64_t value = *state;
  value ^= value >> 12;
  value ^= value << 25;
  value ^= value >> 27;
  *state = value;
  return value * 2685821657736338717ull;
}

static void shuffle_pairs(
  Var *keys, Var *values, size_t count, uint64_t seed
) {
  if (count < 2) return;
  for (size_t i = count - 1; i > 0; i--) {
    size_t j = (size_t) (random_next(&seed) % (i + 1));
    Var key = keys[i];
    Var value = values[i];
    keys[i] = keys[j];
    values[i] = values[j];
    keys[j] = key;
    values[j] = value;
  }
}

static void shuffle(Var *values, size_t count, uint64_t seed) {
  if (count < 2) return;
  for (size_t i = count - 1; i > 0; i--) {
    size_t j = (size_t) (random_next(&seed) % (i + 1));
    Var value = values[i];
    values[i] = values[j];
    values[j] = value;
  }
}

static unsigned table_capacity(size_t count) {
  uint64_t needed = (uint64_t) count * 2;
  unsigned capacity = 2;
  while ((uint64_t) capacity < needed) {
    if (capacity > UINT32_MAX / 2) fail("table capacity exceeds Map limit");
    capacity *= 2;
  }
  return capacity;
}

static Inputs inputs_new(size_t count, size_t probe_multiplier) {
  if (!count || count > INT32_MAX / 2)
    fail("count must be between 1 and INT32_MAX / 2");
  if (!probe_multiplier || count > SIZE_MAX / probe_multiplier)
    fail("probe count overflow");

  Inputs inputs = {
    .keys = checked_calloc(count, sizeof(Var)),
    .hit_keys = checked_calloc(count, sizeof(Var)),
    .missing = checked_calloc(count, sizeof(Var)),
    .values = checked_calloc(count, sizeof(Var)),
    .replacements = checked_calloc(count, sizeof(Var)),
    .native_keys = checked_calloc(count, sizeof(int)),
    .native_hit_keys = checked_calloc(count, sizeof(int)),
    .native_missing = checked_calloc(count, sizeof(int)),
    .native_values = checked_calloc(count, sizeof(int)),
    .native_replacements = checked_calloc(count, sizeof(int)),
    .count = count,
    .probes = count * probe_multiplier,
    .capacity = table_capacity(count)
  };

  for (size_t i = 0; i < count; i++) {
    inputs.keys[i] = int_var((int) i + 1);
    inputs.missing[i] = int_var((int) (i + count) + 1);
    inputs.values[i] = int_var((int) (i ^ 0x13579bdu));
    inputs.replacements[i] = int_var((int) (i ^ 0x2468aceu));
  }
  shuffle_pairs(
    inputs.keys, inputs.values, count, 0x6a09e667f3bcc909ull
  );
  memcpy(inputs.hit_keys, inputs.keys, count * sizeof(Var));
  shuffle(inputs.hit_keys, count, 0x510e527fade682d1ull);
  shuffle(inputs.missing, count, 0xbb67ae8584caa73bull);
  shuffle(inputs.replacements, count, 0x3c6ef372fe94f82bull);

  /* The native lanes see the identical key and value sequence. */
  for (size_t i = 0; i < count; i++) {
    inputs.native_keys[i] = Var_integer(inputs.keys[i]);
    inputs.native_hit_keys[i] = Var_integer(inputs.hit_keys[i]);
    inputs.native_missing[i] = Var_integer(inputs.missing[i]);
    inputs.native_values[i] = Var_integer(inputs.values[i]);
    inputs.native_replacements[i] = Var_integer(inputs.replacements[i]);
  }
  return inputs;
}

static void inputs_free(Inputs *inputs) {
  free(inputs->keys);
  free(inputs->hit_keys);
  free(inputs->missing);
  free(inputs->values);
  free(inputs->replacements);
  free(inputs->native_keys);
  free(inputs->native_hit_keys);
  free(inputs->native_missing);
  free(inputs->native_values);
  free(inputs->native_replacements);
  memset(inputs, 0, sizeof(*inputs));
}

static void print_measurement(
  unsigned sample, const char *implementation, const Inputs *inputs,
  Measurement measurement
) {
  double ns_per_operation =
    (double) measurement.elapsed / (double) measurement.operations;
  printf(
    "%u,%s,%zu,%u,%s,%zu,%.6f,%" PRIu64 "\n",
    sample, implementation, inputs->count, inputs->capacity,
    measurement.operation, measurement.operations, ns_per_operation,
    measurement.checksum
  );
}

static Measurement x2c_grow_insert(const Inputs *inputs) {
  Scope_retain();
  Map map = Map_new();
  if (!map) fail("Map_new failed");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++)
    Map_set(map, inputs->keys[i], inputs->values[i]);
  uint64_t elapsed = now_ns() - start;
  uint64_t checksum = Map_len(map);
  Scope_release();
  return (Measurement) {
    "grow-insert", inputs->count, elapsed, checksum
  };
}

static Measurement reference_grow_insert(const Inputs *inputs) {
  ReferenceMap *map = reference_map_init();
  if (!map) fail("reference_map_init failed");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++) {
    int absent;
    khint_t entry = reference_map_put(map, inputs->keys[i], &absent);
    if (entry == kh_end(map)) fail("khashl insertion failed");
    kh_val(map, entry) = inputs->values[i];
  }
  uint64_t elapsed = now_ns() - start;
  uint64_t checksum = kh_size(map);
  reference_map_destroy(map);
  return (Measurement) {
    "grow-insert", inputs->count, elapsed, checksum
  };
}

static Map x2c_reserved_insert(
  const Inputs *inputs, Measurement *measurement
) {
  Map map = Map_new_capacity(inputs->capacity);
  if (!map) fail("Map_new_capacity failed");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++)
    Map_set(map, inputs->keys[i], inputs->values[i]);
  measurement->operation = "reserved-insert";
  measurement->operations = inputs->count;
  measurement->elapsed = now_ns() - start;
  measurement->checksum = Map_len(map);
  return map;
}

static ReferenceMap *reference_reserved_insert(
  const Inputs *inputs, Measurement *measurement
) {
  ReferenceMap *map = reference_map_init();
  if (!map) fail("reference_map_init failed");
  reference_map_resize(map, inputs->capacity);
  if (kh_capacity(map) != inputs->capacity)
    fail("khashl reserve failed");

  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++) {
    int absent;
    khint_t entry = reference_map_put(map, inputs->keys[i], &absent);
    if (entry == kh_end(map)) fail("khashl insertion failed");
    kh_val(map, entry) = inputs->values[i];
  }
  measurement->operation = "reserved-insert";
  measurement->operations = inputs->count;
  measurement->elapsed = now_ns() - start;
  measurement->checksum = kh_size(map);
  return map;
}

static Measurement x2c_replace(Map map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    Map_set(
      map, inputs->hit_keys[key_index], inputs->replacements[key_index]
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "replace-hit", inputs->probes, now_ns() - start, Map_len(map)
  };
}

static Measurement reference_replace(
  ReferenceMap *map, const Inputs *inputs
) {
  size_t key_index = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int absent;
    khint_t entry =
      reference_map_put(map, inputs->hit_keys[key_index], &absent);
    if (entry == kh_end(map) || absent)
      fail("khashl replacement missed an existing key");
    kh_val(map, entry) = inputs->replacements[key_index];
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "replace-hit", inputs->probes, now_ns() - start, kh_size(map)
  };
}

static Measurement x2c_update_add(Map map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  Symbol add = Symbol_new("+");
  Var one = int_var(1);
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    Var value = Map_updateindex(map, inputs->hit_keys[key_index], add, one);
    if (Var_is_void(value)) fail("Map_updateindex missed an existing key");
    checksum += value.u64;
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "update-add-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement reference_update_add(
  ReferenceMap *map, const Inputs *inputs
) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    khint_t entry = reference_map_get(map, inputs->hit_keys[key_index]);
    if (entry == kh_end(map)) fail("khashl update missed an existing key");
    Var value = int_var(Var_integer(kh_val(map, entry)) + 1);
    kh_val(map, entry) = value;
    checksum += value.u64;
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "update-add-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement x2c_lookup_hit(Map map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    Var value;
    if (!Map_try_get(map, inputs->hit_keys[key_index], &value))
      fail("Map_try_get missed an existing key");
    checksum += value.u64;
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement reference_lookup_hit(
  ReferenceMap *map, const Inputs *inputs
) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    khint_t entry = reference_map_get(map, inputs->hit_keys[key_index]);
    if (entry == kh_end(map)) fail("khashl missed an existing key");
    checksum += kh_val(map, entry).u64;
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement x2c_lookup_miss(Map map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    Var value;
    checksum +=
      (uint64_t) Map_try_get(map, inputs->missing[key_index], &value);
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement reference_lookup_miss(
  ReferenceMap *map, const Inputs *inputs
) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    khint_t entry = reference_map_get(map, inputs->missing[key_index]);
    checksum += (uint64_t) (entry != kh_end(map));
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement x2c_erase_miss(Map map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    Var value;
    checksum +=
      (uint64_t) Map_try_del(map, inputs->missing[key_index], &value);
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "erase-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement reference_erase_miss(
  ReferenceMap *map, const Inputs *inputs
) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    khint_t entry = reference_map_get(map, inputs->missing[key_index]);
    if (entry != kh_end(map)) {
      checksum += (uint64_t) reference_map_del(map, entry);
    }
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "erase-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement x2c_iterate(
  Map map, const Inputs *inputs, size_t repeats
) {
  uint64_t checksum = 0;
  size_t visited = 0;
  uint64_t start = now_ns();
  for (size_t pass = 0; pass < repeats; pass++) {
    unsigned cursor = 0;
    Var key;
    Var value;
    while (Map_try_next(map, &cursor, &key, &value)) {
      checksum += key.u64 ^ value.u64;
      visited++;
    }
  }
  uint64_t elapsed = now_ns() - start;
  if (visited != inputs->count * repeats)
    fail("Map_try_next visited the wrong number of entries");
  return (Measurement) {
    "iterate", visited, elapsed, checksum
  };
}

static Measurement reference_iterate(
  ReferenceMap *map, const Inputs *inputs, size_t repeats
) {
  uint64_t checksum = 0;
  size_t visited = 0;
  uint64_t start = now_ns();
  for (size_t pass = 0; pass < repeats; pass++) {
    khint_t entry;
    kh_foreach(map, entry) {
      checksum += kh_key(map, entry).u64 ^ kh_val(map, entry).u64;
      visited++;
    }
  }
  uint64_t elapsed = now_ns() - start;
  if (visited != inputs->count * repeats)
    fail("khashl visited the wrong number of entries");
  return (Measurement) {
    "iterate", visited, elapsed, checksum
  };
}

static Measurement x2c_erase_hit(Map map, const Inputs *inputs) {
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++) {
    Var value;
    if (!Map_try_del(map, inputs->hit_keys[i], &value))
      fail("Map_try_del missed an existing key");
    checksum += value.u64;
  }
  uint64_t elapsed = now_ns() - start;
  if (Map_len(map) != 0) fail("Map is not empty after erasing all keys");
  return (Measurement) {
    "erase-hit", inputs->count, elapsed, checksum
  };
}

static Measurement reference_erase_hit(
  ReferenceMap *map, const Inputs *inputs
) {
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++) {
    khint_t entry = reference_map_get(map, inputs->hit_keys[i]);
    if (entry == kh_end(map)) fail("khashl erase missed an existing key");
    checksum += kh_val(map, entry).u64;
    reference_map_del(map, entry);
  }
  uint64_t elapsed = now_ns() - start;
  if (kh_size(map) != 0)
    fail("khashl is not empty after erasing all keys");
  return (Measurement) {
    "erase-hit", inputs->count, elapsed, checksum
  };
}

static Measurement backend_grow_insert(const Inputs *inputs) {
  Scope_retain();
  KhashlMap map = khashl_map_new();
  if (!map) fail("khashl_map_new failed");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++)
    khashl_map_set(map, inputs->keys[i], inputs->values[i]);
  uint64_t elapsed = now_ns() - start;
  uint64_t checksum = khashl_map_len(map);
  Scope_release();
  return (Measurement) {
    "grow-insert", inputs->count, elapsed, checksum
  };
}

static KhashlMap backend_reserved_insert(
  const Inputs *inputs, Measurement *measurement
) {
  KhashlMap map = khashl_map_new_capacity(inputs->capacity);
  if (!map) fail("khashl_map_new_capacity failed");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++)
    khashl_map_set(map, inputs->keys[i], inputs->values[i]);
  measurement->operation = "reserved-insert";
  measurement->operations = inputs->count;
  measurement->elapsed = now_ns() - start;
  measurement->checksum = khashl_map_len(map);
  return map;
}

static Measurement backend_replace(KhashlMap map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    khashl_map_set(
      map, inputs->hit_keys[key_index], inputs->replacements[key_index]
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "replace-hit", inputs->probes, now_ns() - start, khashl_map_len(map)
  };
}

static Measurement backend_update_add(KhashlMap map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  Symbol add = Symbol_new("+");
  Var one = int_var(1);
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    Var value =
      khashl_map_updateindex(map, inputs->hit_keys[key_index], add, one);
    if (Var_is_void(value)) fail("khashl update missed an existing key");
    checksum += value.u64;
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "update-add-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement backend_lookup_hit(KhashlMap map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    Var value;
    if (!khashl_map_try_get(map, inputs->hit_keys[key_index], &value))
      fail("khashl_map_try_get missed an existing key");
    checksum += value.u64;
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement backend_lookup_miss(KhashlMap map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    Var value;
    checksum += (uint64_t) khashl_map_try_get(
      map, inputs->missing[key_index], &value
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement backend_erase_miss(KhashlMap map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    Var value;
    checksum += (uint64_t) khashl_map_try_del(
      map, inputs->missing[key_index], &value
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "erase-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement backend_iterate(
  KhashlMap map, const Inputs *inputs, size_t repeats
) {
  uint64_t checksum = 0;
  size_t visited = 0;
  uint64_t start = now_ns();
  for (size_t pass = 0; pass < repeats; pass++) {
    unsigned cursor = 0;
    Var key;
    Var value;
    while (khashl_map_try_next(map, &cursor, &key, &value)) {
      checksum += key.u64 ^ value.u64;
      visited++;
    }
  }
  uint64_t elapsed = now_ns() - start;
  if (visited != inputs->count * repeats)
    fail("khashl_map_try_next visited the wrong number of entries");
  return (Measurement) {
    "iterate", visited, elapsed, checksum
  };
}

static Measurement backend_erase_hit(KhashlMap map, const Inputs *inputs) {
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++) {
    Var value;
    if (!khashl_map_try_del(map, inputs->hit_keys[i], &value))
      fail("khashl_map_try_del missed an existing key");
    checksum += value.u64;
  }
  uint64_t elapsed = now_ns() - start;
  if (khashl_map_len(map) != 0)
    fail("khashl map is not empty after erasing all keys");
  return (Measurement) {
    "erase-hit", inputs->count, elapsed, checksum
  };
}

static Measurement typed_grow_insert(const Inputs *inputs) {
  Scope_retain();
  MapIntInt map = MapIntInt_new();
  if (!map) fail("MapIntInt_new failed");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++)
    MapIntInt_set(map, inputs->native_keys[i], inputs->native_values[i]);
  uint64_t elapsed = now_ns() - start;
  uint64_t checksum = MapIntInt_len(map);
  Scope_release();
  return (Measurement) {
    "grow-insert", inputs->count, elapsed, checksum
  };
}

static Measurement native_reference_grow_insert(const Inputs *inputs) {
  NativeReferenceMap *map = native_reference_map_init();
  if (!map) fail("native_reference_map_init failed");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++) {
    int absent;
    khint_t entry =
      native_reference_map_put(map, inputs->native_keys[i], &absent);
    if (entry == kh_end(map)) fail("khashl insertion failed");
    kh_val(map, entry) = inputs->native_values[i];
  }
  uint64_t elapsed = now_ns() - start;
  uint64_t checksum = kh_size(map);
  native_reference_map_destroy(map);
  return (Measurement) {
    "grow-insert", inputs->count, elapsed, checksum
  };
}

static MapIntInt typed_reserved_insert(
  const Inputs *inputs, Measurement *measurement
) {
  MapIntInt map = MapIntInt_new_capacity(inputs->capacity);
  if (!map) fail("MapIntInt_new_capacity failed");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++)
    MapIntInt_set(map, inputs->native_keys[i], inputs->native_values[i]);
  measurement->operation = "reserved-insert";
  measurement->operations = inputs->count;
  measurement->elapsed = now_ns() - start;
  measurement->checksum = MapIntInt_len(map);
  return map;
}

static NativeReferenceMap *native_reference_reserved_insert(
  const Inputs *inputs, Measurement *measurement
) {
  NativeReferenceMap *map = native_reference_map_init();
  if (!map) fail("native_reference_map_init failed");
  native_reference_map_resize(map, inputs->capacity);
  if (kh_capacity(map) != inputs->capacity)
    fail("khashl reserve failed");

  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++) {
    int absent;
    khint_t entry =
      native_reference_map_put(map, inputs->native_keys[i], &absent);
    if (entry == kh_end(map)) fail("khashl insertion failed");
    kh_val(map, entry) = inputs->native_values[i];
  }
  measurement->operation = "reserved-insert";
  measurement->operations = inputs->count;
  measurement->elapsed = now_ns() - start;
  measurement->checksum = kh_size(map);
  return map;
}

static Measurement typed_replace(MapIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    MapIntInt_set(
      map, inputs->native_hit_keys[key_index],
      inputs->native_replacements[key_index]
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "replace-hit", inputs->probes, now_ns() - start, MapIntInt_len(map)
  };
}

static Measurement native_reference_replace(
  NativeReferenceMap *map, const Inputs *inputs
) {
  size_t key_index = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int absent;
    khint_t entry =
      native_reference_map_put(
        map, inputs->native_hit_keys[key_index], &absent
      );
    if (entry == kh_end(map) || absent)
      fail("khashl replacement missed an existing key");
    kh_val(map, entry) = inputs->native_replacements[key_index];
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "replace-hit", inputs->probes, now_ns() - start, kh_size(map)
  };
}

static Measurement typed_update_add(MapIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  Symbol add = Symbol_new("+");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value =
      MapIntInt_updateindex(map, inputs->native_hit_keys[key_index], add, 1);
    checksum += (unsigned) value;
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "update-add-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement native_reference_update_add(
  NativeReferenceMap *map, const Inputs *inputs
) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    khint_t entry =
      native_reference_map_get(map, inputs->native_hit_keys[key_index]);
    if (entry == kh_end(map)) fail("khashl update missed an existing key");
    int value = kh_val(map, entry) + 1;
    kh_val(map, entry) = value;
    checksum += (unsigned) value;
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "update-add-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement typed_lookup_hit(MapIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value;
    if (!MapIntInt_try_get(map, inputs->native_hit_keys[key_index], &value))
      fail("MapIntInt_try_get missed an existing key");
    checksum += (unsigned) value;
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement native_reference_lookup_hit(
  NativeReferenceMap *map, const Inputs *inputs
) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    khint_t entry =
      native_reference_map_get(map, inputs->native_hit_keys[key_index]);
    if (entry == kh_end(map)) fail("khashl missed an existing key");
    checksum += (unsigned) kh_val(map, entry);
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement typed_lookup_miss(MapIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value;
    checksum += (uint64_t) MapIntInt_try_get(
      map, inputs->native_missing[key_index], &value
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement native_reference_lookup_miss(
  NativeReferenceMap *map, const Inputs *inputs
) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    khint_t entry =
      native_reference_map_get(map, inputs->native_missing[key_index]);
    checksum += (uint64_t) (entry != kh_end(map));
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement typed_erase_miss(MapIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value;
    checksum += (uint64_t) MapIntInt_try_del(
      map, inputs->native_missing[key_index], &value
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "erase-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement native_reference_erase_miss(
  NativeReferenceMap *map, const Inputs *inputs
) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    khint_t entry =
      native_reference_map_get(map, inputs->native_missing[key_index]);
    if (entry != kh_end(map)) {
      checksum += (uint64_t) native_reference_map_del(map, entry);
    }
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "erase-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement typed_iterate(
  MapIntInt map, const Inputs *inputs, size_t repeats
) {
  uint64_t checksum = 0;
  size_t visited = 0;
  uint64_t start = now_ns();
  for (size_t pass = 0; pass < repeats; pass++) {
    unsigned cursor = 0;
    int key;
    int value;
    while (MapIntInt_try_next(map, &cursor, &key, &value)) {
      checksum += (unsigned) key ^ (unsigned) value;
      visited++;
    }
  }
  uint64_t elapsed = now_ns() - start;
  if (visited != inputs->count * repeats)
    fail("MapIntInt_try_next visited the wrong number of entries");
  return (Measurement) {
    "iterate", visited, elapsed, checksum
  };
}

static Measurement native_reference_iterate(
  NativeReferenceMap *map, const Inputs *inputs, size_t repeats
) {
  uint64_t checksum = 0;
  size_t visited = 0;
  uint64_t start = now_ns();
  for (size_t pass = 0; pass < repeats; pass++) {
    khint_t entry;
    kh_foreach(map, entry) {
      checksum += (unsigned) kh_key(map, entry) ^ (unsigned) kh_val(map, entry);
      visited++;
    }
  }
  uint64_t elapsed = now_ns() - start;
  if (visited != inputs->count * repeats)
    fail("khashl visited the wrong number of entries");
  return (Measurement) {
    "iterate", visited, elapsed, checksum
  };
}

static Measurement typed_erase_hit(MapIntInt map, const Inputs *inputs) {
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++) {
    int value;
    if (!MapIntInt_try_del(map, inputs->native_hit_keys[i], &value))
      fail("MapIntInt_try_del missed an existing key");
    checksum += (unsigned) value;
  }
  uint64_t elapsed = now_ns() - start;
  if (MapIntInt_len(map) != 0)
    fail("MapIntInt is not empty after erasing all keys");
  return (Measurement) {
    "erase-hit", inputs->count, elapsed, checksum
  };
}

static Measurement native_reference_erase_hit(
  NativeReferenceMap *map, const Inputs *inputs
) {
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++) {
    khint_t entry =
      native_reference_map_get(map, inputs->native_hit_keys[i]);
    if (entry == kh_end(map)) fail("khashl erase missed an existing key");
    checksum += (unsigned) kh_val(map, entry);
    native_reference_map_del(map, entry);
  }
  uint64_t elapsed = now_ns() - start;
  if (kh_size(map) != 0)
    fail("khashl is not empty after erasing all keys");
  return (Measurement) {
    "erase-hit", inputs->count, elapsed, checksum
  };
}

static void run_x2c(
  unsigned sample, const Inputs *inputs, size_t iteration_repeats
) {
  print_measurement(sample, "x2c", inputs, x2c_grow_insert(inputs));

  Scope_retain();
  Measurement measurement;
  Map map = x2c_reserved_insert(inputs, &measurement);
  print_measurement(sample, "x2c", inputs, measurement);
  print_measurement(sample, "x2c", inputs, x2c_replace(map, inputs));
  print_measurement(sample, "x2c", inputs, x2c_update_add(map, inputs));
  print_measurement(sample, "x2c", inputs, x2c_lookup_hit(map, inputs));
  print_measurement(sample, "x2c", inputs, x2c_lookup_miss(map, inputs));
  print_measurement(sample, "x2c", inputs, x2c_erase_miss(map, inputs));
  print_measurement(
    sample, "x2c", inputs,
    x2c_iterate(map, inputs, iteration_repeats)
  );
  print_measurement(sample, "x2c", inputs, x2c_erase_hit(map, inputs));
  Scope_release();
}

static void run_reference(
  unsigned sample, const Inputs *inputs, size_t iteration_repeats
) {
  print_measurement(
    sample, "khashl", inputs, reference_grow_insert(inputs)
  );

  Measurement measurement;
  ReferenceMap *map = reference_reserved_insert(inputs, &measurement);
  print_measurement(sample, "khashl", inputs, measurement);
  print_measurement(
    sample, "khashl", inputs, reference_replace(map, inputs)
  );
  print_measurement(
    sample, "khashl", inputs, reference_update_add(map, inputs)
  );
  print_measurement(
    sample, "khashl", inputs, reference_lookup_hit(map, inputs)
  );
  print_measurement(
    sample, "khashl", inputs, reference_lookup_miss(map, inputs)
  );
  print_measurement(
    sample, "khashl", inputs, reference_erase_miss(map, inputs)
  );
  print_measurement(
    sample, "khashl", inputs,
    reference_iterate(map, inputs, iteration_repeats)
  );
  print_measurement(
    sample, "khashl", inputs, reference_erase_hit(map, inputs)
  );
  reference_map_destroy(map);
}

static Measurement flat_grow_insert(const Inputs *inputs) {
  Scope_retain();
  MapFlatIntInt map = MapFlatIntInt_new();
  if (!map) fail("MapFlatIntInt_new failed");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++)
    MapFlatIntInt_set(map, inputs->native_keys[i], inputs->native_values[i]);
  uint64_t elapsed = now_ns() - start;
  uint64_t checksum = MapFlatIntInt_len(map);
  Scope_release();
  return (Measurement) {
    "grow-insert", inputs->count, elapsed, checksum
  };
}

static MapFlatIntInt flat_reserved_insert(
  const Inputs *inputs, Measurement *measurement
) {
  MapFlatIntInt map = MapFlatIntInt_new_capacity(inputs->capacity);
  if (!map) fail("MapFlatIntInt_new_capacity failed");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++)
    MapFlatIntInt_set(map, inputs->native_keys[i], inputs->native_values[i]);
  measurement->operation = "reserved-insert";
  measurement->operations = inputs->count;
  measurement->elapsed = now_ns() - start;
  measurement->checksum = MapFlatIntInt_len(map);
  return map;
}

static Measurement flat_replace(MapFlatIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    MapFlatIntInt_set(
      map, inputs->native_hit_keys[key_index],
      inputs->native_replacements[key_index]
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "replace-hit", inputs->probes, now_ns() - start, MapFlatIntInt_len(map)
  };
}

static Measurement flat_update_add(MapFlatIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  Symbol add = Symbol_new("+");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value = MapFlatIntInt_updateindex(
      map, inputs->native_hit_keys[key_index], add, 1
    );
    checksum += (unsigned) value;
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "update-add-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement flat_lookup_hit(MapFlatIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value;
    if (!MapFlatIntInt_try_get(
          map, inputs->native_hit_keys[key_index], &value))
      fail("MapFlatIntInt_try_get missed an existing key");
    checksum += (unsigned) value;
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement flat_lookup_miss(MapFlatIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value;
    checksum += (uint64_t) MapFlatIntInt_try_get(
      map, inputs->native_missing[key_index], &value
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement flat_erase_miss(MapFlatIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value;
    checksum += (uint64_t) MapFlatIntInt_try_del(
      map, inputs->native_missing[key_index], &value
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "erase-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement flat_iterate(
  MapFlatIntInt map, const Inputs *inputs, size_t repeats
) {
  uint64_t checksum = 0;
  size_t visited = 0;
  uint64_t start = now_ns();
  for (size_t pass = 0; pass < repeats; pass++) {
    unsigned cursor = 0;
    int key;
    int value;
    while (MapFlatIntInt_try_next(map, &cursor, &key, &value)) {
      checksum += (unsigned) key ^ (unsigned) value;
      visited++;
    }
  }
  uint64_t elapsed = now_ns() - start;
  if (visited != inputs->count * repeats)
    fail("MapFlatIntInt_try_next visited the wrong number of entries");
  return (Measurement) {
    "iterate", visited, elapsed, checksum
  };
}

static Measurement flat_erase_hit(MapFlatIntInt map, const Inputs *inputs) {
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++) {
    int value;
    if (!MapFlatIntInt_try_del(map, inputs->native_hit_keys[i], &value))
      fail("MapFlatIntInt_try_del missed an existing key");
    checksum += (unsigned) value;
  }
  uint64_t elapsed = now_ns() - start;
  if (MapFlatIntInt_len(map) != 0)
    fail("MapFlatIntInt is not empty after erasing all keys");
  return (Measurement) {
    "erase-hit", inputs->count, elapsed, checksum
  };
}

static void run_flat(
  unsigned sample, const Inputs *inputs, size_t iteration_repeats
) {
  print_measurement(
    sample, "x2c-flat", inputs, flat_grow_insert(inputs)
  );

  Scope_retain();
  Measurement measurement;
  MapFlatIntInt map = flat_reserved_insert(inputs, &measurement);
  print_measurement(sample, "x2c-flat", inputs, measurement);
  print_measurement(sample, "x2c-flat", inputs, flat_replace(map, inputs));
  print_measurement(sample, "x2c-flat", inputs, flat_update_add(map, inputs));
  print_measurement(sample, "x2c-flat", inputs, flat_lookup_hit(map, inputs));
  print_measurement(sample, "x2c-flat", inputs, flat_lookup_miss(map, inputs));
  print_measurement(sample, "x2c-flat", inputs, flat_erase_miss(map, inputs));
  print_measurement(
    sample, "x2c-flat", inputs, flat_iterate(map, inputs, iteration_repeats)
  );
  print_measurement(sample, "x2c-flat", inputs, flat_erase_hit(map, inputs));
  Scope_release();
}

static Measurement wide_grow_insert(const Inputs *inputs) {
  Scope_retain();
  MapWideIntInt map = MapWideIntInt_new();
  if (!map) fail("MapWideIntInt_new failed");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++)
    MapWideIntInt_set(map, inputs->native_keys[i], inputs->native_values[i]);
  uint64_t elapsed = now_ns() - start;
  uint64_t checksum = MapWideIntInt_len(map);
  Scope_release();
  return (Measurement) {
    "grow-insert", inputs->count, elapsed, checksum
  };
}

static MapWideIntInt wide_reserved_insert(
  const Inputs *inputs, Measurement *measurement
) {
  MapWideIntInt map = MapWideIntInt_new_capacity(inputs->capacity);
  if (!map) fail("MapWideIntInt_new_capacity failed");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++)
    MapWideIntInt_set(map, inputs->native_keys[i], inputs->native_values[i]);
  measurement->operation = "reserved-insert";
  measurement->operations = inputs->count;
  measurement->elapsed = now_ns() - start;
  measurement->checksum = MapWideIntInt_len(map);
  return map;
}

static Measurement wide_replace(MapWideIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    MapWideIntInt_set(
      map, inputs->native_hit_keys[key_index],
      inputs->native_replacements[key_index]
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "replace-hit", inputs->probes, now_ns() - start, MapWideIntInt_len(map)
  };
}

static Measurement wide_update_add(MapWideIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  Symbol add = Symbol_new("+");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value = MapWideIntInt_updateindex(
      map, inputs->native_hit_keys[key_index], add, 1
    );
    checksum += (unsigned) value;
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "update-add-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement wide_lookup_hit(MapWideIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value;
    if (!MapWideIntInt_try_get(
          map, inputs->native_hit_keys[key_index], &value))
      fail("MapWideIntInt_try_get missed an existing key");
    checksum += (unsigned) value;
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement wide_lookup_miss(MapWideIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value;
    checksum += (uint64_t) MapWideIntInt_try_get(
      map, inputs->native_missing[key_index], &value
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement wide_erase_miss(MapWideIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value;
    checksum += (uint64_t) MapWideIntInt_try_del(
      map, inputs->native_missing[key_index], &value
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "erase-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement wide_iterate(
  MapWideIntInt map, const Inputs *inputs, size_t repeats
) {
  uint64_t checksum = 0;
  size_t visited = 0;
  uint64_t start = now_ns();
  for (size_t pass = 0; pass < repeats; pass++) {
    unsigned cursor = 0;
    int key;
    int value;
    while (MapWideIntInt_try_next(map, &cursor, &key, &value)) {
      checksum += (unsigned) key ^ (unsigned) value;
      visited++;
    }
  }
  uint64_t elapsed = now_ns() - start;
  if (visited != inputs->count * repeats)
    fail("MapWideIntInt_try_next visited the wrong number of entries");
  return (Measurement) {
    "iterate", visited, elapsed, checksum
  };
}

static Measurement wide_erase_hit(MapWideIntInt map, const Inputs *inputs) {
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++) {
    int value;
    if (!MapWideIntInt_try_del(map, inputs->native_hit_keys[i], &value))
      fail("MapWideIntInt_try_del missed an existing key");
    checksum += (unsigned) value;
  }
  uint64_t elapsed = now_ns() - start;
  if (MapWideIntInt_len(map) != 0)
    fail("MapWideIntInt is not empty after erasing all keys");
  return (Measurement) {
    "erase-hit", inputs->count, elapsed, checksum
  };
}

static void run_wide(
  unsigned sample, const Inputs *inputs, size_t iteration_repeats
) {
  print_measurement(
    sample, "x2c-wide", inputs, wide_grow_insert(inputs)
  );

  Scope_retain();
  Measurement measurement;
  MapWideIntInt map = wide_reserved_insert(inputs, &measurement);
  print_measurement(sample, "x2c-wide", inputs, measurement);
  print_measurement(sample, "x2c-wide", inputs, wide_replace(map, inputs));
  print_measurement(sample, "x2c-wide", inputs, wide_update_add(map, inputs));
  print_measurement(sample, "x2c-wide", inputs, wide_lookup_hit(map, inputs));
  print_measurement(sample, "x2c-wide", inputs, wide_lookup_miss(map, inputs));
  print_measurement(sample, "x2c-wide", inputs, wide_erase_miss(map, inputs));
  print_measurement(
    sample, "x2c-wide", inputs, wide_iterate(map, inputs, iteration_repeats)
  );
  print_measurement(sample, "x2c-wide", inputs, wide_erase_hit(map, inputs));
  Scope_release();
}

static Measurement meta_grow_insert(const Inputs *inputs) {
  Scope_retain();
  MapMetaIntInt map = MapMetaIntInt_new();
  if (!map) fail("MapMetaIntInt_new failed");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++)
    MapMetaIntInt_set(map, inputs->native_keys[i], inputs->native_values[i]);
  uint64_t elapsed = now_ns() - start;
  uint64_t checksum = MapMetaIntInt_len(map);
  Scope_release();
  return (Measurement) {
    "grow-insert", inputs->count, elapsed, checksum
  };
}

static MapMetaIntInt meta_reserved_insert(
  const Inputs *inputs, Measurement *measurement
) {
  MapMetaIntInt map = MapMetaIntInt_new_capacity(inputs->capacity);
  if (!map) fail("MapMetaIntInt_new_capacity failed");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++)
    MapMetaIntInt_set(map, inputs->native_keys[i], inputs->native_values[i]);
  measurement->operation = "reserved-insert";
  measurement->operations = inputs->count;
  measurement->elapsed = now_ns() - start;
  measurement->checksum = MapMetaIntInt_len(map);
  return map;
}

static Measurement meta_replace(MapMetaIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    MapMetaIntInt_set(
      map, inputs->native_hit_keys[key_index],
      inputs->native_replacements[key_index]
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "replace-hit", inputs->probes, now_ns() - start, MapMetaIntInt_len(map)
  };
}

static Measurement meta_update_add(MapMetaIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  Symbol add = Symbol_new("+");
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value = MapMetaIntInt_updateindex(
      map, inputs->native_hit_keys[key_index], add, 1
    );
    checksum += (unsigned) value;
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "update-add-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement meta_lookup_hit(MapMetaIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value;
    if (!MapMetaIntInt_try_get(
          map, inputs->native_hit_keys[key_index], &value))
      fail("MapMetaIntInt_try_get missed an existing key");
    checksum += (unsigned) value;
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-hit", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement meta_lookup_miss(MapMetaIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value;
    checksum += (uint64_t) MapMetaIntInt_try_get(
      map, inputs->native_missing[key_index], &value
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "lookup-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement meta_erase_miss(MapMetaIntInt map, const Inputs *inputs) {
  size_t key_index = 0;
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->probes; i++) {
    int value;
    checksum += (uint64_t) MapMetaIntInt_try_del(
      map, inputs->native_missing[key_index], &value
    );
    if (++key_index == inputs->count) key_index = 0;
  }
  return (Measurement) {
    "erase-miss", inputs->probes, now_ns() - start, checksum
  };
}

static Measurement meta_iterate(
  MapMetaIntInt map, const Inputs *inputs, size_t repeats
) {
  uint64_t checksum = 0;
  size_t visited = 0;
  uint64_t start = now_ns();
  for (size_t pass = 0; pass < repeats; pass++) {
    unsigned cursor = 0;
    int key;
    int value;
    while (MapMetaIntInt_try_next(map, &cursor, &key, &value)) {
      checksum += (unsigned) key ^ (unsigned) value;
      visited++;
    }
  }
  uint64_t elapsed = now_ns() - start;
  if (visited != inputs->count * repeats)
    fail("MapMetaIntInt_try_next visited the wrong number of entries");
  return (Measurement) {
    "iterate", visited, elapsed, checksum
  };
}

static Measurement meta_erase_hit(MapMetaIntInt map, const Inputs *inputs) {
  uint64_t checksum = 0;
  uint64_t start = now_ns();
  for (size_t i = 0; i < inputs->count; i++) {
    int value;
    if (!MapMetaIntInt_try_del(map, inputs->native_hit_keys[i], &value))
      fail("MapMetaIntInt_try_del missed an existing key");
    checksum += (unsigned) value;
  }
  uint64_t elapsed = now_ns() - start;
  if (MapMetaIntInt_len(map) != 0)
    fail("MapMetaIntInt is not empty after erasing all keys");
  return (Measurement) {
    "erase-hit", inputs->count, elapsed, checksum
  };
}

static void run_meta(
  unsigned sample, const Inputs *inputs, size_t iteration_repeats
) {
  print_measurement(
    sample, "x2c-meta", inputs, meta_grow_insert(inputs)
  );

  Scope_retain();
  Measurement measurement;
  MapMetaIntInt map = meta_reserved_insert(inputs, &measurement);
  print_measurement(sample, "x2c-meta", inputs, measurement);
  print_measurement(sample, "x2c-meta", inputs, meta_replace(map, inputs));
  print_measurement(sample, "x2c-meta", inputs, meta_update_add(map, inputs));
  print_measurement(sample, "x2c-meta", inputs, meta_lookup_hit(map, inputs));
  print_measurement(sample, "x2c-meta", inputs, meta_lookup_miss(map, inputs));
  print_measurement(sample, "x2c-meta", inputs, meta_erase_miss(map, inputs));
  print_measurement(
    sample, "x2c-meta", inputs, meta_iterate(map, inputs, iteration_repeats)
  );
  print_measurement(sample, "x2c-meta", inputs, meta_erase_hit(map, inputs));
  Scope_release();
}

static void run_backend(
  unsigned sample, const Inputs *inputs, size_t iteration_repeats
) {
  print_measurement(
    sample, "x2c-khashl", inputs, backend_grow_insert(inputs)
  );

  Scope_retain();
  Measurement measurement;
  KhashlMap map = backend_reserved_insert(inputs, &measurement);
  print_measurement(sample, "x2c-khashl", inputs, measurement);
  print_measurement(
    sample, "x2c-khashl", inputs, backend_replace(map, inputs)
  );
  print_measurement(
    sample, "x2c-khashl", inputs, backend_update_add(map, inputs)
  );
  print_measurement(
    sample, "x2c-khashl", inputs, backend_lookup_hit(map, inputs)
  );
  print_measurement(
    sample, "x2c-khashl", inputs, backend_lookup_miss(map, inputs)
  );
  print_measurement(
    sample, "x2c-khashl", inputs, backend_erase_miss(map, inputs)
  );
  print_measurement(
    sample, "x2c-khashl", inputs,
    backend_iterate(map, inputs, iteration_repeats)
  );
  print_measurement(
    sample, "x2c-khashl", inputs, backend_erase_hit(map, inputs)
  );
  Scope_release();
}

static void run_typed(
  unsigned sample, const Inputs *inputs, size_t iteration_repeats
) {
  print_measurement(
    sample, "x2c-typed", inputs, typed_grow_insert(inputs)
  );

  Scope_retain();
  Measurement measurement;
  MapIntInt map = typed_reserved_insert(inputs, &measurement);
  print_measurement(sample, "x2c-typed", inputs, measurement);
  print_measurement(
    sample, "x2c-typed", inputs, typed_replace(map, inputs)
  );
  print_measurement(
    sample, "x2c-typed", inputs, typed_update_add(map, inputs)
  );
  print_measurement(
    sample, "x2c-typed", inputs, typed_lookup_hit(map, inputs)
  );
  print_measurement(
    sample, "x2c-typed", inputs, typed_lookup_miss(map, inputs)
  );
  print_measurement(
    sample, "x2c-typed", inputs, typed_erase_miss(map, inputs)
  );
  print_measurement(
    sample, "x2c-typed", inputs,
    typed_iterate(map, inputs, iteration_repeats)
  );
  print_measurement(
    sample, "x2c-typed", inputs, typed_erase_hit(map, inputs)
  );
  Scope_release();
}

static void run_native_reference(
  unsigned sample, const Inputs *inputs, size_t iteration_repeats
) {
  print_measurement(
    sample, "khashl-typed", inputs, native_reference_grow_insert(inputs)
  );

  Measurement measurement;
  NativeReferenceMap *map =
    native_reference_reserved_insert(inputs, &measurement);
  print_measurement(sample, "khashl-typed", inputs, measurement);
  print_measurement(
    sample, "khashl-typed", inputs, native_reference_replace(map, inputs)
  );
  print_measurement(
    sample, "khashl-typed", inputs, native_reference_update_add(map, inputs)
  );
  print_measurement(
    sample, "khashl-typed", inputs, native_reference_lookup_hit(map, inputs)
  );
  print_measurement(
    sample, "khashl-typed", inputs, native_reference_lookup_miss(map, inputs)
  );
  print_measurement(
    sample, "khashl-typed", inputs, native_reference_erase_miss(map, inputs)
  );
  print_measurement(
    sample, "khashl-typed", inputs,
    native_reference_iterate(map, inputs, iteration_repeats)
  );
  print_measurement(
    sample, "khashl-typed", inputs, native_reference_erase_hit(map, inputs)
  );
  native_reference_map_destroy(map);
}

static size_t parse_size(const char *text, const char *name) {
  char *end;
  uintmax_t value = strtoumax(text, &end, 10);
  if (!text[0] || *end || value == 0 || value > SIZE_MAX) {
    fprintf(stderr, "map-comparison: invalid %s: %s\n", name, text);
    exit(2);
  }
  return (size_t) value;
}

int main(int argc, char **argv) {
  if (argc != 6) {
    fprintf(
      stderr,
      "usage: %s COUNT PROBE_MULTIPLIER ITERATION_REPEATS SAMPLE ORDER\n",
      argv[0]
    );
    return 2;
  }

  size_t count = parse_size(argv[1], "count");
  size_t probe_multiplier = parse_size(argv[2], "probe multiplier");
  size_t iteration_repeats = parse_size(argv[3], "iteration repeats");
  size_t sample_value = parse_size(argv[4], "sample");
  if (sample_value > UINT32_MAX) fail("sample exceeds UINT32_MAX");

  Inputs inputs = inputs_new(count, probe_multiplier);

  /* Pay lazy runtime and generated-file initialization before either timer. */
  (void) Var_hash(inputs.keys[0]);
  Scope_retain();
  Map warm_map = Map_new();
  Map_set(warm_map, inputs.keys[0], inputs.values[0]);
  Var warm_value;
  if (!Map_try_get(warm_map, inputs.keys[0], &warm_value))
    fail("Map warmup failed");
  MapIntInt warm_typed = MapIntInt_new();
  MapIntInt_set(warm_typed, inputs.native_keys[0], inputs.native_values[0]);
  int warm_typed_value;
  if (!MapIntInt_try_get(warm_typed, inputs.native_keys[0], &warm_typed_value))
    fail("MapIntInt warmup failed");
  Scope_release();

  if (strcmp(argv[5], "x2c-first") == 0) {
    run_x2c((unsigned) sample_value, &inputs, iteration_repeats);
    run_backend((unsigned) sample_value, &inputs, iteration_repeats);
    run_reference((unsigned) sample_value, &inputs, iteration_repeats);
    run_typed((unsigned) sample_value, &inputs, iteration_repeats);
    run_flat((unsigned) sample_value, &inputs, iteration_repeats);
    run_wide((unsigned) sample_value, &inputs, iteration_repeats);
    run_meta((unsigned) sample_value, &inputs, iteration_repeats);
    run_native_reference((unsigned) sample_value, &inputs, iteration_repeats);
  }
  else if (strcmp(argv[5], "khashl-first") == 0) {
    run_native_reference((unsigned) sample_value, &inputs, iteration_repeats);
    run_meta((unsigned) sample_value, &inputs, iteration_repeats);
    run_wide((unsigned) sample_value, &inputs, iteration_repeats);
    run_flat((unsigned) sample_value, &inputs, iteration_repeats);
    run_typed((unsigned) sample_value, &inputs, iteration_repeats);
    run_reference((unsigned) sample_value, &inputs, iteration_repeats);
    run_backend((unsigned) sample_value, &inputs, iteration_repeats);
    run_x2c((unsigned) sample_value, &inputs, iteration_repeats);
  }
  else {
    fail("ORDER must be x2c-first or khashl-first");
  }

  inputs_free(&inputs);
  return 0;
}
