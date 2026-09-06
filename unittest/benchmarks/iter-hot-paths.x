/*  iter-hot-paths.x -- focused iterator timings and retention metrics */


#include <stdint.h>
#include <sys/resource.h>
#include <time.h>

typedef struct {
  int current;
  int stop;
} BenchState;

/* Mirrors the private record in lib/map.x so the inline-scan lane below
   walks exactly the memory Map.try_next walks. */
struct BenchMapRecord { Var key, val; };

static uint64_t now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t) ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

static void result(const char *name, uint64_t elapsed, long operations) {
  printf("%s,%.3f\n", name, (double) elapsed / operations);
}

static int bench_next(Iter iter, Var *out) {
  BenchState *state = iter.obj.p64;
  if (state.current >= state.stop) return 0;
  *out = state.current;
  state.current += 1;
  return 1;
}

static Var increment(Var value) {
  return value.int() + 1;
}

static int is_even(Var value) {
  return !(value.int() & 1);
}

static List range_list(int count) {
  Array values = %[];
  for (int i = 0; i < count; i++) values.push(i);
  List result = values.list_free();
  return result;
}

static void benchmark_unzip(
  int count, int lagged, volatile unsigned long *sink) {
  struct Iter left_storage, right_storage, zip_storage, unzip_storage;
  UnzipShared shared;
  Iter left = range(0, count - 1, 1, &left_storage);
  Iter right = range(count, 2 * count - 1, 1, &right_storage);
  Iter zipped = Iter.zip(left, right, &zip_storage);
  Iter columns = Iter.unzip(zipped, &shared, &unzip_storage);
  Var left_var = columns.next(), right_var = columns.next();
  struct Iter unused_left, unused_right;
  Iter first = Var.iter(left_var, &unused_left);
  Iter second = Var.iter(right_var, &unused_right);
  Var value;
  uint64_t start = now_ns();
  if (lagged) {
    while (first.try_next(&value)) *sink += value.integer();
    printf("unzip-lagged-peak,%zu\n",
           shared.buffers[0].len() + shared.buffers[1].len());
    while (second.try_next(&value)) *sink += value.integer();
  }
  else {
    while (first.try_next(&value)) {
      *sink += value.integer();
      if (!second.try_next(&value)) abort();
      *sink += value.integer();
    }
  }
  result(lagged ? "unzip-lagged" : "unzip-lockstep", now_ns() - start, count);
  printf("%s-retained,%zu\n",
         lagged ? "unzip-lagged" : "unzip-lockstep",
         shared.buffers[0].len() + shared.buffers[1].len());
}

int main(void) {
  int count = 1000000, construct_count = 200000;
  volatile unsigned long sink = 0;
  uint64_t start;
  Var value;

  BenchState bench_state = {0, count};
  struct Iter bench_storage;
  Iter bench = Iter.init(&bench_storage,
                         (Var) { .p64 = &bench_state },
                         bench_next, (Var) { .u64 = 0 });
  start = now_ns();
  while (bench.try_next(&value)) sink += value.integer();
  result("try-next", now_ns() - start, count);

  start = now_ns();
  for (int i = 0; i < construct_count; i++) {
    struct Iter storage;
    sink ^= (uintptr_t) range(0, 31, 1, &storage);
  }
  result("range-construct-up", now_ns() - start, construct_count);

  start = now_ns();
  for (int i = 0; i < construct_count; i++) {
    struct Iter storage;
    sink ^= (uintptr_t) range(31, 0, -1, &storage);
  }
  result("range-construct-down", now_ns() - start, construct_count);

  start = now_ns();
  for (int i = 0; i < construct_count; i++) {
    struct Iter storage;
    sink ^= (uintptr_t) range(0, 62, 2, &storage);
  }
  result("range-construct-general", now_ns() - start, construct_count);

  struct Iter up_storage;
  Iter up = range(0, count - 1, 1, &up_storage);
  start = now_ns();
  while (up.try_next(&value)) sink += value.integer();
  result("range-up", now_ns() - start, count);

  struct Iter down_storage;
  Iter down = range(count - 1, 0, -1, &down_storage);
  start = now_ns();
  while (down.try_next(&value)) sink += value.integer();
  result("range-down", now_ns() - start, count);

  struct Iter general_storage;
  Iter general = range(0, 2 * count - 2, 2, &general_storage);
  start = now_ns();
  while (general.try_next(&value)) sink += value.integer();
  result("range-general", now_ns() - start, count);

  int width = 2048, repeats = count / width;
  List list = range_list(width);
  start = now_ns();
  for (int r = 0; r < repeats; r++) {
    struct Iter storage;
    Iter iter = list.iter(&storage);
    while (iter.try_next(&value)) sink += value.integer();
  }
  result("list-iter", now_ns() - start, (long) width * repeats);

  Array array = %[];
  for (int i = 0; i < width; i++) array.push(i);
  start = now_ns();
  for (int r = 0; r < repeats; r++) {
    struct Iter storage;
    Iter iter = array.iter(&storage);
    while (iter.try_next(&value)) sink += value.integer();
  }
  result("array-iter", now_ns() - start, (long) width * repeats);

  String text = "abcdefghijklmnopqrstuvwxyz";
  int text_repeats = count / text.len();
  start = now_ns();
  for (int r = 0; r < text_repeats; r++) {
    struct Iter storage;
    Iter iter = text.iter(&storage);
    while (iter.try_next(&value)) sink += value.integer();
  }
  result("string-iter", now_ns() - start, (long) text.len() * text_repeats);

  String word_text = %"alpha beta gamma delta epsilon zeta eta theta";
  int words_per_scan = 8, word_repeats = count / words_per_scan;
  Split words = word_text.words();
  start = now_ns();
  for (int r = 0; r < word_repeats; r++)
    foreach(String word, words)
      sink += word.len();
  result("split-foreach", now_ns() - start,
         (long) words_per_scan * word_repeats);

  // Handwritten control for the typed Split lane.
  start = now_ns();
  for (int r = 0; r < word_repeats; r++) {
    int cursor = 0;
    String word;
    while (words.try_next(&cursor, &word)) sink += word.len();
  }
  result("split-try-next", now_ns() - start,
         (long) words_per_scan * word_repeats);

  Map entries = %{};
  for (int i = 0; i < width; i++) entries.set(i, i + 1);
  start = now_ns();
  for (int r = 0; r < repeats; r++)
    foreach(Var (key, map_value), entries)
      sink += map_value.integer();
  result("map-foreach", now_ns() - start, (long) width * repeats);

  start = now_ns();
  for (int r = 0; r < repeats; r++) {
    unsigned cursor = 0;
    Var key, map_value;
    while (entries.try_next(&cursor, &key, &map_value))
      sink += map_value.integer();
  }
  result("map-try-next", now_ns() - start, (long) width * repeats);

  // The cost of the pair `Map.enumerate` yields, which the destructuring
  // foreach above no longer builds.
  start = now_ns();
  for (int r = 0; r < repeats; r++) {
    unsigned cursor = 0;
    Var key, map_value;
    while (entries.try_next(&cursor, &key, &map_value)) {
      List pair = %($key $map_value);
      sink += pair.cadr().integer();
    }
  }
  result("map-try-next-pair", now_ns() - start, (long) width * repeats);

  /* The floor for the current storage: the same slot scan with no call
     boundary, no cursor in memory, and nothing copied out. The distance from
     here to map-try-next is what the call costs. */
  start = now_ns();
  for (int r = 0; r < repeats; r++) {
    unsigned *hashes = entries.hashes;
    struct BenchMapRecord *records = entries.entries;
    unsigned capacity = entries.capacity;
    for (unsigned i = 0; i < capacity; i++)
      if (hashes[i]) sink += records[i].val.integer();
  }
  result("map-inline-scan", now_ns() - start, (long) width * repeats);

  struct Iter map_source_storage, map_storage;
  Iter map_source = range(0, count - 1, 1, &map_source_storage);
  Iter mapped = Iter.map(map_source, increment, &map_storage);
  start = now_ns();
  while (mapped.try_next(&value)) sink += value.integer();
  result("map-pipeline", now_ns() - start, count);

  struct Iter filter_source_storage, filter_storage;
  Iter filter_source = range(0, 2 * count - 1, 1, &filter_source_storage);
  Iter filtered = Iter.filter(filter_source, is_even, &filter_storage);
  start = now_ns();
  while (filtered.try_next(&value)) sink += value.integer();
  result("filter-pipeline", now_ns() - start, count);

  start = now_ns();
  struct Iter explicit_source_storage, explicit_map_storage,
              explicit_filter_storage;
  Iter explicit_source = range(0, 2 * count - 1, 1,
                               &explicit_source_storage);
  Iter explicit_map = explicit_source.map(increment, &explicit_map_storage);
  Iter explicit_filter = explicit_map.filter(is_even,
                                             &explicit_filter_storage);
  sink += explicit_filter.sum().integer();
  result("map-filter-explicit", now_ns() - start, count);

  start = now_ns();
  sink += range(0, 2 * count - 1, 1)
    .map(increment).filter(is_even).sum().integer();
  result("map-filter-implicit", now_ns() - start, count);

  Scope.retain();
  benchmark_unzip(10000, 0, &sink);
  Scope.release();
  Scope.retain();
  benchmark_unzip(10000, 1, &sink);
  Scope.release();

  struct rusage usage;
  getrusage(RUSAGE_SELF, &usage);
  printf("peak-rss,%ld\n", usage.ru_maxrss);
  array.free();
  if (sink == 0) return 1;
  return 0;
}
