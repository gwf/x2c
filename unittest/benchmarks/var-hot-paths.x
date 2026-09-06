/*  var-hot-paths.x -- focused Var operation timings */


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

int main(void) {
  int count = 5000000;
  volatile unsigned long sink = 0;
  Var one = 123, same = 123, other = 124, wide = Var.new(<i48>, 123L);
  int value = 7;
  Var pointer = (void *) &value;
  uint64_t start;

  start = now_ns();
  for (int i = 0; i < count; i++) sink += one.tag();
  result("tag", now_ns() - start, count);

  start = now_ns();
  for (int i = 0; i < count; i++) sink += one.kind();
  result("kind", now_ns() - start, count);

  start = now_ns();
  for (int i = 0; i < count; i++) sink += one.integer();
  result("integer", now_ns() - start, count);

  start = now_ns();
  for (int i = 0; i < count; i++) sink += (uintptr_t) pointer.pointer();
  result("pointer", now_ns() - start, count);

  start = now_ns();
  for (int i = 0; i < count; i++) sink += one.hash();
  result("hash", now_ns() - start, count);

  start = now_ns();
  for (int i = 0; i < count; i++) sink += Var.equal(one, same);
  result("equal-hit", now_ns() - start, count);

  start = now_ns();
  for (int i = 0; i < count; i++) sink += Var.equal(one, other);
  result("equal-miss", now_ns() - start, count);

  start = now_ns();
  for (int i = 0; i < count; i++) sink += Var.compare(one, wide) + 1;
  result("compare-numeric", now_ns() - start, count);

  Scope.retain();
  Map map = %{};
  for (int i = 0; i < 1024; i++) map[i] = i + 1;
  start = now_ns();
  for (int i = 0; i < count; i++) sink += map[i & 1023].integer();
  result("map-get", now_ns() - start, count);
  Scope.release();

  if (sink == 0) return 1;
  return 0;
}
