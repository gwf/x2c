#include <inttypes.h>

#include "common.c"

#include "u32-map-abi.h"

static void print_profile(void) {
  X2CU32MapProfile profile = x2c_u32_map_profile();
  printf(
    "UP\toperations=%" PRIu64 "\tprobes=%" PRIu64
    "\thash_matches=%" PRIu64 "\tkey_matches=%" PRIu64
    "\tmax_probe=%" PRIu64 "\tempty_insertions=%" PRIu64
    "\trobin_hood_insertions=%" PRIu64
    "\treinsert_probes=%" PRIu64 "\treinsert_swaps=%" PRIu64
    "\tmax_reinsert_probe=%" PRIu64 "\texpansions=%" PRIu64
    "\texpansion_records=%" PRIu64
    "\texpansion_reinsert_probes=%" PRIu64
    "\tnew_records=%" PRIu64 "\treused_records=%" PRIu64
    "\terase_calls=%" PRIu64 "\terase_scan_steps=%" PRIu64
    "\terase_shifts=%" PRIu64 "\n",
    profile.operations, profile.probes, profile.hash_matches,
    profile.key_matches, profile.max_probe, profile.empty_insertions,
    profile.robin_hood_insertions, profile.reinsert_probes,
    profile.reinsert_swaps, profile.max_reinsert_probe,
    profile.expansions, profile.expansion_records,
    profile.expansion_reinsert_probes, profile.new_records,
    profile.reused_records,
    profile.erase_calls, profile.erase_scan_steps, profile.erase_shifts
  );
}

void test_int(
  uint32_t N,
  uint32_t n0,
  int32_t is_del,
  uint32_t x0,
  uint32_t n_cp,
  udb_checkpoint_t *cp
) {
  uint32_t step = (N - n0) / (n_cp - 1);
  uint32_t i, n, j;
  uint64_t z = 0, x = x0;
  X2CU32Map map = x2c_u32_map_new();

  for (j = 0, i = 0, n = n0; j < n_cp; ++j, n += step) {
    for (; i < n; ++i) {
      uint64_t y = udb_splitmix64(&x);
      uint32_t key = udb_get_key(n, y);
#ifdef U32_MAP_SPLIT_RESULT
      if (is_del) {
        int inserted;
        X2CU32MapItr itr = x2c_u32_map_get_or_insert_hashed(
          map, key, udb_hash_fn(key), i, &inserted
        );
        if (inserted) ++z;
        else x2c_u32_map_erase_itr(map, itr);
      }
      else {
        X2CU32MapValueResult result =
          x2c_u32_map_get_or_insert_value_hashed(
            map, key, udb_hash_fn(key), 1
          );
        if (!result.inserted) ++*result.value;
        z += *result.value;
      }
#else
      int inserted;
      X2CU32MapItr itr = x2c_u32_map_get_or_insert_hashed(
        map, key, udb_hash_fn(key), is_del ? i : 1, &inserted
      );

      if (is_del) {
        if (inserted) ++z;
        else x2c_u32_map_erase_itr(map, itr);
      }
      else {
        uint32_t *value = x2c_u32_map_value(map, itr);
        if (!inserted) ++*value;
        z += *value;
      }
#endif
    }
    udb_measure(n, x2c_u32_map_len(map), z, &cp[j]);
  }

  print_profile();
  x2c_u32_map_free(map);
}
