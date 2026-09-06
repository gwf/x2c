/*  scope-hot-paths.x -- focused Scope operation timings */


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
  int count = 1000000;
  volatile uintptr_t sink = 0;
  uint64_t start;

  Scope.retain();
  start = now_ns();
  for (int i = 0; i < count; i++) {
    void *ptr = Scope.malloc(24);
    sink ^= (uintptr_t) ptr;
    Scope.free(ptr);
  }
  result("malloc-free", now_ns() - start, count);
  Scope.release();

  start = now_ns();
  for (int i = 0; i < count; i++) {
    Scope.retain();
    Scope.release();
  }
  result("retain-release", now_ns() - start, count);

  Scope named = Scope.new();
  start = now_ns();
  for (int i = 0; i < count; i++) {
    Scope.push(&named);
    void *ptr = Scope.malloc(24);
    sink ^= (uintptr_t) ptr;
    Scope.free(ptr);
    Scope.pop();
  }
  result("push-malloc-free-pop", now_ns() - start, count);

  start = now_ns();
  for (int i = 0; i < count; i++) {
    void *ptr = Scope.malloc_in(&named, 24);
    sink ^= (uintptr_t) ptr;
    Scope.free(ptr);
  }
  result("malloc-in-free", now_ns() - start, count);
  Scope.destroy(named);

  Pool pool = Pool.retain_named(NULL, "pool-hot-path");
  start = now_ns();
  for (int i = 0; i < count; i++) {
    void *ptr = Pool.malloc(pool, 24);
    sink ^= (uintptr_t) ptr;
    Pool.free(pool, ptr);
  }
  result("pool-malloc-free", now_ns() - start, count);
  Pool.release(pool);

  int list_count = 200000;
  start = now_ns();
  for (int i = 0; i < list_count; i++) sink ^= (uintptr_t) cons(i, NULL);
  result("list-cons-miss", now_ns() - start, list_count);

  if (sink == UINTPTR_MAX) return 1;
  return 0;
}
