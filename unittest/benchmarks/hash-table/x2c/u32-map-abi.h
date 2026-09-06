#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *X2CU32Map;

typedef struct X2CU32MapItr {
  uint32_t slot;
#ifdef U32_MAP_RECORD_ITERATOR
  uint32_t record;
#endif
} X2CU32MapItr;

#ifdef U32_MAP_COMPACT_RESULT
typedef struct X2CU32MapResult {
  uint32_t slot, record_and_inserted;
} X2CU32MapResult;
#elif defined(U32_MAP_SPLIT_RESULT)
typedef struct X2CU32MapValueResult {
  uint32_t *value;
  int inserted;
} X2CU32MapValueResult;
#elif defined(U32_MAP_DIRECT_RESULT)
typedef struct X2CU32MapResult {
  uint32_t *value;
  X2CU32MapItr itr;
  int inserted;
} X2CU32MapResult;
#endif

typedef struct X2CU32MapProfile {
  uint64_t operations, probes, hash_matches, key_matches;
  uint64_t max_probe;
  uint64_t empty_insertions, robin_hood_insertions;
  uint64_t reinsert_probes, reinsert_swaps, max_reinsert_probe;
  uint64_t expansions, expansion_records, expansion_reinsert_probes;
  uint64_t new_records, reused_records;
  uint64_t erase_calls, erase_scan_steps, erase_shifts;
} X2CU32MapProfile;

X2CU32Map x2c_u32_map_new(void);
void x2c_u32_map_free(X2CU32Map map);
uint32_t x2c_u32_map_len(X2CU32Map map);
X2CU32MapItr x2c_u32_map_find_hashed(
  X2CU32Map map, uint32_t key, uint64_t hash
);
#ifdef U32_MAP_COMPACT_RESULT
X2CU32MapResult x2c_u32_map_get_or_insert_hashed(
  X2CU32Map map, uint32_t key, uint64_t hash, uint32_t initial
);
static inline int x2c_u32_map_result_inserted(X2CU32MapResult result) {
  return !!(result.record_and_inserted & UINT32_C(0x80000000));
}
uint32_t *x2c_u32_map_result_value(
  X2CU32Map map, X2CU32MapResult result
);
#elif defined(U32_MAP_SPLIT_RESULT)
X2CU32MapValueResult x2c_u32_map_get_or_insert_value_hashed(
  X2CU32Map map, uint32_t key, uint64_t hash, uint32_t initial
);
X2CU32MapItr x2c_u32_map_get_or_insert_hashed(
  X2CU32Map map, uint32_t key, uint64_t hash,
  uint32_t initial, int *inserted
);
#elif defined(U32_MAP_DIRECT_RESULT)
X2CU32MapResult x2c_u32_map_get_or_insert_hashed(
  X2CU32Map map, uint32_t key, uint64_t hash, uint32_t initial
);
#elif defined(U32_MAP_OUT_VALUE)
X2CU32MapItr x2c_u32_map_get_or_insert_hashed(
  X2CU32Map map, uint32_t key, uint64_t hash,
  uint32_t initial, int *inserted, uint32_t **value
);
#else
X2CU32MapItr x2c_u32_map_get_or_insert_hashed(
  X2CU32Map map, uint32_t key, uint64_t hash,
  uint32_t initial, int *inserted
);
#endif
void x2c_u32_map_erase_itr(X2CU32Map map, X2CU32MapItr itr);
X2CU32MapItr x2c_u32_map_first(X2CU32Map map);
X2CU32MapItr x2c_u32_map_next(X2CU32Map map, X2CU32MapItr itr);
int x2c_u32_map_valid(X2CU32Map map, X2CU32MapItr itr);
/* Pointer accessors require an iterator valid for this map. */
const uint32_t *x2c_u32_map_key(X2CU32Map map, X2CU32MapItr itr);
uint32_t *x2c_u32_map_value(X2CU32Map map, X2CU32MapItr itr);

X2CU32MapProfile x2c_u32_map_profile(void);

#ifdef __cplusplus
}
#endif
