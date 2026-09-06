/*  list-hot-paths.x -- focused List operation timings */


#include <assert.h>
#include <stdint.h>
#include <sys/resource.h>
#include <time.h>

static uint64_t now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t) ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

static void result(const char *name, uint64_t elapsed, long operations) {
  printf("%s,%.3f\n", name, (double) elapsed / operations);
}

static Var increment(Var value) {
  return value.integer() + 1;
}

static int is_even(Var value) {
  return !(value.integer() & 1);
}

static List range_list(int count) {
  Array values = %[];
  for (int i = 0; i < count; i++) values.push(i);
  List result = values.list_free();
  return result;
}

static double map_average_psl(Map map) {
  if (!map.used) return 0.0;
  assert(map.hashes.block().width == sizeof(unsigned));
  unsigned *hashes = map.hashes;
  unsigned long total = 0;
  for (unsigned index = 0; index < map.capacity; index++) {
    if (!hashes[index]) continue;
    unsigned ideal = hashes[index] & map.mask;
    total += (index - ideal) & map.mask;
  }
  return (double) total / map.used;
}

int main(void) {
  int width = 2048;
  int traversal_repeats = 500;
  int index_repeats = 2000;
  int builder_repeats = 100;
  volatile unsigned long sink = 0;
  uint64_t start;
  List base = range_list(width), suffix = %(9001 9002 9003);

  printf("sizeof-list,%zu\n", sizeof(struct List));

  start = now_ns();
  List unique = NULL;
  int unique_count = 20000;
  for (int i = 0; i < unique_count; i++) unique = cons(1000000 + i, unique);
  result("cons-unique", now_ns() - start, unique_count);
  sink += unique.car().integer();

  start = now_ns();
  int hit_count = 200000;
  for (int i = 0; i < hit_count; i++) sink += (uintptr_t) cons(17, base);
  result("cons-repeated", now_ns() - start, hit_count);

  start = now_ns();
  for (int r = 0; r < traversal_repeats; r++) {
    List cur = base;
    while (cur) {
      sink += cur.car().integer();
      cur = cur.cdr();
    }
  }
  result("cdr-traversal", now_ns() - start, (long) traversal_repeats * width);

  start = now_ns();
  for (int i = 0; i < hit_count; i++) sink += base.hash();
  result("hash", now_ns() - start, hit_count);

  Map map = %{};
  Array keys = %[];
  int key_count = 2048;
  for (int i = 0; i < key_count; i++) {
    List key = %( $i ${base.nth_cdr(i & 1023)} );
    keys.push(key);
    map[key] = i + 1;
  }
  printf("map-average-psl,%.6f\n", map_average_psl(map));
  start = now_ns();
  for (int i = 0; i < hit_count; i++)
    sink += map[keys[i & (key_count - 1)]].integer();
  result("map-list-key-get", now_ns() - start, hit_count);

  start = now_ns();
  for (int i = 0; i < builder_repeats; i++)
    sink += base.head(1536).car().integer();
  result("head", now_ns() - start, builder_repeats);

  start = now_ns();
  for (int i = 0; i < index_repeats; i++)
    sink += base.tail(512).car().integer();
  result("tail", now_ns() - start, index_repeats);

  start = now_ns();
  for (int i = 0; i < index_repeats; i++)
    sink += base.getindex(-257).integer();
  result("negative-index", now_ns() - start, index_repeats);

  start = now_ns();
  for (int i = 0; i < builder_repeats; i++)
    sink += base.append(suffix).car().integer();
  result("append", now_ns() - start, builder_repeats);

  start = now_ns();
  for (int i = 0; i < builder_repeats; i++)
    sink += base.map(increment).car().integer();
  result("map", now_ns() - start, builder_repeats);

  start = now_ns();
  for (int i = 0; i < builder_repeats; i++)
    sink += base.filter(is_even).car().integer();
  result("filter", now_ns() - start, builder_repeats);

  start = now_ns();
  for (int i = 0; i < builder_repeats; i++)
    sink += base.getslice(1900, 100, -3).car().integer();
  result("slice", now_ns() - start, builder_repeats);

  start = now_ns();
  for (int i = 0; i < builder_repeats; i++) {
    struct Iter storage;
    Iter iter = base.iter(&storage);
    sink += iter.list().car().integer();
  }
  result("iter-list", now_ns() - start, builder_repeats);

  struct rusage usage;
  getrusage(RUSAGE_SELF, &usage);
  printf("peak-rss,%ld\n", usage.ru_maxrss);
  keys.free();
  if (sink == 0) return 1;
  return 0;
}
