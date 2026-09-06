#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define U32_MAP_MAX_LOAD_NUMERATOR 3u
#define U32_MAP_MAX_LOAD_DENOMINATOR 4u

typedef struct U32MapSlot {
  uint32_t hash, index;
} U32MapSlot;

typedef struct U32MapRecord {
  uint32_t key, value;
} U32MapRecord;

typedef struct U32Map {
  U32MapSlot *slots;
  U32MapRecord *records;
  uint32_t *pool;
  uint32_t used, capacity, mask;
  uint32_t record_length, record_capacity;
  uint32_t pool_length, pool_capacity;
} *U32Map;

typedef struct U32MapItr {
  uint32_t slot;
} U32MapItr;

typedef struct U32MapProfile {
  uint64_t operations, probes, hash_matches, key_matches;
  uint64_t max_probe;
  uint64_t empty_insertions, robin_hood_insertions;
  uint64_t reinsert_probes, reinsert_swaps, max_reinsert_probe;
  uint64_t expansions, expansion_records, expansion_reinsert_probes;
  uint64_t new_records, reused_records;
  uint64_t erase_calls, erase_scan_steps, erase_shifts;
} U32MapProfile;

static U32MapProfile _u32_map_profile;

#pragma private

macro Expression $u32.unlikely(Expr $condition) => (
  __builtin_expect(!!($condition), 0)
)

macro Unit $u32.record_accessor(
  Name $method, Param $map, Param $itr, Expr $body
) => {
  static inline uint32_t *U32Map.$method($map, $itr) {
    return $body;
  }
}

static void _fail(void) {
  abort();
}

static void *_allocate(size_t count, size_t size) {
  if (count && size > SIZE_MAX / count) _fail();
  void *memory = malloc(count * size);
  if (!memory) _fail();
  return memory;
}

static void *_resize(void *memory, size_t count, size_t size) {
  if (count && size > SIZE_MAX / count) _fail();
  void *resized = realloc(memory, count * size);
  if (!resized) _fail();
  return resized;
}

static uint32_t _double_capacity(uint32_t capacity) {
  if (capacity > UINT32_MAX / 2) _fail();
  return capacity * 2;
}

static uint32_t _stored_hash(uint64_t hash) {
  uint32_t stored = (uint32_t) hash;
  return stored ? stored : 1;
}

static inline int U32Map._would_exceed_max_load(U32Map map) {
  return ((uint64_t) map.used + 1) * U32_MAP_MAX_LOAD_DENOMINATOR >
         (uint64_t) map.capacity * U32_MAP_MAX_LOAD_NUMERATOR;
}

static U32MapItr _invalid_itr(void) {
  return (U32MapItr) { .slot = UINT32_MAX };
}

/* Keep rare realloc and zeroing work out of the insertion path. */
#pragma clang attribute push(__attribute__((noinline)), apply_to=function)
static void U32Map._grow_records(U32Map map, uint32_t needed) {
  uint32_t capacity = map.record_capacity;
  while (capacity < needed) capacity = _double_capacity(capacity);
  map.records = _resize(map.records, capacity, sizeof(U32MapRecord));
  memset(map.records + map.record_capacity, 0,
         (capacity - map.record_capacity) * sizeof(U32MapRecord));
  map.record_capacity = capacity;
}
#pragma clang attribute pop

static void U32Map._reserve_pool(U32Map map, uint32_t needed) {
  if (needed <= map.pool_capacity) return;
  uint32_t capacity = map.pool_capacity ? map.pool_capacity : 2;
  while (capacity < needed) capacity = _double_capacity(capacity);
  map.pool = _resize(map.pool, capacity, sizeof(uint32_t));
  map.pool_capacity = capacity;
}

static void U32Map._save_record(U32Map map, uint32_t index) {
  map._reserve_pool(map.pool_length + 1);
  map.pool[map.pool_length++] = index;
}

static uint32_t U32Map._store_record(
  U32Map map, uint32_t key, uint32_t value, uint32_t index) {
  if (index) U32_MAP_PROFILE_ADD(reused_records, 1);
  else {
    if (map.pool_length) {
      U32_MAP_PROFILE_ADD(reused_records, 1);
      index = map.pool[--map.pool_length];
    }
    else {
      U32_MAP_PROFILE_ADD(new_records, 1);
      if (map.record_length == UINT32_MAX) _fail();
      if (map.record_length == map.record_capacity)
        map._grow_records(map.record_length + 1);
      index = map.record_length++;
    }
  }
  map.records[index] = (U32MapRecord) { .key = key, .value = value };
  map.used++;
  return index;
}

static U32MapSlot *U32Map._find(U32Map map, uint32_t key, uint32_t hash) {
  uint32_t start = hash & map.mask;
  U32MapRecord *records = map.records;
  for (uint32_t psl = 0; psl < map.capacity; psl++) {
    uint32_t index = (start + psl) & map.mask;
    U32MapSlot *slot = map.slots + index;
    if (!slot.hash) return NULL;
    if (slot.hash == hash && records[slot.index].key == key) return slot;
    uint32_t stored_start = slot.hash & map.mask;
    uint32_t stored_psl = (map.capacity + index - stored_start) & map.mask;
    if (stored_psl < psl) return NULL;
  }
  return NULL;
}

static void U32Map._reinsert(
  U32Map map, U32MapSlot displaced, uint32_t initial_psl) {
  uint32_t start = displaced.hash & map.mask;
  for (uint32_t psl = initial_psl; psl < map.capacity; psl++) {
    U32_MAP_PROFILE_ADD(reinsert_probes, 1);
    U32_MAP_PROFILE_MAX(max_reinsert_probe, psl + 1);
    uint32_t index = (start + psl) & map.mask;
    U32MapSlot *slot = map.slots + index;
    if (!slot.hash) {
      if (slot.index && slot.index != displaced.index)
        map._save_record(slot.index);
      *slot = displaced;
      return;
    }
    uint32_t stored_start = slot.hash & map.mask;
    uint32_t stored_psl = (map.capacity + index - stored_start) & map.mask;
    if (stored_psl < psl) {
      U32_MAP_PROFILE_ADD(reinsert_swaps, 1);
      U32MapSlot swap = *slot; *slot = displaced; displaced = swap;
      start = stored_start;
      psl = stored_psl;
    }
  }
  _fail();
}

static void U32Map._expand(U32Map map) {
  U32_MAP_PROFILE_ADD(expansions, 1);
  U32_MAP_PROFILE_EXPAND_BEGIN();
  uint32_t old_capacity = map.capacity;
  uint32_t capacity = _double_capacity(old_capacity);
  U32MapSlot *old_slots = map.slots;
  U32MapSlot *slots = _allocate(capacity, sizeof(U32MapSlot));
  memset(slots, 0, capacity * sizeof(U32MapSlot));

  map.slots = slots;
  map.capacity = capacity;
  map.mask = capacity - 1;
  for (uint32_t i = 0; i < old_capacity; i++) {
    if (old_slots[i].hash) {
      U32_MAP_PROFILE_ADD(expansion_records, 1);
      map._reinsert(old_slots[i], 0);
    }
    else if (old_slots[i].index) map._save_record(old_slots[i].index);
  }
  U32_MAP_PROFILE_EXPAND_END();
  free(old_slots);
}

/* Keep allocation and displacement out of the common existing-key path. */
#pragma clang attribute push(__attribute__((noinline)), apply_to=function)
static U32MapItr U32Map._insert_hashed(
  U32Map map, uint32_t key, uint32_t hash, uint32_t initial, int *inserted,
  uint32_t index, uint32_t stored_psl) {
  if ($u32.unlikely(map._would_exceed_max_load())) {
    map._expand();
    return map.get_or_insert_hashed(key, (uint64_t) hash, initial, inserted);
  }

  U32MapSlot *slot = map.slots + index;
  if (!slot.hash) {
    U32_MAP_PROFILE_ADD(empty_insertions, 1);
    uint32_t record = map._store_record(key, initial, slot.index);
    *slot = (U32MapSlot) { .hash = hash, .index = record };
  }
  else {
    U32_MAP_PROFILE_ADD(robin_hood_insertions, 1);
    uint32_t record = map._store_record(key, initial, 0);
    U32MapSlot displaced = *slot;
    *slot = (U32MapSlot) { .hash = hash, .index = record };
    map._reinsert(displaced, stored_psl + 1);
  }

  *inserted = 1;
  return (U32MapItr) { .slot = index };
}
#pragma clang attribute pop

static U32Map U32Map.new(void) {
  U32Map map = _allocate(1, sizeof(struct U32Map));
  memset(map, 0, sizeof(struct U32Map));
  map.capacity = 2;
  map.mask = 1;
  map.slots = _allocate(map.capacity, sizeof(U32MapSlot));
  memset(map.slots, 0, map.capacity * sizeof(U32MapSlot));
  map.record_capacity = 2;
  map.records = _allocate(map.record_capacity, sizeof(U32MapRecord));
  memset(map.records, 0, map.record_capacity * sizeof(U32MapRecord));
  map.record_length = 1;
  return map;
}

static void U32Map.free(U32Map map) {
  if (!map) return;
  free(map.slots);
  free(map.records);
  free(map.pool);
  free(map);
}

static uint32_t U32Map.len(U32Map map) {
  return map ? map.used : 0;
}

static int U32Map.valid(U32Map map, U32MapItr itr) {
  return map && itr.slot < map.capacity && map.slots[itr.slot].hash;
}

/* Pointer access requires an iterator which is valid for this map. */
$u32.record_accessor(
  key, U32Map map, U32MapItr itr,
  &map.records[map.slots[itr.slot].index].key
);
$u32.record_accessor(
  value, U32Map map, U32MapItr itr,
  &map.records[map.slots[itr.slot].index].value
);

static U32MapItr U32Map.find_hashed(U32Map map, uint32_t key, uint64_t hash) {
  if (!map) return _invalid_itr();
  U32MapSlot *slot = map._find(key, _stored_hash(hash));
  return slot ? (U32MapItr) { .slot = (uint32_t) (slot - map.slots) } :
                _invalid_itr();
}

static U32MapItr U32Map.first(U32Map map) {
  if (!map) return _invalid_itr();
  for (uint32_t i = 0; i < map.capacity; i++)
    if (map.slots[i].hash) return (U32MapItr) { .slot = i };
  return _invalid_itr();
}

static U32MapItr U32Map.next(U32Map map, U32MapItr itr) {
  if (!map || itr.slot == UINT32_MAX) return _invalid_itr();
  for (uint32_t i = itr.slot + 1; i < map.capacity; i++)
    if (map.slots[i].hash) return (U32MapItr) { .slot = i };
  return _invalid_itr();
}

static U32MapItr U32Map.get_or_insert_hashed(
  U32Map map, uint32_t key, uint64_t supplied_hash, uint32_t initial,
  int *inserted) {
  if (!map || !inserted) _fail();
  U32_MAP_PROFILE_ADD(operations, 1);
  *inserted = 0;
  uint32_t hash = _stored_hash(supplied_hash), start = hash & map.mask;
  U32MapRecord *records = map.records;
  for (uint32_t psl = 0; psl < map.capacity; psl++) {
    U32_MAP_PROFILE_ADD(probes, 1);
    U32_MAP_PROFILE_MAX(max_probe, psl + 1);
    uint32_t index = (start + psl) & map.mask;
    U32MapSlot *slot = map.slots + index;
    if (slot.hash == hash) {
      U32_MAP_PROFILE_ADD(hash_matches, 1);
      if (records[slot.index].key == key) {
        U32_MAP_PROFILE_ADD(key_matches, 1);
        return (U32MapItr) { .slot = index };
      }
    }

    if (!slot.hash) {
      return map._insert_hashed(key, hash, initial, inserted, index, 0);
    }

    uint32_t stored_start = slot.hash & map.mask;
    uint32_t stored_psl = (map.capacity + index - stored_start) & map.mask;
    if (stored_psl < psl) {
      return map._insert_hashed(
        key, hash, initial, inserted, index, stored_psl
      );
    }
  }
  _fail();
  return _invalid_itr();
}

static void U32Map.erase_itr(U32Map map, U32MapItr itr) {
  if (!map.valid(itr)) _fail();
  U32_MAP_PROFILE_ADD(erase_calls, 1);
  uint32_t index = itr.slot;
  U32MapSlot *slot = map.slots + index;
  uint32_t record = slot.index;
  map.records[record] = (U32MapRecord) { 0 };
  slot.hash = 0;
  map.used--;

  while (1) {
    U32_MAP_PROFILE_ADD(erase_scan_steps, 1);
    uint32_t empty = index;
    index = (index + 1) & map.mask;
    U32MapSlot *next = map.slots + index;
    if (!next.hash || (next.hash & map.mask) == index) return;
    U32_MAP_PROFILE_ADD(erase_shifts, 1);
    U32MapSlot swap = map.slots[empty];
    map.slots[empty] = *next;
    *next = swap;
  }
}

static U32MapProfile U32Map.profile(void) {
  return _u32_map_profile;
}
