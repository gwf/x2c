#include "u32-map-abi.h"
#include "khashl.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static uint64_t hash_key(uint32_t key) {
  uint64_t value = key;
  value ^= value >> 30;
  value *= UINT64_C(0xbf58476d1ce4e5b9);
  value ^= value >> 27;
  value *= UINT64_C(0x94d049bb133111eb);
  return value ^ (value >> 31);
}

KHASHL_MAP_INIT(
  KH_LOCAL, ReferenceMap, reference_map, uint32_t, uint32_t,
  hash_key, kh_eq_generic
)

static void check(int condition, const char *message) {
  if (condition) return;
  fprintf(stderr, "u32-map test failed: %s\n", message);
  exit(2);
}

static X2CU32MapItr put(
  X2CU32Map map, uint32_t key, uint64_t hash,
  uint32_t initial, int *inserted
) {
#ifdef U32_MAP_COMPACT_RESULT
  X2CU32MapResult result = x2c_u32_map_get_or_insert_hashed(
    map, key, hash, initial
  );
  *inserted = x2c_u32_map_result_inserted(result);
  X2CU32MapItr itr = { .slot = result.slot };
#elif defined(U32_MAP_DIRECT_RESULT)
  X2CU32MapResult result = x2c_u32_map_get_or_insert_hashed(
    map, key, hash, initial
  );
  *inserted = result.inserted;
  X2CU32MapItr itr = result.itr;
#elif defined(U32_MAP_OUT_VALUE)
  X2CU32MapItr itr = x2c_u32_map_get_or_insert_hashed(
    map, key, hash, initial, inserted, NULL
  );
#else
  X2CU32MapItr itr = x2c_u32_map_get_or_insert_hashed(
    map, key, hash, initial, inserted
  );
#endif
  check(x2c_u32_map_valid(map, itr), "insertion returned invalid iterator");
  return itr;
}

static void test_empty_and_replacement(void) {
  X2CU32Map map = x2c_u32_map_new();
  check(map != NULL, "new returned null");
  check(x2c_u32_map_len(map) == 0, "new map is not empty");
  check(!x2c_u32_map_valid(map, x2c_u32_map_first(map)),
        "empty map has a first iterator");
  check(!x2c_u32_map_valid(
          map, x2c_u32_map_find_hashed(map, 7, hash_key(7))),
        "empty lookup succeeded");

  int inserted;
  X2CU32MapItr itr = put(map, 7, hash_key(7), 11, &inserted);
  check(inserted && *x2c_u32_map_value(map, itr) == 11,
        "new value was not inserted");
  *x2c_u32_map_value(map, itr) = 19;
  X2CU32MapItr again = put(map, 7, hash_key(7), 99, &inserted);
  check(!inserted && *x2c_u32_map_value(map, again) == 19,
        "existing value was replaced by initial value");
  check(x2c_u32_map_len(map) == 1, "replacement changed length");
  x2c_u32_map_free(map);
}

static void test_collisions_growth_and_reuse(void) {
  X2CU32Map map = x2c_u32_map_new();
  int inserted;
  X2CU32MapItr first = put(map, 1, 1, 10, &inserted);
  uint32_t *first_record = x2c_u32_map_value(map, first);
  x2c_u32_map_erase_itr(map, first);
  X2CU32MapItr reused = put(map, 3, 1, 30, &inserted);
  check(inserted, "replacement key was not inserted");
  check(x2c_u32_map_value(map, reused) == first_record,
        "deleted record was not reused");

  for (uint32_t key = 4; key < 20000; key++) {
    uint64_t forced = (uint64_t) (key & 7) | UINT64_C(0x100000000);
    X2CU32MapItr itr = put(map, key, forced, key ^ 0x55aa, &inserted);
    check(inserted, "collision key already existed");
    check(*x2c_u32_map_value(map, itr) == (key ^ 0x55aa),
          "collision value mismatch");
  }
  check(x2c_u32_map_len(map) == 19997, "growth length mismatch");
  for (uint32_t key = 4; key < 20000; key += 3) {
    uint64_t forced = (uint64_t) (key & 7) | UINT64_C(0x100000000);
    X2CU32MapItr itr = x2c_u32_map_find_hashed(map, key, forced);
    check(x2c_u32_map_valid(map, itr), "collision lookup missed");
    x2c_u32_map_erase_itr(map, itr);
  }
  x2c_u32_map_free(map);
}

static void test_wraparound_backshift(void) {
  X2CU32Map map = x2c_u32_map_new();
  int inserted;

  for (uint32_t key = 100; key < 105; key++)
    put(map, key, hash_key(key), key, &inserted);
  for (uint32_t key = 100; key < 105; key++) {
    X2CU32MapItr itr = x2c_u32_map_find_hashed(map, key, hash_key(key));
    check(x2c_u32_map_valid(map, itr), "growth setup lookup missed");
    x2c_u32_map_erase_itr(map, itr);
  }

  X2CU32MapItr first = put(map, 1, 15, 10, &inserted);
  put(map, 2, 15, 20, &inserted);
  put(map, 3, 15, 30, &inserted);
  x2c_u32_map_erase_itr(map, first);

  X2CU32MapItr second = x2c_u32_map_find_hashed(map, 2, 15);
  X2CU32MapItr third = x2c_u32_map_find_hashed(map, 3, 15);
  check(x2c_u32_map_valid(map, second), "back-shift lost second key");
  check(x2c_u32_map_valid(map, third), "back-shift lost third key");
  check(*x2c_u32_map_value(map, second) == 20,
        "back-shift changed second value");
  check(*x2c_u32_map_value(map, third) == 30,
        "back-shift changed third value");

  X2CU32MapItr fourth = put(map, 4, 15, 40, &inserted);
  check(inserted && *x2c_u32_map_value(map, fourth) == 40,
        "wraparound tombstone was not reusable");
  check(x2c_u32_map_len(map) == 3, "wraparound length mismatch");
  x2c_u32_map_free(map);
}

static void compare_all(X2CU32Map map, ReferenceMap *reference) {
  check(x2c_u32_map_len(map) == kh_size(reference), "lengths differ");
  uint32_t visited = 0;
  for (X2CU32MapItr itr = x2c_u32_map_first(map);
       x2c_u32_map_valid(map, itr);
       itr = x2c_u32_map_next(map, itr)) {
    uint32_t key = *x2c_u32_map_key(map, itr);
    khint_t found = reference_map_get(reference, key);
    check(found != kh_end(reference), "iteration produced unknown key");
    check(*x2c_u32_map_value(map, itr) == kh_val(reference, found),
          "iteration value differs");
    visited++;
  }
  check(visited == kh_size(reference), "iteration count differs");
}

static void test_random_differential(void) {
  X2CU32Map map = x2c_u32_map_new();
  ReferenceMap *reference = reference_map_init();
  check(reference != NULL, "reference allocation failed");
  uint64_t state = UINT64_C(0x9e3779b97f4a7c15);

  for (uint32_t step = 0; step < 1000000; step++) {
    state ^= state >> 12;
    state ^= state << 25;
    state ^= state >> 27;
    uint32_t key = (uint32_t) (state % 16384);
    uint32_t operation = (uint32_t) (state >> 32) % 5;
    uint64_t hash = hash_key(key);
    khint_t found = reference_map_get(reference, key);

    if (operation < 3) {
      int inserted, absent;
      X2CU32MapItr itr = put(map, key, hash, step, &inserted);
      khint_t ref = reference_map_put(reference, key, &absent);
      check(ref != kh_end(reference), "reference insertion failed");
      check(inserted == absent, "insertion status differs");
      if (absent) kh_val(reference, ref) = step;
      else {
        (*x2c_u32_map_value(map, itr))++;
        kh_val(reference, ref)++;
      }
    }
    else if (operation == 3) {
      X2CU32MapItr itr = x2c_u32_map_find_hashed(map, key, hash);
      check(x2c_u32_map_valid(map, itr) == (found != kh_end(reference)),
            "lookup presence differs");
      if (found != kh_end(reference))
        check(*x2c_u32_map_value(map, itr) == kh_val(reference, found),
              "lookup value differs");
    }
    else if (found != kh_end(reference)) {
      X2CU32MapItr itr = x2c_u32_map_find_hashed(map, key, hash);
      check(x2c_u32_map_valid(map, itr), "erase lookup missed");
      x2c_u32_map_erase_itr(map, itr);
      reference_map_del(reference, found);
    }

    if ((step & 16383) == 0) compare_all(map, reference);
  }
  compare_all(map, reference);
  reference_map_destroy(reference);
  x2c_u32_map_free(map);
}

int main(void) {
  test_empty_and_replacement();
  test_collisions_growth_and_reuse();
  test_wraparound_backshift();
  test_random_differential();
  puts("u32-map tests passed");
  return 0;
}
