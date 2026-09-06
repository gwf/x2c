/*  string-hot-paths.x -- focused String operation timings */


#include <stdint.h>
#include <time.h>

static uint64_t now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t) ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

static void result(const char *name, uint64_t elapsed, int count) {
  printf("%s,%.3f\n", name, (double) elapsed / count);
}

static int keep_non_x(char ch) {
  return ch != 'x';
}

static int next_byte(char ch) {
  return ch + 1;
}

int main(void) {
  int fast_count = 5000000, build_count = 200000, callback_count = 5000;
  volatile unsigned long sink = 0;
  String canonical = %"canonical benchmark string";
  String left = %"compiler-", right = %"runtime";
  String dense = %"abxxabxxabxxabxxabxxabxxabxxabxx";
  String count_text = %"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  List words = %("alpha" "beta" "gamma" "delta");
  uint64_t start;

  start = now_ns();
  for (int i = 0; i < fast_count; i++) sink += canonical.hash();
  result("hash-canonical", now_ns() - start, fast_count);

  start = now_ns();
  for (int i = 0; i < build_count; i++)
    sink += String.new("canonical benchmark string").len();
  result("intern-duplicate", now_ns() - start, build_count);

  start = now_ns();
  for (int i = 0; i < build_count; i++) sink += count_text.count(%"aa");
  result("count-dense", now_ns() - start, build_count);

  start = now_ns();
  for (int i = 0; i < build_count; i++) sink += (left + right).len();
  result("concat", now_ns() - start, build_count);

  start = now_ns();
  for (int i = 0; i < build_count; i++) sink += %"-".join(words).len();
  result("join", now_ns() - start, build_count);

  start = now_ns();
  for (int i = 0; i < build_count; i++)
    sink += dense.replace(%"ab", %"wxyz").len();
  result("replace-dense", now_ns() - start, build_count);

  start = now_ns();
  for (int i = 0; i < build_count; i++)
    sink += dense.replace(%"ab", NULL).len();
  result("replace-delete", now_ns() - start, build_count);

  start = now_ns();
  for (int i = 0; i < callback_count; i++)
    sink += dense.filter(keep_non_x).len();
  result("filter", now_ns() - start, callback_count);

  start = now_ns();
  for (int i = 0; i < callback_count; i++)
    sink += dense.map(next_byte).len();
  result("map", now_ns() - start, callback_count);

  start = now_ns();
  for (int i = 0; i < build_count; i++)
    sink += String.printf("value-%d", i & 255).len();
  result("printf-small", now_ns() - start, build_count);

  return sink == 0;
}
