/* flat-test.c -- udb3 driver for the metadata-array MapMetaIntInt specimen */

#include "common.c"

#include "x2c.h"
#include "flat-map.h"

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
  char add_text[] = "+";
  Symbol add = Symbol_new(add_text);

  Scope_retain();
  MapMetaIntInt map = MapMetaIntInt_new();

  for(j = 0, i = 0, n = n0; j < n_cp; ++j, n += step) {
    for(; i < n; ++i) {
      uint64_t y = udb_splitmix64(&x);
      int key = (int) udb_get_key(n, y);

      if(is_del) {
        int removed;
        if(!MapMetaIntInt_try_del(map, key, &removed)) {
          MapMetaIntInt_set(map, key, (int) i);
          ++z;
        }
      }
      else {
        z += (uint64_t) MapMetaIntInt_updateindex(map, key, add, 1);
      }
    }
    udb_measure(n, MapMetaIntInt_len(map), z, &cp[j]);
  }

  Scope_release();
}
