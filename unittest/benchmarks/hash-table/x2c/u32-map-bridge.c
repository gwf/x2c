#ifndef X2C_U32_MAP_GENERATED
#define X2C_U32_MAP_GENERATED "u32-map.c"
#endif

#ifdef U32_MAP_PROFILE
#define U32_MAP_PROFILE_ADD(field, amount) \
  (_u32_map_profile.field += (amount))
#define U32_MAP_PROFILE_MAX(field, value) \
  do { \
    uint64_t candidate = (value); \
    if (_u32_map_profile.field < candidate) \
      _u32_map_profile.field = candidate; \
  } while (0)
#define U32_MAP_PROFILE_EXPAND_BEGIN() \
  uint64_t profile_reinsert_start = _u32_map_profile.reinsert_probes
#define U32_MAP_PROFILE_EXPAND_END() \
  (_u32_map_profile.expansion_reinsert_probes += \
   _u32_map_profile.reinsert_probes - profile_reinsert_start)
#else
#define U32_MAP_PROFILE_ADD(field, amount) ((void) 0)
#define U32_MAP_PROFILE_MAX(field, value) ((void) 0)
#define U32_MAP_PROFILE_EXPAND_BEGIN() ((void) 0)
#define U32_MAP_PROFILE_EXPAND_END() ((void) 0)
#endif

#include X2C_U32_MAP_GENERATED
#include "u32-map-abi.h"

static U32Map _map(X2CU32Map map) {
  return (U32Map) map;
}

static U32MapItr _itr(X2CU32MapItr itr) {
#ifdef U32_MAP_RECORD_ITERATOR
  return (U32MapItr) { .slot = itr.slot, .record = itr.record };
#else
  return (U32MapItr) { .slot = itr.slot };
#endif
}

static X2CU32MapItr _public_itr(U32MapItr itr) {
#ifdef U32_MAP_RECORD_ITERATOR
  return (X2CU32MapItr) { .slot = itr.slot, .record = itr.record };
#else
  return (X2CU32MapItr) { .slot = itr.slot };
#endif
}

X2CU32Map x2c_u32_map_new(void) {
  return (X2CU32Map) U32Map_new();
}

void x2c_u32_map_free(X2CU32Map map) {
  U32Map_free(_map(map));
}

uint32_t x2c_u32_map_len(X2CU32Map map) {
  return U32Map_len(_map(map));
}

X2CU32MapItr x2c_u32_map_find_hashed(
  X2CU32Map map, uint32_t key, uint64_t hash
) {
  return _public_itr(U32Map_find_hashed(_map(map), key, hash));
}

#ifdef U32_MAP_COMPACT_RESULT
X2CU32MapResult x2c_u32_map_get_or_insert_hashed(
  X2CU32Map map, uint32_t key, uint64_t hash, uint32_t initial
) {
  U32MapResult result = U32Map_get_or_insert_hashed(
    _map(map), key, hash, initial
  );
  return (X2CU32MapResult) {
    .slot = result.slot,
    .record_and_inserted = result.record_and_inserted,
  };
}

uint32_t *x2c_u32_map_result_value(
  X2CU32Map map, X2CU32MapResult result
) {
  return U32Map_result_value(_map(map), (U32MapResult) {
    .slot = result.slot,
    .record_and_inserted = result.record_and_inserted,
  });
}
#elif defined(U32_MAP_SPLIT_RESULT)
X2CU32MapValueResult x2c_u32_map_get_or_insert_value_hashed(
  X2CU32Map map, uint32_t key, uint64_t hash, uint32_t initial
) {
  U32MapValueResult result = U32Map_get_or_insert_value_hashed(
    _map(map), key, hash, initial
  );
  return (X2CU32MapValueResult) {
    .value = result.value,
    .inserted = result.inserted,
  };
}

X2CU32MapItr x2c_u32_map_get_or_insert_hashed(
  X2CU32Map map, uint32_t key, uint64_t hash,
  uint32_t initial, int *inserted
) {
  return _public_itr(
    U32Map_get_or_insert_hashed(_map(map), key, hash, initial, inserted)
  );
}
#elif defined(U32_MAP_DIRECT_RESULT)
X2CU32MapResult x2c_u32_map_get_or_insert_hashed(
  X2CU32Map map, uint32_t key, uint64_t hash, uint32_t initial
) {
  U32MapResult result = U32Map_get_or_insert_hashed(
    _map(map), key, hash, initial
  );
  return (X2CU32MapResult) {
    .value = result.value,
    .itr = _public_itr(result.itr),
    .inserted = result.inserted,
  };
}
#elif defined(U32_MAP_OUT_VALUE)
X2CU32MapItr x2c_u32_map_get_or_insert_hashed(
  X2CU32Map map, uint32_t key, uint64_t hash,
  uint32_t initial, int *inserted, uint32_t **value
) {
  return _public_itr(
    U32Map_get_or_insert_hashed(
      _map(map), key, hash, initial, inserted, value
    )
  );
}
#else
X2CU32MapItr x2c_u32_map_get_or_insert_hashed(
  X2CU32Map map, uint32_t key, uint64_t hash,
  uint32_t initial, int *inserted
) {
  return _public_itr(
    U32Map_get_or_insert_hashed(_map(map), key, hash, initial, inserted)
  );
}
#endif

void x2c_u32_map_erase_itr(X2CU32Map map, X2CU32MapItr itr) {
  U32Map_erase_itr(_map(map), _itr(itr));
}

X2CU32MapItr x2c_u32_map_first(X2CU32Map map) {
  return _public_itr(U32Map_first(_map(map)));
}

X2CU32MapItr x2c_u32_map_next(X2CU32Map map, X2CU32MapItr itr) {
  return _public_itr(U32Map_next(_map(map), _itr(itr)));
}

int x2c_u32_map_valid(X2CU32Map map, X2CU32MapItr itr) {
  return U32Map_valid(_map(map), _itr(itr));
}

const uint32_t *x2c_u32_map_key(X2CU32Map map, X2CU32MapItr itr) {
  return U32Map_key(_map(map), _itr(itr));
}

uint32_t *x2c_u32_map_value(X2CU32Map map, X2CU32MapItr itr) {
  return U32Map_value(_map(map), _itr(itr));
}

X2CU32MapProfile x2c_u32_map_profile(void) {
  U32MapProfile profile = U32Map_profile();
  return (X2CU32MapProfile) {
    .operations = profile.operations,
    .probes = profile.probes,
    .hash_matches = profile.hash_matches,
    .key_matches = profile.key_matches,
    .max_probe = profile.max_probe,
    .empty_insertions = profile.empty_insertions,
    .robin_hood_insertions = profile.robin_hood_insertions,
    .reinsert_probes = profile.reinsert_probes,
    .reinsert_swaps = profile.reinsert_swaps,
    .max_reinsert_probe = profile.max_reinsert_probe,
    .expansions = profile.expansions,
    .expansion_records = profile.expansion_records,
    .expansion_reinsert_probes = profile.expansion_reinsert_probes,
    .new_records = profile.new_records,
    .reused_records = profile.reused_records,
    .erase_calls = profile.erase_calls,
    .erase_scan_steps = profile.erase_scan_steps,
    .erase_shifts = profile.erase_shifts,
  };
}
