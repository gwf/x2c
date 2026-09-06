#include "common.c"

#include "u32-map-abi.h"

void test_int(
  uint32_t N,
  uint32_t n0,
  int32_t is_del,
  uint32_t x0,
  uint32_t n_cp,
  udb_checkpoint_t *cp
)
{
  uint32_t step = (N - n0) / (n_cp - 1);
  uint32_t i, n, j;
  uint64_t z = 0, x = x0;
  X2CU32Map map = x2c_u32_map_new();

  for(j = 0, i = 0, n = n0; j < n_cp; ++j, n += step) {
    for(; i < n; ++i) {
      uint64_t y = udb_splitmix64(&x);
      uint32_t key = udb_get_key(n, y);
#ifdef U32_MAP_COMPACT_RESULT
      X2CU32MapResult result = x2c_u32_map_get_or_insert_hashed(
        map, key, udb_hash_fn(key), is_del ? i : 1
      );
      X2CU32MapItr itr = { .slot = result.slot };
      int inserted = x2c_u32_map_result_inserted(result);
      if(is_del) {
        if(inserted) ++z;
        else x2c_u32_map_erase_itr(map, itr);
      }
      else {
        uint32_t *value = x2c_u32_map_result_value(map, result);
        if(!inserted) ++*value;
        z += *value;
      }
#elif defined(U32_MAP_SPLIT_RESULT)
      if(is_del) {
        int inserted;
        X2CU32MapItr itr = x2c_u32_map_get_or_insert_hashed(
          map, key, udb_hash_fn(key), i, &inserted
        );
        if(inserted) ++z;
        else x2c_u32_map_erase_itr(map, itr);
      }
      else {
        X2CU32MapValueResult result =
          x2c_u32_map_get_or_insert_value_hashed(
            map, key, udb_hash_fn(key), 1
          );
        if(!result.inserted) ++*result.value;
        z += *result.value;
      }
#else
#ifdef U32_MAP_DIRECT_RESULT
      X2CU32MapResult result = x2c_u32_map_get_or_insert_hashed(
        map, key, udb_hash_fn(key), is_del ? i : 1
      );
      X2CU32MapItr itr = result.itr;
      int inserted = result.inserted;
#elif defined(U32_MAP_OUT_VALUE)
      int inserted;
      uint32_t *value;
      X2CU32MapItr itr = x2c_u32_map_get_or_insert_hashed(
        map, key, udb_hash_fn(key), is_del ? i : 1, &inserted,
        is_del ? NULL : &value
      );
#else
      int inserted;
      X2CU32MapItr itr = x2c_u32_map_get_or_insert_hashed(
        map, key, udb_hash_fn(key), is_del ? i : 1, &inserted
      );
#endif

      if(is_del) {
        if(inserted) ++z;
        else x2c_u32_map_erase_itr(map, itr);
      }
      else {
#ifdef U32_MAP_DIRECT_RESULT
        uint32_t *value = result.value;
#elif defined(U32_MAP_OUT_VALUE)
        (void)itr;
#else
        uint32_t *value = x2c_u32_map_value(map, itr);
#endif
        if(!inserted) ++*value;
        z += *value;
      }
#endif
    }
    udb_measure(n, x2c_u32_map_len(map), z, &cp[j]);
  }

  x2c_u32_map_free(map);
}
